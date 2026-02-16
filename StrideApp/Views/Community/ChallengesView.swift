import SwiftUI

struct ChallengesView: View {
    @StateObject private var viewModel = ChallengesViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading && viewModel.activeChallenges.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.stridePrimary)
                        Text("Loading challenges...")
                            .font(.inter(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if viewModel.activeChallenges.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text("No active challenges")
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Check back soon for new weekly races and monthly challenges.")
                            .font(.inter(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(viewModel.activeChallenges) { challenge in
                        NavigationLink(destination: ChallengeDetailView(challengeId: challenge.id)) {
                            ChallengeCardView(challenge: challenge)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.loadActiveChallenges()
        }
    }
}

#Preview {
    NavigationStack {
        ChallengesView()
    }
}
