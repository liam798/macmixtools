import Foundation
import SwiftUI
import Combine
import Citadel
import NIO

/// ViewModel for the standalone SFTP browser
class SFTPViewModel: ObservableObject {
    @Published var currentPath: String = "/"
    @Published var files: [RemoteFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFileId: UUID?
    
    // Editor State
    @Published var activeEditorFile: RemoteFile?
    @Published var activeEditorContent: String = ""
    @Published var isEditorOpen: Bool = false
    
    // Rename State
    @Published var activeRenameFile: RemoteFile?
    @Published var isRenameOpen: Bool = false
    
    let runner = SSHRunner()
    private let connection: SSHConnection
    private var cancellables = Set<AnyCancellable>()
    
    init(connection: SSHConnection) {
        self.connection = connection
        
        runner.$sftp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sftp in
                if sftp != nil {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
    }
    
    func connectAndList() {
        guard !runner.isConnected else {
            refresh()
            return
        }
        isLoading = true
        runner.connect(connection: connection)
    }
    
    func refresh() {
        guard let sftp = runner.sftp else {
            if !runner.isConnected { return }
            errorMessage = "SFTP not initialized"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let mappedFiles = try await SFTPService.shared.listDirectory(sftp: sftp, at: self.currentPath)
                let sorted = mappedFiles.sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name < $1.name
                }
                
                await MainActor.run {
                    self.files = sorted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "List failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    func navigate(to path: String) {
        currentPath = path
        refresh()
    }
    
    func goUp() {
        if currentPath.hasSuffix("/") { currentPath.removeLast() }
        let components = currentPath.split(separator: "/")
        if components.count > 0 {
            currentPath = "/" + components.dropLast().joined(separator: "/")
            if currentPath == "" { currentPath = "/" }
        } else {
            currentPath = "/"
        }
        refresh()
    }
    
    func enterDirectory(_ name: String) {
        currentPath = (currentPath.hasSuffix("/") ? currentPath : currentPath + "/") + name
        refresh()
    }
    
    func editFile(_ file: RemoteFile) {
        if file.rawSize > 5 * 1024 * 1024 {
            ToastManager.shared.show(message: "File too large to edit (> 5MB)".localized, type: .error)
            return
        }
        
        guard let sftp = runner.sftp else { return }
        isLoading = true
        
        Task { [weak self] in
            guard let self = self else { return }
            let remotePath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + file.name
            
            do {
                let content = try await SFTPService.shared.readFile(sftp: sftp, at: remotePath)
                await MainActor.run {
                    self.activeEditorFile = file
                    self.activeEditorContent = content
                    self.isEditorOpen = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to read file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func saveFileContent(_ content: String) {
        guard let sftp = runner.sftp, let file = activeEditorFile else { return }
        
        Task { [weak self] in
            guard let self = self else { return }
            let remotePath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + file.name
            
            do {
                try await SFTPService.shared.writeFile(sftp: sftp, at: remotePath, content: content)
                await MainActor.run {
                    ToastManager.shared.show(message: "Saved \(file.name)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Failed to save: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    func download(file: RemoteFile) {
        guard let sftp = runner.sftp else { return }
        
        let defaultPath = SettingsManager.shared.defaultDownloadPath
        var localURL: URL? = nil
        
        if !defaultPath.isEmpty {
            localURL = URL(fileURLWithPath: defaultPath).appendingPathComponent(file.name)
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            if panel.runModal() == .OK {
                localURL = panel.url
            }
        }
        
        if let targetURL = localURL {
            Task { [weak self] in
                guard let self = self else { return }
                let remotePath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + file.name
                do {
                    try await SFTPService.shared.download(sftp: sftp, remotePath: remotePath, fileName: file.name, to: targetURL)
                } catch {
                    Logger.log("Download failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    func upload() {
        guard let sftp = runner.sftp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let localURL = panel.url {
            let remotePath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + localURL.lastPathComponent
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await SFTPService.shared.upload(sftp: sftp, localURL: localURL, remotePath: remotePath)
                    await MainActor.run { self.refresh() }
                } catch {
                    Logger.log("Upload failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    func deleteFile(_ file: RemoteFile) {
        guard let sftp = runner.sftp else { return }
        let remotePath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + file.name
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await SFTPService.shared.deleteFile(sftp: sftp, at: remotePath, isDirectory: file.isDirectory)
                await MainActor.run {
                    ToastManager.shared.show(message: "Deleted \(file.name)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Delete failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    func renameFile(_ file: RemoteFile, to newName: String) {
        guard let sftp = runner.sftp else { return }
        let oldPath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + file.name
        let newPath = (self.currentPath.hasSuffix("/") ? self.currentPath : self.currentPath + "/") + newName
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await SFTPService.shared.rename(sftp: sftp, oldPath: oldPath, newPath: newPath)
                await MainActor.run {
                    ToastManager.shared.show(message: "Renamed to \(newName)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Rename failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    func cleanup() {
        runner.disconnect()
    }
}