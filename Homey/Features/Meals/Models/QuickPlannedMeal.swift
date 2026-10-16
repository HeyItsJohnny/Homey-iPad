import Foundation

/// A title-only plan entry. Deliberately has no recipe or ingredient identity.
struct QuickPlannedMeal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeID: UUID
    let calendarEventID: UUID
    let title: String
    let plannedDate: String
    let mealType: MealType

    static let mealTypes: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    enum CodingKeys: String, CodingKey {
        case id = "entry_id", homeID = "home_id", calendarEventID = "calendar_event_id"
        case title, plannedDate = "planned_date", mealType = "meal_type"
    }

    static func normalizedTitle(_ title: String) -> String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct SaveQuickMealParameters: Encodable {
    let homeID: UUID
    /// Stable across retries; server must upsert this ID atomically with its Calendar event.
    let entryID: UUID
    let title: String
    let plannedDate: String
    let mealType: MealType
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", entryID = "requested_entry_id"
        case title = "requested_title", plannedDate = "requested_planned_date"
        case mealType = "requested_meal_type", timezone = "requested_timezone"
    }
}

struct QuickMealRangeParameters: Encodable {
    let homeID: UUID
    let start: String
    let end: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case start = "requested_start_date"
        case end = "requested_end_date"
    }
}

struct DeleteQuickMealParameters: Encodable {
    let homeID: UUID
    let entryID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case entryID = "requested_entry_id"
    }
}

extension QuickPlannedMeal {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        homeID = try values.decode(UUID.self, forKey: .homeID)
        calendarEventID = try values.decode(UUID.self, forKey: .calendarEventID)
        title = try values.decode(String.self, forKey: .title)
        plannedDate = try values.decode(String.self, forKey: .plannedDate)
        var dateCalendar = Calendar(identifier: .gregorian)
        dateCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = plannedDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [4, 2, 2],
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = dateCalendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.dayKey(date, calendar: dateCalendar) == plannedDate else {
            throw DecodingError.dataCorruptedError(forKey: .plannedDate, in: values,
                debugDescription: "Expected a valid YYYY-MM-DD calendar date")
        }
        mealType = try values.decode(MealType.self, forKey: .mealType)
        guard Self.mealTypes.contains(mealType) else {
            throw DecodingError.dataCorruptedError(forKey: .mealType, in: values,
                debugDescription: "Expected breakfast, lunch, dinner or snack")
        }
    }
}
