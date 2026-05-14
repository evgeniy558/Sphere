import SwiftUI

/// Active listen-together session UI: shows current track, participants, and controls.
struct ListenTogetherView: View {
    @ObservedObject private var manager = ListenTogetherManager.shared
    @ObservedObject private var voiceManager = WebRTCVoiceManager.shared
    let accent: Color
    let isEnglish: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let session = manager.activeSession {
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(isEnglish ? "Listening together" : "Слушаем вместе")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Track info
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(accent)

                        Text(session.track_provider)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        Text(isEnglish ? "Track: \(session.track_id)" : "Трек: \(session.track_id)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    // Participants
                    if let participants = session.participants, !participants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isEnglish ? "Participants" : "Участники")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 20)

                            ForEach(participants, id: \.user_id) { p in
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: p.avatar_url)) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Circle().fill(accent.opacity(0.2))
                                                .overlay(
                                                    Text(String(p.username.prefix(1)).uppercased())
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(accent)
                                                )
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name.isEmpty ? p.username : p.name)
                                            .font(.system(size: 15, weight: .medium))
                                        if p.user_id == session.host_id {
                                            Text(isEnglish ? "Host" : "Хост")
                                                .font(.system(size: 11))
                                                .foregroundStyle(accent)
                                        }
                                    }
                                    Spacer()

                                    // Voice indicator placeholder
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.green.opacity(0.7))
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 8)
                    }

                    Spacer()

                    // Voice controls
                    HStack(spacing: 20) {
                        Button {
                            if voiceManager.isVoiceActive {
                                voiceManager.stopVoice()
                            } else if let session = manager.activeSession,
                                      let participants = session.participants {
                                let others = participants.filter { $0.user_id != session.host_id }
                                if let target = others.first {
                                    Task { await voiceManager.startVoice(sessionID: session.id, targetUserID: target.user_id) }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: voiceManager.isVoiceActive ? "phone.fill" : "phone")
                                Text(voiceManager.isVoiceActive
                                     ? (isEnglish ? "End Call" : "Завершить звонок")
                                     : (isEnglish ? "Start Voice" : "Начать звонок"))
                            }
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(voiceManager.isVoiceActive ? Color.red.opacity(0.15) : accent.opacity(0.15))
                            .foregroundStyle(voiceManager.isVoiceActive ? .red : accent)
                            .clipShape(Capsule())
                        }

                        if voiceManager.isVoiceActive {
                            Button {
                                voiceManager.toggleMute()
                            } label: {
                                Image(systemName: voiceManager.isMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(voiceManager.isMuted ? Color.red.opacity(0.15) : accent.opacity(0.15))
                                    .foregroundStyle(voiceManager.isMuted ? .red : accent)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Controls
                    VStack(spacing: 12) {
                        if manager.isHost {
                            Button {
                                Task { await manager.endSession() }
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(isEnglish ? "End Session" : "Завершить сеанс")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                            }
                        } else {
                            Button {
                                Task { await manager.leaveSession() }
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.left.circle.fill")
                                    Text(isEnglish ? "Leave Session" : "Покинуть сеанс")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(accent.opacity(0.15))
                                .foregroundStyle(accent)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                } else {
                    Spacer()
                    Text(isEnglish ? "No active session" : "Нет активного сеанса")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .navigationTitle(isEnglish ? "Listen Together" : "Слушаем вместе")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEnglish ? "Done" : "Готово") { dismiss() }
                }
            }
        }
    }
}
