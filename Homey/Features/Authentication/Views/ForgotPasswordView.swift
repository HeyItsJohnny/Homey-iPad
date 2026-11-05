import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var recovery: PasswordRecoveryService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onBackToLogin: () -> Void

    @State private var email = ""
    @State private var successMessage: String?
    @FocusState private var focusedField: ForgotPasswordField?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            AuthenticationBackground()

            if isRegularWidth {
                regularLayout
            } else {
                compactLayout
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Layouts

    private var regularLayout: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 76) {
                AuthenticationHeroView(isCompact: false)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                AuthenticationFormCard {
                    forgotPasswordForm
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
        .scrollDismissesKeyboard(.interactively)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthenticationHeroView(isCompact: true)

                AuthenticationFormCard(isCompact: true) {
                    forgotPasswordForm
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Form

    private var forgotPasswordForm: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Forgot Password",
                subtitle: "Enter the email address associated with your Homey account and we'll send you a password reset email."
            )

            AuthenticationTextField(
                title: "Email",
                systemImage: "envelope",
                text: $email,
                focusedField: $focusedField,
                field: .email,
                keyboardType: .emailAddress,
                textContentType: .username,
                submitLabel: .go
            )

            if let errorMessage = recovery.requestError {
                AuthenticationErrorView(message: errorMessage)
            }

            Button {
                Task {
                    await resetPassword()
                }
            } label: {
                if recovery.isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Reset Password")
                }
            }
            .buttonStyle(HomeyPrimaryButtonStyle())
            .disabled(recovery.isSending)

            if successMessage != nil {
                AuthenticationSuccessView(
                    title: "Check your email",
                    message: "If an account exists for that email address, you’ll receive a password reset link. Open it on this iPad."
                )
                .transition(.opacity)
            }

            AuthenticationDividerWithText(text: "or")

            Button("Back to Login", action: onBackToLogin)
                .buttonStyle(AuthenticationSecondaryButtonStyle())
                .disabled(recovery.isSending)
        }
    }

    // MARK: - Actions

    private func resetPassword() async {
        successMessage = nil
        let didSend = await recovery.send(email: email)

        if didSend {
            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Password reset email sent."
            }
        }
    }
}

private enum ForgotPasswordField: Hashable {
    case email
}

#Preview("iPhone Forgot Password") {
    NavigationStack {
        ForgotPasswordView(onBackToLogin: {})
            .environmentObject(PasswordRecoveryService(auth: SupabasePasswordRecoveryAuth()))
    }
}

#Preview("iPad Forgot Password") {
    NavigationStack {
        ForgotPasswordView(onBackToLogin: {})
            .environmentObject(PasswordRecoveryService(auth: SupabasePasswordRecoveryAuth()))
    }
}
