import Foundation

/// Only the boundary used by DeviceUnlockService. Real auth restoration paths
/// and reset policies are checked separately against AuthenticationService.
@MainActor
final class AuthenticationService {
    var authenticationState: AuthenticationState = .authenticated
    var validSession = true
    var validations = 0
    var pauseValidation = false
    var continuation: CheckedContinuation<Void, Never>?

    func validateSessionForDeviceUnlock() async -> Bool {
        validations += 1
        if pauseValidation { await withCheckedContinuation { continuation = $0 } }
        return validSession
    }
}
