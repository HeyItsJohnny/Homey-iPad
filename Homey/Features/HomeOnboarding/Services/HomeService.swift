import Combine
import Foundation
import Functions
import PostgREST
import Supabase

@MainActor
final class HomeService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var homes: [HomeSummary] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var pendingInvitations: [HomeInvitationDisplay] = []
    @Published private(set) var myPendingInvitations: [HomeInvitationDisplay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMembers = false
    @Published private(set) var isLoadingInvitations = false
    @Published private(set) var isLoadingMyInvitations = false
    @Published private(set) var isCreatingInvitation = false
    @Published private(set) var cancellingInvitationID: UUID?
    @Published private(set) var acceptingInvitationID: UUID?
    @Published private(set) var decliningInvitationID: UUID?
    @Published var selectedHomeID: UUID?
    @Published var errorMessage: String?
    @Published var membersErrorMessage: String?
    @Published var invitationsErrorMessage: String?
    @Published var myInvitationsErrorMessage: String?

    // MARK: - Private Properties

    @Published private(set) var isRedeemingInvitation = false
    @Published var joinErrorMessage: String?
    private let invitationFlow = HouseholdInvitationFlow()
    private let codeRedemption = HouseholdCodeRedemption()
    private var accountRevision = UUID()
    private let client = SupabaseManager.shared.client
    private var loadedMembersHomeID: UUID?
    private var loadingMembersHomeID: UUID?
    private var loadedInvitationsHomeID: UUID?
    private var loadedInvitationUserID: UUID?
    private var invitationRefreshRequested = false

    private func requireVerifiedAccount(expectedID: UUID? = nil) async throws {
        let session = try await client.auth.session
        let user = try await client.auth.user(jwt: session.accessToken)
        guard EmailVerification.permitsHomeAccess(sessionID: session.user.id, userID: user.id,
            email: user.email, emailConfirmed: user.emailConfirmedAt != nil,
            anonymous: user.isAnonymous, expired: session.isExpired),
            expectedID == nil || expectedID == user.id,
            client.auth.currentSession?.user.id == user.id else {
            throw HomeVerificationFailure.unverified
        }
    }

    // MARK: - Loading

    func loadHomes(for userID: UUID) async {
        guard !isLoading else {
            return
        }

        let revision = accountRevision
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await fetchHomes(for: userID)
            guard revision == accountRevision, client.auth.currentSession?.user.id == userID else { return }
            homes = fetched
            restoreOrSelectHome()
        } catch {
            guard revision == accountRevision else { return }
            homes = []
            setSelectedHomeID(nil)
            errorMessage = "Unable to load your Homes."

            #if DEBUG
            print("Failed to load Homes: \(error)")
            #endif
        }

        isLoading = false
    }

    func createHome(name: String, timezone: String, userID: UUID) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a Home name."
            return false
        }

        guard !trimmedTimezone.isEmpty else {
            errorMessage = "Enter a timezone."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try await requireVerifiedAccount(expectedID: userID)
            #if DEBUG
            print("Creating Home...")
            print("home_name: \(trimmedName)")
            print("home_timezone: \(trimmedTimezone)")
            #endif

            let createdHomeID: UUID = try await client
                .rpc(
                    "create_home",
                    params: CreateHomeRPCParameters(
                        homeName: trimmedName,
                        homeTimezone: trimmedTimezone
                    )
                )
                .execute()
                .value

            await CalendarService().ensureDefaultSystemCategories(homeId: createdHomeID)

            homes = try await fetchHomes(for: userID)
            setSelectedHomeID(createdHomeID)
            restoreOrSelectHome()
            isLoading = false
            return true
        } catch {
            errorMessage = "Unable to create Home."

            #if DEBUG
            print("Failed to create Home: \(error)")
            #endif

            isLoading = false
            return false
        }
    }

    func updateHomeSettings(homeID: UUID, name: String, timezone: String, weekStartsOn: Int, userID: UUID) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Home name is required."
            return false
        }

        guard !trimmedTimezone.isEmpty else {
            errorMessage = "Choose a timezone."
            return false
        }

        guard weekStartsOn == 1 || weekStartsOn == 2 else {
            errorMessage = "Choose Sunday or Monday as the week start."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try await client
                .from("homes")
                .update(
                    UpdateHomeSettingsParams(
                        name: trimmedName,
                        timezone: trimmedTimezone,
                        weekStartsOn: weekStartsOn
                    )
                )
                .eq("id", value: homeID.uuidString)
                .execute()

            homes = try await fetchHomes(for: userID)
            setSelectedHomeID(homeID)
            restoreOrSelectHome()
            isLoading = false
            return true
        } catch {
            errorMessage = homeErrorMessage(for: error)

            #if DEBUG
            print("Failed to update Home settings: \(error)")
            #endif

            isLoading = false
            return false
        }
    }

    func selectHome(id: UUID?) {
        setSelectedHomeID(id)
    }

    func restoreSelectedHome(from storedValue: String?) {
        setSelectedHomeID(storedValue.flatMap(UUID.init(uuidString:)))
        restoreOrSelectHome()
    }

    func selectedHome() -> HomeSummary? {
        guard let selectedHomeID else {
            return nil
        }

        return homes.first { $0.id == selectedHomeID }
    }

    func membersForSelectedHome() -> [HomeMemberDisplay] {
        guard loadedMembersHomeID == selectedHomeID else {
            return []
        }

        return members
    }

    func currentMembershipForSelectedHome() -> HomeMemberDisplay? {
        guard loadedMembersHomeID == selectedHomeID else {
            return nil
        }

        return members.first(where: { $0.isCurrentUser })
    }

    func currentMembershipForSelectedHome(currentUserID: UUID?) -> HomeMemberDisplay? {
        guard loadedMembersHomeID == selectedHomeID else {
            return nil
        }

        if let currentUserID {
            return members.first { $0.userId == currentUserID }
        }

        return currentMembershipForSelectedHome()
    }

    var selectedHomeRole: HomeMemberRole? {
        currentMembershipForSelectedHome()?.role ?? selectedHome()?.role
    }

    func selectedHomeRole(currentUserID: UUID?) -> HomeMemberRole? {
        currentMembershipForSelectedHome(currentUserID: currentUserID)?.role ?? selectedHome()?.role
    }

    var permissionResolutionState: PermissionResolutionState {
        permissionResolutionState(currentUserID: nil)
    }

    func permissionResolutionState(currentUser: UserProfile?) -> PermissionResolutionState {
        permissionResolutionState(currentUserID: currentUser?.id)
    }

    func permissionResolutionState(currentUserID: UUID?) -> PermissionResolutionState {
        guard let selectedHomeID else {
            return .unavailable
        }

        if let currentUserID,
           let currentMembership = currentMembershipForSelectedHome(currentUserID: currentUserID),
           currentMembership.homeId == selectedHomeID,
           currentMembership.userId == currentUserID {
            let permissions = HomePermissions(role: currentMembership.role)
            #if DEBUG
            if permissions == .restrictive {
                print("Warning: matching Home membership resolved restrictive meal permissions")
                print("authenticated_user_id: \(currentUserID.uuidString)")
                print("selected_home_id: \(selectedHomeID.uuidString)")
                print("current_membership_user_id: \(currentMembership.userId.uuidString)")
                print("current_membership_home_id: \(currentMembership.homeId.uuidString)")
                print("decoded_role: \(currentMembership.role.rawValue)")
            }
            #endif
            return .resolved(permissions)
        }

        if let selectedHome = selectedHome(),
           let role = selectedHome.role {
            return .resolved(HomePermissions(role: role))
        }

        if isLoadingMembers || loadingMembersHomeID == selectedHomeID {
            return .loading
        }

        if loadedMembersHomeID == selectedHomeID {
            return .unavailable
        }

        if selectedHome() != nil {
            return .loading
        }

        return .unavailable
    }

    var homePermissions: HomePermissions {
        permissionResolutionState.permissions
    }

    func homePermissions(currentUser: UserProfile?) -> HomePermissions {
        permissionResolutionState(currentUser: currentUser).permissions
    }

    func memberCountForSelectedHome() -> Int? {
        guard loadedMembersHomeID == selectedHomeID else {
            return nil
        }

        return members.count
    }

    func hasLoadedMembersForSelectedHome() -> Bool {
        loadedMembersHomeID == selectedHomeID
    }

    func loadMembers(for homeID: UUID, currentUser: UserProfile, forceRefresh: Bool = false) async {
        if isLoadingMembers && loadingMembersHomeID == homeID && !forceRefresh {
            return
        }

        if !forceRefresh && loadedMembersHomeID == homeID {
            return
        }

        isLoadingMembers = true
        loadingMembersHomeID = homeID
        membersErrorMessage = nil

        if loadedMembersHomeID != homeID {
            members = []
            loadedMembersHomeID = nil
        }

        #if DEBUG
        print("Resolving Home permissions")
        print("authenticated_user_id: \(currentUser.id.uuidString)")
        print("selected_home_id: \(selectedHomeID?.uuidString ?? "nil")")
        print("requested_members_home_id: \(homeID.uuidString)")
        #endif

        do {
            let loadedMembers = try await fetchMembers(for: homeID, currentUser: currentUser)

            guard loadingMembersHomeID == homeID, selectedHomeID == homeID else {
                #if DEBUG
                print("Ignoring stale Home members response")
                print("loaded_members_home_id: \(homeID.uuidString)")
                print("current_selected_home_id: \(selectedHomeID?.uuidString ?? "nil")")
                #endif
                return
            }

            members = loadedMembers
            loadedMembersHomeID = homeID

            #if DEBUG
            let currentMember = currentMembershipForSelectedHome()
            let resolvedRole = currentMember?.role ?? selectedHome()?.role
            let resolvedPermissions = HomePermissions(role: resolvedRole)
            print("loaded_members_home_id: \(homeID.uuidString)")
            print("current_membership_user_id: \(currentMember?.userId.uuidString ?? "nil")")
            print("current_membership_home_id: \(currentMember?.homeId.uuidString ?? "nil")")
            print("decoded_role: \(resolvedRole?.rawValue ?? "nil")")
            print("permission_loading_state: resolved")
            print("meals_can_create: \(resolvedPermissions.meals.canCreate)")
            print("meals_can_edit: \(resolvedPermissions.meals.canEdit)")
            #endif
        } catch {
            guard loadingMembersHomeID == homeID, selectedHomeID == homeID else {
                return
            }

            membersErrorMessage = homeErrorMessage(for: error)

            #if DEBUG
            print("Failed to load Home members via RPC get_home_members")
            print("target_home_id: \(homeID.uuidString)")
            print(String(reflecting: error))
            if let postgrestError = error as? PostgrestError {
                print("PostgREST code: \(postgrestError.code ?? "")")
                print("PostgREST message: \(postgrestError.message)")
                print("PostgREST detail: \(postgrestError.detail ?? "")")
                print("PostgREST hint: \(postgrestError.hint ?? "")")
            }
            #endif
        }

        if loadingMembersHomeID == homeID {
            loadingMembersHomeID = nil
        }
        if selectedHomeID == homeID {
            isLoadingMembers = false
        }
    }

    func refreshMembers(for homeID: UUID, currentUser: UserProfile) async {
        await loadMembers(for: homeID, currentUser: currentUser, forceRefresh: true)
    }

    func reorderMembers(
        homeID: UUID,
        membershipIDs: [UUID],
        currentUser: UserProfile
    ) async -> Bool {
        let currentMembers = membersForSelectedHome()
        let uniqueMembershipIDs = Set(membershipIDs)
        guard selectedHomeID == homeID,
              !membershipIDs.isEmpty,
              uniqueMembershipIDs.count == membershipIDs.count,
              membershipIDs.count == currentMembers.count,
              uniqueMembershipIDs == Set(currentMembers.map(\.membershipId)) else {
            #if DEBUG
            print("[Homey] MEMBER REORDER VALIDATION ERROR")
            print("requested_home_id: \(homeID.uuidString)")
            print("selected_home_id: \(selectedHomeID?.uuidString ?? "nil")")
            print("ordered_member_count: \(membershipIDs.count)")
            print("loaded_member_count: \(currentMembers.count)")
            print("unique_membership_id_count: \(uniqueMembershipIDs.count)")
            print("ordered membership ids: \(membershipIDs.map(\.uuidString))")
            print("loaded membership ids: \(currentMembers.map { $0.membershipId.uuidString })")
            #endif
            return false
        }

        membersErrorMessage = nil

        #if DEBUG
        print("[Homey] MEMBER REORDER REQUEST")
        print("home_id: \(homeID.uuidString)")
        print("members:")
        for (index, member) in currentMembers.enumerated() {
            print("\(index):")
            print("name: \(member.displayName)")
            print("membership_id: \(member.membershipId.uuidString)")
            print("user_id: \(member.userId.uuidString)")
        }
        print("ordered membership ids: \(membershipIDs.map(\.uuidString))")
        #endif

        do {
            try await client
                .rpc(
                    "reorder_home_members",
                    params: ReorderHomeMembersRPCParameters(
                        homeID: homeID,
                        membershipIDs: membershipIDs
                    )
                )
                .execute()
        } catch is CancellationError {
            return false
        } catch {
            membersErrorMessage = "Unable to save the member order."
            #if DEBUG
            print("[Homey] MEMBER REORDER ERROR")
            if let postgrestError = error as? PostgrestError {
                print("code: \(postgrestError.code ?? "nil")")
                print("detail: \(postgrestError.detail ?? "nil")")
                print("hint: \(postgrestError.hint ?? "nil")")
                print("message: \(postgrestError.message)")
            }
            print("raw error: \(String(reflecting: error))")
            #endif
            return false
        }

        guard selectedHomeID == homeID else { return false }

        let membersByID = Dictionary(uniqueKeysWithValues: currentMembers.map { ($0.membershipId, $0) })
        members = membershipIDs.compactMap { membersByID[$0] }
        loadedMembersHomeID = homeID

        // Persistence is complete once the RPC succeeds. A verification read
        // should refine local data, but a transient read failure must not make
        // the UI claim that the committed reorder was rolled back.
        if let reorderedMembers = try? await fetchMembers(for: homeID, currentUser: currentUser),
           selectedHomeID == homeID {
            members = reorderedMembers
            loadedMembersHomeID = homeID
        }

        return true
    }

    func invitationsForSelectedHome() -> [HomeInvitationDisplay] {
        guard loadedInvitationsHomeID == selectedHomeID else {
            return []
        }

        return pendingInvitations
    }

    func hasLoadedInvitationsForSelectedHome() -> Bool {
        loadedInvitationsHomeID == selectedHomeID
    }

    func loadPendingInvitations(for homeID: UUID, forceRefresh: Bool = false) async {
        guard !isLoadingInvitations else {
            if forceRefresh || homeID == selectedHomeID { invitationRefreshRequested = true }
            return
        }
        let revision = accountRevision

        if !forceRefresh && loadedInvitationsHomeID == homeID {
            return
        }

        isLoadingInvitations = true
        invitationsErrorMessage = nil

        if loadedInvitationsHomeID != homeID {
            pendingInvitations = []
        }

        do {
            let fetched = try await fetchPendingInvitations(for: homeID)
            guard revision == accountRevision else { return }
            if selectedHomeID == homeID {
                pendingInvitations = HomeInvitationDisplay.sorted(fetched)
                loadedInvitationsHomeID = homeID
            }
        } catch {
            guard revision == accountRevision else { return }
            if selectedHomeID == homeID { invitationsErrorMessage = "Couldn't load pending invitations. Please try again." }
        }

        isLoadingInvitations = false
        if invitationRefreshRequested, let currentHomeID = selectedHomeID {
            invitationRefreshRequested = false
            await loadPendingInvitations(for: currentHomeID, forceRefresh: true)
        }
    }

    func refreshPendingInvitations(for homeID: UUID) async {
        await loadPendingInvitations(for: homeID, forceRefresh: true)
    }

    func loadMyPendingInvitations(for userID: UUID, forceRefresh: Bool = false) async {
        guard !isLoadingMyInvitations else {
            return
        }

        if !forceRefresh && loadedInvitationUserID == userID {
            return
        }

        let revision = accountRevision
        isLoadingMyInvitations = true
        myInvitationsErrorMessage = nil

        if loadedInvitationUserID != userID {
            myPendingInvitations = []
        }

        do {
            try await requireVerifiedAccount(expectedID: userID)
            let fetched = try await fetchMyPendingInvitations()
            guard revision == accountRevision, client.auth.currentSession?.user.id == userID else { return }
            myPendingInvitations = HomeInvitationDisplay.sorted(fetched)
            loadedInvitationUserID = userID
        } catch {
            guard revision == accountRevision else { return }
            myInvitationsErrorMessage = "Couldn't load your invitations. Please try again."
        }

        isLoadingMyInvitations = false
    }

    func refreshMyPendingInvitations(for userID: UUID) async {
        await loadMyPendingInvitations(for: userID, forceRefresh: true)
    }

    func createInvitation(homeID: UUID, email: String, role: HomeMemberRole) async -> Bool {
        guard !isCreatingInvitation else { return false }
        guard let userID = client.auth.currentSession?.user.id else {
            invitationsErrorMessage = HouseholdInvitationFailure.backend("unauthorized").message
            return false
        }
        guard homeID == selectedHomeID, selectedHome() != nil else {
            invitationsErrorMessage = HouseholdInvitationFailure.backend("invalid_home_id").message
            return false
        }
        let revision = accountRevision
        isCreatingInvitation = true
        invitationsErrorMessage = nil
        defer { if revision == accountRevision { isCreatingInvitation = false } }
        do {
            try await requireVerifiedAccount(expectedID: userID)
            guard revision == accountRevision, homeID == selectedHomeID else { return false }
            return try await invitationFlow.send(userID: userID, homeID: homeID, email: email,
                role: role, senderRole: selectedHomeRole(currentUserID: userID), verified: true,
                invoke: { request in
                    do {
                        try await self.client.functions.invoke("homey-send-household-invitation",
                            options: FunctionInvokeOptions(body: request)) { data, _ in
                                try HouseholdInvitationFailure.validateResponse(data)
                            }
                    } catch let error as FunctionsError {
                        if case .httpError(_, let data) = error {
                            // This decoder only accepts explicit error codes; unknown bodies are uncertain.
                            do { try HouseholdInvitationFailure.validateResponse(data) }
                            catch { throw error }
                        }
                        throw HouseholdInvitationFailure.uncertain
                    } catch let error as HouseholdInvitationFailure { throw error }
                    catch { throw HouseholdInvitationFailure.uncertain }
                }, refresh: {
                    guard revision == self.accountRevision, self.client.auth.currentSession?.user.id == userID,
                          self.selectedHomeID == homeID else { return }
                    await self.refreshPendingInvitations(for: homeID)
                }) && revision == accountRevision && client.auth.currentSession?.user.id == userID && selectedHomeID == homeID
        } catch {
            guard revision == accountRevision else { return false }
            invitationsErrorMessage = error is HomeVerificationFailure
                ? HouseholdInvitationFailure.backend("unverified_email").message
                : (error as? HouseholdInvitationFailure ?? .uncertain).message
            return false
        }
    }

    func redeemInvitationCode(_ input: String, currentUserID: UUID) async -> Bool {
        guard !isRedeemingInvitation, acceptingInvitationID == nil else { return false }
        let code = HouseholdInvitationFlow.normalizedCode(input)
        guard HouseholdInvitationFlow.validCode(code) else {
            joinErrorMessage = code.isEmpty ? "Enter your invitation code." : "Enter the complete invitation code from your email."
            return false
        }
        let revision = accountRevision
        isRedeemingInvitation = true
        joinErrorMessage = nil
        defer { if revision == accountRevision { isRedeemingInvitation = false } }
        do {
            try await requireVerifiedAccount(expectedID: currentUserID)
            guard revision == accountRevision else { return false }
            let redeemed = try await codeRedemption.redeem(code, userID: currentUserID, verified: true,
                isCurrent: { revision == self.accountRevision && self.client.auth.currentSession?.user.id == currentUserID },
                invoke: { requestedCode in
                    try await self.client.rpc("redeem_home_invitation_code",
                        params: RedeemHomeInvitationParameters(requestedCode: requestedCode)).execute().value
                })
            if redeemed {
                myPendingInvitations = []
                loadedInvitationUserID = nil
            }
            return redeemed
        } catch {
            if revision == accountRevision { joinErrorMessage = HouseholdInvitationFailure.joinMessage(error) }
            return false
        }
    }

    func finishJoiningHome(currentUserID: UUID) async -> Bool {
        guard !isRedeemingInvitation else { return false }
        let revision = accountRevision
        isRedeemingInvitation = true
        defer { if revision == accountRevision { isRedeemingInvitation = false } }
        do {
            try await requireVerifiedAccount(expectedID: currentUserID)
            var refreshed: [HomeSummary] = []
            let finished = try await codeRedemption.finish(userID: currentUserID,
                isCurrent: { revision == self.accountRevision && self.client.auth.currentSession?.user.id == currentUserID },
                refresh: {
                    refreshed = try await self.fetchHomes(for: currentUserID)
                    return refreshed.map(\.id)
                }, navigate: { homeID in
                    self.homes = refreshed
                    self.setSelectedHomeID(homeID)
                })
            if finished { await refreshMyPendingInvitations(for: currentUserID) }
            return finished
        } catch {
            if revision == accountRevision { joinErrorMessage = "Couldn't refresh your Homes. Please try Continue again." }
            return false
        }
    }

    func cancelInvitation(_ invitation: HomeInvitationDisplay) async -> Bool {
        guard cancellingInvitationID == nil else {
            return false
        }

        cancellingInvitationID = invitation.id
        invitationsErrorMessage = nil

        do {
            try await client
                .rpc(
                    "cancel_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()

            await refreshPendingInvitations(for: invitation.homeID)
            cancellingInvitationID = nil
            return true
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)

            cancellingInvitationID = nil
            return false
        }
    }

    func acceptInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> AcceptedHomeInvitationResult? {
        guard acceptingInvitationID == nil, !isRedeemingInvitation else {
            return nil
        }

        let revision = accountRevision
        acceptingInvitationID = invitation.id
        myInvitationsErrorMessage = nil

        do {
            try await requireVerifiedAccount(expectedID: currentUserID)
            let acceptedHomeID: UUID = try await client
                .rpc(
                    "accept_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()
                .value

            guard revision == accountRevision, client.auth.currentSession?.user.id == currentUserID else { return nil }
            let result = AcceptedHomeInvitationResult(
                homeID: acceptedHomeID,
                homeName: invitation.homeName ?? "Home"
            )

            myPendingInvitations.removeAll { $0.id == invitation.id }
            await loadHomes(for: currentUserID)
            guard revision == accountRevision else { return nil }
            loadedInvitationUserID = nil
            await refreshMyPendingInvitations(for: currentUserID)
            acceptingInvitationID = nil
            return result
        } catch {
            guard revision == accountRevision else { return nil }
            myInvitationsErrorMessage = invitationErrorMessage(for: error)

            acceptingInvitationID = nil
            return nil
        }
    }

    func declineInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> Bool {
        guard decliningInvitationID == nil else {
            return false
        }

        decliningInvitationID = invitation.id
        myInvitationsErrorMessage = nil

        do {
            try await client
                .rpc(
                    "decline_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()

            myPendingInvitations.removeAll { $0.id == invitation.id }
            loadedInvitationUserID = nil
            await refreshMyPendingInvitations(for: currentUserID)
            decliningInvitationID = nil
            return true
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)

            decliningInvitationID = nil
            return false
        }
    }

    func clearAuthenticatedState() {
        accountRevision = UUID()
        invitationRefreshRequested = false
        codeRedemption.reset()
        isRedeemingInvitation = false
        joinErrorMessage = nil
        homes = []
        members = []
        pendingInvitations = []
        myPendingInvitations = []
        isLoading = false
        isLoadingMembers = false
        isLoadingInvitations = false
        isLoadingMyInvitations = false
        isCreatingInvitation = false
        cancellingInvitationID = nil
        acceptingInvitationID = nil
        decliningInvitationID = nil
        selectedHomeID = nil
        errorMessage = nil
        membersErrorMessage = nil
        invitationsErrorMessage = nil
        myInvitationsErrorMessage = nil
        loadedMembersHomeID = nil
        loadedInvitationsHomeID = nil
        loadedInvitationUserID = nil
    }

    // MARK: - Private Helpers

    private func fetchHomes(for userID: UUID) async throws -> [HomeSummary] {
        let memberships: [HomeMembershipResponse] = try await client
            .from("home_members")
            .select("role, homes(id, name, timezone, week_starts_on, created_at)")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        var summaries: [HomeSummary] = []

        for membership in memberships {
            guard let home = membership.home else {
                continue
            }

            let memberCount = try await loadMemberCount(homeID: home.id)
            summaries.append(
                HomeSummary(
                    id: home.id,
                    name: home.name,
                    timezone: home.timezone,
                    role: membership.role,
                    createdAt: home.createdAt,
                    memberCount: memberCount,
                    weekStartsOn: home.weekStartsOn
                )
            )
        }

        return summaries
    }

    private func loadMemberCount(homeID: UUID) async throws -> Int {
        let members: [HomeMemberResponse] = try await client
            .from("home_members")
            .select("id")
            .eq("home_id", value: homeID.uuidString)
            .execute()
            .value

        return members.count
    }

    private func fetchMembers(for homeID: UUID, currentUser: UserProfile) async throws -> [HomeMemberDisplay] {
        let responses: [HomeMemberListResponse] = try await client
            .rpc(
                "get_home_members",
                params: GetHomeMembersParameters(targetHomeId: homeID)
            )
            .execute()
            .value

        return responses.map { response in
            HomeMemberDisplay(
                id: response.membershipID,
                homeId: response.homeID,
                userId: response.userID,
                role: response.role,
                joinedAt: response.joinedAt,
                displayOrder: response.displayOrder,
                firstName: response.firstName,
                lastName: response.lastName,
                profileDisplayName: response.displayName,
                email: response.email,
                avatarURL: response.avatarURL,
                isCurrentUser: response.userID == currentUser.id
            )
        }
    }

    private func fetchPendingInvitations(for homeID: UUID) async throws -> [HomeInvitationDisplay] {
        let responses: [HomeInvitationResponse] = try await client
            .from("home_invitations")
            .select("id, home_id, email, role, status, invited_by, created_at, expires_at")
            .eq("home_id", value: homeID.uuidString)
            .eq("status", value: HomeInvitationStatus.pending.rawValue)
            .execute()
            .value

        return responses.map { response in
            HomeInvitationDisplay(
                id: response.id,
                homeID: response.homeID,
                email: response.email,
                role: response.role,
                status: response.status,
                invitedBy: response.invitedBy,
                createdAt: response.createdAt,
                expiresAt: response.expiresAt
            )
        }
    }

    private func fetchMyPendingInvitations() async throws -> [HomeInvitationDisplay] {
        let responses: [MyHomeInvitationResponse] = try await client
            .rpc("get_my_pending_home_invitations")
            .execute()
            .value

        return responses.map { response in
            HomeInvitationDisplay(
                id: response.invitationID,
                homeID: response.homeID,
                email: response.email,
                role: response.role,
                status: response.status,
                invitedBy: response.invitedBy,
                createdAt: response.createdAt,
                expiresAt: response.expiresAt,
                homeName: response.homeName,
                inviterDisplayName: response.inviterName
            )
        }
    }

    private func homeErrorMessage(for error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.message
        }

        return error.localizedDescription
    }

    private func invitationErrorMessage(for error: Error) -> String {
        HouseholdInvitationFailure.joinMessage(error)
    }

    private func restoreOrSelectHome(preferredHomeName: String? = nil) {
        guard !homes.isEmpty else {
            setSelectedHomeID(nil)
            return
        }

        if let selectedHomeID, homes.contains(where: { $0.id == selectedHomeID }) {
            return
        }

        if let preferredHomeName,
           let preferredHome = homes.first(where: { $0.name == preferredHomeName }) {
            setSelectedHomeID(preferredHome.id)
        } else {
            setSelectedHomeID(homes[0].id)
        }
    }

    private func setSelectedHomeID(_ id: UUID?) {
        guard selectedHomeID != id else {
            return
        }

        selectedHomeID = id
        members = []
        loadedMembersHomeID = nil
        loadingMembersHomeID = nil
        isLoadingMembers = false
        membersErrorMessage = nil
        pendingInvitations = []
        loadedInvitationsHomeID = nil
        invitationsErrorMessage = nil
    }
}

