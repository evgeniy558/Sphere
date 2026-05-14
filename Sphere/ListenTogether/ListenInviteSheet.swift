import SwiftUI

/// Sheet to invite a friend to listen together. Reuses the pattern from ShareTrackToUserSheet.
struct ListenInviteSheet: View {
    let track: CatalogTrack
    let accent: Color
    let isEnglish: Bool
    let isDarkMode: Bool
    let onDone: () -> Void

    @State private var users: [BackendUserListItem] = []
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMsg: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if users.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(isEnglish ? "No friends to invite" : "Нет друзей для приглашения")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(users, id: \.id) { user in
                            Button {
                                inviteUser(user)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: user.avatar_url)) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Circle().fill(accent.opacity(0.2))
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.name.isEmpty ? user.username : user.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text("@\(user.username)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "headphones.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(accent)
                                }
                            }
                            .disabled(isSending)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(isEnglish ? "Invite to Listen" : "Пригласить слушать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEnglish ? "Cancel" : "Отмена") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )) {
                Button("OK") { errorMsg = nil }
            } message: {
                if let msg = errorMsg { Text(msg) }
            }
        }
        .task { await loadFriends() }
    }

    private func loadFriends() async {
        isLoading = true
        do {
            let myID = AuthService.shared.backendAccountSnapshot?.id ?? ""
            guard !myID.isEmpty else {
                isLoading = false
                return
            }
            let response = try await SphereAPIClient.shared.listUserSubscriptions(id: myID)
            let items: [BackendUserListItem]
            if case .users(let list) = response {
                items = list
            } else {
                items = []
            }
            await MainActor.run {
                self.users = items
                self.isLoading = false
            }
        } catch {
            await MainActor.run { self.isLoading = false }
        }
    }

    private func inviteUser(_ user: BackendUserListItem) {
        isSending = true
        Task {
            do {
                let mgr = ListenTogetherManager.shared
                // Create session if not already active.
                if mgr.activeSession == nil {
                    try await mgr.createSession(track: track)
                }
                try await mgr.inviteFriend(targetUserID: user.id, track: track)
                await MainActor.run {
                    isSending = false
                    onDone()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMsg = error.localizedDescription
                }
            }
        }
    }
}

/// Incoming invite alert: shown when another user invites you to listen together.
struct ListenInviteAlertView: View {
    let invite: ListenInviteEvent
    let accent: Color
    let isEnglish: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnglish
                         ? "\(invite.from_username) invites you to listen"
                         : "\(invite.from_username) приглашает слушать")
                        .font(.system(size: 15, weight: .semibold))

                    if !invite.track_title.isEmpty {
                        Text("\(invite.track_title) — \(invite.track_artist)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    onDecline()
                } label: {
                    Text(isEnglish ? "Decline" : "Отклонить")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }

                Button {
                    onAccept()
                } label: {
                    Text(isEnglish ? "Join" : "Присоединиться")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        )
        .padding(.horizontal, 16)
    }
}
