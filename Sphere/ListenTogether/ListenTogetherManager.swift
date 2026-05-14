import SwiftUI
import Combine
import Foundation

/// Manages listen-together sessions: creation, joining, sync events via WebSocket.
final class ListenTogetherManager: ObservableObject {
    static let shared = ListenTogetherManager()

    @Published var activeSession: ListenSession?
    @Published var isHost: Bool = false
    @Published var pendingInvite: ListenInviteEvent?
    @Published var lastSyncEvent: ListenSyncEvent?

    private let api = SphereAPIClient.shared

    // MARK: - Host actions

    func createSession(track: CatalogTrack) async throws {
        let session = try await api.createListenSession(
            trackProvider: track.provider,
            trackID: track.id
        )
        await MainActor.run {
            self.activeSession = session
            self.isHost = true
        }
    }

    func inviteFriend(targetUserID: String, track: CatalogTrack) async throws {
        guard let session = activeSession else { return }
        try await api.sendListenInvite(
            sessionID: session.id,
            targetUserID: targetUserID,
            trackTitle: track.title,
            trackArtist: track.artist,
            trackCoverURL: track.coverURL ?? ""
        )
    }

    func syncPlayback(positionSeconds: Double, isPlaying: Bool) async {
        guard let session = activeSession, isHost else { return }
        try? await api.sendListenSync(
            sessionID: session.id,
            trackProvider: session.track_provider,
            trackID: session.track_id,
            positionSeconds: positionSeconds,
            isPlaying: isPlaying
        )
    }

    // MARK: - Participant actions

    func joinSession(sessionID: String) async throws {
        try await api.joinListenSession(sessionID: sessionID)
        let session = try await api.getListenSession(sessionID: sessionID)
        await MainActor.run {
            self.activeSession = session
            self.isHost = false
        }
    }

    func leaveSession() async {
        guard let session = activeSession else { return }
        try? await api.leaveListenSession(sessionID: session.id)
        await MainActor.run {
            self.activeSession = nil
            self.isHost = false
        }
    }

    func endSession() async {
        guard let session = activeSession, isHost else { return }
        try? await api.endListenSession(sessionID: session.id)
        await MainActor.run {
            self.activeSession = nil
            self.isHost = false
        }
    }

    // MARK: - WebSocket event handling

    func handleWSEvent(_ data: Data) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "listen.invite":
            if let payload = dict["payload"],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let invite = try? JSONDecoder().decode(ListenInviteEvent.self, from: payloadData) {
                DispatchQueue.main.async {
                    self.pendingInvite = invite
                }
            }

        case "listen.sync":
            if let payload = dict["payload"],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let sync = try? JSONDecoder().decode(ListenSyncEvent.self, from: payloadData) {
                DispatchQueue.main.async {
                    self.lastSyncEvent = sync
                }
            }

        case "listen.webrtc.offer", "listen.webrtc.answer", "listen.webrtc.ice":
            if let payload = dict["payload"] as? [String: Any] {
                WebRTCVoiceManager.shared.handleSignalingEvent(type: type, payload: payload)
            }

        case "listen.join", "listen.leave", "listen.end":
            // Refresh session state.
            if let session = activeSession {
                Task {
                    if type == "listen.end" {
                        await MainActor.run {
                            self.activeSession = nil
                            self.isHost = false
                        }
                    } else {
                        if let updated = try? await api.getListenSession(sessionID: session.id) {
                            await MainActor.run { self.activeSession = updated }
                        }
                    }
                }
            }

        default:
            break
        }
    }

    func dismissInvite() {
        pendingInvite = nil
    }
}
