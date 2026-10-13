import Foundation
import Supabase

struct TripHousehold: Decodable, Identifiable {
    let homeID: UUID
    let role: String
    let status: String
    let isCurrentUserHome: Bool
    var id: UUID { homeID }
    var isOrganizer: Bool { role == "organizer" }
    var isAccepted: Bool { status == "accepted" }
    enum CodingKeys: String, CodingKey {
        case homeID = "home_id", role = "household_role", status = "household_status"
        case isCurrentUserHome = "is_current_user_home"
    }
}

struct TripParticipant: Decodable, Identifiable {
    let homeID: UUID
    let userID: UUID
    let displayName: String?
    let avatarURL: URL?
    var id: String { "\(homeID)-\(userID)" }
    var name: String {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Home Member" : name
    }
    enum CodingKeys: String, CodingKey {
        case homeID = "home_id", userID = "user_id", displayName = "display_name", avatarURL = "avatar_url"
    }
}

struct TripHouseholdInvite: Decodable {
    let inviteID: UUID
    let code: String
    let expiresAt: String
    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id", code = "invite_code", expiresAt = "expires_at"
    }
}

struct TripInvitePreview: Decodable {
    let tripID: UUID
    let title: String
    let destinationName: String?
    let durationType: TripDurationType
    let startDate: String?
    let endDate: String?
    let expiresAt: String
    var dateRange: String? {
        TripDateFormatters.range(
            start: startDate.flatMap(TripDateFormatters.backendDate.date(from:)),
            end: endDate.flatMap(TripDateFormatters.backendDate.date(from:))
        )
    }
    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id", title, destinationName = "destination_name"
        case durationType = "duration_type", startDate = "start_date", endDate = "end_date", expiresAt = "expires_at"
    }
}

struct TripPeopleService {
    private let client = SupabaseManager.shared.client

    func households(tripID: UUID) async throws -> [TripHousehold] {
        try await perform("get_trip_households", params: TripPeopleParameters(tripID: tripID), message: "Households could not be loaded.")
    }

    func participants(tripID: UUID) async throws -> [TripParticipant] {
        try await perform("get_trip_participants", params: TripPeopleParameters(tripID: tripID), message: "People could not be loaded.")
    }

    func saveParticipants(tripID: UUID, homeID: UUID, userIDs: Set<UUID>) async throws {
        try await mutate("save_trip_participants", params: TripPeopleParameters(tripID: tripID, homeID: homeID, userIDs: userIDs.sorted { $0.uuidString < $1.uuidString }), message: "People could not be saved.")
    }

    func createInvite(tripID: UUID) async throws -> TripHouseholdInvite {
        let result: TripSingleResult<TripHouseholdInvite> = try await perform("create_trip_household_invite", params: TripPeopleParameters(tripID: tripID), message: "Trip invitation could not be created.")
        return result.value
    }

    func preview(code: String) async throws -> TripInvitePreview {
        let result: TripSingleResult<TripInvitePreview> = try await perform("preview_trip_household_invite", params: TripPeopleParameters(code: Self.normalizedCode(code)), message: "Trip invitation is invalid or expired.")
        return result.value
    }

    func accept(code: String, homeID: UUID) async throws -> UUID {
        let result: TripSingleResult<TripAcceptedResult> = try await perform("accept_trip_household_invite", params: TripPeopleParameters(homeID: homeID, code: Self.normalizedCode(code)), message: "Trip invitation is invalid or expired.")
        return result.value.tripID
    }

    func removeHousehold(tripID: UUID, homeID: UUID) async throws {
        try await mutate("remove_trip_household", params: TripPeopleParameters(tripID: tripID, homeID: homeID), message: "Household could not be removed.")
    }

    func revokeInvite(tripID: UUID) async throws {
        try await mutate("revoke_trip_household_invite", params: TripPeopleParameters(tripID: tripID), message: "Trip invitation could not be revoked.")
    }

    static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func perform<T: Decodable>(_ operation: String, params: TripPeopleParameters, message: String) async throws -> T {
        do {
            try Task.checkCancellation()
            return try await client.rpc(operation, params: params).execute().value
        } catch { throw sanitized(error, operation: operation, message: message) }
    }

    private func mutate(_ operation: String, params: TripPeopleParameters, message: String) async throws {
        do {
            try Task.checkCancellation()
            try await client.rpc(operation, params: params).execute()
        } catch { throw sanitized(error, operation: operation, message: message) }
    }

    private func sanitized(_ error: Error, operation: String, message: String) -> Error {
        let nsError = error as NSError
        if error is CancellationError || Task.isCancelled || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            return CancellationError()
        }
        #if DEBUG
        // Never log invite codes or RPC payloads.
        print("[Homey Trips] \(operation) failed (\(String(describing: type(of: error))))")
        #endif
        return TripPeopleError(message: message)
    }
}

struct TripPeopleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct TripPeopleParameters: Encodable {
    var tripID: UUID? = nil
    var homeID: UUID? = nil
    var userIDs: [UUID]? = nil
    var code: String? = nil
    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id", homeID = "requested_home_id"
        case userIDs = "requested_user_ids", code = "requested_invite_code"
    }
}

private struct TripSingleResult<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        if var rows = try? decoder.unkeyedContainer() {
            value = try rows.decode(T.self)
        } else {
            value = try T(from: decoder)
        }
    }
}

private struct TripAcceptedResult: Decodable {
    let tripID: UUID
    enum CodingKeys: String, CodingKey { case tripID = "trip_id" }
    init(from decoder: Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(UUID.self) { tripID = id }
        else { tripID = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .tripID) }
    }
}

enum TripInviteDates {
    static func expiration(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: value) else { return "Expiration unavailable" }
        return "Expires \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}
