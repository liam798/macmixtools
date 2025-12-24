import SwiftUI

struct SFTPView: View {
    @StateObject private var viewModel: SFTPViewModel
    
    init(connection: SSHConnection) {
        _viewModel = StateObject(wrappedValue: SFTPViewModel(connection: connection))
    }
    
    var body: some View {
        VStack {
            HStack {
                TextField("Path".localized, text: $viewModel.currentPath)
                    .onSubmit { viewModel.refresh() }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: viewModel.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                
                Button(action: viewModel.goUp) {
                    Image(systemName: "arrow.up")
                }
                .help("Up Directory")
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            ZStack {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.files, id: \.id) { file in
                        HStack {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                                .foregroundColor(file.isDirectory ? DesignSystem.Colors.blue : (viewModel.selectedFileId == file.id ? .white : DesignSystem.Colors.text))
                            Text(file.name)
                                .foregroundColor(viewModel.selectedFileId == file.id ? .white : DesignSystem.Colors.text)
                            Spacer()
                            Text(file.size)
                                .foregroundColor(viewModel.selectedFileId == file.id ? .white.opacity(0.8) : DesignSystem.Colors.textSecondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(viewModel.selectedFileId == file.id ? DesignSystem.Colors.blue.opacity(0.7) : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle()) // Make full row clickable for double tap
                        .simultaneousGesture(TapGesture().onEnded {
                            viewModel.selectedFileId = file.id
                        })
                        .gesture(TapGesture(count: 2).onEnded {
                            if file.isDirectory {
                                viewModel.enterDirectory(file.name)
                            } else {
                                viewModel.editFile(file)
                            }
                        })
                        .contextMenu {
                            Button(action: {
                                viewModel.activeRenameFile = file
                                viewModel.isRenameOpen = true
                            }) {
                                Label("Rename", systemImage: "pencil.and.outline")
                            }
                            
                            Button(action: {
                                let fullPath = viewModel.currentPath.hasSuffix("/") ? viewModel.currentPath + file.name : viewModel.currentPath + "/" + file.name
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(fullPath, forType: .string)
                                ToastManager.shared.show(message: "Path copied".localized, type: .success)
                            }) {
                                Label("Copy Path", systemImage: "doc.on.doc")
                            }
                            
                            Button(role: .destructive, action: { viewModel.deleteFile(file) }) {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            if !file.isDirectory {
                                Button(action: { viewModel.editFile(file) }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                
                                Button(action: { viewModel.download(file: file) }) {
                                    Label("Download", systemImage: "arrow.down.circle")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 10)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
            
            HStack {
                Button("Upload File".localized) {
                    viewModel.upload()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary))
                
                Spacer()
                
                Text("\(viewModel.files.count) " + "items".localized)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
        }
        .onAppear {
            viewModel.connectAndList()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .navigationTitle(viewModel.currentPath)
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
    }
}
