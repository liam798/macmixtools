import Foundation
import WebKit
import AppKit

final class TerminalWebViewSession: NSObject, WKScriptMessageHandler, WKNavigationDelegate, TerminalOutputSink {
    let webView: WKWebView

    private weak var runner: (any TerminalRunner)?
    private var isLoaded = false
    private var pendingFocus = false
    private var pendingWritesB64: [String] = []
    private var flushScheduled = false
    private var inputLineBuffer = ""
    private var outputLineBuffer = ""
    private var outputLogBytes: Int = 0
    private let outputLogLimit: Int = 1024 * 64 // 64 KB per session to avoid log spam
    private let markerStart = "__SSHTOOLS_PWD__"
    private let markerEnd = "__END__"

    override init() {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        let wv = FocusableWKWebView(frame: .zero, configuration: config)
        // Keep background controlled by the HTML/CSS; avoid AppKit default white.
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsMagnification = false
        self.webView = wv
        super.init()
        contentController.add(self, name: "sshTerm")
        wv.navigationDelegate = self
    }

    func attach(runner: any TerminalRunner) {
        self.runner = runner
    }

    func loadTerminal(url: URL, resourceRoot: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: resourceRoot)
    }

    func loadHTML(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    func writeToTerminal(_ data: Data) {
        logOutput(data)
        let cleaned = processMarkers(in: data)
        let b64 = cleaned.base64EncodedString()
        pendingWritesB64.append(b64)
        scheduleFlush()
    }

    func focus() {
        let delays: [TimeInterval] = [0, 0.05, 0.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let view = self?.webView else { return }
                view.window?.makeFirstResponder(view)
                _ = view.becomeFirstResponder()
                view.evaluateJavaScript("window.sshToolsFocus && window.sshToolsFocus(); if(window.term && window.term.scrollToBottom){window.term.scrollToBottom();} if(window.term && window.term.focus){window.term.focus();}", completionHandler: nil)
            }
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushScheduled = false
            self?.flushIfReady()
        }
    }

    private func flushIfReady() {
        guard isLoaded else { return }
        guard !pendingWritesB64.isEmpty else { return }

        let batch = pendingWritesB64
        pendingWritesB64.removeAll()

        if let jsonData = try? JSONSerialization.data(withJSONObject: batch, options: []),
           let json = String(data: jsonData, encoding: .utf8)
        {
            webView.evaluateJavaScript("window.sshToolsWriteBatchBase64(\(json))", completionHandler: nil)
        } else {
            for b64 in batch {
                webView.evaluateJavaScript("window.sshToolsWriteBase64('\(b64)')", completionHandler: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        flushIfReady()
        webView.evaluateJavaScript("window.sshToolsFocus && window.sshToolsFocus()", completionHandler: nil)
        if pendingFocus {
            pendingFocus = false
            focus()
        }
        webView.evaluateJavaScript("typeof window.Terminal") { result, error in
            if let error {
                Logger.log("Terminal: JS probe failed: \(error.localizedDescription)", level: .error)
                return
            }
            Logger.log("Terminal: JS probe typeof Terminal = \(result ?? "nil")", level: .info)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.log("Terminal: webview didCommit", level: .debug)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.log("Terminal: webview didStartProvisionalNavigation", level: .debug)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.log("Terminal: web content process terminated", level: .error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        Logger.log("Terminal: webview provisional navigation failed: \(error.localizedDescription)", level: .error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        Logger.log("Terminal: webview navigation failed: \(error.localizedDescription)", level: .error)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "sshTerm" else { return }
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String
        else { return }

        switch type {
        case "input":
            guard let b64 = dict["b64"] as? String,
                  let data = Data(base64Encoded: b64)
            else { return }
            runner?.send(data: data)
            logInput(data)

        case "resize":
            let cols = dict["cols"] as? Int ?? 80
            let rows = dict["rows"] as? Int ?? 24
            runner?.resize(cols: cols, rows: rows)

        case "copy":
            guard let text = dict["text"] as? String, !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)

        case "pasteRequest":
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            guard !text.isEmpty else { return }
            if let data = text.data(using: .utf8) {
                runner?.send(data: data)
            }

        case "cwd":
            guard let raw = dict["data"] as? String else { return }
            let cleaned = Self.cleanDirectoryFromOSC7(raw)
            guard !cleaned.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let runner = self?.runner else { return }
                if let sshRunner = runner as? SSHRunner {
                    sshRunner.updateCurrentPathFromOSC7(cleaned)
                } else if runner.currentPath != cleaned {
                    runner.currentPath = cleaned
                }
            }

        case "ready":
            Logger.log("Terminal: xterm.js ready", level: .info)
            DispatchQueue.main.async { [weak self] in
                self?.runner?.notifyTerminalReady()
                if self?.pendingFocus == true {
                    self?.pendingFocus = false
                    self?.focus()
                }
            }

        case "jsError":
            if let msg = dict["message"] as? String {
                Logger.log("Terminal: xterm.js error: \(msg)", level: .error)
            } else {
                Logger.log("Terminal: xterm.js error", level: .error)
            }

        default:
            break
        }
    }

    private func processMarkers(in data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8),
              let runner
        else { return data }

        var cleaned = text
        var searchStart = cleaned.startIndex
        var pathFound = false

        while let rangeStart = cleaned.range(of: markerStart, range: searchStart..<cleaned.endIndex),
              let rangeEnd = cleaned.range(of: markerEnd, range: rangeStart.upperBound..<cleaned.endIndex) {
            let pathRange = rangeStart.upperBound..<rangeEnd.lowerBound
            let path = String(cleaned[pathRange])
            if !path.isEmpty {
                DispatchQueue.main.async {
                    runner.currentPath = path
                    if let sshRunner = runner as? SSHRunner {
                        sshRunner.finishRestoringPathIfNeeded()
                    }
                }
                pathFound = true
            }
            cleaned.removeSubrange(rangeStart.lowerBound..<rangeEnd.upperBound)
            searchStart = rangeStart.lowerBound
        }

        if pathFound, let cleanedData = cleaned.data(using: .utf8) {
            return cleanedData
        }
        return data
    }

    private static func cleanDirectoryFromOSC7(_ raw: String) -> String {
        var dir = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if dir.isEmpty { return "" }

        if dir.hasPrefix("file://") {
            let components = dir.components(separatedBy: "://")
            if components.count > 1 {
                let pathWithHost = components[1]
                if let firstSlashIndex = pathWithHost.firstIndex(of: "/") {
                    dir = String(pathWithHost[firstSlashIndex...])
                } else {
                    dir = "/"
                }
            }
        }

        if let decoded = dir.removingPercentEncoding {
            dir = decoded
        }

        if dir.isEmpty { return "/" }
        return dir
    }

    private func logInput(_ data: Data) {
        guard let fragment = String(data: data, encoding: .utf8) else { return }
        inputLineBuffer.append(fragment)

        // Split on CR/LF boundaries.
        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "\r"))
        let parts = inputLineBuffer.components(separatedBy: separators)
        guard !parts.isEmpty else { return }

        inputLineBuffer = parts.last ?? ""
        for line in parts.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            Logger.log("TERM INPUT: \(trimmed)", level: .info)
            if !containsControlChars(trimmed) && !trimmed.contains("\t") {
                maybeHandleCd(from: trimmed)
            }
        }
    }

    private func logOutput(_ data: Data) {
        guard outputLogBytes < outputLogLimit else { return }
        guard let fragment = String(data: data, encoding: .utf8) else { return }
        outputLineBuffer.append(fragment)

        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "\r"))
        let parts = outputLineBuffer.components(separatedBy: separators)
        outputLineBuffer = parts.last ?? ""

        for line in parts.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // To avoid flooding logs and changing state on output replay, we only log lines that look like prompts.
            if trimmed.contains("#") || trimmed.contains("$") {
                let payload = "TERM OUTPUT: \(trimmed)"
                outputLogBytes += payload.utf8.count
                if outputLogBytes <= outputLogLimit {
                    Logger.log(payload, level: .info)
                } else {
                    Logger.log("TERM OUTPUT: (truncated log limit reached)", level: .info)
                    break
                }
                let cleaned = sanitizeOutputLine(trimmed)
                if cleaned.contains(" cd ") || cleaned.hasSuffix(" cd") || cleaned.hasSuffix(" cd/") || cleaned.contains(" cd\t") {
                    maybeHandleCd(from: cleaned)
                }
            }
        }
    }

    /// Detect `cd <path>` commands from output lines and sync runner.currentPath for SFTP.
    private func maybeHandleCd(from line: String) {
        // Strip leading prompt chars (#, $, %, >, ▶) and check if the actual command starts with cd
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let promptDelims: [Character] = ["#", "$", "%", ">", "▶"]
        var commandPortion = trimmed
        for delim in promptDelims {
            if let idx = commandPortion.lastIndex(of: delim),
               commandPortion.index(after: idx) < commandPortion.endIndex {
                let tail = commandPortion[commandPortion.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    commandPortion = tail
                    break
                }
            }
        }

        let lower = commandPortion.lowercased()
        guard lower.hasPrefix("cd") else { return }
        let rawArg = commandPortion.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        let pathPart = normalizeCdArgument(rawArg)
        guard !pathPart.isEmpty else { return }

        let cmdString = pathPart.isEmpty ? "cd" : "cd \(pathPart)"
        if let sshRunner = runner as? SSHRunner, sshRunner.shouldSkipOutputCd(cmdString) {
            return
        }

        let resolved = resolvePath(pathPart, current: runner?.currentPath ?? "/")
        Logger.log("SFTP: parsed cd raw=\"\(rawArg)\" path=\"\(pathPart)\" resolved=\"\(resolved)\"", level: .info)
        DispatchQueue.main.async { [weak runner] in
            runner?.currentPath = resolved
            if let sshRunner = runner as? SSHRunner {
                sshRunner.finishRestoringPathIfNeeded()
            }
            NotificationCenter.default.post(name: .sshtoolsCurrentPathChanged, object: resolved)
        }
    }

    /// Best-effort resolution of cd targets relative to current path.
    private func resolvePath(_ raw: String, current: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return NSHomeDirectory()
        }
        if trimmed.hasPrefix("~") {
            let rest = String(trimmed.dropFirst())
            return (NSHomeDirectory() as NSString).appendingPathComponent(rest)
        }
        if trimmed.hasPrefix("/") {
            return NSString(string: trimmed).standardizingPath
        }
        // Relative path
        let base = current.isEmpty ? "/" : current
        let combined = (base as NSString).appendingPathComponent(trimmed)
        return NSString(string: combined).standardizingPath
    }

    /// Handle forms like "cd -- /path", "cd '/path'", "cd \"../foo\"" etc.
    private func normalizeCdArgument(_ raw: String) -> String {
        var arg = raw
        // Drop leading "--" (cd -- /path)
        if arg.hasPrefix("--") {
            arg = arg.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove surrounding quotes if present
        if (arg.hasPrefix("'") && arg.hasSuffix("'")) || (arg.hasPrefix("\"") && arg.hasSuffix("\"")) {
            arg = String(arg.dropFirst().dropLast())
        }
        return arg.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsControlChars(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .controlCharacters) != nil
    }

    private func stripANSI(_ text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*[A-Za-z]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    private func sanitizeOutputLine(_ text: String) -> String {
        let noAnsi = stripANSI(text)
        var out = ""
        for ch in noAnsi {
            if ch == "\u{8}" || ch == "\u{7f}" {
                if !out.isEmpty { out.removeLast() }
                continue
            }
            if ch == "\r" || ch == "\n" { continue }
            if ch.isASCII {
                let v = ch.unicodeScalars.first?.value ?? 0
                if v < 32 || v == 127 { continue }
            }
            out.append(ch)
        }
        return out
    }

}
