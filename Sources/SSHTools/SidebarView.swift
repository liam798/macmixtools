import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: ConnectionsStore
    @ObservedObject var tabManager: TabManager
    @ObservedObject var transferManager: TransferManager = .shared
    
    @Binding var selection: UUID?
    @Binding var editingConnectionID: IdentifiableUUID?
    
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))
                
                TextField("Search servers...".localized, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            List(selection: $selection) {
                if searchText.isEmpty {
                    Section("Tools".localized) {
                        SidebarToolRow(title: "HTTP Client".localized, 
                                       icon: "network", 
                                       color: DesignSystem.Colors.blue, 
                                       id: AppConstants.FixedIDs.httpClient)
                        
                        SidebarToolRow(title: "Dev Toolbox".localized, 
                                       icon: "wrench.and.screwdriver.fill", 
                                       color: DesignSystem.Colors.purple, 
                                       id: AppConstants.FixedIDs.devToolbox)
                    }
                }
                
                // Grouped Connections
                ForEach($store.groups) { $group in
                    let filteredConnections = store.connections.filter { 
                        group.connectionIds.contains($0.id) && 
                        (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.host.localizedCaseInsensitiveContains(searchText))
                    }
                    
                    if !filteredConnections.isEmpty {
                        Section(header: Text(group.name)) {
                            ForEach(filteredConnections) { connection in
                                ConnectionRowView(connection: connection, 
                                                 editingConnectionID: $editingConnectionID,
                                                 tabManager: tabManager,
                                                 onDelete: { store.deleteConnection(id: connection.id) })
                                    .tag(connection.id)
                            }
                        }
                    }
                }
                
                // Orphan Connections
                let orphanConnections = store.connections.filter { conn in
                    !store.groups.contains(where: { $0.connectionIds.contains(conn.id) }) &&
                    (searchText.isEmpty || conn.name.localizedCaseInsensitiveContains(searchText) || conn.host.localizedCaseInsensitiveContains(searchText))
                }
                
                if !orphanConnections.isEmpty {
                    Section("Servers".localized) {
                        ForEach(orphanConnections) { connection in
                            ConnectionRowView(connection: connection, 
                                             editingConnectionID: $editingConnectionID,
                                             tabManager: tabManager,
                                             onDelete: { store.deleteConnection(id: connection.id) })
                                .tag(connection.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Servers".localized)
        .toolbar {
            ToolbarItem {
                SidebarAddMenu(store: store, onAdd: addConnection)
            }
            
            ToolbarItem {
                TransferStatusButton(transferManager: transferManager)
            }
        }
    }
    
    private func addConnection(type: ConnectionType) {
        var newConnection = SSHConnection(name: type == .ssh ? "New Server" : (type == .redis ? "New Redis" : "New MySQL"), host: "", username: "")
        newConnection.type = type
        if type == .redis {
            newConnection.port = AppConstants.Ports.redis
            newConnection.username = "" 
        } else if type == .mysql {
            newConnection.port = AppConstants.Ports.mysql
        }
        store.connections.append(newConnection)
        selection = newConnection.id
        editingConnectionID = IdentifiableUUID(id: newConnection.id)
    }
}

private struct SidebarToolRow: View {
    let title: String
    let icon: String
    let color: Color
    let id: UUID
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14))
            }
            Text(title)
                .font(DesignSystem.Typography.body.weight(.medium))
                .foregroundColor(DesignSystem.Colors.text)
        }
        .padding(.vertical, 4)
        .tag(id)
    }
}

private struct SidebarAddMenu: View {
    @ObservedObject var store: ConnectionsStore
    let onAdd: (ConnectionType) -> Void
    
    var body: some View {
        Menu {
            Button(action: { store.addGroup(name: "New Group") }) {
                Label("Add Group", systemImage: "folder.badge.plus")
            }
            Divider()
            Button(action: { onAdd(.ssh) }) {
                Label("SSH Terminal".localized, systemImage: "terminal")
            }
            Button(action: { onAdd(.redis) }) {
                Label("Redis".localized, systemImage: "database")
            }
            Button(action: { onAdd(.mysql) }) {
                Label("MySQL Database".localized, systemImage: "server.rack")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}

private struct TransferStatusButton: View {
    @ObservedObject var transferManager: TransferManager
    
    var body: some View {
        Button(action: { transferManager.isShowingTasks.toggle() }) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(transferManager.tasks.isEmpty ? .secondary : .blue)
        }
        .popover(isPresented: $transferManager.isShowingTasks) {
            TransferListView()
        }
        .help("Transfer Tasks")
    }
}

