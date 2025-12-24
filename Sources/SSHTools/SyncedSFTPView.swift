import SwiftUI

struct SyncedSFTPView: View {
    let runner: SSHRunner
    @Binding var path: String
    @Binding var isExpanded: Bool // New binding for expansion state
    let onNavigate: (String) -> Void
    
    @StateObject private var viewModel: SyncedSFTPViewModel
    // FileEditManager removed
    
    init(runner: SSHRunner, path: Binding<String>, isExpanded: Binding<Bool>, onNavigate: @escaping (String) -> Void) {
        self.runner = runner
        self._path = path
        self._isExpanded = isExpanded
        self.onNavigate = onNavigate
        _viewModel = StateObject(wrappedValue: SyncedSFTPViewModel(runner: runner, path: path.wrappedValue, onNavigate: onNavigate))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.path)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                
                // Collapse/Expand Button
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Collapse".localized : "Expand".localized)

                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.5)
                }
                Button(action: viewModel.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.surface)
            
            // Table Header
            HStack(spacing: 12) {
                Button(action: { viewModel.toggleSort(field: .name) }) {
                    HStack {
                        Text("Name".localized)
                        SortIndicator(field: .name, currentField: viewModel.sortField, ascending: viewModel.sortAscending)
                    }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 28) // Alignment with icon + text
                
                Text("Permissions".localized)
                    .frame(width: 85, alignment: .leading)
                
                Text("Owner".localized)
                    .frame(width: 80, alignment: .leading)
                
                Button(action: { viewModel.toggleSort(field: .size) }) {
                    HStack {
                        Text("Size".localized)
                        SortIndicator(field: .size, currentField: viewModel.sortField, ascending: viewModel.sortAscending)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 70, alignment: .trailing)
                
                Button(action: { viewModel.toggleSort(field: .date) }) {
                    HStack {
                        Text("Date".localized)
                        SortIndicator(field: .date, currentField: viewModel.sortField, ascending: viewModel.sortAscending)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 120, alignment: .trailing)
                
                Spacer().frame(width: 80) // Spacer for actions column
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.surfaceSecondary.opacity(0.5))
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                Spacer()
            } else {
                List(viewModel.files, id: \.id) { file in
                    FileRowView(file: file,
                                path: viewModel.path,
                                isSelected: viewModel.selectedFileId == file.id,
                                onDownload: { viewModel.download(file: file) },
                                onEdit: { _ in viewModel.editFile(file) },
                                onNavigate: self.onNavigate,
                                onRename: { newName in viewModel.renameFile(file, to: newName) },
                                onShowRename: {
                                    viewModel.activeRenameFile = file
                                    viewModel.isRenameOpen = true
                                },
                                onSelect: {
                                    viewModel.selectedFileId = file.id
                                },
                                onDelete: { viewModel.deleteFile(file) })
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 10) // Reduced to 10pt
                }
            }
        }
        .sheet(isPresented: $viewModel.isEditorOpen) {
            if let file = viewModel.activeEditorFile {
                FileEditorSheet(
                    fileName: file.name,
                    content: viewModel.activeEditorContent,
                    onSave: { newContent in
                        viewModel.saveFileContent(newContent)
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.isRenameOpen) {
            if let file = viewModel.activeRenameFile {
                RenameSheet(
                    currentName: file.name,
                    onRename: { newName in
                        viewModel.renameFile(file, to: newName)
                    }
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // Handle file drops
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            viewModel.uploadFile(from: url)
                        }
                    }
                }
            }
            return true
        }
        .onChange(of: viewModel.path) { _ in // Observe viewModel.path, not SyncedSFTPView's path directly
            viewModel.refresh()
        }
        .onChange(of: path) { newPath in // Observe the path passed from TerminalView
            if viewModel.path != newPath {
                viewModel.path = newPath
                viewModel.refresh()
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

struct FileRowView: View {
    @ObservedObject var file: RemoteFile
    let path: String
    let isSelected: Bool
    let onDownload: () -> Void
    let onEdit: (String) -> Void
    let onNavigate: (String) -> Void
    let onRename: (String) -> Void
    let onShowRename: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(file.isDirectory ? DesignSystem.Colors.blue : DesignSystem.Colors.text)
                .frame(width: 16)
            
            Text(file.name)
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            
            Group {
                Text(file.permissions)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 85, alignment: .leading)
                
                Text("\(file.owner):\(file.group)")
                    .font(.system(size: 11))
                    .frame(width: 80, alignment: .leading)
                
                Text(file.size)
                    .font(.system(size: 11))
                    .frame(width: 70, alignment: .trailing)
                
                Text(file.date)
                    .font(.system(size: 11))
                    .frame(width: 120, alignment: .trailing)
            }
            .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            
            HStack(spacing: 8) {
                // Status Indicators only
                switch file.downloadStatus {
                case .transferring:
                    if let progress = file.downloadProgress {
                        DownloadIndicator(progress: progress)
                    }
                case .queuing:
                    ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
                case .failed(let msg):
                    Text("Error").foregroundColor(.red).font(.caption).help(msg)
                case .completed:
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                case .none:
                    EmptyView()
                }
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(isSelected ? DesignSystem.Colors.blue.opacity(0.7) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .gesture(TapGesture(count: 2).onEnded {
            let fullPath = path.hasSuffix("/") ? path + file.name : path + "/" + file.name
            if file.isDirectory {
                onNavigate(fullPath)
            } else {
                onEdit(fullPath)
            }
        })
        .contextMenu {
            Button(action: onShowRename) {
                Label("Rename", systemImage: "pencil.and.outline")
            }
            
            Button(action: {
                let fullPath = path.hasSuffix("/") ? path + file.name : path + "/" + file.name
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(fullPath, forType: .string)
                ToastManager.shared.show(message: "Path copied".localized, type: .success)
            }) {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            
            if !file.isDirectory {
                Button(action: { onEdit(path.hasSuffix("/") ? path + file.name : path + "/" + file.name) }) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}

struct DownloadIndicator: View {
    let progress: Double
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 60)
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .frame(height: 10)
    }
}

struct SortIndicator: View {
    let field: SyncedSFTPViewModel.SortField
    let currentField: SyncedSFTPViewModel.SortField
    let ascending: Bool
    
    var body: some View {
        if field == currentField {
            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.blue)
        } else {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.3))
        }
    }
}
