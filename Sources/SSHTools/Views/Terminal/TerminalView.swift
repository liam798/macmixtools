import SwiftUI
import AppKit

struct TerminalView: View {
    @ObservedObject private var viewModel: TerminalViewModel
    @Namespace private var bottomID
    
    private let tabID: UUID

    init(connection: SSHConnection, tabID: UUID) {
        _viewModel = ObservedObject(wrappedValue: TerminalViewModelStore.shared.viewModel(for: connection))
        self.tabID = tabID
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let splitterHeight: CGFloat = DesignSystem.Layout.terminalSplitterHeight
            
            // 默认 1:1：未手动调整过时，终端与底部文件管理各占一半
            let defaultSftpHeight = (totalHeight - splitterHeight) / 2
            let effectiveSftpHeight = (viewModel.sftpHeight == DesignSystem.Layout.sftpDefaultHeight)
                ? defaultSftpHeight
                : viewModel.sftpHeight
            
            let maxSftpHeight = totalHeight - DesignSystem.Layout.terminalMinHeight - splitterHeight
            let sftpMin = DesignSystem.Layout.sftpMinHeight
            let sftpMax = max(maxSftpHeight, sftpMin)
            let constrainedSftpHeight = min(max(effectiveSftpHeight, sftpMin), sftpMax)
            let terminalPadding: CGFloat = 12
            let ipBarHeight: CGFloat = 32
            let terminalHeight = max(0, totalHeight - constrainedSftpHeight - splitterHeight)
            
            VStack(spacing: 0) {
                // 1. 终端区域（IP 栏半透明叠加在顶部）
                ZStack(alignment: .topTrailing) {
                    Color.black
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(0)
                    
                    XTermWebView(runner: viewModel.runner, tabID: tabID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, ipBarHeight + terminalPadding)
                        .padding(.horizontal, terminalPadding)
                        .padding(.bottom, terminalPadding)
                        .clipped()
                        .allowsHitTesting(true)
                        .zIndex(1)
                    
                    // Reconnect overlay when connection drops
                    ReconnectOverlay(
                        isConnected: viewModel.runner.isConnected,
                        isConnecting: viewModel.runner.isConnecting,
                        error: viewModel.runner.error,
                        onReconnect: { viewModel.connect() }
                    )
                    .frame(height: terminalHeight)
                    .zIndex(25)
                    
                    // Quick Actions - 右下角
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Button(action: { 
                                    withAnimation(.spring()) {
                                        viewModel.showFlowPanel.toggle()
                                        if viewModel.showFlowPanel {
                                            viewModel.showAIHelper = false
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle")
                                        Text("Flow")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.showFlowPanel ? DesignSystem.Colors.blue : DesignSystem.Colors.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(true)

                                Button(action: { 
                                    withAnimation(.spring()) {
                                        viewModel.showAIHelper.toggle()
                                        if viewModel.showAIHelper {
                                            viewModel.showFlowPanel = false
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                        Text("AI Assistant".localized)
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.showAIHelper ? Color.purple : Color.purple.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(true)
                            }
                            .padding(20)
                        }
                    }
                    .zIndex(5)

                    // AI 面板弹出
                    if viewModel.showAIHelper {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                TerminalAIOverlay(
                                    isPresented: $viewModel.showAIHelper,
                                    prompt: $viewModel.aiPrompt,
                                    isGenerating: $viewModel.isAIGenerating,
                                    steps: $viewModel.aiSteps,
                                    onGenerate: viewModel.generateAICommand,
                                    onExecuteStep: viewModel.executeAIStep
                                )
                                .padding(.trailing, 20)
                                .padding(.bottom, 60) // Shift up to be above the button
                                .allowsHitTesting(true)
                            }
                        }
                        .allowsHitTesting(true)
                        .zIndex(20)
                    }

                    // 连接状态横幅
                    if viewModel.runner.isConnecting || viewModel.showSuccessBanner {
                        HStack {
                            Spacer()
                            statusBanner
                            Spacer()
                        }
                        .padding(.top, 40)
                        .allowsHitTesting(false) // CRITICAL: Don't block terminal selection
                        .zIndex(30)
                    }
                }
                .frame(height: terminalHeight)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text("IP")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text(viewModel.connection.host.isEmpty ? "—" : viewModel.connection.host)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Button(action: copyHostToClipboard) {
                                Text("复制".localized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring()) {
                                    viewModel.toggleMonitor()
                                }
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 14))
                                    .foregroundColor(viewModel.monitorService.isVisible ? .blue : .white.opacity(0.6))
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(height: ipBarHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.15))
                        
                        if viewModel.monitorService.isVisible {
                            HStack {
                                Spacer(minLength: 0)
                                SystemMonitorView(service: viewModel.monitorService)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .allowsHitTesting(true)
                }
                .clipped()
                
                // 2. 分割线
                DraggableSplitter(
                    isDragging: $viewModel.isDragging,
                    offset: $viewModel.dragOffset,
                    onDragChanged: { translation in
                        viewModel.updateLayout(translation: translation, isEnded: false)
                    },
                    onDragEnded: { translation in
                        viewModel.updateLayout(translation: translation, isEnded: true)
                    }
                )
                .frame(height: splitterHeight)
                
                // 3. SFTP 区域
                Group {
                    if viewModel.runner.isConnected {
                        SyncedSFTPView(
                            runner: viewModel.runner,
                            connectionID: viewModel.connection.id,
                            path: $viewModel.runner.currentPath,
                            isExpanded: Binding(get: { viewModel.isSFTPViewExpanded }, set: { viewModel.toggleSFTP(expanded: $0) }),
                            onNavigate: { dir in
                                viewModel.runner.currentPath = dir
                            }
                        )
                    } else {
                        VStack {
                            if let error = viewModel.runner.error {
                                Text(error).foregroundColor(.red).padding()
                            } else {
                                ProgressView("Connecting...").padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: constrainedSftpHeight)
                .safeAreaInset(edge: .bottom) {
                    if viewModel.showFlowPanel {
                        Color.clear.frame(height: 200)
                    }
                }
                .background(DesignSystem.Colors.surface)
            }
        }
        .onAppear { viewModel.connect() }
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .bottomTrailing) {
            if viewModel.showFlowPanel {
                TerminalFlowOverlay(
                    isPresented: $viewModel.showFlowPanel,
                    groups: $viewModel.flowGroups,
                    stopOnError: $viewModel.stopFlowOnError,
                    onExecuteStep: viewModel.executeFlowStep,
                    onExecuteGroup: viewModel.executeFlowGroup,
                    onExecuteAll: viewModel.executeAllFlowGroups
                )
                .padding(.trailing, 20)
                .padding(.bottom, 16)
                .zIndex(100)
            }
        }
    }
    
    private func copyHostToClipboard() {
        let host = viewModel.connection.host
        guard !host.isEmpty else {
            ToastManager.shared.show(message: "No host to copy".localized, type: .warning)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(host, forType: .string)
        ToastManager.shared.show(message: "Copied".localized, type: .success)
    }
    
    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.runner.isConnecting {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.5).controlSize(.small)
                Text("Connecting...".localized).font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        } else if viewModel.showSuccessBanner {
            Text("Success".localized).font(.caption).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.green.opacity(0.8)).cornerRadius(12)
        }
    }

}
