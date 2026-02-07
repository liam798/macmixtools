import Foundation
import SwiftUI

/// Centralized manager for file upload and download tasks
class TransferManager: ObservableObject {
    static let shared = TransferManager()
    
    @Published var tasks: [TransferTask] = []
    @Published var isShowingTasks = false
    @Published var savedUploadTasks: [SavedUploadTask] = [] {
        didSet { saveSavedTasks() }
    }

    private let savedTasksKey = "sshtools.savedUploadTasks"
    private var controls: [UUID: TransferControl] = [:]
    private var retryHandlers: [UUID: @Sendable () -> Void] = [:]
    
    private init() {
        loadSavedTasks()
    }
    
    func addTask(_ task: TransferTask) {
        DispatchQueue.main.async {
            var seeded = task
            let now = Date()
            seeded.startTime = now
            seeded.lastUpdateTime = now
            self.tasks.insert(seeded, at: 0)
            self.isShowingTasks = true
        }
    }

    func registerControl(id: UUID, control: TransferControl) {
        controls[id] = control
    }

    func registerRetryHandler(id: UUID, handler: @escaping @Sendable () -> Void) {
        retryHandlers[id] = handler
    }
    
    func updateTask(id: UUID, progress: Double, transferredSize: Int64, status: DownloadStatus? = nil) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                let now = Date()
                let previousSize = self.tasks[index].transferredSize
                let elapsed = now.timeIntervalSince(self.tasks[index].lastUpdateTime)
                if elapsed > 0.05 {
                    let delta = max(transferredSize - previousSize, 0)
                    self.tasks[index].speedBytesPerSec = Double(delta) / elapsed
                }
                self.tasks[index].lastUpdateTime = now
                self.tasks[index].progress = progress
                self.tasks[index].transferredSize = transferredSize
                if let status = status {
                    self.tasks[index].status = status
                } else if self.tasks[index].status == .queuing {
                    self.tasks[index].status = .transferring
                }
            }
        }
    }
    
    func completeTask(id: UUID) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .completed
                self.tasks[index].progress = 1.0
                self.tasks[index].speedBytesPerSec = 0
            }
        }
    }
    
    func failTask(id: UUID, message: String) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                let hint = self.failureHint(for: message)
                let fullMessage = hint.isEmpty ? message : "\(message) · \(hint)"
                self.tasks[index].status = .failed(fullMessage)
                self.tasks[index].speedBytesPerSec = 0
            }
        }
    }

    func markCancelled(id: UUID) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .cancelled
                self.tasks[index].speedBytesPerSec = 0
            }
        }
    }

    func pauseTask(id: UUID) {
        if let control = controls[id] {
            Task { await control.setPaused(true) }
        }
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .paused
                self.tasks[index].speedBytesPerSec = 0
            }
        }
    }

    func resumeTask(id: UUID) {
        if let control = controls[id] {
            Task { await control.setPaused(false) }
        }
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .transferring
                self.tasks[index].lastUpdateTime = Date()
            }
        }
    }

    func cancelTask(id: UUID) {
        if let control = controls[id] {
            Task { await control.cancel() }
        }
        markCancelled(id: id)
    }

    func retryTask(id: UUID) {
        guard let handler = retryHandlers[id] else { return }
        handler()
        DispatchQueue.main.async {
            self.tasks.removeAll { $0.id == id }
        }
    }
    
    func clearCompleted() {
        tasks.removeAll { task in
            if case .completed = task.status { return true }
            if case .failed = task.status { return true }
            if case .cancelled = task.status { return true }
            return false
        }
    }

    func savedTasks(for connectionID: UUID) -> [SavedUploadTask] {
        savedUploadTasks.filter { $0.connectionID == connectionID }
    }

    func addSavedTask(_ task: SavedUploadTask) {
        savedUploadTasks.insert(task, at: 0)
    }

    func removeSavedTask(id: UUID) {
        savedUploadTasks.removeAll { $0.id == id }
    }

    private func loadSavedTasks() {
        guard let data = UserDefaults.standard.data(forKey: savedTasksKey),
              let decoded = try? JSONDecoder().decode([SavedUploadTask].self, from: data)
        else { return }
        savedUploadTasks = decoded
    }

    private func saveSavedTasks() {
        guard let encoded = try? JSONEncoder().encode(savedUploadTasks) else { return }
        UserDefaults.standard.set(encoded, forKey: savedTasksKey)
    }

    private func failureHint(for message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("permission") || lower.contains("denied") {
            return "权限不足"
        }
        if lower.contains("no such file") || lower.contains("not found") {
            return "路径不存在"
        }
        if lower.contains("timeout") {
            return "连接超时"
        }
        if lower.contains("connection") || lower.contains("closed") {
            return "连接中断"
        }
        if lower.contains("eof") {
            return "远端主动断开"
        }
        if lower.contains("sftp") && lower.contains("not") && lower.contains("connected") {
            return "SFTP 未连接"
        }
        return ""
    }
}

