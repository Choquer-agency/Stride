import SwiftUI

struct UserSearchView: View {
    @StateObject private var viewModel = UserSearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search runners...", text: $viewModel.query)
                    .font(.inter(size: 16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.query) { _, _ in
                        viewModel.search()
                    }
                if !viewModel.query.isEmpty {
                    Button { viewModel.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if viewModel.isLoading {
                ProgressView()
                    .tint(Color.stridePrimary)
                    .padding(.top, 40)
                Spacer()
            } else if viewModel.results.isEmpty && !viewModel.query.isEmpty && viewModel.query.count >= 2 {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text("No runners found")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                Spacer()
            } else if viewModel.results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text("Find runners to follow")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Search by display name")
                        .font(.inter(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 60)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.results) { user in
                            NavigationLink(destination: UserProfileView(userId: user.id)) {
                                UserSearchRow(user: user) {
                                    viewModel.toggleFollow(userId: user.id)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - User Search Row

struct UserSearchRow: View {
    let user: UserSearchResult
    let onToggleFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let base64 = user.profilePhotoBase64,
               let data = Data(base64Encoded: base64),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(user.displayName.prefix(1)).uppercased())
                            .font(.inter(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.inter(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.inter(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                onToggleFollow()
            } label: {
                Text(user.isFollowing ? "Following" : "Follow")
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundStyle(user.isFollowing ? Color.secondary : Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(user.isFollowing ? Color(.tertiarySystemFill) : Color.stridePrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
