import SwiftUI
import Testing
@testable import Transit

@MainActor
@Suite("AppTheme")
struct AppThemeTests {

    @Test("followSystem returns nil preferredColorScheme")
    func followSystemReturnsNil() {
        #expect(AppTheme.followSystem.preferredColorScheme == nil)
    }

    @Test("light returns .light preferredColorScheme")
    func lightReturnsLight() {
        #expect(AppTheme.light.preferredColorScheme == .light)
    }

    @Test("dark returns .dark preferredColorScheme")
    func darkReturnsDark() {
        #expect(AppTheme.dark.preferredColorScheme == .dark)
    }

    @Test("universal returns .light preferredColorScheme for consistent appearance")
    func universalReturnsLight() {
        #expect(AppTheme.universal.preferredColorScheme == .light)
    }

    // Verify that resolved theme is independent of system color scheme for explicit themes
    @Test("light theme resolves to .light regardless of system color scheme")
    func lightResolvesCorrectly() {
        #expect(AppTheme.light.resolved(with: .dark) == .light)
        #expect(AppTheme.light.resolved(with: .light) == .light)
    }

    @Test("dark theme resolves to .dark regardless of system color scheme")
    func darkResolvesCorrectly() {
        #expect(AppTheme.dark.resolved(with: .light) == .dark)
        #expect(AppTheme.dark.resolved(with: .dark) == .dark)
    }

    @Test("followSystem resolves based on system color scheme")
    func followSystemResolvesFromSystem() {
        #expect(AppTheme.followSystem.resolved(with: .light) == .light)
        #expect(AppTheme.followSystem.resolved(with: .dark) == .dark)
    }

    @Test("universal always resolves to .universal")
    func universalResolvesConsistently() {
        #expect(AppTheme.universal.resolved(with: .light) == .universal)
        #expect(AppTheme.universal.resolved(with: .dark) == .universal)
    }
}
