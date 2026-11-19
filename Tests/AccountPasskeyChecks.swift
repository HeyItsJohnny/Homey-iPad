import Foundation

@main
struct AccountPasskeyChecks {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1
        }
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: false, hasLoaded: true) == .setup, "confirmed empty account offers setup")
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: true, hasLoaded: true) == .remove, "registered account offers removal")
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: false, hasLoaded: false) == .refresh, "unknown status never claims setup available")
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: true, hasLoaded: false) == .remove, "failed refresh preserves configured presentation")
        func credential(_ id: String) -> AccountPasskey { .init(id: id, name: "Private name", createdAt: .distantPast) }
        let removal = AccountPasskeyRemoval()
        var server = [credential("one"), credential("two")]
        var deletes: [String] = [], reads = 0
        var current = true
        func list() async throws -> [AccountPasskey] { reads += 1; return server }
        func delete(_ id: String) async throws { deletes.append(id); server.removeAll { $0.id == id } }
        let all = try await removal.remove(confirmedIDs: ["one", "two"], isCurrent: { current }, list: list, delete: delete)
        check(all?.isEmpty == true && deletes == ["one", "two"] && reads == 2, "all confirmed credentials removed and rechecked")
        check(!removal.isRemoving, "loading clears after success")
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: !all!.isEmpty, hasLoaded: true) == .setup, "confirmed removal offers setup")
        server = [credential("one"), credential("new")]; deletes = []; reads = 0
        let remaining = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: list, delete: delete)
        check(deletes == ["one"] && remaining?.map(\.id) == ["new"], "credential added after confirmation is never deleted or hidden")
        check(AccountPasskeyAction.resolve(hasRegisteredPasskey: !remaining!.isEmpty, hasLoaded: true) == .remove, "remaining credential keeps removal button")
        server = []; deletes = []; reads = 0
        let absent = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: list, delete: delete)
        check(absent?.isEmpty == true && deletes.isEmpty && reads == 2, "already removed credential safely reconciled")
        let unconfirmed = try await removal.remove(confirmedIDs: [], isCurrent: { current }, list: list, delete: delete)
        check(unconfirmed == nil && reads == 2, "no confirmation causes no writes or reads")
        current = false
        let wrongAccount = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: list, delete: delete)
        check(wrongAccount == nil && reads == 2, "wrong account does not touch backend")
        current = true
        server = [credential("one"), credential("two")]; deletes = []
        do {
            _ = try await removal.remove(confirmedIDs: ["one", "two"], isCurrent: { current }, list: list, delete: { id in
                if id == "two" { throw URLError(.notConnectedToInternet) }
                try await delete(id)
            })
            preconditionFailure("partial failure cannot report success")
        } catch { count += 1 }
        check(deletes == ["one"] && server.map(\.id) == ["two"] && !removal.isRemoving, "partial failure does not claim all removed")
        let retried = try await removal.remove(confirmedIDs: ["one", "two"], isCurrent: { current }, list: list, delete: delete)
        check(retried?.isEmpty == true && deletes == ["one", "two"], "retry only deletes credentials still registered")
        server = [credential("one")]; deletes = []; reads = 0
        do {
            _ = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: {
                reads += 1
                if reads == 2 { throw URLError(.timedOut) }
                return server
            }, delete: delete)
            preconditionFailure("final refresh failure cannot report success")
        } catch { count += 1 }
        check(!removal.isRemoving, "refresh failure clears loading")
        reads = 0; deletes = []
        do {
            _ = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: { throw URLError(.timedOut) }, delete: delete)
            preconditionFailure("preflight failure cannot report success")
        } catch { count += 1 }
        check(deletes.isEmpty, "preflight error causes no deletion")
        server = [credential("one")]
        let staleRead = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: {
            current = false; return server
        }, delete: delete)
        check(staleRead == nil && deletes.isEmpty, "account switch during list blocks deletion")
        current = true
        server = [credential("one"), credential("two")]
        let staleWrite = try await removal.remove(confirmedIDs: ["one", "two"], isCurrent: { current }, list: list, delete: { id in
            deletes.append(id); current = false
        })
        check(staleWrite == nil && deletes == ["one"], "account switch stops remaining deletes and UI publication")
        current = true; deletes = []
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: {
            if continuation == nil { await withCheckedContinuation { continuation = $0 } }
            return server
        }, delete: delete) }
        while continuation == nil { await Task.yield() }
        check(removal.isRemoving, "loading during removal")
        let duplicate = try await removal.remove(confirmedIDs: ["one"], isCurrent: { current }, list: list, delete: delete)
        check(duplicate == nil && deletes.isEmpty, "duplicate removal blocked")
        continuation!.resume()
        _ = try await task.value
        check(deletes == ["one"] && !removal.isRemoving, "only one removal completes")
        let relaunchedAction = AccountPasskeyAction.resolve(hasRegisteredPasskey: false, hasLoaded: false)
        check(relaunchedAction == .refresh, "relaunch rechecks server rather than trusting enrollment preference")
        print("Passed \(count) account passkey state and mocked removal checks")
    }
}
