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
        let red = roundedByte(from: resolved.red)
        let green = roundedByte(from: resolved.green)
        let blue = roundedByte(from: resolved.blue)
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    /// Quantize a resolved sRGB component to its nearest 8-bit channel value.
    /// Resolved components can be a fraction below an exact byte boundary due
    /// to platform color-space conversion, so truncation would darken colors.
    private func roundedByte(from component: Float) -> Int {
        guard component.isFinite else { return 0 }
        let clamped = max(0, min(1, component))
        return Int((clamped * 255).rounded())
    }
}
