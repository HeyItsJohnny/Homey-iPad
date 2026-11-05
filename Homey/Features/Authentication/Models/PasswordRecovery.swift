import Foundation

enum PasswordRecoveryState: Equatable {
    case idle, exchanging, ready, updating, success, invalidLink

    var isPresented: Bool { self != .idle }
    var isBusy: Bool { self == .exchanging || self == .updating }
}

enum PasswordRecovery {
    static let redirectURL = URL(string: "homeyipad://auth/reset-password")!

    static func isCallback(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "homeyipad" && parts.host == "auth"
            && parts.percentEncodedPath == "/reset-password" && parts.user == nil
            && parts.password == nil && parts.port == nil
    }

    /// Only PKCE codes from our dedicated recovery client are accepted. Bearer-token
    /// fragments and mixed/duplicate parameters never establish recovery authority.
    static func code(from url: URL) -> String? {
        guard isCallback(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.fragment == nil, let items = parts.queryItems,
              items.count == 1, items[0].name == "code", let code = items[0].value,
              !code.isEmpty, code.utf8.count <= 2048,
              code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).contains($0) })
        else { return nil }
        return code
    }

    static func validEmail(_ email: String) -> Bool {
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    static func passwordError(_ password: String, confirmation: String) -> String? {
        guard !password.isEmpty else { return "Enter your new password." }
        guard password == confirmation else { return "Your passwords do not match." }
        // The project's policy is enforced by Supabase, including strength and
        // breached-password checks. Do not invent a weaker client-side policy.
        return nil
    }
}

struct RecoveryIdentity: Equatable {
    let userID: UUID
    let expiresAt: Date
}

enum RecoveryAuthFailure: Error {
    case policy(String)
    case invalidSession
}

@MainActor
protocol PasswordRecoveryAuth {
    func send(email: String) async throws
    func exchange(code: String) async throws -> RecoveryIdentity
    func validate(identity: RecoveryIdentity) async throws
    func update(password: String) async throws
    func clear() async
}
