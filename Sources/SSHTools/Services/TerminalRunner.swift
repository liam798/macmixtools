import Foundation

protocol TerminalRunner: AnyObject, ObservableObject {
    var terminalOutput: TerminalOutputSink? { get set }
    var currentPath: String { get set }
    var connectionID: UUID? { get }

    func send(data: Data)
    func resize(cols: Int, rows: Int)
    func notifyTerminalReady()
}
