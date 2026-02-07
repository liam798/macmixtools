import SwiftUI
import AppKit

struct SavedUploadTasksView: View {
    let connectionID: UUID
    let runner: SSHRunner

    @ObservedObject private var manager = TransferManager.shared
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Uploads".localized)
                    .font(.headline)
                Spacer()
                Button(action: { isAdding = true }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(DesignSystem.Colors.surface)

            Divider()

            let tasks = manager.savedTasks(for: connectionID)
            if tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("No saved tasks".localized)
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        SavedUploadTaskRow(task: task, onUpload: { upload(task) }, onDelete: {
                            manager.removeSavedTask(id: task.id)
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 420)
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $isAdding) {
            SavedUploadTaskEditor(connectionID: connectionID) { task in
                manager.addSavedTask(task)
            }
        }
    }

    private func upload(_ task: SavedUploadTask) {
        guard let sftp = runner.sftp else {
            ToastManager.shared.show(message: "SFTP not connected".localized, type: .error)
            return
        }

        let localURL = URL(fileURLWithPath: task.localPath)
        if !FileManager.default.fileExists(atPath: localURL.path) {
            ToastManager.shared.show(message: "Local file not found".localized, type: .error)
            return
        }

        let remoteDirectory = task.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if remoteDirectory.isEmpty {
            ToastManager.shared.show(message: "Remote directory is empty".localized, type: .error)
            return
        }

        let remotePath: String
        if remoteDirectory.hasSuffix("/") {
            remotePath = remoteDirectory + localURL.lastPathComponent
        } else {
            remotePath = remoteDirectory + "/" + localURL.lastPathComponent
        }

        Task {
            do {
                try await SFTPService.shared.upload(sftp: sftp, localURL: localURL, remotePath: remotePath)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }
}

private struct SavedUploadTaskRow: View {
    let task: SavedUploadTask
    let onUpload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .foregroundColor(.blue)
                Text(task.note.isEmpty ? task.fileName : task.note)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button(action: onUpload) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }

            Text(task.localPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(task.remoteDirectory)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SavedUploadTaskEditor: View {
    let connectionID: UUID
    let onSave: (SavedUploadTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""
    @State private var localPath: String = ""
    @State private var remoteDirectory: String = ""

    var body: some View {
        SheetScaffold(
            title: "Add Upload Task".localized,
            minSize: NSSize(width: 520, height: 320),
            onClose: { dismiss() }
        ) {
            VStack(spacing: DesignSystem.Spacing.medium) {
                TextField("Note".localized, text: $note)
                    .textFieldStyle(ModernTextFieldStyle(icon: "note.text"))

                HStack(spacing: DesignSystem.Spacing.small) {
                    TextField("Local File".localized, text: $localPath)
                        .textFieldStyle(ModernTextFieldStyle(icon: "doc"))
                        .disabled(true)

                    Button("Choose File".localized, action: pickFile)
                        .buttonStyle(ModernButtonStyle(variant: .secondary))
                }

                TextField("Remote Directory".localized, text: $remoteDirectory)
                    .textFieldStyle(ModernTextFieldStyle(icon: "folder"))
            }
            .padding()
        } footer: {
            HStack {
                Button("Cancel".localized, action: { dismiss() })
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                Spacer()
                Button("Save".localized, action: save)
                    .buttonStyle(ModernButtonStyle(variant: .primary))
                    .disabled(localPath.isEmpty || remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let handleSelection: (URL) -> Void = { url in
            localPath = url.path
            if note.isEmpty {
                note = url.lastPathComponent
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    handleSelection(url)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            handleSelection(url)
        }
    }

    private func save() {
        let trimmedRemote = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = SavedUploadTask(
            connectionID: connectionID,
            note: trimmedNote,
            localPath: localPath,
            remoteDirectory: trimmedRemote
        )
        onSave(task)
        dismiss()
    }
}

private extension SavedUploadTask {
    var fileName: String {
        URL(fileURLWithPath: localPath).lastPathComponent
    }
}
