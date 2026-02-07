import Foundation

final class LocalTerminalPathStore: ObservableObject {
    static let shared = LocalTerminalPathStore()

    @Published private(set) var paths: [UUID: String] = [:]

    func loadPersistedPath(for connectionID: UUID) {
        let key = "sshtools.local.lastCwd.\(connectionID.uuidString)"
        guard let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty
        else { return }
        updatePath(stored, for: connectionID)
    }

    func updatePath(_ path: String, for connectionID: UUID) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if paths[connectionID] != trimmed {
            paths[connectionID] = trimmed
        }
    }

    func path(for connectionID: UUID) -> String? {
        paths[connectionID]
    }

    func removePath(for connectionID: UUID) {
        paths[connectionID] = nil
    }
}
