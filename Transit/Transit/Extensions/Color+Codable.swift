import SwiftUI

extension Color {
    /// Create a Color from a hex string (e.g., "#FF5733" or "FF5733").
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }

    /// Convert to a hex string for storage (e.g., "FF5733").
    /// Uses Color.Resolved to avoid UIColor/NSColor actor isolation issues.
    var hexString: String {
        let resolved = self.resolve(in: EnvironmentValues())
        let red = Int(max(0, min(1, resolved.red)) * 255)
        let green = Int(max(0, min(1, resolved.green)) * 255)
        let blue = Int(max(0, min(1, resolved.blue)) * 255)
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
