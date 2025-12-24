import Foundation
import Combine
import Citadel

struct SystemStats {
    var osName: String = "-"
    var kernel: String = "-"
    var hostname: String = "-"
    var arch: String = "-"
    var cpuModel: String = "-"
    var cpuUsage: String = "0%"
    var memoryUsage: Double = 0.0
    var memoryLabel: String = "- / -"
    var swapUsage: Double = 0.0
    var diskUsage: String = "-"
    var uptime: String = "-"
}

class SystemMonitorService: ObservableObject {
    @Published var stats = SystemStats()
    @Published var isVisible = false
    
    private let runner: SSHRunner
    private var timer: Timer?
    private var isFetching = false
    
    init(runner: SSHRunner) {
        self.runner = runner
    }
    
    func startMonitoring() {
        guard timer == nil else { return }
        isVisible = true
        fetchStats() // Initial fetch
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchStats()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isVisible = false
    }
    
    func toggle() {
        if isVisible {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func fetchStats() {
        guard !isFetching else { return }
        isFetching = true
        
        Task {
            do {
                // Combined command for efficiency
                // Using standard tools available on most Linux distros
                let script = """
                echo "OS:$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
                echo "KERNEL:$(uname -r)"
                echo "ARCH:$(uname -m)"
                echo "HOSTNAME:$(hostname)"
                echo "CPU_MODEL:$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
                echo "MEM:$(free -m 2>/dev/null | grep Mem | awk '{print $2,$3}')"
                echo "SWAP:$(free -m 2>/dev/null | grep Swap | awk '{print $2,$3}')"
                echo "DISK:$(df -h / 2>/dev/null | tail -1 | awk '{print $5}')"
                echo "UPTIME:$(uptime -p 2>/dev/null)"
                echo "CPU_IDLE:$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $8}')"
                """
                
                let output = try await runner.executeCommand(script)
                
                await MainActor.run {
                    self.parseOutput(output)
                    self.isFetching = false
                }
            } catch {
                // print("Monitor fetch failed: \(error)") // Silence frequent errors if disconnected
                self.isFetching = false
            }
        }
    }
    
    private func parseOutput(_ output: String) {
        var newStats = self.stats
        
        output.enumerateLines { line, _ in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0]
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch key {
                case "OS": newStats.osName = value.isEmpty ? "Linux" : value
                case "KERNEL": newStats.kernel = value
                case "ARCH": newStats.arch = value
                case "HOSTNAME": newStats.hostname = value
                case "CPU_MODEL": newStats.cpuModel = value
                case "DISK": newStats.diskUsage = value
                case "UPTIME": newStats.uptime = value.replacingOccurrences(of: "up ", with: "")
                case "CPU_IDLE":
                    if let idle = Double(value) {
                        let usage = 100.0 - idle
                        newStats.cpuUsage = String(format: "%.1f%%", usage)
                    } else if let idle = Double(value.replacingOccurrences(of: ",", with: ".")) {
                         // Handle locales using comma
                        let usage = 100.0 - idle
                        newStats.cpuUsage = String(format: "%.1f%%", usage)
                    }
                case "MEM":
                    let memParts = value.split(separator: " ").compactMap { Double($0) }
                    if memParts.count == 2 {
                        let total = memParts[0]
                        let used = memParts[1]
                        if total > 0 {
                            newStats.memoryUsage = used / total
                            newStats.memoryLabel = "\(Int(used))M / \(Int(total))M"
                        }
                    }
                case "SWAP":
                    let swapParts = value.split(separator: " ").compactMap { Double($0) }
                    if swapParts.count == 2 {
                        let total = swapParts[0]
                        let used = swapParts[1]
                        if total > 0 {
                            newStats.swapUsage = used / total
                        }
                    }
                default: break
                }
            }
        }
        
        self.stats = newStats
    }
}
