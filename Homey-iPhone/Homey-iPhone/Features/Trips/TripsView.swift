import SwiftUI
import Combine

@MainActor
final class TripsViewModel: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = TripsService()
    private var activeHomeID: UUID?
    private var activeLoadID = UUID()

    func load(homeID: UUID?) async {
        guard let homeID else {
            reset()
            return
        }

        let homeChanged = activeHomeID != homeID
        activeHomeID = homeID
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeHomeID == homeID, activeLoadID == loadID {
                isLoading = false
            }
        }
        if homeChanged {
            trips = []
        }

        do {
            let loadedTrips = try await service.trips(homeID: homeID)
            guard activeHomeID == homeID, activeLoadID == loadID else { return }
            trips = loadedTrips
        } catch {
            guard activeHomeID == homeID, activeLoadID == loadID else { return }
            guard !Self.isCancellation(error) else { return }
            errorMessage = "Trips could not be loaded. Please try again."
        }

    }

    func refresh() async {
        errorMessage = nil
        await load(homeID: activeHomeID)
    }

    func trips(in section: TripsSection) -> [Trip] {
        switch section {
        case .saved:
            return trips
                .filter { $0.status == .idea }
                .sorted { $0.createdAt > $1.createdAt }
        case .planned:
            return trips
                .filter { $0.status == .planned || $0.status == .active }
                .sorted(by: Self.upcomingSort)
        case .past:
            return trips
                .filter { $0.status == .completed }
                .sorted(by: Self.pastSort)
        }
    }

    private func reset() {
        activeHomeID = nil
        activeLoadID = UUID()
        trips = []
        isLoading = false
        errorMessage = nil
    }

    private static func upcomingSort(_ lhs: Trip, _ rhs: Trip) -> Bool {
        return switch (lhs.startDate, rhs.startDate) {
        case let (left?, right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.createdAt < rhs.createdAt
        }
    }

    private static func pastSort(_ lhs: Trip, _ rhs: Trip) -> Bool {
        let left = lhs.endDate ?? lhs.startDate
        let right = rhs.endDate ?? rhs.startDate
        return switch (left, right) {
        case let (left?, right?): left > right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }
}

struct TripsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = TripsViewModel()
    @State private var section: TripsSection = .saved
    @State private var editorMode: TripEditorMode?
    @State private var showsJoinTrip = false
    @State private var joinHomeID: UUID?

    var body: some View {
        ZStack {
            HomeyBackground()

            VStack(spacing: 12) {
                header
                sectionPicker
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: session.activeHome?.id) {
            await model.load(homeID: session.activeHome?.id)
        }
        .sheet(isPresented: $showsJoinTrip, onDismiss: { joinHomeID = nil }) {
            if let homeID = joinHomeID {
                TripJoinView(homeID: homeID) { joinedHomeID, tripID in
                    guard session.activeHome?.id == joinedHomeID else { return }
                    await model.load(homeID: joinedHomeID)
                    guard session.activeHome?.id == joinedHomeID else { return }
                    if let trip = model.trips.first(where: { $0.id == tripID }) {
                        switch trip.status {
                        case .idea: section = .saved
                        case .planned, .active: section = .planned
                        case .completed, .cancelled: section = .past
                        }
                    }
                }
                .environmentObject(session)
            }
        }
        .sheet(item: $editorMode) { mode in
            if let homeID = session.activeHome?.id {
                TripEditorView(homeID: homeID, mode: mode) {
                    await model.refresh()
                    section = mode.status == .idea ? .saved : .planned
                }
                .environmentObject(session)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Trips")
                    .font(.title.bold())
                    .foregroundStyle(HomeyColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Plan something together.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
            }

            Spacer()

            Menu {
                Button("Save Trip Idea", systemImage: "bookmark") {
                    editorMode = .saveIdea
                }
                Button("Plan a Trip", systemImage: "calendar.badge.plus") {
                    editorMode = .planTrip
                }
                Button("Join Trip", systemImage: "person.2.badge.plus") {
                    joinHomeID = session.activeHome?.id
                    showsJoinTrip = joinHomeID != nil
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 44, height: 44)
                    .background(HomeyColors.field, in: Circle())
            }
            .accessibilityLabel("Add Trip")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var sectionPicker: some View {
        Picker("Trips", selection: $section) {
            ForEach(TripsSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
        if session.activeHome == nil {
            ContentUnavailableView("Choose a Home", systemImage: "house")
                .frame(maxHeight: .infinity)
        } else if model.isLoading && model.trips.isEmpty {
            ProgressView("Loading trips…")
                .tint(HomeyColors.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            tripsList
        }
    }

    private var tripsList: some View {
        let visibleTrips = model.trips(in: section)
        return ScrollView {
            LazyVStack(spacing: 14) {
                if let errorMessage = model.errorMessage {
                    TripsErrorView(message: errorMessage) {
                        Task { await model.refresh() }
                    }
                } else if visibleTrips.isEmpty {
                    TripsEmptyView(section: section)
                } else {
                    ForEach(visibleTrips) { trip in
                        NavigationLink {
                            TripDetailView(
                                trip: trip,
                                homeID: session.activeHome?.id ?? trip.organizerHomeID,
                                onUpdated: { await model.refresh() },
                                onCompleted: {
                                    let completingHomeID = session.activeHome?.id
                                    await model.refresh()
                                    guard session.activeHome?.id == completingHomeID else { return }
                                    section = .past
                                }
                            )
                        } label: {
                            TripCard(trip: trip, section: section)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await model.refresh()
        }
    }
}

private struct TripCard: View {
    let trip: Trip
    let section: TripsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(trip.title)
                    .font(.headline)
                    .foregroundStyle(HomeyColors.text)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(trip.durationType.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyColors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HomeyColors.primary.opacity(0.10), in: Capsule())
            }

            if let destination = normalized(trip.destinationName) ?? normalized(trip.destinationAddress) {
                Label(destination, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .lineLimit(2)
            }

            if let dateText {
                Label(dateText, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyColors.secondaryText)
            }

            if section == .past, trip.rating != nil || trip.wouldDoAgain == true {
                HStack(spacing: 12) {
                    if let rating = trip.rating {
                        Text(String(repeating: "★", count: min(max(rating, 0), 5)))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("\(rating) out of 5 stars")
                    }
                    if trip.wouldDoAgain == true {
                        Label("Would Do Again", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyColors.success)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeyCard()
    }

    private var dateText: String? {
        TripDateFormatters.range(start: trip.startDate, end: trip.endDate)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TripsEmptyView: View {
    let section: TripsSection

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .homeyCard()
    }

    private var title: String {
        switch section {
        case .saved: "No trip ideas yet."
        case .planned: "No trips planned."
        case .past: "No past trips yet."
        }
    }

    private var icon: String {
        switch section {
        case .saved: "bookmark"
        case .planned: "calendar"
        case .past: "clock.arrow.circlepath"
        }
    }

    private var description: String {
        switch section {
        case .saved: "Save places your household would love to visit."
        case .planned: "Scheduled trips will appear here."
        case .past: "Completed trips will appear here."
        }
    }
}

private struct TripsErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(HomeyColors.danger)
            Text(message)
                .font(.headline)
                .foregroundStyle(HomeyColors.text)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(HomeyColors.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260)
        .homeyCard()
    }
}
