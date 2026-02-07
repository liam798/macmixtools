import Foundation

/// Cache TerminalViewModel instances per connection to keep SSH sessions alive across tab switches.
final class TerminalViewModelStore {
    static let shared = TerminalViewModelStore()
    private var cache: [UUID: TerminalViewModel] = [:]
    private let lock = NSLock()

    private init() {}

    func viewModel(for connection: SSHConnection) -> TerminalViewModel {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[connection.id] {
            return existing
        }
        let vm = TerminalViewModel(connection: connection)
        cache[connection.id] = vm
        return vm
    }

    func remove(connectionID: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: connectionID)
    }
}
