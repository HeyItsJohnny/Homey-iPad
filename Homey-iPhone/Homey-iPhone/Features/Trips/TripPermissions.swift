import Foundation

/// Shared edits follow the active Home's membership, regardless of who organizes the Trip.
enum TripPermissions {
    static func canEdit(homeID: UUID, role: HomeMemberRole?, households: [TripHousehold]) -> Bool {
        guard role == .owner || role == .admin else { return false }
        return households.contains { $0.homeID == homeID && $0.isCurrentUserHome && $0.isAccepted }
    }

    static func canComplete(status: TripStatus, homeID: UUID, role: HomeMemberRole?, households: [TripHousehold]) -> Bool {
        (status == .planned || status == .active) && canEdit(homeID: homeID, role: role, households: households)
    }

    static func canDelete(homeID: UUID, organizerHomeID: UUID, role: HomeMemberRole?, households: [TripHousehold]) -> Bool {
        canManageHouseholds(homeID: homeID, organizerHomeID: organizerHomeID, role: role, households: households)
    }

    static func canManageHouseholds(homeID: UUID, organizerHomeID: UUID, role: HomeMemberRole?, households: [TripHousehold]) -> Bool {
        homeID == organizerHomeID && canEdit(homeID: homeID, role: role, households: households)
    }
}
