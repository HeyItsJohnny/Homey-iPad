import SwiftUI
import Supabase

private enum TripHubSheet: Identifiable {
    case idea(SavedTripIdea), trip(Trip), editor(SavedTripIdea?), again(Trip)
    var id: String {
        switch self {
        case .idea(let i): "idea-\(i.id)"
        case .trip(let t): "trip-\(t.id)"
        case .editor(let i): "edit-\(i?.id.uuidString ?? "new")"
        case .again(let t): "again-\(t.id)"
        }
    }
}

struct TripsView: View {
    @EnvironmentObject private var homes: HomeService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TripsHubModel()
    @State private var sheet: TripHubSheet?
    private var homeID: UUID? { homes.selectedHomeID }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Trips").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Little outings. Big memories.").font(.title3).foregroundStyle(HomeyTheme.textSecondary)
                }
                Spacer()
                Button { sheet = .editor(nil) } label: {
                    Label("Add Trip Idea", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(HomeyTheme.primary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(homeID == nil)
            }.padding(.trailing, 70)
            if let error = model.error {
                Text(error).foregroundStyle(HomeyTheme.danger).accessibilityLabel(error)
            }
            HStack(alignment: .top, spacing: 16) {
                column("Saved", icon: "bookmark.fill", color: HomeyTheme.tripSaved) {
                    if model.ideas.isEmpty { empty("Save an idea for your next adventure.", icon: "bookmark") }
                    ForEach(model.ideas) { idea in
                        Button { sheet = .idea(idea) } label: {
                            card(idea.title, destination: idea.destinationName) {
                                Text("\(idea.completedVisitCount) completed visits").font(.caption)
                                if idea.ratedVisitCount > 0, let rating = idea.averageRating {
                                    Label(String(format: "%.1f", rating), systemImage: "star.fill").font(.caption)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                column("Planned", icon: "calendar", color: HomeyTheme.tripPlanned) {
                    let trips = TripsHubSort.planned(model.trips)
                    if trips.isEmpty { empty("Plan a Saved idea and find it here.", icon: "calendar") }
                    ForEach(trips) { trip in tripCard(trip) }
                }
                column("Past", icon: "sun.max.fill", color: HomeyTheme.tripPast) {
                    let trips = TripsHubSort.past(model.trips)
                    if trips.isEmpty { empty("Your completed adventures will appear here.", icon: "sun.max") }
                    ForEach(trips) { trip in tripCard(trip) }
                }
            }
            .padding(20).dashboardCard(cornerRadius: HomeyRadius.page)
            .overlay {
                if model.loading && model.trips.isEmpty && model.ideas.isEmpty {
                    ProgressView("Loading Trips…").padding(20)
                        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card))
                }
            }
        }
        .foregroundStyle(HomeyTheme.textPrimary)
        .padding(.horizontal, 34).padding(.top, 34).padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .task(id: homeID) { sheet = nil; await model.load(homeID) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load(homeID) } }
        }
        .sheet(item: $sheet) { destination in
            if let homeID {
                switch destination {
                case .idea(let idea):
                    TripIdeaHubDetail(idea: idea, homeID: homeID, onChanged: refresh, onPlanned: { sheet = nil })
                case .trip(let trip):
                    TripHubDetail(trip: trip, homeID: homeID, onChanged: refresh) { sheet = .again(trip) }
                case .editor(let idea):
                    TripIdeaHubEditor(homeID: homeID, idea: idea, source: nil, onSaved: { _ in await refresh() })
                case .again(let trip):
                    TripIdeaHubEditor(homeID: homeID, idea: nil, source: trip) { id in
                        await refresh()
                        if let idea = model.ideas.first(where: { $0.id == id }) { sheet = .idea(idea) }
                    }
                }
            }
        }
    }
    private func refresh() async { await model.load(homeID) }
    private func column<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Label(title, systemImage: icon).font(.headline.bold()).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(color.opacity(0.10))
            ScrollView { LazyVStack(alignment: .leading, spacing: 10, content: content).padding(12) }
                .scrollBounceBehavior(.always, axes: .vertical)
                .refreshable { await refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card))
        .clipShape(RoundedRectangle(cornerRadius: HomeyRadius.card))
        .overlay { RoundedRectangle(cornerRadius: HomeyRadius.card).stroke(HomeyTheme.borderSubtle.opacity(0.75)) }
    }
    private func card<Content: View>(_ title: String, destination: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.bold())
            if let destination, !destination.isEmpty { Text(destination).font(.caption) }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            .padding(12).background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button))
            .overlay { RoundedRectangle(cornerRadius: HomeyRadius.button).stroke(HomeyTheme.borderSubtle.opacity(0.65)) }
    }
    private func tripCard(_ trip: Trip) -> some View {
        Button { sheet = .trip(trip) } label: {
            card(trip.title, destination: trip.destinationName) {
                Text(TripDateFormatters.range(start: trip.startDate, end: trip.endDate) ?? "Dates to be decided").font(.caption)
                if trip.status == .completed { TripFeedbackSummary(homeID: homeID, tripID: trip.id) }
            }
        }.buttonStyle(.plain)
    }
    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) { Image(systemName: icon).font(.title2); Text(text).font(.subheadline) }
            .foregroundStyle(HomeyTheme.textSecondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

private struct TripFeedbackSummary: View {
    let homeID: UUID?
    let tripID: UUID
    @State private var feedback: TripHouseholdFeedback?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let feedback {
                if (1...5).contains(feedback.rating) {
                    Text(String(repeating: "★", count: feedback.rating) + String(repeating: "☆", count: 5 - feedback.rating))
                        .accessibilityLabel("\(feedback.rating) out of 5 stars")
                }
                if let notes = feedback.notes { Text(notes) }
            }
            if failed { Text("Home review unavailable. Reopen to retry.") }
        }.font(.caption)
        .task(id: "\(homeID?.uuidString ?? ""):\(tripID)") {
            feedback = nil; failed = false
            guard let homeID else { return }
            do { feedback = try await Trips2Service().feedback(homeID: homeID, tripID: tripID) }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct TripHubDetail: View {
    @EnvironmentObject private var homes: HomeService
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let homeID: UUID
    let onChanged: () async -> Void
    let again: () -> Void
    @State private var calendarNotice: String?
    @StateObject private var calendarSubmission = TripCalendarSubmission(service: TripCalendarService())
    var body: some View {
        TripModalLayout(title: "Trip Details", subtitle: trip.title, onDone: { dismiss() }) {
            if let destination = trip.destinationName {
                TripModalInfo(title: "Destination", value: destination, icon: "mappin.and.ellipse")
            }
            TripModalInfo(title: "Dates", value: TripDateFormatters.range(start: trip.startDate, end: trip.endDate) ?? "Dates to be decided", icon: "calendar")
            if let startTime = TripTimeFormatters.displayString(trip.startTime) {
                TripModalInfo(title: "Times", value: [startTime, TripTimeFormatters.displayString(trip.endTime)].compactMap { $0 }.joined(separator: " – "), icon: "clock")
            }
            if let notes = trip.notes, !notes.isEmpty {
                TripModalInfo(title: "Notes", value: notes, icon: "text.alignleft")
            }
            if trip.status == .completed {
                VStack(alignment: .leading, spacing: 12) {
                    TripModalSectionLabel(title: "Your Home’s review")
                    TripFeedbackSummary(homeID: homeID, tripID: trip.id)
                }.frame(maxWidth: .infinity, alignment: .leading).tripInsetPanel()
            }
            if let calendarNotice { TripModalBanner(message: calendarNotice) }
            HStack(spacing: 12) {
                if trip.status == .completed {
                    Button("Plan Again", action: again).buttonStyle(HomeyPrimaryButtonStyle())
                } else {
                    Button { Task { await addToCalendar() } } label: {
                        if calendarSubmission.isSaving { ProgressView().tint(.white) }
                        else { Label(calendarSubmission.isComplete ? "Added to Calendar" : (calendarSubmission.needsReconciliation ? "Check Calendar" : "Add to Calendar"), systemImage: "calendar.badge.plus") }
                    }
                        .buttonStyle(HomeyPrimaryButtonStyle())
                        .disabled(calendarSubmission.isSaving || calendarSubmission.isComplete || homes.selectedHomeID != homeID)
                }
            }
        }
    }
    private func addToCalendar() async {
        guard homes.selectedHomeID == homeID else { return }
        do {
            guard let start = trip.startDate else { throw TripCalendarPreparation.DraftError.invalidSchedule }
            let userID = try await SupabaseManager.shared.client.auth.session.user.id
            let draft = try TripCalendarPreparation(tripID: trip.id, homeID: homeID, title: trip.title,
                location: TripCalendarPreparation.destination(name: trip.destinationName, address: trip.destinationAddress),
                timezone: homes.selectedHome()?.timezone ?? TimeZone.current.identifier,
                startDate: TripDateFormatters.backendDate.string(from: start),
                endDate: trip.endDate.map { TripDateFormatters.backendDate.string(from: $0) },
                startTime: trip.startTime, endTime: trip.endTime, notes: trip.notes)
            let added = await calendarSubmission.submit(draft, userID: userID) { homes.selectedHomeID == homeID }
            guard homes.selectedHomeID == homeID else { return }
            if added {
                NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: homeID)
                calendarNotice = nil
                await onChanged()
            } else { calendarNotice = calendarSubmission.errorMessage }

        } catch { calendarNotice = error.localizedDescription }
    }
}

private struct TripIdeaHubDetail: View {
    @EnvironmentObject private var homes: HomeService
    @Environment(\.dismiss) private var dismiss
    let idea: SavedTripIdea
    let homeID: UUID
    let onChanged: () async -> Void
    let onPlanned: () -> Void
    @State private var planning = false
    @State private var editing = false
    @State private var archiving = false
    @State private var confirmsArchive = false
    @State private var error: String?
    var body: some View {
        TripModalLayout(title: "Saved Idea", subtitle: idea.title, onDone: { dismiss() }, onEdit: { editing = true }) {
            if let destination = idea.destinationName {
                TripModalInfo(title: "Destination", value: destination, icon: "mappin.and.ellipse")
            }
            if let notes = idea.notes, !notes.isEmpty {
                TripModalInfo(title: "Notes", value: notes, icon: "text.alignleft")
            }
            VStack(alignment: .leading, spacing: 12) {
                TripModalSectionLabel(title: "Family visits")
                Label("\(idea.completedVisitCount) completed visits", systemImage: "checkmark.circle")
                if idea.ratedVisitCount > 0, let rating = idea.averageRating {
                    Label(String(format: "%.1f out of 5", rating), systemImage: "star.fill")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).tripInsetPanel()
            if let error { TripModalBanner(message: error, isError: true) }
            Button("Plan This Trip") { planning = true }.buttonStyle(HomeyPrimaryButtonStyle())
            Button(role: .destructive) { confirmsArchive = true } label: {
                HStack(spacing: 9) {
                    if archiving { ProgressView() } else { Image(systemName: "archivebox"); Text("Archive Idea") }
                }
                .font(.subheadline.bold()).foregroundStyle(HomeyTheme.danger)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(HomeyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.button))
                .overlay { RoundedRectangle(cornerRadius: HomeyRadius.button).stroke(HomeyTheme.danger.opacity(0.18)) }
            }.buttonStyle(.plain)
        }
        .disabled(archiving)
        .interactiveDismissDisabled(archiving)
        .confirmationDialog("Archive this idea? Historical Trips will be kept.", isPresented: $confirmsArchive) {
            Button("Archive", role: .destructive) {
                guard homes.selectedHomeID == homeID else { return }
                archiving = true
                Task { @MainActor in
                    defer { archiving = false }
                    do { try await Trips2Service().archiveIdea(homeID: homeID, ideaID: idea.id); await onChanged(); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $planning) { TripQuickPlan(idea: idea, homeID: homeID, onChanged: onChanged, onPlanned: onPlanned) }
        .sheet(isPresented: $editing) {
            TripIdeaHubEditor(homeID: homeID, idea: idea, source: nil) { _ in await onChanged(); dismiss() }
        }
    }
}

private struct TripIdeaHubEditor: View {
    @EnvironmentObject private var homes: HomeService
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID
    let idea: SavedTripIdea?
    let source: Trip?
    let onSaved: (UUID) async -> Void
    @State private var draft: TripIdeaDraft
    @State private var saving = false
    @State private var error: String?
    init(homeID: UUID, idea: SavedTripIdea?, source: Trip?, onSaved: @escaping (UUID) async -> Void) {
        self.homeID = homeID; self.idea = idea; self.source = source; self.onSaved = onSaved
        _draft = State(initialValue: idea.map(TripIdeaDraft.init(idea:)) ?? source.map(TripIdeaDraft.init(trip:)) ?? TripIdeaDraft())
    }
    var body: some View {
        TripModalLayout(title: idea == nil ? "Add Trip Idea" : "Edit Trip Idea", subtitle: "Save inspiration for your family’s next adventure.") {
            if source != nil { TripModalBanner(message: "Save a new idea from this visit, then choose new dates. The historical Trip stays unchanged.") }
            TripModalField(title: "Title", supportingText: "Required", text: $draft.title)
            TripModalField(title: "Destination", text: $draft.destinationName)
            TripModalField(title: "Notes", text: $draft.notes, axis: .vertical)
            if let error { TripModalBanner(message: error, isError: true) }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(HomeySecondaryButtonStyle()).disabled(saving)
                Button { save() } label: {
                    if saving { ProgressView().tint(.white).accessibilityLabel("Saving idea") }
                    else { Text("Save Idea") }
                }
                .buttonStyle(HomeyPrimaryButtonStyle())
                .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || homes.selectedHomeID != homeID)
            }
        }.disabled(saving)
        .interactiveDismissDisabled(saving)
        .onChange(of: homes.selectedHomeID) { _, id in if id != homeID { dismiss() } }
    }
    private func save() {
        guard !saving, homes.selectedHomeID == homeID else { return }
        saving = true; error = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                let id: UUID
                if let idea { try await Trips2Service().updateIdea(homeID: homeID, ideaID: idea.id, draft: draft); id = idea.id }
                else { id = try await Trips2Service().createIdea(homeID: homeID, draft: draft) }
                dismiss()
                if homes.selectedHomeID == homeID { await onSaved(id) }
            } catch { self.error = error.localizedDescription }
        }
    }
}
