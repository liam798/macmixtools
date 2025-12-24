import Foundation
import Citadel
import NIO
import Crypto

/// Manages SSH connections to enable reuse/multiplexing.
/// Prevents multiple TCP connections for the same host/port/user.
actor SSHConnectionManager {
    static let shared = SSHConnectionManager()
    
    private init() {}
    
    struct ConnectionKey: Hashable {
        let host: String
        let port: Int
        let username: String
    }
    
    private var clients: [ConnectionKey: SSHClient] = [:]
    
    func getClient(for connection: SSHConnection) async throws -> SSHClient {
        let port = Int(connection.port) ?? 22
        let key = ConnectionKey(host: connection.host, port: port, username: connection.username)
        
        if let existing = clients[key] {
            return existing
        }
        
        // Create new connection
        let client = try await createConnection(for: connection, port: port)
        
        // Re-check in case another task created it while we were awaiting
        if let raceClient = clients[key] {
            try? await client.close()
            return raceClient
        }
        
        clients[key] = client
        return client
    }
    
    private func createConnection(for connection: SSHConnection, port: Int) async throws -> SSHClient {
        var authMethod: SSHAuthenticationMethod = .passwordBased(username: connection.username, password: connection.password)
        
        if connection.useKey {
            let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
            
            if FileManager.default.fileExists(atPath: expandedKeyPath),
               let keyData = try? Data(contentsOf: URL(fileURLWithPath: expandedKeyPath)),
               var keyString = String(data: keyData, encoding: .utf8) {
                
                // Legacy PEM conversion logic
                if keyString.contains("BEGIN RSA PRIVATE KEY") || keyString.contains("BEGIN PRIVATE KEY") {
                    if let converted = SSHKeyUtils.convertToOpenSSHFormat(at: expandedKeyPath) {
                        keyString = converted
                    }
                }
                
                if let edKey = try? Curve25519.Signing.PrivateKey(sshEd25519: keyString) {
                    authMethod = .ed25519(username: connection.username, privateKey: edKey)
                } else if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: keyString) {
                    authMethod = .rsa(username: connection.username, privateKey: rsaKey)
                }
            }
        }
        
        return try await Citadel.SSHClient.connect(
            host: connection.host,
            port: port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(), // In a real app, should verify host keys
            reconnect: .never
        )
    }
    
    func removeClient(for connection: SSHConnection) {
        let port = Int(connection.port) ?? 22
        let key = ConnectionKey(host: connection.host, port: port, username: connection.username)
        if let client = clients[key] {
            // Close in background
            Task { try? await client.close() }
            clients.removeValue(forKey: key)
        }
    }
    
    func disconnectAll() async {
        let allClients = Array(clients.values)
        clients.removeAll()
        
        for client in allClients {
            try? await client.close()
        }
    }
}