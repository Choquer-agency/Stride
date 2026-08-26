import SwiftUI
import Charts

/// Fitbit vitals dashboard — reached by tapping the Fitbit row in Integrations.
///
/// Shows the most recent heart-rate reading (fresh from Google, current as of
/// the watch's last cloud sync), the last 24h HR curve, and 14-day trends for
/// resting HR, overnight HRV and sleep — the same vitals the coach reads.
struct FitbitDashboardView: View {
    @State private var vitals: FitbitVitalsDTO?
    @State private var isLoading = true
    @State private var error: String?

    // Live BLE broadcast test — connects to the watch's "Share heart rate"
    // broadcast so the user can verify the Bluetooth path without starting a run.
    @ObservedObject private var hrManager = HeartRateManager.shared
    @State private var dashboardStartedScan = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                liveBroadcastCard
                if let vitals {
                    liveHeartRateCard(vitals)
                    if !vitals.todayHeartRate.isEmpty {
                        heartRateCurveCard(vitals)
                    }
                    dailyTrendsCard(vitals)
                } else if isLoading {
                    ProgressView("Pulling your vitals…")
                        .padding(.top, 80)
                } else if let error {
                    ContentUnavailableView(
                        "Couldn't load vitals",
                        systemImage: "heart.slash",
                        description: Text(error)
                    )
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("Fitbit Vitals")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onAppear {
            // Start scanning for the watch broadcast unless a run already owns it
            if !hrManager.isConnected && !hrManager.isScanning {
                dashboardStartedScan = true
                hrManager.startScanning()
            }
        }
        .onDisappear {
            // Only tear down a scan this screen started — never a run's capture
            if dashboardStartedScan {
                hrManager.stopAndDisconnect()
                dashboardStartedScan = false
            }
        }
    }

    // MARK: - Live Bluetooth broadcast card

    @ViewBuilder
    private var liveBroadcastCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(hrManager.isConnected ? Color.green : Color.secondary)
                Text("LIVE BROADCAST")
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
            }

            if hrManager.isConnected {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.stridePrimary)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(hrManager.currentBPM.map { "\($0)" } ?? "--")
                        .font(.barlowCondensed(size: 64, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("bpm")
                        .font(.inter(size: 16))
                        .foregroundStyle(.secondary)
                }
                Text("Connected to \(hrManager.deviceName ?? "your watch") — this is the same live signal you'll see during runs.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else if hrManager.bluetoothUnavailable {
                Text("Bluetooth is unavailable. Check iPhone Settings → Stride → Bluetooth, and that Bluetooth is on.")
                    .font(.inter(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your watch's broadcast…")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Text("On the watch, make sure \"Share heart rate\" is on (Always visible works best).")
                    .font(.inter(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.strideCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.strideBorder, lineWidth: 1))
    }

    private func load() async {
        do {
            vitals = try await APIService.shared.fitbitVitals()
            error = nil
        } catch {
            self.error = "Check your connection and pull to retry."
        }
        isLoading = false
    }

    // MARK: - Cards

    @ViewBuilder
    private func liveHeartRateCard(_ v: FitbitVitalsDTO) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.stridePrimary)
                Text("LAST CLOUD SYNC")
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
            }
            if let bpm = v.latestBpm {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(bpm)")
                        .font(.barlowCondensed(size: 64, weight: .bold))
                        .foregroundStyle(Color.stridePrimary)
                    Text("bpm")
                        .font(.inter(size: 16))
                        .foregroundStyle(.secondary)
                }
                if let at = v.latestAt {
                    Text("as of \(at.formatted(.relative(presentation: .named)))")
                        .font(.inter(size: 13))
                        .foregroundStyle(.secondary)
                }
                Text("From Google's cloud — updates when your watch syncs to the Fitbit app. The live broadcast above is real-time.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            } else {
                Text("No recent samples — open the Fitbit app to sync your watch.")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.strideCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.strideBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func heartRateCurveCard(_ v: FitbitVitalsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 24 hours")
                .font(.inter(size: 14, weight: .semibold))
            Chart(v.todayHeartRate) { sample in
                LineMark(
                    x: .value("Time", sample.at),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(Color.stridePrimary)
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.strideCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.strideBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func dailyTrendsCard(_ v: FitbitVitalsDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Last 14 days")
                .font(.inter(size: 14, weight: .semibold))

            if v.daily.isEmpty {
                Text("Daily vitals will appear here after your first overnight sync.")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                trendRow(
                    title: "Resting heart rate",
                    unit: "bpm",
                    points: v.daily.compactMap { day in
                        day.restingHeartRate.map { (day.date, Double($0)) }
                    }
                )
                trendRow(
                    title: "Overnight HRV",
                    unit: "ms",
                    points: v.daily.compactMap { day in
                        day.hrvOvernight.map { (day.date, $0) }
                    }
                )
                trendRow(
                    title: "Sleep",
                    unit: "h",
                    points: v.daily.compactMap { day in
                        day.sleepDurationMinutes.map { (day.date, Double($0) / 60.0) }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.strideCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.strideBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func trendRow(title: String, unit: String, points: [(String, Double)]) -> some View {
        if points.isEmpty {
            HStack {
                Text(title).font(.inter(size: 13))
                Spacer()
                Text("No data yet").font(.inter(size: 13)).foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.inter(size: 13))
                    Spacer()
                    if let latest = points.first {
                        Text(latest.1.formatted(.number.precision(.fractionLength(unit == "h" ? 1 : 0))))
                            .font(.barlowCondensed(size: 22, weight: .semibold))
                        Text(unit).font(.inter(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Chart(Array(points.reversed().enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Day", point.0),
                        y: .value(title, point.1)
                    )
                    .foregroundStyle(Color.stridePrimary.opacity(0.8))
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 44)
            }
        }
    }
}
