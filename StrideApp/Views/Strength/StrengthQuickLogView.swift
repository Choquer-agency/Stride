import SwiftUI

/// Single-tap "Done as prescribed" log with optional RPE slider.
struct StrengthQuickLogView: View {
    @ObservedObject var viewModel: StrengthViewModel
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Int = 6
    @State private var includeRPE: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 16)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(Color.stridePrimary)

                VStack(spacing: 8) {
                    Text("DONE AS PRESCRIBED")
                        .font(.barlowCondensed(size: 42))
                    Text("One tap closes today's gym session.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if includeRPE {
                    VStack(spacing: 10) {
                        Text("PERCEIVED EFFORT")
                            .font(.runEyebrow(11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(1...10, id: \.self) { i in
                                Button {
                                    let h = UIImpactFeedbackGenerator(style: .light); h.impactOccurred()
                                    rpe = i
                                } label: {
                                    Circle()
                                        .fill(rpe >= i ? Color.stridePrimary : Color.gray.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                        .overlay(Text("\(i)").font(.caption.weight(.medium)).foregroundStyle(rpe >= i ? .white : .secondary))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }

                Button { includeRPE.toggle() } label: {
                    Text(includeRPE ? "Skip effort rating" : "Add effort rating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        let ok = await viewModel.quickLog(perceivedEffort: includeRPE ? rpe : nil)
                        if ok { onDone(); dismiss() }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        Text("SAVE SESSION")
                            .font(.barlowCondensed(size: 23, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color.stridePrimary)
                .clipShape(Capsule())
                .disabled(viewModel.isSubmitting)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle("QUICK LOG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .strideSecondaryScreen()
    }
}
