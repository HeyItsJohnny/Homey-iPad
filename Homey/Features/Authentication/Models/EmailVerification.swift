import Foundation

/// Presentation context only. Authentication always comes from Supabase.
struct PendingSignup: Codable, Equatable {
    let email: String
    var resendAvailableAt: Date

    func remainingSeconds(at now: Date) -> Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSince(now))))
    }
}

enum EmailVerification {
    static let redirectURL = URL(string: "homeyipad://auth/verify-email")!
    static let storageKey = "homeyipad.pending-signup.v1"

    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isCallback(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "homeyipad" && parts.host == "auth"
            && parts.percentEncodedPath == "/verify-email" && parts.user == nil
            && parts.password == nil && parts.port == nil
    }

    static func code(from url: URL) -> String? {
        guard isCallback(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.fragment == nil, let items = parts.queryItems,
              items.count == 1, items[0].name == "code", let code = items[0].value,
              !code.isEmpty, code.utf8.count <= 2048,
              code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) })
        else { return nil }
        return code
    }

    static func signupError(firstName: String, lastName: String, displayName: String,
                            email: String, password: String, confirmation: String) -> String? {
        for (value, message) in [(firstName, "Enter your first name."), (lastName, "Enter your last name."),
                                  (displayName, "Enter a display name.")] {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return message }
        }
        guard PasswordRecovery.validEmail(normalize(email)) else { return "Enter a valid email address." }
        guard !password.isEmpty else { return "Enter a password." }
        guard !confirmation.isEmpty else { return "Confirm your password." }
        guard password == confirmation else { return "Passwords do not match." }
        // Supabase enforces the configured password policy.
        return nil
    }

    static func permitsHomeAccess(sessionID: UUID, userID: UUID, email: String?,
                                  emailConfirmed: Bool, anonymous: Bool, expired: Bool) -> Bool {
        sessionID == userID && emailConfirmed && !anonymous && !expired
            && email.map { PasswordRecovery.validEmail($0) } == true
    }
}

struct VerificationIdentity {
    let userID: UUID
    let email: String
    let emailConfirmed: Bool
}

@MainActor
protocol EmailVerificationAuth {
    func resend(email: String) async throws
    func exchange(code: String) async throws -> VerificationIdentity
    func discardSession() async
}

/// Only these name values are sent as signup metadata. No password is retained.
struct SignupNames {
    let metadata: [String: String]

    init(firstName: String, lastName: String, displayName: String) {
        metadata = ["first_name": firstName, "last_name": lastName, "display_name": displayName]
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

struct MissingProfileName {
    let column: String
    let previousValue: String?
    let value: String

    static func repairs(existing: [String: String], metadata: [String: String]) -> [MissingProfileName] {
        ["first_name", "last_name", "display_name"].compactMap { column in
            guard existing[column]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  let value = metadata[column]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return MissingProfileName(column: column, previousValue: existing[column], value: value)
        }
    }
}
