import SwiftUI

/// Top-level entry hub for logging a gym session. Two large tap targets:
/// "Quick log" and "Log details." Recent sessions surfaced below.
struct StrengthLogHubView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @StateObject private var viewModel = StrengthViewModel()

    @State private var showQuickLog = false
    @State private var showDetailedLog = false
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(appearance == .white ? "StrideLogo" : "StrideLogoDark")
                            .resizable().scaledToFit().frame(width: 120)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").frame(width: 40, height: 40)
                                .background(style.card, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Close")
                    }
                    headerSection
                    twoButtons
                    if !viewModel.sessions.isEmpty {
                        recentSection
                    }
                    if let err = viewModel.error {
                        Text(err).font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background { StridePageBackdrop().ignoresSafeArea() }
            .foregroundStyle(style.ink)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await viewModel.loadSessions() }
        .sheet(isPresented: $showQuickLog) {
            StrengthQuickLogView(viewModel: viewModel) { showQuickLog = false }
        }
        .sheet(isPresented: $showDetailedLog) {
            StrengthSessionView(viewModel: viewModel) { showDetailedLog = false }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY / STRENGTH").font(.runEyebrow(11)).foregroundStyle(style.muted)
            Text("GYM SESSION").font(.barlowCondensed(size: 43))
        }
    }

    private var twoButtons: some View {
        HStack(spacing: 12) {
            entryButton(label: "Quick log", icon: "checkmark.circle.fill", subtitle: "Done as prescribed") {
                showQuickLog = true
            }
            entryButton(label: "Log details", icon: "list.bullet.rectangle", subtitle: "Sets & reps") {
                showDetailedLog = true
            }
        }
    }

    private func entryButton(label: String, icon: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 25)).foregroundStyle(style.accent)
                Text(label.uppercased()).font(.barlowCondensed(size: 25)).foregroundStyle(style.ink)
                Text(subtitle.uppercased()).font(.runEyebrow(9)).foregroundStyle(style.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .stridePageCard(style)
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SESSIONS").font(.barlowCondensed(size: 25))
                .foregroundStyle(style.ink)
            ForEach(viewModel.sessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date)
                            .font(.inter(size: 14, weight: .medium))
                        Text(session.quickLogged ? "Quick log" : "Detailed (\(session.durationMinutes ?? 0) min)")
                            .font(.runEyebrow(10)).foregroundStyle(style.muted)
                    }
                    Spacer()
                    if let rpe = session.perceivedEffort {
                        Text("RPE \(rpe)")
                            .font(.runEyebrow(10)).foregroundStyle(style.muted)
                    }
                }
                .padding(10)
                .stridePageCard(style, radius: 18)
            }
        }
    }
}
