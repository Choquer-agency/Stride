import SwiftUI

struct ActivityFeedView: View {
    @StateObject private var viewModel = ActivityFeedViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toggle
            Picker("Feed", selection: $viewModel.followingOnly) {
                Text("Following").tag(true)
                Text("Everyone").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: viewModel.followingOnly) { _, _ in
                viewModel.loadFeed()
            }

            if viewModel.isLoading && viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.stridePrimary)
                    Text("Loading feed...")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.followingOnly ? "person.2.slash" : "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text(viewModel.followingOnly ? "No activity from people you follow" : "No activity yet")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    if viewModel.followingOnly {
                        Text("Follow runners to see their activity here")
                            .font(.inter(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.items) { item in
                            ActivityCardView(item: item, showUser: true)

                            // Load more when near bottom
                            if item.id == viewModel.items.last?.id {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear { viewModel.loadMore() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Activity Feed")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.loadFeed() }
    }
}

// MARK: - Activity Card View

struct ActivityCardView: View {
    let item: ActivityFeedItem
    let showUser: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Activity icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: item.activityIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                if showUser {
                    Text(item.displayName)
                        .font(.inter(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(item.activityDescription)
                    .font(.inter(size: 14))
                    .foregroundStyle(showUser ? .secondary : .primary)

                Text(item.timeAgo)
                    .font(.inter(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var iconColor: Color {
        switch item.activityType {
        case "run": return .green
        case "achievement": return .orange
        case "pb": return .yellow
        case "follow": return .blue
        default: return .gray
        }
    }
}
