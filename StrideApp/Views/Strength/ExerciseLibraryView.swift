import SwiftUI

/// Searchable, categorized exercise library. Tapping an exercise calls the
/// `onSelect` closure. Categories: posterior_chain / hip_stability / single_leg / core.
struct ExerciseLibraryView: View {
    @ObservedObject var viewModel: StrengthViewModel
    var onSelect: (StrengthExerciseDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "all"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker
                List {
                    ForEach(filteredGroups, id: \.category) { group in
                        Section(headerText(for: group.category)) {
                            ForEach(group.exercises) { ex in
                                Button {
                                    onSelect(ex)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ex.name).font(.callout.weight(.medium))
                                            HStack(spacing: 8) {
                                                Text(ex.equipment).font(.caption2).foregroundStyle(.secondary)
                                                Text("•").font(.caption2).foregroundStyle(.tertiary)
                                                Text("\(ex.defaultSetCount) × \(ex.defaultRepRange)")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if let urlString = ex.youtubeDemoUrl, let url = URL(string: urlString) {
                                            Link(destination: url) {
                                                Image(systemName: "play.circle")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search exercises")
            }
            .navigationTitle("Exercise library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .task { await viewModel.loadLibrary() }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            Text("All").tag("all")
            Text("Posterior").tag("posterior_chain")
            Text("Hip").tag("hip_stability")
            Text("Single leg").tag("single_leg")
            Text("Core").tag("core")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filteredGroups: [(category: String, exercises: [StrengthExerciseDTO])] {
        let groups = viewModel.libraryByCategory
        let categoryFiltered: [(category: String, exercises: [StrengthExerciseDTO])] = selectedCategory == "all"
            ? groups
            : groups.filter { $0.category == selectedCategory }
        guard !searchText.isEmpty else { return categoryFiltered }
        let q = searchText.lowercased()
        return categoryFiltered.compactMap { group in
            let matches = group.exercises.filter { $0.name.lowercased().contains(q) }
            return matches.isEmpty ? nil : (category: group.category, exercises: matches)
        }
    }

    private func headerText(for category: String) -> String {
        switch category {
        case "posterior_chain": return "Posterior chain"
        case "hip_stability":   return "Hip stability"
        case "single_leg":      return "Single leg"
        case "core":            return "Core"
        default:                return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
