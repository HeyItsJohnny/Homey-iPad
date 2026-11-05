"""Wiring regression checks complement executable state/policy tests; no network calls."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
auth = (root / 'Homey/Features/Authentication/Services/AuthenticationService.swift').read_text()
signup = auth.split('    func signUp(')[1].split('    func signOut(')[0]
assert 'SignupNames(' in signup and '.metadata.mapValues { .string($0) }' in signup
assert 'redirectTo: EmailVerification.redirectURL' in signup
assert 'upsertProfile(' not in signup and '.upsert(' not in signup
assert 'response.user.id' not in signup and 'currentUser = UserProfile' not in signup
assert 'clearSession(state: .emailVerificationRequired)' in signup
assert 'verification.begin(email: normalizedEmail, sent: true)' in signup
assert 'user.confirmedAt' not in auth
assert 'verification.errorMessage != nil' in auth.split('func handleEmailVerification')[1].split('func resendVerificationEmail')[0]
assert 'queuedVerificationURL = url' in auth and 'drainVerificationCallback()' in auth
apply = auth.split('    private func applySession(')[1].split('    func retryAccountInitialization')[0]
assert apply.index('client.auth.user(jwt:') < apply.index('initializeProfile(') < apply.index('authenticationState = .authenticated')
assert 'revision == authRevision' in apply and 'candidate.isExpired' in apply
assert '.profileInitializationRequired' in apply
assert 'await applySession(signedInSession' in auth.split('    func signInWithPasskey')[1]
assert 'isVerified(user: verifiedUser)' in auth.split('    func validateSessionForDeviceUnlock')[1]
profile = auth.split('    private func initializeProfile')[1].split('    private func clearSession')[0]
assert 'ignoreDuplicates: true' in profile and 'MissingProfileName.repairs' in profile
assert '.eq("id", value: user.id.uuidString)' in profile
assert 'query.is(repair.column, value: nil)' in profile
assert 'query.eq(repair.column, value: previous)' in profile
adapter = (root / 'Homey/Features/Authentication/Services/SupabaseEmailVerificationAuth.swift').read_text()
assert 'type: .signup' in adapter and 'emailRedirectTo: EmailVerification.redirectURL' in adapter
assert 'exchangeCodeForSession(authCode: code)' in adapter and 'client.auth.user(jwt: session.accessToken)' in adapter
assert 'emailConfirmedAt != nil' in adapter and 'resetPasswordForEmail' not in adapter
recovery = (root / 'Homey/Features/Authentication/Services/SupabasePasswordRecoveryAuth.swift').read_text()
assert 'storageKey: "homeyipad.password-recovery"' in recovery
assert 'PasswordRecovery.redirectURL' in recovery
app = (root / 'Homey/HomeyApp.swift').read_text()
assert 'if PasswordRecovery.isCallback(url)' in app and 'else if EmailVerification.isCallback(url)' in app
view = (root / 'Homey/Features/Authentication/Views/VerifyEmailView.swift').read_text()
for text in ['Verify Your Email', "We've sent a verification link to:", 'Waiting for email verification',
             'Resend Verification Email', 'Back to Log In', 'TimelineView', 'remainingSeconds', 'ScrollView']:
    assert text in view
assert 'Continue' not in view and 'Refresh Session' not in view
home = (root / 'Homey/Features/HomeOnboarding/Services/HomeService.swift').read_text()
assert home.count('try await requireVerifiedAccount(') == 3
routing = (root / 'Homey/Core/Routing/RootView.swift').read_text()
assert 'case .profileInitializationRequired:' in routing and 'case .emailVerificationRequired:' in routing
assert 'HomeInvitationOnboardingView()' in routing and 'HomeOnboardingView()' in routing
print('Passed signup, session, profile, navigation, passkey, device-unlock and recovery wiring contracts')
