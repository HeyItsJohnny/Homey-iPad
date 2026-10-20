import SwiftUI

struct HomeInvitationOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var homeService: HomeService

    @State private var isShowingInvitations = false
    @State private var isShowingCreateHome = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var invitationCount: Int {
        homeService.myPendingInvitations.count
    }

    private var primaryInvitation: HomeInvitationDisplay? {
        homeService.myPendingInvitations.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthenticationBackground()

                if isRegularWidth {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .navigationDestination(isPresented: $isShowingInvitations) {
                HomeInvitationsView {
                    isShowingInvitations = false
                }
            }
            .navigationDestination(isPresented: $isShowingCreateHome) {
                CreateHomeView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var regularLayout: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 76) {
                AuthenticationHeroView(isCompact: false)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                AuthenticationFormCard {
                    invitationChoiceCard
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 1400)
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 720)
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthenticationHeroView(isCompact: true)

                AuthenticationFormCard(isCompact: true) {
                    invitationChoiceCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var invitationChoiceCard: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Welcome to Homey",
                subtitle: invitationSubtitle
            )

            if let primaryInvitation {
                VStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HomeyTheme.primary)
                        .frame(width: 56, height: 56)
                        .background(HomeyTheme.primarySoft, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))

                    Text(primaryInvitation.homeName ?? "A Homey Home")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Role: \(primaryInvitation.formattedRole)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textSecondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(HomeyTheme.primarySoft.opacity(0.55), in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
            }

            Button {
                isShowingInvitations = true
            } label: {
                Text(invitationCount == 1 ? "View Invitation" : "View Invitations")
            }
            .buttonStyle(HomeyPrimaryButtonStyle())

            Button {
                isShowingCreateHome = true
            } label: {
                Text("Create My Own Home")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
            }
        }
    }

    private var invitationSubtitle: String {
        if invitationCount == 1 {
            return "You have been invited to join a home."
        }

        return "You have been invited to join \(invitationCount) homes."
    }
}

#Preview("Home Invitation Onboarding") {
    HomeInvitationOnboardingView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
