import SwiftUI

/// Garmin integration row + status, designed to drop into ProfileView's settings List.
///
/// Wire it into SettingsSectionsView by adding the `IntegrationsSection()` view as
/// another `Section` in the body. It manages its own ViewModel and refreshes on
/// stride://garmin/connected deep links.
struct IntegrationsSection: View {
    @StateObject private var viewModel = GarminViewModel()
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingDisconnectConfirm = false

    var body: some View {
        Section {
            HStack {
                Label("Garmin", systemImage: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
                Spacer()
                statusIndicator
            }

            if viewModel.isConnected {
                if viewModel.backfillRunning {
                    backfillProgressRow
                }
                Button {
                    Task { await viewModel.forceRefreshGarmin() }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .disabled(viewModel.actionInFlight)

                Button(role: .destructive) {
                    showingDisconnectConfirm = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .foregroundStyle(.red, .red)
                }
                .disabled(viewModel.actionInFlight)
            } else {
                Button {
                    viewModel.openConnectURL()
                } label: {
                    Label("Connect Garmin", systemImage: "link")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Integrations")
        } footer: {
            if viewModel.isConnected, let connectedAt = viewModel.status?.connectedAt {
                Text("Connected \(connectedAt.formatted(date: .abbreviated, time: .shortened)). Stride uses your Garmin data to coach you continuously.")
            } else {
                Text("Connect Garmin to unlock continuous coaching — your runs and recovery flow into Stride automatically.")
            }
        }
        .task { await viewModel.refreshStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.refreshStatus() }
            }
        }
        .onChange(of: deepLinkRouter.pendingLink) { _, link in
            if case .garminConnected = link {
                Task { await viewModel.refreshStatus() }
                deepLinkRouter.consume()
            }
        }
        .confirmationDialog(
            "Disconnect Garmin?",
            isPresented: $showingDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your historical data stays — we just stop pulling new runs and metrics. You can reconnect anytime.")
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if viewModel.isLoading {
            ProgressView().controlSize(.small)
        } else if viewModel.isConnected {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Connected").foregroundStyle(.secondary).font(.subheadline)
            }
        } else {
            HStack(spacing: 6) {
                Circle().fill(Color.gray).frame(width: 8, height: 8)
                Text("Not connected").foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var backfillProgressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Importing 90 days of history", systemImage: "arrow.down.circle")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
                Spacer()
                Text("\(viewModel.backfillProgress)%")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: Double(viewModel.backfillProgress) / 100.0)
                .tint(Color.stridePrimary)
        }
    }
}
