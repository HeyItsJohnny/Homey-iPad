import Foundation

/// User-facing classifications; raw database messages are never logged or displayed.
enum QuickMealError: LocalizedError, Equatable {
    case permissionDenied
    case calendarReconciliation
    case unavailable
    case requestFailed

    static func serverError(code: String?, message: String) -> QuickMealError {
        let text = message.lowercased()
        if code == "42501" || code == "PGRST301" || text.contains("permission denied") {
            return .permissionDenied
        }
        if code == "23503" || (text.contains("calendar") &&
            ["missing", "not found", "deleted", "does not exist", "no longer"].contains(where: text.contains)) {
            return .calendarReconciliation
        }
        if code == "PGRST202" { return .unavailable }
        return .requestFailed
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "You no longer have permission to change this Home's meal plan. Refresh your Home and try again."
        case .calendarReconciliation:
            return "This Quick Add's Calendar event is missing or was deleted. Refresh the planner. If the entry remains, ask your Home owner to reconcile it before retrying."
        case .unavailable:
            return "The Quick Add service is unavailable. Please try again later."
        case .requestFailed:
            return "We couldn't complete the Quick Add request. Check your connection and retry. Your entered name has been kept."
        }
    }
}
