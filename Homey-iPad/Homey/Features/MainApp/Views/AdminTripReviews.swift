import SwiftUI
import Supabase

struct AdminPendingTripReview: Decodable, Identifiable, Equatable, Sendable {
    let tripID: UUID
    let organizerHomeID: UUID
    let title: String
    let destinationName: String?
    let durationType: String
    let startDate: String?
    let endDate: String?
    let completedAt: String?
    let sourceImageURL: String?
    var id: UUID { tripID }

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id", organizerHomeID = "organizer_home_id", title
        case destinationName = "destination_name", durationType = "duration_type"
        case startDate = "start_date", endDate = "end_date", completedAt = "completed_at", sourceImageURL = "source_image_url"
    }
}

struct AdminTripReviewDraft: Equatable {
    var rating: Int? = nil
    var wouldDoAgain = false
    var notes = ""
    var isValid: Bool { rating.map { (1...5).contains($0) } == true }
    var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AdminTripReviewError: LocalizedError {
    case sessionExpired, loadFailed, reviewFailed, invalidRating
    var errorDescription: String? {
        switch self {
        case .sessionExpired: "Admin session expired. Enter a PIN to continue."
        case .loadFailed: "Trip reviews could not be loaded. Please try again."
        case .reviewFailed: "Trip could not be reviewed. Please try again."
        case .invalidRating: "Choose a rating from 1 to 5 stars."
        }
    }

    static func isSessionExpiry(_ error: Error) -> Bool {
        let message = ((error as? PostgrestError)?.message ?? error.localizedDescription).lowercased()
        return message.contains("admin session") && (message.contains("invalid") || message.contains("expired"))
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isCancellation(underlying) }
        return false
    }
}

protocol AdminTripReviewServing {
    func pendingReviews(homeID: UUID) async throws -> [AdminPendingTripReview]
    func submit(homeID: UUID, sessionToken: String, tripID: UUID, draft: AdminTripReviewDraft) async throws -> UUID
}

struct AdminTripReviewService: AdminTripReviewServing {
    private let client = SupabaseManager.shared.client

    func pendingReviews(homeID: UUID) async throws -> [AdminPendingTripReview] {
        do {
            try Task.checkCancellation()
            return try await client.rpc("get_pending_trip_reviews", params: AdminTripReviewHomeParameters(homeID: homeID)).execute().value
        } catch {
            if AdminTripReviewError.isCancellation(error) { throw CancellationError() }
            if AdminTripReviewError.isSessionExpiry(error) { throw AdminTripReviewError.sessionExpired }
            throw AdminTripReviewError.loadFailed
        }
    }

    func submit(homeID: UUID, sessionToken: String, tripID: UUID, draft: AdminTripReviewDraft) async throws -> UUID {
        guard draft.isValid, let rating = draft.rating else { throw AdminTripReviewError.invalidRating }
        do {
            try Task.checkCancellation()
            let feedbackID: UUID = try await client.rpc(
                "submit_trip_household_feedback_with_admin_session",
                params: AdminTripReviewParameters(homeID: homeID, sessionToken: sessionToken, tripID: tripID,
                                                  rating: rating, wouldDoAgain: draft.wouldDoAgain, notes: draft.normalizedNotes)
            ).execute().value
            return feedbackID
        } catch {
            if AdminTripReviewError.isCancellation(error) { throw CancellationError() }
            #if DEBUG
            // Never print the PIN session token or request payload.
            if let error = error as? PostgrestError {
                let details = [error.code, error.message, error.detail, error.hint].compactMap { $0 }.joined(separator: " | ")
                print("[Homey] ADMIN TRIP REVIEW ERROR: \(details.replacingOccurrences(of: sessionToken, with: "[redacted]"))")
            } else {
                print("[Homey] ADMIN TRIP REVIEW ERROR: \(String(reflecting: type(of: error)))")
            }
            #endif
            if AdminTripReviewError.isSessionExpiry(error) { throw AdminTripReviewError.sessionExpired }
            throw AdminTripReviewError.reviewFailed
        }
    }
}

struct AdminTripReviewHomeParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "requested_home_id" }
}

struct AdminTripReviewParameters: Encodable {
    let homeID: UUID
    let sessionToken: String
    let tripID: UUID
    let rating: Int
    let wouldDoAgain: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id", sessionToken = "requested_session_token", tripID = "requested_trip_id"
        case rating = "requested_rating", wouldDoAgain = "requested_would_do_again", notes = "requested_notes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(sessionToken, forKey: .sessionToken)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(rating, forKey: .rating)
        try container.encode(wouldDoAgain, forKey: .wouldDoAgain)
        if let notes { try container.encode(notes, forKey: .notes) }
        else { try container.encodeNil(forKey: .notes) }
    }
}

struct AdminTripReviewCard: View {
    let trip: AdminPendingTripReview
    let timezone: TimeZone
    let isProcessing: Bool
    let onSubmit: (AdminTripReviewDraft) -> Void
    @State private var draft = AdminTripReviewDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("TRIP REVIEW", systemImage: "map.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
            HStack(alignment: .top, spacing: 18) {
                artwork
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.title)
                        .font(.title2.bold())
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    if let destination = trip.destinationName, !destination.isEmpty {
                        Text(destination).font(.headline).foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                    if let completedText {
                        Text(completedText).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                }
                Spacer()
            }
            Text("How was this trip?").font(.headline).foregroundStyle(HomeyDashboardTheme.primaryText)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { rating in
                    Button { draft.rating = rating } label: {
                        Image(systemName: rating <= (draft.rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rating) out of 5 stars")
                    .accessibilityAddTraits(draft.rating == rating ? .isSelected : [])
                }
            }
            Toggle("Would Do Again", isOn: $draft.wouldDoAgain)
                .font(.headline)
                .tint(HomeyDashboardTheme.sageAccent)
            TextField("Notes for next time (optional)", text: $draft.notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14))
            Button { onSubmit(draft) } label: {
                HStack(spacing: 10) {
                    if isProcessing { ProgressView().tint(.white) }
                    Text(isProcessing ? "Submitting…" : "Submit Review")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(HomeyDashboardTheme.warmBrown, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(!draft.isValid || isProcessing)
            .opacity(draft.isValid ? 1 : 0.5)
        }
        .padding(24)
        .dashboardCard(cornerRadius: 28)
        .disabled(isProcessing)
    }

    private var artwork: some View {
        AsyncImage(url: trip.sourceImageURL.flatMap(URL.init(string:))) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() }
            else {
                Image(systemName: "map.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HomeyDashboardTheme.selectedSidebarBackground)
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityHidden(true)
    }

    private var completedText: String? {
        guard let value = trip.completedAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = iso.date(from: value)
        iso.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? iso.date(from: value) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateStyle = .medium
        return "Completed \(formatter.string(from: date))"
    }
}
