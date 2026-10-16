import Foundation

@main struct QuickMealChecks {
    static func main() throws {
        precondition(QuickPlannedMeal.normalizedTitle(" \n ") == nil)
        precondition(QuickPlannedMeal.normalizedTitle("  Wingstop\n") == "Wingstop")
        precondition(QuickPlannedMeal.mealTypes == [.breakfast, .lunch, .dinner, .snack])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 23))!
        precondition(QuickPlannedMeal.dayKey(friday, calendar: calendar) == "2026-10-16")
        let homeID = UUID(), entryID = UUID()
        let parameters = SaveQuickMealParameters(homeID: homeID, entryID: entryID, title: "Wingstop",
            plannedDate: QuickPlannedMeal.dayKey(friday, calendar: calendar), mealType: .dinner, timezone: calendar.timeZone.identifier)
        let data = try JSONEncoder().encode(parameters)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(json["requested_home_id"] as? String == homeID.uuidString)
        precondition(json["requested_entry_id"] as? String == entryID.uuidString)
        precondition(json["requested_title"] as? String == "Wingstop")
        precondition(json["requested_planned_date"] as? String == "2026-10-16")
        precondition(json["requested_meal_type"] as? String == "dinner")
        precondition(json["requested_meal_id"] == nil)
        let retryData = try JSONEncoder().encode(parameters)
        let retryJSON = try JSONSerialization.jsonObject(with: retryData) as! NSDictionary
        precondition(retryJSON == json as NSDictionary) // retries preserve identity
        let entry = QuickPlannedMeal(id: entryID, homeID: homeID, calendarEventID: UUID(),
            title: "Wingstop", plannedDate: "2026-10-16", mealType: .dinner)
        let decoded = try JSONDecoder().decode(QuickPlannedMeal.self, from: JSONEncoder().encode(entry))
        precondition(decoded == entry)
        let second = QuickPlannedMeal(id: UUID(), homeID: homeID, calendarEventID: UUID(),
            title: "Pizza", plannedDate: entry.plannedDate, mealType: entry.mealType)
        precondition(Set([entry, second]).count == 2)
        for type in QuickPlannedMeal.mealTypes {
            let payload = SaveQuickMealParameters(homeID: homeID, entryID: entryID, title: "Renamed",
                plannedDate: "2026-11-02", mealType: type, timezone: nil)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
            precondition(encoded["requested_meal_type"] as? String == type.rawValue)
            precondition(encoded["requested_entry_id"] as? String == entryID.uuidString)
            precondition(encoded["requested_planned_date"] as? String == "2026-11-02")
            precondition(encoded["requested_timezone"] == nil)
        }
        let range = QuickMealRangeParameters(homeID: homeID, start: "2026-10-16", end: "2026-10-17")
        let rangeJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(range)) as! [String: String]
        precondition(rangeJSON == ["requested_home_id": homeID.uuidString,
            "requested_start_date": "2026-10-16", "requested_end_date": "2026-10-17"])
        let deletion = DeleteQuickMealParameters(homeID: homeID, entryID: entryID)
        let deleteJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(deletion)) as! [String: String]
        precondition(deleteJSON == ["requested_home_id": homeID.uuidString, "requested_entry_id": entryID.uuidString])
        let counters = ["meals_deleted", "meal_recipes_deleted", "recipe_ingredients_deleted", "recipe_steps_deleted",
            "meal_photos_deleted", "meal_favorites_deleted", "meal_collections_deleted", "meal_collection_items_deleted",
            "meal_plan_entries_deleted", "quick_meals_deleted"]
        let response = Dictionary(uniqueKeysWithValues: counters.enumerated().map { ($0.element, $0.offset + 1) })
        let clearResult = try JSONDecoder().decode(ClearHomeMealsResult.self, from: JSONSerialization.data(withJSONObject: response))
        precondition(clearResult.mealsDeleted == 1 && clearResult.mealRecipesDeleted == 2)
        precondition(clearResult.recipeIngredientsDeleted == 3 && clearResult.recipeStepsDeleted == 4)
        precondition(clearResult.mealPhotosDeleted == 5 && clearResult.mealFavoritesDeleted == 6)
        precondition(clearResult.mealCollectionsDeleted == 7 && clearResult.mealCollectionItemsDeleted == 8)
        precondition(clearResult.mealPlanEntriesDeleted == 9 && clearResult.quickMealsDeleted == 10)
        let zeros = try JSONDecoder().decode(ClearHomeMealsResult.self,
            from: JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: counters.map { ($0, 0) })))
        precondition(zeros.quickMealsDeleted == 0)
        precondition(QuickMealError.serverError(code: "23503", message: "foreign key failure") == .calendarReconciliation)
        precondition(QuickMealError.serverError(code: "P0001", message: "Calendar event no longer exists") == .calendarReconciliation)
        precondition(QuickMealError.serverError(code: "42501", message: "") == .permissionDenied)
        precondition(QuickMealError.serverError(code: "PGRST202", message: "") == .unavailable)
        precondition(QuickMealError.serverError(code: nil, message: "Unknown internal detail") == .requestFailed)
        print("Quick Meal model, normalization, Home/date/type payload, retry identity, multiple-entry, error classification and Clear Meals V2 decoding checks passed")
    }
}
