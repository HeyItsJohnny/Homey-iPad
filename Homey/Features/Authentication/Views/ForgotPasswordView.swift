import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var recovery: PasswordRecoveryService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onBackToLogin: () -> Void

    @State private var email = ""
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
                title: "Forgot Your Password?",
                subtitle: "Enter your email address and we'll help you reset your password."
            )

            AuthenticationTextField(
                title: "Email Address",
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

            AuthenticationDividerWithText(text: "or")

            Button("Back to Login", action: onBackToLogin)
                .buttonStyle(AuthenticationSecondaryButtonStyle())
                .disabled(recovery.isSending)
        }
    }

    // MARK: - Actions

    private func resetPassword() async {
        focusedField = nil
        // The root presents ResetPasswordView as soon as the request succeeds.
        _ = await recovery.send(email: email)
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
