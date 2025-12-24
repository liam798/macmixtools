import Foundation

enum SSHKeyUtils {
    /// Converts a legacy PEM private key to modern OpenSSH format using ssh-keygen.
    /// Uses a secure, isolated temporary directory with strict permissions.
    static func convertToOpenSSHFormat(at path: String) -> String? {
        // 1. Create a unique temporary directory
        let tempDirName = "sshtools_safe_" + UUID().uuidString
        let tempDirURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempDirName)
        
        do {
            // 2. Create directory with strict permissions (700 - only owner can read/write/execute)
            try FileManager.default.createDirectory(at: tempDirURL, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: [.posixPermissions: 0o700])
            
            // Ensure cleanup happens even if errors occur
            defer {
                try? FileManager.default.removeItem(at: tempDirURL)
            }
            
            let sourceURL = URL(fileURLWithPath: path)
            let tempKeyURL = tempDirURL.appendingPathComponent("id_key")
            
            // 3. Copy key file
            try FileManager.default.copyItem(at: sourceURL, to: tempKeyURL)
            
            // 4. Set strict permissions on the file itself (600 - only owner can read/write)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempKeyURL.path)
            
            // 5. Run ssh-keygen
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            // -p: Change passphrase
            // -N "": Set new passphrase to empty
            // -f: File path
            task.arguments = ["-p", "-N", "", "-f", tempKeyURL.path]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            
            try task.run()
            task.waitUntilExit()
            
            // 6. Read the converted content
            let converted = try String(contentsOf: tempKeyURL, encoding: .utf8)
            
            if converted.contains("BEGIN OPENSSH PRIVATE KEY") {
                return converted
            }
        } catch {
            Logger.log("SSHKeyUtils: Key conversion failed: \(error.localizedDescription)", level: .debug)
        }
        
        return nil
    }
}