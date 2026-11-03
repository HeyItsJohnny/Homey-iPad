import SwiftUI
import UIKit

/// A separate scene window covers presented sheets as well as the root hierarchy.
/// It is raised synchronously on deactivation, before UIKit captures a snapshot.
struct PrivacySnapshotShield: UIViewRepresentable {
    let deviceUnlock: DeviceUnlockService

    func makeUIView(context: Context) -> ShieldAnchor {
        ShieldAnchor(deviceUnlock: deviceUnlock)
    }

    func updateUIView(_ uiView: ShieldAnchor, context: Context) {}

    @MainActor
    final class ShieldAnchor: UIView {
        private let deviceUnlock: DeviceUnlockService
        private var shield: UIWindow?
        private var observers: [NSObjectProtocol] = []

        init(deviceUnlock: DeviceUnlockService) {
            self.deviceUnlock = deviceUnlock
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            shield?.isHidden = true
            shield = nil
            guard let scene = window?.windowScene else { return }
            deviceUnlock.sceneDidConnect()
            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            shield.isUserInteractionEnabled = false
            shield.rootViewController = UIHostingController(rootView:
                ZStack {
                    HomeyTheme.backgroundPrimary.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield").font(.system(size: 48))
                        Text("Homey").font(.largeTitle.bold())
                    }
                    .foregroundStyle(HomeyTheme.primary)
                }.preferredColorScheme(.light)
            )
            self.shield = shield
            observe(UIScene.willDeactivateNotification, scene: scene) { anchor in
                anchor.deviceUnlock.sceneWillDeactivate()
                anchor.updateShield(forceCover: true)
            }
            observe(UIScene.didEnterBackgroundNotification, scene: scene) { anchor in
                anchor.deviceUnlock.sceneDidEnterBackground()
                anchor.updateShield(forceCover: true)
            }
            observe(UIScene.didActivateNotification, scene: scene) { anchor in
                anchor.deviceUnlock.sceneDidActivate()
                anchor.updateShield(forceCover: false)
            }
            updateShield(forceCover: scene.activationState != .foregroundActive)
            if scene.activationState == .foregroundActive { deviceUnlock.sceneDidActivate() }
        }

        private func observe(_ name: Notification.Name, scene: UIWindowScene, action: @escaping (ShieldAnchor) -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: scene, queue: .main) { [weak self] _ in
                // UIScene lifecycle notifications are delivered on the main thread.
                MainActor.assumeIsolated {
                    if let self { action(self) }
                }
            })
        }

        private func updateShield(forceCover: Bool) {
            // Snapshot privacy also protects login fields when device unlock is off.
            // Foreground household access remains unchanged when the setting is off.
            shield?.isHidden = !forceCover
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
