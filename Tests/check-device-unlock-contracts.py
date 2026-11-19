"""Verify production restoration/reset policy and household lock routing offline."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
service = read('Homey/Core/Security/DeviceUnlockService.swift')
auth = read('Homey/Features/Authentication/Services/AuthenticationService.swift')
route = read('Homey/Core/Routing/RootView.swift')
app = read('Homey/HomeyApp.swift')
shield = read('Homey/Core/Security/PrivacySnapshotShield.swift')
assert 'homey.deviceUnlock.accountID' in service
init = service.split('    init(defaults:')[1].split('    func bindAccount')[0]
for text in ['defaults.string(forKey: Self.preferenceKey)', 'isEnabled = protectedAccountID != nil', 'isLocked = protectedAccountID != nil']:
    assert text in init, text
unavailable = service.split('    func sessionBecameUnavailable()')[1].split('    func reset()')[0]
assert 'accountID = nil' in unavailable and 'isLocked = isEnabled' in unavailable
assert 'removeObject' not in unavailable and 'reset()' not in unavailable
bind = service.split('    func bindAccount(')[1].split('    func sessionBecameUnavailable')[0]
assert 'protectedAccountID != id.uuidString' in bind and 'isLocked = isEnabled' in bind
restore = auth.split('    func restoreSession()')[1].split('    func handleEmailVerification')[0]
assert 'clearSession(state:' in restore and 'resetDeviceProtection: true' not in restore
clear = auth.split('    private func clearSession(')[1].split('    private func isVerified')[0]
assert 'resetDeviceProtection: Bool = false' in clear
assert 'deviceUnlock.reset()' in clear and 'deviceUnlock.sessionBecameUnavailable()' in clear
apply = auth.split('    private func applySession(')[1].split('    func retryAccountInitialization')[0]
assert apply.index('initializeProfile(user:') < apply.index('deviceUnlock.bindAccount(user.id)') < apply.index('authenticationState = .authenticated')
catch = apply.split('        } catch {')[1]
assert '.profileInitializationRequired' in catch and 'deviceUnlock.reset' not in catch
assert 'resetDeviceProtection: true' not in apply
refresh = auth.split('    func refreshSession()')[1].split('    // MARK: - Authentication')[0]
assert '.profileInitializationRequired' in refresh and 'resetDeviceProtection: true' not in refresh
logout = auth.split('    func signOut(')[1].split('    func clearError')[0]
assert 'resetDeviceProtection: true' in logout
handler = auth.split('    private func handleAuthStateChange(')[1].split('    private func applySession')[0]
missing = handler.split('            } else {')[1].split('        case .signedOut')[0]
assert 'clearSession(state:' in missing and 'resetDeviceProtection: true' not in missing
assert 'case .signedOut, .userDeleted:' in handler and 'resetDeviceProtection: true' in handler
assert auth.count('resetDeviceProtection: true') == 3  # explicit signup/logout and terminal auth event
validation = auth.split('    func validateSessionForDeviceUnlock()')[1].split('    func refreshSession')[0]
assert 'if invalidSession {' in validation and 'clearSession(state: .unauthenticated)' in validation
assert validation.index('if invalidSession {') < validation.index('client.auth.signOut(scope: .local)')
assert 'default:\n                    invalidSession = false' in validation
unlock = service.split('    func unlock(using')[1].split('    func beginAccountAuthentication')[0]
assert unlock.index('validateSessionForDeviceUnlock()') < unlock.index('await authenticate(reason:') < unlock.index('isLocked = false')
assert 'authentication.authenticationState == .authenticated' in unlock
assert 'accountID == expectedAccountID' in unlock
assert '.evaluatePolicy(.deviceOwnerAuthentication' in service
assert route.index('case .loading:') < route.index('case .authenticated:')
assert route.index('case .profileInitializationRequired:') < route.index('case .authenticated:')
assert route.index('deviceUnlock.isEnabled && deviceUnlock.isLocked') < route.index('private var authenticatedContent')
assert 'DeviceUnlockView()' in route
assert 'deviceUnlock.reset()' not in route and 'resetDeviceProtection' not in route
assert 'AuthenticationService(deviceUnlock: deviceUnlock)' in app
assert '.environmentObject(deviceUnlock)' in app
for callback in ['sceneWillDeactivate()', 'sceneDidEnterBackground()', 'sceneDidActivate()', 'sceneDidConnect()']:
    assert callback in shield, callback
assert 'UIWindow(windowScene: scene)' in shield and '.alert + 1' in shield
passkey = auth.split('    func registerPasskey(')[1].split('    private func isPasskeyCancellation')[0]
assert 'deviceUnlock.reset()' not in passkey and 'resetDeviceProtection: true' not in passkey
assert 'client.auth.registerPasskey' in passkey and 'client.auth.deletePasskey' in passkey
print('Passed restoration/nil/profile failure preservation, explicit reset policy, lock routing and passkey isolation contracts')
