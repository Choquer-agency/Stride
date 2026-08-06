import SwiftUI

/// Post-profile-setup gate that asks the athlete to connect Garmin.
/// Skippable. Wire from ProfileSetupView's success handler:
///
///     .sheet(isPresented: $showConnectGarmin) {
///         ConnectGarminView(onDone: { showConnectGarmin = false })
///     }
///
/// Once connected, the athlete returns via stride://garmin/connected which is
/// observed by the DeepLinkRouter — this view auto-dismisses on connect.
struct ConnectGarminView: View {
    var onDone: () -> Void

    @StateObject private var viewModel = GarminViewModel()
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 16)

            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Color.stridePrimary)

            VStack(spacing: 12) {
                Text("Connect Garmin")
                    .font(.largeTitle.bold())

                Text("Stride coaches you continuously by watching your training and recovery — HRV, sleep, splits, the whole picture. Connect Garmin once and the rest is automatic.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 14) {
                bullet("Workouts sync the moment they finish")
                bullet("Recovery (HRV, sleep, RHR) flows in overnight")
                bullet("90 days of history imported on connect")
                bullet("Coach adapts your plan when something's off")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    viewModel.openConnectURL()
                } label: {
                    Text("Connect Garmin")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.stridePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.actionInFlight)

                Button("Skip for now") {
                    onDone()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .task { await viewModel.refreshStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.refreshStatus() }
            }
        }
        .onChange(of: viewModel.isConnected) { _, connected in
            if connected { onDone() }
        }
        .onChange(of: deepLinkRouter.pendingLink) { _, link in
            if case .garminConnected = link {
                Task { await viewModel.refreshStatus() }
                deepLinkRouter.consume()
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.stridePrimary)
                .font(.body)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}
