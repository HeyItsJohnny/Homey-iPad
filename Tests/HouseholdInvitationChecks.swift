import Foundation

@main
struct HouseholdInvitationChecks {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label); count += 1
        }
        let suite = "homey.invitation-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let flow = HouseholdInvitationFlow(defaults: defaults)
        let user = UUID(), home = UUID()
        var requests: [HouseholdInvitationRequest] = []
        var refreshes = 0
        func send(_ sender: HomeMemberRole? = .owner, _ role: HomeMemberRole = .member,
                  _ email: String = " MEMBER@example.com ", _ verified: Bool = true,
                  _ failure: Error? = nil) async throws -> Bool {
            try await flow.send(userID: user, homeID: home, email: email, role: role,
                senderRole: sender, verified: verified, invoke: {
                    requests.append($0)
                    if let failure { throw failure }
                }, refresh: { refreshes += 1 })
        }
        for sender in [HomeMemberRole.owner, .admin] {
            let result = try await send(sender)
            check(result, "owner/admin send")
        }
        check(requests.count == 2 && refreshes == 2, "success refreshes list")
        check(requests[0].recipientEmail == "member@example.com", "email normalized")
        check(requests[0].requestID != requests[1].requestID, "new confirmed request gets new id")
        for invalid in [(HomeMemberRole.member, HomeMemberRole.member, "x@example.com", true),
                        (.owner, .owner, "x@example.com", true), (.owner, .member, "bad", true),
                        (.owner, .member, "x@example.com", false)] {
            do { _ = try await send(invalid.0, invalid.1, invalid.2, invalid.3); preconditionFailure("invalid request allowed") }
            catch { count += 1 }
        }
        check(requests.count == 2, "invalid requests never reach backend")
        for failure in [HouseholdInvitationFailure.uncertain, .backend("already_pending_invitation"), .backend("rate_limited")] {
            do { _ = try await send(.owner, .member, "retry@example.com", true, failure) }
            catch { check((error as? HouseholdInvitationFailure) == failure, "backend error retained") }
        }
        do { _ = try await send(.owner, .member, "retry@example.com", true, URLError(.timedOut)) } catch { count += 1 }
        let retryID = requests.last!.requestID
        check(requests.suffix(4).allSatisfy { $0.requestID == retryID }, "all failures preserve id")
        let restored = HouseholdInvitationFlow(defaults: defaults)
        _ = try await restored.send(userID: user, homeID: home, email: "retry@example.com", role: .member,
            senderRole: .admin, verified: true, invoke: { check($0.requestID == retryID, "cold launch retry id") }, refresh: {})
        check(refreshes == 2, "failures do not refresh as success")
        var continuation: CheckedContinuation<Void, Never>?
        let sending = Task { try await flow.send(userID: user, homeID: home, email: "busy@example.com", role: .admin,
            senderRole: .owner, verified: true, invoke: { _ in await withCheckedContinuation { continuation = $0 } }, refresh: {}) }
        while continuation == nil { await Task.yield() }
        let duplicate = try await send()
        check(!duplicate && flow.isSending, "duplicate taps blocked")
        continuation!.resume()
        _ = try await sending.value
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(requests[0])) as! [String: Any]
        check(Set(payload.keys) == ["home_id", "recipient_email", "role", "request_id"], "exact shared function payload")
        for body in ["{\"success\":true}", "{\"status\":\"sent\"}", "{\"delivery_status\":\"accepted\"}"] {
            try HouseholdInvitationFailure.validateResponse(Data(body.utf8)); count += 1
        }
        for body in ["{}", "not-json", "{\"status\":\"pending\"}", "{\"success\":true,\"status\":\"delivery_uncertain\"}", "{\"error\":\"delivery_uncertain\"}", "{\"success\":false,\"status\":\"sent\"}"] {
            do { try HouseholdInvitationFailure.validateResponse(Data(body.utf8)); preconditionFailure("unknown delivery accepted") }
            catch { count += 1 }
        }
        for code in ["invalid_request", "invalid_home_id", "invalid_request_id", "invalid_recipient", "invalid_role",
                     "unauthorized", "unverified_email", "insufficient_home_permissions", "already_pending_invitation",
                     "request_conflict", "invitation_unavailable", "invitation_terminal", "rate_limited", "provider_failure", "service_unavailable"] {
            for body in ["{\"error\":\"\(code)\"}", "{\"error\":{\"code\":\"\(code)\",\"message\":\"secret\"}}"] {
                do { try HouseholdInvitationFailure.validateResponse(Data(body.utf8)); preconditionFailure("error accepted") }
                catch { check((error as? HouseholdInvitationFailure) == .backend(code), "flat/nested error code") }
            }
            check(!HouseholdInvitationFailure.backend(code).message.contains("secret"), "friendly error")
        }
        let valid = "ABCD-1234-EF56-7890-ABCD-1234-EF56-7890"
        check(HouseholdInvitationFlow.validCode(valid), "complete code format")
        for invalid in ["", "ABCD", valid + "-ABCD", valid.replacingOccurrences(of: "ABCD", with: "AB!D")] {
            check(!HouseholdInvitationFlow.validCode(invalid), "malformed code")
        }
        let join = HouseholdCodeRedemption()
        var redemptions = 0, navigations: [UUID] = []
        var current = true
        func redeem(_ code: String = valid, _ verified: Bool = true, _ error: Error? = nil) async throws -> Bool {
            try await join.redeem(code, userID: user, verified: verified, isCurrent: { current }, invoke: {
                check($0 == valid, "uppercase trimmed code passed to RPC")
                redemptions += 1
                if let error { throw error }
                return home
            })
        }
        do { _ = try await redeem(valid, false); preconditionFailure("unverified join") } catch { count += 1 }
        do { _ = try await redeem(""); preconditionFailure("empty join") } catch { count += 1 }
        check(redemptions == 0, "invalid/unverified never redeem")
        struct MockRPCError: Error, CustomStringConvertible { let description: String }
        for message in ["invalid code", "expired invitation", "already accepted", "cancelled", "declined", "wrong email", "unverified email"] {
            let failure = MockRPCError(description: message)
            do { _ = try await redeem(valid, true, failure); preconditionFailure("RPC rejection ignored") }
            catch { check(!HouseholdInvitationFailure.joinMessage(error).isEmpty, "friendly code error") }
        }
        check(HouseholdInvitationFailure.joinMessage(URLError(.notConnectedToInternet)).contains("connection"), "network join error")
        let result = try await redeem(" \(valid.lowercased())\n")
        check(result, "valid redemption")
        let before = redemptions
        _ = try await redeem()
        check(redemptions == before, "no duplicate redemption after success")
        do {
            _ = try await join.finish(userID: user, isCurrent: { current }, refresh: { throw URLError(.timedOut) }, navigate: { navigations.append($0) })
        } catch { count += 1 }
        do {
            _ = try await join.finish(userID: user, isCurrent: { current }, refresh: { [] }, navigate: { navigations.append($0) })
        } catch { count += 1 }
        check(navigations.isEmpty, "no navigation without refreshed membership")
        let finished = try await join.finish(userID: user, isCurrent: { current }, refresh: { [home] }, navigate: { navigations.append($0) })
        check(finished && navigations == [home] && redemptions == before, "refresh retry navigates joined Home without redeeming")
        var joinContinuation: CheckedContinuation<Void, Never>?
        let joining = Task { try await join.redeem(valid, userID: user, verified: true, isCurrent: { current }, invoke: { _ in
            await withCheckedContinuation { joinContinuation = $0 }; return home
        }) }
        while joinContinuation == nil { await Task.yield() }
        let secondJoin = try await redeem()
        check(!secondJoin, "concurrent redemption blocked")
        current = false
        joinContinuation!.resume()
        let stale = try await joining.value
        check(!stale, "session change drops redemption result")
        print("Passed \(count) mocked household invitation and code redemption checks")
    }
}
