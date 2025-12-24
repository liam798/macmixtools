import Foundation
import Combine
import Citadel
import NIO
import SwiftTerm
import AppKit
import Darwin
import Crypto

/// SSH Runner handling the connection via a Hybrid Approach:
/// 1. Terminal: Uses system /usr/bin/ssh via PTY for interactive terminal support (colors, vim).
/// 2. SFTP: Uses Citadel for native Swift-based file management.
class SSHRunner: ObservableObject, Cleanable {
    @Published var isConnected: Bool = false
    @Published var currentPath: String = "" {
        didSet {
            saveCurrentPath()
        }
    }
    
    private var connectionID: UUID?
    @Published var error: String? = nil
    
    // SFTP Client exposed for the SFTP view
    @Published var sftp: SFTPClient?
    
    // Reference to the SwiftTerm view to feed data into
    weak var terminalView: SwiftTerm.TerminalView?
    
    // Terminal Process Properties
    private var masterFD: Int32 = -1
    private var task: Process?
    private let readQueue = DispatchQueue(label: "com.sshtools.pty.read")
    private var readSource: DispatchSourceRead?
    
    // Citadel Client for SFTP
    private var citadelClient: Citadel.SSHClient?
    
    // Guard against multiple concurrent connection attempts
    private var isConnecting = false
    
