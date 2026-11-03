import SwiftUI

struct DeviceUnlockView: View {
    @EnvironmentObject private var deviceUnlock: DeviceUnlockService
    @EnvironmentObject private var authentication: AuthenticationService

    var body: some View {
        ZStack {
            HomeyTheme.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(HomeyTheme.primary)
                    .accessibilityHidden(true)
                Text("Homey is locked")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Unlock this shared iPad with \(deviceUnlock.biometricName) or the device passcode.")
                    .foregroundStyle(HomeyTheme.textSecondary)
                Text("Device unlock does not identify a household member or change anyone’s permissions.")
                    .font(.footnote)
                    .foregroundStyle(HomeyTheme.textSecondary)
                if let error = deviceUnlock.errorMessage {
                    Text(error).font(.callout).foregroundStyle(HomeyTheme.textSecondary)
                }
                Button {
                    Task { await deviceUnlock.unlock(using: authentication) }
                } label: {
                    HStack {
                        if deviceUnlock.isAuthenticating { ProgressView().tint(.white) }
                        Text(deviceUnlock.isAuthenticating ? "Verifying…" : "Unlock Homey")
                    }
                }
                .buttonStyle(HomeyPrimaryButtonStyle())
                .disabled(deviceUnlock.isAuthenticating || authentication.isLoading || deviceUnlock.isAccountAuthenticationInProgress)
                Button("Sign out of Homey") {
                    Task { await authentication.signOut() }
                }
                .disabled(authentication.isLoading)
                .frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: 480)
        }
    }
}

struct DeviceUnlockSettingsView: View {
    @EnvironmentObject private var deviceUnlock: DeviceUnlockService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unlock this iPad")
                .font(.title3.weight(.bold))
            Toggle("Require Face ID / Touch ID to Unlock", isOn: Binding(
                get: { deviceUnlock.isEnabled },
                set: { enabled in Task { await deviceUnlock.setEnabled(enabled) } }
            ))
            .disabled(deviceUnlock.isAuthenticating || deviceUnlock.isAccountAuthenticationInProgress || (!deviceUnlock.isEnabled && !deviceUnlock.canAuthenticate))
            if deviceUnlock.isAuthenticating { ProgressView("Confirming device owner…") }
            Text(deviceUnlock.availabilityMessage)
            Text("Optional protection for this iPad only. Anyone with an enrolled biometric or the iPad passcode can unlock the signed-in household hub. This does not select a member or grant approvals, chores, rewards, or account ownership.")
            Text("When enabled, Homey locks whenever you leave the app. Signing out turns this setting off.")
            if let error = deviceUnlock.errorMessage { Text(error) }
        }
        .font(.subheadline)
        .foregroundStyle(HomeyTheme.textSecondary)
        .tint(HomeyTheme.primary)
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .onAppear { deviceUnlock.refreshAvailability() }
    }
}
