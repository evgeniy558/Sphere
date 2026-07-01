import SwiftUI

enum LibrarySection: String, CaseIterable, Identifiable {
    case recent
    case queue
    case playlists
    case liked

    var id: String { rawValue }
}

struct LibraryTabView: View {
    let isEnglish: Bool
    let isDarkMode: Bool
    let accent: Color

    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var recentStore: RecentlyPlayedStore
    @ObservedObject var downloadsStore: DownloadsStore

    let catalogQueue: [CatalogTrack]
    let groupPlaylists: [GroupPlaylist]
    let playlistCoverURLs: [String: [String]]
    let playlistDetails: [String: GroupPlaylistDetail]
    let currentUserBackendID: String?
    let isLoadingPlaylists: Bool

    var onPlayCatalogTrack: (CatalogTrack, [CatalogTrack]) -> Void
    var onPlayRecent: (RecentlyPlayedStore.Item) -> Void
    var onOpenLiked: () -> Void
    var onOpenDownloads: () -> Void
    var onOpenGroupPlaylist: (GroupPlaylist) -> Void

    @State private var section: LibrarySection = .recent
    @State private var searchText = ""

    private var libraryTitle: String { isEnglish ? "Library" : "Библиотека" }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    libraryQuickGrid

                    sectionPills

