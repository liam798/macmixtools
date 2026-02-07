import Foundation

struct SettingsSnapshot: Codable {
    var defaultDownloadPath: String
    var geminiApiKey: String
    var terminalBackgroundImagePath: String
    var terminalBackgroundColor: String
    var terminalFontSize: Double
    var terminalTheme: String
    var userTheme: String
    var sftpDownloadChunkMB: Int
    var enableLocalProxy: Bool
    var localProxyHost: String
    var localProxyPort: String
}

struct ConfigSnapshot: Codable {
    var version: Int
    var exportedAt: Date
    var connections: [SSHConnection]
    var groups: [ConnectionGroup]
    var authProfiles: [SSHAuthProfile]
    var settings: SettingsSnapshot
    var savedUploadTasks: [SavedUploadTask]
}

enum ConfigIOError: Error {
    case invalidData
}

enum ConfigIO {
    static func makeSnapshot(store: ConnectionsStore) -> ConfigSnapshot {
        let settings = SettingsManager.shared
        let auth = AuthProfileManager.shared
        let transfer = TransferManager.shared

        let settingsSnapshot = SettingsSnapshot(
            defaultDownloadPath: settings.defaultDownloadPath,
            geminiApiKey: settings.geminiApiKey,
            terminalBackgroundImagePath: settings.terminalBackgroundImagePath,
            terminalBackgroundColor: settings.terminalBackgroundColor,
            terminalFontSize: settings.terminalFontSize,
            terminalTheme: settings.terminalTheme.rawValue,
            userTheme: settings.userTheme.rawValue,
            sftpDownloadChunkMB: settings.sftpDownloadChunkMB,
            enableLocalProxy: settings.enableLocalProxy,
            localProxyHost: settings.localProxyHost,
            localProxyPort: settings.localProxyPort
        )

        return ConfigSnapshot(
            version: 1,
            exportedAt: Date(),
            connections: store.connections,
            groups: store.groups,
            authProfiles: auth.profiles,
            settings: settingsSnapshot,
            savedUploadTasks: transfer.savedUploadTasks
        )
    }

    static func applySnapshot(_ snapshot: ConfigSnapshot, to store: ConnectionsStore) {
        store.connections = snapshot.connections
        store.groups = snapshot.groups

        AuthProfileManager.shared.profiles = snapshot.authProfiles
        TransferManager.shared.savedUploadTasks = snapshot.savedUploadTasks

        let settings = SettingsManager.shared
        settings.defaultDownloadPath = snapshot.settings.defaultDownloadPath
        settings.geminiApiKey = snapshot.settings.geminiApiKey
        settings.terminalBackgroundImagePath = snapshot.settings.terminalBackgroundImagePath
        settings.terminalBackgroundColor = snapshot.settings.terminalBackgroundColor
        settings.terminalFontSize = snapshot.settings.terminalFontSize
        settings.terminalTheme = DesignSystem.TerminalTheme(rawValue: snapshot.settings.terminalTheme) ?? .standard
        settings.userTheme = AppTheme(rawValue: snapshot.settings.userTheme) ?? .system
        settings.sftpDownloadChunkMB = snapshot.settings.sftpDownloadChunkMB
        settings.enableLocalProxy = snapshot.settings.enableLocalProxy
        settings.localProxyHost = snapshot.settings.localProxyHost
        settings.localProxyPort = snapshot.settings.localProxyPort

        let localPaths = LocalTerminalPathStore.shared
        for connection in snapshot.connections where connection.type == .localTerminal {
            localPaths.loadPersistedPath(for: connection.id)
        }
    }

    static func exportToURL(_ url: URL, store: ConnectionsStore) throws {
        let snapshot = makeSnapshot(store: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url)
    }

    static func importFromURL(_ url: URL) throws -> ConfigSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfigSnapshot.self, from: data)
    }
}
