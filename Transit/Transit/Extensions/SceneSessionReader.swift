#if os(iOS)
import SwiftUI
import UIKit

/// A view modifier that discovers the `UIWindowScene` session identifier
/// for the hosting window and stores it in the environment.
///
/// This bridges UIKit's per-scene identity into SwiftUI so views can
/// distinguish which window they belong to in iPadOS multi-window.
struct SceneSessionReader: ViewModifier {
    @State private var sceneSessionID: String?

    func body(content: Content) -> some View {
        content
            .environment(\.sceneSessionID, sceneSessionID)
            .background(
                SceneSessionResolver(sceneSessionID: $sceneSessionID)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
    }
}

extension View {
    /// Reads the hosting window's scene session identifier and makes it
    /// available via `@Environment(\.sceneSessionID)`.
    func readSceneSession() -> some View {
        modifier(SceneSessionReader())
    }
}

// MARK: - Environment Key

private struct SceneSessionIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var sceneSessionID: String? {
        get { self[SceneSessionIDKey.self] }
        set { self[SceneSessionIDKey.self] = newValue }
    }
}

// MARK: - UIKit Bridge

/// A zero-size UIView that resolves its window scene's session identifier
/// once it is moved into the view hierarchy.
private struct SceneSessionResolver: UIViewRepresentable {
    @Binding var sceneSessionID: String?

    func makeUIView(context: Context) -> SessionResolverView {
        let view = SessionResolverView()
        view.onSceneResolved = { id in
            sceneSessionID = id
        }
        return view
    }

    // Session ID is resolved imperatively in didMoveToWindow; no SwiftUI-driven updates needed.
    func updateUIView(_ uiView: SessionResolverView, context: Context) {}
}

/// Lightweight UIView that reports the window scene session ID
/// once it is added to a window.
private final class SessionResolverView: UIView {
    var onSceneResolved: ((String) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let sessionID = window?.windowScene?.session.persistentIdentifier {
            onSceneResolved?(sessionID)
        }
    }
}
#endif
