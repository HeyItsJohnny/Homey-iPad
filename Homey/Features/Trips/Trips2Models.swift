import Foundation

struct SavedTripIdea: Decodable, Identifiable, Equatable {
    let id: UUID
    let homeID: UUID
    let title: String
    let destinationName: String?
    let destinationAddress: String?
    let durationType: TripDurationType
    let notes: String?
    let legacyTripID: UUID?
    let createdAt: String
    let updatedAt: String
    let linkedTripCount: Int64
    let completedVisitCount: Int64
    let ratedVisitCount: Int64
    let averageRating: Double?
    let lastVisitedDate: String?
    enum CodingKeys: String, CodingKey {
        case id = "idea_id", homeID = "home_id", title, destinationName = "destination_name"
        case destinationAddress = "destination_address", durationType = "duration_type", notes
        case legacyTripID = "legacy_trip_id", createdAt = "created_at", updatedAt = "updated_at"
        case linkedTripCount = "linked_trip_count", completedVisitCount = "completed_visit_count"
        case ratedVisitCount = "rated_visit_count", averageRating = "average_rating", lastVisitedDate = "last_visited_date"
    }
}

struct TripPendingReview: Decodable, Identifiable {
    let id: UUID
    let organizerHomeID: UUID
    let title: String
    let destinationName: String?
    let durationType: TripDurationType
    let startDate: String?
    let endDate: String?
    let completedAt: String?
    let sourceImageURL: String?
    enum CodingKeys: String, CodingKey {
        case id = "trip_id", organizerHomeID = "organizer_home_id", title
        case destinationName = "destination_name", durationType = "duration_type"
        case startDate = "start_date", endDate = "end_date", completedAt = "completed_at", sourceImageURL = "source_image_url"
    }
}

struct TripAwaitingCompletion: Decodable, Identifiable {
    let id: UUID
    let organizerHomeID: UUID
    let title: String
    let destinationName: String?
    let startDate: String?
    let endDate: String?
    let sourceImageURL: String?
    let daysSinceEnd: Int
    enum CodingKeys: String, CodingKey {
        case id = "trip_id", organizerHomeID = "organizer_home_id", title
        case destinationName = "destination_name", startDate = "start_date", endDate = "end_date"
        case sourceImageURL = "source_image_url", daysSinceEnd = "days_since_end"
    }
}

struct TripIdeaDraft {
    var title = ""
    var destinationName = ""
    var destinationAddress = ""
    var durationType = TripDurationType.dayTrip
    var notes = ""
    init() {}
    init(idea: SavedTripIdea) {
        title = idea.title; destinationName = idea.destinationName ?? ""
        destinationAddress = idea.destinationAddress ?? ""; durationType = idea.durationType; notes = idea.notes ?? ""
    }
    init(trip: Trip) {
        title = trip.title; destinationName = trip.destinationName ?? ""
        destinationAddress = trip.destinationAddress ?? ""; durationType = trip.durationType; notes = trip.notes ?? ""
    }
}

struct TripIdeaEditParameters: Encodable {
    let title: String
    let destinationName: String?
    let destinationAddress: String?
    let durationType: TripDurationType
    let notes: String?
    enum CodingKeys: String, CodingKey {
        case title, destinationName = "destination_name", destinationAddress = "destination_address"
        case durationType = "duration_type", notes
    }
    init(draft: TripIdeaDraft) throws {
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TripsServiceError.missingTitle }
        func clean(_ value: String) -> String? {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        destinationName = clean(draft.destinationName); destinationAddress = clean(draft.destinationAddress)
        durationType = draft.durationType; notes = clean(draft.notes)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(destinationName, forKey: .destinationName)
        try container.encode(destinationAddress, forKey: .destinationAddress)
        try container.encode(durationType, forKey: .durationType)
        try container.encode(notes, forKey: .notes)
    }
}

struct TripIdeaIdentity: Decodable { let id: UUID }
struct TripIdeaArchiveParameters: Encodable {
    let isArchived = true
    enum CodingKeys: String, CodingKey { case isArchived = "is_archived" }
}

struct TripHouseholdFeedback: Decodable, Identifiable {
    let id: UUID
    let rating: Int
    let wouldDoAgain: Bool
    let notes: String?
    let reviewedBy: UUID
    let reviewerDisplayName: String
    let reviewedAt: String
    enum CodingKeys: String, CodingKey {
        case id = "feedback_id", rating, wouldDoAgain = "would_do_again", notes
        case reviewedBy = "reviewed_by", reviewerDisplayName = "reviewer_display_name", reviewedAt = "reviewed_at"
    }
}

struct TripIdeaCreateParameters: Encodable {
    let homeID: UUID
    let createdBy: UUID
    let descriptive: TripIdeaEditParameters
    enum CodingKeys: String, CodingKey { case homeID = "home_id", createdBy = "created_by" }
    func encode(to encoder: Encoder) throws {
        try descriptive.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(createdBy, forKey: .createdBy)
    }
}

struct TripAttentionDestination: Equatable {
    let homeID: UUID
    let tripID: UUID
    let wantsReview: Bool
}
