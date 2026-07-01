//
//  NodeLogoGeometry.swift
//  Node
//
//  Shared dot-based Node mark geometry for splash and onboarding setup.
//

import SwiftUI

struct NodeLogoDot: Identifiable {
    let id: Int
    let position: CGPoint
    let size: CGFloat
    let arcIndex: Int
}

enum NodeLogoGeometry {
    static func generateDots(center: CGPoint, size: CGFloat) -> [NodeLogoDot] {
        var dots: [NodeLogoDot] = []
        var index = 0
        let r = size * 0.42
        let stemLen = size * 0.35
        let dotSize: CGFloat = size * 0.042
        let spacing: CGFloat = size * 0.038

        struct ArcSegment {
            let stemStart: CGPoint
            let arcCenter: CGPoint
            let startAngle: CGFloat
            let endAngle: CGFloat
            let stemEnd: CGPoint
        }

        let cx = center.x
        let cy = center.y

        let segments: [ArcSegment] = [
            ArcSegment(
                stemStart: CGPoint(x: cx, y: cy - stemLen - r),
                arcCenter: CGPoint(x: cx + r, y: cy - r),
                startAngle: .pi,
                endAngle: .pi * 1.5,
                stemEnd: CGPoint(x: cx + r, y: cy - r - stemLen)
            ),
            ArcSegment(
                stemStart: CGPoint(x: cx + stemLen + r, y: cy),
                arcCenter: CGPoint(x: cx + r, y: cy + r),
                startAngle: .pi * 1.5,
                endAngle: .pi * 2,
                stemEnd: CGPoint(x: cx + r + stemLen, y: cy + r)
            ),
            ArcSegment(
                stemStart: CGPoint(x: cx, y: cy + stemLen + r),
                arcCenter: CGPoint(x: cx - r, y: cy + r),
                startAngle: 0,
                endAngle: .pi * 0.5,
                stemEnd: CGPoint(x: cx - r, y: cy + r + stemLen)
            ),
            ArcSegment(
                stemStart: CGPoint(x: cx - stemLen - r, y: cy),
                arcCenter: CGPoint(x: cx - r, y: cy - r),
                startAngle: .pi * 0.5,
                endAngle: .pi,
                stemEnd: CGPoint(x: cx - r - stemLen, y: cy - r)
            ),
        ]

        for (arcIdx, seg) in segments.enumerated() {
            let arcStartPoint = CGPoint(
                x: seg.arcCenter.x + r * cos(seg.startAngle),
                y: seg.arcCenter.y + r * sin(seg.startAngle)
            )
            for pt in pointsAlongLine(from: seg.stemStart, to: arcStartPoint, spacing: spacing) {
                dots.append(NodeLogoDot(id: index, position: pt, size: dotSize, arcIndex: arcIdx))
                index += 1
            }

            let arcLength = r * abs(seg.endAngle - seg.startAngle)
            let arcDotCount = Int(arcLength / spacing)
            for i in 0...arcDotCount {
                let t = CGFloat(i) / CGFloat(max(1, arcDotCount))
                let angle = seg.startAngle + t * (seg.endAngle - seg.startAngle)
                let pt = CGPoint(
                    x: seg.arcCenter.x + r * cos(angle),
                    y: seg.arcCenter.y + r * sin(angle)
                )
                dots.append(NodeLogoDot(id: index, position: pt, size: dotSize, arcIndex: arcIdx))
                index += 1
            }

            let arcEndPoint = CGPoint(
                x: seg.arcCenter.x + r * cos(seg.endAngle),
                y: seg.arcCenter.y + r * sin(seg.endAngle)
            )
            for pt in pointsAlongLine(from: arcEndPoint, to: seg.stemEnd, spacing: spacing) {
                dots.append(NodeLogoDot(id: index, position: pt, size: dotSize, arcIndex: arcIdx))
                index += 1
            }
        }

        return dots
    }

    private static func pointsAlongLine(from: CGPoint, to: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return [from] }
        let count = Int(length / spacing)
        guard count > 0 else { return [from] }
        var points: [CGPoint] = []
        for i in 0...count {
            let t = CGFloat(i) / CGFloat(count)
            points.append(CGPoint(x: from.x + dx * t, y: from.y + dy * t))
        }
        return points
    }
}

// MARK: - Reusable canvas

struct NodeLogoDotsCanvas: View {
    var center: CGPoint
    var side: CGFloat
    var progress: CGFloat
    var opacity: CGFloat = 1
    var glowPhase: CGFloat = 0
    var dotColor: Color = .white

    var body: some View {
        Canvas { context, _ in
            let dots = NodeLogoGeometry.generateDots(center: center, size: side)
            let totalDots = dots.count
            let visibleCount = Int(progress * CGFloat(totalDots))

            for (i, dot) in dots.enumerated() {
                guard i < visibleCount else { break }
                let dotProgress = CGFloat(i) / CGFloat(max(1, totalDots))
                let fadeIn = min(1.0, (progress - dotProgress) * CGFloat(totalDots) * 0.15)
                let glow = 1.0 + 0.18 * sin(glowPhase + CGFloat(i) * 0.12)
                let dotSize = dot.size * fadeIn * glow
                let rect = CGRect(
                    x: dot.position.x - dotSize / 2,
                    y: dot.position.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.opacity = Double(fadeIn * opacity)
                context.fill(Circle().path(in: rect), with: .color(dotColor))
            }
        }
    }
}
