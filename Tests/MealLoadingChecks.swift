import Foundation

@main struct MealLoadingChecks {
    static func main() async throws {
        let home = UUID(), otherHome = UUID()
        func fixture(type: String = "dinner", date: String = "2026-10-16") -> [String: Any] {
            ["entry_id": UUID().uuidString, "home_id": home.uuidString,
             "calendar_event_id": UUID().uuidString, "title": "PRIVATE-TITLE-NEVER-IN-DIAGNOSTICS",
             "planned_date": date, "meal_type": type]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // date-only String does not use timestamp decoding
        for type in ["breakfast", "lunch", "dinner", "snack"] {
            let data = try JSONSerialization.data(withJSONObject: [fixture(type: type)])
            let meals = try decoder.decode([QuickPlannedMeal].self, from: data)
            precondition(meals.count == 1 && meals[0].plannedDate == "2026-10-16")
            precondition(meals[0].mealType.rawValue == type && meals[0].homeID == home)
        }
        let empty = try decoder.decode([QuickPlannedMeal].self, from: Data("[]".utf8))
        precondition(empty.isEmpty)
        for date in ["2026-02-30", "2026-13-01", "2026-1-01", "2026-10-16T00:00:00Z"] {
            let data = try JSONSerialization.data(withJSONObject: [fixture(date: date)])
            do { _ = try decoder.decode([QuickPlannedMeal].self, from: data); preconditionFailure("Invalid date accepted") }
            catch {
                let error = MealLoadFailure.capture(operation: "get_quick_meal_plan_entries", error: error)
                precondition(error.path == "[0].planned_date")
                precondition(error.kind == "DecodingError.dataCorrupted")
                precondition(!error.localizedDescription.contains("PRIVATE-TITLE"))
            }
        }
        for type in ["Dinner", "unknown", "dessert"] {
            let data = try JSONSerialization.data(withJSONObject: [fixture(type: type)])
            do { _ = try decoder.decode([QuickPlannedMeal].self, from: data); preconditionFailure("Unsupported type accepted") }
            catch {
                let error = MealLoadFailure.capture(operation: "get_quick_meal_plan_entries", error: error)
                precondition(error.path == "[0].meal_type")
            }
        }
        var malformed = fixture()
        malformed["title"] = NSNull()
        let badData = try JSONSerialization.data(withJSONObject: [malformed])
        let goodData = try JSONSerialization.data(withJSONObject: [fixture()])
        async let quickFailure = MealLoadResult<[QuickPlannedMeal]>.fetch(operation: "get_quick_meal_plan_entries") {
            try decoder.decode([QuickPlannedMeal].self, from: badData)
        }
        async let recipes = MealLoadResult<[String]>.fetch(operation: "recipe_plan.read") { ["recipe-entry"] }
        let (quickResult, recipeResult) = await (quickFailure, recipes)
        guard case .success(let recipeEntries) = recipeResult,
              case .failure(let error) = quickResult else { preconditionFailure("Failure was not isolated") }
        precondition(recipeEntries == ["recipe-entry"] && error.path == "[0].title")
        precondition(error.kind == "DecodingError.valueNotFound")
        precondition(!error.localizedDescription.contains("PRIVATE-TITLE"))
        async let quickSuccess = MealLoadResult<[QuickPlannedMeal]>.fetch(operation: "get_quick_meal_plan_entries") {
            try decoder.decode([QuickPlannedMeal].self, from: goodData)
        }
        async let recipeFailure = MealLoadResult<[String]>.fetch(operation: "meal_event_details.read") {
            throw MealLoadFailure(operation: "meal_event_details.read", kind: "PostgrestError", code: "42P01", path: nil)
        }
        let (loadedQuick, failedRecipe) = await (quickSuccess, recipeFailure)
        guard case .success(let quickEntries) = loadedQuick,
              case .failure(let recipeError) = failedRecipe else { preconditionFailure("Recipe failure gated Quick Adds") }
        precondition(quickEntries.count == 1 && recipeError.operation == "meal_event_details.read" && recipeError.code == "42P01")
        // Same-date/type entries retain distinct identities; no recipe lookup or meal_id is required.
        let another = try decoder.decode([QuickPlannedMeal].self, from: JSONSerialization.data(withJSONObject: [fixture()]))
        precondition(Set(quickEntries + another).count == 2)
        precondition(quickEntries.filter { $0.homeID == otherHome }.isEmpty)
        let code = MealLoadFailure.capture(operation: "get_quick_meal_plan_entries",
            error: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-TITLE"]), postgrestCode: "42501")
        precondition(code.code == "42501" && !code.localizedDescription.contains("PRIVATE-TITLE"))
        print("iPhone-contract Quick Add fixtures, date-only decoding, empty/malformed responses, safe diagnostics and independent async loading checks passed")
    }
}
