import Foundation
import LocalAuthentication

@main
struct DeviceUnlockChecks {
    @MainActor
    static func main() async throws {
        let key = "homey.deviceUnlock.accountID"
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--verify-persisted" {
            let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
            let gate = DeviceUnlockService(defaults: defaults)
            precondition(gate.isEnabled && gate.isLocked, "new process must start protected")
            precondition(defaults.string(forKey: key) == CommandLine.arguments[3], "new process must retain account preference")
            print("PASS: fresh-process preference restoration starts locked")
            return
        }
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label); count += 1
        }
        let suite = "homey.device-unlock-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let userA = UUID(), userB = UUID()
        let gate = DeviceUnlockService(defaults: defaults)
        let auth = AuthenticationService()
        check(!gate.isEnabled && !gate.isLocked && defaults.string(forKey: key) == nil, "new install unconfigured")
        await gate.setEnabled(true)
        check(!gate.isEnabled, "cannot enable without confirmed account binding")
        gate.bindAccount(userA)
        await gate.setEnabled(true)
        check(gate.isEnabled && !gate.isLocked, "enable after successful device authentication")
        check(defaults.string(forKey: key) == userA.uuidString, "preference stores bound account id")
        check(LAContext.evaluatedPolicies == [.deviceOwnerAuthentication], "device passcode fallback is supported")

        // Use another process, not merely another service instance, to verify
        // UserDefaults survives destruction of the process owning the service.
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--verify-persisted", suite, userA.uuidString]
        try child.run(); child.waitUntilExit()
        check(child.terminationStatus == 0, "cold launch in separate process")
        let restored = DeviceUnlockService(defaults: defaults)
        check(restored.isEnabled && restored.isLocked, "force-quit/relaunch model starts locked before authentication")
        restored.bindAccount(userA)
        check(restored.isEnabled && restored.isLocked, "same-account restoration preserves protection")
        for _ in 0..<3 { restored.sessionBecameUnavailable() }
        check(restored.isEnabled && restored.isLocked && defaults.string(forKey: key) == userA.uuidString,
              "temporary offline/Supabase/nil-account failures never erase preference")
        await restored.setEnabled(false)
        check(restored.isEnabled && defaults.string(forKey: key) == userA.uuidString, "nil account cannot implicitly disable protection")
        restored.bindAccount(userA)
        check(restored.isEnabled && restored.isLocked, "same-account retry still requires local unlock")
        auth.validSession = false
        let before = LAContext.evaluatedPolicies.count
        await restored.unlock(using: auth)
        check(restored.isLocked && restored.isEnabled && LAContext.evaluatedPolicies.count == before,
              "unrestored/invalid session cannot reach biometrics or protected content")
        auth.authenticationState = .profileInitializationRequired
        await restored.unlock(using: auth)
        check(restored.isLocked && defaults.string(forKey: key) == userA.uuidString, "profile-loading failure retains protection")
        auth.authenticationState = .authenticated
        auth.validSession = true
        LAContext.outcome = .failure(MockAuthenticationError.cancelled)
        await restored.unlock(using: auth)
        check(restored.isLocked && restored.isEnabled && restored.errorMessage != nil, "biometric cancellation retains lock and preference")
        LAContext.outcome = .failure(MockAuthenticationError.failed)
        await restored.unlock(using: auth)
        check(restored.isLocked && defaults.string(forKey: key) == userA.uuidString, "biometric failure retains lock and preference")
        LAContext.outcome = .success(false)
        await restored.unlock(using: auth)
        check(restored.isLocked, "false device result cannot unlock")
        LAContext.outcome = .success(true)
        await restored.unlock(using: auth)
        check(!restored.isLocked && restored.isEnabled, "valid session and successful device authentication unlock")
        restored.sceneWillDeactivate()
        check(restored.isLocked, "deactivation immediately locks")
        restored.sceneDidEnterBackground(); restored.sceneDidActivate()
        check(restored.isEnabled && restored.isLocked, "background/foreground never auto-unlocks or disables")
        await restored.unlock(using: auth)
        restored.sceneDidConnect()
        check(restored.isLocked, "new iPad window cannot inherit unlocked content")
        await restored.unlock(using: auth)
        check(restored.beginAccountAuthentication(), "passkey ceremony starts independently")
        restored.sceneWillDeactivate()
        check(!restored.isLocked && restored.isEnabled, "native passkey sheet does not spuriously disable/lock app")
        restored.sceneDidEnterBackground()
        check(restored.isLocked && defaults.string(forKey: key) == userA.uuidString, "actual background still locks during passkey ceremony")
        restored.endAccountAuthentication(); restored.sceneDidActivate()
        check(!restored.isAccountAuthenticationInProgress, "passkey ceremony guard clears")

        LAContext.pauseEvaluation = true
        let unlocking = Task { await restored.unlock(using: auth) }
        while LAContext.continuation == nil { await Task.yield() }
        restored.sceneDidEnterBackground()
        LAContext.continuation!.resume(); LAContext.continuation = nil
        await unlocking.value
        check(restored.isLocked && restored.isEnabled, "late biometric success after background cannot unlock")
        LAContext.pauseEvaluation = false
        restored.sceneDidActivate()
        auth.pauseValidation = true
        let validating = Task { await restored.unlock(using: auth) }
        while auth.continuation == nil { await Task.yield() }
        restored.sessionBecameUnavailable()
        auth.continuation!.resume(); auth.continuation = nil
        await validating.value
        check(restored.isLocked && restored.isEnabled, "late session validation after temporary nil cannot unlock")
        auth.pauseValidation = false
        restored.bindAccount(userA)
        await restored.setEnabled(false)
        check(!restored.isEnabled && !restored.isLocked && defaults.string(forKey: key) == nil, "explicit user disable deletes preference")
        LAContext.testBiometry = .none
        await restored.setEnabled(true)
        check(restored.isEnabled && restored.biometricName == "Face ID / Touch ID", "passcode-only device can enable local protection")
        check(LAContext.evaluatedPolicies.last == .deviceOwnerAuthentication, "fallback uses device-owner policy")
        restored.reset()
        check(!restored.isEnabled && defaults.string(forKey: key) == nil, "explicit signout/security-reset primitive removes preference")
        restored.bindAccount(userA)
        LAContext.testBiometry = .touchID
        await restored.setEnabled(true)
        check(restored.biometricName == "Touch ID", "Touch ID supported")
        restored.sessionBecameUnavailable(); restored.bindAccount(userB)
        check(!restored.isEnabled && !restored.isLocked && defaults.string(forKey: key) == nil, "confirmed other account cannot inherit protection")
        let accountBLaunch = DeviceUnlockService(defaults: defaults)
        check(!accountBLaunch.isEnabled, "account switch removal persists across relaunch")
        LAContext.available = false
        accountBLaunch.bindAccount(userB)
        await accountBLaunch.setEnabled(true)
        check(!accountBLaunch.isEnabled, "unavailable device authentication cannot enable protection")
        print("Passed \(count) actual DeviceUnlockService checks with mocked auth and biometric boundaries")
    }
}
