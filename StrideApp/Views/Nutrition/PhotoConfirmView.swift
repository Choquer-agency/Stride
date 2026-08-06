import SwiftUI

/// Reviews parsed items (from photo or text) before final save. Athlete can
/// edit individual item macros if needed. Always shown — LEA + accuracy guard.
struct PhotoConfirmView: View {
    let parsed: ParsedMealDTO
    let mealType: String
    @ObservedObject var viewModel: NutritionViewModel
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedItems: [ParsedMealItemDTO]
    @State private var totalsOverridden: Bool = false

    init(parsed: ParsedMealDTO, mealType: String, viewModel: NutritionViewModel, onSaved: @escaping () -> Void) {
        self.parsed = parsed
        self.mealType = mealType
        self.viewModel = viewModel
        self.onSaved = onSaved
        _editedItems = State(initialValue: parsed.items)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notes = parsed.notes, !notes.isEmpty {
                    Section { Text(notes).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Items") {
                    if editedItems.isEmpty {
                        Text("Couldn't find anything to log.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(editedItems.indices, id: \.self) { i in
                            itemRow(item: editedItems[i])
                        }
                    }
                }
                Section("Totals") {
                    HStack { Text("Calories"); Spacer(); Text("\(totalCalories)").monospacedDigit() }
                    HStack { Text("Carbs"); Spacer(); Text("\(Int(totalCarbs))g").monospacedDigit() }
                    HStack { Text("Protein"); Spacer(); Text("\(Int(totalProtein))g").monospacedDigit() }
                    HStack { Text("Fat"); Spacer(); Text("\(Int(totalFat))g").monospacedDigit() }
                }
                if parsed.confidence > 0 && parsed.confidence < 0.7 {
                    Section {
                        Label("Lower confidence — double-check portions before saving.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Confirm meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(editedItems.isEmpty)
                }
            }
        }
    }

    // MARK: - Item row

    private func itemRow(item: ParsedMealItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name ?? "Item").font(.callout.weight(.medium))
            if let q = item.estimatedQuantity {
                Text(q).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let cal = item.calories { Text("\(cal) kcal").font(.caption2).foregroundStyle(.secondary) }
                if let c = item.carbsG { Text("C \(Int(c))g").font(.caption2).foregroundStyle(.secondary) }
                if let p = item.proteinG { Text("P \(Int(p))g").font(.caption2).foregroundStyle(.secondary) }
                if let f = item.fatG { Text("F \(Int(f))g").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Totals

    private var totalCalories: Int { editedItems.reduce(0) { $0 + ($1.calories ?? 0) } }
    private var totalCarbs: Double { editedItems.reduce(0) { $0 + ($1.carbsG ?? 0) } }
    private var totalProtein: Double { editedItems.reduce(0) { $0 + ($1.proteinG ?? 0) } }
    private var totalFat: Double { editedItems.reduce(0) { $0 + ($1.fatG ?? 0) } }

    private func save() async {
        let entryMethod = parsed.photoUrl != nil ? "photo" : "text"
        let ok = await viewModel.logMeal(
            mealType: mealType,
            entryMethod: entryMethod,
            items: editedItems,
            totalCalories: totalCalories,
            totalCarbs: totalCarbs,
            totalProtein: totalProtein,
            totalFat: totalFat,
            photoUrl: parsed.photoUrl,
            rawDescription: nil,
            confidence: parsed.confidence,
            editedAfterParse: false
        )
        if ok { onSaved(); dismiss() }
    }
}