    func connect(connection: SSHConnection) {
        guard !isConnecting else { return }
        isConnecting = true
        self.connectionID = connection.id
        
        // 1. Cleanup old state immediately and SYNCHRONOUSLY
        syncDisconnect()
        
        self.error = nil
        
        // Delay slightly to allow OS to release PTY resources
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 1. Start Terminal Process
            self.startTerminalProcess(connection: connection)
            
            // 2. Start Citadel for SFTP
            self.startCitadelSFTP(connection: connection)
            
            // 3. Restore last directory
            self.restoreLastDirectory(for: connection)
            
            self.isConnecting = false
        }
    }
    
    private func saveCurrentPath() {
        guard let id = connectionID, !currentPath.isEmpty else { return }
        UserDefaults.standard.set(currentPath, forKey: "LastDir_\(id.uuidString)")
    }
    
    private func restoreLastDirectory(for connection: SSHConnection) {
        if let lastDir = UserDefaults.standard.string(forKey: "LastDir_\(connection.id.uuidString)"), !lastDir.isEmpty {
            // Wait a bit for the shell to be ready, then send cd command
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Logger.log("SSH: Restoring directory to \(lastDir)", level: .info)
                self.sendRaw("cd \"\(lastDir)\"\r")
                self.sendRaw("clear\r")
            }
        }
    }
    
    private func startTerminalProcess(connection: SSHConnection) {
        Logger.log("SSH: Starting terminal process for \(connection.host)...", level: .info)
        do {
            Logger.log("SSH: Opening PTY...", level: .debug)
            let (master, slave, _) = try PTYHelper.open()
            self.masterFD = master
            setNonBlocking(master)
            
            Logger.log("SSH: Creating Process object...", level: .debug)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            
            // Robust port and host check
            let portStr = connection.port.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = portStr.allSatisfy(\.isNumber) && !portStr.isEmpty ? portStr : "22"
            
            var args = ["-p", port,
                        "-o", "ConnectTimeout=10",
                        "-t",
                        "\(connection.username)@\(connection.host)",
                        #"export LANG='en_US.UTF-8'; export LC_ALL='en_US.UTF-8'; export PROMPT_COMMAND='printf "\033]7;file://localhost$PWD\007"'; export PS1='[\u@\h \W] \$ '; stty erase ^?; exec $SHELL -l"#]
            
            if connection.useKey {
                let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
                args.insert(contentsOf: ["-i", expandedKeyPath], at: 2)
            }
            
            process.arguments = args
            Logger.log("SSH: Arguments: \(args.joined(separator: " "))", level: .debug)
            
            let slaveFileHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
            process.standardInput = slaveFileHandle
            process.standardOutput = slaveFileHandle
            process.standardError = slaveFileHandle
            
            process.terminationHandler = { [weak self] _ in
                Logger.log("SSH: Process terminated", level: .info)
                self?.cleanupTerminal()
            }
            
            Logger.log("SSH: Calling process.run()...", level: .debug)
            try process.run()
            self.task = process
            
            Logger.log("SSH: Closing slave FD...", level: .debug)
            close(slave) // Close slave in parent
            
            Logger.log("SSH: Initiating startReading()...", level: .debug)
            startReading()
            
            DispatchQueue.main.async {
                self.isConnected = true
                Logger.log("SSH: Terminal process started and connected successfully", level: .info)
            }
            
            // 2. Start Citadel for SFTP
            startCitadelSFTP(connection: connection)
        } catch {
            Logger.log("SSH: Terminal failed to start: \(error.localizedDescription)", level: .error)
            DispatchQueue.main.async {
                self.error = "Terminal error: \(error.localizedDescription)"
            }
        }
    }

    private func startCitadelSFTP(connection: SSHConnection) {
        Task { @MainActor in
            do {
                Logger.log("SSH: Requesting shared Citadel connection...", level: .info)
                
                // Use ConnectionManager for pooling
                let client = try await SSHConnectionManager.shared.getClient(for: connection)
                self.citadelClient = client
                
                // Open SFTP channel on the (potentially shared) connection
                self.sftp = try await client.openSFTP()
                
                Logger.log("SSH: Citadel SFTP channel opened successfully", level: .info)
            } catch {
                Logger.log("SSH: SFTP connection failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags != -1 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    private func startReading() {
        guard masterFD != -1 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        guard masterFD != -1 else { return }
        
        // Use a larger buffer for better throughput
        let bufferSize = 16384 
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        // Read ONCE per event. DispatchSource will trigger again if more data is available.
        // This prevents the background thread from hogging CPU and flooding the main thread.
        let bytesRead = read(masterFD, &buffer, bufferSize)
        
        if bytesRead > 0 {
            let chunk = Array(buffer.prefix(bytesRead))
            DispatchQueue.main.async { [weak self] in
                // Feed data to the terminal emulator
                self?.terminalView?.feed(byteArray: ArraySlice(chunk))
            }
        } else if bytesRead == 0 {
            // EOF
            Logger.log("SSH: PTY EOF reached", level: .info)
            cleanupTerminal()
        } else if bytesRead == -1 {
            let err = errno
            if err != EAGAIN && err != EWOULDBLOCK {
                Logger.log("SSH: PTY read error: \(err)", level: .error)
                cleanupTerminal()
            }
        }
    }

    private func cleanupTerminal() {
        readSource?.cancel()
        readSource = nil
        if masterFD != -1 {
            close(masterFD)
            masterFD = -1
        }
        task = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func send(data: Data) {
        guard masterFD != -1 else { return }
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = write(masterFD, baseAddress, ptr.count)
        }
    }
    
    func sendRaw(_ text: String) {
        if let data = text.data(using: .utf8) {
            send(data: data)
        }
    }
    
    func resize(cols: Int, rows: Int) {
        guard masterFD != -1 else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }
    
    /// Synchronous part of disconnection to ensure stability during reconnect
    private func syncDisconnect() {
        readSource?.cancel()
        readSource = nil
        
        if let task = self.task, task.isRunning {
            task.terminate()
        }
        self.task = nil
        
        if masterFD != -1 {
            close(masterFD)
            masterFD = -1
        }
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func disconnect() {
        syncDisconnect()
        
        // Asynchronous Citadel cleanup
        Task {
            try? await citadelClient?.close()
                        await MainActor.run {
                            self.citadelClient = nil
                            self.sftp = nil
                        }
                    }
                }
                
                        func cleanup() {
                            Logger.log("Cleaning up SSHRunner", level: .info)
                            disconnect()
                        }
                        
                        func executeCommand(_ command: String) async throws -> String {
                            guard let client = citadelClient else {
                                throw NSError(domain: "SSHRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
                            }
                            let outputBuffer = try await client.executeCommand(command)
                            return String(buffer: outputBuffer)
                        }
                        
                        func detectSystemInfo() async -> String {                            guard let client = citadelClient else { return "Unknown Linux" }
                            do {
                                // Try to read os-release
                                let outputBuffer = try await client.executeCommand("cat /etc/os-release")
                                let output = String(buffer: outputBuffer)
                                
                                // Extract PRETTY_NAME
                                var result = "Linux"
                                output.enumerateLines { line, _ in
                                    if line.starts(with: "PRETTY_NAME=") {
                                        result = line.replacingOccurrences(of: "PRETTY_NAME=", with: "")
                                            .replacingOccurrences(of: "\"", with: "")
                                    }
                                }
                                
                                // If os-release failed/empty, try uname
                                if result == "Linux" {
                                     let unameBuffer = try await client.executeCommand("uname -sr")
                                     let uname = String(buffer: unameBuffer)
                                     if !uname.isEmpty { result = uname.trimmingCharacters(in: .whitespacesAndNewlines) }
                                }
                                
                                Logger.log("SSH: Detected System Info: \(result)", level: .info)
                                return result
                            } catch {
                                Logger.log("SSH: Failed to detect system info: \(error)", level: .warning)
                                return "Unknown Linux"
                            }
                        }
                    }