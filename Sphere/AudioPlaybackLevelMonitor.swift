import AVFoundation
import Accelerate

/// Live loudness for home-screen beat visuals (local engine playback).
enum AudioPlaybackLevelMonitor {
    static func attachEngine(_ engine: SphereAudioEngine, handler: @escaping (Float) -> Void) {
        engine.onOutputLevel = handler
        engine.startOutputLevelMonitoring()
    }

    static func detachEngine(_ engine: SphereAudioEngine) {
        engine.stopOutputLevelMonitoring()
    }
}
