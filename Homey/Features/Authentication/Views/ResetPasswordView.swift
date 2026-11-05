import Auth
import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var recovery: PasswordRecoveryService
    @EnvironmentObject private var authentication: AuthenticationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showPassword = false
    @State private var showConfirmation = false
    @State private var isFinishing = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case password, confirmation }

    var body: some View {
        ZStack {
            AuthenticationBackground()
            ScrollView {
                HStack(spacing: 76) {
                    if horizontalSizeClass == .regular {
                        AuthenticationHeroView(isCompact: false)
                            .frame(maxWidth: 600)
                    }
                    AuthenticationFormCard(isCompact: horizontalSizeClass != .regular) {
                        form
                    }
                    .frame(maxWidth: 520)
                }
                .frame(maxWidth: 1400)
                .padding(.horizontal, horizontalSizeClass == .regular ? 56 : 22)
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onDisappear { clearPasswords() }
        .onChange(of: recovery.state) { _, state in
            if state == .invalidLink || state == .success { clearPasswords() }
        }
    }

    private var form: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(title: "Reset Your Password", subtitle: "Enter your new password below.")
            switch recovery.state {
            case .idle, .exchanging:
                ProgressView("Checking your reset link…")
            case .invalidLink:
                AuthenticationErrorView(message: "This reset link is invalid, expired, or already used. Request a new link from Forgot Password and open it on the same iPad.")
                Button("Continue") { Task { await recovery.dismiss() } }
                    .buttonStyle(HomeyPrimaryButtonStyle())
            case .success:
                AuthenticationSuccessView(title: "Password updated", message: "Your new password is ready. Sign in to Homey to continue.")
                Button {
                    isFinishing = true
                    Task {
                        await authentication.signOut(scope: .local)
                        await recovery.dismiss()
                        isFinishing = false
                    }
                } label: {
                    if isFinishing { ProgressView().tint(.white) }
                    else { Text("Back to Login") }
                }
                .buttonStyle(HomeyPrimaryButtonStyle())
                .disabled(isFinishing || authentication.isLoading || authentication.isPasskeyOperationInProgress)
            case .ready, .updating:
                passwordFields
                if let message = recovery.errorMessage { AuthenticationErrorView(message: message) }
                Button {
                    focusedField = nil
                    Task {
                        if await recovery.update(password: password, confirmation: confirmation) {
                            clearPasswords()
                        }
                    }
                } label: {
                    if recovery.state == .updating { ProgressView().tint(.white) }
                    else { Text("Update Password") }
                }
                .buttonStyle(HomeyPrimaryButtonStyle())
                .disabled(recovery.state.isBusy)
                Button("Cancel") {
                    clearPasswords()
                    Task { await recovery.dismiss() }
                }
                .buttonStyle(AuthenticationSecondaryButtonStyle())
                .disabled(recovery.state.isBusy)
            }
        }
    }

    private var passwordFields: some View {
        VStack(spacing: 16) {
            AuthenticationSecureField(title: "New Password", text: $password,
                isPasswordVisible: $showPassword, focusedField: $focusedField,
                field: .password, textContentType: .newPassword, submitLabel: .next)
            AuthenticationSecureField(title: "Confirm New Password", text: $confirmation,
                isPasswordVisible: $showConfirmation, focusedField: $focusedField,
                field: .confirmation, textContentType: .newPassword, submitLabel: .done)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(recovery.state.isBusy)
    }

    private func clearPasswords() {
        password = ""
        confirmation = ""
        showPassword = false
        showConfirmation = false
    }
}
