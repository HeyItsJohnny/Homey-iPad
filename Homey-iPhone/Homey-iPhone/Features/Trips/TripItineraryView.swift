import SwiftUI
import Combine

@MainActor
final class TripItineraryViewModel: ObservableObject {
    @Published private(set) var items: [TripItineraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?

    private let service = TripItineraryService()
    private var activeTripID: UUID?
    private var loadID = UUID()

    func load(tripID: UUID) async {
        let tripChanged = activeTripID != tripID
        activeTripID = tripID
        let requestID = UUID()
        loadID = requestID
        if tripChanged { items = [] }
        isLoading = true
        errorMessage = nil
        defer {
            if activeTripID == tripID, loadID == requestID { isLoading = false }
        }

        do {
            let loaded = try await service.itinerary(tripID: tripID)
            guard activeTripID == tripID, loadID == requestID else { return }
            items = loaded
        } catch is CancellationError {
            // Navigation and task cancellation are not user-facing failures.
        } catch {
            guard activeTripID == tripID, loadID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let activeTripID else { return }
        errorMessage = nil
        await load(tripID: activeTripID)
    }

    func days(for trip: Trip) -> [TripItineraryDay] {
        guard let tripStart = trip.startDate ?? trip.endDate else { return [] }
        let tripEnd = trip.endDate ?? tripStart
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = min(tripStart, tripEnd)
        let end = max(tripStart, tripEnd)
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        let grouped = Dictionary(grouping: items, by: { TripDateFormatters.backendDate.string(from: $0.itemDate) })
        return dates.enumerated().map { index, date in
            let key = TripDateFormatters.backendDate.string(from: date)
            let dayItems = (grouped[key] ?? []).sorted(by: Self.itemSort)
            return TripItineraryDay(index: index + 1, date: date, items: dayItems)
        }
    }

    func sortOrder(for item: TripItineraryItem?, on date: Date) -> Int {
        if let item,
           TripDateFormatters.backendDate.string(from: item.itemDate) == TripDateFormatters.backendString(from: date) {
            return item.sortOrder
        }
        let key = TripDateFormatters.backendString(from: date)
        return items
            .filter { TripDateFormatters.backendDate.string(from: $0.itemDate) == key }
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    func remove(_ item: TripItineraryItem) async {
        guard !isMutating, activeTripID == item.tripID else { return }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await service.remove(tripID: item.tripID, itemID: item.id)
            await load(tripID: item.tripID)
        } catch is CancellationError {
            // Normal cancellation is intentionally silent.
        } catch {
            errorMessage = error.localizedDescription
            await loadAfterMutationFailure(tripID: item.tripID, preserving: error.localizedDescription)
        }
    }

    func reorder(dayItems: [TripItineraryItem], from source: IndexSet, to destination: Int, canEdit: @escaping @MainActor () -> Bool) {
        guard canEdit(), !isMutating, let tripID = activeTripID else { return }
        var reordered = dayItems
        reordered.move(fromOffsets: source, toOffset: destination)
        let changes = reordered.enumerated().compactMap { index, item -> (TripItineraryItem, Int)? in
            item.sortOrder == index ? nil : (item, index)
        }
        guard !changes.isEmpty else { return }

        for (item, order) in changes {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].sortOrder = order
            }
        }
        isMutating = true
        errorMessage = nil
        Task {
            var mutationError: Error?
            do {
                for (item, order) in changes {
                    try Task.checkCancellation()
                    guard canEdit() else { break }
                    try await service.saveExisting(item, sortOrder: order)
                }
            } catch is CancellationError {
                // A reload below restores the authoritative order.
            } catch {
                mutationError = error
            }
            await load(tripID: tripID)
            if let mutationError { errorMessage = mutationError.localizedDescription }
            isMutating = false
        }
    }

    private func loadAfterMutationFailure(tripID: UUID, preserving message: String) async {
        await load(tripID: tripID)
        errorMessage = message
    }

