//
//  HomeyApp.swift
//  Homey
//
//  Created by Johnny Laroco on 7/21/26.
//

import SwiftUI
import SwiftData

@main
struct HomeyApp: App {
    @StateObject private var deviceUnlock: DeviceUnlockService
    @StateObject private var authenticationService: AuthenticationService
    @StateObject private var passwordRecovery = PasswordRecoveryService(auth: SupabasePasswordRecoveryAuth())
    @StateObject private var homeService = HomeService()

    init() {
        let deviceUnlock = DeviceUnlockService()
        _deviceUnlock = StateObject(wrappedValue: deviceUnlock)
        _authenticationService = StateObject(wrappedValue: AuthenticationService(deviceUnlock: deviceUnlock))
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(HomeyTheme.primary)
                .foregroundStyle(HomeyTheme.textPrimary)
                .preferredColorScheme(.light)
                .environmentObject(authenticationService)
                .environmentObject(deviceUnlock)
                .environmentObject(homeService)
                .environmentObject(passwordRecovery)
                .onOpenURL { url in
                    if PasswordRecovery.isCallback(url) {
                        Task { await passwordRecovery.handle(url) }
                    } else if EmailVerification.isCallback(url) {
                        Task { await authenticationService.handleEmailVerification(url) }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
