import Foundation
import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct AvailableUpdate: Equatable {
        let version: String
        let releaseURL: String
        let downloadURL: String
        let releaseNotes: String?
    }

    private struct VersionDescriptor: Decodable {
        let latestVersion: String
        let downloadURL: String?
        let releaseNotes: String?
        let releasePage: String?
    }

    private enum UpdateError: LocalizedError {
        case invalidDownloadURL
        case invalidArchive
        case unsupportedRuntime
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDownloadURL:
                return "下载地址无效"
            case .invalidArchive:
                return "更新包解析失败"
            case .unsupportedRuntime:
                return "当前运行环境不支持自动替换，请使用安装包版本"
            case .commandFailed(let message):
                return message
            }
        }
    }

    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isInstallingUpdate = false

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdates(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let now = Date()

        if !force,
           let lastCheck = defaults.object(forKey: AppConstants.StorageKeys.lastUpdateCheck) as? Date,
           now.timeIntervalSince(lastCheck) < AppConstants.Update.minimumCheckInterval {
            return
        }
        defaults.set(now, forKey: AppConstants.StorageKeys.lastUpdateCheck)

        guard let request = buildDescriptorRequest() else {
            Logger.log("无法构建版本描述文件请求", level: .error)
            return
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.log("版本描述文件请求失败", level: .warning)
                return
            }

            let descriptor = try JSONDecoder().decode(VersionDescriptor.self, from: data)
            let latestVersion = sanitizeVersion(descriptor.latestVersion)

            guard isRemoteVersionNewer(latest: latestVersion) else {
                availableUpdate = nil
                return
            }

            let fallbackReleaseURL = "https://github.com/\(AppConstants.Update.repository)/releases/latest"
            let releaseURL = descriptor.releasePage ?? fallbackReleaseURL
            let downloadURL = descriptor.downloadURL ?? releaseURL
            let update = AvailableUpdate(
                version: latestVersion,
                releaseURL: releaseURL,
                downloadURL: downloadURL,
                releaseNotes: descriptor.releaseNotes
            )

            if availableUpdate?.version != update.version {
                ToastManager.shared.show(message: "发现新版本: v\(update.version)", type: .info)
            }
            availableUpdate = update
        } catch {
            Logger.log("检查更新失败: \(error.localizedDescription)", level: .warning)
        }
    }

    func presentUpdateAlert() {
        guard let update = availableUpdate else {
            let alert = NSAlert()
            alert.messageText = "当前已是最新版本"
            alert.informativeText = "无需更新。"
            alert.addButton(withTitle: "确定")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "发现新版本: v\(update.version)"
        if let notes = update.releaseNotes, !notes.isEmpty {
            alert.informativeText = notes
        } else {
            alert.informativeText = "点击“自动更新”将下载并替换当前应用。"
        }
        alert.addButton(withTitle: "自动更新")
        alert.addButton(withTitle: "浏览器下载")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await startAutomaticUpdate() }
        case .alertSecondButtonReturn:
            openURL(update.downloadURL, fallback: update.releaseURL)
        default:
            break
        }
    }

    private func startAutomaticUpdate() async {
        guard !isInstallingUpdate, let update = availableUpdate else { return }
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }

        do {
            guard let downloadURL = URL(string: update.downloadURL) else {
                throw UpdateError.invalidDownloadURL
            }

            ToastManager.shared.show(message: "正在下载 v\(update.version) 更新包...", type: .info)
            let archiveURL = try await downloadArchive(from: downloadURL)
            let extractedAppURL = try extractAppBundle(from: archiveURL)
            let installedAppURL = try replaceCurrentApp(with: extractedAppURL)

            availableUpdate = nil
            ToastManager.shared.show(message: "更新完成，正在重启应用", type: .success)
            relaunchAndTerminate(appURL: installedAppURL)
        } catch {
            let message = error.localizedDescription
            Logger.log("自动更新失败: \(message)", level: .error)
            ToastManager.shared.show(message: "自动更新失败：\(message)", type: .error)
            if let update = availableUpdate {
                showInstallFailedAlert(message: message, update: update)
            }
        }
    }

    private func showInstallFailedAlert(message: String, update: AvailableUpdate) {
        let alert = NSAlert()
        alert.messageText = "自动更新失败"
        alert.informativeText = "\(message)\n你可以改用浏览器下载后手动安装。"
        alert.addButton(withTitle: "浏览器下载")
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openURL(update.downloadURL, fallback: update.releaseURL)
        }
    }

    private func buildDescriptorRequest() -> URLRequest? {
        let path = "\(AppConstants.Update.rawContentBase)/\(AppConstants.Update.repository)/\(AppConstants.Update.descriptorBranch)/\(AppConstants.Update.descriptorPath)"
        guard let url = URL(string: path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("PrismShell/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func currentVersion() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return AppConstants.Update.fallbackVersion
    }

    private func sanitizeVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func isRemoteVersionNewer(latest: String) -> Bool {
        let current = sanitizeVersion(currentVersion())
        return compareVersion(latest, isGreaterThan: current)
    }

    private func compareVersion(_ lhs: String, isGreaterThan rhs: String) -> Bool {
        let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func downloadArchive(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateError.commandFailed("下载更新包失败")
        }

        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismShell-Update-\(UUID().uuidString)")
            .appendingPathExtension("zip")

        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
        return targetURL
    }

    private func extractAppBundle(from archiveURL: URL) throws -> URL {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismShell-Extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        try runProcess("/usr/bin/ditto", ["-x", "-k", archiveURL.path, extractDir.path])

        guard let appBundle = findFirstAppBundle(in: extractDir) else {
            throw UpdateError.invalidArchive
        }
        return appBundle
    }

    private func findFirstAppBundle(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        return nil
    }

    private func replaceCurrentApp(with downloadedAppURL: URL) throws -> URL {
        let currentAppURL = Bundle.main.bundleURL
        guard currentAppURL.pathExtension == "app" else {
            throw UpdateError.unsupportedRuntime
        }

        let parentPath = currentAppURL.deletingLastPathComponent().path
        if FileManager.default.isWritableFile(atPath: parentPath) {
            if FileManager.default.fileExists(atPath: currentAppURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    currentAppURL,
                    withItemAt: downloadedAppURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.copyItem(at: downloadedAppURL, to: currentAppURL)
            }
        } else {
            try replaceAppWithAdminPrivileges(source: downloadedAppURL, destination: currentAppURL)
        }
        return currentAppURL
    }

    private func replaceAppWithAdminPrivileges(source: URL, destination: URL) throws {
        let command = "/bin/rm -rf \(shellEscaped(destination.path)) && /bin/cp -R \(shellEscaped(source.path)) \(shellEscaped(destination.path))"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedCommand)\" with administrator privileges"
        try runProcess("/usr/bin/osascript", ["-e", appleScript])
    }

    private func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let stderr = Pipe()
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed(message?.isEmpty == false ? message! : "系统命令执行失败")
        }
    }

    private func relaunchAndTerminate(appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                ToastManager.shared.show(message: "重启失败：\(error.localizedDescription)", type: .error)
                return
            }
            NSApp.terminate(nil)
        }
    }

    private func openURL(_ preferredURLString: String, fallback fallbackURLString: String) {
        if let url = URL(string: preferredURLString) {
            NSWorkspace.shared.open(url)
            return
        }
        if let fallback = URL(string: fallbackURLString) {
            NSWorkspace.shared.open(fallback)
        }
    }
}
