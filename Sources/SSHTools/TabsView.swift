import SwiftUI

struct TabsView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var connections: [SSHConnection] // We need write access to update connections from Settings
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabManager.tabs) { tab in
                        TabButton(tab: tab, 
                                  isSelected: tabManager.selectedTabID == tab.id,
                                  onSelect: { tabManager.selectedTabID = tab.id },
                                  onClose: { tabManager.closeTab(id: tab.id) })
                    }
                }
            }
            .frame(height: 36) // Slightly taller for better touch target
            .background(DesignSystem.Colors.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(DesignSystem.Colors.border),
                alignment: .bottom
            )
            
            // Content Area
            ZStack {
                if tabManager.tabs.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                        Text("No Open Tabs".localized)
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                } else {
                    // Use ZStack to keep all views alive
                    ForEach(tabManager.tabs) { tab in
                        TabContentView(tab: tab, connections: $connections, tabManager: tabManager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(tabManager.selectedTabID == tab.id ? 1 : 0)
                            // Crucial: Disable hit testing for hidden views so they don't capture clicks
                            .allowsHitTesting(tabManager.selectedTabID == tab.id)
                    }
                }
            }
        }
    }
}

struct TabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.content.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
            
            Text(tab.content.title)
                .font(DesignSystem.Typography.caption)
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundColor(isSelected ? DesignSystem.Colors.text : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
            
            if tab.content != .home {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isHovering ? DesignSystem.Colors.text : DesignSystem.Colors.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(isHovering ? DesignSystem.Colors.textSecondary.opacity(0.1) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(isSelected ? DesignSystem.Colors.background : DesignSystem.Colors.surface)
        .contentShape(Rectangle()) // Make entire area clickable
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(
            // Separator on the right
            Rectangle()
                .frame(width: 1)
                .foregroundColor(DesignSystem.Colors.border)
                .opacity(0.5)
                .padding(.vertical, 10),
            alignment: .trailing
        )
    }
}

struct TabContentView: View {
    let tab: TabItem
    @Binding var connections: [SSHConnection]
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        switch tab.content {
        case .home:
            HomeView()
        case .terminal(let connection):
            TerminalView(connection: connection)
        case .sftp(let connection):
            SFTPView(connection: connection)
        case .redis(let connection):
            // RedisView updates connection settings internally, but usually we just use it
            RedisView(connection: connection) { updated in
                if let index = connections.firstIndex(where: { $0.id == updated.id }) {
                    connections[index] = updated
                }
            }
        case .mysql(let connection):
            MySQLView(connection: connection)
        case .httpClient:
            HTTPToolView()
        case .devToolbox:
            DevToolboxView()
        }
    }
}
