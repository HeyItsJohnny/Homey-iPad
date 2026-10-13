import SwiftUI

struct TripPeopleView: View {
    @EnvironmentObject private var session: AppSession
    let trip: Trip
    let homeID: UUID
    let onUpdated: () async -> Void

    @State private var households: [TripHousehold] = []
    @State private var participants: [TripParticipant] = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var showsPicker = false
    @State private var invite: TripHouseholdInvite?
    @State private var removal: TripHousehold?
    @State private var mutationTask: Task<Void, Never>?
    private let service = TripPeopleService()

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    HomeyErrorView(message: errorMessage)
                    Button("Try Again") { Task { await load() } }.disabled(isMutating)
                }
            }
            Section("Households") {
                ForEach(orderedHouseholds) { household in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(householdName(household))
                                .font(.headline)
                            Text(household.isOrganizer ? "Organizer Household" : "Participating Household")
                                .font(.caption)
                                .foregroundStyle(HomeyColors.secondaryText)
                            if !household.isAccepted {
                                Text(household.status.capitalized).font(.caption)
                            }
                        }
                        Spacer()
                        if canManage, !household.isOrganizer, household.homeID != trip.organizerHomeID {
                            Button("Remove", role: .destructive) { removal = household }
                                .disabled(isMutating)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if hasLoaded, households.isEmpty {
                    Text("No households available.").foregroundStyle(HomeyColors.secondaryText)
                }
                if canManage {
                    Button("Invite Household", systemImage: "person.2.badge.plus") {
                        mutate {
                            let created = try await service.createInvite(tripID: trip.id)
                            guard isCurrentContext, canManage else { return }
                            invite = created
                        }
                    }
                    .disabled(isMutating)
                }
            }
            Section("People Going") {
                if canEditPeople {
                    Button("Edit People", systemImage: "person.crop.circle.badge.checkmark") { showsPicker = true }
                        .disabled(isMutating || isLoading)
                }
                ForEach(orderedHouseholds.filter(\.isAccepted)) { household in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(household.homeID == homeID ? "YOUR HOUSEHOLD" : (household.isOrganizer ? "ORGANIZER HOUSEHOLD" : "PARTICIPATING HOUSEHOLD"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyColors.secondaryText)
                        let going = participants.filter { $0.homeID == household.homeID }
                        if going.isEmpty {
                            Text("No people selected yet.")
                                .font(.subheadline)
                                .foregroundStyle(HomeyColors.secondaryText)
                        } else {
                            ForEach(going) { person in
                                HStack(spacing: 12) {
                                    TripPersonAvatar(name: person.name, url: person.avatarURL)
                                    Text(person.name)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay { if isLoading, !hasLoaded { ProgressView("Loading people…") } }
        .task(id: homeID) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsPicker) {
            TripParticipantPicker(tripID: trip.id, homeID: homeID) {
                await load()
            }
            .environmentObject(session)
        }
        .sheet(isPresented: Binding(get: { invite != nil }, set: { if !$0 { invite = nil } })) {
            if let invite {
                TripHouseholdInviteView(trip: trip, homeID: homeID, invite: invite)
                    .environmentObject(session)
            }
        }
        .confirmationDialog("Remove Household?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Household", role: .destructive) {
                guard let household = removal, canManage, !household.isOrganizer,
                      household.homeID != trip.organizerHomeID else { return }
                removal = nil
                mutate {
                    try await service.removeHousehold(tripID: trip.id, homeID: household.homeID)
                    guard isCurrentContext else { return }
                    await load()
                    await onUpdated()
                }
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: {
            Text("This household and its participant selections will be removed from the Trip.")
        }
        .onChange(of: session.activeHome?.id) { _, id in
            if id != homeID {
                mutationTask?.cancel()
                loadID = UUID()
                households = []
                participants = []
                invite = nil
                showsPicker = false
                removal = nil
            }
        }
        .onDisappear { mutationTask?.cancel() }
    }

    private var isCurrentContext: Bool { session.activeHome?.id == homeID && !session.isSwitchingHome && !Task.isCancelled }
    private var canManage: Bool {
        isCurrentContext && TripPermissions.canManageHouseholds(
            homeID: homeID, organizerHomeID: trip.organizerHomeID, role: session.activeRole, households: households
        )
    }
    private var canEditPeople: Bool {
        isCurrentContext && TripPermissions.canEdit(homeID: homeID, role: session.activeRole, households: households)
    }
    private var orderedHouseholds: [TripHousehold] {
        households.sorted {
            if $0.isOrganizer != $1.isOrganizer { return $0.isOrganizer }
            if ($0.homeID == homeID) != ($1.homeID == homeID) { return $0.homeID == homeID }
            return $0.homeID.uuidString < $1.homeID.uuidString
        }
    }
    private func householdName(_ household: TripHousehold) -> String {
        session.homes.homes.first { $0.id == household.homeID }?.name ??
            (household.isOrganizer ? "Organizer Household" : "Participating Household")
    }

    private func load() async {
        guard isCurrentContext else { return }
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        errorMessage = nil
        defer { if loadID == requestID { isLoading = false } }
        do {
            async let homes = service.households(tripID: trip.id)
            async let people = service.participants(tripID: trip.id)
            let result = try await (homes, people)
            guard isCurrentContext, loadID == requestID else { return }
            households = result.0
            participants = result.1
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            guard isCurrentContext, loadID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func mutate(_ operation: @escaping () async throws -> Void) {
        guard !isMutating, isCurrentContext else { return }
        isMutating = true
        errorMessage = nil
        mutationTask = Task { @MainActor in
            defer { isMutating = false }
            do {
                try Task.checkCancellation()
                guard canManage else { return }
                try await operation()
            } catch is CancellationError {
            } catch {
                guard isCurrentContext else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct TripPersonAvatar: View {
    let name: String
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HomeyColors.primary.opacity(0.12))
                    .foregroundStyle(HomeyColors.primary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .accessibilityLabel("Avatar for \(name)")
    }
}

private struct TripParticipantPicker: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    let homeID: UUID
    let onSaved: () async -> Void
    @State private var members: [HomeMemberDisplay] = []
    @State private var selection: Set<UUID> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?
    private let service = TripPeopleService()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    HomeyErrorView(message: errorMessage)
                    if !hasLoaded { Button("Try Again") { Task { await load() } } }
                }
                if isLoading { ProgressView("Loading members…") }
                ForEach(members) { member in
                    Button {
                        if selection.contains(member.userID) { selection.remove(member.userID) }
                        else { selection.insert(member.userID) }
                    } label: {
                        HStack(spacing: 12) {
                            HomeMemberAvatar(member: member, size: 40)
                            Text(member.displayName).foregroundStyle(HomeyColors.text)
                            Spacer()
                            Image(systemName: selection.contains(member.userID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(HomeyColors.primary)
                        }
                    }
                    .disabled(isSaving || isLoading)
                    .accessibilityAddTraits(selection.contains(member.userID) ? .isSelected : [])
                }
                Section {
                    Text("Choose who is going from your Home. You can leave everyone unselected.")
                        .font(.footnote).foregroundStyle(HomeyColors.secondaryText)
                }
            }
            .navigationTitle("Edit People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || isLoading || !hasLoaded || !canManagePeople)
                }
            }
        }
        .task { await load() }
        .onChange(of: canManagePeople) { _, allowed in
            if !allowed { saveTask?.cancel(); dismiss() }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: session.activeHome?.id) { _, id in
            if id != homeID { selection = []; saveTask?.cancel(); dismiss() }
        }
        .onDisappear { saveTask?.cancel() }
    }

    private var canManagePeople: Bool {
        session.activeHome?.id == homeID && session.activeRole?.canManageInvitations == true && !session.isSwitchingHome
    }

    private func load() async {
        guard canManagePeople, let userID = session.currentUser?.id else { return }
        isLoading = true
        hasLoaded = false
        errorMessage = nil
        defer { isLoading = false }
        await session.homes.loadMembers(homeID: homeID, currentUserID: userID, forceRefresh: true)
        guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
        guard session.homes.hasLoadedMembers(for: homeID), session.homes.membersErrorMessage == nil else {
            errorMessage = session.homes.membersErrorMessage ?? "Home members could not be loaded."
            return
        }
        do {
            let households = try await service.households(tripID: tripID)
            guard TripPermissions.canEdit(homeID: homeID, role: session.activeRole, households: households) else {
                throw TripPeopleError(message: "Your Home is no longer participating in this Trip.")
            }
            let people = try await service.participants(tripID: tripID)
            guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
            members = session.homes.membersForSelectedHome()
            let memberUserIDs = Set(members.map(\.userID))
            selection = Set(people.filter { $0.homeID == homeID }.map(\.userID)).intersection(memberUserIDs)
            hasLoaded = true
        } catch is CancellationError {
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        guard !isSaving, hasLoaded, !isLoading, canManagePeople else { return }
        isSaving = true
        errorMessage = nil
        let selectedUserIDs = selection
        saveTask = Task { @MainActor in
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                guard canManagePeople else { return }
                try await service.saveParticipants(tripID: tripID, homeID: homeID, userIDs: selectedUserIDs)
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                await onSaved()
                dismiss()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
