import SwiftUI

/// Artist profile: top 10 tracks, albums from API, fans-also-like from backend.
struct ArtistProfileView: View {
    let artist: CatalogArtist
    let accent: Color
    let isDarkMode: Bool
    let isEnglish: Bool
    let onPlayTrack: (CatalogTrack, [CatalogTrack]) -> Void
    var onAlbumTap: ((CatalogAlbum) -> Void)?
    var onRelatedArtistTap: ((CatalogArtist) -> Void)?

    @Environment(\.dismiss) private var dismiss
    private let apiClient = SphereAPIClient.shared
    @State private var unified: CatalogArtist?
    @State private var albums: [CatalogAlbum] = []
    @State private var fansAlsoLike: [CatalogArtist] = []
    @State private var isLoading = false
    @State private var isLoadingAlbums = false
    @State private var loadError: String?
    @State private var isFollowing = false

    private var displayArtist: CatalogArtist { unified ?? artist }
    private var topTracks: [CatalogTrack] { Array((displayArtist.tracks ?? []).prefix(10)) }
    private var providerID: (provider: String, id: String)? {
        if artist.id != "placeholder", !artist.provider.isEmpty, artist.provider != "all" {
            return (artist.provider, artist.id)
        }
        if let u = unified, u.provider != "all", u.id != "placeholder" {
            return (u.provider, u.id)
        }
        return nil
    }

    private var isPlaceholder: Bool { artist.id == "placeholder" }

