import Combine
import SwiftUI
import UIKit

/// Resolve the initiating view's actual window, never another iPad scene's key window.
@MainActor
final class PasskeyWindowAnchor: ObservableObject {
    weak var window: UIWindow?
}

struct PasskeyPresentationAnchor: UIViewRepresentable {
    let anchor: PasskeyWindowAnchor

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(anchor: anchor)
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        private let anchor: PasskeyWindowAnchor

        init(anchor: PasskeyWindowAnchor) {
            self.anchor = anchor
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            anchor.window = window
        }
    }
}
