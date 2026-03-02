import SwiftUI

enum AppTheme: String, CaseIterable {
    case followSystem
    case universal
    case light
    case dark

    var displayName: String {
        switch self {
        case .followSystem: "Follow System"
        case .universal: "Universal"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .followSystem: nil
        case .universal: .light
        case .light: .light
        case .dark: .dark
        }
    }

    func resolved(with colorScheme: ColorScheme) -> ResolvedTheme {
        switch self {
        case .followSystem:
            colorScheme == .dark ? .dark : .light
        case .universal:
            .universal
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum ResolvedTheme {
    case universal
    case light
    case dark
}

private struct ResolvedThemeKey: EnvironmentKey {
    static let defaultValue: ResolvedTheme = .light
}

extension EnvironmentValues {
    var resolvedTheme: ResolvedTheme {
        get { self[ResolvedThemeKey.self] }
        set { self[ResolvedThemeKey.self] = newValue }
    }
}