    private static func itemSort(_ lhs: TripItineraryItem, _ rhs: TripItineraryItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TripItineraryView: View {
    @EnvironmentObject private var session: AppSession
    let trip: Trip
    let homeID: UUID
    let canEditSharedTrip: Bool
    let planTrip: () -> Void

    @StateObject private var model = TripItineraryViewModel()
    @State private var editor: ItineraryEditorPresentation?
    @State private var removeCandidate: TripItineraryItem?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if trip.status == .idea || trip.startDate == nil {
                lockedState
            } else {
                itineraryList
            }
        }
        .task(id: trip.id) {
            if trip.status != .idea, trip.startDate != nil {
                await model.load(tripID: trip.id)
            }
        }
        .sheet(item: $editor) { presentation in
            TripItineraryEditorView(
                homeID: homeID,
                trip: trip,
                canEditTrip: canEditSharedTrip,
                selectedDate: presentation.date,
                item: presentation.item,
                sortOrder: { date in model.sortOrder(for: presentation.item, on: date) },
                onSaved: { await model.load(tripID: trip.id) }
            )
            .environmentObject(session)
        }
        .confirmationDialog(
            "Remove Activity?",
            isPresented: .init(
                get: { removeCandidate != nil },
                set: { if !$0 { removeCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard isEditable, let item = removeCandidate else { return }
                removeCandidate = nil
                Task {
                    guard isEditable else { return }
                    await model.remove(item)
                }
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: {
            Text("Remove this activity from the itinerary?")
        }
        .toolbar {
            if isEditable, model.items.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    .disabled(model.isMutating)
                }
            }
        }
        .onChange(of: isEditable) { _, allowed in
            if !allowed {
                editor = nil
                removeCandidate = nil
                editMode = .inactive
            }
        }
        .environment(\.editMode, $editMode)
    }

    private var itineraryList: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(HomeyColors.danger)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(HomeyColors.danger)
                        Spacer()
                        Button("Retry") { Task { await model.refresh() } }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.white.opacity(0.94))
            }

            ForEach(model.days(for: trip)) { day in
                Section {
                    if day.items.isEmpty {
                        Text("No activities planned")
                            .font(.subheadline)
                            .foregroundStyle(HomeyColors.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(day.items) { item in
                            itineraryRow(item)
                        }
                        .onMove { source, destination in
                            guard isEditable else { return }
                            model.reorder(dayItems: day.items, from: source, to: destination, canEdit: { isEditable })
                        }
                    }

                    if isEditable, !editMode.isEditing {
                        Button {
                            editor = ItineraryEditorPresentation(date: day.date, item: nil)
                        } label: {
                            Label("Add Activity", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeyColors.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                        .disabled(model.isMutating)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAY \(day.index)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyColors.primary)
                        Text(TripItineraryDateFormatters.dayHeader.string(from: day.date))
                            .font(.headline)
                            .foregroundStyle(HomeyColors.text)
                            .textCase(nil)
                    }
                    .padding(.top, 8)
                }
                .listRowBackground(Color.white.opacity(0.94))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay {
            if model.isLoading, model.items.isEmpty {
                ProgressView("Loading itinerary…")
                    .tint(HomeyColors.primary)
            }
        }
        .refreshable { await model.refresh() }
    }

    private func itineraryRow(_ item: TripItineraryItem) -> some View {
        Button {
            guard isEditable, !model.isMutating, !editMode.isEditing else { return }
            editor = ItineraryEditorPresentation(date: item.itemDate, item: item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let time = TripTimeFormatters.displayString(item.startTime) {
                    Text(time)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyColors.primary)
                        .frame(width: 72, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(HomeyColors.text)
                    if let location = normalized(item.locationName) {
                        Text(location)
                            .font(.subheadline)
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                if isEditable, !editMode.isEditing {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyColors.secondaryText.opacity(0.6))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .swipeActions {
            if isEditable {
                Button("Remove", role: .destructive) { removeCandidate = item }
            }
        }
    }

    private var lockedState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(HomeyColors.primary)
                Text("Plan this trip to start building an itinerary.")
                    .font(.headline)
                    .foregroundStyle(HomeyColors.text)
                    .multilineTextAlignment(.center)
                if trip.status == .idea, canEditSharedTrip {
                    Button("Plan This Trip", action: planTrip)
                        .buttonStyle(HomeyButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .homeyCard()
            .padding(16)
        }
    }

    private var isEditable: Bool {
        canEditSharedTrip && session.activeHome?.id == homeID &&
            session.activeRole?.canManageInvitations == true && !session.isSwitchingHome &&
            (trip.status == .planned || trip.status == .active)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ItineraryEditorPresentation: Identifiable {
    let id = UUID()
    let date: Date
    let item: TripItineraryItem?
}
