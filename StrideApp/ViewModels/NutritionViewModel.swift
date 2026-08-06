import Foundation
import SwiftUI
import os.log

private let nutritionLog = Logger(subsystem: "com.stride.app", category: "Nutrition")

/// Backing view model for the nutrition flow.
@MainActor
final class NutritionViewModel: ObservableObject {
    @Published private(set) var today: NutritionTodayDTO?
    @Published private(set) var hydration: HydrationDTO?
    @Published private(set) var templates: [TemplateDTO] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let t = APIService.shared.getNutritionToday()
            async let temps = APIService.shared.getNutritionTemplates()
            self.today = try await t
            self.templates = try await temps
        } catch {
            nutritionLog.error("refresh failed: \(error.localizedDescription)")
            self.error = "Couldn't load nutrition."
        }
    }

    func addHydration(glasses: Int = 1) async {
        do {
            let resp = try await APIService.shared.addHydration(glasses: glasses)
            self.hydration = resp
        } catch {
            self.error = "Couldn't update hydration."
        }
    }

    func logMeal(
        mealType: String,
        entryMethod: String,
        items: [ParsedMealItemDTO],
        totalCalories: Int,
        totalCarbs: Double,
        totalProtein: Double,
        totalFat: Double,
        photoUrl: String? = nil,
        rawDescription: String? = nil,
        confidence: Double? = nil,
        editedAfterParse: Bool = false
    ) async -> Bool {
        let parsedDicts = items.map { item -> [String: Any] in
            var d: [String: Any] = [:]
            if let v = item.name { d["name"] = v }
            if let v = item.estimatedQuantity { d["estimated_quantity"] = v }
            if let v = item.calories { d["calories"] = v }
            if let v = item.carbsG { d["carbs_g"] = v }
            if let v = item.proteinG { d["protein_g"] = v }
            if let v = item.fatG { d["fat_g"] = v }
            if let v = item.fiberG { d["fiber_g"] = v }
            return d
        }
        do {
            _ = try await APIService.shared.logMeal(
                mealType: mealType,
                entryMethod: entryMethod,
                parsedItems: parsedDicts,
                totals: (totalCalories, totalCarbs, totalProtein, totalFat, nil),
                photoUrl: photoUrl,
                rawDescription: rawDescription,
                confidence: confidence,
                editedAfterParse: editedAfterParse
            )
            await refresh()
            return true
        } catch {
            nutritionLog.error("logMeal failed: \(error.localizedDescription)")
            self.error = "Couldn't save meal."
            return false
        }
    }
}
