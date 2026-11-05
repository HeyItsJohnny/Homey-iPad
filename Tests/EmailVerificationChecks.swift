import Foundation

@MainActor
private final class FakeVerificationAuth: EmailVerificationAuth {
    var sends: [String] = []
    var codes: [String] = []
    var discarded = 0
    var fails = false
    var pauseSend = false
    var pauseExchange = false
    var continuation: CheckedContinuation<Void, Never>?
    var identity = VerificationIdentity(userID: UUID(), email: "member@example.com", emailConfirmed: true)
    func resend(email: String) async throws {
        sends.append(email)
        if pauseSend { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.notConnectedToInternet) }
    }
    func exchange(code: String) async throws -> VerificationIdentity {
        codes.append(code)
        if pauseExchange { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.badServerResponse) }
        return identity
    }
    func discardSession() async { discarded += 1 }
}

@main
struct EmailVerificationChecks {
    @MainActor
    static func main() async {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label)
            count += 1
        }
        let valid = "member@example.com"
        func validation(_ first: String = "First", _ last: String = "Last", _ display: String = "Member",
                        _ email: String = valid, _ password: String = "password", _ confirm: String = "password") -> String? {
            EmailVerification.signupError(firstName: first, lastName: last, displayName: display,
                                          email: email, password: password, confirmation: confirm)
        }
        check(validation() == nil, "valid signup")
        check(validation(" ") != nil, "required first name")
        check(validation("First", "") != nil, "required last name")
        check(validation("First", "Last", " ") != nil, "required display name")
        check(validation("First", "Last", "Member", "invalid") != nil, "invalid email")
        check(validation("First", "Last", "Member", valid, "", "") != nil, "required password")
        check(validation("First", "Last", "Member", valid, "password", "") != nil, "required confirmation")
        check(validation("First", "Last", "Member", valid, "password", "different") != nil, "matching passwords")
        check(EmailVerification.normalize("  MEMBER@example.com\n") == valid, "normalize email")
        let names = SignupNames(firstName: " First ", lastName: "Last", displayName: " Member ")
        check(names.metadata == ["first_name": "First", "last_name": "Last", "display_name": "Member"], "exact signup metadata")
        check(EmailVerification.redirectURL.absoluteString == "homeyipad://auth/verify-email", "iPad signup redirect")
        let callback = URL(string: "homeyipad://auth/verify-email?code=abc-123_xyz")!
        check(EmailVerification.code(from: callback) == "abc-123_xyz", "valid PKCE code")
        for url in ["homey://auth/verify-email?code=abc", "https://auth/verify-email?code=abc",
                    "homeyipad://other/verify-email?code=abc", "homeyipad://auth/reset-password?code=abc",
                    "homeyipad://auth/verify-email/?code=abc", "homeyipad://auth/verify%2Demail?code=abc",
                    "homeyipad://user@auth/verify-email?code=abc", "homeyipad://auth:123/verify-email?code=abc",
                    "homeyipad://auth/verify-email?code=", "homeyipad://auth/verify-email?code=abc&code=def",
                    "homeyipad://auth/verify-email?code=abc&extra=def", "homeyipad://auth/verify-email#access_token=secret",
                    "homeyipad://auth/verify-email?code=bad%20code", "homeyipad://auth/verify-email?error=access_denied"] {
            check(EmailVerification.code(from: URL(string: url)!) == nil, "reject malformed callback: \(url)")
        }
        let id = UUID()
        func permits(_ sessionID: UUID = id, _ userID: UUID = id, _ confirmed: Bool = true,
                     _ anonymous: Bool = false, _ expired: Bool = false, _ email: String? = valid) -> Bool {
            EmailVerification.permitsHomeAccess(sessionID: sessionID, userID: userID, email: email,
                emailConfirmed: confirmed, anonymous: anonymous, expired: expired)
        }
        check(permits(), "verified account allowed")
        check(!permits(id, id, false), "unverified email blocked regardless of generic confirmation")
        check(!permits(UUID()), "identity mismatch blocked")
        check(!permits(id, id, true, true), "anonymous blocked")
        check(!permits(id, id, true, false, true), "expired session blocked")
        check(!permits(id, id, true, false, false, nil), "missing email blocked")
        let repairs = MissingProfileName.repairs(existing: ["first_name": "Preserved", "last_name": " "],
            metadata: ["first_name": "Replacement", "last_name": " Last ", "display_name": "Member", "avatar_url": "unrelated"])
        check(repairs.count == 2, "fill only missing names")
        check(!repairs.contains { $0.column == "first_name" }, "preserve valid names")
        check(repairs.first?.previousValue == " ", "conditional repair preserves concurrent writes")
        check(MissingProfileName.repairs(existing: ["first_name": "First", "last_name": "Last", "display_name": "Member"], metadata: names.metadata).isEmpty, "profile initialization idempotent")
        let suite = "homey.verification-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let flow = EmailVerificationService(defaults: defaults)
        let auth = FakeVerificationAuth()
        flow.begin(email: " MEMBER@example.com ", sent: true, now: clock)
        check(flow.pending?.email == valid, "pending presentation without authenticated profile")
        check(flow.pending?.remainingSeconds(at: clock) == 60, "initial cooldown")
        let restored = EmailVerificationService(defaults: defaults)
        check(restored.pending == flow.pending, "cold launch persistence")
        check(restored.pending?.remainingSeconds(at: clock.addingTimeInterval(35)) == 25, "elapsed background countdown")
        check(restored.pending?.remainingSeconds(at: clock.addingTimeInterval(100)) == 0, "cooldown expires")
        let saved = defaults.data(forKey: EmailVerification.storageKey)!
        let keys = Set((try! JSONSerialization.jsonObject(with: saved) as! [String: Any]).keys)
        check(keys == ["email", "resendAvailableAt"], "persist only safe context, never passwords or authority")
        await flow.resend(using: auth, now: clock)
        check(auth.sends.isEmpty, "resend blocked by cooldown")
        auth.pauseSend = true
        let sending = Task { await flow.resend(using: auth, now: clock.addingTimeInterval(61)) }
        while auth.continuation == nil { await Task.yield() }
        await flow.resend(using: auth, now: clock.addingTimeInterval(122))
        check(auth.sends.count == 1, "prevent concurrent resend")
        check(flow.isBusy, "busy while sending")
        auth.continuation?.resume(); auth.continuation = nil
        await sending.value
        check(flow.message != nil && flow.pending != nil, "resend success never grants verification")
        check(auth.sends == [valid], "resend targets pending address")
        auth.pauseSend = false
        auth.fails = true
        await flow.resend(using: auth, now: clock.addingTimeInterval(122))
        check(flow.errorMessage != nil, "network/rate-limit error presented")
        check(flow.pending?.remainingSeconds(at: clock.addingTimeInterval(122)) == 60, "failed request cooldown persists")
        auth.fails = false
        let invalid = await flow.handle(URL(string: "homeyipad://auth/verify-email?error_code=otp_expired")!, using: auth)
        check(invalid == nil && flow.errorMessage != nil && auth.codes.isEmpty, "expired redirect never exchanges")
        auth.pauseExchange = true
        let exchange = Task { await flow.handle(callback, using: auth) }
        while auth.continuation == nil { await Task.yield() }
        let duplicate = await flow.handle(callback, using: auth)
        check(duplicate == nil && auth.codes.count == 1, "concurrent callback delivered once")
        auth.continuation?.resume(); auth.continuation = nil
        let verified = await exchange.value
        check(verified?.userID == auth.identity.userID, "successful PKCE authoritative identity returned")
        let delivered = await flow.handle(callback, using: auth)
        check(delivered == nil && auth.codes.count == 1, "repeated successful callback ignored")
        auth.pauseExchange = false
        auth.identity = VerificationIdentity(userID: UUID(), email: "other@example.com", emailConfirmed: true)
        let mismatch = await flow.handle(URL(string: "homeyipad://auth/verify-email?code=other")!, using: auth)
        check(mismatch == nil && auth.discarded == 1, "wrong account session discarded")
        auth.identity = VerificationIdentity(userID: UUID(), email: valid, emailConfirmed: false)
        let unverified = await flow.handle(URL(string: "homeyipad://auth/verify-email?code=unverified")!, using: auth)
        check(unverified == nil && auth.discarded == 2, "unverified authoritative user rejected")
        auth.fails = true
        let expired = await flow.handle(URL(string: "homeyipad://auth/verify-email?code=expired")!, using: auth)
        check(expired == nil && flow.pending != nil && auth.discarded == 3, "expired/consumed/missing verifier failures retain recovery")
        flow.begin(email: "new@example.com", now: clock)
        check(flow.pending?.email == "new@example.com", "account switching replaces pending context")
        flow.clear()
        check(flow.pending == nil && defaults.data(forKey: EmailVerification.storageKey) == nil, "cancel/verification clears persistence")
        let afterCancel = EmailVerificationService(defaults: defaults)
        afterCancel.begin(email: "new@example.com", sent: true, now: clock)
        afterCancel.clear()
        let afterNavigation = EmailVerificationService(defaults: defaults)
        check(afterNavigation.pending == nil, "cancelled context does not restore screen")
        afterNavigation.begin(email: "new@example.com", now: clock.addingTimeInterval(20))
        check(afterNavigation.pending?.remainingSeconds(at: clock.addingTimeInterval(20)) == 40, "navigation preserves latest email cooldown")
        afterNavigation.clear()
        let calls = auth.codes.count
        let wrongDevice = await flow.handle(callback, using: auth)
        check(wrongDevice == nil && auth.codes.count == calls, "missing signup context requires login or origin device")
        let late = EmailVerificationService(defaults: defaults)
        let delayed = FakeVerificationAuth()
        late.begin(email: valid, now: clock)
        delayed.pauseExchange = true
        let delayedCallback = Task { await late.handle(callback, using: delayed) }
        while delayed.continuation == nil { await Task.yield() }
        late.clear()
        delayed.continuation?.resume(); delayed.continuation = nil
        let staleIdentity = await delayedCallback.value
        check(staleIdentity == nil && late.pending == nil, "cancelled callback never grants authority")
        check(delayed.discarded == 1, "cancelled exchange session discarded")
        late.begin(email: valid, now: clock)
        delayed.pauseSend = true
        let delayedResend = Task { await late.resend(using: delayed, now: clock) }
        while delayed.continuation == nil { await Task.yield() }
        late.clear()
        delayed.continuation?.resume(); delayed.continuation = nil
        await delayedResend.value
        check(late.message == nil && late.pending == nil, "cancelled resend cannot revive signup")
        check(PasswordRecovery.code(from: callback) == nil, "signup callback never recovery authority")
        check(!EmailVerification.isCallback(PasswordRecovery.redirectURL), "password reset callback stays isolated")
        print("Passed \(count) email verification checks")
    }
}
