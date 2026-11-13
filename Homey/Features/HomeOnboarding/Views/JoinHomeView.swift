import SwiftUI

struct JoinHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @State private var code = ""
    @State private var joined = false
    @State private var validationMessage: String?
    var onJoined: () -> Void = {}

    var body: some View {
        ZStack {
            AuthenticationBackground()
            ScrollView {
                if authenticationService.authenticationState == .emailVerificationRequired {
                    VerifyEmailView(onBackToLogin: {})
                } else if joined {
                    InvitationSuccessCard(title: "Welcome Home!",
                        message: "You've successfully joined your Homey household.",
                        buttonTitle: "Continue", isBusy: homeService.isRedeemingInvitation,
                        errorMessage: homeService.joinErrorMessage) {
                            Task {
                                guard let id = authenticationService.currentUser?.id else { return }
                                if await homeService.finishJoiningHome(currentUserID: id) {
                                    onJoined()
                                    dismiss()
                                }
                            }
                        }
                } else {
                    AuthenticationFormCard {
                        VStack(alignment: .leading, spacing: 20) {
                            AuthenticationFormHeader(title: "Join a Home",
                                subtitle: "Have an invitation code? Enter it below to join your Homey household.")
                            Text("Invitation Code").font(.headline)
                            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.go)
                                .padding(16)
                                .background(HomeyTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button))
                                .accessibilityLabel("Invitation Code")
                                .onChange(of: code) { _, value in
                                    code = value.uppercased()
                                    validationMessage = nil
                                }
                                .onSubmit { Task { await join() } }
                                .disabled(homeService.isRedeemingInvitation)
                            if let message = validationMessage ?? homeService.joinErrorMessage {
                                AuthenticationErrorView(message: message)
                            }
                            Button { Task { await join() } } label: {
                                if homeService.isRedeemingInvitation { ProgressView().tint(.white) }
                                else { Text("Join Home") }
                            }
                            .buttonStyle(HomeyPrimaryButtonStyle())
                            .disabled(homeService.isRedeemingInvitation)
                            Button("Back") { dismiss() }
                                .buttonStyle(AuthenticationSecondaryButtonStyle())
                                .disabled(homeService.isRedeemingInvitation)
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.center)
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(homeService.isRedeemingInvitation)
        .onAppear { homeService.joinErrorMessage = nil }
    }

    private func join() async {
        guard authenticationService.authenticationState == .authenticated,
              let id = authenticationService.currentUser?.id else {
            validationMessage = "Verify your email address before joining a Home."
            return
        }
        joined = await homeService.redeemInvitationCode(code, currentUserID: id)
        if joined { code = "" }
    }
}

struct InvitationSuccessCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    var isBusy = false
    var errorMessage: String?
    let action: () -> Void

    var body: some View {
        AuthenticationFormCard {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(HomeyTheme.primary)
                        .accessibilityHidden(true)
                    Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(message).font(.body).foregroundStyle(HomeyTheme.textSecondary)
                    if let errorMessage { AuthenticationErrorView(message: errorMessage) }
                    Button(action: action) {
                        if isBusy { ProgressView().tint(.white) }
                        else { Text(buttonTitle) }
                    }
                    .buttonStyle(HomeyPrimaryButtonStyle())
                    .disabled(isBusy)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
    }
}