struct SavedUploadTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var connectionID: UUID
    var note: String
    var localPath: String
    var remoteDirectory: String
}

struct TransferListView: View {
    @ObservedObject var manager = TransferManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfer Tasks".localized)
                    .font(.headline)
                Spacer()
                Button("Clear Finished".localized) {
                    manager.clearCompleted()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            if manager.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("No active tasks".localized)
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.tasks) { task in
                        TransferTaskRow(task: task)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 350, height: 450)
        .background(DesignSystem.Colors.background)
    }
}

struct TransferTaskRow: View {
    let task: TransferTask
    @ObservedObject private var manager = TransferManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: task.type == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(task.type == .download ? .blue : .green)
                Text(task.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                statusIcon
            }
            
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .accentColor(progressColor)
            
            HStack {
                Text(sizeStringAndSpeed)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if task.status == .transferring || task.status == .paused {
                    transferControls
                } else if isFailed {
                    retryButton
                }
                Text(percentString)
                    .font(.caption2)
                    .monospacedDigit()
            }
            if case .failed(let message) = task.status {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .paused:
            Image(systemName: "pause.circle.fill").foregroundColor(.orange)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
        case .transferring:
            ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
        default:
            EmptyView()
        }
    }
    
    private var progressColor: Color {
        switch task.status {
        case .paused: return .orange
        case .cancelled: return .gray
        case .failed: return .red
        case .completed: return .green
        default: return .blue
        }
    }
    
    private var sizeString: String {
        let current = ByteCountFormatter.string(fromByteCount: task.transferredSize, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: task.totalSize, countStyle: .file)
        return "\(current) / \(total)"
    }

    private var speedString: String {
        guard task.status == .transferring, task.speedBytesPerSec > 0 else { return "--/s" }
        let speed = ByteCountFormatter.string(fromByteCount: Int64(task.speedBytesPerSec), countStyle: .file)
        return "\(speed)/s"
    }

    private var sizeStringAndSpeed: String {
        "\(sizeString) · \(speedString)"
    }

    private var isFailed: Bool {
        if case .failed = task.status { return true }
        return false
    }

    @ViewBuilder
    private var transferControls: some View {
        HStack(spacing: 6) {
            if task.status == .paused {
                controlButton(systemName: "play.fill", help: "Resume") {
                    manager.resumeTask(id: task.id)
                }
            } else {
                controlButton(systemName: "pause.fill", help: "Pause") {
                    manager.pauseTask(id: task.id)
                }
            }
            controlButton(systemName: "xmark", help: "Cancel") {
                manager.cancelTask(id: task.id)
            }
        }
    }

    private var retryButton: some View {
        controlButton(systemName: "arrow.clockwise", help: "Retry") {
            manager.retryTask(id: task.id)
        }
    }

    private func controlButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(4)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(help)
    }
    
    private var percentString: String {
        String(format: "%.0f%%", task.progress * 100)
    }
}

actor TransferControl {
    private var paused = false
    private var cancelled = false

    func setPaused(_ value: Bool) {
        paused = value
    }

    func cancel() {
        cancelled = true
    }

    func waitIfPaused() async throws {
        while paused {
            try await Task.sleep(nanoseconds: 120_000_000)
            if cancelled { throw CancellationError() }
        }
        if cancelled { throw CancellationError() }
    }
}
