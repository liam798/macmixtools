import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConnectionsStore()
    @StateObject private var tabManager = TabManager()
    
    @State private var sidebarSelection: UUID?
    @State private var editingConnectionID: IdentifiableUUID?
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(store: store, 
                            tabManager: tabManager, 
                            selection: $sidebarSelection, 
                            editingConnectionID: $editingConnectionID)
            } detail: {
                TabsView(tabManager: tabManager, connections: $store.connections)
            }
            .onChange(of: sidebarSelection) { newID in
                handleSelectionChange(newID)
            }
            .sheet(item: $editingConnectionID) { identifiableUUID in
                ConnectionSettingsPresenter(store: store, 
                                          id: identifiableUUID.id, 
                                          onClose: { editingConnectionID = nil },
                                          onConnect: { id in
                    editingConnectionID = nil
                    if let connection = store.connections.first(where: { $0.id == id }) {
                        openConnection(connection)
                    }
                })
            }
            
            ToastContainerView()
        }
    }
    
    private func handleSelectionChange(_ id: UUID?) {
        guard let id = id else { return }
        
        if id == AppConstants.FixedIDs.httpClient {
            tabManager.openTab(content: .httpClient)
            return
        }
        
        if id == AppConstants.FixedIDs.devToolbox {
            tabManager.openTab(content: .devToolbox)
            return
        }
        
        guard let connection = store.connections.first(where: { $0.id == id }) else { return }
        
        if isConnectionValid(connection) {
            openConnection(connection)
        } else {
            editingConnectionID = IdentifiableUUID(id: id)
        }
    }
    
    private func openConnection(_ connection: SSHConnection) {
        switch connection.type {
        case .redis:
            tabManager.openTab(content: .redis(connection))
        case .mysql:
            tabManager.openTab(content: .mysql(connection))
        case .ssh:
            tabManager.openTab(content: .terminal(connection))
        }
    }
    
    private func isConnectionValid(_ connection: SSHConnection) -> Bool {
        if connection.host.isEmpty { return false }
        if (connection.type == .ssh || connection.type == .mysql) && connection.username.isEmpty { return false }
        return true
    }
}

/// 辅助视图用于连接设置的逻辑呈现
struct ConnectionSettingsPresenter: View {
    @ObservedObject var store: ConnectionsStore
    let id: UUID
    let onClose: () -> Void
    let onConnect: (UUID) -> Void
    
    var body: some View {
        if let index = store.connections.firstIndex(where: { $0.id == id }) {
            ConnectionSettingsSheet(connection: $store.connections[index],
                                    onClose: onClose,
                                    onConnect: { onConnect(id) })
        } else {
            Text("Error".localized)
        }
    }
}