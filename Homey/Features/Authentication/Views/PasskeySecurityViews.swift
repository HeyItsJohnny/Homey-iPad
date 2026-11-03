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
    @State private var passkeyToRemove: AccountPasskey?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIGN-IN & SECURITY")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary)
            Text("Set Up Face ID / Touch ID Sign-In")
                .font(.title3.weight(.bold))
            Text("Create a passkey for the signed-in Homey account. Apple handles device verification and stores the private key. This does not change household members or their permissions.")
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
            if let email = authentication.currentUser?.email {
                Text("Homey account: \(email)")
                    .font(.subheadline.weight(.semibold))
            }
            Button("Set Up Passkey") {
                Task { await authentication.registerPasskey(presentationAnchor: anchor.window) }
            }
            .buttonStyle(AuthenticationSecondaryButtonStyle())
            if authentication.isPasskeyOperationInProgress { ProgressView("Updating account passkeys…") }
            if let message = authentication.passkeyMessage {
                Text(message).font(.subheadline)
            }
            if authentication.hasLoadedPasskeys {
                Text(authentication.accountPasskeys.isEmpty ? "No passkeys registered for this account." : "Account passkeys")
                    .font(.subheadline.weight(.semibold))
                ForEach(authentication.accountPasskeys) { passkey in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(passkey.name).font(.subheadline.weight(.semibold))
                            Text("Added \(passkey.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(HomeyTheme.textSecondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { passkeyToRemove = passkey }
                            .frame(minHeight: 44)
                    }
                }
                Text("Passkeys may be synced or stored on other devices. This list does not identify who is using this iPad. Removing one revokes it for this Homey account; manage stored copies in Apple Passwords or your credential provider.")
                    .font(.footnote)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }
            Button("Refresh Passkeys") {
                Task { await authentication.loadAccountPasskeys() }
            }
            .frame(minHeight: 44)
        }
        .disabled(authentication.isLoading)
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .background(PasskeyPresentationAnchor(anchor: anchor).frame(width: 0, height: 0))
        .task(id: authentication.currentUser?.id) { await authentication.loadAccountPasskeys() }
        .confirmationDialog("Remove this account passkey?", isPresented: Binding(
            get: { passkeyToRemove != nil },
            set: { if !$0 { passkeyToRemove = nil } }
        ), titleVisibility: .visible) {
            if let passkey = passkeyToRemove {
                Button("Remove Passkey", role: .destructive) {
                    Task { await authentication.deleteAccountPasskey(id: passkey.id) }
                    passkeyToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) { passkeyToRemove = nil }
        } message: {
            Text("This revokes the passkey for the signed-in Homey account. Email and password sign-in remain available.")
        }
    }
}
