import Foundation

struct HouseholdInvitationRequest: Codable, Equatable {
    let homeID: UUID
    let recipientEmail: String
    let role: HomeMemberRole
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "home_id", recipientEmail = "recipient_email", role, requestID = "request_id"
    }
}

enum HouseholdInvitationFailure: Error, Equatable {
    case backend(String)
    case uncertain

    var message: String {
        switch self {
        case .uncertain:
            return "We couldn't confirm whether the invitation email was sent. Please check your pending invitations before trying again."
        case .backend(let code):
            switch code {
            case "invalid_recipient": return "Enter a valid email address."
            case "invalid_role": return "Choose Member or Admin."
            case "invalid_home_id": return "Please choose a Home and try again."
            case "invalid_request", "invalid_request_id": return "This invitation request could not be processed. Please try again."
            case "unauthorized": return "Please sign in and try again."
            case "unverified_email": return "Please verify your email before inviting members."
            case "insufficient_home_permissions": return "Only Home Owners and Admins can invite members."
            case "already_pending_invitation": return "This person already has a pending invitation."
            case "request_conflict": return "This request belongs to another invitation. Check your pending invitations."
            case "invitation_unavailable", "invitation_terminal": return "This invitation is no longer available. Check your pending invitations."
            case "rate_limited": return "Too many invitations have been requested. Please try again later."
            case "provider_failure": return "The email provider could not accept this invitation. Please try again later."
            case "service_unavailable": return "Invitations are temporarily unavailable. Please try again later."
            default: return HouseholdInvitationFailure.uncertain.message
            }
        }
    }

    // Do not infer delivery from HTTP 2xx alone or display server-supplied details.
    static func validateResponse(_ data: Data) throws {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Self.uncertain
        }
        let nested = body["error"] as? [String: Any]
        if let code = body["error"] as? String ?? nested?["code"] as? String ?? body["code"] as? String {
            throw code == "delivery_uncertain" ? Self.uncertain : Self.backend(code)
        }
        let status = body["delivery_status"] as? String ?? body["status"] as? String
        if status == "delivery_uncertain" || body["success"] as? Bool == false { throw Self.uncertain }
        if status == "sent" || status == "accepted" || (body["success"] as? Bool == true && status == nil) { return }
        throw Self.uncertain
    }

    static func joinMessage(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("unverified") || text.contains("verif") {
            return "Verify your email address before joining a Home."
        }
        if error is URLError { return "Couldn't connect to Homey. Please check your connection and try again." }
        if text.contains("expired") { return "This invitation has expired. Ask for a new invitation." }
        if text.contains("accepted") || text.contains("used") { return "This invitation has already been used." }
        if text.contains("cancel") || text.contains("declin") || text.contains("revok") {
            return "This invitation is no longer available."
        }
        if text.contains("email") { return "This invitation isn't available for this account. Check the account you're signed in with." }
        return "This invitation couldn't be accepted. Check your code and account, or ask for a new invitation."
    }
}

/// Keeps request IDs across sheet dismissal, network errors and app restarts.
/// No invitation code, token or backend response is persisted.
@MainActor
final class HouseholdInvitationFlow {
    private let defaults: UserDefaults
    private let storageKey = "homeyipad.invitation-request-ids"
    private(set) var isSending = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func validEmail(_ email: String) -> Bool {
        email.count <= 254 && email.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
                                         options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func normalizedCode(_ code: String) -> String { code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    static func validCode(_ code: String) -> Bool {
        // Format only; the database decides validity, expiration and one-time use.
        code.range(of: #"^[A-Z0-9]{4}(-[A-Z0-9]{4}){7}$"#, options: .regularExpression) != nil
    }

    func send(userID: UUID, homeID: UUID, email: String, role: HomeMemberRole,
              senderRole: HomeMemberRole?, verified: Bool,
              invoke: (HouseholdInvitationRequest) async throws -> Void,
              refresh: () async -> Void) async throws -> Bool {
        guard !isSending else { return false }
        guard verified else { throw HouseholdInvitationFailure.backend("unverified_email") }
        guard senderRole == .owner || senderRole == .admin else {
            throw HouseholdInvitationFailure.backend("insufficient_home_permissions")
        }
        let recipient = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.validEmail(recipient) else { throw HouseholdInvitationFailure.backend("invalid_recipient") }
        guard role.canBeInvited else { throw HouseholdInvitationFailure.backend("invalid_role") }
        isSending = true
        defer { isSending = false }
        let key = "\(userID)|\(homeID)|\(recipient)|\(role.rawValue)"
        var ledger = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        let requestID = ledger[key].flatMap(UUID.init(uuidString:)) ?? UUID()
        ledger[key] = requestID.uuidString
        defaults.set(ledger, forKey: storageKey)
        // Retain IDs after all failures, including unknown responses and terminal errors.
        // A confirmed send ends this logical request; the backend prevents pending duplicates.
        try await invoke(.init(homeID: homeID, recipientEmail: recipient, role: role, requestID: requestID))
        ledger = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        ledger.removeValue(forKey: key)
        defaults.set(ledger, forKey: storageKey)
        await refresh()
        return true
    }
}

@MainActor
final class HouseholdCodeRedemption {
    private(set) var isBusy = false
    private var joined: (userID: UUID, homeID: UUID)?

    func reset() { joined = nil }

    func redeem(_ input: String, userID: UUID, verified: Bool, isCurrent: () -> Bool,
                invoke: (String) async throws -> UUID) async throws -> Bool {
        guard !isBusy, isCurrent() else { return false }
        guard verified else { throw HouseholdInvitationFailure.backend("unverified_email") }
        if joined?.userID == userID { return true }
        let code = HouseholdInvitationFlow.normalizedCode(input)
        guard HouseholdInvitationFlow.validCode(code) else { throw CodeFailure.invalid }
        isBusy = true
        defer { isBusy = false }
        let homeID = try await invoke(code)
        guard isCurrent() else { return false }
        joined = (userID, homeID)
        return true
    }

    func finish(userID: UUID, isCurrent: () -> Bool,
                refresh: () async throws -> [UUID], navigate: (UUID) -> Void) async throws -> Bool {
        guard !isBusy, isCurrent(), let joined, joined.userID == userID else { return false }
        isBusy = true
        defer { isBusy = false }
        let homes = try await refresh()
        guard isCurrent() else { return false }
        guard homes.contains(joined.homeID) else { throw CodeFailure.membershipUnavailable }
        navigate(joined.homeID)
        self.joined = nil
        return true
    }

    enum CodeFailure: Error { case invalid, membershipUnavailable }
}
