import SwiftUI

struct HomeInvitationsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}
    var onSwitchHome: () -> Void = {}

    @State private var invitationToDecline: HomeInvitationDisplay?
    @State private var isShowingDeclineConfirmation = false
    @State private var joinedHome: AcceptedHomeInvitationResult?
    @State private var isShowingSwitchPrompt = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var invitations: [HomeInvitationDisplay] {
        homeService.myPendingInvitations
    }

    var body: some View {
        ZStack {
            HomeyTheme.backgroundPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if homeService.isLoadingMyInvitations && invitations.isEmpty {
                        loadingCard
                    } else if let error = homeService.myInvitationsErrorMessage, invitations.isEmpty {
                        errorCard(message: error)
                    } else if invitations.isEmpty {
                        emptyCard
                    } else {
                        invitationsList
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshInvitations()
            }
        }
        .task(id: authenticationService.currentUser?.id) {
            await loadInvitations()
        }
        .confirmationDialog(
            "Decline Invitation?",
            isPresented: $isShowingDeclineConfirmation,
            titleVisibility: .visible,
            presenting: invitationToDecline
        ) { invitation in
            Button("Keep Invitation", role: .cancel) {
                invitationToDecline = nil
            }
            Button("Decline Invitation", role: .destructive) {
                Task {
                    await decline(invitation)
                }
            }
        } message: { _ in
            Text("You will not be added to this home.")
        }
        .confirmationDialog(
            "Welcome to \(joinedHome?.homeName ?? "Home")",
            isPresented: $isShowingSwitchPrompt,
            titleVisibility: .visible
        ) {
            Button("Not Now", role: .cancel) {
                joinedHome = nil
                onClose()
            }
            Button("Switch Home") {
                if let joinedHome {
                    homeService.selectHome(id: joinedHome.homeID)
                }
                joinedHome = nil
                onSwitchHome()
            }
        } message: {
            Text("You are now a member of this home. Would you like to switch to it now?")
        }
        .alert("Home Invitation Error", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Home Invitations")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    if !invitations.isEmpty {
                        Text("\(invitations.count) Pending")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(HomeyTheme.primarySoft, in: Capsule())
                    }
                }

                Text("You have been invited to join a home.")
                    .font(.title3)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.primary)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyTheme.surfacePrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var invitationsList: some View {
        VStack(spacing: 16) {
            ForEach(invitations) { invitation in
                HomeInvitationCard(
                    invitation: invitation,
                    isAccepting: homeService.acceptingInvitationID == invitation.id,
                    isDeclining: homeService.decliningInvitationID == invitation.id,
                    onAccept: {
                        Task {
                            await accept(invitation)
                        }
                    },
                    onDecline: {
                        invitationToDecline = invitation
                        isShowingDeclineConfirmation = true
                    }
                )
            }
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(HomeyTheme.primary)
                .accessibilityLabel("Loading Home invitations")

            Text("Loading invitations...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(HomeyTheme.primary)

            Text("No Pending Invitations")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text("Invitations to join another home will appear here.")
                .font(.body)
                .foregroundStyle(HomeyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(34)
        .frame(maxWidth: .infinity, minHeight: 240)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .accessibilityElement(children: .combine)
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(HomeyTheme.danger)

            Text("Unable to Load Invitations")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text(message)
                .font(.body)
                .foregroundStyle(HomeyTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await refreshInvitations()
                }
            } label: {
                Text("Try Again")
            }
            .buttonStyle(HomeyPrimaryButtonStyle())
            .frame(maxWidth: 260)
        }
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 260)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private func loadInvitations() async {
        guard let userID = authenticationService.currentUser?.id else {
            return
        }

        await homeService.loadMyPendingInvitations(for: userID)
    }

    private func refreshInvitations() async {
        guard let userID = authenticationService.currentUser?.id else {
            return
        }

        await homeService.refreshMyPendingInvitations(for: userID)
    }

    private func accept(_ invitation: HomeInvitationDisplay) async {
        guard let userID = authenticationService.currentUser?.id else {
            showError("Please sign in and try again.")
            return
        }

        let hadActiveHome = homeService.selectedHomeID != nil

        guard let result = await homeService.acceptInvitation(invitation, currentUserID: userID) else {
            showError(homeService.myInvitationsErrorMessage ?? "We couldn’t accept this invitation. Please try again.")
            return
        }

        if hadActiveHome {
            joinedHome = result
            isShowingSwitchPrompt = true
        } else {
            homeService.selectHome(id: result.homeID)
        }
    }

    private func decline(_ invitation: HomeInvitationDisplay) async {
        guard let userID = authenticationService.currentUser?.id else {
            showError("Please sign in and try again.")
            return
        }

        let didDecline = await homeService.declineInvitation(invitation, currentUserID: userID)

        if didDecline {
            invitationToDecline = nil
        } else {
            showError(homeService.myInvitationsErrorMessage ?? "We couldn’t decline this invitation. Please try again.")
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

struct HomeInvitationCard: View {
    let invitation: HomeInvitationDisplay
    let isAccepting: Bool
    let isDeclining: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var isBusy: Bool {
        isAccepting || isDeclining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                        .fill(HomeyTheme.primarySoft)
                        .frame(width: 62, height: 62)

                    Image(systemName: "house.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HomeyTheme.primary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("You’re Invited")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.primary)

                    Text(invitation.homeName ?? "A Homey Home")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyTheme.textPrimary)

                    Text(inviterText)
                        .font(.subheadline)
                        .foregroundStyle(HomeyTheme.textSecondary)
                }

                Spacer()

                Text(invitation.formattedRole)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HomeyTheme.primarySoft, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(invitation.invitedDateText)
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)

                if let expirationText = invitation.expirationText {
                    Text(expirationText)
                        .font(.subheadline)
                        .foregroundStyle(HomeyTheme.textSecondary)
                }
            }

            HStack(spacing: 12) {
                Button(action: onDecline) {
                    if isDeclining {
                        ProgressView()
                            .tint(HomeyTheme.danger)
                    } else {
                        Text("Decline")
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyTheme.danger)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
                .disabled(isBusy)
                .buttonStyle(.plain)

                Button(action: onAccept) {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Accept Invitation")
                    }
                }
                .buttonStyle(HomeyPrimaryButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding(26)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Invitation to join \(invitation.homeName ?? "a Home"), role \(invitation.formattedRole)")
    }

    private var inviterText: String {
        if let inviterDisplayName = invitation.inviterDisplayName, !inviterDisplayName.isEmpty {
            return "\(inviterDisplayName) invited you to join this home."
        }

        return "You have been invited to join this home."
    }
}

#Preview("Home Invitations") {
    HomeInvitationsView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}

#Preview("Home Invitation Card") {
    HomeInvitationCard(
        invitation: HomeInvitationDisplay(
            id: UUID(),
            homeID: UUID(),
            email: "nancy@example.com",
            role: .member,
            status: .pending,
            invitedBy: UUID(),
            createdAt: "2026-07-26T12:00:00Z",
            expiresAt: nil,
            homeName: "Laroco Home",
            inviterDisplayName: "Johnny Laroco"
        ),
        isAccepting: false,
        isDeclining: false,
        onAccept: {},
        onDecline: {}
    )
    .padding()
    .background(HomeyTheme.backgroundPrimary)
}
