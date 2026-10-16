import Foundation

enum MealSlotAddKind: String, CaseIterable, Identifiable {
    case quickAdd
    case recipes

    var id: String { rawValue }
    var title: String { self == .quickAdd ? "Quick Add" : "Recipes" }
    var systemImage: String { self == .quickAdd ? "text.badge.plus" : "book.closed" }
}

/// Captures navigation context before any sheet opens; never reads a later selection.
struct MealSlotAddRoute: Identifiable, Equatable {
    let id = UUID()
    let homeID: UUID
    let date: Date
    let mealType: MealType
    let kind: MealSlotAddKind

    static func present(_ current: inout MealSlotAddRoute?, homeID: UUID?, date: Date,
                        mealType: MealType, kind: MealSlotAddKind) {
        guard current == nil, let homeID else { return }
        current = MealSlotAddRoute(homeID: homeID, date: date, mealType: mealType, kind: kind)
    }
}
