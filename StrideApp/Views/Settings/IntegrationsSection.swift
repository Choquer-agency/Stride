import SwiftUI

/// Garmin integration row + status, designed to drop into ProfileView's settings List.
///
/// Wire it into SettingsSectionsView by adding the `IntegrationsSection()` view as
/// another `Section` in the body. It manages its own ViewModel and refreshes on
/// stride://garmin/connected deep links.
struct IntegrationsSection: View {
    @StateObject private var viewModel = GarminViewModel()
    @StateObject private var fitbitViewModel = FitbitViewModel()
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingDisconnectConfirm = false
    @State private var showingFitbitDisconnectConfirm = false

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

            // ── Fitbit (Google Health API) ─────────────────────────────
            if fitbitViewModel.isConnected {
                NavigationLink {
                    FitbitDashboardView()
                } label: {
                    HStack {
                        Label("Fitbit", systemImage: "heart.circle")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                        Spacer()
                        fitbitStatusIndicator
                    }
                }
            } else {
                HStack {
                    Label("Fitbit", systemImage: "heart.circle")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    fitbitStatusIndicator
                }
            }

            if fitbitViewModel.isConnected {
                if fitbitViewModel.backfillRunning {
                    fitbitBackfillProgressRow
                }
                Button {
                    Task { await fitbitViewModel.forceRefresh() }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .disabled(fitbitViewModel.actionInFlight)

                Button(role: .destructive) {
                    showingFitbitDisconnectConfirm = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .foregroundStyle(.red, .red)
                }
                .disabled(fitbitViewModel.actionInFlight)
            } else {
                Button {
                    fitbitViewModel.openConnectURL()
                } label: {
                    Label("Connect Fitbit", systemImage: "link")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let error = fitbitViewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Integrations")
        } footer: {
            if viewModel.isConnected || fitbitViewModel.isConnected {
                Text("Stride pulls your runs, sleep, HRV and resting heart rate around the clock so the coach can react to how you're actually recovering.")
            } else {
                Text("Connect your watch to unlock continuous coaching — your runs and recovery flow into Stride automatically.")
            }
        }
        .task {
            await viewModel.refreshStatus()
            await fitbitViewModel.refreshStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.refreshStatus()
                    await fitbitViewModel.refreshStatus()
                }
            }
        }
        .onChange(of: deepLinkRouter.pendingLink) { _, link in
            if case .garminConnected = link {
                Task { await viewModel.refreshStatus() }
                deepLinkRouter.consume()
            }
            if case .fitbitConnected = link {
                Task { await fitbitViewModel.refreshStatus() }
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
        .confirmationDialog(
            "Disconnect Fitbit?",
            isPresented: $showingFitbitDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await fitbitViewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your historical data stays — we just stop pulling new runs and vitals. You can reconnect anytime.")
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
    private var fitbitStatusIndicator: some View {
        if fitbitViewModel.isLoading {
            ProgressView().controlSize(.small)
        } else if fitbitViewModel.isConnected {
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
    private var fitbitBackfillProgressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Importing 90 days of history", systemImage: "arrow.down.circle")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
                Spacer()
                Text("\(fitbitViewModel.backfillProgress)%")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: Double(fitbitViewModel.backfillProgress) / 100.0)
                .tint(Color.stridePrimary)
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
