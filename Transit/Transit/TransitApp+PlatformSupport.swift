import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - macOS Commands

#if os(macOS)
struct NewTaskCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                openWindow(id: "add-task")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

struct SettingsCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif

// MARK: - Quick Action App Delegate

#if os(iOS)
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    var quickActionService: QuickActionService?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem, shortcut.type == QuickActionService.newTaskActionType {
            quickActionService?.requestNewTask(
                forSceneSession: connectingSceneSession.persistentIdentifier
            )
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // Always register scene delegate so warm-start quick actions are delivered
        // via windowScene(_:performActionFor:completionHandler:).
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = shortcutItem.type == QuickActionService.newTaskActionType
        if handled, let appDelegate = UIApplication.shared.delegate as? QuickActionAppDelegate {
            appDelegate.quickActionService?.requestNewTask(
                forSceneSession: windowScene.session.persistentIdentifier
            )
        }
        completionHandler(handled)
    }
}
#endif
