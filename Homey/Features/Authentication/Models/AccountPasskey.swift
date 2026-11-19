import Foundation

struct AccountPasskey: Identifiable {
    let id: String
    let name: String
    let createdAt: Date
}

enum AccountPasskeyAction: Equatable {
    case setup, remove, refresh

    static func resolve(hasRegisteredPasskey: Bool, hasLoaded: Bool) -> Self {
        if hasRegisteredPasskey { return .remove }
        return hasLoaded ? .setup : .refresh
    }
}

/// Deletes only credentials covered by the user's confirmation. Every write uses
/// the existing authenticated API; only the final server list proves removal.
@MainActor
final class AccountPasskeyRemoval {
    private(set) var isRemoving = false

    func remove(confirmedIDs: Set<String>, isCurrent: () -> Bool,
                list: () async throws -> [AccountPasskey],
                delete: (String) async throws -> Void) async throws -> [AccountPasskey]? {
        guard !isRemoving, !confirmedIDs.isEmpty, isCurrent() else { return nil }
        isRemoving = true
        defer { isRemoving = false }
        let current = try await list()
        guard isCurrent(), !Task.isCancelled else { return nil }
        for credential in current where confirmedIDs.contains(credential.id) {
            guard isCurrent(), !Task.isCancelled else { return nil }
            try await delete(credential.id)
            guard isCurrent(), !Task.isCancelled else { return nil }
        }
        let remaining = try await list()
        guard isCurrent(), !Task.isCancelled else { return nil }
        return remaining
    }
}
