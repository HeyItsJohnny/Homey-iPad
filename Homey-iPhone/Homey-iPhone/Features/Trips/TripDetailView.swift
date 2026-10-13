import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let homeID: UUID
    let onUpdated: () async -> Void
    var opensItinerary = false
    var onCompleted: (() async -> Void)? = nil

    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var didDelete = false
    @State private var deleteError: String?
    @State private var deleteTask: Task<Void, Never>?
    @State private var showsCompletionConfirmation = false
    @State private var isCompleting = false
    @State private var didComplete = false
    @State private var completionError: String?
    @State private var completionTask: Task<Void, Never>?
    @State private var showsCalendarCreate = false
    @State private var households: [TripHousehold] = []
    @State private var showsPlanAgain = false
    @State private var clonedTrip: Trip?
    @State private var showsClonedTrip = false
    @State private var didPlanAgain = false
    @State private var editorMode: TripEditorMode?
    @State private var section: TripDetailSection = .overview

    var body: some View {
        ZStack {
            HomeyBackground()

            VStack(spacing: 8) {
                Picker("Trip Details", selection: $section) {
                    ForEach(TripDetailSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCompleting || isDeleting || didDelete)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if section == .overview {
                    overview
                } else if section == .itinerary {
                    TripItineraryView(
                        trip: trip,
                        homeID: homeID,
                        canEditSharedTrip: canEditSharedTrip,
                        planTrip: { if canEditSharedTrip { editorMode = .planTrip } }
                    )
                    .environmentObject(session)
                } else {
                    TripPeopleView(trip: trip, homeID: homeID, onUpdated: onUpdated)
                        .environmentObject(session)
                }
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: homeID) {
            let loaded = try? await TripPeopleService().households(tripID: trip.id)
            guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
            households = loaded ?? []
        }
        .onChange(of: canEditSharedTrip) { _, allowed in
            if !allowed {
                editorMode = nil
                showsCompletionConfirmation = false
                completionTask?.cancel()
                showsDeleteConfirmation = false
                if !didDelete { deleteTask?.cancel() }
            }
        }
        .onAppear {
            if opensItinerary { section = .itinerary }
        }
        .navigationDestination(isPresented: $showsClonedTrip) {
            if let clonedTrip {
                TripDetailView(trip: clonedTrip, homeID: homeID, onUpdated: onUpdated, opensItinerary: true, onCompleted: onCompleted)
            }
        }
        .sheet(isPresented: $showsPlanAgain, onDismiss: {
            guard didPlanAgain, session.activeHome?.id == homeID else { return }
            didPlanAgain = false
            if clonedTrip != nil { showsClonedTrip = true } else { dismiss() }
        }) {
            TripPlanAgainView(trip: trip, homeID: homeID) { newID in
                await onUpdated()
                guard session.activeHome?.id == homeID else { return }
                // Reload authoritative backend data, including metadata and clone provenance.
                clonedTrip = try? await TripsService().trips(homeID: homeID).first { $0.id == newID }
                didPlanAgain = true
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $showsCalendarCreate) {
            if let home = session.activeHome, home.id == homeID {
                TripCalendarCreateView(trip: trip, home: home)
                    .environmentObject(session)
            }
        }
        .sheet(item: $editorMode) { mode in
            TripEditorView(homeID: homeID, mode: mode, trip: trip, canEditTrip: canEditSharedTrip) {
                await onUpdated()
                dismiss()
            }
            .environmentObject(session)
        }
        .confirmationDialog("Mark Trip Complete?", isPresented: $showsCompletionConfirmation, titleVisibility: .visible) {
            Button("Mark Complete") { completeTrip() }
                .disabled(isCompleting || !canCompleteTrip)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the Trip to Past and make it available for household review.")
        }
        .confirmationDialog("Delete Trip?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) { deleteTrip() }
                .disabled(isDeleting || !canDeleteTrip)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this Trip, its itinerary, household participation, participant selections, invitations, and Trip reviews. This cannot be undone.")
        }
        .onDisappear {
            completionTask?.cancel()
            // A confirmed deletion still refreshes the list after detail navigation closes.
            if !didDelete { deleteTask?.cancel() }
        }
        .onChange(of: session.activeHome?.id) { _, activeHomeID in
            if activeHomeID != homeID {
                showsCompletionConfirmation = false
                completionTask?.cancel()
                showsDeleteConfirmation = false
                if !didDelete { deleteTask?.cancel() }
                showsCalendarCreate = false
                showsPlanAgain = false
                clonedTrip = nil
                showsClonedTrip = false
                dismiss()
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if trip.status == .completed {
                    planAgainAction.disabled(isDeleting || didDelete)
                }
                overviewCard
                if let notes = normalized(trip.notes) {
                    detailCard(title: "Notes", symbol: "note.text") {
                        Text(notes)
                            .foregroundStyle(HomeyColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if hasSourceMetadata {
                    sourceCard
                }
                actions
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.title)
                        .font(HomeyTypography.hero)
                        .foregroundStyle(HomeyColors.text)
                    if let destination = normalized(trip.destinationName) {
                        Text(destination)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                }
                Spacer(minLength: 10)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyColors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HomeyColors.primary.opacity(0.10), in: Capsule())
            }
            if let address = normalized(trip.destinationAddress) {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeyCard()
    }

    private var overviewCard: some View {
        detailCard(title: "Trip Overview", symbol: "map") {
            VStack(spacing: 0) {
                detailRow("Trip Type", value: trip.durationType.displayName)
                if let dates = TripDateFormatters.range(start: trip.startDate, end: trip.endDate) {
                    Divider().padding(.vertical, 12)
                    detailRow("Dates", value: dates)
                }
                if let times = timeRangeText {
                    Divider().padding(.vertical, 12)
                    detailRow("Times", value: times)
                }
                if let drive = driveTimeText {
                    Divider().padding(.vertical, 12)
                    detailRow("Drive", value: drive)
                }
            }
        }
    }

    private var sourceCard: some View {
        detailCard(title: "Source", symbol: "link") {
            VStack(alignment: .leading, spacing: 8) {
                if let sourceTitle = normalized(trip.sourceTitle) {
                    Text(sourceTitle)
                        .font(.headline)
                        .foregroundStyle(HomeyColors.text)
                }
                if let sourceType = normalized(trip.sourceType) {
                    Text(sourceType.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
                if let sourceText = normalized(trip.sourceText) {
                    Text(sourceText)
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }
                if let sourceImage = normalized(trip.sourceImageURL), let url = URL(string: sourceImage) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if let sourceURL = normalized(trip.sourceURL), let url = URL(string: sourceURL) {
                    Link("Open Source", destination: url)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canEditSharedTrip: Bool {
        session.activeHome?.id == homeID && !session.isSwitchingHome &&
            TripPermissions.canEdit(homeID: homeID, role: session.activeRole, households: households)
    }

    private var planAgainAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if trip.wouldDoAgain == true {
                Label("Would Do Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyColors.success)
            }
            Button("Plan Again") { showsPlanAgain = true }
                .buttonStyle(HomeyButtonStyle())
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let completionError { HomeyErrorView(message: completionError) }
            if let deleteError { HomeyErrorView(message: deleteError) }
            if canCompleteTrip {
                Button {
                    showsCompletionConfirmation = true
                } label: {
                    if isCompleting { ProgressView() } else { Text("Mark Trip Complete") }
                }
                .buttonStyle(HomeyButtonStyle())
            }
            if trip.status != .cancelled, session.activeHome?.id == homeID {
                Button("Add to Calendar") { showsCalendarCreate = true }
                    .buttonStyle(HomeyButtonStyle(secondary: true))
                    .disabled(session.isSwitchingHome)
            }
            if canEditSharedTrip, trip.status == .idea {
                Button("Plan This Trip") { editorMode = .planTrip }
                    .buttonStyle(HomeyButtonStyle())
            }
            if canEditSharedTrip {
                Button("Edit Trip") { editorMode = .edit(trip.status) }
                    .buttonStyle(HomeyButtonStyle(secondary: true))
            }
            if canDeleteTrip {
                Divider().padding(.top, 12)
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    HStack(spacing: 10) {
                        if isDeleting { ProgressView().tint(HomeyColors.danger) }
                        Text(isDeleting ? "Deleting…" : "Delete Trip")
                    }
                    .font(.headline)
                    .foregroundStyle(HomeyColors.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HomeyColors.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(isCompleting || didComplete || isDeleting || didDelete)
    }

    private var canDeleteTrip: Bool {
        !didDelete && !didComplete && !isCompleting && session.activeHome?.id == homeID && !session.isSwitchingHome &&
            TripPermissions.canDelete(homeID: homeID, organizerHomeID: trip.organizerHomeID,
                                      role: session.activeRole, households: households)
    }

    private func deleteTrip() {
        guard !isDeleting, canDeleteTrip else { return }
        isDeleting = true
        deleteError = nil
        deleteTask = Task { @MainActor in
            defer { isDeleting = false }
            do {
                try Task.checkCancellation()
                guard canDeleteTrip else { return }
                try await TripsService().delete(tripID: trip.id)
                // Once deletion succeeds, neither navigation nor refresh can retry the RPC.
                didDelete = true
                guard session.activeHome?.id == homeID else { return }
                showsClonedTrip = false
                clonedTrip = nil
                dismiss()
                await onUpdated()
            } catch is CancellationError {
                // Navigation and Home-switch cancellation are silent.
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                deleteError = "Trip could not be deleted."
            }
        }
    }

    private var canCompleteTrip: Bool {
        !didComplete && !didDelete && !isDeleting && session.activeHome?.id == homeID && !session.isSwitchingHome &&
            TripPermissions.canComplete(status: trip.status, homeID: homeID, role: session.activeRole, households: households)
    }

    private func completeTrip() {
        guard !isCompleting, canCompleteTrip else { return }
        isCompleting = true
        completionError = nil
        completionTask = Task { @MainActor in
            defer { isCompleting = false }
            do {
                try Task.checkCancellation()
                guard canCompleteTrip else { return }
                try await TripsService().complete(tripID: trip.id)
                // Completion is final; refreshing never triggers another completion request.
                didComplete = true
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                if let onCompleted { await onCompleted() } else { await onUpdated() }
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                dismiss()
            } catch is CancellationError {
                // Home switching and navigation cancellation are silent.
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                completionError = "Trip could not be completed."
            }
        }
    }

    private func detailCard<Content: View>(
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

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(HomeyColors.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(HomeyColors.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var statusText: String {
        switch trip.status {
        case .idea: "Saved Idea"
        case .planned: "Planned"
        case .active: "Active"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }

    private var timeRangeText: String? {
        let start = TripTimeFormatters.displayString(trip.startTime)
        let end = TripTimeFormatters.displayString(trip.endTime)
        return switch (start, end) {
        case let (start?, end?): "\(start)–\(end)"
        case let (start?, nil): start
        case let (nil, end?): end
        case (nil, nil): nil
        }
    }

    private var driveTimeText: String? {
        guard let total = trip.estimatedDriveMinutes, total > 0 else { return nil }
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    private var hasSourceMetadata: Bool {
        normalized(trip.sourceType) != nil ||
            normalized(trip.sourceURL) != nil ||
            normalized(trip.sourceTitle) != nil ||
            normalized(trip.sourceText) != nil ||
            normalized(trip.sourceImageURL) != nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum TripDetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case itinerary = "Itinerary"
    case people = "People"
    var id: String { rawValue }
}

extension TripEditorMode: Identifiable {
    var id: String {
        switch self {
        case .saveIdea: "saveIdea"
        case .planTrip: "planTrip"
        case let .edit(status): "edit-\(status.rawValue)"
        }
    }
}
