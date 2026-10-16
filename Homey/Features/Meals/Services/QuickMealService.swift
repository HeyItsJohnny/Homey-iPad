import Foundation
import Supabase
import PostgREST

struct QuickMealService {
    private let client = SupabaseManager.shared.client

    func fetch(homeID: UUID, start: String, end: String) async throws -> [QuickPlannedMeal] {
        do {
            let entries: [QuickPlannedMeal] = try await client.rpc("get_quick_meal_plan_entries",
                params: QuickMealRangeParameters(homeID: homeID, start: start, end: end)).execute().value
            return entries.filter { $0.homeID == homeID && $0.plannedDate >= start && $0.plannedDate < end }
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw MealLoadFailure.capture(operation: "get_quick_meal_plan_entries", error: error,
                postgrestCode: (error as? PostgrestError)?.code)
        }
    }

    func save(_ parameters: SaveQuickMealParameters) async throws {
        do {
            try await client.rpc("save_quick_meal_plan_entry", params: parameters).execute()
        } catch { throw Self.userFacingError(error) }
    }

    func remove(_ entry: QuickPlannedMeal) async throws {
        do {
            try await client.rpc("delete_quick_meal_plan_entry",
                params: DeleteQuickMealParameters(homeID: entry.homeID, entryID: entry.id)).execute()
        } catch { throw Self.userFacingError(error) }
    }

    /// An edit of stale UI must not turn an independently deleted event into a new plan.
    /// The server still owns transactional integrity if deletion races this check.
    @MainActor
    func validateExisting(_ entry: QuickPlannedMeal, calendar: Calendar) async throws {
        let parts = entry.plannedDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw QuickMealError.calendarReconciliation
        }
        do {
            let entries = try await fetch(homeID: entry.homeID, start: entry.plannedDate,
                end: QuickPlannedMeal.dayKey(end, calendar: calendar))
            guard entries.contains(where: { $0.id == entry.id && $0.calendarEventID == entry.calendarEventID }) else {
                throw QuickMealError.calendarReconciliation
            }
            let events = try await CalendarService(calendar: calendar).fetchEvents(
                homeId: entry.homeID, rangeStart: start, rangeEnd: end)
            guard events.contains(where: { $0.eventId == entry.calendarEventID && $0.homeId == entry.homeID }) else {
                throw QuickMealError.calendarReconciliation
            }
        } catch let error as QuickMealError { throw error }
        catch { throw Self.userFacingError(error) }
    }

    private static func userFacingError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let server = error as? PostgrestError {
            return QuickMealError.serverError(code: server.code, message: server.message)
        }
        return QuickMealError.requestFailed
    }
}
