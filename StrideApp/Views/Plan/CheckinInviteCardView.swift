import SwiftUI

/// Plan-tab card shown while a weekly check-in is open ("invited"/"in_progress").
/// Tapping it opens the typeform flow; the card refreshes on appear and after
/// the flow dismisses.
struct CheckinInviteCardView: View {
    @State private var checkin: WeeklyCheckinDTO?
    @State private var showFlow = false

    var body: some View {
        Group {
            if let checkin, checkin.isOpen {
                Button {
                    showFlow = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.stridePrimary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sit down with your coach")
                                .font(.interSemibold(15))
                                .foregroundStyle(.primary)
                            Text(checkin.status == "in_progress"
                                 ? "Pick up your check-in where you left off"
                                 : "Two minutes on your week — then next week gets built around it")
                                .font(.interBody(13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color.stridePrimary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.stridePrimary.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .task { await refresh() }
        .fullScreenCover(isPresented: $showFlow, onDismiss: { Task { await refresh() } }) {
            WeeklyCheckinFlowView()
        }
    }

    private func refresh() async {
        checkin = try? await APIService.shared.fetchCurrentCheckin()
    }
}