private struct CreateHomeRPCParameters: Encodable {
    let homeName: String
    let homeTimezone: String

    enum CodingKeys: String, CodingKey {
        case homeName = "home_name"
        case homeTimezone = "home_timezone"
    }
}

private struct UpdateHomeSettingsParams: Encodable {
    let name: String
    let timezone: String
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case name
        case timezone
        case weekStartsOn = "week_starts_on"
    }
}

private struct GetHomeMembersParameters: Encodable {
    let targetHomeId: UUID

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
    }
}

private struct RedeemHomeInvitationParameters: Encodable {
    let requestedCode: String
    enum CodingKeys: String, CodingKey { case requestedCode = "requested_code" }
}

struct AcceptedHomeInvitationResult: Hashable {
    let homeID: UUID
    let homeName: String
}

private struct InvitationIdRPCParameters: Encodable {
    let targetInvitationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetInvitationID = "target_invitation_id"
    }
}

private struct HomeMembershipResponse: Decodable {
    let role: HomeMemberRole?
    let home: HomeResponse?

    enum CodingKeys: String, CodingKey {
        case role
        case home = "homes"
    }
}

private struct HomeResponse: Decodable {
    let id: UUID
    let name: String
    let timezone: String?
    let createdAt: String?
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case timezone
        case createdAt = "created_at"
        case weekStartsOn = "week_starts_on"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        weekStartsOn = try container.decodeIfPresent(Int.self, forKey: .weekStartsOn) ?? 1
    }
}

private struct HomeMemberResponse: Decodable {
    let id: UUID
}

private struct HomeMemberListResponse: Decodable {
    let membershipID: UUID
    let homeID: UUID
    let userID: UUID
    let role: HomeMemberRole
    let joinedAt: String?
    let displayOrder: Int
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let email: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case membershipID = "membership_id"
        case homeID = "home_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
        case displayOrder = "display_order"
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case email
        case avatarURL = "avatar_url"
    }
}

private struct ReorderHomeMembersRPCParameters: Encodable {
    let homeID: UUID
    let membershipIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case membershipIDs = "requested_membership_ids"
    }
}

private struct HomeInvitationResponse: Decodable {
    let id: UUID
    let homeID: UUID
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID?
    let createdAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case email
        case role
        case status
        case invitedBy = "invited_by"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private struct MyHomeInvitationResponse: Decodable {
    let invitationID: UUID
    let homeID: UUID
    let homeName: String
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID
    let inviterName: String
    let createdAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case homeID = "home_id"
        case homeName = "home_name"
        case email
        case role
        case status
        case invitedBy = "invited_by"
        case inviterName = "inviter_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private enum HomeVerificationFailure: Error { case unverified }
