import SwiftUI

struct EventCardView: View {
    let event: EventResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner image
            if let bannerUrl = event.bannerImageUrl, let url = URL(string: bannerUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(event.parsedPrimaryColor ?? Color.stridePrimary)
                        .overlay(
                            Image(systemName: event.typeIcon)
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
                .frame(height: 140)
                .clipped()
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                event.parsedPrimaryColor ?? Color.stridePrimary,
                                event.parsedAccentColor ?? Color(.systemGray)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)
                    .overlay(
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.typeLabel.uppercased())
                                    .font(.inter(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                if let category = event.distanceCategory {
                                    Text(category)
                                        .font(.barlowCondensed(size: 28, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Spacer()
                            Image(systemName: event.typeIcon)
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(16)
                    )
            }

            // Info section
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            Label(event.dateRange, systemImage: "calendar")
                            Label("\(event.participantCount)", systemImage: "person.2")
                        }
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Sponsor logo
                    if let logoUrl = event.sponsorLogoUrl, let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(maxWidth: 48, maxHeight: 28)
                    }
                }

                HStack {
                    if event.isFeatured {
                        Text("FEATURED")
                            .font(.inter(size: 10, weight: .bold))
                            .foregroundStyle(Color.stridePrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.stridePrimary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(event.timeRemaining)
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if event.isRegistered {
                        Label("Registered", systemImage: "checkmark.circle.fill")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}
