import Foundation

@main struct QuickMealAutoPlanChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: Date())!)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let homeID = UUID()
        let quickMeals = QuickPlannedMeal.mealTypes.map { type in
            QuickPlannedMeal(id: UUID(), homeID: homeID, calendarEventID: UUID(), title: "Wingstop",
                plannedDate: QuickPlannedMeal.dayKey(day, calendar: calendar), mealType: type)
        }
        let config = AutoPlanConfiguration(selectedDates: [day], selectedMealTypes: Set(QuickPlannedMeal.mealTypes),
            recipePool: .allRecipes, allowsRepeats: true)
        let recipeJSON: [String: Any] = ["id": UUID().uuidString, "home_id": homeID.uuidString,
            "name": "Home Recipe", "meal_types": QuickPlannedMeal.mealTypes.map(\.rawValue),
            "is_archived": false, "created_by": UUID().uuidString,
            "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recipe = try decoder.decode(Meal.self, from: JSONSerialization.data(withJSONObject: recipeJSON))
        let formatter = ISO8601DateFormatter()
        let eventID = UUID()
        let eventJSON: [String: Any] = ["event_id": eventID.uuidString, "home_id": homeID.uuidString,
            "title": "Wingstop", "category_id": NSNull(), "starts_at": formatter.string(from: day),
            "ends_at": formatter.string(from: day.addingTimeInterval(3600)), "is_all_day": false,
            "timezone": calendar.timeZone.identifier, "created_at": formatter.string(from: day), "updated_at": formatter.string(from: day)]
        let event = try decoder.decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: eventJSON))
        precondition(event.categoryId == nil && event.homeId == homeID && event.eventId == eventID)
        precondition(event.occurrenceEndsAt.timeIntervalSince(event.occurrenceStartsAt) == 3600)
        let titleOnlyDetail: [String: Any] = ["calendar_event_id": eventID.uuidString, "meal_id": NSNull(),
            "meal_type": "dinner", "created_by": UUID().uuidString,
            "created_at": formatter.string(from: day), "updated_at": formatter.string(from: day)]
        do {
            _ = try decoder.decode([MealEventDetail].self, from: JSONSerialization.data(withJSONObject: [titleOnlyDetail]))
            preconditionFailure("A title-only row must not be treated as a recipe detail")
        } catch {
            let failure = MealLoadFailure.capture(operation: "meal_event_details.read", error: error)
            precondition(failure.kind == "DecodingError.valueNotFound" && failure.path == "[0].meal_id")
        }
        let detail = MealEventDetail(calendarEventId: eventID, mealId: recipe.id, mealType: .breakfast,
            createdBy: UUID(), createdAt: day, updatedAt: day)
        let plannedRecipe = PlannedMeal(calendarEvent: event, mealEventDetail: detail, meal: recipe, signedPhotoURL: nil)
        let recipeDraft = AutoPlanEngine(calendar: calendar).generateDraft(homeId: homeID,
            weekRange: (day, end), weekDays: [day], eligibleMeals: [recipe], favoritesByMember: [:], members: [],
            existingPlannedMeals: [plannedRecipe], recentPlannedMeals: [], configuration: config)
        let breakfast = recipeDraft.slots.first { $0.mealType == .breakfast }!
        precondition(breakfast.isFilled && breakfast.existingPlannedMeals == [plannedRecipe])
        precondition(breakfast.suggestion?.meal?.id == recipe.id)
        let engine = AutoPlanEngine(calendar: calendar, seed: 1, quickMeals: quickMeals)
        let draft = engine.generateDraft(homeId: homeID, weekRange: (day, end), weekDays: [day],
            eligibleMeals: [recipe], favoritesByMember: [:], members: [], existingPlannedMeals: [plannedRecipe], recentPlannedMeals: [], configuration: config)
        precondition(draft.slots.count == 4)
        precondition(draft.slots.allSatisfy { $0.isFilled && $0.quickMealTitle == "Wingstop" })
        precondition(draft.creatableSlots.isEmpty)
        let rerolled = engine.reroll(slotId: draft.slots[0].id, draft: draft, eligibleMeals: [recipe],
            favoritesByMember: [:], members: [], existingPlannedMeals: [], recentPlannedMeals: [])
        precondition(rerolled == draft)
        let empty = AutoPlanEngine(calendar: calendar).generateDraft(homeId: homeID, weekRange: (day, end), weekDays: [day],
            eligibleMeals: [recipe], favoritesByMember: [:], members: [], existingPlannedMeals: [], recentPlannedMeals: [], configuration: config)
        precondition(empty.slots.allSatisfy { !$0.isFilled })
        precondition(!empty.creatableSlots.isEmpty)
        precondition(empty.creatableSlots.allSatisfy { $0.suggestion?.meal?.id == recipe.id })
        print("Auto Plan preserves all four Quick Add slots and does not turn them into recipe candidates")
    }
}
