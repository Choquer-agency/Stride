import SwiftUI

struct TeamsView: View {
    @StateObject private var viewModel = TeamsViewModel()
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false

    // Create form
    @State private var newTeamName = ""
    @State private var newTeamDescription = ""

    // Join form
    @State private var joinCode = ""

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.teams.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.stridePrimary)
                    Text("Loading teams...")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.teams.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text("No teams yet")
                        .font(.inter(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Create a team or join one with an invite code")
                        .font(.inter(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.teams) { team in
                            NavigationLink(destination: TeamDetailView(teamId: team.id)) {
                                TeamCardView(team: team)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showJoinSheet = true
                } label: {
                    Image(systemName: "link")
                }
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { viewModel.loadMyTeams() }
        .sheet(isPresented: $showCreateSheet) {
            createTeamSheet
        }
        .sheet(isPresented: $showJoinSheet) {
            joinTeamSheet
        }
    }

    // MARK: - Create Team Sheet

    private var createTeamSheet: some View {
        NavigationStack {
            Form {
                Section("Team Name") {
                    TextField("e.g. Morning Runners", text: $newTeamName)
                        .font(.inter(size: 16))
                }
                Section("Description (Optional)") {
                    TextField("What's your team about?", text: $newTeamDescription, axis: .vertical)
                        .font(.inter(size: 16))
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Create Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createTeam(
                            name: newTeamName,
                            description: newTeamDescription.isEmpty ? nil : newTeamDescription
                        )
                        newTeamName = ""
                        newTeamDescription = ""
                        showCreateSheet = false
                    }
                    .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Join Team Sheet

    private var joinTeamSheet: some View {
        NavigationStack {
            Form {
                Section("Invite Code") {
                    TextField("Enter code", text: $joinCode)
                        .font(.inter(size: 16))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Join Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showJoinSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        viewModel.joinTeam(inviteCode: joinCode)
                        joinCode = ""
                        showJoinSheet = false
                    }
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Team Card View

struct TeamCardView: View {
    let team: TeamResponse

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.inter(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(team.memberCount) member\(team.memberCount == 1 ? "" : "s")")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
