import Foundation
import SwiftUI
import Combine
import Citadel
import NIO

class SyncedSFTPViewModel: ObservableObject {
    let runner: SSHRunner
    let onNavigate: (String) -> Void
    
    enum SortField {
        case name, size, date
    }
    
    @Published var path: String
    @Published var files: [RemoteFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sortField: SortField = .name
    @Published var sortAscending: Bool = true
    @Published var selectedFileId: UUID?
    
    // Editor State
    @Published var activeEditorFile: RemoteFile?
    @Published var activeEditorContent: String = ""
    @Published var isEditorOpen: Bool = false
    
    // Rename State
    @Published var activeRenameFile: RemoteFile?
    @Published var isRenameOpen: Bool = false
    
    private var rawFiles: [RemoteFile] = []
    private var cancellables = Set<AnyCancellable>()
    
    init(runner: SSHRunner, path: String, onNavigate: @escaping (String) -> Void) {
        self.runner = runner
        self.path = path.isEmpty ? "/" : path
        self.onNavigate = onNavigate
        
        runner.$sftp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sftp in
                if sftp != nil {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
    }
    
    func toggleSort(field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
        applySort()
    }
    
    private func applySort() {
        let sorted = rawFiles.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            
            let result: Bool
            switch sortField {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                result = lhs.size.localizedStandardCompare(rhs.size) == .orderedAscending
            case .date:
                result = lhs.date.localizedStandardCompare(rhs.date) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
        self.files = sorted
    }
    
    func refresh() {
        guard let sftp = runner.sftp else {
            errorMessage = "SFTP not connected"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let mappedFiles = try await SFTPService.shared.listDirectory(sftp: sftp, at: self.path)
                await MainActor.run {
                    self.rawFiles = mappedFiles
                    self.applySort()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to list files: \(error.localizedDescription)"
                    self.isLoading = false
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
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
            Task {
                do {
                    try await SFTPService.shared.download(sftp: sftp, remotePath: remotePath, fileName: file.name, to: targetURL)
                } catch {
                    Logger.log("Download failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    func uploadFile(from localURL: URL) {
        guard let sftp = runner.sftp else { return }
        let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + localURL.lastPathComponent
        
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
    
    func editFile(_ file: RemoteFile) {
        if file.rawSize > 5 * 1024 * 1024 {
            ToastManager.shared.show(message: "File too large to edit (> 5MB)".localized, type: .error)
            return
        }
        
        guard let sftp = runner.sftp else { return }
        isLoading = true
        
        Task { [weak self] in
            guard let self = self else { return }
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
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
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
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
    
    func renameFile(_ file: RemoteFile, to newName: String) {
        guard let sftp = runner.sftp else { return }
        let oldPath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
        let newPath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + newName
        
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
    
    func deleteFile(_ file: RemoteFile) {
        guard let sftp = runner.sftp else { return }
        let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
        
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
}
