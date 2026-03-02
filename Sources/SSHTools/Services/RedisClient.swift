import Foundation
import RediStack
import NIO
import Logging

/// Redis Error Types
enum RedisError: Error {
    case connectionFailed
    case sendFailed
    case receiveFailed
    case errorResponse(String)
}

class RedisClient: ObservableObject {
    private struct RedisConfig: Equatable {
        let host: String
        let port: Int
        let password: String
        let db: Int
    }

    private var connection: RedisConnection?
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var lastConfig: RedisConfig?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let reconnectMaxDelay: TimeInterval = 30
    
    @Published var isConnected = false
    @Published var lastError: String?
    
    deinit {
        reconnectTask?.cancel()
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    func connect(host: String, port: String, password: String, db: Int, completion: @escaping (Bool) -> Void) {
        let portInt = Int(port) ?? 6379
        let cfg = RedisConfig(host: host, port: portInt, password: password, db: db)
        lastConfig = cfg
        reconnectAttempts = 0
        reconnectTask?.cancel()
        
        do {
            let config = try RedisConnection.Configuration(
                hostname: host,
                port: portInt,
                password: password.isEmpty ? nil : password,
                initialDatabase: db
            )
            
            // Connect
            RedisConnection.make(
                configuration: config,
                boundEventLoop: eventLoopGroup.next()
            ).whenComplete { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let conn):
                    self.connection = conn
                    self.reconnectAttempts = 0
                    
                    // Handle unexpected closures (e.g. network lost)
                    conn.onUnexpectedClosure = { [weak self] in
                        DispatchQueue.main.async {
                            self?.isConnected = false
                            self?.lastError = "Connection closed unexpectedly"
                        }
                        self?.scheduleReconnect()
                    }
                    
                    DispatchQueue.main.async {
                        self.isConnected = true
                        completion(true)
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        self.isConnected = false
                        completion(false)
                    }
                    self.scheduleReconnect()
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "Configuration error: \(error.localizedDescription)"
                completion(false)
            }
            scheduleReconnect()
        }
    }
    
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        if let conn = connection {
            conn.close().whenComplete { _ in
                // Connection closed gracefully
            }
        }
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    private func scheduleReconnect() {
        guard let cfg = lastConfig else { return }
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), reconnectMaxDelay)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await MainActor.run { self.lastError = "Reconnecting…" }
            self.connect(host: cfg.host, port: "\(cfg.port)", password: cfg.password, db: cfg.db) { _ in }
        }
    }
    
    // Map raw command args to RediStack
    func sendCommand(_ args: [String], completion: @escaping (Any?, Error?) -> Void) {
        guard let connection = connection else {
            completion(nil, RedisError.connectionFailed)
            scheduleReconnect()
            return
        }
        
        guard !args.isEmpty else { return }
        
        // Convert [String] to RESPValue
        let command = args[0]
        let arguments = args.dropFirst().map { RESPValue(from: $0) }
        
        // Send arbitrary command
        connection.send(command: command, with: arguments)
            .whenComplete { result in
                switch result {
                case .success(let respValue):
                    // Convert RESPValue to Any? (String, Int, Array, etc) for UI
                    let mapped = self.mapRESPValue(respValue)
                    completion(mapped, nil)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.isConnected = false
                    self.scheduleReconnect()
                    completion(nil, error)
                }
            }
    }
    
    // Helper to map RediStack.RESPValue to the format your UI expects
    private func mapRESPValue(_ value: RESPValue) -> Any? {
        switch value {
        case .simpleString(let buffer):
            return String(buffer: buffer)
        case .bulkString(let buffer):
            return buffer.map { String(buffer: $0) } ?? nil // Null bulk string
        case .integer(let int):
            return int
        case .array(let values):
            return values.map { mapRESPValue($0) }
        case .error(let err):
            // RediStack wraps error responses in .error
            return err.message
        case .null:
            return nil
        }
    }
}