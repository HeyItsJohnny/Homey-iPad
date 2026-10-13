import SwiftUI

struct TripCalendarCreateView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let home: HomeSummary
    @State private var categories: [PhoneCalendarCategory] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let service = PhoneCalendarService()

    private var timezone: TimeZone { home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timezone
        value.firstWeekday = home.weekStartsOn == 2 ? 2 : 1
        return value
    }

    var body: some View {
        Group {
            if hasLoaded {
                PhoneCalendarEditor(
                    mode: .create(Date()), categories: categories, calendar: calendar, timezone: timezone,
                    isSaving: isSaving, externalError: errorMessage,
                    initialDraft: TripCalendarDraft.make(trip: trip, calendar: calendar),
                    saveTitle: "Add", allowsRecurrence: false,
                    scheduleHint: TripCalendarDraft.needsFreshDates(trip) ? "Choose a new date for this Calendar event." : nil,
                    preservesDurationOnStartChange: true,
                    onSave: add
                )
                .environment(\.calendar, calendar)
                .environment(\.timeZone, timezone)
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if isLoading { ProgressView("Loading Calendar…") }
                        if let errorMessage {
                            HomeyErrorView(message: errorMessage)
                            Button("Try Again") { Task { await loadCategories() } }
                                .disabled(isLoading)
                        }
                    }
                    .padding(24)
                    .navigationTitle("New Event")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                }
            }
        }
        .task { await loadCategories() }
        .onChange(of: session.activeHome?.id) { _, id in
            if id != home.id { dismiss() }
        }
        .onChange(of: session.isSwitchingHome) { _, switching in
            if switching { dismiss() }
        }
    }

    private func loadCategories() async {
        guard session.activeHome?.id == home.id, !session.isSwitchingHome else { dismiss(); return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await service.fetchCategories(homeID: home.id)
            guard !Task.isCancelled, session.activeHome?.id == home.id else { return }
            categories = loaded
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, session.activeHome?.id == home.id else { return }
            errorMessage = "Calendar could not be loaded. Please try again."
        }
    }

    private func add(_ draft: PhoneCalendarDraft) async -> Bool {
        guard !isSaving, !Task.isCancelled, !session.isSwitchingHome,
              session.activeHome?.id == home.id else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try Task.checkCancellation()
            var event = draft
            event.recurrence = PhoneCalendarRecurrence()
            try await service.create(homeID: home.id, draft: event, timezone: timezone, calendar: calendar)
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled, session.activeHome?.id == home.id else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
