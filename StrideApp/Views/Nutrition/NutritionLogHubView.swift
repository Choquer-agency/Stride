import PhotosUI
import SwiftUI

/// Top-level entry hub for logging a meal. Presents three tap targets:
/// Photo / Text / Manual. Recent templates carousel below.
struct NutritionLogHubView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NutritionViewModel()

    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var showTextEntry = false
    @State private var showManualEntry = false
    @State private var showPhotoConfirm = false
    @State private var parsedMeal: ParsedMealDTO?
    @State private var selectedMealType: String = autoDefaultMealType()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    mealTypePicker
                    threeButtons
                    if !viewModel.templates.isEmpty {
                        templatesSection
                    }
                    if let today = viewModel.today {
                        todaySummary(today)
                    }
                    if let err = viewModel.error {
                        Text(err).font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
        .task { await viewModel.refresh() }
        .photosPicker(isPresented: .constant(false), selection: $pickedPhotoItem, matching: .images)
        .onChange(of: pickedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pickedImageData = data
                    do {
                        let parsed = try await APIService.shared.parseMealPhoto(imageData: data, mealType: selectedMealType)
                        parsedMeal = parsed
                        showPhotoConfirm = true
                    } catch {
                        viewModel.error = "Couldn't parse photo."
                    }
                }
            }
        }
        .sheet(isPresented: $showTextEntry) {
            TextEntryView(mealType: selectedMealType, onParsed: { parsed in
                parsedMeal = parsed
                showTextEntry = false
                showPhotoConfirm = true
            })
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView(mealType: selectedMealType, viewModel: viewModel) {
                showManualEntry = false
            }
        }
        .sheet(isPresented: $showPhotoConfirm) {
            if let parsed = parsedMeal {
                PhotoConfirmView(
                    parsed: parsed,
                    mealType: selectedMealType,
                    viewModel: viewModel,
                    onSaved: {
                        parsedMeal = nil
                        showPhotoConfirm = false
                    }
                )
            }
        }
    }

    // MARK: - Sub-views

    private var mealTypePicker: some View {
        Picker("Meal type", selection: $selectedMealType) {
            Text("Breakfast").tag("breakfast")
            Text("Lunch").tag("lunch")
            Text("Dinner").tag("dinner")
            Text("Snack").tag("snack")
            Text("Pre-workout").tag("pre_workout")
            Text("Post-workout").tag("post_workout")
        }
        .pickerStyle(.segmented)
    }

    private var threeButtons: some View {
        HStack(spacing: 12) {
            entryButton(label: "Photo", icon: "camera.fill") {
                pickedPhotoItem = nil
                // PhotosPicker uses `isPresented`; iOS 17 — present manually:
                Task { @MainActor in
                    pickedPhotoItem = try? await PhotosPickerItem(itemIdentifier: "")
                }
            }
            entryButton(label: "Text", icon: "text.cursor") { showTextEntry = true }
            entryButton(label: "Manual", icon: "square.and.pencil") { showManualEntry = true }
        }
    }

    private func entryButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.stridePrimary)
                Text(label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.templates) { tpl in
                        Button {
                            Task {
                                _ = try? await APIService.shared.logFromTemplate(templateId: tpl.id, mealType: selectedMealType)
                                await viewModel.refresh()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tpl.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                if let cal = tpl.totalCalories {
                                    Text("\(cal) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(width: 140, alignment: .leading)
                            .background(Color.stridePrimary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func todaySummary(_ today: NutritionTodayDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today so far")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statTile(label: "kcal", value: "\(today.totals.calories)")
                statTile(label: "Carbs", value: "\(Int(today.totals.carbsG))g")
                statTile(label: "Protein", value: "\(Int(today.totals.proteinG))g")
                statTile(label: "Fat", value: "\(Int(today.totals.fatG))g")
            }
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - default meal type by time of day

private func autoDefaultMealType() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 4..<11: return "breakfast"
    case 11..<15: return "lunch"
    case 15..<18: return "snack"
    case 18..<23: return "dinner"
    default: return "snack"
    }
}
