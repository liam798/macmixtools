import Foundation
import Darwin

/// PTY 错误类型
enum PTYError: Error {
    case openFailed
    case grantFailed
    case unlockFailed
    case nameFailed
}

/// PTY（伪终端）辅助类
/// 用于创建主从终端对，实现交互式终端功能
class PTYHelper {
    /// 打开 PTY 并返回主从文件描述符和从设备路径
    /// - Returns: (master FD, slave FD, slave 设备路径)
    /// - Throws: PTYError 如果操作失败
    static func open() throws -> (master: Int32, slave: Int32, name: String) {
        Logger.log("PTY: Calling posix_openpt...", level: .debug)
        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        if masterFD == -1 { 
            Logger.log("PTY: posix_openpt failed", level: .error)
            throw PTYError.openFailed 
        }
        
        Logger.log("PTY: Calling grantpt...", level: .debug)
        if grantpt(masterFD) == -1 {
            Logger.log("PTY: grantpt failed", level: .error)
            close(masterFD)
            throw PTYError.grantFailed
        }
        
        Logger.log("PTY: Calling unlockpt...", level: .debug)
        if unlockpt(masterFD) == -1 {
            Logger.log("PTY: unlockpt failed", level: .error)
            close(masterFD)
            throw PTYError.unlockFailed
        }
        
        Logger.log("PTY: Getting slave name...", level: .debug)
        let namePtr = ptsname(masterFD)
        guard let namePtr = namePtr, let slavePath = String(cString: namePtr, encoding: .utf8) else {
            Logger.log("PTY: ptsname failed", level: .error)
            close(masterFD)
            throw PTYError.nameFailed
        }
        
        Logger.log("PTY: Opening slave at \(slavePath)...", level: .debug)
        let slaveFD = Darwin.open(slavePath, O_RDWR | O_NOCTTY)
        if slaveFD == -1 {
            Logger.log("PTY: Opening slave failed", level: .error)
            close(masterFD)
            throw PTYError.openFailed
        }
        
        Logger.log("PTY: Success. Master: \(masterFD), Slave: \(slaveFD)", level: .debug)
        return (masterFD, slaveFD, slavePath)
    }
}
