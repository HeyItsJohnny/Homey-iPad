import SwiftUI

struct TripItineraryEditorView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let homeID: UUID
    let trip: Trip
    let canEditTrip: Bool
    let item: TripItineraryItem?
    let sortOrder: (Date) -> Int
    let onSaved: () async -> Void

    @State private var draft: TripItineraryDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = TripItineraryService()

    @MainActor init(
        homeID: UUID,
        trip: Trip,
        canEditTrip: Bool,
        selectedDate: Date,
        item: TripItineraryItem? = nil,
        sortOrder: @escaping (Date) -> Int,
        onSaved: @escaping () async -> Void
    ) {
        self.homeID = homeID
        self.trip = trip
        self.canEditTrip = canEditTrip
        self.item = item
        self.sortOrder = sortOrder
        self.onSaved = onSaved
        _draft = State(initialValue: item.map(TripItineraryDraft.init) ?? TripItineraryDraft(itemDate: selectedDate))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        activityCard
                        timeCard
                        locationCard
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
            .navigationTitle(item == nil ? "Add Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text("Save").fontWeight(.semibold) }
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

    private var activityCard: some View {
        editorCard(title: "Activity", symbol: "figure.walk") {
            VStack(spacing: 14) {
                TextField("Activity Name", text: $draft.title)
                    .textInputAutocapitalization(.words)
                    .homeyTextField()
                DatePicker(
                    "Date",
                    selection: $draft.itemDate,
                    in: validDateRange,
                    displayedComponents: .date
                )
            }
        }
    }

    private var timeCard: some View {
        editorCard(title: "Time", symbol: "clock") {
            VStack(spacing: 14) {
                Toggle("Start Time", isOn: $draft.includesStartTime)
                    .tint(HomeyColors.primary)
                if draft.includesStartTime {
                    DatePicker("Starts", selection: $draft.startTime, displayedComponents: .hourAndMinute)
                }
                Divider()
                Toggle("End Time", isOn: $draft.includesEndTime)
                    .tint(HomeyColors.primary)
                if draft.includesEndTime {
                    DatePicker("Ends", selection: $draft.endTime, displayedComponents: .hourAndMinute)
                }
            }
        }
    }

    private var locationCard: some View {
        editorCard(title: "Location", symbol: "mappin.and.ellipse") {
            VStack(spacing: 12) {
                TextField("Location", text: $draft.locationName)
                    .textInputAutocapitalization(.words)
                    .homeyTextField()
                TextField("Address", text: $draft.locationAddress)
                    .textContentType(.fullStreetAddress)
                    .homeyTextField()
            }
        }
    }

    private var notesCard: some View {
        editorCard(title: "Notes", symbol: "note.text") {
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .homeyTextField()
        }
    }

    private var validDateRange: ClosedRange<Date> {
        let start = TripDateFormatters.localDate(trip.startDate ?? trip.endDate ?? Date())
        let end = TripDateFormatters.localDate(trip.endDate ?? trip.startDate ?? start)
        return min(start, end)...max(start, end)
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
        canEditTrip && session.activeHome?.id == homeID &&
            session.activeRole?.canManageInvitations == true && !session.isSwitchingHome
    }

    private func save() {
        guard !isSaving, canSave else {
            dismiss()
            return
        }
        guard validDateRange.contains(draft.itemDate) else {
            errorMessage = TripItineraryError.invalidDate.localizedDescription
            return
        }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                guard canSave else { isSaving = false; return }
                try await service.save(
                    tripID: trip.id,
                    itemID: item?.id,
                    draft: draft,
                    sortOrder: sortOrder(draft.itemDate)
                )
                guard session.activeHome?.id == homeID else {
                    dismiss()
                    return
                }
                await onSaved()
                dismiss()
            } catch is CancellationError {
                // Normal task cancellation should not be shown as an error.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
