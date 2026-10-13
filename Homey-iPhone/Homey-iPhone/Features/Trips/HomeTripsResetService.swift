import Foundation
import Supabase

struct ClearTripsResult: Decodable, Equatable {
    let organizedTripsDeleted: Int
    let sharedTripMembershipsRemoved: Int
    let participantRowsDeleted: Int
    let feedbackRowsDeleted: Int
    let invitesDeleted: Int
    enum CodingKeys: String, CodingKey {
        case organizedTripsDeleted = "organized_trips_deleted"
        case sharedTripMembershipsRemoved = "shared_trip_memberships_removed"
        case participantRowsDeleted = "participant_rows_deleted"
        case feedbackRowsDeleted = "feedback_rows_deleted"
        case invitesDeleted = "invites_deleted"
    }
}

struct HomeTripsResetService {
    private let client = SupabaseManager.shared.client
    func clear(homeID: UUID, role: HomeMemberRole?) async throws -> ClearTripsResult {
        guard role == .owner else { throw ClearTripsError.failed }
        do {
            try Task.checkCancellation()
            let rows: [ClearTripsResult] = try await client.rpc(
                "clear_home_trips", params: ClearTripsParameters(homeID: homeID)
            ).execute().value
            guard let result = rows.first else { throw ClearTripsError.failed }
            return result
        } catch {
            let nsError = error as NSError
            if error is CancellationError || Task.isCancelled || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                throw CancellationError()
            }
            #if DEBUG
            print("[Homey] clear_home_trips failed: \(String(reflecting: error))")
            #endif
            throw ClearTripsError.failed
        }
    }
}

struct ClearTripsParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "requested_home_id" }
}

enum ClearTripsError: LocalizedError {
    case failed
    var errorDescription: String? { "Trips could not be cleared." }
}

enum TripsResetNotice {
    static let name = Notification.Name("homeyTripsDidClear")
    static let confirmation = "This will permanently delete all Trips organized by this Home, including their itineraries, participant selections, invitations, and Trip reviews.\n\nYour Home will also leave any Trips organized by another household.\n\nCalendar events previously created from Trips will not be deleted.\n\nThis cannot be undone."
}
