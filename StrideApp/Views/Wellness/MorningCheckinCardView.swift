import SwiftUI

/// Pinned card on the Run tab when the athlete hasn't done a morning wellness
/// check-in today. Tap → presents WellnessCheckinView. Auto-hides once submitted.
///
/// Drop into RunLobbyView body:
///     MorningCheckinCardView()
struct MorningCheckinCardView: View {
    @StateObject private var viewModel = WellnessViewModel()
    @State private var showingSheet = false

    var body: some View {
        Group {
            if viewModel.needsMorning {
                cardContent
            } else {
                EmptyView()
            }
        }
        .task { await viewModel.refreshToday() }
        .sheet(isPresented: $showingSheet) {
            WellnessCheckinView()
                .onDisappear { Task { await viewModel.refreshToday() } }
        }
    }

    private var cardContent: some View {
        Button { showingSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(Color.stridePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning check-in")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("30 seconds. Coach reads it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.stridePrimary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.stridePrimary.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
