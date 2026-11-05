import Auth
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var passwordRecovery: PasswordRecoveryService
    @EnvironmentObject private var deviceUnlock: DeviceUnlockService
    @EnvironmentObject private var homeService: HomeService
    @AppStorage("selectedHomeID") private var storedSelectedHomeID = ""

    @State private var loadedHomeUserID: UUID?

    var body: some View {
        Group {
            if passwordRecovery.state.isPresented {
                ResetPasswordView()
            } else {
                normalContent
            }
        }
        .background {
            PrivacySnapshotShield(deviceUnlock: deviceUnlock)
                .frame(width: 0, height: 0)
        }
        .task {
            await authenticationService.restoreSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, authenticationService.authenticationState == .emailVerificationRequired,
               authenticationService.session != nil {
                Task { await authenticationService.restoreSession() }
            }
        }
        .onChange(of: homeService.selectedHomeID) { _, selectedHomeID in
            storedSelectedHomeID = selectedHomeID?.uuidString ?? ""
        }
        .onChange(of: authenticationService.authenticationState) { _, state in
            if state == .unauthenticated || state == .emailVerificationRequired || state == .profileInitializationRequired {
                loadedHomeUserID = nil
                storedSelectedHomeID = ""
                homeService.clearAuthenticatedState()
            }
        }
    }

    @ViewBuilder
    private var normalContent: some View {
        switch authenticationService.authenticationState {
        case .loading:
            ProgressView()
        case .unauthenticated:
            AuthenticationView()
        case .emailVerificationRequired:
            NavigationStack {
                VerifyEmailView(onBackToLogin: {})
            }
        case .profileInitializationRequired:
            ZStack {
                AuthenticationBackground()
                VStack(spacing: 24) {
                    Text("Finish Setting Up Your Account").font(.title.bold())
                    Text(authenticationService.errorMessage ?? "We couldn't load your profile. Please try again.")
                    Button("Try Again") {
                        Task { await authenticationService.retryAccountInitialization() }
                    }
                    .buttonStyle(HomeyPrimaryButtonStyle())
                    Button("Back to Log In") {
                        Task { await authenticationService.signOut(scope: .local) }
                    }
                    .buttonStyle(AuthenticationSecondaryButtonStyle())
                }
                .disabled(authenticationService.isLoading)
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: 560)
            }
        case .authenticated:
            if deviceUnlock.isEnabled && deviceUnlock.isLocked {
                DeviceUnlockView()
            } else {
                authenticatedContent
            }
        }
    }

    private var authenticatedContent: some View {
        Group {
            if homeService.isLoading || loadedHomeUserID != authenticationService.currentUser?.id {
                ProgressView()
            } else if homeService.homes.isEmpty && !homeService.myPendingInvitations.isEmpty {
                HomeInvitationOnboardingView()
            } else if homeService.homes.isEmpty {
                HomeOnboardingView()
            } else {
                HomeyMainView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Keep household onboarding/invitations uninterrupted. This offer is
            // separate from the dashboard and never starts native UI automatically.
            if authenticationService.shouldOfferPasskeySetup,
               !homeService.isLoading,
               loadedHomeUserID == authenticationService.currentUser?.id,
               homeService.selectedHomeID != nil,
               !homeService.homes.isEmpty {
                PasskeySetupOfferView()
            }
        }
        .task(id: authenticationService.currentUser?.id) {
            await loadHomesForAuthenticatedUser()
        }
    }

    private func loadHomesForAuthenticatedUser() async {
        guard authenticationService.authenticationState == .authenticated,
              let userID = authenticationService.currentUser?.id else {
            return
        }

        loadedHomeUserID = nil
        homeService.restoreSelectedHome(from: storedSelectedHomeID)
        await homeService.loadHomes(for: userID)
        await homeService.loadMyPendingInvitations(for: userID)
        guard !Task.isCancelled, authenticationService.authenticationState == .authenticated,
              authenticationService.currentUser?.id == userID else { return }
        storedSelectedHomeID = homeService.selectedHomeID?.uuidString ?? ""
        loadedHomeUserID = userID
    }
}
