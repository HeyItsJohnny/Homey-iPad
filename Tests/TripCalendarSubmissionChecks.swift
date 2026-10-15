import Foundation

@MainActor
private final class FakeCalendar: TripCalendarEventService {
    var eventID: UUID?
    var creates = 0
    var reads = 0
    var failRead = false
    var failCreate = false
    var commitBeforeFailure = false
    var pauseCreate = false
    var onRead: (() -> Void)?
    var lastDraft: TripCalendarPreparation?
    enum Failure: Error { case offline }
    func matchingEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID? {
        reads += 1; onRead?()
        if failRead { throw Failure.offline }
        return eventID
    }
    func createEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID {
        creates += 1; lastDraft = draft
        if pauseCreate { try await Task.sleep(nanoseconds: 20_000_000) }
        if !failCreate || commitBeforeFailure { eventID = UUID() }
        if failCreate { throw Failure.offline }
        return eventID!
    }
}

@main struct TripCalendarSubmissionChecks {
    @MainActor static func main() async throws {
        let suite = "TripCalendarSubmissionChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let user = UUID(), home = UUID()
        func draft(_ tripID: UUID = UUID(), _ homeID: UUID? = nil) throws -> TripCalendarPreparation {
            try TripCalendarPreparation(tripID: tripID, homeID: homeID ?? home, title: "Family outing", location: "Park",
                timezone: "America/Los_Angeles", startDate: "2026-10-31", endDate: "2026-11-01",
                startTime: nil, endTime: nil, notes: "Bring snacks")
        }
        let backend = FakeCalendar()
        let screen = TripCalendarSubmission(service: backend, defaults: defaults)
        let payload = try draft()
        let added = await screen.submit(payload, userID: user) { true }
        precondition(added && backend.creates == 1 && screen.isComplete)
        precondition(backend.lastDraft == payload && payload.endsAt.timeIntervalSince(payload.startsAt) == 49 * 3600)
        let repeatTap = await screen.submit(payload, userID: user) { true }
        precondition(repeatTap && backend.creates == 1)
        let relaunched = TripCalendarSubmission(service: backend, defaults: defaults)
        let confirmed = await relaunched.submit(payload, userID: user) { true }
        precondition(confirmed && backend.creates == 1)

        let existing = FakeCalendar(); existing.eventID = UUID()
        let existingScreen = TripCalendarSubmission(service: existing, defaults: defaults)
        let found = await existingScreen.submit(try draft(), userID: user) { true }
        precondition(found && existing.creates == 0)

        let uncertain = FakeCalendar(); uncertain.failCreate = true
        let uncertainDraft = try draft()
        let uncertainScreen = TripCalendarSubmission(service: uncertain, defaults: defaults)
        let failed = await uncertainScreen.submit(uncertainDraft, userID: user) { true }
        precondition(!failed && uncertainScreen.needsReconciliation && uncertain.creates == 1 && uncertainScreen.errorMessage != nil)
        let reopened = TripCalendarSubmission(service: uncertain, defaults: defaults)
        let stillUncertain = await reopened.submit(uncertainDraft, userID: user) { true }
        precondition(!stillUncertain && uncertain.creates == 1)
        uncertain.eventID = UUID() // delayed backend visibility after an ambiguous response
        let reconciled = await reopened.submit(uncertainDraft, userID: user) { true }
        precondition(reconciled && uncertain.creates == 1)

        let lostResponse = FakeCalendar(); lostResponse.failCreate = true; lostResponse.commitBeforeFailure = true
        let lostScreen = TripCalendarSubmission(service: lostResponse, defaults: defaults)
        let recovered = await lostScreen.submit(try draft(), userID: user) { true }
        precondition(recovered && lostResponse.creates == 1)

        let offline = FakeCalendar(); offline.failRead = true
        let offlineScreen = TripCalendarSubmission(service: offline, defaults: defaults)
        let offlineDraft = try draft()
        let offlineResult = await offlineScreen.submit(offlineDraft, userID: user) { true }
        precondition(!offlineResult && offline.creates == 0 && !offlineScreen.needsReconciliation)
        offline.failRead = false
        let onlineResult = await offlineScreen.submit(offlineDraft, userID: user) { true }
        precondition(onlineResult && offline.creates == 1)

        let slow = FakeCalendar(); slow.pauseCreate = true
        let slowScreen = TripCalendarSubmission(service: slow, defaults: defaults)
        let slowDraft = try draft()
        let first = Task { await slowScreen.submit(slowDraft, userID: user) { true } }
        while !slowScreen.isSaving { await Task.yield() }
        let simultaneous = await slowScreen.submit(slowDraft, userID: user) { true }
        precondition(!simultaneous)
        let firstResult = await first.value
        precondition(firstResult && slow.creates == 1)

        var currentHome = true
        let switched = FakeCalendar(); switched.onRead = { currentHome = false }
        let switchedScreen = TripCalendarSubmission(service: switched, defaults: defaults)
        let switchedResult = await switchedScreen.submit(try draft(), userID: user) { currentHome }
        precondition(!switchedResult && switched.creates == 0)
        let otherUser = UUID()
        let isolated = FakeCalendar()
        let isolatedScreen = TripCalendarSubmission(service: isolated, defaults: defaults)
        let isolatedResult = await isolatedScreen.submit(uncertainDraft, userID: otherUser) { true }
        precondition(isolatedResult && isolated.creates == 1)
        let otherHomeResult = await isolatedScreen.submit(try draft(uncertainDraft.tripID, UUID()), userID: otherUser) { true }
        precondition(otherHomeResult && isolated.reads >= 2)
        print("PASS: Calendar submission, exact payload, existing-event skip, repeated taps, concurrent tap guard, lost-response reconciliation, relaunch recovery, preflight failure/retry, Home switch and account/Home scoping")
    }
}
