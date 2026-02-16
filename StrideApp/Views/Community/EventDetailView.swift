import SwiftUI

struct EventDetailView: View {
    let eventId: String
    @StateObject private var viewModel = EventsViewModel()
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        ScrollView {
            if viewModel.isLoadingDetail && viewModel.detail == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.stridePrimary)
                    Text("Loading event...")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else if let detail = viewModel.detail {
                VStack(alignment: .leading, spacing: 0) {
                    // Banner
                    bannerSection(detail)

                    VStack(alignment: .leading, spacing: 20) {
                        // Title + info
                        titleSection(detail)

                        // Register button
                        registerButton(detail)

                        // Description
                        if let description = detail.description, !description.isEmpty {
                            Text(description)
                                .font(.inter(size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }

                        // Your result
                        if detail.isRegistered {
                            yourResultSection(detail)
                        }

                        // Leaderboard
                        if !detail.leaderboard.isEmpty {
                            leaderboardSection(detail)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadDetail(eventId: eventId)
        }
    }

    // MARK: - Banner

    private func bannerSection(_ detail: EventDetailResponse) -> some View {
        Group {
            if let bannerUrl = detail.bannerImageUrl, let url = URL(string: bannerUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(hex: detail.primaryColor ?? "#FF2617") ?? Color.stridePrimary)
                }
                .frame(height: 200)
                .clipped()
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: detail.primaryColor ?? "#FF2617") ?? Color.stridePrimary,
                                Color(hex: detail.accentColor ?? "#333333") ?? Color(.systemGray)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: detail.isRace ? "flag.checkered" : "person.3")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
        }
    }

    // MARK: - Title

    private func titleSection(_ detail: EventDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.title)
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label {
                    Text(detail.timeRemaining)
                        .font(.inter(size: 13))
                } icon: {
                    Image(systemName: "clock")
                }

                Label {
                    Text("\(detail.participantCount) runners")
                        .font(.inter(size: 13))
                } icon: {
                    Image(systemName: "person.2")
                }

                if let category = detail.distanceCategory {
                    Label {
                        Text(category)
                            .font(.inter(size: 13))
                    } icon: {
                        Image(systemName: "ruler")
                    }
                }
            }
            .foregroundStyle(.secondary)

            // Sponsor
            if let sponsor = detail.sponsorName {
                HStack(spacing: 8) {
                    if let logoUrl = detail.sponsorLogoUrl, let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(maxWidth: 32, maxHeight: 20)
                    }
                    Text("Sponsored by \(sponsor)")
                        .font(.inter(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Register Button

    private func registerButton(_ detail: EventDetailResponse) -> some View {
        Button {
            if detail.isRegistered {
                viewModel.unregister(eventId: eventId)
            } else {
                viewModel.register(eventId: eventId)
            }
        } label: {
            HStack {
                if viewModel.isRegistering {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: detail.isRegistered ? "checkmark.circle.fill" : "plus.circle")
                    Text(detail.isRegistered ? "Registered" : "Register")
                }
            }
            .font(.inter(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(detail.isRegistered ? Color.green : (Color(hex: detail.primaryColor ?? "#FF2617") ?? Color.stridePrimary))
            .cornerRadius(12)
        }
        .disabled(viewModel.isRegistering)
        .padding(.horizontal, 16)
    }

    // MARK: - Your Result

    private func yourResultSection(_ detail: EventDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Result")
                .font(.inter(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                if detail.isRace, let seconds = detail.yourBestTimeSeconds {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best Time")
                            .font(.inter(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(formatTime(seconds: seconds))
                            .font(.barlowCondensed(size: 28, weight: .semibold))
                            .foregroundStyle(Color(hex: detail.primaryColor ?? "#FF2617") ?? Color.stridePrimary)
                    }
                } else if let km = detail.yourTotalDistanceKm, km > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Distance")
                            .font(.inter(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.1f km", km))
                            .font(.barlowCondensed(size: 28, weight: .semibold))
                            .foregroundStyle(Color(hex: detail.primaryColor ?? "#FF2617") ?? Color.stridePrimary)
                    }
                } else {
                    Text("No qualifying runs yet")
                        .font(.inter(size: 14))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Leaderboard

    private func leaderboardSection(_ detail: EventDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.inter(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 2) {
                ForEach(detail.leaderboard) { entry in
                    LeaderboardCardView(
                        entry: entry,
                        isCurrentUser: false,
                        isDistanceLeaderboard: !detail.isRace
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EventDetailView(eventId: "test")
            .environmentObject(AuthService.shared)
    }
}
