import Combine
import Foundation

@MainActor
final class EmailVerificationService: ObservableObject {
    @Published private(set) var pending: PendingSignup?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private var lastCooldown: PendingSignup?
    private var generation = 0
    private var deliveredCodes: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: EmailVerification.storageKey + ".cooldown") {
            lastCooldown = try? JSONDecoder().decode(PendingSignup.self, from: data)
        }
        if let data = defaults.data(forKey: EmailVerification.storageKey),
           let saved = try? JSONDecoder().decode(PendingSignup.self, from: data),
           PasswordRecovery.validEmail(saved.email) {
            pending = saved
        }
    }

    func begin(email: String, sent: Bool = false, now: Date = Date()) {
        let email = EmailVerification.normalize(email)
        guard PasswordRecovery.validEmail(email) else { return }
        if pending?.email != email {
            generation += 1
            deliveredCodes.removeAll()
            let availableAt = lastCooldown.flatMap { $0.email == email ? $0.resendAvailableAt : nil } ?? now
            pending = PendingSignup(email: email, resendAvailableAt: max(now, availableAt))
        }
        if sent, let availableAt = pending?.resendAvailableAt {
            pending?.resendAvailableAt = max(availableAt, now.addingTimeInterval(60))
        }
        errorMessage = nil
        message = nil
        persist()
    }

    func clear() {
        generation += 1
        pending = nil
        message = nil
        errorMessage = nil
        defaults.removeObject(forKey: EmailVerification.storageKey)
    }

    func resend(using auth: any EmailVerificationAuth, now: Date = Date()) async {
        guard !isBusy, let pending, pending.remainingSeconds(at: now) == 0 else { return }
        isBusy = true
        let revision = generation
        // Also throttle failed requests; server limits may be longer than our UI cooldown.
        self.pending?.resendAvailableAt = now.addingTimeInterval(60)
        persist()
        message = nil
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await auth.resend(email: pending.email)
            guard revision == generation else { return }
            message = "Verification email requested. Check your inbox and use the latest email."
        } catch {
            guard revision == generation else { return }
            errorMessage = "We couldn't send the email. Check your connection and try again after the countdown. If you've requested several emails, please wait a little longer."
        }
    }

    func handle(_ url: URL, using auth: any EmailVerificationAuth) async -> VerificationIdentity? {
        guard EmailVerification.isCallback(url), !isBusy else { return nil }
        guard let pending else {
            errorMessage = "Open the link on the iPad where you signed up, or log in after confirming your email."
            return nil
        }
        guard let code = EmailVerification.code(from: url) else {
            errorMessage = "This verification link is invalid or expired. Request another email and use the latest link."
            return nil
        }
        guard !deliveredCodes.contains(code) else {
            errorMessage = nil
            return nil
        }
        isBusy = true
        let revision = generation
        errorMessage = nil
        message = nil
        defer { isBusy = false }
        do {
            let identity = try await auth.exchange(code: code)
            guard revision == generation,
                  EmailVerification.normalize(identity.email) == pending.email, identity.emailConfirmed else {
                await auth.discardSession()
                errorMessage = "This link doesn't match your pending signup. Return to Log In to switch accounts."
                return nil
            }
            deliveredCodes.insert(code)
            return identity
        } catch {
            // A code can already be consumed even if fetching the user failed. Password
            // login is a safe fallback after email confirmation; never trust local state.
            await auth.discardSession()
            guard revision == generation else { return nil }
            errorMessage = "We couldn't verify this link. It may be expired, already used, or opened on another device. Use the latest email, request another, or log in if you've already confirmed your email."
            return nil
        }
    }

    private func persist() {
        if let pending, let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: EmailVerification.storageKey)
            // Keep only the latest email's throttle when navigation cancels signup.
            // This record cannot restore the verification screen or grant access.
            lastCooldown = pending
            defaults.set(data, forKey: EmailVerification.storageKey + ".cooldown")
        }
    }
}