    var body: some View {
        NavigationStack {
            Group {
                if isPlaceholder && unified == nil {
                    SkeletonArtistProfile()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(contentBackground.ignoresSafeArea())
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            heroSection
                            contentSection
                        }
                    }
                    .background(contentBackground.ignoresSafeArea())
                }
            }
            .navigationTitle(displayArtist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEnglish ? "Done" : "Готово") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .task { await loadAll() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            blurredBackdrop
            heroForeground
        }
        .frame(maxWidth: .infinity)
    }

    private var blurredBackdrop: some View {
        GeometryReader { proxy in
            AsyncImage(url: catalogRemoteImageURL(displayArtist.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle().fill(Color(white: 0.12))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .blur(radius: 70)
            .scaleEffect(1.35)
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.25),
                        Color.black.opacity(0.65),
                        Color.black,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: 560)
    }

    private var heroForeground: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 56)
            AsyncImage(url: catalogRemoteImageURL(displayArtist.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle()
                        .fill(isDarkMode ? Color(white: 0.18) : Color(white: 0.9))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white.opacity(0.55))
                        )
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 18)

            Text(displayArtist.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            statsLine

            playButtons.padding(.horizontal, 24)
        }
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var statsLine: some View {
        let parts = statsItems.map { "\($0.value) \($0.label.lowercased())" }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var playButtons: some View {
        HStack(spacing: 12) {
            Button {
                isFollowing.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(isFollowing
                         ? (isEnglish ? "Following" : "Подписан")
                         : (isEnglish ? "Follow" : "Подписаться"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(isFollowing ? Color.white.opacity(0.16) : Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isFollowing ? 0.4 : 0.18), lineWidth: 1)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                if let first = topTracks.first { onPlayTrack(first, topTracks) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(isEnglish ? "Play" : "Слушать")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.white))
                .foregroundStyle(.black)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(topTracks.isEmpty)
            .opacity(topTracks.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Content

    private var contentBackground: Color { Color.black }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            popularTracksSection
            albumsSection
            fansAlsoLikeSection
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var popularTracksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEnglish ? "Popular tracks" : "Популярные треки")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            if topTracks.isEmpty && !isLoading {
                Text(isEnglish ? "No tracks yet" : "Пока нет треков")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(topTracks.enumerated()), id: \.element.id) { idx, track in
                        ArtistTrackRow(index: idx + 1, track: track, isDarkMode: true) {
                            onPlayTrack(track, topTracks)
                        }
                        if idx < topTracks.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEnglish ? "Albums" : "Альбомы")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            if isLoadingAlbums {
                ProgressView().controlSize(.small).tint(.white)
            } else if albums.isEmpty {
                Text(isEnglish ? "No albums" : "Нет альбомов")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(albums) { al in
                            Button {
                                onAlbumTap?(al)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: catalogRemoteImageURL(al.coverURL)) { phase in
                                            switch phase {
                                            case .success(let img): img.resizable().scaledToFill()
                                            default: Rectangle().fill(Color.white.opacity(0.08))
                                            }
                                        }
                                        .frame(width: 148, height: 148)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        if let tracks = al.tracks,
                                           DownloadsStore.shared.isCollectionFullyDownloaded(tracks: tracks) {
                                            DownloadedBadge(size: 16).padding(6)
                                        }
                                    }
                                    Text(al.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(albumSubtitle(al))
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }
                                .frame(width: 148, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func albumSubtitle(_ al: CatalogAlbum) -> String {
        let label = isEnglish ? "Album" : "Альбом"
        let artistName = al.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if artistName.isEmpty || artistName == displayArtist.name {
            return label
        }
        return "\(label) • \(artistName)"
    }

    private var fansAlsoLikeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEnglish ? "Fans also like" : "Поклонникам также нравится")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            if fansAlsoLike.isEmpty {
                Text(isEnglish ? "Not enough listening data yet" : "Пока недостаточно данных")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(fansAlsoLike) { related in
                            Button {
                                onRelatedArtistTap?(related)
                            } label: {
                                VStack(spacing: 10) {
                                    AsyncImage(url: catalogRemoteImageURL(related.imageURL)) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Circle().fill(Color.white.opacity(0.10))
                                                .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.4)))
                                        }
                                    }
                                    .frame(width: 104, height: 104)
                                    .clipShape(Circle())
                                    Text(related.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 104)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var statsItems: [(value: String, label: String)] {
        var out: [(String, String)] = []
        if let listeners = displayArtist.monthlyListeners, listeners > 0 {
            out.append((formatNumber(listeners), isEnglish ? "Monthly listeners" : "Слушателей в месяц"))
        }
        if let followers = displayArtist.followers, followers > 0 {
            out.append((formatNumber(followers), isEnglish ? "Followers" : "Подписчиков"))
        }
        return out
    }

    private var stats: some View {
        HStack(spacing: 24) {
            ForEach(statsItems.indices, id: \.self) { idx in
                let item = statsItems[idx]
                VStack(spacing: 2) {
                    Text(item.value).font(.system(size: 16, weight: .semibold))
                    Text(item.label).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Data

    private func loadAll() async {
        await loadUnified()
        await loadAlbums()
        await loadFansAlsoLike()
    }

    private func loadUnified() async {
        guard unified == nil else { return }
        isLoading = true
        loadError = nil
        do {
            unified = try await apiClient.getArtistUnified(name: artist.name)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadAlbums() async {
        isLoadingAlbums = true
        defer { isLoadingAlbums = false }
        if let pid = providerID, pid.provider == "spotify" {
            albums = (try? await apiClient.getArtistAlbums(provider: pid.provider, id: pid.id)) ?? []
            return
        }
        let name = unified?.name ?? artist.name
        if let search = try? await apiClient.search(query: name, limit: 10),
           let sp = search.artists.first(where: { $0.provider == "spotify" })
            ?? search.artists.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            albums = (try? await apiClient.getArtistAlbums(provider: sp.provider, id: sp.id)) ?? []
            return
        }
        albums = []
    }

    private func loadFansAlsoLike() async {
        guard let pid = providerID else { return }
        fansAlsoLike = (try? await apiClient.getFansAlsoLike(provider: pid.provider, id: pid.id)) ?? []
    }

    private func formatNumber(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Row

struct ArtistTrackRow: View {
    let index: Int
    let track: CatalogTrack
    let isDarkMode: Bool
    let onTap: () -> Void

    @ObservedObject private var downloads = DownloadsStore.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isDarkMode ? .white : .primary)
                        .lineLimit(1)
                    if let album = track.album, !album.isEmpty {
                        Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if downloads.isDownloaded(provider: track.provider, id: track.id) {
                    DownloadedBadge(size: 14)
                }
                ServiceIconBadge(provider: track.provider, size: 16)
                Text(track.durationFormatted)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
