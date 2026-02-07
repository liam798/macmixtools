import Foundation

final class SyncedSFTPViewModelStore {
    static let shared = SyncedSFTPViewModelStore()
    private var cache: [ObjectIdentifier: SyncedSFTPViewModel] = [:]
    private let lock = NSLock()

    private init() {}

    func viewModel(
        runner: SSHRunner,
        initialPath: String,
        onNavigate: @escaping (String) -> Void
    ) -> SyncedSFTPViewModel {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(runner)
        if let existing = cache[key] { return existing }
        let vm = SyncedSFTPViewModel(runner: runner, path: initialPath, onNavigate: onNavigate)
        cache[key] = vm
        return vm
    }

    func remove(runner: SSHRunner) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: ObjectIdentifier(runner))
    }
}
