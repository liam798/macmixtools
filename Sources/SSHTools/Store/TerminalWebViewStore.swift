import Foundation
import WebKit

final class TerminalWebViewStore {
    static let shared = TerminalWebViewStore()
    private var cache: [UUID: TerminalWebViewSession] = [:]
    private let lock = NSLock()

    private init() {}

    func session(for tabID: UUID, make: () -> TerminalWebViewSession) -> TerminalWebViewSession {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[tabID] { return existing }
        let session = make()
        cache[tabID] = session
        return session
    }

    func remove(tabID: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: tabID)
    }
}
