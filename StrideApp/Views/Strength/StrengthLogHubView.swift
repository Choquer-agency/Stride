import SwiftUI

/// Top-level entry hub for logging a gym session. Two large tap targets:
/// "Quick log" and "Log details." Recent sessions surfaced below.
struct StrengthLogHubView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = StrengthViewModel()

    @State private var showQuickLog = false
    @State private var showDetailedLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
            .navigationTitle("Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
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
            Text("Today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("Gym session")
                .font(.title2.weight(.semibold))
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
                Image(systemName: icon).font(.title2).foregroundStyle(Color.stridePrimary)
                Text(label).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.sessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date)
                            .font(.callout.weight(.medium))
                        Text(session.quickLogged ? "Quick log" : "Detailed (\(session.durationMinutes ?? 0) min)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let rpe = session.perceivedEffort {
                        Text("RPE \(rpe)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
