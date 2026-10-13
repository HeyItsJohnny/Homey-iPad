import Foundation

/// A disposable Calendar prefill. It contains no Trip identity or integration state.
enum TripCalendarDraft {
    static func needsFreshDates(_ trip: Trip) -> Bool {
        guard trip.status == .planned || trip.status == .active,
              let start = trip.startDate else { return true }
        return (trip.endDate ?? start) < start
    }

    @MainActor static func make(trip: Trip, calendar: Calendar, now: Date = Date()) -> PhoneCalendarDraft {
        let freshDates = needsFreshDates(trip)
        let today = calendar.startOfDay(for: now)
        let startDay = freshDates ? today : localDay(trip.startDate!, calendar: calendar)
        let endDay: Date
        if !freshDates {
            endDay = localDay(trip.endDate ?? trip.startDate!, calendar: calendar)
        } else {
            var backendCalendar = Calendar(identifier: .gregorian)
            backendCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let duration: Int
            if trip.durationType == .fewHours || trip.durationType == .dayTrip {
                duration = 0
            } else if let start = trip.startDate, let end = trip.endDate {
                duration = max(0, backendCalendar.dateComponents([.day], from: start, to: end).day ?? 0)
            } else {
                duration = trip.durationType == .weekend ? 2 : 0
            }
            endDay = calendar.date(byAdding: .day, value: duration, to: startDay) ?? startDay
        }
        var draft = PhoneCalendarDraft(date: startDay, calendar: calendar)
        draft.title = trip.title
        draft.location = nonempty(trip.destinationName) ?? nonempty(trip.destinationAddress) ?? ""
        draft.notes = trip.notes ?? ""
        draft.isAllDay = trip.durationType != .fewHours &&
            !(trip.durationType == .custom && (trip.startTime != nil || trip.endTime != nil))
        if draft.isAllDay {
            draft.startsAt = startDay
            // The normal Calendar editor uses an inclusive end day; its service owns conversion.
            draft.endsAt = max(startDay, endDay)
        } else {
            draft.startsAt = time(trip.startTime, on: startDay, defaultHour: 9, calendar: calendar)
            let end = time(trip.endTime, on: endDay, defaultHour: 17, calendar: calendar)
            draft.endsAt = end > draft.startsAt ? end : (calendar.date(byAdding: .hour, value: 1, to: draft.startsAt) ?? draft.startsAt)
        }
        draft.recurrence = PhoneCalendarRecurrence()
        draft.assignedUserIDs = []
        return draft
    }

    private static func localDay(_ date: Date, calendar: Calendar) -> Date {
        PhoneCalendarDateOnly.date(TripDateFormatters.backendDate.string(from: date), timezone: calendar.timeZone) ?? date
    }

    private static func time(_ value: String?, on day: Date, defaultHour: Int, calendar: Calendar) -> Date {
        let pieces = value?.split(separator: ":") ?? []
        let hour = pieces.first.flatMap { Int($0) } ?? defaultHour
        let minute = pieces.count > 1 ? (Int(pieces[1]) ?? 0) : 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
