import SwiftUI
import UniformTypeIdentifiers

/// Node Studio — creator dashboard: listening stats, drafts, upload entry point.
/// Lives inside Settings → "Node Studio".
struct NodeStudioView: View {
    let isEnglish: Bool
    let isDarkMode: Bool
    let accent: Color

    @ObservedObject private var auth: AuthService = AuthService.shared
    @ObservedObject private var favorites: FavoritesStore = FavoritesStore.shared
    @ObservedObject private var recents: RecentlyPlayedStore = RecentlyPlayedStore.shared
    @ObservedObject private var uploader: TrackUploadManager = TrackUploadManager.shared

    @State private var showUploadHint = false
    @State private var showUploadSheet = false
    @State private var summary: SphereAPIClient.StudioSummary?

    var body: some View {
        ZStack {
            NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.45).ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    if uploader.isUploading || uploader.progress >= 1 {
                        uploadProgressCard
                    }
                    statsRow
                    listeningChart
                    quickActions
                    activitySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Node Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadSummary() }
        .sheet(isPresented: $showUploadSheet) {
            TrackUploadSheet(
                isEnglish: isEnglish,
                accent: accent,
                defaultArtist: displayName,
                onClose: { showUploadSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var uploadProgressCard: some View {
        let statusColor: Color = uploader.lastError != nil ? .red : (uploader.progress >= 1 ? .green : accent)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: uploader.lastError != nil ? "exclamationmark.triangle.fill"
                      : (uploader.progress >= 1 ? "checkmark.circle.fill" : "arrow.up.circle.fill"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(uploader.lastError ?? uploader.statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(uploader.progress * 100))%")
                    .font(.nodeMono(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ProgressView(value: uploader.progress)
                .tint(statusColor)
        }
        .padding(16)
        .libraryGlassCard(cornerRadius: 18)
    }

    private func loadSummary() async {
        do {
            let s = try await SphereAPIClient.shared.getStudioSummary()
            await MainActor.run { summary = s }
        } catch {
            // Fall back to local estimates in statsRow.
        }
    }

    private var displayName: String {
        auth.currentProfile?.nickname
            ?? auth.backendAccountSnapshot?.name
            ?? (isEnglish ? "Creator" : "Автор")
    }

    private var avatarURL: String? {
        auth.currentProfile?.avatarUrl ?? auth.backendAccountSnapshot?.avatarUrl
    }

    // MARK: - Header

    private var headerCard: some View {
        ZStack(alignment: .topLeading) {
            // Premium multi-stop gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        accent.opacity(0.70),
                        accent.opacity(0.45),
                        Color(red: 0.50, green: 0.32, blue: 0.94).opacity(0.40),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            // Subtle pattern overlay
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.08), .clear, .white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("NODE • STUDIO")
                            .font(.nodeMono(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                }

                Text(isEnglish
                     ? "Share your sound. Track listeners and drops."
                     : "Делись звуком. Считай слушателей и релизы.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(20)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: accent.opacity(0.25), radius: 20, x: 0, y: 8)
    }

    private var avatar: some View {
        Group {
            if let urlStr = avatarURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.18)
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let listenedMinutes = summary?.listening_minutes ?? max(0, recents.items.count * 3)
        let likedTracks = summary?.liked_tracks ?? favorites.items.filter { $0.itemType == "track" }.count
        let recentArtists = summary?.recent_artists ?? Set(recents.items.map { $0.artist }).filter { !$0.isEmpty }.count

        return HStack(spacing: 12) {
            statTile(
                title: isEnglish ? "Listening" : "Прослушано",
                value: "\(listenedMinutes)",
                unit: isEnglish ? "min" : "мин",
                color: NodeDesignStyle.tilePalette[0]
            )
            statTile(
                title: isEnglish ? "Liked" : "Лайки",
                value: "\(likedTracks)",
                unit: isEnglish ? "tracks" : "тр.",
                color: NodeDesignStyle.tilePalette[1]
            )
            statTile(
                title: isEnglish ? "Artists" : "Артисты",
                value: "\(recentArtists)",
                unit: isEnglish ? "this week" : "за неделю",
                color: NodeDesignStyle.tilePalette[5]
            )
        }
    }

    private func statTile(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.nodeMono(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                let t = (sin(timeline.date.timeIntervalSinceReferenceDate * 1.2) + 1) / 2
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.55 + 0.25 * t)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        )
        .shadow(color: color.opacity(0.32), radius: 12, x: 0, y: 6)
    }

    // MARK: - Listening Chart

    private var listeningChart: some View {
        // Build weekly data from recents
        let cal = Calendar.current
        let today = Date()
        let days = (0..<7).reversed().map { offset -> (day: String, minutes: Double) in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let dayName = date.formatted(.dateTime.weekday(.abbreviated))
            let dayStart = cal.startOfDay(for: date)
            let dayTracks = recents.items.filter { $0.playedAt >= dayStart }
            let mins = Double(dayTracks.count * 3)
            return (dayName, mins)
        }
        let maxMins = max(1, days.map(\.minutes).max() ?? 1)

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(isEnglish ? "This week" : "За неделю")

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days.indices, id: \.self) { idx in
                    let data = days[idx]
                    let color = NodeDesignStyle.tileColor(for: data.day)
                    let barHeight = max(8, (data.minutes / maxMins) * 100)
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.9), color.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: barHeight)
                        Text(data.day.prefix(3))
                            .font(.nodeMono(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
            )
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(isEnglish ? "Tools" : "Инструменты")
            VStack(spacing: 0) {
                actionRow(
                    icon: "waveform.badge.plus",
                    iconColor: accent,
                    title: isEnglish ? "Upload track" : "Загрузить трек",
                    subtitle: uploader.isUploading
                        ? (isEnglish ? "Uploading…" : "Загрузка…")
                        : (isEnglish ? "MP3, M4A, WAV, FLAC" : "MP3, M4A, WAV, FLAC")
                ) { showUploadSheet = true }

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                actionRow(
                    icon: "chart.bar.fill",
                    iconColor: NodeDesignStyle.tilePalette[5],
                    title: isEnglish ? "Listener insights" : "Инсайты слушателей",
                    subtitle: isEnglish ? "Top regions, playlists" : "Топ-регионы, плейлисты"
                ) { showUploadHint = true }

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                actionRow(
                    icon: "rectangle.stack.fill.badge.person.crop",
                    iconColor: NodeDesignStyle.tilePalette[7],
                    title: isEnglish ? "Drafts" : "Черновики",
                    subtitle: isEnglish ? "0 in queue" : "0 в очереди"
                ) { showUploadHint = true }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .alert(isEnglish ? "Coming soon" : "Скоро будет",
               isPresented: $showUploadHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(isEnglish
                 ? "Studio uploads are in private beta. We will notify when it's available."
                 : "Загрузка треков в закрытой бете. Мы сообщим, когда откроем.")
        }
    }

    private func actionRow(icon: String, iconColor: Color = .white, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(iconColor.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(isEnglish ? "Recent activity" : "Активность")
            if recents.items.isEmpty {
                Text(isEnglish ? "Nothing yet — listen a few tracks first." : "Пока пусто — послушай пару треков.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .libraryGlassCard(cornerRadius: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.items.prefix(5).enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 14) {
                            // Timeline connector
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(NodeDesignStyle.tileColor(for: item.title))
                                    .frame(width: 8, height: 8)
                                    .shadow(color: NodeDesignStyle.tileColor(for: item.title).opacity(0.5), radius: 4, x: 0, y: 0)
                                if idx < min(recents.items.count, 5) - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.10))
                                        .frame(width: 1.5)
                                }
                            }
                            .frame(width: 16)

                            activityRow(title: item.title, subtitle: item.artist, coverURL: item.coverURL)
                        }
                        .padding(.leading, 10)
                    }
                }
                .padding(.vertical, 10)
                .libraryGlassCard(cornerRadius: 20)
            }
        }
    }

    private func activityRow(title: String, subtitle: String, coverURL: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let urlStr = coverURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.white.opacity(0.1)
                        }
                    }
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.trailing, 14)
        .padding(.vertical, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .padding(.leading, 4)
    }
}
