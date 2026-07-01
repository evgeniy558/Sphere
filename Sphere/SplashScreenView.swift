import SwiftUI

/// Key for "splash already shown" flag (used in SphereApp via @AppStorage).
let kNodeHasSeenLaunchSplash = "SphereHasSeenLaunchSplash"

struct SplashScreenView: View {
    let onFinish: () -> Void

    @State private var contentOpacity: CGFloat = 1
    @State private var imageScale: CGFloat = 0.94

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.44
                let cornerRadius = side * 0.24
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                ZStack {
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.03),
                            .clear
                        ],
                        center: .center,
                        startRadius: side * 0.2,
                        endRadius: side * 0.95
                    )
                    .position(center)

                    Image("NodeSplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                        .overlay {
                            movingContourStroke(cornerRadius: cornerRadius)
                        }
                        .shadow(color: .white.opacity(0.08), radius: side * 0.16, x: 0, y: 0)
                        .position(center)
                        .scaleEffect(imageScale)
                        .opacity(contentOpacity)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                imageScale = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
                withAnimation(.easeOut(duration: 0.45)) {
                    contentOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                onFinish()
            }
        }
    }

    @ViewBuilder
    private func movingContourStroke(cornerRadius: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate * 0.72
            let phase = CGFloat(cycle.truncatingRemainder(dividingBy: 1))
            let easedPhase = nonlinearPhase(phase)
            let segment = 0.18 + 0.08 * CGFloat((sin(cycle * .pi * 2) + 1) * 0.5)
            contourSegment(cornerRadius: cornerRadius, start: easedPhase, segment: segment)
        }
    }

    /// Non-linear movement: accelerates and decelerates during each loop.
    private func nonlinearPhase(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4 * t * t * t
        }
        let p = -2 * t + 2
        return 1 - (p * p * p) / 2
    }

    @ViewBuilder
    private func contourSegment(cornerRadius: CGFloat, start: CGFloat, segment: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let end = start + segment
        let style = StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)

        if end <= 1 {
            shape
                .trim(from: start, to: end)
                .stroke(Color.white.opacity(0.98), style: style)
                .shadow(color: .white.opacity(0.5), radius: 3, x: 0, y: 0)
        } else {
            ZStack {
                shape
                    .trim(from: start, to: 1)
                    .stroke(Color.white.opacity(0.98), style: style)
                shape
                    .trim(from: 0, to: end - 1)
                    .stroke(Color.white.opacity(0.98), style: style)
            }
            .shadow(color: .white.opacity(0.5), radius: 3, x: 0, y: 0)
        }
    }
}
