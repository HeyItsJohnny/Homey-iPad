import Foundation
import Combine

@MainActor
protocol TripCalendarEventService {
    func matchingEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID?
    func createEvent(for draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async throws -> UUID
}

/// Session guards and conservative recovery, not server-enforced idempotency.
@MainActor
final class TripCalendarSubmission: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var isComplete = false
    @Published private(set) var needsReconciliation = false
    @Published private(set) var errorMessage: String?
    private let service: any TripCalendarEventService
    private let defaults: UserDefaults
    private var activeKey: String?

    init(service: any TripCalendarEventService, defaults: UserDefaults = .standard) {
        self.service = service; self.defaults = defaults
    }

    func submit(_ draft: TripCalendarPreparation, userID: UUID, isCurrentScope: () -> Bool) async -> Bool {
        guard !isSaving, isCurrentScope(), !Task.isCancelled else { return false }
        let key = "homey.tripCalendarSubmission.\(userID).\(draft.homeID).\(draft.tripID)"
        if activeKey != key {
            activeKey = key; isComplete = false; needsReconciliation = false
        }
        if isComplete { return true }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            if let data = defaults.data(forKey: key) {
                let receipt = try JSONDecoder().decode(Receipt.self, from: data)
                guard receipt.draft.homeID == draft.homeID, receipt.draft.tripID == draft.tripID else {
                    throw PlanningStoreError.scopeMismatch
                }
                if receipt.eventID != nil {
                    guard isCurrentScope() else { return false }
                    isComplete = true; return true
                }
                // An interrupted create may already have committed. Only query; never resend it.
                return await reconcile(receipt.draft, userID: userID, key: key, isCurrentScope: isCurrentScope)
            }
            if let eventID = try await service.matchingEvent(for: draft, userID: userID, isCurrentScope: isCurrentScope) {
                try record(draft, eventID: eventID, key: key)
                guard isCurrentScope() else { return false }
                isComplete = true; return true
            }
            guard isCurrentScope(), !Task.isCancelled else { return false }
            // Retain the exact payload before sending a potentially ambiguous write.
            try record(draft, eventID: nil, key: key)
            do {
                let eventID = try await service.createEvent(for: draft, userID: userID, isCurrentScope: isCurrentScope)
                try record(draft, eventID: eventID, key: key)
                guard isCurrentScope() else { return false }
                isComplete = true; needsReconciliation = false
                return true
            } catch {
                guard isCurrentScope() else { return false }
                return await reconcile(draft, userID: userID, key: key, isCurrentScope: isCurrentScope)
            }
        } catch {
            guard isCurrentScope() else { return false }
            errorMessage = "Calendar could not be checked. Restore your connection and try again."
            return false
        }
    }

    private func reconcile(_ draft: TripCalendarPreparation, userID: UUID, key: String, isCurrentScope: () -> Bool) async -> Bool {
        needsReconciliation = true
        do {
            if let eventID = try await service.matchingEvent(for: draft, userID: userID, isCurrentScope: isCurrentScope) {
                try record(draft, eventID: eventID, key: key)
                guard isCurrentScope() else { return false }
                isComplete = true; needsReconciliation = false; errorMessage = nil
                return true
            }
            guard isCurrentScope() else { return false }
            errorMessage = "The Calendar request may have succeeded, but no matching event is visible yet. Check Calendar again before adding another event manually."
        } catch {
            guard isCurrentScope() else { return false }
            errorMessage = "The Calendar request may have succeeded. Calendar could not be checked; restore your connection and check again."
        }
        return false
    }

    private func record(_ draft: TripCalendarPreparation, eventID: UUID?, key: String) throws {
        defaults.set(try JSONEncoder().encode(Receipt(draft: draft, eventID: eventID)), forKey: key)
    }
    private struct Receipt: Codable {
        let draft: TripCalendarPreparation
        let eventID: UUID?
    }
}
