import SwiftUI
import Combine
import AVFoundation
import WebRTC

/// Manages WebRTC peer connections for voice calls during listen-together sessions.
final class WebRTCVoiceManager: ObservableObject {
    static let shared = WebRTCVoiceManager()

    @Published var isVoiceActive: Bool = false
    @Published var isMuted: Bool = false
    @Published var connectedPeers: [String] = []

    private let api = SphereAPIClient.shared
    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var currentSessionID: String?
    private var currentTargetUserID: String?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    private static var rtcConfig: RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: [
                "stun:stun.l.google.com:19302",
                "stun:stun1.l.google.com:19302",
            ])
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        return config
    }

    private static var mediaConstraints: RTCMediaConstraints {
        RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
    }

    // MARK: - Public API

    /// Start a voice call in the current listen session.
    func startVoice(sessionID: String, targetUserID: String) async {
        let granted = await requestMicrophonePermission()
        guard granted else { return }

        currentSessionID = sessionID
        currentTargetUserID = targetUserID

        configureAudioSession()
        createPeerConnection()
        addLocalAudioTrack()

        // Create offer
        guard let pc = peerConnection else { return }
        do {
            let offer = try await pc.offer(for: Self.mediaConstraints)
            try await pc.setLocalDescription(offer)

            // Send offer via signaling server
            let sdpDict: [String: Any] = [
                "type": "offer",
                "sdp": offer.sdp
            ]
            try await api.sendWebRTCSignal(
                sessionID: sessionID,
                targetUserID: targetUserID,
                signalType: "offer",
                payload: sdpDict
            )

            await MainActor.run { isVoiceActive = true }
        } catch {
            print("[WebRTC] Failed to create offer: \(error)")
        }
    }

    /// Stop the voice call.
    func stopVoice() {
        peerConnection?.close()
        peerConnection = nil
        localAudioTrack = nil
        currentSessionID = nil
        currentTargetUserID = nil
        isVoiceActive = false
        isMuted = false
        connectedPeers = []
    }

    /// Toggle mute state.
    func toggleMute() {
        isMuted.toggle()
        localAudioTrack?.isEnabled = !isMuted
    }

    // MARK: - WebSocket Event Handling

    func handleSignalingEvent(type: String, payload: [String: Any]) {
        guard let fromUserID = payload["from_user_id"] as? String,
              let sessionID = payload["session_id"] as? String,
              let data = payload["data"] as? [String: Any] else { return }

        switch type {
        case "listen.webrtc.offer":
            handleOffer(from: fromUserID, sessionID: sessionID, data: data)

        case "listen.webrtc.answer":
            handleAnswer(data: data, from: fromUserID)

        case "listen.webrtc.ice":
            handleICECandidate(data: data)

        default:
            break
        }
    }

    // MARK: - Private: Offer/Answer/ICE

    private func handleOffer(from userID: String, sessionID: String, data: [String: Any]) {
        guard let sdpString = data["sdp"] as? String else { return }

        currentSessionID = sessionID
        currentTargetUserID = userID

        configureAudioSession()
        createPeerConnection()
        addLocalAudioTrack()

        guard let pc = peerConnection else { return }

        let remoteSDP = RTCSessionDescription(type: .offer, sdp: sdpString)

        Task {
            do {
                try await pc.setRemoteDescription(remoteSDP)

                let answer = try await pc.answer(for: Self.mediaConstraints)
                try await pc.setLocalDescription(answer)

                // Send answer back
                let answerDict: [String: Any] = [
                    "type": "answer",
                    "sdp": answer.sdp
                ]
                try await api.sendWebRTCSignal(
                    sessionID: sessionID,
                    targetUserID: userID,
                    signalType: "answer",
                    payload: answerDict
                )

                await MainActor.run {
                    self.isVoiceActive = true
                    if !self.connectedPeers.contains(userID) {
                        self.connectedPeers.append(userID)
                    }
                }
            } catch {
                print("[WebRTC] Failed to handle offer: \(error)")
            }
        }
    }

    private func handleAnswer(data: [String: Any], from userID: String) {
        guard let sdpString = data["sdp"] as? String,
              let pc = peerConnection else { return }

        let remoteSDP = RTCSessionDescription(type: .answer, sdp: sdpString)

        Task {
            do {
                try await pc.setRemoteDescription(remoteSDP)
                await MainActor.run {
                    if !self.connectedPeers.contains(userID) {
                        self.connectedPeers.append(userID)
                    }
                }
            } catch {
                print("[WebRTC] Failed to set remote description: \(error)")
            }
        }
    }

    private func handleICECandidate(data: [String: Any]) {
        guard let candidate = data["candidate"] as? String,
              let sdpMid = data["sdpMid"] as? String,
              let sdpMLineIndex = data["sdpMLineIndex"] as? Int32 else { return }

        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        peerConnection?.add(iceCandidate) { error in
            if let error {
                print("[WebRTC] Failed to add ICE candidate: \(error)")
            }
        }
    }

    // MARK: - Private: Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    private func createPeerConnection() {
        peerConnection?.close()
        peerConnection = Self.factory.peerConnection(
            with: Self.rtcConfig,
            constraints: Self.mediaConstraints,
            delegate: WebRTCDelegateAdapter.shared
        )
        WebRTCDelegateAdapter.shared.manager = self
    }

    private func addLocalAudioTrack() {
        let audioSource = Self.factory.audioSource(with: Self.mediaConstraints)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "sphere-voice-0")
        audioTrack.isEnabled = true
        localAudioTrack = audioTrack

        peerConnection?.add(audioTrack, streamIds: ["sphere-voice"])
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // Called by delegate when ICE candidate is generated locally
    fileprivate func didGenerateICECandidate(_ candidate: RTCIceCandidate) {
        guard let sessionID = currentSessionID,
              let targetUserID = currentTargetUserID else { return }

        let iceDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex,
        ]

        Task {
            try? await api.sendWebRTCSignal(
                sessionID: sessionID,
                targetUserID: targetUserID,
                signalType: "ice",
                payload: iceDict
            )
        }
    }

    fileprivate func didChangeConnectionState(_ state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected, .completed:
                self.isVoiceActive = true
            case .disconnected, .failed, .closed:
                self.stopVoice()
            default:
                break
            }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate Adapter

/// Separate class to act as RTCPeerConnectionDelegate (requires NSObject).
private class WebRTCDelegateAdapter: NSObject, RTCPeerConnectionDelegate {
    static let shared = WebRTCDelegateAdapter()
    weak var manager: WebRTCVoiceManager?

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        manager?.didChangeConnectionState(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        manager?.didGenerateICECandidate(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
