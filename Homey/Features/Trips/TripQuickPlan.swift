import SwiftUI
import Supabase

struct TripQuickPlan: View {
    @EnvironmentObject private var homes: HomeService
    @Environment(\.dismiss) private var dismiss
    let idea: SavedTripIdea
    let homeID: UUID
    let onChanged: () async -> Void
    let onPlanned: () -> Void
    @State private var start = Date()
    @State private var end = Date()
    @State private var addToCalendar = true
    @State private var confirmedTripID: UUID?
    @StateObject private var calendarSubmission = TripCalendarSubmission(service: TripCalendarService())
    @State private var includesTimes = false
    @State private var startTime = TripTimeFormatters.defaultStartDate
    @State private var endTime = TripTimeFormatters.defaultEndDate
    @State private var attempt: TripIdeaPlanningAttempt?
    @State private var userID: UUID?
    @State private var ready = false
    @State private var saving = false
    @State private var finished = false
    @State private var error: String?
    private let store = TripIdeaPlanningStore()

    var body: some View {
        TripModalLayout(title: "Plan This Trip", subtitle: idea.title) {
            VStack(alignment: .leading, spacing: 12) {
                TripModalSectionLabel(title: "Date and Time", supportingText: "Choose a day trip or a longer adventure.")
                VStack(alignment: .leading, spacing: 16) {
                    if let attempt {
                        Label("Resume request", systemImage: "arrow.clockwise.circle").font(.headline)
                        Text("\(attempt.startDate) – \(attempt.endDate ?? attempt.startDate)")
                        if let time = attempt.startTime { Text("\(time) – \(attempt.endTime ?? time)") }
                        Text(attempt.addToCalendar == true ? "Add to Calendar: Yes" : "Add to Calendar: No")
                        Text("The original dates and Calendar choice are preserved while this request is unresolved.")
                            .font(.caption).foregroundStyle(HomeyTheme.textSecondary)
                    } else {
                        TripDateField("Start Date", selection: $start)
                        TripDateField("End Date", selection: $end, in: start...)
                        Toggle("Add Times", isOn: $includesTimes)
                        Toggle("Add to Calendar", isOn: $addToCalendar)
                        if includesTimes {
                            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }.datePickerStyle(.compact).tripInsetPanel()
            }.disabled(saving || finished || !ready)
            if let error { TripModalBanner(message: error, isError: true) }
            HStack(spacing: 12) {
                Button(finished ? "Done" : "Close") {
                    if finished { onPlanned() } else { dismiss() }
                }
                    .buttonStyle(HomeySecondaryButtonStyle()).disabled(saving)
                if !finished {
                    Button { plan() } label: {
                        if saving { ProgressView().tint(.white).accessibilityLabel("Planning Trip") }
                        else { Text(attempt == nil ? "Plan Trip" : "Retry Original Request") }
                    }
                    .buttonStyle(HomeyPrimaryButtonStyle())
                    .disabled(!ready || saving || homes.selectedHomeID != homeID)
                } else if confirmedTripID != nil {
                    Button(calendarSubmission.needsReconciliation ? "Check Calendar" : "Retry Calendar") { retryCalendar() }
                        .buttonStyle(HomeyPrimaryButtonStyle())
                        .disabled(saving || calendarSubmission.isSaving || homes.selectedHomeID != homeID)
                }
            }
            if finished, confirmedTripID != nil {
                Button("Close and Keep Trip") { keepTripOnly() }
                    .buttonStyle(HomeySecondaryButtonStyle())
                    .disabled(saving || homes.selectedHomeID != homeID)
            }
        }
        .interactiveDismissDisabled(saving)
        .onChange(of: start) { _, date in if end < date { end = date } }
        .onChange(of: homes.selectedHomeID) { _, id in if id != homeID { dismiss() } }
        .task {
            do {
                let user = try await SupabaseManager.shared.client.auth.session.user.id
                userID = user
                attempt = try store.load(userID: user, homeID: homeID, ideaID: idea.id)
                if let attempt, let tripID = try store.confirmedTripID(for: attempt) {
                    confirmedTripID = tripID
                    finished = true
                    if attempt.addToCalendar == true {
                        error = "Your Trip is planned. Retry Calendar to finish adding the existing Trip."
                    } else {
                        try store.finish(attempt)
                        if homes.selectedHomeID == homeID {
                            onPlanned()
                            await onChanged()
                        }
                    }
                }
                ready = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func plan() {
        guard !saving, !finished, ready, let userID, homes.selectedHomeID == homeID else { return }
        saving = true; error = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                guard try await SupabaseManager.shared.client.auth.session.user.id == userID else { throw TripPlanningSessionError.changed }
                guard homes.selectedHomeID == homeID else { return }
                let request: TripIdeaPlanningAttempt
                if let attempt { request = attempt }
                else {
                    let startDate = TripDateFormatters.backendString(from: start)
                    let endDate = TripDateFormatters.backendString(from: end)
                    let fromTime = includesTimes ? TripTimeFormatters.backendString(from: startTime) : nil
                    let toTime = includesTimes ? TripTimeFormatters.backendString(from: endTime) : nil
                    guard endDate >= startDate, !(includesTimes && endDate == startDate && (toTime ?? "") <= (fromTime ?? "")) else {
                        error = "Choose an end after the start."; return
                    }
                    request = TripIdeaPlanningAttempt(userID: userID, homeID: homeID, ideaID: idea.id,
                        startDate: startDate, endDate: endDate, startTime: fromTime, endTime: toTime,
                        addToCalendar: addToCalendar,
                        timezone: homes.selectedHome()?.timezone ?? TimeZone.current.identifier)
                    try store.save(request)
                    attempt = request
                }
                let tripID: UUID
                if let recovered = try store.confirmedTripID(for: request) {
                    tripID = recovered
                } else {
                    tripID = try await Trips2Service().planIdea(request)
                    // Do not allow the original plan to be resubmitted if local receipt storage fails.
                    confirmedTripID = tripID
                    finished = true
                    try store.confirm(request, tripID: tripID)
                }
                confirmedTripID = tripID
                finished = true
                if request.addToCalendar == true {
                    await syncCalendar(tripID: tripID, request: request)
                    if homes.selectedHomeID == homeID { await onChanged() }
                } else {
                    try store.finish(request)
                    UserDefaults.standard.removeObject(forKey: "homey.planCalendar.\(request.requestID)")
                    if homes.selectedHomeID == homeID {
                        onPlanned()
                        await onChanged()
                    }
                }
            } catch {
                self.error = confirmedTripID == nil ? error.localizedDescription :
                    "Your Trip is planned, but recovery information could not be saved. Your original request has been retained."
            }
        }
    }

    private func retryCalendar() {
        guard !saving, let tripID = confirmedTripID, let attempt,
              homes.selectedHomeID == homeID else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            await syncCalendar(tripID: tripID, request: attempt)
            if homes.selectedHomeID == homeID { await onChanged() }
        }
    }

    /// Calendar retry uses the confirmed canonical Trip and never calls the planning RPC.
    private func syncCalendar(tripID: UUID, request: TripIdeaPlanningAttempt) async {
        guard homes.selectedHomeID == request.homeID else { return }
        do {
            guard try await SupabaseManager.shared.client.auth.session.user.id == request.userID else {
                throw TripPlanningSessionError.changed
            }
            let trips = try await Trips2Service().trips(homeID: request.homeID)
            guard homes.selectedHomeID == request.homeID, !Task.isCancelled else { return }
            guard let trip = trips.first(where: { $0.id == tripID }), let start = trip.startDate else {
                throw TripCalendarPreparation.DraftError.invalidSchedule
            }
            let draft = try TripCalendarPreparation(tripID: tripID, homeID: request.homeID, title: trip.title,
                location: TripCalendarPreparation.destination(name: trip.destinationName, address: trip.destinationAddress),
                timezone: request.timezone ?? homes.selectedHome()?.timezone ?? TimeZone.current.identifier,
                startDate: TripDateFormatters.backendDate.string(from: start),
                endDate: trip.endDate.map { TripDateFormatters.backendDate.string(from: $0) },
                startTime: request.startTime, endTime: request.endTime, notes: trip.notes)
            let added = await calendarSubmission.submit(draft, userID: request.userID) {
                homes.selectedHomeID == request.homeID
            }
            guard homes.selectedHomeID == request.homeID else { return }
            if added {
                try store.finish(request)
                NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: request.homeID)
                onPlanned()
            } else {
                error = "Your Trip is planned, but Calendar was not confirmed. " + (calendarSubmission.errorMessage ?? "Please try again.")
            }
        } catch {
            self.error = "Your Trip is planned. Calendar could not be added: \(error.localizedDescription) Retry Calendar to use the existing Trip."
        }
    }

    private func keepTripOnly() {
        guard !saving, let attempt, confirmedTripID != nil, homes.selectedHomeID == homeID else { return }
        do {
            try store.finish(attempt)
            UserDefaults.standard.removeObject(forKey: "homey.planCalendar.\(attempt.requestID)")
            onPlanned()
        } catch { self.error = error.localizedDescription }
    }
}
