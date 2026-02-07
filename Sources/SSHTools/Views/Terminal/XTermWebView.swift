import SwiftUI
import WebKit
import AppKit

final class FocusableWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

struct XTermWebView<Runner: TerminalRunner>: NSViewRepresentable {
    @ObservedObject var runner: Runner
    let tabID: UUID

    private static func locateTerminalHTML() -> (bundle: Bundle, htmlURL: URL)? {
        // 1) SwiftPM resource bundle (works when run via `swift run` or when the generated resource bundle is present).
        let spmBundle = Bundle.module
        if let url = spmBundle.url(forResource: "terminal", withExtension: "html") {
            return (spmBundle, url)
        }

        // 2) When packaged as a .app, SwiftPM resources are often copied as a nested bundle in `Contents/Resources`.
        //    build_app.sh copies `SSHTools_SSHTools.bundle`, so look for that in Bundle.main.
        if let nestedBundleURL = Bundle.main.url(forResource: "SSHTools_SSHTools", withExtension: "bundle"),
           let nestedBundle = Bundle(url: nestedBundleURL),
           let url = nestedBundle.url(forResource: "terminal", withExtension: "html")
        {
            return (nestedBundle, url)
        }

        // 3) Fallback: scan for any `*_SSHTools.bundle` in the app resources (debug/release names can vary).
        if let resourcesURL = Bundle.main.resourceURL,
           let candidates = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil),
           let match = candidates.first(where: { $0.pathExtension == "bundle" && $0.lastPathComponent.hasSuffix("_SSHTools.bundle") }),
           let nestedBundle = Bundle(url: match),
           let url = nestedBundle.url(forResource: "terminal", withExtension: "html")
        {
            return (nestedBundle, url)
        }

        return nil
    }

    func makeNSView(context: Context) -> WKWebView {
        let session = TerminalWebViewStore.shared.session(for: tabID) {
            TerminalWebViewSession()
        }
        let webView = session.webView
        session.attach(runner: runner)
        runner.terminalOutput = session

        if webView.url == nil {
            if let located = Self.locateTerminalHTML(),
               let resourceRoot = located.bundle.resourceURL
            {
                Logger.log("Terminal: loading terminal.html from bundle=\(located.bundle.bundlePath)", level: .info)
                Logger.log("Terminal: terminal.html url=\(located.htmlURL.path)", level: .info)
                session.loadTerminal(url: located.htmlURL, resourceRoot: resourceRoot)
            } else {
                Logger.log("Terminal: failed to locate terminal.html in Bundle.module or app resources", level: .error)
                let fallbackHTML = """
                <!doctype html><html><body style="background:#000;color:#9ef;font:12px Menlo,monospace;padding:12px;">
                Failed to locate terminal resources.
                <br/><br/>
                Expected to find either:
                <br/>- SwiftPM Bundle.module resources, or
                <br/>- Contents/Resources/SSHTools_SSHTools.bundle/terminal/terminal.html
                </body></html>
                """
                session.loadHTML(fallbackHTML)
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let session = TerminalWebViewStore.shared.session(for: tabID) {
            TerminalWebViewSession()
        }
        session.attach(runner: runner)
        runner.terminalOutput = session
        session.focus()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        // Keep session alive for this tab to preserve scrollback.
    }
}
