import Foundation

@main struct TripsHubChecks {
    static func main() throws {
        let home = UUID(), otherHome = UUID(), user = UUID(), ideaID = UUID()
        func trip(_ title: String, _ status: String, _ start: String?, _ end: String?, organizer: UUID? = nil) throws -> Trip {
            let json: [String: Any] = ["trip_id": UUID().uuidString, "organizer_home_id": (organizer ?? home).uuidString,
                "title": title, "status": status, "duration_type": "day_trip", "start_date": start as Any? ?? NSNull(),
                "end_date": end as Any? ?? NSNull(), "created_at": "", "updated_at": ""]
            return try JSONDecoder().decode(Trip.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func idea(_ title: String) throws -> SavedTripIdea {
            let json: [String: Any] = ["idea_id": UUID().uuidString, "home_id": home.uuidString, "title": title,
                "duration_type": "day_trip", "created_at": "", "updated_at": "", "linked_trip_count": 0,
                "completed_visit_count": 0, "rated_visit_count": 0]
            return try JSONDecoder().decode(SavedTripIdea.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let ideas = try [idea("zoo"), idea("Aquarium"), idea("beach")]
        precondition(TripsHubSort.ideas(ideas).map(\.title) == ["Aquarium", "beach", "zoo"])
        let visits = try [trip("Undated", "planned", nil, nil), trip("Later", "planned", "2027-01-03", nil),
            trip("Joined", "active", "2027-01-01", nil, organizer: otherHome),
            trip("Old", "completed", "2025-01-01", "2025-01-02"), trip("Recent", "completed", "2026-01-01", "2026-01-03")]
        precondition(TripsHubSort.planned(visits).map(\.title) == ["Joined", "Later", "Undated"])
        precondition(TripsHubSort.past(visits).map(\.title) == ["Recent", "Old"])
        precondition(TripsHubSort.planned(visits).first?.organizerHomeID == otherHome)

        let suite = "TripsHubChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TripIdeaPlanningStore(defaults: defaults)
        let attempt = TripIdeaPlanningAttempt(userID: user, homeID: home, ideaID: ideaID,
            startDate: "2026-10-20", endDate: "2026-10-20", startTime: nil, endTime: nil)
        try store.save(attempt)
        let reloaded = try TripIdeaPlanningStore(defaults: defaults).load(userID: user, homeID: home, ideaID: ideaID)
        precondition(reloaded == attempt)
        precondition(tryValue { try store.load(userID: user, homeID: otherHome, ideaID: ideaID) } == nil)
        precondition(tryValue { try store.load(userID: UUID(), homeID: home, ideaID: ideaID) } == nil)
        try store.save(attempt)
        do {
            try store.save(TripIdeaPlanningAttempt(userID: user, homeID: home, ideaID: ideaID,
                startDate: "2026-11-20", endDate: nil, startTime: nil, endTime: nil))
            preconditionFailure("Unresolved request was replaced")
        } catch PlanningStoreError.unresolvedAttempt { }
        let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt.parameters)) as! [String: Any]
        precondition(params["requested_request_id"] as? String == attempt.requestID.uuidString)
        precondition(params["requested_start_time"] is NSNull)
        precondition(params["requested_home_id"] as? String == home.uuidString)
        let canonicalTripID = UUID()
        try store.confirm(attempt, tripID: canonicalTripID)
        try store.confirm(attempt, tripID: canonicalTripID)
        precondition(tryValue { try TripIdeaPlanningStore(defaults: defaults).confirmedTripID(for: attempt) } == canonicalTripID)
        do {
            try store.confirm(attempt, tripID: UUID())
            preconditionFailure("Canonical receipt was replaced")
        } catch PlanningStoreError.scopeMismatch { }
        try store.finish(attempt)
        precondition(tryValue { try store.confirmedTripID(for: attempt) } == nil)
        precondition(tryValue { try store.load(userID: user, homeID: home, ideaID: ideaID) } == nil)
        let calendarAttempt = TripIdeaPlanningAttempt(userID: user, homeID: home, ideaID: ideaID,
            startDate: "2026-10-31", endDate: "2026-11-01", startTime: nil, endTime: nil,
            addToCalendar: true, timezone: "America/Los_Angeles")
        try store.save(calendarAttempt)
        try store.confirm(calendarAttempt, tripID: canonicalTripID)
        let restoredStore = TripIdeaPlanningStore(defaults: defaults)
        let restoredAttempt = try restoredStore.load(userID: user, homeID: home, ideaID: ideaID)!
        precondition(restoredAttempt.addToCalendar == true && restoredAttempt.timezone == "America/Los_Angeles")
        precondition(tryValue { try restoredStore.confirmedTripID(for: restoredAttempt) } == canonicalTripID)
        // A lost plan response has no receipt, but retains the same RPC request ID.
        try restoredStore.finish(restoredAttempt)
        try restoredStore.save(calendarAttempt)
        precondition(tryValue { try restoredStore.confirmedTripID(for: calendarAttempt) } == nil)
        precondition(tryValue { try restoredStore.load(userID: user, homeID: home, ideaID: ideaID) }?.requestID == calendarAttempt.requestID)
        try restoredStore.finish(calendarAttempt)
        let encodedLegacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)) as! [String: Any]
        var legacy = encodedLegacy
        legacy.removeValue(forKey: "addToCalendar"); legacy.removeValue(forKey: "timezone")
        let migrated = try JSONDecoder().decode(TripIdeaPlanningAttempt.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.addToCalendar == nil && migrated.timezone == nil)
        precondition(ideas.count == 3) // Planning does not mutate the permanent collection.
        var draft = TripIdeaDraft(); draft.title = "  Family day  "; draft.notes = "  "
        let create = TripIdeaCreateParameters(homeID: home, createdBy: user, descriptive: try TripIdeaEditParameters(draft: draft))
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(create)) as! [String: Any]
        precondition(payload["home_id"] as? String == home.uuidString && payload["created_by"] as? String == user.uuidString)
        precondition(payload["id"] == nil && payload["created_at"] == nil && payload["title"] as? String == "Family day")
        do { _ = try TripIdeaEditParameters(draft: TripIdeaDraft()); preconditionFailure("Empty title accepted") }
        catch TripsServiceError.missingTitle { }
        precondition(TripCalendarPreparation.destination(name: "  ", address: "  Park  ") == "Park")
        let tripID = UUID()
        let calendar = try TripCalendarPreparation(tripID: tripID, homeID: home, title: "Adventure", location: nil,
            timezone: "America/Los_Angeles", startDate: "2026-10-31", endDate: "2026-11-01", startTime: nil, endTime: nil)
        precondition(calendar.isAllDay && calendar.endsAt.timeIntervalSince(calendar.startsAt) == 49 * 3600)
        try calendar.save(defaults: defaults); try calendar.save(defaults: defaults)
        precondition(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("homey.tripCalendarDraft.") }.count == 1)
        let timed = try TripCalendarPreparation(tripID: tripID, homeID: home, title: "Adventure", location: nil,
            timezone: "America/Los_Angeles", startDate: "2026-10-20", endDate: nil, startTime: "09:00", endTime: "17:00")
        precondition(!timed.isAllDay && timed.endsAt.timeIntervalSince(timed.startsAt) == 8 * 3600)
        do {
            _ = try TripCalendarPreparation(tripID: tripID, homeID: home, title: "Invalid", location: nil,
                timezone: "America/Los_Angeles", startDate: "2026-10-20", endDate: nil, startTime: "09:00", endTime: nil)
            preconditionFailure("Partial times accepted")
        } catch TripCalendarPreparation.DraftError.invalidSchedule { }
        let multiTimed = try TripCalendarPreparation(tripID: tripID, homeID: home, title: "Two days", location: nil,
            timezone: "America/Los_Angeles", startDate: "2026-10-20", endDate: "2026-10-21", startTime: "09:00", endTime: "17:00")
        precondition(!multiTimed.isAllDay && multiTimed.endsAt.timeIntervalSince(multiTimed.startsAt) == 32 * 3600)
        print("PASS: sorting, joined visibility, payloads, Home/account isolation, durable retries, confirmed Trip recovery, preserved Calendar intent/timezone, legacy migration, unresolved replacement protection, completion, Calendar all-day/DST/times and draft deduplication")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
}
