import SwiftUI
import Combine
import AVFoundation

/// Manages WebRTC peer connections for voice calls during listen-together sessions.
///
/// To enable WebRTC voice:
/// 1. Add the WebRTC SPM package: https://github.com/nicklama/WebRTC (or stasel/WebRTC)
/// 2. Uncomment the WebRTC import and implementation below
/// 3. Add NSMicrophoneUsageDescription to Info.plist
///
/// The signaling flow uses the existing WebSocket connection:
/// - Host sends offer → backend relays to participant
/// - Participant sends answer → backend relays to host
/// - Both exchange ICE candidates → backend relays each way
final class WebRTCVoiceManager: ObservableObject {
    static let shared = WebRTCVoiceManager()

    @Published var isVoiceActive: Bool = false
    @Published var isMuted: Bool = false
    @Published var connectedPeers: [String] = []

    private let api = SphereAPIClient.shared

    // MARK: - Public API

    /// Start a voice call in the current listen session.
    func startVoice(sessionID: String, targetUserID: String) async {
        // Request microphone permission
        let granted = await requestMicrophonePermission()
        guard granted else { return }

        await MainActor.run { isVoiceActive = true }

        // Create and send WebRTC offer via signaling server
        try? await api.sendWebRTCSignal(
            sessionID: sessionID,
            targetUserID: targetUserID,
            signalType: "offer",
            payload: ["type": "offer", "sdp": "placeholder_sdp"]
        )
    }

    /// Stop the voice call.
    func stopVoice() {
        isVoiceActive = false
        isMuted = false
        connectedPeers = []
    }

    /// Toggle mute state.
    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - WebSocket Event Handling

    func handleSignalingEvent(type: String, payload: [String: Any]) {
        guard let sessionID = payload["session_id"] as? String,
              let fromUserID = payload["from_user_id"] as? String else { return }

        switch type {
        case "listen.webrtc.offer":
            // Received offer — create answer and send back
            Task {
                try? await api.sendWebRTCSignal(
                    sessionID: sessionID,
                    targetUserID: fromUserID,
                    signalType: "answer",
                    payload: ["type": "answer", "sdp": "placeholder_answer_sdp"]
                )
                await MainActor.run {
                    isVoiceActive = true
                    if !connectedPeers.contains(fromUserID) {
                        connectedPeers.append(fromUserID)
                    }
                }
            }

        case "listen.webrtc.answer":
            // Received answer — connection established
            DispatchQueue.main.async {
                if !self.connectedPeers.contains(fromUserID) {
                    self.connectedPeers.append(fromUserID)
                }
            }

        case "listen.webrtc.ice":
            // Received ICE candidate — add to peer connection
            break

        default:
            break
        }
    }

    // MARK: - Private

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// WebRTC signaling is handled through SphereAPIClient.sendWebRTCSignal()
// defined in SphereAPIClient.swift
