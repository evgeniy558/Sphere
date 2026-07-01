import Combine
import QuartzCore
import SwiftUI

/// Converts live audio levels into a punchy 0…1 envelope for home-screen visuals.
@MainActor
final class MusicBeatPulseDriver: ObservableObject {
    @Published private(set) var punch: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var level: Float = 0
    private var smoothed: Float = 0
    private var punchDecay: Float = 0
    private var lastBeatPhase: Double = 0
    private var playbackTime: TimeInterval = 0
    private var beatEstimateBPM: Double = 118
    private var adaptiveBeatConfidence: Float = 0
    private var lastTransientTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var lastPlaybackPushHostTime: CFTimeInterval = 0
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        punch = 0
        level = 0
        smoothed = 0
        punchDecay = 0
        beatEstimateBPM = 118
        adaptiveBeatConfidence = 0
        lastTransientTime = 0
        lastFrameTime = 0
        lastPlaybackPushHostTime = 0
        ensureDisplayLink()
    }

    func stop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        punch = 0
        level = 0
        smoothed = 0
        punchDecay = 0
        adaptiveBeatConfidence = 0
        lastTransientTime = 0
        lastFrameTime = 0
        lastPlaybackPushHostTime = 0
    }

    func pushLevel(_ raw: Float) {
        level = min(max(raw, 0), 1)
    }

    func pushPlaybackTime(_ time: TimeInterval) {
        playbackTime = max(0, time)
        lastPlaybackPushHostTime = CACurrentMediaTime()
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        guard isRunning else { return }

        let now = CACurrentMediaTime()
        let dt = max(1.0 / 120.0, now - (lastFrameTime > 0 ? lastFrameTime : now - 1.0 / 60.0))
        lastFrameTime = now

        smoothed = smoothed * 0.72 + level * 0.28

        // Peak / transient emphasis (kick and snare hits).
        let transient = max(0, level - smoothed * 1.12 - 0.04)
        if transient > 0.08 {
            punchDecay = max(punchDecay, min(1, transient * 2.8))

            // Adaptive BPM from transients. Keeps visuals closer to actual rhythm.
            if lastTransientTime > 0 {
                let interval = now - lastTransientTime
                if interval > 0.24, interval < 0.95 {
                    let candidate = 60.0 / interval
                    beatEstimateBPM = beatEstimateBPM * 0.84 + candidate * 0.16
                    adaptiveBeatConfidence = min(1, adaptiveBeatConfidence + 0.10)
                }
            }
            lastTransientTime = now
        } else {
            adaptiveBeatConfidence = max(0, adaptiveBeatConfidence - Float(dt * 0.15))
        }

        let effectivePlaybackTime: TimeInterval = {
            guard lastPlaybackPushHostTime > 0 else { return playbackTime }
            let extrapolated = now - lastPlaybackPushHostTime
            return playbackTime + max(0, min(extrapolated, 0.45))
        }()

        // Pulse from estimated beat; fallback to reference BPM when confidence is low.
        let estimated = min(max(beatEstimateBPM, 78), 176)
        let fallbackBPM = 118.0
        let blend = min(max(Double(adaptiveBeatConfidence), 0), 1)
        let bpm = fallbackBPM * (1 - blend) + estimated * blend
        let beatPhase = (effectivePlaybackTime * (bpm / 60.0)).truncatingRemainder(dividingBy: 1)
        if beatPhase < lastBeatPhase {
            let beatHit: Float = level > 0.03 ? (0.55 + smoothed * 0.4) : 0.72
            punchDecay = max(punchDecay, beatHit)
        } else if beatPhase < 0.06 {
            punchDecay = max(punchDecay, 0.25 + smoothed * 0.3)
        }
        lastBeatPhase = beatPhase

        punchDecay *= 0.86
        let target = CGFloat(min(1, punchDecay + smoothed * 0.35))
        punch = punch * 0.55 + target * 0.45
    }
}
