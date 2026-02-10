import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

extension Color {
    @MainActor
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            self = .black
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }

    @MainActor
    var hexString: String {
        #if canImport(UIKit) || canImport(AppKit)
        let platformColor = PlatformColor(self)

        #if canImport(AppKit)
        let converted = platformColor.usingColorSpace(.sRGB) ?? platformColor
        #else
        let converted = platformColor
        #endif

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let redInt = Int((red * 255.0).rounded())
        let greenInt = Int((green * 255.0).rounded())
        let blueInt = Int((blue * 255.0).rounded())
        return String(format: "%02X%02X%02X", redInt, greenInt, blueInt)
        #else
        return "000000"
        #endif
    }
}
