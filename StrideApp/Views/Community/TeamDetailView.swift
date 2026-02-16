import SwiftUI

struct TeamDetailView: View {
    let teamId: String
    @StateObject private var viewModel = TeamsViewModel()
    @State private var showLeaveAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if viewModel.isLoadingDetail {
                ProgressView()
                    .tint(Color.stridePrimary)
                    .padding(.top, 60)
            } else if let detail = viewModel.teamDetail {
                VStack(spacing: 20) {
                    teamHeader(detail)
                    inviteCodeSection(detail)
                    leaderboardSection(detail)
                    leaveButton(detail)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle(viewModel.teamDetail?.name ?? "Team")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadDetail(teamId: teamId) }
        .alert("Leave Team", isPresented: $showLeaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                viewModel.leaveTeam(teamId: teamId)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to leave this team?")
        }
    }

    // MARK: - Team Header

    private func teamHeader(_ detail: TeamDetailResponse) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            Text(detail.name)
                .font(.inter(size: 22, weight: .bold))

            if let desc = detail.description, !desc.isEmpty {
                Text(desc)
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("\(detail.memberCount) member\(detail.memberCount == 1 ? "" : "s")")
                .font(.inter(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Invite Code

    private func inviteCodeSection(_ detail: TeamDetailResponse) -> some View {
        Group {
            if let code = detail.inviteCode {
                VStack(spacing: 8) {
                    Text("Invite Code")
                        .font(.inter(size: 13))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(code)
                            .font(.barlowCondensed(size: 28, weight: .semibold))
                            .tracking(4)

                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.stridePrimary)
                        }
                    }

                    Button {
                        let activityVC = UIActivityViewController(
                            activityItems: ["Join my team on Stride! Use invite code: \(code)"],
                            applicationActivities: nil
                        )
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = scene.windows.first,
                           let rootVC = window.rootViewController {
                            rootVC.present(activityVC, animated: true)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.inter(size: 14, weight: .medium))
                            .foregroundStyle(Color.stridePrimary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Leaderboard

    private func leaderboardSection(_ detail: TeamDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.inter(size: 16, weight: .semibold))

            ForEach(Array(detail.leaderboard.enumerated()), id: \.element.userId) { index, member in
                HStack(spacing: 12) {
                    Text("#\(index + 1)")
                        .font(.barlowCondensed(size: 18, weight: .semibold))
                        .foregroundStyle(index < 3 ? Color.stridePrimary : .secondary)
                        .frame(width: 32)

                    if let base64 = member.profilePhotoBase64,
                       let data = Data(base64Encoded: base64),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(member.displayName.prefix(1)).uppercased())
                                    .font(.inter(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.displayName)
                            .font(.inter(size: 14, weight: .medium))
                        HStack(spacing: 2) {
                            if member.role == "owner" {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                            Text(member.role == "owner" ? "Owner" : "Member")
                                .font(.inter(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Text(String(format: "%.0f km", member.totalDistanceKm))
                        .font(.barlowCondensed(size: 18, weight: .semibold))
                        .foregroundStyle(Color.stridePrimary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Leave Button

    private func leaveButton(_ detail: TeamDetailResponse) -> some View {
        Group {
            if detail.isMember {
                Button {
                    showLeaveAlert = true
                } label: {
                    Text("Leave Team")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
    }
}
