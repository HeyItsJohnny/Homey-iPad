import Auth
import SwiftUI

struct VerifyEmailView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    let onBackToLogin: () -> Void

    var body: some View {
        VerificationContent(verification: authenticationService.verification, onBackToLogin: onBackToLogin)
    }
}

private struct VerificationContent: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @ObservedObject var verification: EmailVerificationService
    let onBackToLogin: () -> Void

    var body: some View {
        ZStack {
            AuthenticationBackground()
            ScrollView {
                AuthenticationFormCard {
                    VStack(spacing: 24) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.largeTitle)
                            .foregroundStyle(HomeyTheme.primary)
                            .accessibilityHidden(true)
                        Text("Verify Your Email")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 10) {
                            Text("We've sent a verification link to:")
                            Text(verification.pending?.email ?? authenticationService.session?.user.email ?? "your email address")
                                .font(.headline)
                                .textSelection(.enabled)
                            Text("Check your inbox and tap the link to verify your email address.")
                        }
                        Label("Waiting for email verification", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if authenticationService.isLoading || verification.isBusy {
                            ProgressView("Checking your account…")
                        }
                        if let message = verification.message {
                            Text(message).foregroundStyle(HomeyTheme.primary)
                                .accessibilityLabel("Success. \(message)")
                        }
                        if let error = verification.errorMessage ?? authenticationService.errorMessage {
                            AuthenticationErrorView(message: error)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = verification.pending?.remainingSeconds(at: context.date) ?? 0
                            Button {
                                Task { await authenticationService.resendVerificationEmail() }
                            } label: {
                                Text(seconds > 0 ? "Resend in \(seconds)s" : "Resend Verification Email")
                            }
                            .buttonStyle(HomeyPrimaryButtonStyle())
                            .disabled(seconds > 0 || verification.isBusy || authenticationService.isLoading || verification.pending == nil)
                            .accessibilityHint(seconds > 0 ? "Available in \(seconds) seconds" : "Sends a new signup verification link")
                        }
                        Button("Back to Log In") {
                            Task {
                                await authenticationService.signOut(scope: .local)
                                onBackToLogin()
                            }
                        }
                        .buttonStyle(AuthenticationSecondaryButtonStyle())
                        .disabled(verification.isBusy || authenticationService.isLoading)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 560)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
