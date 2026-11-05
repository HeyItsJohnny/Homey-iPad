enum AuthenticationState {
    case loading
    case unauthenticated
    case emailVerificationRequired
    case profileInitializationRequired
    case authenticated
}
