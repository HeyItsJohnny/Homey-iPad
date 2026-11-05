import Foundation

@MainActor
final class FakeRecoveryAuth: PasswordRecoveryAuth {
    var sends = 0
    var sentEmails: [String] = []
    var exchanges = 0
    var validations = 0
    var updates = 0
    var clears = 0
    var failure: Error?
    var updateFailure: Error?
    var identity = RecoveryIdentity(userID: UUID(), expiresAt: Date().addingTimeInterval(600))
    var sendGate: CheckedContinuation<Void, Never>?
    var exchangeGate: CheckedContinuation<Void, Never>?
    var updateGate: CheckedContinuation<Void, Never>?
    var pauseSend = false
    var pauseExchange = false
    var pauseUpdate = false
    func send(email: String) async throws {
        sends += 1
        sentEmails.append(email)
        if pauseSend { await withCheckedContinuation { sendGate = $0 } }
        if let failure { throw failure }
    }
    func exchange(code: String) async throws -> RecoveryIdentity {
        exchanges += 1
        if pauseExchange { await withCheckedContinuation { exchangeGate = $0 } }
        if let failure { throw failure }
        return identity
    }
    func validate(identity: RecoveryIdentity) async throws {
        validations += 1
        precondition(identity == self.identity)
        if let failure { throw failure }
    }
    func update(password: String) async throws {
        updates += 1
        if pauseUpdate { await withCheckedContinuation { updateGate = $0 } }
        if let updateFailure { throw updateFailure }
        if let failure { throw failure }
    }
    func clear() async { clears += 1 }
}

