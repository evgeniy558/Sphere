import SwiftUI

enum NodeDesignStyle {
    static let cardCornerRadius: CGFloat = 18
    static let sectionCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 16
    static let glassStrokePrimary = Color.white.opacity(0.24)
    static let glassStrokeSecondary = Color.white.opacity(0.14)
    static let glassTintSelected = Color.white.opacity(0.18)
    static let glassTintIdle = Color.white.opacity(0.07)

    static func baseBackground(for isDarkMode: Bool) -> Color {
        isDarkMode ? Color.black : Color(.systemGroupedBackground)
    }

    static func primaryText(for isDarkMode: Bool) -> Color {
        isDarkMode ? .white : .primary
    }

    static func secondaryText(for isDarkMode: Bool) -> Color {
        isDarkMode ? Color.white.opacity(0.68) : .secondary
    }

    /// Tile palette inspired by Brink (purple/blue/teal/red/yellow/green/orange/brown/pink…).
    /// Used for genre cards, library quick tiles, mood cards.
    static let tilePalette: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.96), // purple
        Color(red: 0.36, green: 0.42, blue: 0.96), // indigo blue
        Color(red: 0.20, green: 0.74, blue: 0.78), // teal
        Color(red: 0.94, green: 0.34, blue: 0.40), // red
        Color(red: 0.96, green: 0.74, blue: 0.18), // yellow
        Color(red: 0.20, green: 0.74, blue: 0.40), // green
        Color(red: 0.95, green: 0.50, blue: 0.18), // orange
        Color(red: 0.55, green: 0.42, blue: 0.36), // brown
        Color(red: 0.91, green: 0.30, blue: 0.61), // pink
        Color(red: 0.32, green: 0.58, blue: 0.95), // sky
        Color(red: 0.62, green: 0.36, blue: 0.78), // violet
        Color(red: 0.18, green: 0.55, blue: 0.55), // sea
    ]

    /// Stable color from string (genre name, library tile, etc.).
    static func tileColor(for key: String) -> Color {
        var hash: UInt32 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return tilePalette[Int(hash % UInt32(tilePalette.count))]
    }
}

/// Defers building `Content` until the view is actually shown.
/// Critical for `NavigationLink(destination:)`, whose destination is otherwise
/// constructed eagerly — touching singletons/stores while the parent list renders.
struct LazyView<Content: View>: View {
    private let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

/// Monospaced "Nothing-style" helper for the Node logo and subtle accents.
extension Font {
    static func nodeMono(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Smooth, harmonious moving backdrop.
///
/// Instead of hard-edged radial blobs (which read as blocky color regions), this
/// interpolates between two color palettes every frame and renders a heavily
/// blurred angular gradient that slowly rotates — the AnimatableGradients
/// approach (interpolate start→end colors by an animated completion value).
struct NodeHarmonyBackground: View {
    let isDarkMode: Bool
    let accent: Color
    var intensity: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var startColors: [Color] {
        [
            accent.opacity(0.28),
            Color(red: 0.12, green: 0.18, blue: 0.42),
            Color(red: 0.22, green: 0.10, blue: 0.34),
            accent.opacity(0.18),
        ]
    }
    private var endColors: [Color] {
        [
            Color(red: 0.18, green: 0.08, blue: 0.30),
            accent.opacity(0.22),
            Color(red: 0.08, green: 0.16, blue: 0.36),
            Color(red: 0.14, green: 0.06, blue: 0.22),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if reduceMotion {
                gradientLayer(t: 0.5, degrees: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let t = (sin(time * 0.14) + 1) / 2
                    let degrees = time * 6
                    gradientLayer(t: t, degrees: degrees)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func gradientLayer(t: Double, degrees: Double) -> some View {
        let cols = zip(startColors, endColors).map { NodeColorMix.lerp($0, $1, CGFloat(t)) }
        let ring = cols + [cols.first ?? accent.opacity(0.2)]
        return AngularGradient(
            gradient: Gradient(colors: ring),
            center: .center,
            angle: .degrees(degrees)
        )
        .scaleEffect(1.45)
        .blur(radius: 58)
        .opacity((isDarkMode ? 0.24 : 0.18) * intensity)
        .ignoresSafeArea()
    }
}

/// Linear color interpolation in sRGB for animatable gradients.
enum NodeColorMix {
    static func lerp(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let p = min(1, max(0, t))
        return Color(
            red: Double(ar + (br - ar) * p),
            green: Double(ag + (bg - ag) * p),
            blue: Double(ab + (bb - ab) * p),
            opacity: Double(aa + (ba - aa) * p)
        )
    }
}
