import SwiftUI

struct BoardBackground: View {
    let theme: ResolvedTheme

    var body: some View {
        ZStack {
            baseColor

            // Layered radial gradients for a colourful mesh effect
            RadialGradient(
                colors: [blob1.opacity(blobOpacity), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 400
            )

            RadialGradient(
                colors: [blob2.opacity(blobOpacity), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 450
            )

            RadialGradient(
                colors: [blob3.opacity(blobOpacity), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 350
            )

            RadialGradient(
                colors: [blob4.opacity(blobOpacity), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Theme-Adapted Colours

    private var baseColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var blobOpacity: Double {
        switch theme {
        case .universal: 0.35
        case .light: 0.25
        case .dark: 0.40
        }
    }

    private var blob1: Color {
        switch theme {
        case .universal: .indigo
        case .light: Color(red: 0.65, green: 0.65, blue: 1.0)   // pastel indigo
        case .dark: Color(red: 0.25, green: 0.20, blue: 0.65)    // deep indigo
        }
    }

    private var blob2: Color {
        switch theme {
        case .universal: .pink
        case .light: Color(red: 1.0, green: 0.70, blue: 0.75)    // pastel rose
        case .dark: Color(red: 0.60, green: 0.15, blue: 0.30)    // deep rose
        }
    }

    private var blob3: Color {
        switch theme {
        case .universal: .teal
        case .light: Color(red: 0.60, green: 0.90, blue: 0.88)   // pastel teal
        case .dark: Color(red: 0.10, green: 0.40, blue: 0.45)    // deep teal
        }
    }

    private var blob4: Color {
        switch theme {
        case .universal: .purple
        case .light: Color(red: 0.80, green: 0.70, blue: 1.0)    // pastel violet
        case .dark: Color(red: 0.35, green: 0.15, blue: 0.55)    // deep violet
        }
    }
}
