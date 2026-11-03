import Combine
import Foundation
import LocalAuthentication

/// A device-owner gate only. Never changes Homey profiles, memberships, or roles.
@MainActor
final class DeviceUnlockService: ObservableObject {
    private static let preferenceKey = "homey.deviceUnlock.accountID"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published private(set) var biometricName = "Face ID / Touch ID"
    @Published private(set) var canAuthenticate = false
    @Published private(set) var availabilityMessage = ""
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private var protectedAccountID: String?
    private var accountID: UUID?
    private var context: LAContext?
    private var attemptID: UUID?
    private var sceneIsActive = true
    @Published private(set) var isAccountAuthenticationInProgress = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        protectedAccountID = defaults.string(forKey: Self.preferenceKey)
        isEnabled = protectedAccountID != nil
        isLocked = protectedAccountID != nil
        refreshAvailability()
    }

    func bindAccount(_ id: UUID) {
        guard accountID != id else { return }
        cancelAuthentication()
        accountID = id
        if let protectedAccountID, protectedAccountID != id.uuidString {
            reset()
            accountID = id
        }
        isLocked = isEnabled
    }

    func sessionBecameUnavailable() {
        cancelAuthentication()
        accountID = nil
        isLocked = isEnabled
        errorMessage = nil
        // Keep the preference across a temporary restore/network failure. Only
        // logout or a different signed-in account may remove local protection.
    }

    func reset() {
        cancelAuthentication()
        defaults.removeObject(forKey: Self.preferenceKey)
        protectedAccountID = nil
        accountID = nil
        isEnabled = false
        isLocked = false
        errorMessage = nil
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: biometricName = "Face ID"
        case .touchID: biometricName = "Touch ID"
        default: biometricName = "Face ID / Touch ID"
        }
        canAuthenticate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        if !canAuthenticate {
            availabilityMessage = "Set up an iPad passcode in Settings to enable device unlock."
        } else if context.biometryType == .none {
            availabilityMessage = "Biometrics are unavailable. Your iPad passcode can unlock Homey."
        } else {
            availabilityMessage = "Use \(biometricName) or your iPad passcode."
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isAuthenticating, !isAccountAuthenticationInProgress, sceneIsActive, let accountID else { return }
        if !enabled {
            defaults.removeObject(forKey: Self.preferenceKey)
            protectedAccountID = nil
            isEnabled = false
            isLocked = false
            errorMessage = nil
            return
        }
        guard !isEnabled else { return }
        refreshAvailability()
        guard canAuthenticate else { errorMessage = availabilityMessage; return }
        let success = await authenticate(reason: "Enable device-owner unlock for this shared Homey iPad.")
        guard success, self.accountID == accountID, sceneIsActive else { return }
        protectedAccountID = accountID.uuidString
        defaults.set(protectedAccountID, forKey: Self.preferenceKey)
        isEnabled = true
        isLocked = false
    }

    func unlock(using authentication: AuthenticationService) async {
        guard isEnabled, isLocked, !isAuthenticating, !isAccountAuthenticationInProgress, sceneIsActive else { return }
        // Validate Homey first. A device-owner result cannot revive an invalid session.
        let id = UUID()
        attemptID = id
        isAuthenticating = true
        errorMessage = nil
        let validSession = await authentication.validateSessionForDeviceUnlock()
        guard attemptID == id else { return }
        isAuthenticating = false
        attemptID = nil
        guard validSession, sceneIsActive, isEnabled else {
            if authentication.authenticationState == .authenticated {
                errorMessage = "Connect to the internet to verify your Homey session, then try again."
            }
            return
        }
        let expectedAccountID = accountID
        let success = await authenticate(reason: "Unlock this shared Homey iPad. This does not identify a household member.")
        guard success, sceneIsActive, accountID == expectedAccountID,
              authentication.authenticationState == .authenticated else { return }
        isLocked = false
    }

    func beginAccountAuthentication() -> Bool {
        guard !isAuthenticating, !isAccountAuthenticationInProgress else { return false }
        isAccountAuthenticationInProgress = true
        return true
    }

    func endAccountAuthentication() {
        isAccountAuthenticationInProgress = false
    }

    func sceneDidConnect() {
        // A new iPad window must not inherit an already-unlocked root hierarchy.
        // All windows share the device gate and a single authentication attempt.
        cancelAuthentication()
        if isEnabled { isLocked = true }
    }

    func sceneWillDeactivate() {
        sceneIsActive = false
        // The system authentication sheet itself makes the scene inactive.
        if isEnabled && !isAuthenticating && !isAccountAuthenticationInProgress { isLocked = true }
    }

    func sceneDidEnterBackground() {
        sceneIsActive = false
        if isEnabled { isLocked = true }
        cancelAuthentication()
    }

    func sceneDidActivate() {
        sceneIsActive = true
        refreshAvailability()
    }

    private func cancelAuthentication() {
        attemptID = nil
        context?.invalidate()
        context = nil
        isAuthenticating = false
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        let id = UUID()
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        attemptID = id
        isAuthenticating = true
        errorMessage = nil
        defer {
            if attemptID == id {
                self.context = nil
                attemptID = nil
                isAuthenticating = false
            }
            context.invalidate()
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard attemptID == id else { return false }
            // Successful LocalAuthentication can return just before didActivate.
            // Allow success while inactive; background explicitly cancels this attempt.
            if success { sceneIsActive = true }
            return success
        } catch {
            guard attemptID == id else { return false }
            errorMessage = "Homey remains protected. Try again with biometrics or your iPad passcode."
            if !isEnabled { errorMessage = "Device unlock was not enabled. Authenticate successfully to turn it on." }
            return false
        }
    }
}
