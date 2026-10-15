import Foundation
import Supabase

/// Trips 2.0 uses the installed RPCs and narrowly scoped RLS-backed idea updates.
struct Trips2Service {
    private let client = SupabaseManager.shared.client

    func trips(homeID: UUID) async throws -> [Trip] {
        let rows: [Trip] = try await client.rpc("get_home_trips", params: TripHomeScope(homeID: homeID)).execute().value
        var seen = Set<UUID>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    func savedIdeas(homeID: UUID) async throws -> [SavedTripIdea] {
        try await client.rpc("get_home_saved_trip_ideas", params: TripHomeScope(homeID: homeID)).execute().value
    }

    func planIdea(_ attempt: TripIdeaPlanningAttempt) async throws -> UUID {
        try Task.checkCancellation()
        guard try await client.auth.session.user.id == attempt.userID else { throw TripPlanningSessionError.changed }
        return try await client.rpc("plan_saved_trip_idea", params: attempt.parameters).execute().value
    }

    @discardableResult
    func link(homeID: UUID, ideaID: UUID, tripID: UUID) async throws -> UUID {
        try Task.checkCancellation()
        return try await client.rpc("link_trip_to_saved_idea", params: TripIdeaLinkParameters(
            homeID: homeID, ideaID: ideaID, tripID: tripID
        )).execute().value
    }

    @discardableResult
    func submitReview(homeID: UUID, tripID: UUID, rating: Int, wouldDoAgain: Bool, notes: String?) async throws -> UUID {
        guard (1...5).contains(rating) else { throw TripReviewInputError.invalidRating }
        try Task.checkCancellation()
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await client.rpc("submit_home_trip_review", params: TripReviewParameters(
            homeID: homeID, tripID: tripID, rating: rating,
            wouldDoAgain: wouldDoAgain, notes: trimmed?.isEmpty == false ? trimmed : nil
        )).execute().value
    }

    func dismissReview(homeID: UUID, tripID: UUID) async throws {
        try Task.checkCancellation()
        try await client.rpc("dismiss_home_trip_review", params: TripReviewScope(homeID: homeID, tripID: tripID)).execute()
    }

    func pendingReviews(homeID: UUID) async throws -> [TripPendingReview] {
        try await client.rpc("get_pending_trip_reviews", params: TripHomeScope(homeID: homeID)).execute().value
    }

    func feedback(homeID: UUID, tripID: UUID) async throws -> TripHouseholdFeedback? {
        let rows: [TripHouseholdFeedback] = try await client.rpc("get_trip_household_feedback", params: TripReviewScope(homeID: homeID, tripID: tripID)).execute().value
        return rows.first
    }

    func awaitingCompletion(homeID: UUID, localDate: String) async throws -> [TripAwaitingCompletion] {
        try await client.rpc("get_home_trips_awaiting_completion", params: TripCompletionScope(
            homeID: homeID, localDate: localDate
        )).execute().value
    }
    func createIdea(homeID: UUID, draft: TripIdeaDraft) async throws -> UUID {
        let userID = try await client.auth.session.user.id
        let payload = try TripIdeaCreateParameters(homeID: homeID, createdBy: userID,
                                                   descriptive: TripIdeaEditParameters(draft: draft))
        let created: TripIdeaIdentity = try await client.from("trip_ideas").insert(payload)
            .select("id").single().execute().value
        return created.id
    }

    func updateIdea(homeID: UUID, ideaID: UUID, draft: TripIdeaDraft) async throws {
        let payload = try TripIdeaEditParameters(draft: draft)
        let _: TripIdeaIdentity = try await client.from("trip_ideas").update(payload)
            .eq("home_id", value: homeID.uuidString).eq("id", value: ideaID.uuidString)
            .select("id").single().execute().value
    }

    func archiveIdea(homeID: UUID, ideaID: UUID) async throws {
        let _: TripIdeaIdentity = try await client.from("trip_ideas").update(TripIdeaArchiveParameters())
            .eq("home_id", value: homeID.uuidString).eq("id", value: ideaID.uuidString)
            .select("id").single().execute().value
    }

}

struct TripHomeScope: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "requested_home_id" }
}

struct TripReviewScope: Encodable {
    let homeID: UUID
    let tripID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", tripID = "requested_trip_id"
    }
}

struct TripIdeaLinkParameters: Encodable {
    let homeID: UUID
    let ideaID: UUID
    let tripID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", ideaID = "requested_idea_id", tripID = "requested_trip_id"
    }
}

struct TripReviewParameters: Encodable {
    let homeID: UUID
    let tripID: UUID
    let rating: Int
    let wouldDoAgain: Bool
    let notes: String?
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", tripID = "requested_trip_id", rating = "requested_rating"
        case wouldDoAgain = "requested_would_do_again", notes = "requested_notes"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(rating, forKey: .rating)
        try container.encode(wouldDoAgain, forKey: .wouldDoAgain)
        try container.encode(notes, forKey: .notes)
    }
}

struct TripCompletionScope: Encodable {
    let homeID: UUID
    let localDate: String
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", localDate = "requested_local_date"
    }
}

enum TripReviewInputError: LocalizedError {
    case invalidRating
    var errorDescription: String? { "Choose a rating from 1 to 5 stars." }
}

enum TripPlanningSessionError: LocalizedError {
    case changed
    var errorDescription: String? { "Sign in to the account that started this planning request to resume it." }
}
