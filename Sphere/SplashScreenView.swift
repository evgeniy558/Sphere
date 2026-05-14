//
//  SplashScreenView.swift
//  Sphere
//
//  Animated dot-based splash: renders the Sphere logo as particles that appear
//  sequentially along the four curved arcs, hold briefly, then fade out.
//

import SwiftUI

/// Key for "splash already shown" flag (used in SphereApp via @AppStorage).
let kSphereHasSeenLaunchSplash = "SphereHasSeenLaunchSplash"

struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: String = ""
    let onFinish: () -> Void

    @State private var animationProgress: CGFloat = 0
    @State private var opacity: CGFloat = 1
    @State private var glowPhase: CGFloat = 0

    private var isDark: Bool {
        switch preferredColorSchemeRaw {
        case "dark": return true
        case "light": return false
        default: return colorScheme == .dark
        }
    }

    private var dotColor: Color { isDark ? .white : .black }
    private var bgColor: Color { isDark ? .black : .white }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.45
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, size in
                    let dots = generateLogoDots(center: center, size: side)
                    let totalDots = dots.count
                    let visibleCount = Int(animationProgress * CGFloat(totalDots))

                    for (i, dot) in dots.enumerated() {
                        guard i < visibleCount else { break }
                        let dotProgress = CGFloat(i) / CGFloat(totalDots)
                        let fadeIn = min(1.0, (animationProgress - dotProgress) * CGFloat(totalDots) * 0.15)
                        let glow = 1.0 + 0.15 * sin(glowPhase + CGFloat(i) * 0.12)
                        let dotSize = dot.size * fadeIn * glow

                        let rect = CGRect(
                            x: dot.position.x - dotSize / 2,
                            y: dot.position.y - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )

                        context.opacity = Double(fadeIn * opacity)
                        context.fill(
                            Circle().path(in: rect),
                            with: .color(dotColor)
                        )
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            // Phase 1: Dots appear sequentially (1.2s)
            withAnimation(.easeInOut(duration: 1.2)) {
                animationProgress = 1.0
            }

            // Gentle glow pulse
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                glowPhase = .pi * 2
            }

            // Phase 2: Hold (0.6s) then fade out (0.4s) then finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onFinish()
            }
        }
    }
}

// MARK: - Logo Geometry

private struct LogoDot {
    let position: CGPoint
    let size: CGFloat
    let arcIndex: Int
}

/// Generates dots along the 4 arcs of the Sphere logo.
/// The logo is a cross/sphere shape: 4 quarter-circle arcs with connecting stems,
/// forming an interlocking pattern of curves and gaps.
private func generateLogoDots(center: CGPoint, size: CGFloat) -> [LogoDot] {
    var dots: [LogoDot] = []
    let r = size * 0.42   // radius for the quarter-circle arcs
    let stemLen = size * 0.35  // length of straight stem extensions
    let dotSize: CGFloat = size * 0.042
    let spacing: CGFloat = size * 0.038

    // The logo has 4 segments, each is a straight stem -> quarter arc -> straight stem.
    // They interlock to form the cross/sphere shape.

    struct ArcSegment {
        let stemStart: CGPoint
        let arcCenter: CGPoint
        let startAngle: CGFloat  // radians
        let endAngle: CGFloat
        let stemEnd: CGPoint
        let clockwise: Bool
    }

    let cx = center.x
    let cy = center.y

    // Top-left arc (opens right-down)
    let segments: [ArcSegment] = [
        // Top segment: stem goes up, arc curves right
        ArcSegment(
            stemStart: CGPoint(x: cx, y: cy - stemLen - r),
            arcCenter: CGPoint(x: cx + r, y: cy - r),
            startAngle: .pi,
            endAngle: .pi * 1.5,
            stemEnd: CGPoint(x: cx + r, y: cy - r - stemLen),
            clockwise: false
        ),
        // Right segment: stem goes right, arc curves down
        ArcSegment(
            stemStart: CGPoint(x: cx + stemLen + r, y: cy),
            arcCenter: CGPoint(x: cx + r, y: cy + r),
            startAngle: .pi * 1.5,
            endAngle: .pi * 2,
            stemEnd: CGPoint(x: cx + r + stemLen, y: cy + r),
            clockwise: false
        ),
        // Bottom segment: stem goes down, arc curves left
        ArcSegment(
            stemStart: CGPoint(x: cx, y: cy + stemLen + r),
            arcCenter: CGPoint(x: cx - r, y: cy + r),
            startAngle: 0,
            endAngle: .pi * 0.5,
            stemEnd: CGPoint(x: cx - r, y: cy + r + stemLen),
            clockwise: false
        ),
        // Left segment: stem goes left, arc curves up
        ArcSegment(
            stemStart: CGPoint(x: cx - stemLen - r, y: cy),
            arcCenter: CGPoint(x: cx - r, y: cy - r),
            startAngle: .pi * 0.5,
            endAngle: .pi,
            stemEnd: CGPoint(x: cx - r - stemLen, y: cy - r),
            clockwise: false
        ),
    ]

    for (arcIdx, seg) in segments.enumerated() {
        // 1. Stem from start point to arc beginning
        let arcStartPoint = CGPoint(
            x: seg.arcCenter.x + r * cos(seg.startAngle),
            y: seg.arcCenter.y + r * sin(seg.startAngle)
        )
        let stemDots1 = pointsAlongLine(
            from: seg.stemStart,
            to: arcStartPoint,
            spacing: spacing
        )
        for pt in stemDots1 {
            dots.append(LogoDot(position: pt, size: dotSize, arcIndex: arcIdx))
        }

        // 2. Quarter arc
        let arcLength = r * abs(seg.endAngle - seg.startAngle)
        let arcDotCount = Int(arcLength / spacing)
        for i in 0...arcDotCount {
            let t = CGFloat(i) / CGFloat(max(1, arcDotCount))
            let angle = seg.startAngle + t * (seg.endAngle - seg.startAngle)
            let pt = CGPoint(
                x: seg.arcCenter.x + r * cos(angle),
                y: seg.arcCenter.y + r * sin(angle)
            )
            dots.append(LogoDot(position: pt, size: dotSize, arcIndex: arcIdx))
        }

        // 3. Stem from arc end to end point
        let arcEndPoint = CGPoint(
            x: seg.arcCenter.x + r * cos(seg.endAngle),
            y: seg.arcCenter.y + r * sin(seg.endAngle)
        )
        let stemDots2 = pointsAlongLine(
            from: arcEndPoint,
            to: seg.stemEnd,
            spacing: spacing
        )
        for pt in stemDots2 {
            dots.append(LogoDot(position: pt, size: dotSize, arcIndex: arcIdx))
        }
    }

    return dots
}

/// Generates evenly-spaced points along a straight line.
private func pointsAlongLine(from: CGPoint, to: CGPoint, spacing: CGFloat) -> [CGPoint] {
    let dx = to.x - from.x
    let dy = to.y - from.y
    let length = sqrt(dx * dx + dy * dy)
    guard length > 0 else { return [from] }

    let count = Int(length / spacing)
    guard count > 0 else { return [from] }

    var points: [CGPoint] = []
    for i in 0...count {
        let t = CGFloat(i) / CGFloat(count)
        points.append(CGPoint(
            x: from.x + dx * t,
            y: from.y + dy * t
        ))
    }
    return points
}
