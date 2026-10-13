import SwiftUI

struct TripEditorView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let homeID: UUID
    let mode: TripEditorMode
    let trip: Trip?
    let canEditTrip: Bool
    let onSaved: () async -> Void

    @State private var draft: TripEditorDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = TripsService()

    @MainActor init(
        homeID: UUID,
        mode: TripEditorMode,
        trip: Trip? = nil,
        canEditTrip: Bool = false,
        onSaved: @escaping () async -> Void
    ) {
        self.homeID = homeID
        self.mode = mode
        self.trip = trip
        self.canEditTrip = canEditTrip
        self.onSaved = onSaved
        _draft = State(initialValue: trip.map(TripEditorDraft.init) ?? TripEditorDraft())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        detailsCard
                        typeCard
                        if mode.showsSchedule {
                            scheduleCard
                            travelCard
                        }
                        notesCard
                        if let errorMessage {
                            HomeyErrorView(message: errorMessage)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onChange(of: canSave) { _, allowed in
            if !allowed { dismiss() }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: session.activeHome?.id) { _, activeHomeID in
            if activeHomeID != homeID { dismiss() }
        }
    }

    private var detailsCard: some View {
        editorCard(title: "Trip Details", symbol: "airplane.departure") {
            VStack(spacing: 12) {
                editorField("Trip Name", text: $draft.title, contentType: .none)
                editorField("Destination", text: $draft.destinationName, contentType: .fullStreetAddress)
                editorField("Address (Optional)", text: $draft.destinationAddress, contentType: .fullStreetAddress)
            }
        }
    }

    private var typeCard: some View {
        editorCard(title: "Trip Type", symbol: "map") {
            Picker("Trip Type", selection: $draft.durationType) {
                ForEach(TripDurationType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(HomeyColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: draft.durationType) { _, newType in
                if newType == .fewHours || newType == .dayTrip {
                    draft.endDate = draft.startDate
                }
                if newType == .fewHours { draft.includesTimes = true }
            }
        }
    }

    private var scheduleCard: some View {
        editorCard(title: "Schedule", symbol: "calendar") {
            VStack(spacing: 14) {
                if draft.durationType == .fewHours || draft.durationType == .dayTrip {
                    DatePicker("Date", selection: $draft.startDate, displayedComponents: .date)
                        .onChange(of: draft.startDate) { _, value in draft.endDate = value }
                } else {
                    DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
                        .onChange(of: draft.startDate) { _, value in
                            if draft.endDate < value { draft.endDate = value }
                        }
                    Divider()
                    DatePicker("End Date", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }

                if draft.durationType == .dayTrip || draft.durationType == .custom {
                    Divider()
                    Toggle("Add Times", isOn: $draft.includesTimes)
                        .tint(HomeyColors.primary)
                }

                if showsTimePickers {
                    Divider()
                    DatePicker("Start Time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
                    Divider()
                    DatePicker("End Time", selection: $draft.endTime, displayedComponents: .hourAndMinute)
                }
            }
            .foregroundStyle(HomeyColors.text)
        }
    }

    private var travelCard: some View {
        editorCard(title: "Travel", symbol: "car") {
            VStack(spacing: 12) {
                HStack {
                    Text("Estimated Drive Time")
                        .foregroundStyle(HomeyColors.text)
                    Spacer()
                    Text(driveTimeText)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
                Stepper("Hours", value: $draft.estimatedDriveHours, in: 0...24)
                Stepper("Minutes", value: $draft.estimatedDriveMinutes, in: 0...55, step: 5)
            }
        }
    }

    private var notesCard: some View {
        editorCard(title: "Notes", symbol: "note.text") {
            TextField("Anything to remember?", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .homeyTextField()
        }
    }

    private var showsTimePickers: Bool {
        draft.durationType == .fewHours ||
            ((draft.durationType == .dayTrip || draft.durationType == .custom) && draft.includesTimes)
    }

    private var driveTimeText: String {
        let hours = draft.estimatedDriveHours
        let minutes = draft.estimatedDriveMinutes
        if hours == 0, minutes == 0 { return "Optional" }
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    private func editorField(
        _ prompt: String,
        text: Binding<String>,
        contentType: UITextContentType?
    ) -> some View {
        TextField(prompt, text: text)
            .textContentType(contentType)
            .textInputAutocapitalization(.words)
            .homeyTextField()
    }

    private func editorCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(HomeyTypography.headline)
                .foregroundStyle(HomeyColors.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeyCard()
    }

    private var canSave: Bool {
        session.activeHome?.id == homeID && !session.isSwitchingHome &&
            (trip == nil || (canEditTrip && session.activeRole?.canManageInvitations == true))
    }

    private func save() {
        guard !isSaving, canSave else {
            dismiss()
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                guard canSave else { isSaving = false; return }
                if let trip {
                    try await service.update(tripID: trip.id, draft: draft, mode: mode)
                } else {
                    try await service.create(homeID: homeID, draft: draft, mode: mode)
                }
                guard session.activeHome?.id == homeID else {
                    dismiss()
                    return
                }
                await onSaved()
                dismiss()
            } catch is CancellationError {
                // Normal task cancellation should not be shown as a save error.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
