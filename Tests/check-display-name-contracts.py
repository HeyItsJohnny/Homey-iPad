"""Verify actual field event wiring, preflight validation and profile persistence."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
for file in ['Homey/Features/Authentication/Views/SignUpView.swift', 'Homey/Features/MainApp/Views/MyAccountView.swift']:
    view = read(file)
    for obsolete in ['isDisplayNameCustomized', 'isUpdatingDisplayNameProgrammatically', 'handleDisplayNameChange', '.onChange(of: displayName)', '.onChange(of: firstName)', '.onChange(of: lastName)']:
        assert obsolete not in view, (file, obsolete)
    for required in ['text: firstNameInput,', 'text: lastNameInput,', 'text: $displayName,', 'guard value != firstName', 'guard value != lastName']:
        assert required in view, (file, required)
    assert view.count('fillBlankDisplayNameAfterNameChange()') == 3
signup = read('Homey/Features/Authentication/Views/SignUpView.swift')
action = signup.split('private func createAccount()')[1].split('private var firstNameInput')[0]
assert action.index('EmailVerification.signupError(') < action.index('authenticationService.signUp(')
assert 'validationMessage = error' in action and 'displayName: trimmedDisplayName' in action
profile = read('Homey/Features/MainApp/Views/MyAccountView.swift')
load = profile.split('private func populateProfileFields()')[1].split('private func saveAccount()')[0]
assert 'displayName = loadedValues.displayName' in load and 'generatedDisplayName' not in load and 'fillBlank' not in load
assert 'ProfileNameFormatter.displayNameError(displayName)' in profile and 'MyAccountErrorBanner(message: message)' in profile
save = profile.split('private func saveAccount()')[1].split('private func loadSelectedPhoto')[0]
assert save.index('ProfileNameFormatter.displayNameError(') < save.index('authenticationService.updateCurrentUserProfile(')
assert 'displayName: currentValues.displayName' in save and 'populateProfileFields()' in save
assert 'authenticationService.currentUser?.id == userID' in save
service = read('Homey/Features/Authentication/Services/AuthenticationService.swift')
for method in ['signUp', 'updateCurrentUserProfile']:
    body = service.split('func ' + method + '(')[1].split('    func ')[0]
    assert 'normalizedProfile.displayName != nil' in body and 'ProfileNameFormatter.requiredDisplayNameMessage' in body
    assert body.index('normalizedProfile.displayName != nil') < body.index('isLoading = true')
update = service.split('func updateCurrentUserProfile(')[1].split('    func ')[0]
assert 'self.currentUser = refreshed' in update and 'authRevision == revision' in update
fetch = service.split('private func fetchProfile(')[1].split('private func upsertProfile(')[0]
assert 'displayName: profile.displayName' in fetch and 'generatedDisplayName' not in fetch
init = service.split('private func initializeProfile(')[1].split('private func clearSession(')[0]
assert 'ignoreDuplicates: true' in init and 'displayName: initialNames.displayName' in init
assert '.eq("id", value: user.id.uuidString)' in init
print('Passed signup/profile input events, validation, persistence, missing-row and account-scope contracts')
