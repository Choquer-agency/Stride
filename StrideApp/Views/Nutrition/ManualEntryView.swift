import SwiftUI

/// Direct macros entry — fastest path for repeat-known meals or cases where
/// vision parse failed.
struct ManualEntryView: View {
    let mealType: String
    @ObservedObject var viewModel: NutritionViewModel
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var calories: String = ""
    @State private var carbs: String = ""
    @State private var protein: String = ""
    @State private var fat: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal name") {
                    TextField("e.g. Oatmeal with banana", text: $name)
                }
                Section("Macros") {
                    HStack { Text("Calories"); Spacer(); TextField("kcal", text: $calories).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Carbs (g)"); Spacer(); TextField("g", text: $carbs).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Protein (g)"); Spacer(); TextField("g", text: $protein).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Fat (g)"); Spacer(); TextField("g", text: $fat).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
            }
            .navigationTitle("Manual entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(calories.isEmpty || viewModel.isLoading)
                }
            }
        }
    }

    private func save() async {
        let item = ParsedMealItemDTO(
            name: name.isEmpty ? "Manual entry" : name,
            estimatedQuantity: nil,
            calories: Int(calories),
            carbsG: Double(carbs),
            proteinG: Double(protein),
            fatG: Double(fat),
            fiberG: nil
        )
        let ok = await viewModel.logMeal(
            mealType: mealType,
            entryMethod: "manual",
            items: [item],
            totalCalories: Int(calories) ?? 0,
            totalCarbs: Double(carbs) ?? 0,
            totalProtein: Double(protein) ?? 0,
            totalFat: Double(fat) ?? 0,
            confidence: 1.0
        )
        if ok { onSaved(); dismiss() }
    }
}
