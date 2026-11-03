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
    @Published private(set) var passkeyMessage: String?
    @Published private(set) var shouldOfferPasskeySetup = false

    // MARK: - Private Properties

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
        guard !isPasskeyOperationInProgress else { return }
        authenticationState = .loading
        isLoading = true
        clearError()

        do {
            let restoredSession = try await client.auth.session
            applySession(restoredSession)
            await refreshCurrentUserProfile()
        } catch {
            logCompleteError(error, context: "RESTORE SESSION FAILED")
            clearSession(state: .unauthenticated)
        }

        isLoading = false
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
            applySession(restored)
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
        guard !isPasskeyOperationInProgress else { return }
        isLoading = true
        clearError()

        do {
            let refreshedSession = try await client.auth.refreshSession()
            applySession(refreshedSession)
            offerPasskeySetupIfNeeded()
        } catch {
            logCompleteError(error, context: "REFRESH SESSION FAILED")
            errorMessage = authErrorMessage(for: error)
            authenticationState = .emailVerificationRequired
        }

        isLoading = false
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async {
        guard !isLoading, !isPasskeyOperationInProgress else { return }
        guard validate(email: email, password: password) else {
            return
        }

        isLoading = true
        clearError()

        do {
            let signedInSession = try await client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            applySession(signedInSession)
            offerPasskeySetupIfNeeded()
            await refreshCurrentUserProfile()
        } catch {
            logCompleteError(error, context: "SIGN IN FAILED")
            clearSession(state: .unauthenticated)
            errorMessage = authErrorMessage(for: error)
        }

        isLoading = false
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, displayName: String) async {
        guard !isLoading, !isPasskeyOperationInProgress else { return }
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

        if client.auth.currentSession != nil {
            do {
                try await client.auth.signOut()
                clearSession(state: .unauthenticated)
            } catch {
                logCompleteError(error, context: "CLEAR CACHED SESSION BEFORE SIGNUP FAILED")
            }
        }

        do {
            #if DEBUG
            print("========== SIGNUP STARTED ==========")
            print("email: \(email.trimmingCharacters(in: .whitespacesAndNewlines))")
            print("===================================")
            #endif

            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            do {
                try await upsertProfile(
                    userID: response.user.id,
                    email: response.user.email ?? email.trimmingCharacters(in: .whitespacesAndNewlines),
                    profile: normalizedProfile
                )
            } catch {
                logCompleteError(error, context: "SIGNUP PROFILE SAVE FAILED")
                errorMessage = "Your account was created, but your profile information could not be saved. Please try again."
                isLoading = false
                return
            }

            if let signUpSession = response.session {
                applySession(signUpSession)
                offerPasskeySetupIfNeeded()
                await refreshCurrentUserProfile()
            } else {
                session = nil
                currentUser = UserProfile(
                    id: response.user.id,
                    email: response.user.email ?? email.trimmingCharacters(in: .whitespacesAndNewlines),
                    firstName: normalizedProfile.firstName,
                    lastName: normalizedProfile.lastName,
                    displayName: normalizedProfile.displayName,
                    avatarURL: nil
                )
                authenticationState = .emailVerificationRequired
            }
        } catch {
            logCompleteError(error, context: "SIGNUP FAILED")
            clearSession(state: .unauthenticated)
            errorMessage = authErrorMessage(for: error)
        }

        isLoading = false
    }

    func signOut() async {
        guard !isPasskeyOperationInProgress else { return }
        isLoading = true
        clearError()

        do {
            try await client.auth.signOut()
        } catch {
            logCompleteError(error, context: "SIGN OUT FAILED")
            errorMessage = authErrorMessage(for: error)
        }

        clearSession(state: .unauthenticated, resetDeviceProtection: true)
        isLoading = false
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard !isPasskeyOperationInProgress else { return false }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address."
            return false
        }

        isLoading = true
        clearError()

        do {
            try await client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isLoading = false
            return true
        } catch {
            logCompleteError(error, context: "PASSWORD RESET FAILED")
            errorMessage = authErrorMessage(for: error)
            isLoading = false
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshCurrentUserProfile() async {
        guard let currentUser else {
            return
        }

        do {
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
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
        defer { isLoading = false }

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
    }

    private func beginPasskeyOperation(anchor: UIWindow? = nil, requiresAnchor: Bool = false) -> Bool {
        guard !isPasskeyOperationInProgress, !isLoading else { return false }
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
        isLoading = false
        deviceUnlock.endAccountAuthentication()
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
            applySession(signedInSession)
            if authenticationState == .authenticated { dismissPasskeySetupOffer() }
            await refreshCurrentUserProfile()
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
            _ = try await client.auth.registerPasskey(presentationAnchor: presentationAnchor)
            guard session?.user.id == expectedID, authenticationState == .authenticated else { return }
            dismissPasskeySetupOffer()
            passkeyMessage = "Passkey added to this Homey account."
            await fetchAccountPasskeys(expectedID: expectedID)
        } catch {
            guard session?.user.id == expectedID else { return }
            if !isPasskeyCancellation(error) {
                passkeyMessage = "Passkey setup could not be completed. Your existing sign-in method is still available."
            }
        }
    }

    func loadAccountPasskeys() async {
        guard authenticationState == .authenticated, let expectedID = session?.user.id,
              beginPasskeyOperation() else { return }
        defer { endPasskeyOperation() }
        await fetchAccountPasskeys(expectedID: expectedID)
    }

    private func fetchAccountPasskeys(expectedID: UUID) async {
        do {
            let passkeys = try await client.auth.listPasskeys()
            guard session?.user.id == expectedID, authenticationState == .authenticated else { return }
            accountPasskeys = passkeys.map {
                AccountPasskey(id: $0.id, name: $0.friendlyName ?? "Passkey", createdAt: $0.createdAt)
            }
            hasLoadedPasskeys = true
        } catch {
            guard session?.user.id == expectedID else { return }
            hasLoadedPasskeys = false
            passkeyMessage = "Could not load account passkeys. Refresh to try again."
        }
    }

    func deleteAccountPasskey(id: String) async {
        guard authenticationState == .authenticated, let expectedID = session?.user.id,
              accountPasskeys.contains(where: { $0.id == id }), beginPasskeyOperation() else { return }
        defer { endPasskeyOperation() }
        do {
            try await client.auth.deletePasskey(id: id)
            guard session?.user.id == expectedID else { return }
            accountPasskeys.removeAll { $0.id == id }
            passkeyMessage = "Passkey removed from this Homey account."
        } catch {
            guard session?.user.id == expectedID else { return }
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
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session {
                applySession(session)
                Task {
                    await refreshCurrentUserProfile()
                }
            } else {
                clearSession(state: .unauthenticated)
            }
        case .signedOut, .userDeleted:
            clearSession(state: .unauthenticated, resetDeviceProtection: true)
        case .passwordRecovery:
            if let session {
                applySession(session)
            }
        }
    }

    // MARK: - State Helpers

    private func applySession(_ session: Session) {
        if self.session?.user.id != session.user.id {
            clearPasskeyPresentationState()
        }
        deviceUnlock.bindAccount(session.user.id)
        self.session = session
        currentUser = UserProfile(user: session.user)
        authenticationState = isVerified(user: session.user) ? .authenticated : .emailVerificationRequired
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
        user.emailConfirmedAt != nil || user.confirmedAt != nil
    }

    private func validate(email: String, password: String) -> Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address."
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

        guard let profile = profiles.first else {
            return UserProfile(id: userID, email: email)
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
        print("========== \(context) ==========")
        print(String(reflecting: error))
        print(error.localizedDescription)

        if let authError = error as? AuthError {
            print("AuthError.code: \(authError.errorCode)")
            print("AuthError.message: \(authError.message)")
            print("AuthError.details: <not exposed by Supabase AuthError>")
            print("AuthError.hint: <not exposed by Supabase AuthError>")

            switch authError {
            case .api(let message, let errorCode, let underlyingData, let underlyingResponse):
                print("AuthError.api.message: \(message)")
                print("AuthError.api.code: \(errorCode)")
                print("AuthError.api.statusCode: \(underlyingResponse.statusCode)")
                print("AuthError.api.responseBody: \(String(data: underlyingData, encoding: .utf8) ?? "<non-UTF8 response body>")")
            case .weakPassword(let message, let reasons):
                print("AuthError.weakPassword.message: \(message)")
                print("AuthError.weakPassword.reasons: \(reasons)")
            case .pkceGrantCodeExchange(let message, let error, let code):
                print("AuthError.pkceGrantCodeExchange.message: \(message)")
                print("AuthError.pkceGrantCodeExchange.error: \(error ?? "")")
                print("AuthError.pkceGrantCodeExchange.code: \(code ?? "")")
            case .implicitGrantRedirect(let message):
                print("AuthError.implicitGrantRedirect.message: \(message)")
            case .jwtVerificationFailed(let message):
                print("AuthError.jwtVerificationFailed.message: \(message)")
            case .sessionMissing:
                print("AuthError.sessionMissing")
            default:
                print("AuthError: \(authError)")
            }
        }

        if let postgrestError = error as? PostgrestError {
            print("PostgrestError.code: \(postgrestError.code ?? "")")
            print("PostgrestError.message: \(postgrestError.message)")
            print("PostgrestError.details: \(postgrestError.detail ?? "")")
            print("PostgrestError.hint: \(postgrestError.hint ?? "")")
            print("PostgrestError.statusCode: <not exposed by PostgrestError>")
            print("PostgrestError.responseBody: <not exposed by PostgrestError>")
        }

        if let httpError = error as? HTTPError {
            print("HTTPError.statusCode: \(httpError.response.statusCode)")
            print("HTTPError.responseBody: \(String(data: httpError.data, encoding: .utf8) ?? "<non-UTF8 response body>")")
        }

        print("===================================")
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
