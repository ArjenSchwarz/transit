//
//  Color+Codable.swift
//  Transit
//
//  Hex string conversion for Color to enable CloudKit/SwiftData storage.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Convert Color to hex string for storage.
    /// Format: #RRGGBB (e.g., #FF5733)
    var hexString: String {
        #if canImport(UIKit)
        let nativeColor = UIColor(self)
        #elseif canImport(AppKit)
        let nativeColor = NSColor(self)
        #endif

        guard let components = nativeColor.cgColor.components,
              components.count >= 3 else {
            return "#000000"
        }

        let red = Int(components[0] * 255.0)
        let green = Int(components[1] * 255.0)
        let blue = Int(components[2] * 255.0)

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Initialize Color from hex string.
    /// Supports formats: #RRGGBB, RRGGBB
    /// Returns black if parsing fails.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red, green, blue: Double
        switch hex.count {
        case 6: // RGB
            red = Double((int >> 16) & 0xFF) / 255.0
            green = Double((int >> 8) & 0xFF) / 255.0
            blue = Double(int & 0xFF) / 255.0
        default:
            red = 0
            green = 0
            blue = 0
        }

        self.init(red: red, green: green, blue: blue)
    }
}
