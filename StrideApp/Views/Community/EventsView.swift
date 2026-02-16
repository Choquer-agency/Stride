import SwiftUI

struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if viewModel.isLoading && viewModel.activeEvents.isEmpty && viewModel.upcomingEvents.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.stridePrimary)
                        Text("Loading events...")
                            .font(.inter(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if viewModel.activeEvents.isEmpty && viewModel.upcomingEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text("No events right now")
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Check back soon for upcoming events and races.")
                            .font(.inter(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // Active Events
                    if !viewModel.activeEvents.isEmpty {
                        sectionHeader("Active Now")
                        ForEach(viewModel.activeEvents) { event in
                            NavigationLink(destination: EventDetailView(eventId: event.id)) {
                                EventCardView(event: event)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Upcoming Events
                    if !viewModel.upcomingEvents.isEmpty {
                        sectionHeader("Upcoming")
                        ForEach(viewModel.upcomingEvents) { event in
                            NavigationLink(destination: EventDetailView(eventId: event.id)) {
                                EventCardView(event: event)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.loadEvents()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack {
        EventsView()
    }
}
