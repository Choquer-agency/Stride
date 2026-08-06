import SwiftUI

/// 5-second wellness check shown right before a run starts.
/// Three sliders: sleep, energy, body. Skippable.
///
/// Logged with entry_method='pre_run'. The pre-run voice coach prompt
/// receives these values and references them in the audible send-off.
///
/// Surfaced from RunViewModel.startRun() when the athlete hasn't done a
/// morning check-in today AND has no pre_run entry in past 4h.
struct PreRunCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WellnessViewModel()
    var onComplete: (_ submitted: Bool) -> Void

    @State private var sleep: Int = 3
    @State private var energy: Int = 3
    @State private var body_: Int = 3

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)

            VStack(spacing: 6) {
                Text("Quick check")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("How's the body?")
                    .font(.title2.weight(.semibold))
            }

            VStack(spacing: 18) {
                slider(label: "Sleep", icon: "moon.fill", value: $sleep)
                slider(label: "Energy", icon: "bolt.fill", value: $energy)
                slider(label: "Body", icon: "figure.run", value: $body_, lowLabel: "Sore", highLabel: "Loose")
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        let ok = await viewModel.submitPreRun(
                            sleepQuality: sleep,
                            energy: energy,
                            soreness: 6 - body_  // body 5 (loose) → soreness 1 (low)
                        )
                        onComplete(ok)
                        dismiss()
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        Text("Done — start run")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color.stridePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(viewModel.isSubmitting)

                Button("Skip") {
                    onComplete(false)
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func slider(
        label: String,
        icon: String,
        value: Binding<Int>,
        lowLabel: String = "Low",
        highLabel: String = "High"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(Color.stridePrimary)
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value.wrappedValue)/5").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        let h = UIImpactFeedbackGenerator(style: .light); h.impactOccurred()
                        value.wrappedValue = i
                    } label: {
                        Circle()
                            .fill(value.wrappedValue >= i ? Color.stridePrimary : Color.gray.opacity(0.18))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text("\(i)")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(value.wrappedValue >= i ? .white : .secondary)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text(lowLabel).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(highLabel).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
    }
}
