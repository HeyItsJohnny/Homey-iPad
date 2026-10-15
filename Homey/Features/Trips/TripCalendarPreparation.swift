import Foundation

/// Normalized generic Calendar payload; dates follow the existing Calendar RPC contract.
struct TripCalendarPreparation: Codable, Equatable {
    let tripID: UUID
    let homeID: UUID
    let title: String
    let location: String?
    let notes: String?
    let timezone: String
    let startsAt: Date
    /// Exclusive midnight after the final day for all-day events.
    let endsAt: Date
    let isAllDay: Bool

    static func destination(name: String?, address: String?) -> String? {
        [name, address].compactMap { value -> String? in
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }.first
    }

    init(tripID: UUID, homeID: UUID, title: String, location: String?, timezone: String,
         startDate: String, endDate: String?, startTime: String?, endTime: String?, notes: String? = nil) throws {
        self.tripID = tripID; self.homeID = homeID; self.title = title; self.location = location
        self.timezone = timezone
        self.notes = notes
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: timezone) else { throw DraftError.invalidSchedule }
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; formatter.isLenient = false
        guard (startTime == nil) == (endTime == nil) else { throw DraftError.invalidSchedule }
        isAllDay = startTime == nil && endTime == nil
        func time(_ value: String?) -> String {
            guard let value else { return "00:00:00" }
            return value.count == 5 ? value + ":00" : value
        }
        guard let start = formatter.date(from: startDate + " " + time(startTime)),
              let end = formatter.date(from: (endDate ?? startDate) + " " + time(endTime)) else { throw DraftError.invalidSchedule }
        startsAt = start
        if isAllDay {
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: end) else { throw DraftError.invalidSchedule }
            endsAt = exclusiveEnd
        } else { endsAt = end }
        guard endsAt > startsAt else { throw DraftError.invalidSchedule }
    }
    func save(defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: "homey.tripCalendarDraft.\(homeID).\(tripID)")
    }
    enum DraftError: LocalizedError {
        case invalidSchedule
        var errorDescription: String? { "Calendar needs valid dates and a Home timezone." }
    }
}
