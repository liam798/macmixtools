import Foundation

final class CommandSnippetStore {
    static let shared = CommandSnippetStore()

    private let maxItems = 40
    private let globalKey = "sshtools.snippets.command.global"

    private init() {}

    func recordCommand(_ command: String, connectionID: UUID?) {
        let normalized = normalize(command)
        guard !normalized.isEmpty else { return }
        guard normalized.count <= 240 else { return }
        let lower = normalized.lowercased()
        if lower.contains("password") || lower.contains("passwd") { return }

        if let connectionID {
            let connectionKey = key(for: connectionID)
            save(normalized, to: connectionKey)
        }
        save(normalized, to: globalKey)
    }

    func suggestions(for input: String, connectionID: UUID?, limit: Int = 6) -> [String] {
        let query = normalize(input).lowercased()
        guard !query.isEmpty else { return [] }

        var orderedKeys: [String] = []
        if let connectionID {
            orderedKeys.append(key(for: connectionID))
        }
        orderedKeys.append(globalKey)

        var seen = Set<String>()
        var results: [String] = []
        for storageKey in orderedKeys {
            for command in UserDefaults.standard.stringArray(forKey: storageKey) ?? [] {
                let lower = command.lowercased()
                if !lower.hasPrefix(query) { continue }
                if seen.contains(lower) { continue }
                seen.insert(lower)
                results.append(command)
                if results.count >= limit {
                    return results
                }
            }
        }
        return results
    }

    func allCommands(connectionID: UUID?, limit: Int = 80) -> [String] {
        var orderedKeys: [String] = []
        if let connectionID {
            orderedKeys.append(key(for: connectionID))
        }
        orderedKeys.append(globalKey)

        var seen = Set<String>()
        var results: [String] = []
        for storageKey in orderedKeys {
            for command in UserDefaults.standard.stringArray(forKey: storageKey) ?? [] {
                let lower = command.lowercased()
                if seen.contains(lower) { continue }
                seen.insert(lower)
                results.append(command)
                if results.count >= limit {
                    return results
                }
            }
        }
        return results
    }

    private func key(for connectionID: UUID) -> String {
        "sshtools.snippets.cd.\(connectionID.uuidString)"
    }

    private func save(_ command: String, to storageKey: String) {
        var items = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        items.removeAll { $0.caseInsensitiveCompare(command) == .orderedSame }
        items.insert(command, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        UserDefaults.standard.set(items, forKey: storageKey)
    }

    private func normalize(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
