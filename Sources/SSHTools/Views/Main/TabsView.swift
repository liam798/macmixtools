import SwiftUI
import AppKit

private struct ContentPane: Identifiable, Equatable {
    let id: UUID
    var tabID: UUID?
    var width: CGFloat // fraction of total width (0...1)
    
    init(id: UUID = UUID(), tabID: UUID?, width: CGFloat) {
        self.id = id
        self.tabID = tabID
        self.width = width
    }
}

struct TabsView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var connections: [SSHConnection] // We need write access to update connections from Settings
    
    // Split view state: which tabs are displayed in each pane & their widths (sum to 1)
    @State private var panes: [ContentPane] = []
    @State private var dragBaseWidths: [CGFloat] = []
    @State private var activeDragIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var paneTabCache: [UUID: [UUID]] = [:]
    
    private let layoutStore = PaneLayoutStore()
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabManager.tabs) { tab in
                            TabButton(tab: tab, 
                                      isSelected: tabManager.selectedTabID == tab.id,
                                      onSelect: { selectTab(tab.id) },
                                      onClose: { closeTabAndCleanSplits(tab.id) })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                
                // Split controls
                HStack(spacing: 6) {
                    Button {
                        addSplit()
                    } label: {
                        Label("Split View".localized, systemImage: "square.split.2x1")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Split View".localized)
                    .disabled(panes.count >= AppConstants.UI.maxContentSplits || tabManager.tabs.isEmpty)
                    
                    Button {
                        removeSplit()
                    } label: {
                        Label("Close Split".localized, systemImage: "xmark.rectangle")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Close Split".localized)
                    .disabled(panes.count <= 1)
                    
                    Button {
                        resetLayout()
                    } label: {
                        Label("Reset Layout".localized, systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Reset Layout".localized)
                    
                    if panes.count > 1 {
                        Button {
                            nudgeSplit(deltaFraction: -0.03)
                        } label: {
                            Image(systemName: "arrow.left")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Nudge Split Left".localized)
                        .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
                        
                        Button {
                            nudgeSplit(deltaFraction: 0.03)
                        } label: {
                            Image(systemName: "arrow.right")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Nudge Split Right".localized)
                        .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
                    }
                }
                .padding(.trailing, 12)
            }
            .frame(height: 44)
            .background(DesignSystem.Colors.background)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(DesignSystem.Colors.border),
                alignment: .bottom
            )
            
            // Content Area
            contentArea
        }
        .onAppear {
            loadSavedLayout()
            ensureInitialPane()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            syncPrimaryPaneWithSelection()
        }
        .onChange(of: tabManager.tabs) { _, _ in
            pruneInvalidPaneTabs()
            ensureUniqueTabAssignments()
        }
        .onChange(of: panes) { _, newValue in
            layoutStore.save(newValue)
        }
    }
    
    // MARK: - Content Area
    @ViewBuilder
    private var contentArea: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            if tabManager.tabs.isEmpty {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("No Open Tabs".localized)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                        VStack(spacing: 0) {
                            paneHeader(for: pane)
                            Divider()
                            paneContent(for: pane)
                        }
                        .frame(width: max(pane.width * totalWidth, DesignSystem.Layout.contentPaneMinWidth))
                        .frame(maxHeight: .infinity)
                        
                        if index < panes.count - 1 {
                            SplitDragHandle(
                                isActive: activeDragIndex == index,
                                dragOffset: activeDragIndex == index ? dragOffset : 0,
                                onDragChanged: { translation in
                                    beginDragIfNeeded(at: index)
                                    dragOffset = translation
                                },
                                onDragEnded: { translation in
                                    commitWidths(at: index, translation: translation, totalWidth: totalWidth)
                                    activeDragIndex = nil
                                    dragOffset = 0
                                    dragBaseWidths = []
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Pane Header & Content
    @ViewBuilder
    private func paneHeader(for pane: ContentPane) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: bindingForPane(pane)) {
                ForEach(tabManager.tabs) { tab in
                    Text(tab.content.title).tag(Optional(tab.id))
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .pickerStyle(.menu)
            
            Spacer()
            
            if panes.count > 1 {
                Button {
                    removeSplit(pane.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.surface)
    }
    
    @ViewBuilder
    private func paneContent(for pane: ContentPane) -> some View {
        if let tabID = pane.tabID {
            let cachedIDs = paneTabCache[pane.id] ?? []
            let visibleTabs = tabManager.tabs.filter { cachedIDs.contains($0.id) || $0.id == tabID }
            ZStack {
                ForEach(visibleTabs) { tab in
                    TabContentView(tab: tab, connections: $connections, tabManager: tabManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(tab.id == tabID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabID)
                }
            }
        } else {
            VStack {
                Text("No Open Tabs".localized)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Actions
    private func addSplit() {
        guard panes.count < AppConstants.UI.maxContentSplits else { return }
        let used = Set(panes.compactMap { $0.tabID })
        let preferred = tabManager.selectedTabID
        let targetTabID = (preferred != nil && !used.contains(preferred!)) ? preferred : tabManager.tabs.first(where: { !used.contains($0.id) })?.id
        let newWidth = 1 / CGFloat(panes.count + 1)
        let scale = (1 - newWidth) / max(panes.reduce(0) { $0 + $1.width }, 1)
        for idx in panes.indices { panes[idx].width *= scale }
        panes.append(ContentPane(tabID: targetTabID, width: newWidth))
        cacheTabID(targetTabID, for: panes.last?.id)
    }
    
    private func removeSplit(_ id: UUID? = nil) {
        guard panes.count > 1 else { return }
        if let id = id {
            panes.removeAll { $0.id == id }
        } else {
            panes.removeLast()
        }
        normalizeWidths()
        if panes.isEmpty { ensureInitialPane() }
    }
    
    private func resetLayout() {
        panes = [ContentPane(tabID: tabManager.selectedTabID ?? tabManager.tabs.first?.id, width: 1)]
    }
    
    private func selectTab(_ id: UUID) {
        tabManager.selectedTabID = id
        syncPrimaryPaneWithSelection()
    }
    
    private func closeTabAndCleanSplits(_ id: UUID) {
        tabManager.closeTab(id: id)
        pruneInvalidPaneTabs()
    }
    
    // MARK: - Helpers
    private func ensureInitialPane() {
        if panes.isEmpty {
            panes = [ContentPane(tabID: tabManager.selectedTabID ?? tabManager.tabs.first?.id, width: 1)]
            cacheTabID(panes.first?.tabID, for: panes.first?.id)
        }
    }
    
    private func syncPrimaryPaneWithSelection() {
        guard let selection = tabManager.selectedTabID else { return }
        if panes.isEmpty {
            panes = [ContentPane(tabID: selection, width: 1)]
            cacheTabID(panes.first?.tabID, for: panes.first?.id)
            return
        }
        if panes[0].tabID != selection {
            resolveDuplicateSelection(paneID: panes[0].id, newTabID: selection, oldTabID: panes[0].tabID)
            panes[0].tabID = selection
            cacheTabID(selection, for: panes[0].id)
        }
    }
    
    private func pruneInvalidPaneTabs() {
        let validIDs = Set(tabManager.tabs.map { $0.id })
        var updated = panes
        for idx in updated.indices {
            if let tabID = updated[idx].tabID, !validIDs.contains(tabID) {
                updated[idx].tabID = tabManager.selectedTabID ?? tabManager.tabs.first?.id
            }
        }
        if updated.isEmpty {
            panes = [ContentPane(tabID: tabManager.selectedTabID ?? tabManager.tabs.first?.id, width: 1)]
            cacheTabID(panes.first?.tabID, for: panes.first?.id)
        } else {
            panes = updated
        }
        ensureUniqueTabAssignments()
        normalizeWidths()
    }
    
    private func loadSavedLayout() {
        guard let saved = layoutStore.load() else { return }
        let validIDs = Set(tabManager.tabs.map { $0.id })
        let mapped = saved.compactMap { record -> ContentPane? in
            let tabID = record.tabID.flatMap { validIDs.contains($0) ? $0 : nil } ?? tabManager.tabs.first?.id
            return ContentPane(id: record.id, tabID: tabID, width: record.width)
        }
        guard !mapped.isEmpty else { return }
        panes = mapped
        for pane in panes {
            cacheTabID(pane.tabID, for: pane.id)
        }
        ensureUniqueTabAssignments()
        normalizeWidths()
    }
    
    private func bindingForPane(_ pane: ContentPane) -> Binding<UUID?> {
        Binding<UUID?>(
            get: {
                panes.first(where: { $0.id == pane.id })?.tabID
            },
            set: { newValue in
                if let idx = panes.firstIndex(where: { $0.id == pane.id }) {
                    let oldValue = panes[idx].tabID
                    if let newValue {
                        resolveDuplicateSelection(paneID: pane.id, newTabID: newValue, oldTabID: oldValue)
                    }
                    panes[idx].tabID = newValue
                    if panes.indices.contains(0), panes[0].id == pane.id, let newValue {
                        tabManager.selectedTabID = newValue
                    }
                    cacheTabID(newValue, for: pane.id)
                }
            }
        )
    }

    private func cacheTabID(_ tabID: UUID?, for paneID: UUID?) {
        guard let tabID, let paneID else { return }
        var list = paneTabCache[paneID] ?? []
        if !list.contains(tabID) {
            list.append(tabID)
            paneTabCache[paneID] = list
        }
    }

    private func resolveDuplicateSelection(paneID: UUID, newTabID: UUID, oldTabID: UUID?) {
        guard let otherIndex = panes.firstIndex(where: { $0.id != paneID && $0.tabID == newTabID }) else { return }
        let replacement: UUID?
        if let old = oldTabID, old != newTabID {
            replacement = old
        } else {
            replacement = tabManager.tabs.first(where: { $0.id != newTabID })?.id
        }
        panes[otherIndex].tabID = replacement
        cacheTabID(replacement, for: panes[otherIndex].id)
    }

    private func ensureUniqueTabAssignments() {
        var used = Set<UUID>()
        var updated = panes
        for idx in updated.indices {
            guard let tabID = updated[idx].tabID else { continue }
            if used.contains(tabID) {
                let replacement = tabManager.tabs.first(where: { !used.contains($0.id) })?.id
                updated[idx].tabID = replacement
                cacheTabID(replacement, for: updated[idx].id)
                if let replacement { used.insert(replacement) }
            } else {
                used.insert(tabID)
            }
        }
        panes = updated
    }
    
    private func beginDragIfNeeded(at index: Int) {
        if activeDragIndex == nil {
            activeDragIndex = index
            dragBaseWidths = panes.map { $0.width }
        }
    }
    
    // MARK: - Width Helpers
    private func normalizeWidths() {
        let total = panes.reduce(0) { $0 + $1.width }
        guard total > 0 else {
            let equal = 1 / CGFloat(max(panes.count, 1))
            panes = panes.map { ContentPane(id: $0.id, tabID: $0.tabID, width: equal) }
            return
        }
        for idx in panes.indices {
            panes[idx].width = panes[idx].width / total
        }
    }
    
    private func commitWidths(at index: Int, translation: CGFloat, totalWidth: CGFloat) {
        guard panes.indices.contains(index), panes.indices.contains(index + 1), totalWidth > 0 else { return }
        if dragBaseWidths.isEmpty { dragBaseWidths = panes.map { $0.width } }
        
        let leftBase = dragBaseWidths[index]
        let rightBase = dragBaseWidths[index + 1]
        let deltaFraction = translation / totalWidth
        
        let minFraction = min(DesignSystem.Layout.contentPaneMinWidth / totalWidth, 0.9)
        
        var newLeft = leftBase + deltaFraction
        var newRight = rightBase - deltaFraction
        
        // Clamp to minimums
        if newLeft < minFraction {
            let deficit = minFraction - newLeft
            newLeft = minFraction
            newRight -= deficit
        }
        if newRight < minFraction {
            let deficit = minFraction - newRight
            newRight = minFraction
            newLeft -= deficit
        }
        
        guard newLeft > 0, newRight > 0 else { return }
        
        panes[index].width = newLeft
        panes[index + 1].width = newRight
        normalizeWidths()
    }
    
    private func nudgeSplit(deltaFraction: CGFloat, index: Int = 0) {
        guard panes.count > 1,
              panes.indices.contains(index),
              panes.indices.contains(index + 1) else { return }
        
        var left = panes[index].width
        var right = panes[index + 1].width
        let minFraction: CGFloat = 0.1
        
        left += deltaFraction
        right -= deltaFraction
        
        if left < minFraction || right < minFraction { return }
        
        panes[index].width = left
        panes[index + 1].width = right
        normalizeWidths()
    }
}

private struct SplitDragHandle: View {
    var isActive: Bool
    var dragOffset: CGFloat
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: (CGFloat) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            
            if isActive {
                Rectangle()
                    .fill(DesignSystem.Colors.blue)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .offset(x: dragOffset)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.25))
                    .frame(width: 3, height: 36)
            }
            
            Color.clear
                .contentShape(Rectangle())
        }
        .frame(width: DesignSystem.Layout.sidebarSplitterWidth)
        .frame(maxHeight: .infinity)
        .zIndex(50) // keep guide above terminal/web views
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    NSCursor.resizeLeftRight.set()
                    onDragChanged(value.translation.width)
                }
                .onEnded { value in
                    onDragEnded(value.translation.width)
                    NSCursor.arrow.set()
                }
        )
        .onHover { inside in
            isHovering = inside
            let cursor: NSCursor = inside ? .resizeLeftRight : .arrow
            cursor.set()
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
        HStack(spacing: 8) {
            Image(systemName: tab.content.icon)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? DesignSystem.Colors.blue : DesignSystem.Colors.textSecondary)
            
            Text(tab.content.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? DesignSystem.Colors.text : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
            
            if tab.content != .home {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(4)
                        .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? DesignSystem.Colors.surface : (isHovering ? Color.white.opacity(0.05) : Color.clear))
        )
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
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
            TerminalView(connection: connection, tabID: tab.id)
        case .localTerminal(let connection):
            LocalTerminalView(connection: connection, tabID: tab.id)
        case .sftp(let connection):
            StandaloneSFTPView(connection: connection)
        case .redis(let connection):
            // RedisView updates connection settings internally, but usually we just use it
            RedisView(connection: connection) { updated in
                if let index = connections.firstIndex(where: { $0.id == updated.id }) {
                    connections[index] = updated
                }
            }
        case .mysql(let connection):
            MySQLView(connection: connection)
        case .clickhouse(let connection):
            MySQLView(connection: connection)
        case .httpClient:
            HTTPToolView()
        case .devToolbox:
            DevToolboxView()
        }
    }
}

// MARK: - Persistence
private struct PaneLayoutStore {
    private struct Record: Codable {
        let id: UUID
        let tabID: UUID?
        let width: Double
    }
    
    private let key = "sshtools.layout.panes"
    
    func load() -> [ContentPane]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return nil }
        return records.map { ContentPane(id: $0.id, tabID: $0.tabID, width: CGFloat($0.width)) }
    }
    
    func save(_ panes: [ContentPane]) {
        let total = panes.reduce(0) { $0 + $1.width }
        let normalized = total > 0 ? panes.map { ContentPane(id: $0.id, tabID: $0.tabID, width: $0.width / total) } : panes
        let records = normalized.map { Record(id: $0.id, tabID: $0.tabID, width: Double($0.width)) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
