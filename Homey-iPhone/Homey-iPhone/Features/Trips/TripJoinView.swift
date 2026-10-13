import SwiftUI

struct TripJoinView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID
    let onJoined: (UUID, UUID) async -> Void

    @State private var code = ""
    @State private var preview: TripInvitePreview?
    @State private var selectedHomeID: UUID?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var workTask: Task<Void, Never>?
    @State private var joinedTripID: UUID?
    @State private var joinedHomeID: UUID?
    private let service = TripPeopleService()

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage { HomeyErrorView(message: errorMessage) }
                if joinedTripID != nil {
                    Section {
                        Label("Your household joined the Trip.", systemImage: "checkmark.circle.fill")
                        Button("Open Joined Home", action: openJoinedHome).disabled(isWorking)
                    }
                } else {
                    Section("Enter Trip Code") {
                        TextField("Trip Invite Code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: code) { _, _ in preview = nil }
                        Button("Preview Trip", action: loadPreview)
                            .disabled(isWorking || TripPeopleService.normalizedCode(code).isEmpty)
                    }
                    .disabled(isWorking)
                    if let preview {
                        Section("Trip Preview") {
                            Text(preview.title).font(.headline)
                            if let destination = preview.destinationName, !destination.isEmpty { Text(destination) }
                            if let dates = preview.dateRange { Text(dates) }
                            Text(preview.durationType.displayName)
                            Text(TripInviteDates.expiration(preview.expiresAt))
                                .foregroundStyle(HomeyColors.secondaryText)
                        }
                        Section("Join as") {
                            if eligibleHomes.isEmpty {
                                Text("A Home Owner or Admin can join a household to this Trip.")
                            } else {
                                Picker("Home", selection: $selectedHomeID) {
                                    Text("Choose a Home").tag(nil as UUID?)
                                    ForEach(eligibleHomes) { home in
                                        Text(home.name).tag(Optional(home.id))
                                    }
                                }
                                Button("Join Trip", action: accept)
                                    .disabled(isWorking || selectedHome == nil)
                            }
                        }
                        .disabled(isWorking)
                    }
                }
                if isWorking { ProgressView() }
            }
            .navigationTitle("Join Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joinedTripID == nil ? "Cancel" : "Done") { dismiss() }.disabled(isWorking)
                }
            }
        }
        .task {
            await session.refreshHomeChoices()
            guard session.activeHome?.id == homeID else { dismiss(); return }
            preselectHome()
        }
        .interactiveDismissDisabled(isWorking)
        .onChange(of: session.activeHome?.id) { _, id in
            if id != homeID, joinedTripID == nil {
                workTask?.cancel()
                code = ""
                preview = nil
                dismiss()
            }
        }
        .onDisappear {
            code = ""
            preview = nil
            if joinedTripID == nil { workTask?.cancel() }
        }
    }

    private var eligibleHomes: [HomeSummary] {
        session.homes.homes.filter { $0.role?.canManageInvitations == true }
    }
    private var selectedHome: HomeSummary? { eligibleHomes.first { $0.id == selectedHomeID } }
    private func preselectHome() {
        if eligibleHomes.count == 1 { selectedHomeID = eligibleHomes[0].id }
        else if eligibleHomes.contains(where: { $0.id == homeID }) { selectedHomeID = homeID }
    }

    private func loadPreview() {
        guard !isWorking, session.activeHome?.id == homeID, !session.isSwitchingHome else { return }
        let normalized = TripPeopleService.normalizedCode(code)
        guard !normalized.isEmpty else { return }
        code = normalized
        preview = nil
        isWorking = true
        errorMessage = nil
        workTask = Task { @MainActor in
            defer { isWorking = false }
            do {
                let result = try await service.preview(code: normalized)
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                preview = result
                preselectHome()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accept() {
        guard !isWorking, preview != nil, joinedTripID == nil,
              session.activeHome?.id == homeID, !session.isSwitchingHome,
              let selectedHome, let userID = session.currentUser?.id else { return }
        let normalized = TripPeopleService.normalizedCode(code)
        isWorking = true
        errorMessage = nil
        workTask = Task { @MainActor in
            defer { isWorking = false }
            do {
                // Revalidate the chosen membership without changing it or the active Home.
                let validated = try await session.homes.validatedHome(homeID: selectedHome.id, userID: userID)
                guard !Task.isCancelled, session.activeHome?.id == homeID,
                      validated.role?.canManageInvitations == true else { return }
                let tripID = try await service.accept(code: normalized, homeID: validated.id)
                // Acceptance is final even if refreshing or switching Homes later fails.
                joinedTripID = tripID
                joinedHomeID = validated.id
                code = ""
                preview = nil
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                await finishJoining(home: validated, tripID: tripID)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, session.activeHome?.id == homeID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openJoinedHome() {
        guard !isWorking, let id = joinedHomeID, let tripID = joinedTripID,
              let home = session.homes.homes.first(where: { $0.id == id }) else { return }
        isWorking = true
        workTask = Task { @MainActor in
            defer { isWorking = false }
            await finishJoining(home: home, tripID: tripID)
        }
    }

    private func finishJoining(home: HomeSummary, tripID: UUID) async {
        guard await session.switchHome(to: home) else {
            errorMessage = session.homeSwitchErrorMessage ?? "Your household joined. Open its Home to view the Trip."
            return
        }
        await onJoined(home.id, tripID)
        dismiss()
    }
}
