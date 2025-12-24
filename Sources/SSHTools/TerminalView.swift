import SwiftUI

struct TerminalView: View {
    @StateObject private var viewModel: TerminalViewModel
    @Namespace private var bottomID
    
    init(connection: SSHConnection) {
        _viewModel = StateObject(wrappedValue: TerminalViewModel(connection: connection))
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let constrainedSftpHeight = min(max(viewModel.sftpHeight, DesignSystem.Layout.sftpMinHeight), max(totalHeight - DesignSystem.Layout.terminalMinHeight, DesignSystem.Layout.sftpMinHeight))
            let terminalHeight = max(0, totalHeight - constrainedSftpHeight)
            
            VStack(spacing: 0) {
                // Terminal Area
                SwiftTermView(runner: viewModel.runner)
                    .frame(height: terminalHeight)
                    .id(bottomID)
                    .overlay(alignment: .topTrailing) {
                        HStack {
                            // Monitor Toggle
                            Button(action: { 
                                viewModel.toggleMonitor()
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 14))
                                    .foregroundColor(viewModel.monitorService.isVisible ? .blue : .secondary.opacity(0.5))
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            
                            if viewModel.monitorService.isVisible {
                                SystemMonitorView(service: viewModel.monitorService)
                                    .padding(.trailing, 10)
                                    .padding(.top, 40) // Below the toggle button
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        TerminalAIOverlay(
                            isPresented: $viewModel.showAIHelper,
                            prompt: $viewModel.aiPrompt,
                            isGenerating: $viewModel.isAIGenerating,
                            steps: $viewModel.aiSteps,
                            onGenerate: viewModel.generateAICommand,
                            onExecuteStep: viewModel.executeAIStep
                        )
                    }
                    .overlay {
                        ReconnectOverlay(
                            isConnected: viewModel.runner.isConnected,
                            error: viewModel.runner.error,
                            onReconnect: { viewModel.runner.connect(connection: viewModel.connection) }
                        )
                        .background(DesignSystem.Colors.background.opacity(0.5)) // Slightly dim background
                    }
                
                // Draggable Divider
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
                
                // File Browser Area
                Group {
                    if viewModel.runner.isConnected {
                        SyncedSFTPView(
                            runner: viewModel.runner,
                            path: $viewModel.runner.currentPath,
                            isExpanded: Binding(
                                get: { viewModel.isSFTPViewExpanded },
                                set: { expanded in
                                    viewModel.toggleSFTP(expanded: expanded)
                                }
                            ),
                            onNavigate: { dir in
                                viewModel.runner.sendRaw("cd \"\(dir)\"\r")
                            }
                        )
                    } else {
                        VStack {
                            if let error = viewModel.runner.error {
                                Text("Error: \(error)")
                                    .foregroundColor(DesignSystem.Colors.pink)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            } else {
                                Text("Connecting...".localized)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: constrainedSftpHeight)
                .background(DesignSystem.Colors.surface)
            }
        }
        .onAppear {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .navigationTitle("\(viewModel.connection.name) (\(viewModel.runner.isConnected ? "Connected".localized : "Disconnected".localized))")
        .background(DesignSystem.Colors.background)
    }
}