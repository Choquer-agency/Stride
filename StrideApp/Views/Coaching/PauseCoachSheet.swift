import SwiftUI

/// Pause-coach options sheet. Surfaced from Profile → "Pause coach" or via a
/// quick-action button on the Run tab.
struct PauseCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PauseCoachViewModel()

    @State private var pendingChoice: PauseChoice?

    enum PauseChoice {
        case days(Int)
        case untilResume

        var label: String {
            switch self {
            case .days(let d): return "\(d) day\(d == 1 ? "" : "s")"
            case .untilResume: return "Until I resume"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isPaused {
                    pausedView
                } else {
                    optionsView
                }

                if let err = viewModel.error {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .navigationTitle("Pause coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.refresh() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            Button(confirmationButtonLabel, role: .destructive) {
                Task {
                    if let choice = pendingChoice {
                        await applyChoice(choice)
                    }
                    pendingChoice = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingChoice = nil }
        } message: {
            Text("Coach will go silent for non-critical signals. Critical-pattern flags (HRV crash + missed workouts, severe under-fueling) will still notify after a 24-hour grace.")
        }
    }

    // MARK: - Sub-views

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How long?")
                .font(.headline)

            ForEach([PauseChoice.days(3), .days(7), .untilResume], id: \.label) { choice in
                Button {
                    pendingChoice = choice
                } label: {
                    HStack {
                        Text(choice.label).font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.primary)
                }
                .disabled(viewModel.actionInFlight)
            }

            Text("Coach won't fire weekly reviews, post-run analyses, or proposed adjustments while paused. Critical patterns still escalate after 24 hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var pausedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.stridePrimary)
            Text("Coach is paused")
                .font(.title2.weight(.semibold))
            if let desc = viewModel.pausedUntilDescription {
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await viewModel.resume()
                    dismiss()
                }
            } label: {
                Text("Resume coaching")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.stridePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.actionInFlight)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Confirmation plumbing

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingChoice != nil },
            set: { if !$0 { pendingChoice = nil } }
        )
    }

    private var confirmationTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .days(let d): return "Pause coach for \(d) day\(d == 1 ? "" : "s")?"
        case .untilResume: return "Pause coach until you resume?"
        }
    }

    private var confirmationButtonLabel: String {
        guard let choice = pendingChoice else { return "Pause" }
        return "Pause \(choice.label.lowercased())"
    }

    private func applyChoice(_ choice: PauseChoice) async {
        switch choice {
        case .days(let d):
            await viewModel.pause(durationDays: d)
        case .untilResume:
            await viewModel.pause(untilResume: true)
        }
        if !viewModel.isPaused { return }
        dismiss()
    }
}
