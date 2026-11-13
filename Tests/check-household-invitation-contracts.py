"""Offline wiring checks complement the executable workflow tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
def source(path): return (root / path).read_text()
home = source('Homey/Features/HomeOnboarding/Services/HomeService.swift')
flow = source('Homey/Features/HomeOnboarding/Services/HouseholdInvitationFlow.swift')
invite = source('Homey/Features/MainApp/Views/HomeMembersView.swift')
join = source('Homey/Features/HomeOnboarding/Views/JoinHomeView.swift')
assert '"homey-send-household-invitation"' in home
assert '"create_home_invitation"' not in home
assert '"redeem_home_invitation_code"' in home and '"requested_code"' in home
assert 'FunctionInvokeOptions(body: request)' in home
assert 'homeID == selectedHomeID, selectedHome() != nil' in home
assert 'selectedHomeRole(currentUserID: userID)' in home
assert 'invitationRefreshRequested = true' in home
redemption = home.split('    func redeemInvitationCode')[1].split('    func cancelInvitation')[0]
assert 'requireVerifiedAccount(expectedID: currentUserID)' in redemption
assert 'accountRevision' in redemption and 'currentSession?.user.id == currentUserID' in redemption
assert '.from(' not in redemption and '.insert(' not in redemption
assert 'self.setSelectedHomeID(homeID)' in redemption and 'self.homes = refreshed' in redemption
assert 'refreshMyPendingInvitations' in redemption
assert 'Invitation Sent!' in invite and 'Send Invitation' in invite
assert 'Email delivery will be added later' not in invite
assert 'invitation.expirationText' in invite
assert 'Welcome Home!' in join and 'Continue' in join and 'Join Home' in join
assert 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX' in join
assert 'onSubmit' in join and 'accessibilityLabel("Invitation Code")' in join
for path in ['HomeOnboardingView.swift', 'HomeInvitationOnboardingView.swift', 'HomeSelectionView.swift']:
    assert 'JoinHomeView(' in source('Homey/Features/HomeOnboarding/Views/' + path)
assert 'JoinHomeView(' in source('Homey/Features/MainApp/Views/HomeInvitationsView.swift')
assert 'accept_home_invitation' in home and 'cancel_home_invitation' in home
routing = source('Homey/Core/Routing/RootView.swift')
assert routing.index('passwordRecovery.state.isPresented') < routing.index('normalContent')
assert routing.index('case .emailVerificationRequired:') < routing.index('case .authenticated:')
assert routing.index('deviceUnlock.isEnabled && deviceUnlock.isLocked') < routing.index('private var authenticatedContent')
assert 'UserDefaults' in flow and 'Keychain' not in flow and 'AppGroup' not in flow
assert 'client = SupabaseManager.shared.client' in home
assert 'czddjigvnliclcjyxqoc' in source('Homey.xcodeproj/project.pbxproj')
print('Passed invitation transport, selected Home, session, navigation and security wiring contracts')
