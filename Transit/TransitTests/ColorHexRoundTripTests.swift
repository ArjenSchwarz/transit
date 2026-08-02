import SwiftUI
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ColorHexRoundTripTests {

    @Test func everyRedByteRoundTripsWithoutDarkening() {
        for byte in 0...255 {
            let expected = String(format: "%02X0000", byte)
            #expect(Color(hex: expected).hexString == expected, "Red byte \(byte) did not round-trip")
        }
    }

    @Test func everyGreenByteRoundTripsWithoutDarkening() {
        for byte in 0...255 {
            let expected = String(format: "00%02X00", byte)
            #expect(Color(hex: expected).hexString == expected, "Green byte \(byte) did not round-trip")
        }
    }

    @Test func everyBlueByteRoundTripsWithoutDarkening() {
        for byte in 0...255 {
            let expected = String(format: "0000%02X", byte)
            #expect(Color(hex: expected).hexString == expected, "Blue byte \(byte) did not round-trip")
        }
    }

    @Test func componentsJustBelowEveryByteBoundaryRoundToNearestByte() {
        for byte in 0...255 {
            let component = byte == 0
                ? 0.0
                : (Double(byte) / 255.0).nextDown

            #expect(
                Color(
                    Color.Resolved(
                        colorSpace: .sRGB,
                        red: Float(component), green: 0, blue: 0
                    )
                ).hexString == String(format: "%02X0000", byte),
                "Red boundary component \(byte) did not round-trip"
            )
            #expect(
                Color(
                    Color.Resolved(
                        colorSpace: .sRGB,
                        red: 0, green: Float(component), blue: 0
                    )
                ).hexString == String(format: "00%02X00", byte),
                "Green boundary component \(byte) did not round-trip"
            )
            #expect(
                Color(
                    Color.Resolved(
                        colorSpace: .sRGB,
                        red: 0, green: 0, blue: Float(component)
                    )
                ).hexString == String(format: "0000%02X", byte),
                "Blue boundary component \(byte) did not round-trip"
            )
        }
    }

    @Test func hexStringUsesUppercaseSixDigitRGBWithoutHashAndIgnoresAlpha() {
        let color = Color(
            .sRGB,
            red: 0x12 / 255.0,
            green: 0xAB / 255.0,
            blue: 0xCD / 255.0,
            opacity: 0.25
        )

        #expect(color.hexString == "12ABCD")
        #expect(color.hexString.hasPrefix("#") == false)
        #expect(color.hexString.count == 6)
    }
}
