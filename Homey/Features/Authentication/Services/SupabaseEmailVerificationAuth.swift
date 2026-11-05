import Auth
import Foundation
import Supabase

/// Uses the normal auth client's durable Keychain PKCE verifier. Recovery uses
/// its existing separate client and storage key, so the two flows cannot collide.
@MainActor
struct SupabaseEmailVerificationAuth: EmailVerificationAuth {
    private var client: SupabaseClient { SupabaseManager.shared.client }

    func resend(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup, emailRedirectTo: EmailVerification.redirectURL)
    }

    func exchange(code: String) async throws -> VerificationIdentity {
        let session = try await client.auth.exchangeCodeForSession(authCode: code)
        let user = try await client.auth.user(jwt: session.accessToken)
        guard EmailVerification.permitsHomeAccess(sessionID: session.user.id, userID: user.id,
            email: user.email, emailConfirmed: user.emailConfirmedAt != nil,
            anonymous: user.isAnonymous, expired: session.isExpired) else { throw VerificationFailure.invalidIdentity }
        return VerificationIdentity(userID: user.id, email: user.email ?? "", emailConfirmed: true)
    }

    func discardSession() async { try? await client.auth.signOut(scope: .local) }
}

private enum VerificationFailure: Error { case invalidIdentity }
