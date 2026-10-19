import SwiftUI

/// Perfect Fit's own palette: warm linen, oak and soft ink. Valid = sage, invalid = terracotta.
/// (Nothing from Cube Swipe's rhombi.)
struct Palette {
    let background: Color
    let backgroundDeep: Color
    let surface: Color
    let ink: Color
    let muted: Color
    let line: Color
    let accent: Color      // oak
    let sage: Color
    let terracotta: Color
    let star: Color
    let starEmpty: Color

    static let light = Palette(
        background: Color(hex: 0xF3EEE7), backgroundDeep: Color(hex: 0xE7DFD4), surface: Color(hex: 0xFBF8F4),
        ink: Color(hex: 0x2F2B27), muted: Color(hex: 0x8A8178), line: Color(hex: 0x2F2B27).opacity(0.10),
        accent: Color(hex: 0xA97B50), sage: Color(hex: 0x7E9A83), terracotta: Color(hex: 0xC27C62),
        star: Color(hex: 0xC9974E), starEmpty: Color(hex: 0x2F2B27).opacity(0.12))

    static let dark = Palette(
        background: Color(hex: 0x1D1B19), backgroundDeep: Color(hex: 0x141311), surface: Color(hex: 0x292623),
        ink: Color(hex: 0xEEE8DF), muted: Color(hex: 0x9C9389), line: Color.white.opacity(0.10),
        accent: Color(hex: 0xC99B6C), sage: Color(hex: 0x93AE97), terracotta: Color(hex: 0xD48D72),
        star: Color(hex: 0xDDB06A), starEmpty: Color.white.opacity(0.14))
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

/// Type: a quiet serif for titles, the system sans for everything else.
enum Typo {
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .light, design: .serif) }
    static func label(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .default) }
}
