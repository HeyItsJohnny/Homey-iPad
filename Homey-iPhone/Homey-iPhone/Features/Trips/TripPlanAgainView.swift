import SwiftUI

struct TripPlanAgainDraft {
    var startDate: Date
    var endDate: Date
    var includesTimes: Bool
    var startTime: Date
    var endTime: Date
    let singleDay: Bool

    @MainActor init(trip: Trip) {
        singleDay = trip.durationType == .fewHours || trip.durationType == .dayTrip
        startDate = TripDateFormatters.localNoon(Date())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days: Int
        if let start = trip.startDate, let end = trip.endDate {
            days = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        } else {
            days = trip.durationType == .weekend ? 2 : 0
        }
        endDate = Calendar.current.date(byAdding: .day, value: singleDay ? 0 : days, to: startDate) ?? startDate
        includesTimes = trip.durationType == .fewHours || trip.startTime != nil || trip.endTime != nil
        startTime = TripTimeFormatters.date(from: trip.startTime) ?? TripTimeFormatters.defaultStartDate
        endTime = TripTimeFormatters.date(from: trip.endTime) ?? TripTimeFormatters.defaultEndDate
    }

    mutating func moveStart(to date: Date) {
        let days = max(0, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0)
        startDate = TripDateFormatters.localNoon(date)
        endDate = Calendar.current.date(byAdding: .day, value: singleDay ? 0 : days, to: startDate) ?? startDate
    }
}

struct TripPlanAgainView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let homeID: UUID
    let onPlanned: (UUID) async -> Void

    @State private var draft: TripPlanAgainDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    @MainActor init(trip: Trip, homeID: UUID, onPlanned: @escaping (UUID) async -> Void) {
        self.trip = trip
        self.homeID = homeID
        self.onPlanned = onPlanned
        _draft = State(initialValue: TripPlanAgainDraft(trip: trip))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(trip.title)
                            .font(HomeyTypography.headline)
                        VStack(spacing: 16) {
                            DatePicker(draft.singleDay ? "Date" : "New Start Date", selection: Binding(
                                get: { draft.startDate },
                                set: { draft.moveStart(to: $0) }
                            ), displayedComponents: .date)
                            if !draft.singleDay {
                                DatePicker("New End Date", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                            }
                            if trip.durationType != .fewHours {
                                Toggle("Add Times", isOn: $draft.includesTimes)
                            }
                            if draft.includesTimes {
                                DatePicker("Start Time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
                                DatePicker("End Time", selection: $draft.endTime, displayedComponents: .hourAndMinute)
                            }
                        }
                        .homeyCard()
                        .disabled(isSaving)
                        if let errorMessage { HomeyErrorView(message: errorMessage) }
                        Button(action: plan) {
                            if isSaving { ProgressView() } else { Text("Plan Trip") }
                        }
                        .buttonStyle(HomeyButtonStyle())
                        .disabled(isSaving || session.activeHome?.id != homeID)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Plan Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: session.activeHome?.id) { _, id in
            if id != homeID {
                saveTask?.cancel()
                dismiss()
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    private func plan() {
        guard !isSaving else { return }
        guard session.activeHome?.id == homeID else { dismiss(); return }
        isSaving = true
        errorMessage = nil
        saveTask = Task { @MainActor in
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                guard session.activeHome?.id == homeID else { return }
                let id = try await TripsService().planAgain(tripID: trip.id, schedule: draft)
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                // Success is final: refresh failures must never offer a second clone request.
                await onPlanned(id)
                dismiss()
            } catch is CancellationError {
                // Home switching and navigation cancellation are silent.
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
