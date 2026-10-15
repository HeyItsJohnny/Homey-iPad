import Foundation
import Supabase

/// Same generic Calendar workflow as iPhone's PhoneCalendarService.
@MainActor
struct TripCalendarService: TripCalendarEventService {
    private let calendar = CalendarService()

    private func validate(userID: UUID, isCurrentScope: () -> Bool) async throws {
        guard try await SupabaseManager.shared.client.auth.session.user.id == userID else {
            throw TripPlanningSessionError.changed
        }
        guard isCurrentScope(), !Task.isCancelled else { throw CancellationError() }
    }

    func matchingEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID? {
        try await validate(userID: userID, isCurrentScope: isCurrentScope)
        let events = try await calendar.fetchEvents(homeId: draft.homeID, rangeStart: draft.startsAt, rangeEnd: draft.endsAt)
        return events.first { event in
            event.homeId == draft.homeID && !event.isRecurring && !event.isException &&
            event.title.trimmingCharacters(in: .whitespacesAndNewlines) == draft.title.trimmingCharacters(in: .whitespacesAndNewlines) &&
            Self.clean(event.location) == Self.clean(draft.location) && event.isAllDay == draft.isAllDay &&
            abs(event.startsAt.timeIntervalSince(draft.startsAt)) < 1 &&
            abs(event.endsAt.timeIntervalSince(draft.endsAt)) < 1
        }?.eventId
    }

    func createEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID {
        try await validate(userID: userID, isCurrentScope: isCurrentScope)
        // Both Calendar services send exclusive all-day ends to create_calendar_event.
        // iPhone's Trip prefill leaves category nil until the user explicitly chooses one.
        return try await calendar.createEvent(homeId: draft.homeID, title: draft.title,
            notes: draft.notes, location: draft.location, startsAt: draft.startsAt, endsAt: draft.endsAt,
            isAllDay: draft.isAllDay, timezone: draft.timezone, categoryId: nil)
    }

    private static func clean(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