@main
struct PasswordRecoveryChecks {
    @MainActor static func main() async {
        let callback = URL(string: "homeyipad://auth/reset-password?code=valid-code_123")!
        precondition(PasswordRecovery.code(from: callback) == "valid-code_123")
        for text in [
            "homey://auth/reset-password?code=x", "https://auth/reset-password?code=x",
            "homeyipad://other/reset-password?code=x", "homeyipad://auth/other?code=x",
            "homeyipad://user@auth/reset-password?code=x", "homeyipad://auth:123/reset-password?code=x",
            "homeyipad://auth/reset-password", "homeyipad://auth/reset-password?code=",
            "homeyipad://auth/reset-password?code=x&code=y", "homeyipad://auth/reset-password?code=x&type=signup",
            "homeyipad://auth/reset-password#access_token=secret&type=recovery",
            "homeyipad://auth/reset-password?code=x#access_token=secret", "homeyipad://auth/reset-password?error=access_denied",
            "homeyipad://auth/reset-password?code=%20", "homeyipad://auth/reset-password/extra?code=x"
        ] { precondition(PasswordRecovery.code(from: URL(string: text)!) == nil, text) }
        precondition(PasswordRecovery.validEmail("test@example.com"))
        for email in ["", "name", "a@b", "a@b.c d", "a@@b.com"] {
            precondition(!PasswordRecovery.validEmail(email))
        }
        precondition(PasswordRecovery.passwordError("", confirmation: "") != nil)
        precondition(PasswordRecovery.passwordError("abc", confirmation: "") == "Confirm your new password.")
        precondition(PasswordRecovery.passwordError("one", confirmation: "two") != nil)
        // Client defers the actual password policy to the configured server.
        precondition(PasswordRecovery.passwordError("abc", confirmation: "abc") == nil)

        let auth = FakeRecoveryAuth()
        var now = Date()
        let service = PasswordRecoveryService(auth: auth, now: { now })
        let premature = await service.update(password: "abc", confirmation: "abc")
        precondition(!premature && auth.updates == 0)
        let badEmail = await service.send(email: "invalid")
        precondition(!badEmail && auth.sends == 0)
        auth.pauseSend = true
        let sendTask = Task { await service.send(email: " test@example.com ") }
        while auth.sendGate == nil { await Task.yield() }
        let duplicateSend = await service.send(email: "test@example.com")
        precondition(!duplicateSend && auth.sends == 1)
        auth.sendGate?.resume()
        let sent = await sendTask.value
        precondition(sent && service.state == .pendingVerification && service.state.isPresented)
        precondition(service.requestedEmail == "test@example.com" && auth.sentEmails == ["test@example.com"])
        let pendingUpdate = await service.update(password: "abc", confirmation: "abc")
        precondition(!pendingUpdate && auth.updates == 0 && auth.validations == 0)
        let cooldownSend = await service.resend()
        precondition(!cooldownSend && auth.sends == 1 && service.requestError != nil)
        now = now.addingTimeInterval(61)
        auth.pauseSend = false
        auth.failure = URLError(.notConnectedToInternet)
        let failedResend = await service.resend()
        precondition(!failedResend && service.state == .pendingVerification && !service.isSending)
        precondition(service.requestedEmail == "test@example.com" && service.requestError != nil)
        auth.failure = nil
        auth.pauseSend = true
        auth.sendGate = nil
        let resendTask = Task { await service.resend() }
        while auth.sendGate == nil { await Task.yield() }
        let duplicateResend = await service.resend()
        await service.dismiss()
        precondition(!duplicateResend && service.state == .pendingVerification)
        auth.sendGate?.resume()
        let resent = await resendTask.value
        precondition(resent && service.requestError == nil && auth.sentEmails.count == 3)
        precondition(auth.sentEmails.allSatisfy { $0 == "test@example.com" })

        await service.handle(URL(string: "homey://auth/reset-password?code=x")!)
        precondition(service.state == .pendingVerification && auth.exchanges == 0)
        auth.pauseExchange = true
        let exchangeTask = Task { await service.handle(callback) }
        while auth.exchangeGate == nil { await Task.yield() }
        precondition(service.state == .exchanging)
        await service.handle(callback)
        await service.dismiss() // Cannot cancel while an exchange is in flight.
        precondition(auth.exchanges == 1 && service.state == .exchanging)
        auth.exchangeGate?.resume()
        await exchangeTask.value
        precondition(service.state == .ready && auth.validations == 1)
        let mismatch = await service.update(password: "abc", confirmation: "def")
        precondition(!mismatch && auth.updates == 0)
        auth.updateFailure = RecoveryAuthFailure.policy("Configured policy rejected this password.")
        let weak = await service.update(password: "abc", confirmation: "abc")
        precondition(!weak && service.state == .ready && service.errorMessage != nil)
        auth.updateFailure = nil
        auth.pauseUpdate = true
        let updateTask = Task { await service.update(password: "abc", confirmation: "abc") }
        while auth.updateGate == nil { await Task.yield() }
        let concurrentUpdate = await service.update(password: "abc", confirmation: "abc")
        await service.dismiss()
        precondition(!concurrentUpdate && service.state == .updating && auth.updates == 2)
        auth.updateGate?.resume()
        let success = await updateTask.value
        precondition(success && service.state == .success && auth.updates == 2 && auth.clears == 1)
        let duplicateUpdate = await service.update(password: "abc", confirmation: "abc")
        precondition(!duplicateUpdate && auth.updates == 2)
        await service.dismiss()
        precondition(service.state == .idle && service.requestedEmail == nil && service.requestError == nil)
        let dismissedCooldown = await service.send(email: "other@example.com")
        precondition(!dismissedCooldown && auth.sends == 3)

        // An unknown account is indistinguishable from any accepted Auth request.
        let unknownAuth = FakeRecoveryAuth()
        let unknown = PasswordRecoveryService(auth: unknownAuth)
        let unknownSent = await unknown.send(email: "unknown@example.com")
        precondition(unknownSent && unknown.state == .pendingVerification && unknown.requestError == nil)
        await unknown.dismiss()
        precondition(unknown.state == .idle && unknown.requestedEmail == nil && unknownAuth.clears == 1)

        let pendingInvalidAuth = FakeRecoveryAuth()
        let pendingInvalid = PasswordRecoveryService(auth: pendingInvalidAuth)
        _ = await pendingInvalid.send(email: "test@example.com")
        pendingInvalidAuth.failure = RecoveryAuthFailure.invalidSession
        await pendingInvalid.handle(callback)
        precondition(pendingInvalid.state == .invalidLink && pendingInvalidAuth.clears == 1)

        // Time passing after verification must prevent any password mutation.
        let expiringAuth = FakeRecoveryAuth()
        var expiryTime = Date()
        let expiring = PasswordRecoveryService(auth: expiringAuth, now: { expiryTime })
        await expiring.handle(callback)
        expiryTime = expiryTime.addingTimeInterval(601)
        let expiredUpdate = await expiring.update(password: "abc", confirmation: "abc")
        precondition(!expiredUpdate && expiring.state == .invalidLink && expiringAuth.updates == 0)

        for failure in [RecoveryAuthFailure.invalidSession] {
            let expiredAuth = FakeRecoveryAuth()
            let expired = PasswordRecoveryService(auth: expiredAuth)
            expiredAuth.failure = failure
            await expired.handle(callback)
            precondition(expired.state == .invalidLink && expiredAuth.updates == 0 && expiredAuth.clears == 1)
        }
        let expiredAuth = FakeRecoveryAuth()
        expiredAuth.identity = RecoveryIdentity(userID: UUID(), expiresAt: .distantPast)
        let expired = PasswordRecoveryService(auth: expiredAuth)
        await expired.handle(callback)
        precondition(expired.state == .invalidLink && expiredAuth.validations == 0)
        let revokedAuth = FakeRecoveryAuth()
        let revoked = PasswordRecoveryService(auth: revokedAuth)
        await revoked.handle(callback)
        revokedAuth.failure = RecoveryAuthFailure.invalidSession
        let revokedUpdate = await revoked.update(password: "abc", confirmation: "abc")
        precondition(!revokedUpdate && revoked.state == .invalidLink && revokedAuth.updates == 0)
        let cancelledAuth = FakeRecoveryAuth()
        let cancelled = PasswordRecoveryService(auth: cancelledAuth)
        await cancelled.handle(callback)
        await cancelled.dismiss()
        let cancelledUpdate = await cancelled.update(password: "abc", confirmation: "abc")
        precondition(!cancelledUpdate && cancelledAuth.updates == 0 && cancelledAuth.clears == 1)
        let retryAuth = FakeRecoveryAuth()
        let retry = PasswordRecoveryService(auth: retryAuth)
        await retry.handle(callback)
        retryAuth.updateFailure = URLError(.notConnectedToInternet)
        let offline = await retry.update(password: "abc", confirmation: "abc")
        precondition(!offline && retry.state == .ready && retry.errorMessage != nil)
        retryAuth.updateFailure = nil
        let retried = await retry.update(password: "abc", confirmation: "abc")
        precondition(retried && retry.state == .success)
        let requestFailureAuth = FakeRecoveryAuth()
        requestFailureAuth.failure = URLError(.notConnectedToInternet)
        let requestFailure = PasswordRecoveryService(auth: requestFailureAuth)
        let failedSend = await requestFailure.send(email: "test@example.com")
        precondition(!failedSend && !requestFailure.isSending && requestFailure.requestError != nil)
        let malformedAuth = FakeRecoveryAuth()
        let malformed = PasswordRecoveryService(auth: malformedAuth)
        await malformed.handle(URL(string: "homeyipad://auth/reset-password?error=expired")!)
        precondition(malformed.state == .invalidLink && malformedAuth.exchanges == 0)
        print("Password recovery checks passed: pending navigation, trimmed/neutral requests, resend cooldown/retry, validation, PKCE routing, duplicate sends/callbacks/updates, policy failures, expiration/revocation, cleanup and single-use update state.")
    }
}
