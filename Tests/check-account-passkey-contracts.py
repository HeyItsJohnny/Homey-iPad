"""Offline UI/service contracts complement executable removal tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
view = read('Homey/Features/Authentication/Views/PasskeySecurityViews.swift').split('struct AccountPasskeySettingsView:')[1]
auth = read('Homey/Features/Authentication/Services/AuthenticationService.swift')
assert 'Button(role: authentication.accountPasskeyAction == .remove ? .destructive : nil)' in view
for text in ['Setup Face ID/Touch ID', 'Remove Passkey', 'Passkey is already setup', 'Remove Passkey?',
             "You'll no longer be able to sign in to Homey using this passkey. You can set it up again anytime."]:
    assert text in view, text
assert view.index('.buttonStyle(HomeyPrimaryButtonStyle())') < view.index('Label("Passkey is already setup"')
for removed in ['Apple Passwords', 'ForEach(', 'passkey.name', 'passkey.createdAt', 'Delete Passkey', 'Refresh Passkeys']:
    assert removed not in view, removed
assert 'HomeyTheme.success' in view
assert 'Button("Cancel", role: .cancel)' in view
assert 'confirmedPasskeyIDs.count > 1' in view
assert 'Set(authentication.accountPasskeys.map(\\.id))' in view
assert 'canManageAccountPasskeys' in view
assert '.task(id: authentication.passkeyStatusRevision)' in view
assert 'onChange(of: authentication.session?.user.id)' in view
assert 'onChange(of: authentication.authenticationState)' in view
assert 'onChange(of: authentication.passkeyStatusRevision)' in view
assert 'registerPasskey(presentationAnchor: anchor.window)' in view
register = auth.split('    func registerPasskey(')[1].split('    func loadAccountPasskeys')[0]
assert 'client.auth.registerPasskey' in register and 'fetchAccountPasskeys(expectedID: expectedID)' in register
assert 'passkey setup could not be completed' in register.lower()
remove = auth.split('    func removeAccountPasskeys(')[1].split('    private func isPasskeyCancellation')[0]
for token in ['client.auth.listPasskeys()', 'client.auth.deletePasskey(id: id)', 'beginPasskeyOperation()',
              'endPasskeyOperation()', 'client.auth.currentSession?.user.id == accountID',
              'self.passkeyStatusRevision == revision', 'self.authRevision == authenticationRevision',
              'accountPasskeys = remaining', 'remaining.isEmpty', 'isSubset(of:']:
    assert token in remove, token
for forbidden in ['signOut(', 'clearSession(', 'deviceUnlock.reset(', 'selectedHome', 'applySession(']:
    assert forbidden not in remove, forbidden
assert 'await applySession(signedInSession' in auth.split('func signInWithPasskey(')[1]
account = read('Homey/Features/MainApp/Views/MyAccountView.swift')
assert 'AccountPasskeySettingsView()' in account and 'DeviceUnlockSettingsView()' in account
style = read('Homey/Core/DesignSystem/HomeyTheme.swift').split('struct HomeyPrimaryButtonStyle:')[1]
assert 'configuration.role == .destructive ? HomeyTheme.danger' in style
print('Passed single-action UI, registration/removal, stale-account and device-unlock isolation contracts')
