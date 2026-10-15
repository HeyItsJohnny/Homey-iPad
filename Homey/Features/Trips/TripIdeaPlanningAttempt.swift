import Foundation

/// An immutable schedule and request ID survive ambiguous responses and app relaunch.
/// A retry must reuse this value; a new visit starts only after completion is confirmed.
struct TripIdeaPlanningAttempt: Codable, Equatable {
    let userID: UUID
    let homeID: UUID
    let ideaID: UUID
    let requestID: UUID
    let startDate: String
    let endDate: String?
    let startTime: String?
    let endTime: String?
    // Optional fields keep journals written before Calendar planning compatible.
    let addToCalendar: Bool?
    let timezone: String?

    init(userID: UUID, homeID: UUID, ideaID: UUID, startDate: String, endDate: String?,
         startTime: String?, endTime: String?, addToCalendar: Bool? = nil, timezone: String? = nil) {
        self.userID = userID
        self.homeID = homeID
        self.ideaID = ideaID
        self.requestID = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.startTime = startTime
        self.endTime = endTime
        self.addToCalendar = addToCalendar
        self.timezone = timezone
    }

    var parameters: TripIdeaPlanningParameters {
        TripIdeaPlanningParameters(homeID: homeID, ideaID: ideaID, requestID: requestID,
                                   startDate: startDate, endDate: endDate,
                                   startTime: startTime, endTime: endTime)
    }
}

struct TripIdeaPlanningParameters: Encodable {
    let homeID: UUID
    let ideaID: UUID
    let requestID: UUID
    let startDate: String
    let endDate: String?
    let startTime: String?
    let endTime: String?
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", ideaID = "requested_idea_id", requestID = "requested_request_id"
        case startDate = "requested_start_date", endDate = "requested_end_date"
        case startTime = "requested_start_time", endTime = "requested_end_time"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(ideaID, forKey: .ideaID)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
    }
}

struct TripIdeaPlanningStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(userID: UUID, homeID: UUID, ideaID: UUID) throws -> TripIdeaPlanningAttempt? {
        guard let data = defaults.data(forKey: key(userID, homeID, ideaID)) else { return nil }
        let attempt = try JSONDecoder().decode(TripIdeaPlanningAttempt.self, from: data)
        guard attempt.userID == userID, attempt.homeID == homeID, attempt.ideaID == ideaID else {
            throw PlanningStoreError.scopeMismatch
        }
        return attempt
    }

    func save(_ attempt: TripIdeaPlanningAttempt) throws {
        let storageKey = key(attempt.userID, attempt.homeID, attempt.ideaID)
        if let previous = try load(userID: attempt.userID, homeID: attempt.homeID, ideaID: attempt.ideaID),
           previous != attempt { throw PlanningStoreError.unresolvedAttempt }
        defaults.set(try JSONEncoder().encode(attempt), forKey: storageKey)
    }

    /// This receipt records a confirmed canonical Trip, not Calendar synchronization.
    /// Retrying Calendar must never plan another Trip once this receipt is present.
    func confirmedTripID(for attempt: TripIdeaPlanningAttempt) throws -> UUID? {
        guard let data = defaults.data(forKey: receiptKey(attempt)) else { return nil }
        let receipt = try JSONDecoder().decode(TripIdeaPlanningReceipt.self, from: data)
        guard receipt.requestID == attempt.requestID,
              receipt.userID == attempt.userID, receipt.homeID == attempt.homeID,
              receipt.ideaID == attempt.ideaID else { throw PlanningStoreError.scopeMismatch }
        return receipt.tripID
    }

    func confirm(_ attempt: TripIdeaPlanningAttempt, tripID: UUID) throws {
        guard try load(userID: attempt.userID, homeID: attempt.homeID, ideaID: attempt.ideaID) == attempt else {
            throw PlanningStoreError.scopeMismatch
        }
        if let existing = try confirmedTripID(for: attempt), existing != tripID {
            throw PlanningStoreError.scopeMismatch
        }
        defaults.set(try JSONEncoder().encode(TripIdeaPlanningReceipt(
            requestID: attempt.requestID, userID: attempt.userID, homeID: attempt.homeID,
            ideaID: attempt.ideaID, tripID: tripID)), forKey: receiptKey(attempt))
    }

    /// Clear only the exact request whose successful backend result has been confirmed.
    func finish(_ attempt: TripIdeaPlanningAttempt) throws {
        guard try load(userID: attempt.userID, homeID: attempt.homeID, ideaID: attempt.ideaID) == attempt else { return }
        defaults.removeObject(forKey: key(attempt.userID, attempt.homeID, attempt.ideaID))
        defaults.removeObject(forKey: receiptKey(attempt))
    }

    private func receiptKey(_ attempt: TripIdeaPlanningAttempt) -> String {
        key(attempt.userID, attempt.homeID, attempt.ideaID) + ".confirmedTrip"
    }

    private func key(_ userID: UUID, _ homeID: UUID, _ ideaID: UUID) -> String {
        "homey.planSavedIdea.\(userID.uuidString).\(homeID.uuidString).\(ideaID.uuidString)"
    }
}

private struct TripIdeaPlanningReceipt: Codable {
    let requestID: UUID
    let userID: UUID
    let homeID: UUID
    let ideaID: UUID
    let tripID: UUID
}

enum PlanningStoreError: LocalizedError {
    case scopeMismatch, unresolvedAttempt
    var errorDescription: String? {
        "A previous planning request needs to be resolved before starting another visit."
    }
}