                    sectionContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 130)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(libraryTitle)
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: isEnglish ? "Search your library" : "Поиск в библиотеке"
            )
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.white)
    }

    // MARK: - Quick grid

    private var libraryQuickGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let downloadsCount = downloadsStore.index.count
        let likedCount = favoritesStore.items.filter { $0.itemType == "track" }.count
        let starredCount = favoritesStore.items.filter { $0.itemType != "track" }.count
        return LazyVGrid(columns: cols, spacing: 12) {
            Button { onOpenDownloads() } label: {
                NodeColorTile(
                    title: isEnglish ? "Downloads" : "Загрузки",
                    subtitle: isEnglish ? "\(downloadsCount) tracks" : "\(downloadsCount) треков",
                    icon: "arrow.down.circle.fill",
                    color: NodeDesignStyle.tilePalette[0],
                    aspectRatio: 1.7
                )
            }
            .buttonStyle(.plain)

            Button { onOpenLiked() } label: {
                NodeColorTile(
                    title: isEnglish ? "Liked" : "Нравится",
                    subtitle: isEnglish ? "\(likedCount) tracks" : "\(likedCount) треков",
                    icon: "heart.fill",
                    color: NodeDesignStyle.tilePalette[3],
                    aspectRatio: 1.7
                )
            }
            .buttonStyle(.plain)

            Button { section = .liked } label: {
                NodeColorTile(
                    title: isEnglish ? "Bookmarks" : "Закладки",
                    subtitle: isEnglish ? "0 notes" : "0 заметок",
                    icon: "bookmark.fill",
                    color: NodeDesignStyle.tilePalette[5],
                    aspectRatio: 1.7
                )
            }
            .buttonStyle(.plain)

            Button { section = .liked } label: {
                NodeColorTile(
                    title: isEnglish ? "Starred" : "Избранное",
                    subtitle: isEnglish ? "\(starredCount) items" : "\(starredCount) элементов",
                    icon: "star.fill",
                    color: NodeDesignStyle.tilePalette[4],
                    aspectRatio: 1.7
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Pills

    private var sectionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibrarySection.allCases) { s in
                    let selected = section == s
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            section = s
                        }
                    } label: {
                        Text(pillTitle(s))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .libraryGlassPill(selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pillTitle(_ s: LibrarySection) -> String {
        switch s {
        case .recent: return isEnglish ? "Recent" : "Недавнее"
        case .queue: return isEnglish ? "Queue" : "Очередь"
        case .playlists: return isEnglish ? "Playlists" : "Плейлисты"
        case .liked: return isEnglish ? "Liked" : "Нравится"
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .recent: recentSection
        case .queue: queueSection
        case .playlists: playlistsSection
        case .liked: likedSection
        }
    }

    private var recentSection: some View {
        let groups = groupedRecentItems(filteredRecent)
        return VStack(alignment: .leading, spacing: 14) {
            if groups.isEmpty {
                emptyLabel(isEnglish ? "Nothing here yet" : "Пока пусто")
            } else {
                ForEach(groups, id: \.title) { group in
                    sectionGlassBlock {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                            ForEach(group.items) { item in
                                Button { onPlayRecent(item) } label: {
                                    LibraryListeningCard(
                                        item: item,
                                        isEnglish: isEnglish,
                                        isDarkMode: isDarkMode,
                                        durationLabel: playDurationLabel(for: item),
                                        onPlay: { onPlayRecent(item) }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var queueSection: some View {
        let tracks = filteredQueue
        return VStack(alignment: .leading, spacing: 12) {
            if tracks.isEmpty {
                emptyLabel(isEnglish ? "Queue is empty" : "Очередь пуста")
            } else {
                sectionGlassBlock {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(isEnglish ? "Up next" : "Дальше")
                    ForEach(Array(tracks.enumerated()), id: \.element.compositeKey) { idx, track in
                        Button {
                            onPlayCatalogTrack(track, catalogQueue)
                        } label: {
                            libraryTrackRow(track, index: idx + 1)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }
            }
        }
    }

    private var playlistsSection: some View {
        let list = filteredPlaylists
        return VStack(alignment: .leading, spacing: 12) {
            if isLoadingPlaylists {
                ProgressView().tint(.white).padding(.top, 20)
            } else if list.isEmpty {
                emptyLabel(isEnglish ? "No playlists yet" : "Плейлистов пока нет")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(isEnglish ? "Your playlists" : "Ваши плейлисты")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(list) { pl in
                            Button { onOpenGroupPlaylist(pl) } label: {
                                libraryPlaylistFolder(pl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var likedSection: some View {
        let tracks = filteredLikedTracks
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(isEnglish ? "Liked tracks" : "Любимые треки")
            if tracks.isEmpty {
                emptyLabel(isEnglish ? "Like tracks to see them here" : "Лайкай треки — они появятся здесь")
            } else {
                ForEach(tracks) { fav in
                    Button { playFavorite(fav) } label: {
                        libraryFavoriteRow(fav)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Grouping

    private struct RecentGroup {
        let title: String
        let items: [RecentlyPlayedStore.Item]
    }

    private func groupedRecentItems(_ items: [RecentlyPlayedStore.Item]) -> [RecentGroup] {
        let cal = Calendar.current
        var today: [RecentlyPlayedStore.Item] = []
        var yesterday: [RecentlyPlayedStore.Item] = []
        var older: [RecentlyPlayedStore.Item] = []
        for item in items {
            if cal.isDateInToday(item.playedAt) { today.append(item) }
            else if cal.isDateInYesterday(item.playedAt) { yesterday.append(item) }
            else { older.append(item) }
        }
        var out: [RecentGroup] = []
        if !today.isEmpty {
            out.append(RecentGroup(title: isEnglish ? "Today" : "Сегодня", items: today))
        }
        if !yesterday.isEmpty {
            out.append(RecentGroup(title: isEnglish ? "Yesterday" : "Вчера", items: yesterday))
        }
        if !older.isEmpty {
            out.append(RecentGroup(title: isEnglish ? "Earlier" : "Раньше", items: older))
        }
        return out
    }

    private func playDurationLabel(for item: RecentlyPlayedStore.Item) -> String? {
        guard item.kind == .catalog else { return nil }
        let parts = item.id.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        if let match = catalogQueue.first(where: { $0.provider == parts[0] && $0.id == parts[1] }) {
            return match.durationFormatted
        }
        return nil
    }

    // MARK: - Filtering

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredRecent: [RecentlyPlayedStore.Item] {
        let base = recentStore.items
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) || $0.artist.lowercased().contains(query)
        }
    }

    private var filteredQueue: [CatalogTrack] {
        guard !query.isEmpty else { return catalogQueue }
        return catalogQueue.filter {
            $0.title.lowercased().contains(query) || $0.artist.lowercased().contains(query)
        }
    }

    private var filteredPlaylists: [GroupPlaylist] {
        guard !query.isEmpty else { return groupPlaylists }
        return groupPlaylists.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredLikedTracks: [FavoriteItem] {
        let base = favoritesStore.items.filter { $0.itemType == "track" }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) || $0.artistName.lowercased().contains(query)
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
    }

    private func sectionGlassBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .librarySectionGlass(cornerRadius: NodeDesignStyle.sectionCornerRadius)
    }

    private func emptyLabel(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func libraryTrackRow(_ track: CatalogTrack, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 22)
            cover(url: track.coverURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(1)
            }
            Spacer()
            Text(track.durationFormatted)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.vertical, 8)
    }

    private func libraryFavoriteRow(_ fav: FavoriteItem) -> some View {
        HStack(spacing: 12) {
            cover(url: fav.coverURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !fav.artistName.isEmpty {
                    Text(fav.artistName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func libraryPlaylistFolder(_ pl: GroupPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            playlistFolderArtwork(pl)
                .frame(height: 168)

            Text(pl.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(playlistSubtitle(pl))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Frosted "envelope/pocket": the cover sticks out of the top and its lower
    /// part is tucked behind a translucent frosted pocket front.
    @ViewBuilder
    private func playlistFolderArtwork(_ pl: GroupPlaylist) -> some View {
        let primaryURL = (playlistCoverURLs[pl.id]?.first).flatMap(catalogRemoteImageURL)
            ?? catalogRemoteImageURL(pl.cover_url)
        let trackCount = pl.track_count

        ZStack(alignment: .bottom) {
            // Vivid blurred cover fills the whole sleeve so its colors read through
            // the frosted front (like a record in a translucent sleeve).
            Group {
                if let primaryURL {
                    AsyncImage(url: primaryURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .blur(radius: 22)
                                .scaleEffect(1.35)
                        } else {
                            Color.white.opacity(0.06)
                        }
                    }
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Sharp cover peeking out of the top of the sleeve.
            coverThumb(url: primaryURL)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 12)
                .offset(y: -28)

            // Frosted sleeve front — frosts the vivid cover behind it.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            }
            .frame(height: 88)
            .overlay(alignment: .topTrailing) {
                if trackCount > 0 {
                    Text("\(trackCount)")
                        .font(.nodeMono(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.45)))
                        .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private func coverThumb(url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: playlistCoverPlaceholder
                }
            }
        } else {
            playlistCoverPlaceholder
        }
    }

    private var playlistCoverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func playlistSubtitle(_ pl: GroupPlaylist) -> String {
        let countLabel = isEnglish ? "\(pl.track_count) tracks" : "\(pl.track_count) треков"
        let detail = playlistDetails[pl.id]
        let membersCount = detail?.members?.count ?? 0
        let isOwnerByID = currentUserBackendID != nil && currentUserBackendID == pl.owner_id
        let isCollaborative = membersCount > 1 || !isOwnerByID || (pl.role?.lowercased() != "owner" && pl.role != nil)
        guard isCollaborative else { return countLabel }

        let ownerName = detail?.members?.first(where: { $0.role.lowercased() == "owner" })?.name
            ?? detail?.members?.first?.name
            ?? (isEnglish ? "Collaborative" : "Совместный")
        return "\(ownerName) · \(countLabel)"
    }

    @ViewBuilder
    private func cover(url: String?, size: CGFloat) -> some View {
        AsyncImage(url: catalogRemoteImageURL(url)) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func playFavorite(_ fav: FavoriteItem) {
        let track = CatalogTrack(
            id: fav.providerItemID,
            provider: fav.provider,
            title: fav.title,
            artist: fav.artistName,
            coverURL: fav.coverURL
        )
        onPlayCatalogTrack(track, [track])
    }
}
