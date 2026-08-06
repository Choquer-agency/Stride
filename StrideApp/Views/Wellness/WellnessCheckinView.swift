import SwiftUI

/// Morning wellness check-in. 4 sliders (1-5) + body chips when soreness >= 2 +
/// optional notes. Submitting fires the backend concern-check pipeline.
///
/// Surfaced from `stride://wellness/checkin` deep links and from the Run tab
/// morning card.
struct WellnessCheckinView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WellnessViewModel()

    @State private var sleep: Int = 3
    @State private var soreness: Int = 2
    @State private var motivation: Int = 3
    @State private var stress: Int = 3
    @State private var sorenessAreas: Set<String> = []
    @State private var notes: String = ""

    /// Body parts the iOS chip set mirrors (matches `_BODY_PARTS` in wellness_service.py).
    private let bodyAreas: [(label: String, key: String)] = [
        ("Calves", "calf"),
        ("Knees", "knee"),
        ("Achilles", "achilles"),
        ("IT band", "it band"),
        ("Hip flexors", "hip flexor"),
        ("Hamstrings", "hamstring"),
        ("Lower back", "lower back"),
        ("Foot", "foot"),
        ("Glutes", "glute"),
        ("Quads", "quad"),
        ("Shins", "shin"),
        ("Ankles", "ankle"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    sliderSection(label: "Sleep", systemIcon: "moon.fill", value: $sleep)
                    sliderSection(label: "Soreness", systemIcon: "bolt.fill", value: $soreness, lowLabel: "Fresh", highLabel: "Sore")
                    if soreness >= 2 {
                        bodyAreaSection
                    }
                    sliderSection(label: "Motivation", systemIcon: "flame.fill", value: $motivation)
                    sliderSection(label: "Stress", systemIcon: "waveform.path.ecg", value: $stress, lowLabel: "Calm", highLabel: "Stressed")
                    notesSection

                    if let err = viewModel.error {
                        Text(err).font(.callout).foregroundStyle(.red)
                    }

                    submitButton
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Morning check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.refreshToday() }
        .animation(.easeInOut(duration: 0.2), value: soreness)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("How are you feeling?")
                .font(.title2.weight(.semibold))
        }
    }

    private func sliderSection(
        label: String,
        systemIcon: String,
        value: Binding<Int>,
        lowLabel: String = "Bad",
        highLabel: String = "Great"
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .foregroundStyle(Color.stridePrimary)
                Text(label).font(.headline)
                Spacer()
                Text("\(value.wrappedValue) / 5")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        let h = UIImpactFeedbackGenerator(style: .light)
                        h.impactOccurred()
                        value.wrappedValue = i
                    } label: {
                        Circle()
                            .fill(value.wrappedValue >= i ? Color.stridePrimary : Color.gray.opacity(0.18))
                            .frame(width: 36, height: 36)
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
                Text(lowLabel).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text(highLabel).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var bodyAreaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayoutChips(
                items: bodyAreas.map { $0.label },
                isSelected: { label in
                    sorenessAreas.contains(bodyAreas.first(where: { $0.label == label })?.key ?? label)
                },
                onToggle: { label in
                    let key = bodyAreas.first(where: { $0.label == label })?.key ?? label
                    if sorenessAreas.contains(key) { sorenessAreas.remove(key) } else { sorenessAreas.insert(key) }
                }
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Anything to flag?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mic")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            TextField("Optional — coach reads these.", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                let ok = await viewModel.submitMorning(
                    sleepQuality: sleep,
                    soreness: soreness,
                    motivation: motivation,
                    stress: stress,
                    sorenessAreas: Array(sorenessAreas),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
                if ok { dismiss() }
            }
        } label: {
            if viewModel.isSubmitting {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .background(Color.stridePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(viewModel.isSubmitting)
    }
}

/// Simple wrap-flow chip layout (works on iOS 17+ via Layout protocol).
private struct FlowLayoutChips: View {
    let items: [String]
    let isSelected: (String) -> Bool
    let onToggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onToggle(item)
                } label: {
                    Text(item)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected(item) ? Color.stridePrimary : Color.gray.opacity(0.10))
                        .foregroundStyle(isSelected(item) ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowMaxHeight + spacing
                rowWidth = 0
                rowMaxHeight = 0
            }
            rowWidth += size.width + spacing
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
        height += rowMaxHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowMaxHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowMaxHeight + spacing
                x = bounds.minX
                rowMaxHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
    }
}
