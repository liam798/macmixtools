import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var service: SystemMonitorService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("System Monitor", systemImage: "cpu")
                    .font(.caption.bold())
                Spacer()
                Button(action: { service.stopMonitoring() }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            
            Group {
                MonitorRow(label: "Host", value: service.stats.hostname)
                MonitorRow(label: "OS", value: service.stats.osName)
                MonitorRow(label: "Kernel", value: "\(service.stats.kernel) (\(service.stats.arch))")
                MonitorRow(label: "CPU", value: service.stats.cpuModel)
                MonitorRow(label: "Uptime", value: service.stats.uptime)
            }
            
            Divider()
            
            Group {
                HStack {
                    Text("CPU")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: Double(service.stats.cpuUsage.replacingOccurrences(of: "%", with: "")) ?? 0, total: 100)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    Text(service.stats.cpuUsage)
                        .font(.caption2.monospaced())
                        .frame(width: 45, alignment: .trailing)
                }
                
                HStack {
                    Text("Mem")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: service.stats.memoryUsage)
                        .progressViewStyle(.linear)
                        .tint(.green)
                    Text(service.stats.memoryLabel.split(separator: "/").first ?? "-")
                        .font(.caption2.monospaced())
                        .frame(width: 45, alignment: .trailing)
                }
                
                HStack {
                    Text("Swap")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: service.stats.swapUsage)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                    Text(String(format: "%.0f%%", service.stats.swapUsage * 100))
                        .font(.caption2.monospaced())
                        .frame(width: 45, alignment: .trailing)
                }
                
                HStack {
                    Text("Disk /")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    // Disk usage string usually comes as "45%", convert to double
                    let diskVal = Double(service.stats.diskUsage.replacingOccurrences(of: "%", with: "")) ?? 0
                    ProgressView(value: diskVal, total: 100)
                        .progressViewStyle(.linear)
                        .tint(.purple)
                    Text(service.stats.diskUsage)
                        .font(.caption2.monospaced())
                        .frame(width: 45, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct MonitorRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
