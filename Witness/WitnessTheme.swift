import SwiftUI

// MARK: - Hex color convenience
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

// MARK: - Recipe C tokens (the law)
enum WT {
    // Surfaces
    static let canvas   = Color(hex: 0xf5f1e8)   // cream — app background
    static let paper    = Color(hex: 0xfaf7f0)   // raised paper, companion bubbles
    static let ink      = Color(hex: 0x102023)   // primary text
    static let card     = Color.white.opacity(0.82)

    // Primary / interactive
    static let teal     = Color(hex: 0x0b6b68)
    static let tealDeep = Color(hex: 0x0b4f4d)

    // Accent (rare — see color-vision caution)
    static let gold     = Color(hex: 0xd4a23a)
    static let goldDeep = Color(hex: 0x8a641b)

    // Hairlines & text tints
    static let hairline = Color(hex: 0x102023, alpha: 0.06)
    static let ink55    = Color(hex: 0x102023, alpha: 0.55)
    static let ink40    = Color(hex: 0x102023, alpha: 0.40)

    // Semantic state ONLY (never decorative)
    static let danger   = Color(hex: 0xb4332b)
    static let success  = Color(hex: 0x2e7d5b)

    // Radii
    static let rCard: CGFloat = 24
    static let rCtl:  CGFloat = 16
}

// MARK: - The ONE shadow. Nothing else casts; inner panels are flat.
extension View {
    func witnessCardShadow() -> some View {
        self
            .shadow(color: Color(hex: 0x102023, alpha: 0.03), radius: 1,  y: 1)
            .shadow(color: Color(hex: 0x102023, alpha: 0.10), radius: 24, y: 14)
    }
}

// MARK: - Display serif (Playfair Display)
// Only the SemiBold weight (600) is bundled right now, so every serif call uses it.
// The string below is the font's PostScript name — NO ".ttf" here (that goes only in
// the Info "Fonts provided by application" entry).
extension Font {
    static func serif(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplay-SemiBold", size: size)
    }
}
