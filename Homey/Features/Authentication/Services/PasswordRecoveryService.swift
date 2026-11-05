import Combine
import Foundation

@MainActor
final class PasswordRecoveryService: ObservableObject {
    @Published private(set) var state: PasswordRecoveryState = .idle
    @Published private(set) var isSending = false
    @Published private(set) var requestError: String?
    @Published private(set) var errorMessage: String?
    private let auth: any PasswordRecoveryAuth
    private var identity: RecoveryIdentity?
    private var lastRequestAt: Date?

    init(auth: any PasswordRecoveryAuth) { self.auth = auth }

    func send(email: String) async -> Bool {
        guard !isSending, state == .idle else { return false }
        requestError = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PasswordRecovery.validEmail(email) else {
            requestError = "Enter a valid email address."
            return false
        }
        guard lastRequestAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else {
            requestError = "Please wait a minute before requesting another email."
            return false
        }
        isSending = true
        defer { isSending = false }
        do {
            try await auth.send(email: email)
            lastRequestAt = Date()
            return true
        } catch {
            // Never display raw Auth errors or account-existence information.
            requestError = "We could not send a reset email. Please wait a moment and try again."
            return false
        }
    }

    func handle(_ url: URL) async {
        guard PasswordRecovery.isCallback(url), state == .idle, !isSending else { return }
        state = .exchanging // Synchronous before any suspension; duplicate deliveries are ignored.
        errorMessage = nil
        guard let code = PasswordRecovery.code(from: url) else {
            state = .invalidLink
            return
        }
        do {
            let recovered = try await auth.exchange(code: code)
            guard recovered.expiresAt > Date() else { throw RecoveryAuthFailure.invalidSession }
            try await auth.validate(identity: recovered)
            identity = recovered
            // SDK 2.53 PKCE exchange emits signedIn, not passwordRecovery.
            // Explicit state, tied to this isolated exchange, controls presentation.
            state = .ready
        } catch {
            identity = nil
            await auth.clear()
            state = .invalidLink
        }
    }

    func update(password: String, confirmation: String) async -> Bool {
        guard state == .ready, let identity else { return false }
        errorMessage = PasswordRecovery.passwordError(password, confirmation: confirmation)
        guard errorMessage == nil else { return false }
        state = .updating
        do {
            guard identity.expiresAt > Date() else { throw RecoveryAuthFailure.invalidSession }
            try await auth.validate(identity: identity)
            try await auth.update(password: password)
            self.identity = nil
            await auth.clear()
            state = .success
            return true
        } catch RecoveryAuthFailure.policy(let message) {
            errorMessage = message
            state = .ready
        } catch RecoveryAuthFailure.invalidSession {
            self.identity = nil
            await auth.clear()
            state = .invalidLink
        } catch {
            errorMessage = "We could not update your password. Check your connection and try again."
            state = .ready
        }
        return false
    }

    func dismiss() async {
        guard !state.isBusy else { return }
        // Block callbacks until cleanup finishes; never restore this recovery session.
        state = .exchanging
        identity = nil
        await auth.clear()
        errorMessage = nil
        state = .idle
    }
}
