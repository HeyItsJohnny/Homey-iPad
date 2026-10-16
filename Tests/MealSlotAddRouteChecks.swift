import Foundation

@main struct MealSlotAddRouteChecks {
    static func main() {
        precondition(MealSlotAddKind.allCases.map(\.title) == ["Quick Add", "Recipes"])
        let homeID = UUID()
        let date = Date(timeIntervalSince1970: 1_792_224_000)
        for type in [MealType.breakfast, .lunch, .dinner, .snack] {
            for kind in MealSlotAddKind.allCases {
                var route: MealSlotAddRoute?
                MealSlotAddRoute.present(&route, homeID: homeID, date: date, mealType: type, kind: kind)
                precondition(route?.homeID == homeID && route?.date == date)
                precondition(route?.mealType == type && route?.kind == kind)
                let first = route!
                // Repeated taps and another menu action cannot replace a sheet already in flight.
                MealSlotAddRoute.present(&route, homeID: UUID(), date: date.addingTimeInterval(86400),
                    mealType: .snack, kind: kind == .quickAdd ? .recipes : .quickAdd)
                precondition(route == first)
                route = nil // Cancel/dismiss releases presentation; no persistence action exists here.
                MealSlotAddRoute.present(&route, homeID: homeID, date: date, mealType: type, kind: kind)
                precondition(route?.id != first.id)
            }
        }
        var route: MealSlotAddRoute?
        MealSlotAddRoute.present(&route, homeID: nil, date: date, mealType: .dinner, kind: .quickAdd)
        precondition(route == nil)
        print("Meal-slot menu order, both destinations, all four types, Home/date snapshots and repeated-tap/cancel routing checks passed")
    }
}
