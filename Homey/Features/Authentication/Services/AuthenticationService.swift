import Auth
import Combine
import Foundation
import PostgREST
@_spi(Experimental) import Supabase
import AuthenticationServices
import UIKit

@MainActor
final class AuthenticationService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var session: Session?
    @Published private(set) var currentUser: UserProfile?
    @Published private(set) var authenticationState: AuthenticationState = .loading
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
    @Published var errorMessage: String?

    @Published private(set) var isPasskeyOperationInProgress = false
    @Published private(set) var accountPasskeys: [AccountPasskey] = []
    @Published private(set) var hasLoadedPasskeys = false
    @Published private(set) var isRefreshingPasskeys = false
    @Published private(set) var passkeyStatusRevision = 0
    private var pendingPasskeyStatusRefresh = false

    var hasRegisteredAccountPasskey: Bool {
        authenticationState == .authenticated && !accountPasskeys.isEmpty
    }

    var canSetUpAccountPasskey: Bool {
        authenticationState == .authenticated && hasLoadedPasskeys && accountPasskeys.isEmpty
            && !isLoading && !isPasskeyOperationInProgress && !isRefreshingPasskeys
    }
    @Published private(set) var passkeyMessage: String?
    @Published private(set) var shouldOfferPasskeySetup = false

    // MARK: - Private Properties

    let verification = EmailVerificationService()
    private var authRevision: UInt64 = 0
    private var handlingVerification = false
    private var restoringSession = false
    private var queuedVerificationURL: URL?
    private let client = SupabaseManager.shared.client
    private let deviceUnlock: DeviceUnlockService
    private var authStateChangesTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init(deviceUnlock: DeviceUnlockService? = nil) {
        self.deviceUnlock = deviceUnlock ?? DeviceUnlockService()
        subscribeToAuthStateChanges()
    }

    deinit {
        authStateChangesTask?.cancel()
    }

    // MARK: - Session

    func restoreSession() async {
        guard !isPasskeyOperationInProgress, !handlingVerification, !isLoading,
              authenticationState != .authenticated else { return }
        authRevision &+= 1
        let revision = authRevision
        isLoading = true
        clearError()
        restoringSession = true
        defer {
            restoringSession = false
            if revision == authRevision { finishAuthenticationOperation() }
        }
        do {
            let restoredSession = try await client.auth.session
            await applySession(restoredSession, revision: revision)
        } catch {
            guard revision == authRevision else { return }
            clearSession(state: verification.pending == nil ? .unauthenticated : .emailVerificationRequired)
        }
    }

    func handleEmailVerification(_ url: URL) async {
        guard EmailVerification.isCallback(url), !handlingVerification else { return }
        if (isLoading && !restoringSession) || isPasskeyOperationInProgress || verification.isBusy {
            queuedVerificationURL = url
            return
        }
        // A verification callback supersedes startup restoration. Auth events emitted
        // by exchangeCodeForSession must not publish an intermediate session.
        authRevision &+= 1
        let revision = authRevision
        handlingVerification = true
        isLoading = true
        defer { handlingVerification = false; finishAuthenticationOperation() }
        if let identity = await verification.handle(url, using: SupabaseEmailVerificationAuth()),
           revision == authRevision, let candidate = client.auth.currentSession,
           candidate.user.id == identity.userID {
            await applySession(candidate, revision: revision)
        } else if revision == authRevision, verification.errorMessage != nil,
                  authenticationState != .authenticated {
            clearSession(state: verification.pending == nil ? .unauthenticated : .emailVerificationRequired)
            errorMessage = verification.errorMessage
        }
    }

    func resendVerificationEmail() async {
        guard !isLoading, !isPasskeyOperationInProgress, !verification.isBusy else { return }
        clearError()
        await verification.resend(using: SupabaseEmailVerificationAuth())
        drainVerificationCallback()
    }

    /// A local unlock never creates a Supabase session. Confirm the existing user
    /// with Auth before exposing protected content; keep locked on network errors.
    func validateSessionForDeviceUnlock() async -> Bool {
        guard authenticationState == .authenticated, let expectedID = session?.user.id else { return false }
        do {
            let restored = try await client.auth.session
            let verifiedUser = try await client.auth.user(jwt: restored.accessToken)
            guard authenticationState == .authenticated, session?.user.id == expectedID,
                  restored.user.id == expectedID, verifiedUser.id == expectedID else { return false }
            guard isVerified(user: verifiedUser), !restored.isExpired else {
                clearSession(state: .emailVerificationRequired)
                verification.begin(email: verifiedUser.email ?? "")
                return false
            }
            self.session = restored
            return authenticationState == .authenticated
        } catch {
            guard session?.user.id == expectedID else { return false }
            if let authError = error as? AuthError {
                let invalidSession: Bool
                switch authError {
                case .sessionMissing, .jwtVerificationFailed:
                    invalidSession = true
                case .api(_, let code, _, let response):
                    invalidSession = [401, 403].contains(response.statusCode)
                        || [.badJWT, .userNotFound, .sessionNotFound, .sessionExpired,
                            .refreshTokenNotFound, .refreshTokenAlreadyUsed, .userBanned].contains(code)
                default:
                    invalidSession = false
                }
                if invalidSession {
                    clearSession(state: .unauthenticated)
                    // Supabase removes the Keychain session before its logout request,
                    // including when that request fails. Do not revive rejected credentials.
                    try? await client.auth.signOut(scope: .local)
                }
            }
            return false
        }
    }

    func refreshSession() async {
        guard !isPasskeyOperationInProgress, !isLoading, !handlingVerification, !verification.isBusy else { return }
        authRevision &+= 1
        let revision = authRevision
        isLoading = true
        clearError()

        do {
            let refreshedSession = try await client.auth.refreshSession()
            await applySession(refreshedSession, revision: revision)
            offerPasskeySetupIfNeeded()
        } catch {
            guard revision == authRevision else { return }
            logCompleteError(error, context: "REFRESH SESSION FAILED")
            errorMessage = authErrorMessage(for: error)
            authenticationState = .profileInitializationRequired
        }

        if revision == authRevision { finishAuthenticationOperation() }
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async {
        guard !isLoading, !isPasskeyOperationInProgress, !verification.isBusy else { return }
        guard validate(email: email, password: password) else {
            return
        }

        authRevision &+= 1
        let revision = authRevision
        verification.clear()
        isLoading = true
        clearError()

        do {
            let signedInSession = try await client.auth.signIn(
                email: EmailVerification.normalize(email),
                password: password
            )
            await applySession(signedInSession, revision: revision)
            offerPasskeySetupIfNeeded()
        } catch {
            guard revision == authRevision else { return }
            logCompleteError(error, context: "SIGN IN FAILED")
            clearSession(state: .unauthenticated)
            if let authError = error as? AuthError, authError.errorCode == .emailNotConfirmed {
                verification.begin(email: email)
                authenticationState = .emailVerificationRequired
            } else {
                errorMessage = authErrorMessage(for: error)
            }
        }

        if revision == authRevision { finishAuthenticationOperation() }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, displayName: String) async {
        guard !isLoading, !isPasskeyOperationInProgress, !verification.isBusy else { return }
        guard validate(email: email, password: password) else {
            return
        }

        let normalizedProfile = NormalizedProfileInput(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )

        guard normalizedProfile.firstName != nil else {
            errorMessage = "Enter your first name."
            return
        }

        guard normalizedProfile.lastName != nil else {
            errorMessage = "Enter your last name."
            return
        }

        guard normalizedProfile.displayName != nil else {
            errorMessage = "Enter a display name."
            return
        }

        isLoading = true
        clearError()

        authRevision &+= 1
        let revision = authRevision
        let normalizedEmail = EmailVerification.normalize(email)
        do {
            if client.auth.currentSession != nil {
                try await client.auth.signOut(scope: .local)
            }
            clearSession(state: .unauthenticated, resetDeviceProtection: true)
            // Save context before the request: termination or a lost response must
            // still let the user resend without storing a password or fake profile.
            verification.begin(email: normalizedEmail, sent: true)
            let response = try await client.auth.signUp(
                email: normalizedEmail,
                password: password,
                data: SignupNames(firstName: firstName, lastName: lastName, displayName: displayName)
                    .metadata.mapValues { .string($0) },
                redirectTo: EmailVerification.redirectURL
            )
            guard revision == authRevision else { return }
            // The database trigger owns initial profile creation. A sessionless
            // response (including an obfuscated duplicate signup) is not failure.
            if let candidate = response.session {
                await applySession(candidate, revision: revision)
            } else {
                clearSession(state: .emailVerificationRequired)
            }
        } catch {
            guard revision == authRevision else { return }
            if let authError = error as? AuthError, [.userAlreadyExists, .emailExists].contains(authError.errorCode) {
                clearSession(state: .emailVerificationRequired)
            } else {
                clearSession(state: .unauthenticated)
                if let authError = error as? AuthError,
                   authError.errorCode == .weakPassword {
                    errorMessage = authError.message
                } else {
                    errorMessage = "We couldn't complete signup. Check your connection and password, or wait a minute before trying again. If you've already signed up, check your email or return to Log In."
                }
            }
        }

        finishAuthenticationOperation()
    }

    func signOut(scope: SignOutScope = .global) async {
        guard !isPasskeyOperationInProgress, !handlingVerification, !verification.isBusy else { return }
        authRevision &+= 1
        verification.clear()
        queuedVerificationURL = nil
        isLoading = true
        clearError()

        do {
            try await client.auth.signOut(scope: scope)
        } catch {
            logCompleteError(error, context: "SIGN OUT FAILED")
            errorMessage = authErrorMessage(for: error)
        }

        clearSession(state: .unauthenticated, resetDeviceProtection: true)
        finishAuthenticationOperation()
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshCurrentUserProfile() async {
        guard let currentUser else {
            return
        }

        do {
            let profile = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            guard self.currentUser?.id == currentUser.id else { return }
            self.currentUser = profile
        } catch {
            logCompleteError(error, context: "FETCH PROFILE FAILED")
        }
    }

    func updateCurrentUserProfile(firstName: String, lastName: String, displayName: String) async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        let normalizedProfile = NormalizedProfileInput(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )

        guard normalizedProfile.firstName != nil else {
            errorMessage = "Enter your first name."
            return false
        }

        guard normalizedProfile.lastName != nil else {
            errorMessage = "Enter your last name."
            return false
        }

        guard normalizedProfile.displayName != nil else {
            errorMessage = "Enter a display name."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        clearError()
        defer { finishAuthenticationOperation() }

        do {
            try await upsertProfile(userID: currentUser.id, email: currentUser.email, profile: normalizedProfile)
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            return true
        } catch {
            logCompleteError(error, context: "UPDATE PROFILE FAILED")
            errorMessage = "We could not update your account. Please try again."
            return false
        }
    }

    func uploadCurrentUserAvatar(imageData: Data) async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        guard !isUploadingAvatar else {
            return false
        }

        guard !imageData.isEmpty else {
            errorMessage = "We could not prepare that photo. Please choose another image."
            return false
        }

        isUploadingAvatar = true
        clearError()
        defer { isUploadingAvatar = false }

        let avatarPath = avatarObjectPath(for: currentUser.id)

        do {
            #if DEBUG
            print("Uploading avatar")
            print("bucket: avatars")
            print("objectPath: \(avatarPath)")
            #endif

            try await client.storage
                .from("avatars")
                .upload(
                    avatarPath,
                    data: imageData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            let publicURL = try client.storage
                .from("avatars")
                .getPublicURL(path: avatarPath)

            do {
                try await updateAvatarURL(publicURL)
            } catch {
                #if DEBUG
                print("Avatar profile update failed after upload; retrying once")
                #endif

                do {
                    try await updateAvatarURL(publicURL)
                } catch {
                    logCompleteError(error, context: "UPDATE AVATAR URL FAILED")
                    errorMessage = "Your photo uploaded, but we could not connect it to your profile. Please try again."
                    return false
                }
            }

            let refreshedProfile = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            self.currentUser = refreshedProfile.withAvatarURL(cacheBustedURL(publicURL))
            return true
        } catch {
            logCompleteError(error, context: "UPLOAD AVATAR FAILED")
            errorMessage = avatarErrorMessage(for: error)
            return false
        }
    }

    func removeCurrentUserAvatar() async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        guard !isUploadingAvatar else {
            return false
        }

        isUploadingAvatar = true
        clearError()
        defer { isUploadingAvatar = false }

        let avatarPath = avatarObjectPath(for: currentUser.id)

        do {
            #if DEBUG
            print("Removing avatar")
            print("bucket: avatars")
            print("objectPath: \(avatarPath)")
            #endif

            _ = try? await client.storage
                .from("avatars")
                .remove(paths: [avatarPath])

            try await updateAvatarURL(nil)
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            return true
        } catch {
            logCompleteError(error, context: "REMOVE AVATAR FAILED")
            errorMessage = avatarErrorMessage(for: error)
            return false
        }
    }

    // MARK: - Optional account passkeys

    private func passkeyOfferKey(for id: UUID) -> String {
        "homey.passkeySetupOfferDismissed.\(id.uuidString)"
    }

    private func offerPasskeySetupIfNeeded() {
        guard authenticationState == .authenticated, let session, !session.user.isAnonymous else { return }
        shouldOfferPasskeySetup = !UserDefaults.standard.bool(forKey: passkeyOfferKey(for: session.user.id))
    }

    func dismissPasskeySetupOffer() {
        guard let id = session?.user.id else { return }
        // Presentation preference only; never treated as proof of enrollment.
        UserDefaults.standard.set(true, forKey: passkeyOfferKey(for: id))
        shouldOfferPasskeySetup = false
    }

    private func clearPasskeyPresentationState() {
        accountPasskeys = []
        hasLoadedPasskeys = false
        passkeyMessage = nil
        shouldOfferPasskeySetup = false
        pendingPasskeyStatusRefresh = false
        passkeyStatusRevision += 1
    }

    private func beginPasskeyOperation(anchor: UIWindow? = nil, requiresAnchor: Bool = false) -> Bool {
        guard !isPasskeyOperationInProgress, !isLoading, !verification.isBusy else { return false }
        if requiresAnchor {
            guard let anchor, !anchor.isHidden,
                  anchor.windowScene?.activationState == .foregroundActive else {
                passkeyMessage = "Return to this Homey window and try again."
                return false
            }
        }
        if requiresAnchor {
            guard deviceUnlock.beginAccountAuthentication() else { return false }
        } else {
            guard !deviceUnlock.isAuthenticating, !deviceUnlock.isAccountAuthenticationInProgress else { return false }
        }
        isPasskeyOperationInProgress = true
        isLoading = true
        passkeyMessage = nil
        clearError()
        return true
    }

    private func endPasskeyOperation() {
        isPasskeyOperationInProgress = false
        finishAuthenticationOperation()
        deviceUnlock.endAccountAuthentication()
        resumePendingPasskeyStatusRefresh()
    }

    private func resumePendingPasskeyStatusRefresh() {
        guard pendingPasskeyStatusRefresh, !isRefreshingPasskeys, !isPasskeyOperationInProgress else { return }
        pendingPasskeyStatusRefresh = false
        Task { await loadAccountPasskeys() }
    }

    func signInWithPasskey(presentationAnchor: UIWindow?) async {
        guard let presentationAnchor else {
            errorMessage = "Return to this Homey window and try again."
            return
        }
        guard authenticationState == .unauthenticated else { return }
        guard beginPasskeyOperation(anchor: presentationAnchor, requiresAnchor: true) else {
            if let passkeyMessage { errorMessage = passkeyMessage }
            return
        }
        defer { endPasskeyOperation() }
        do {
            let response = try await client.auth.signInWithPasskey(presentationAnchor: presentationAnchor)
            guard let signedInSession = response.session else {
                errorMessage = "No Homey session was returned. Please use email and password or try again."
                return
            }
            authRevision &+= 1
            verification.clear()
            await applySession(signedInSession, revision: authRevision)
            if authenticationState == .authenticated { dismissPasskeySetupOffer() }
        } catch {
            if !isPasskeyCancellation(error) {
                errorMessage = "Passkey sign-in could not be completed. Try again or use email and password."
            }
        }
    }

    func registerPasskey(presentationAnchor: UIWindow?) async {
        guard let presentationAnchor else {
            passkeyMessage = "Return to this Homey window and try again."
            return
        }
        guard authenticationState == .authenticated, let expectedID = session?.user.id,
              !isRefreshingPasskeys,
              beginPasskeyOperation(anchor: presentationAnchor, requiresAnchor: true) else { return }
        defer { endPasskeyOperation() }
        do {
            // Confirm the server's current account before starting native registration.
            let user = try await client.auth.user()
            guard session?.user.id == expectedID, user.id == expectedID,
                  isVerified(user: user), !user.isAnonymous,
                  authenticationState == .authenticated else {
                passkeyMessage = "Sign in with a confirmed Homey account before setting up a passkey."
                return
            }
            // Recheck the account on the server before opening Apple UI, including
            // when setup was requested from the optional post-login offer.
            guard await fetchAccountPasskeys(expectedID: expectedID) else { return }
            guard accountPasskeys.isEmpty else { return }
            _ = try await client.auth.registerPasskey(presentationAnchor: presentationAnchor)
            guard session?.user.id == expectedID, authenticationState == .authenticated else { return }
            dismissPasskeySetupOffer()
            passkeyMessage = "Passkey added to this Homey account."
            hasLoadedPasskeys = false
            _ = await fetchAccountPasskeys(expectedID: expectedID)
        } catch {
            guard session?.user.id == expectedID else { return }
            if !isPasskeyCancellation(error) {
                passkeyMessage = "Passkey setup could not be completed. Your existing sign-in method is still available."
            }
        }
    }

    func loadAccountPasskeys() async {
        guard authenticationState == .authenticated, let expectedID = session?.user.id,
              !Task.isCancelled else { return }
        guard !isPasskeyOperationInProgress, !isRefreshingPasskeys else {
            pendingPasskeyStatusRefresh = true
            return
        }
        pendingPasskeyStatusRefresh = false
        passkeyMessage = nil
        isRefreshingPasskeys = true
        defer {
            isRefreshingPasskeys = false
            resumePendingPasskeyStatusRefresh()
        }
        _ = await fetchAccountPasskeys(expectedID: expectedID)
    }

    /// Publish only server-confirmed data for the same account/authentication revision.
    /// Keep the last confirmed list on failure, but disable setup until refreshed.
    private func fetchAccountPasskeys(expectedID: UUID) async -> Bool {
        let revision = passkeyStatusRevision
        do {
            let passkeys = try await client.auth.listPasskeys()
            guard session?.user.id == expectedID, authenticationState == .authenticated,
                  passkeyStatusRevision == revision, !Task.isCancelled else { return false }
            accountPasskeys = passkeys.map {
                AccountPasskey(id: $0.id, name: $0.friendlyName ?? "Passkey", createdAt: $0.createdAt)
            }
            hasLoadedPasskeys = true
            return true
        } catch {
            guard session?.user.id == expectedID, passkeyStatusRevision == revision,
                  !Task.isCancelled else { return false }
            hasLoadedPasskeys = false
            passkeyMessage = "Could not refresh account passkeys. Refresh before setting up another passkey."
            return false
        }
    }

    func deleteAccountPasskey(id: String, accountID: UUID) async {
        guard authenticationState == .authenticated, session?.user.id == accountID,
              !isRefreshingPasskeys,
              accountPasskeys.contains(where: { $0.id == id }), beginPasskeyOperation() else { return }
        defer { endPasskeyOperation() }
        do {
            try await client.auth.deletePasskey(id: id)
            guard session?.user.id == accountID, authenticationState == .authenticated else { return }
            // Do not remove a cached row optimistically. A fresh server list decides
            // whether zero or more credentials remain, including synced credentials.
            hasLoadedPasskeys = false
            passkeyMessage = "Passkey removed from this Homey account."
            _ = await fetchAccountPasskeys(expectedID: accountID)
        } catch {
            guard session?.user.id == accountID else { return }
            passkeyMessage = "Could not remove this passkey. Try again."
        }
    }

    private func isPasskeyCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == ASAuthorizationError.errorDomain
            && error.code == ASAuthorizationError.canceled.rawValue
    }

    // MARK: - Auth State Changes

    private func subscribeToAuthStateChanges() {
        authStateChangesTask = Task { [weak self] in
            guard let self else { return }

            for await change in client.auth.authStateChanges {
                handleAuthStateChange(event: change.event, session: change.session)
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        guard !isLoading, !isPasskeyOperationInProgress, !handlingVerification else { return }
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            // RootView owns initial restoration; do not race it with the SDK snapshot.
            if event == .initialSession { return }
            authRevision &+= 1
            let revision = authRevision
            if let session {
                Task { await applySession(session, revision: revision) }
            } else {
                clearSession(state: verification.pending == nil ? .unauthenticated : .emailVerificationRequired)
            }
        case .signedOut, .userDeleted:
            authRevision &+= 1
            clearSession(state: verification.pending == nil ? .unauthenticated : .emailVerificationRequired,
                         resetDeviceProtection: true)
        case .passwordRecovery:
            // Only the isolated recovery client and PasswordRecoveryService handle this.
            break
        }
    }

    private func applySession(_ candidate: Session, revision: UInt64) async {
        guard revision == authRevision else { return }
        let alreadyReady = authenticationState == .authenticated && session?.user.id == candidate.user.id
        if !alreadyReady { authenticationState = .loading }
        do {
            let user = try await client.auth.user(jwt: candidate.accessToken)
            guard revision == authRevision, client.auth.currentSession?.user.id == candidate.user.id,
                  user.id == candidate.user.id else { return }
            guard EmailVerification.permitsHomeAccess(sessionID: candidate.user.id, userID: user.id,
                email: user.email, emailConfirmed: user.emailConfirmedAt != nil,
                anonymous: user.isAnonymous, expired: candidate.isExpired) else {
                session = candidate
                currentUser = nil
                verification.begin(email: user.email ?? "")
                authenticationState = .emailVerificationRequired
                return
            }
            if self.session?.user.id != user.id { clearPasskeyPresentationState() }
            session = candidate
            // Profile failures are recoverable, but never expose Home onboarding.
            let profile = try await initializeProfile(user: user, revision: revision)
            guard revision == authRevision, client.auth.currentSession?.user.id == user.id else { return }
            deviceUnlock.bindAccount(user.id)
            currentUser = profile
            verification.clear()
            authenticationState = .authenticated
            hasLoadedPasskeys = false
            passkeyStatusRevision += 1
            offerPasskeySetupIfNeeded()
        } catch {
            guard revision == authRevision else { return }
            currentUser = nil
            authenticationState = .profileInitializationRequired
            errorMessage = "We couldn't finish loading your account. Check your connection and try again, or return to Log In."
        }
    }

    func retryAccountInitialization() async {
        guard !isLoading else { return }
        await restoreSession()
    }

    private func initializeProfile(user: User, revision: UInt64) async throws -> UserProfile {
        // Retry one transient failure. Conditional column updates preserve values
        // written concurrently by another client and never touch unrelated columns.
        for attempt in 0...1 {
            do {
                var profile: UserProfile
                do {
                    profile = try await fetchProfile(userID: user.id, email: user.email ?? "")
                } catch ProfileInitializationFailure.missingProfile {
                    guard revision == authRevision else { throw CancellationError() }
                    // Repair a missing trigger row only with the verified user's session.
                    // Ignore conflicts so a concurrent trigger/client insert is preserved.
                    try await client.from("profiles").upsert(
                        UpdateProfilePayload(id: user.id, firstName: nil, lastName: nil, displayName: nil),
                        onConflict: "id", ignoreDuplicates: true
                    ).execute()
                    profile = try await fetchProfile(userID: user.id, email: user.email ?? "")
                }
                var existing: [String: String] = [:]
                existing["first_name"] = profile.firstName
                existing["last_name"] = profile.lastName
                existing["display_name"] = profile.displayName
                let metadata = user.userMetadata.compactMapValues { $0.stringValue }
                for repair in MissingProfileName.repairs(existing: existing, metadata: metadata) {
                    guard revision == authRevision else { throw CancellationError() }
                    let query = try client.from("profiles").update([repair.column: repair.value])
                        .eq("id", value: user.id.uuidString)
                    if let previous = repair.previousValue {
                        try await query.eq(repair.column, value: previous).execute()
                    } else {
                        try await query.is(repair.column, value: nil).execute()
                    }
                }
                profile = try await fetchProfile(userID: user.id, email: user.email ?? "")
                guard profile.id == user.id else { throw ProfileInitializationFailure.missingProfile }
                return profile
            } catch {
                if attempt == 1 { throw error }
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        throw ProfileInitializationFailure.missingProfile
    }

    private func clearSession(state: AuthenticationState, resetDeviceProtection: Bool = false) {
        if resetDeviceProtection {
            deviceUnlock.reset()
        } else {
            deviceUnlock.sessionBecameUnavailable()
        }
        clearPasskeyPresentationState()
        session = nil
        currentUser = nil
        authenticationState = state
    }

    private func isVerified(user: User) -> Bool {
        user.emailConfirmedAt != nil && !user.isAnonymous && user.email != nil
    }

    private func finishAuthenticationOperation() {
        isLoading = false
        drainVerificationCallback()
    }

    private func drainVerificationCallback() {
        guard !isLoading, !handlingVerification, !isPasskeyOperationInProgress, !verification.isBusy,
              let url = queuedVerificationURL else { return }
        queuedVerificationURL = nil
        Task { await handleEmailVerification(url) }
    }

    private func validate(email: String, password: String) -> Bool {
        guard PasswordRecovery.validEmail(EmailVerification.normalize(email)) else {
            errorMessage = "Enter a valid email address."
            return false
        }

        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return false
        }

        return true
    }

    private func fetchProfile(userID: UUID, email: String) async throws -> UserProfile {
        let profiles: [ProfileResponse] = try await client
            .from("profiles")
            .select("id, first_name, last_name, display_name, avatar_url")
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let profile = profiles.first, profile.id == userID else {
            throw ProfileInitializationFailure.missingProfile
        }

        return UserProfile(
            id: profile.id,
            email: email,
            firstName: profile.firstName,
            lastName: profile.lastName,
            displayName: profile.displayName,
            avatarURL: profile.avatarURL
        )
    }

    private func upsertProfile(userID: UUID, email: String, profile: NormalizedProfileInput) async throws {
        try await client
            .from("profiles")
            .upsert(
                UpdateProfilePayload(
                    id: userID,
                    firstName: profile.firstName,
                    lastName: profile.lastName,
                    displayName: profile.displayName
                )
            )
            .execute()
    }

    private func avatarObjectPath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/profile.jpg"
    }

    private func cacheBustedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "v" }
        queryItems.append(URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970))))
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private func updateAvatarURL(_ avatarURL: URL?) async throws {
        guard let currentUser else {
            return
        }

        try await client
            .from("profiles")
            .update(UpdateAvatarURLPayload(avatarURL: avatarURL))
            .eq("id", value: currentUser.id.uuidString)
            .execute()
    }

    private func authErrorMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.message
        }

        if let postgrestError = error as? PostgrestError {
            return postgrestError.message
        }

        if let httpError = error as? HTTPError {
            return httpError.errorDescription ?? "HTTP request failed."
        }

        return error.localizedDescription
    }

    private func avatarErrorMessage(for error: Error) -> String {
        let message = authErrorMessage(for: error).lowercased()

        if message.contains("permission") || message.contains("policy") || message.contains("rls") || message.contains("unauthorized") || message.contains("forbidden") {
            return "We could not upload your photo. Please check your connection and try again."
        }

        return "Unable to update your photo. Please try again."
    }

    private func logCompleteError(_ error: Error, context: String) {
        #if DEBUG
        print("Authentication operation failed: \(context)")
        #endif
    }

}

private struct NormalizedProfileInput {
    let firstName: String?
    let lastName: String?
    let displayName: String?

    init(firstName: String, lastName: String, displayName: String) {
        self.firstName = Self.normalized(firstName)
        self.lastName = Self.normalized(lastName)
        self.displayName = Self.normalized(displayName)
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ProfileResponse: Decodable {
    let id: UUID
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

private struct UpdateProfilePayload: Encodable {
    let id: UUID
    let firstName: String?
    let lastName: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
    }
}

private struct UpdateAvatarURLPayload: Encodable {
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let avatarURL {
            try container.encode(avatarURL.absoluteString, forKey: .avatarURL)
        } else {
            try container.encodeNil(forKey: .avatarURL)
        }
    }
}

struct AccountPasskey: Identifiable {
    let id: String
    let name: String
    let createdAt: Date
}

private enum ProfileInitializationFailure: Error { case missingProfile }
