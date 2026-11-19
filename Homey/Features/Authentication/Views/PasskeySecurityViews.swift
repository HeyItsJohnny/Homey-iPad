import Auth
import SwiftUI

/// A nonmodal offer. Native registration starts only after Set Up Passkey is tapped.
struct PasskeySetupOfferView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @StateObject private var anchor = PasskeyWindowAnchor()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set Up Face ID / Touch ID Sign-In")
                .font(.headline)
            if let email = authentication.currentUser?.email {
                Text("Homey account: \(email)").font(.subheadline.weight(.semibold))
            }
            Text("Optional passkey sign-in for your Homey account. On this shared iPad, device verification does not identify a household member.")
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
            if let message = authentication.passkeyMessage {
                Text(message).font(.footnote)
            }
            HStack(spacing: 20) {
                Button("Set Up Passkey") {
                    Task { await authentication.registerPasskey(presentationAnchor: anchor.window) }
                }
                .buttonStyle(AuthenticationSecondaryButtonStyle())
                Button("Not Now") { authentication.dismissPasskeySetupOffer() }
                    .frame(minHeight: 44)
            }
            .disabled(authentication.isLoading)
            if authentication.isPasskeyOperationInProgress { ProgressView("Setting up passkey…") }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(HomeyTheme.backgroundPrimary)
        .background(PasskeyPresentationAnchor(anchor: anchor).frame(width: 0, height: 0))
    }
}

struct AccountPasskeySettingsView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @StateObject private var anchor = PasskeyWindowAnchor()
    @State private var removalAccountID: UUID?
    @State private var confirmedPasskeyIDs: Set<String> = []
    @State private var isShowingRemovalConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIGN-IN & SECURITY")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary)

            Button(role: authentication.accountPasskeyAction == .remove ? .destructive : nil) {
                switch authentication.accountPasskeyAction {
                case .setup:
                    Task { await authentication.registerPasskey(presentationAnchor: anchor.window) }
                case .remove:
                    removalAccountID = authentication.session?.user.id
                    confirmedPasskeyIDs = Set(authentication.accountPasskeys.map(\.id))
                    isShowingRemovalConfirmation = true
                case .refresh:
                    Task { await authentication.loadAccountPasskeys() }
                }
            } label: {
                Text(actionTitle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .buttonStyle(HomeyPrimaryButtonStyle())
            .disabled(!authentication.canManageAccountPasskeys)

            if authentication.hasRegisteredAccountPasskey {
                Label("Passkey is already setup", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.success)
            }
            if authentication.isPasskeyOperationInProgress || authentication.isRefreshingPasskeys {
                ProgressView("Updating account passkeys…")
            }
            if let message = authentication.passkeyMessage {
                Text(message).font(.subheadline)
            }
        }
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .background(PasskeyPresentationAnchor(anchor: anchor).frame(width: 0, height: 0))
        .task(id: authentication.passkeyStatusRevision) { await authentication.loadAccountPasskeys() }
        .onChange(of: authentication.session?.user.id) { _, _ in clearRemovalConfirmation() }
        .onChange(of: authentication.authenticationState) { _, _ in clearRemovalConfirmation() }
        .onChange(of: authentication.passkeyStatusRevision) { _, _ in clearRemovalConfirmation() }
        .confirmationDialog("Remove Passkey?", isPresented: $isShowingRemovalConfirmation,
                            titleVisibility: .visible) {
            Button("Remove Passkey", role: .destructive) {
                if let accountID = removalAccountID {
                    let ids = confirmedPasskeyIDs
                    Task { await authentication.removeAccountPasskeys(confirmedIDs: ids, accountID: accountID) }
                }
                clearRemovalConfirmation()
            }
            Button("Cancel", role: .cancel) { clearRemovalConfirmation() }
        } message: {
            Text(removalConfirmationMessage)
        }
    }

    private var removalConfirmationMessage: String {
        let message = "You'll no longer be able to sign in to Homey using this passkey. You can set it up again anytime."
        if confirmedPasskeyIDs.count > 1 {
            return message + "\n\nThis removes all \(confirmedPasskeyIDs.count) currently registered passkeys for this account."
        }
        return message
    }

    private var actionTitle: String {
        switch authentication.accountPasskeyAction {
        case .setup: return "Setup Face ID/Touch ID"
        case .remove: return "Remove Passkey"
        case .refresh: return "Check Passkey Status"
        }
    }

    private func clearRemovalConfirmation() {
        isShowingRemovalConfirmation = false
        removalAccountID = nil
        confirmedPasskeyIDs = []
    }
}
