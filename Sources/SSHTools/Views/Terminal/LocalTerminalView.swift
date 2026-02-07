import SwiftUI
import Combine

final class LocalTerminalViewModel: ObservableObject {
    let connection: SSHConnection
    @Published var runner: LocalTerminalRunner
    private var cancellables = Set<AnyCancellable>()
    private let pathStore = LocalTerminalPathStore.shared

    init(connection: SSHConnection) {
        self.connection = connection
        let runner = LocalTerminalRunner(connectionID: connection.id)
        self.runner = runner

        runner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        runner.$currentPath
            .sink { [weak self] path in
                guard let self else { return }
                self.pathStore.updatePath(path, for: self.connection.id)
            }
            .store(in: &cancellables)

        pathStore.updatePath(runner.currentPath, for: connection.id)
    }

    deinit {
        cancellables.removeAll()
        runner.disconnect()
    }

    func connect() {
        if !runner.isConnected {
            runner.connect()
        }
    }

    func disconnect() {
        runner.disconnect()
    }
}

struct LocalTerminalView: View {
    @StateObject private var viewModel: LocalTerminalViewModel
    private let tabID: UUID

    init(connection: SSHConnection, tabID: UUID) {
        _viewModel = StateObject(wrappedValue: LocalTerminalViewModel(connection: connection))
        self.tabID = tabID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .foregroundColor(DesignSystem.Colors.blue)
                        Text(viewModel.connection.name)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if !viewModel.runner.currentPath.isEmpty {
                        Button(action: {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(viewModel.runner.currentPath, forType: .string)
                        }) {
                            Text(viewModel.runner.currentPath)
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.runner.isConnected ? DesignSystem.Colors.green : DesignSystem.Colors.pink)
                        .frame(width: 6, height: 6)
                    Text(viewModel.runner.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(DesignSystem.Radius.small)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .frame(height: 44)
            .background(DesignSystem.Colors.surface)

            Divider()

            ZStack {
                XTermWebView(runner: viewModel.runner, tabID: tabID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipped()

                ReconnectOverlay(
                    isConnected: viewModel.runner.isConnected,
                    isConnecting: viewModel.runner.isConnecting,
                    error: viewModel.runner.error,
                    onReconnect: { viewModel.connect() }
                )
            }
        }
        .onAppear { viewModel.connect() }
        .background(DesignSystem.Colors.background)
    }
}
