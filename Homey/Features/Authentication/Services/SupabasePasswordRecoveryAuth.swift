import Auth
import Foundation
import Supabase

/// Recovery has its own Keychain namespace and never changes the household session.
/// Its PKCE verifier survives a cold launch and cannot be overwritten by normal auth.
@MainActor
final class SupabasePasswordRecoveryAuth: PasswordRecoveryAuth {
    private let client = SupabaseClient(
        supabaseURL: AppConfiguration.supabaseURL,
        supabaseKey: AppConfiguration.supabasePublishableKey,
        options: SupabaseClientOptions(auth: .init(
            storageKey: "homeyipad.password-recovery",
            flowType: .pkce,
            autoRefreshToken: false
        ))
    )

    func send(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: PasswordRecovery.redirectURL)
    }

    func exchange(code: String) async throws -> RecoveryIdentity {
        // No fallback to a cached session. Missing verifier, expired and reused codes
        // must fail at the server. This client only issues recovery challenges.
        let session = try await client.auth.exchangeCodeForSession(authCode: code)
        return RecoveryIdentity(userID: session.user.id, expiresAt: Date(timeIntervalSince1970: session.expiresAt))
    }

    func validate(identity: RecoveryIdentity) async throws {
        guard let session = client.auth.currentSession,
              session.user.id == identity.userID, !session.isExpired else {
            throw RecoveryAuthFailure.invalidSession
        }
        do {
            let user = try await client.auth.user(jwt: session.accessToken)
            guard user.id == identity.userID, !user.isAnonymous else { throw RecoveryAuthFailure.invalidSession }
        } catch let error as AuthError {
            if [.invalidJWT, .badJWT, .sessionNotFound, .sessionExpired, .userNotFound].contains(error.errorCode) {
                throw RecoveryAuthFailure.invalidSession
            }
            throw error
        }
    }

    func update(password: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
        } catch let error as AuthError {
            switch error {
            case .weakPassword(let message, _):
                throw RecoveryAuthFailure.policy(message)
            default:
                if error.errorCode == .weakPassword {
                    throw RecoveryAuthFailure.policy(error.message)
                }
                if error.errorCode == .samePassword {
                    throw RecoveryAuthFailure.policy("Choose a password you have not used before.")
                }
                if [.invalidJWT, .badJWT, .sessionNotFound, .sessionExpired, .userNotFound].contains(error.errorCode) {
                    throw RecoveryAuthFailure.invalidSession
                }
                throw error
            }
        }
    }

    func clear() async {
        // SDK removes the local Keychain session before sending the logout request.
        // .local revokes only the recovery session, preserving other devices.
        try? await client.auth.signOut(scope: .local)
    }
}
