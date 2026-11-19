// Test-only replacement framework. The actual DeviceUnlockService is compiled
// unchanged against this module; tests never open real biometric prompts.
import Foundation

public enum LABiometryType { case none, touchID, faceID }
public enum LAPolicy: Equatable { case deviceOwnerAuthentication, deviceOwnerAuthenticationWithBiometrics }
public enum MockAuthenticationError: Error { case cancelled, failed }

public final class LAContext {
    public static var available = true
    public static var testBiometry = LABiometryType.faceID
    public static var outcome: Result<Bool, Error> = .success(true)
    public static var evaluatedPolicies: [LAPolicy] = []
    public static var pauseEvaluation = false
    public static var continuation: CheckedContinuation<Void, Never>?
    public static var invalidations = 0

    public var biometryType: LABiometryType { Self.testBiometry }
    public var localizedCancelTitle: String?
    public var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 0

    public init() {}
    public func canEvaluatePolicy(_ policy: LAPolicy, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        Self.available && (policy == .deviceOwnerAuthentication || Self.testBiometry != .none)
    }
    public func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        Self.evaluatedPolicies.append(policy)
        if Self.pauseEvaluation { await withCheckedContinuation { Self.continuation = $0 } }
        return try Self.outcome.get()
    }
    public func invalidate() { Self.invalidations += 1 }
}
