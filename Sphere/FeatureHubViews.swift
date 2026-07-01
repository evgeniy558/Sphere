import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Plus action menu

enum PlusHubAction: String, Identifiable {
    case jam, blend, playlist, groupPlaylist, upload
    var id: String { rawValue }
}

struct PlusActionMenuSheet: View {
    let isEnglish: Bool
    let accent: Color
    let onSelect: (PlusHubAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text(isEnglish ? "Create" : "Создать")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                menuRow(icon: "person.3.fill", title: isEnglish ? "Jam session" : "Jam-сессия", subtitle: isEnglish ? "Group listening with queue" : "Совместное прослушивание с очередью") {
                    onSelect(.jam); dismiss()
                }
                menuRow(icon: "waveform.path", title: isEnglish ? "Blend" : "Blend", subtitle: isEnglish ? "Taste-merged playlist" : "Плейлист из вкусов") {
                    onSelect(.blend); dismiss()
                }
                menuRow(icon: "music.note.list", title: isEnglish ? "Group playlist" : "Групповой плейлист", subtitle: isEnglish ? "Collaborative playlist" : "Совместный плейлист") {
                    onSelect(.groupPlaylist); dismiss()
                }
                menuRow(icon: "text.badge.plus", title: isEnglish ? "Playlist" : "Плейлист", subtitle: isEnglish ? "Create your own playlist" : "Создайте свой плейлист") {
                    onSelect(.playlist); dismiss()
                }
                menuRow(icon: "arrow.up.circle.fill", title: isEnglish ? "Upload track" : "Загрузить трек", subtitle: isEnglish ? "Your audio to the cloud" : "Ваше аудио в облако") {
                    onSelect(.upload); dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.fraction(0.56)])
        .presentationDragIndicator(.visible)
    }

    private func menuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Jam

struct JamHubView: View {
    let isEnglish: Bool
    let accent: Color
    @State private var title = ""
    @State private var session: JamSession?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isEnglish ? "Session title" : "Название сессии", text: $title)
                    Button(isEnglish ? "Create Jam" : "Создать Jam") {
                        Task { await create() }
                    }
                    .disabled(isLoading)
                }
                if let s = session {
                    Section(isEnglish ? "Active session" : "Активная сессия") {
                        Text(s.title).font(.headline)
                        Text("ID: \(s.id)").font(.caption).foregroundStyle(.secondary)
                        if let q = s.queue, !q.isEmpty {
                            ForEach(q) { item in
                                Text("\(item.title) — \(item.artist)")
                            }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle(isEnglish ? "Jam" : "Jam")
        }
    }

    private func create() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            session = try await SphereAPIClient.shared.createJamSession(title: title.isEmpty ? (isEnglish ? "Jam" : "Jam") : title)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Blend

struct BlendHubView: View {
    let isEnglish: Bool
    let accent: Color
    @State private var blends: [BlendSummary] = []
    @State private var title = ""
    @State private var memberIDsText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section(isEnglish ? "New blend" : "Новый blend") {
                    TextField(isEnglish ? "Title" : "Название", text: $title)
                    TextField(isEnglish ? "Member user IDs (comma-separated)" : "ID участников через запятую", text: $memberIDsText)
                    Button(isEnglish ? "Create" : "Создать") { Task { await create() } }
                }
                Section(isEnglish ? "My blends" : "Мои blends") {
                    ForEach(blends) { b in
                        NavigationLink(b.title) {
                            BlendDetailLoaderView(blendID: b.id, isEnglish: isEnglish, accent: accent)
                        }
                    }
                }
            }
            .navigationTitle("Blend")
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        blends = (try? await SphereAPIClient.shared.listBlends()) ?? []
    }

    private func create() async {
        let ids = memberIDsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            _ = try await SphereAPIClient.shared.createBlend(title: title.isEmpty ? "Blend" : title, memberIDs: ids)
            title = ""; memberIDsText = ""
            await reload()
        } catch let err {
            error = err.localizedDescription
        }
    }
}

struct BlendDetailLoaderView: View {
    let blendID: String
    let isEnglish: Bool
    let accent: Color
    @State private var detail: BlendDetail?

    var body: some View {
        List {
            if let d = detail {
                Section {
                    ForEach(d.tracks ?? []) { t in
                        HStack {
                            Text(t.title)
                            Spacer()
                            Text(t.match_label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(isEnglish ? "Members" : "Участники") {
                    ForEach(d.members ?? []) { m in
                        Text(m.name.isEmpty ? m.username : m.name)
                    }
                }
            }
        }
        .navigationTitle(detail?.title ?? "Blend")
        .task {
            detail = try? await SphereAPIClient.shared.getBlend(id: blendID)
        }
    }
}

// MARK: - Group playlists

struct GroupPlaylistHubView: View {
    let isEnglish: Bool
    let accent: Color
    @State private var playlists: [GroupPlaylist] = []
    @State private var newTitle = ""
    @State private var createStep: PlaylistCreateStep = .name
    @State private var createdPlaylist: GroupPlaylist?
    @State private var selectedTracks: [CatalogTrack] = []
    @State private var suggestedTracks: [CatalogTrack] = []
    @State private var searchQuery = ""
    @State private var searchResults: [CatalogTrack] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isCreating = false
    @State private var isSaving = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var openedPlaylist: GroupPlaylist?

    private enum PlaylistCreateStep {
        case name
        case tracks
    }

    private var displayedTracks: [CatalogTrack] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? suggestedTracks : searchResults
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    createHeader
                    if createStep == .name {
                        createNameStep
                    } else {
                        createTracksStep
                    }
                    myPlaylistsSection
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isEnglish ? "Playlist" : "Плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await reloadPlaylists()
                await loadSuggestedTracksIfNeeded()
            }
            .onChange(of: searchQuery) { newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear { searchTask?.cancel() }
            .sheet(item: $openedPlaylist) { playlist in
                GroupPlaylistDetailView(playlistID: playlist.id, isEnglish: isEnglish, accent: accent)
            }
        }
    }

    private var createHeader: some View {
        Text(isEnglish ? "Create a playlist" : "Создание плейлиста")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private var createNameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEnglish ? "Step 1: Enter playlist name" : "Шаг 1: Введите название плейлиста")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            TextField(isEnglish ? "Playlist name" : "Название плейлиста", text: $newTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .librarySectionGlass(cornerRadius: 14)

            Button {
                Task { await createPlaylistAndMoveToTracks() }
            } label: {
                HStack {
                    if isCreating { ProgressView().tint(.white) }
                    Text(isEnglish ? "Continue to track selection" : "Далее к выбору треков")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .libraryGlassPill(selected: true)
            }
            .buttonStyle(.plain)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .libraryGlassCard(cornerRadius: 18)
        .padding(.horizontal, 16)
    }

    private var createTracksStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEnglish ? "Step 2: Select tracks" : "Шаг 2: Выберите треки")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            TextField(isEnglish ? "Search tracks" : "Поиск треков", text: $searchQuery)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .librarySectionGlass(cornerRadius: 14)

            if isSearching {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }

            if displayedTracks.isEmpty && !isSearching {
                Text(isEnglish ? "No tracks found" : "Треки не найдены")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(displayedTracks.prefix(30).enumerated()), id: \.offset) { _, track in
                        Button { toggleTrack(track) } label: {
                            playlistTrackPickerRow(track)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                Task { await saveTracksAndOpenPlaylist() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) }
                    Text(isEnglish ? "Create playlist" : "Создать плейлист")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("\(selectedTracks.count)")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .libraryGlassPill(selected: true)
            }
            .buttonStyle(.plain)
            .disabled(isSaving || createdPlaylist == nil)
        }
        .padding(14)
        .libraryGlassCard(cornerRadius: 18)
        .padding(.horizontal, 16)
    }

    private var myPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEnglish ? "My playlists" : "Мои плейлисты")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            if playlists.isEmpty {
                Text(isEnglish ? "No playlists yet" : "Пока нет плейлистов")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            GroupPlaylistDetailView(playlistID: playlist.id, isEnglish: isEnglish, accent: accent)
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        Image(systemName: "music.note.list")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.75))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(isEnglish ? "\(playlist.track_count) tracks" : "\(playlist.track_count) треков")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.white.opacity(0.58))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.45))
                            }
                            .padding(12)
                            .libraryGlassCard(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func playlistTrackPickerRow(_ track: CatalogTrack) -> some View {
        let selected = isTrackSelected(track)
        return HStack(spacing: 10) {
            AsyncImage(url: catalogRemoteImageURL(track.coverURL)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(selected ? .green : .white.opacity(0.86))
        }
        .padding(10)
        .librarySectionGlass(cornerRadius: 14)
    }

    private func isTrackSelected(_ track: CatalogTrack) -> Bool {
        selectedTracks.contains(where: { trackKey($0) == trackKey(track) })
    }

    private func toggleTrack(_ track: CatalogTrack) {
        let key = trackKey(track)
        if let index = selectedTracks.firstIndex(where: { trackKey($0) == key }) {
            selectedTracks.remove(at: index)
        } else {
            selectedTracks.append(track)
        }
    }

    private func trackKey(_ track: CatalogTrack) -> String {
        "\(track.provider)::\(track.id)"
    }

    private func createPlaylistAndMoveToTracks() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        await MainActor.run {
            isCreating = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isCreating = false } }
        do {
            let playlist = try await SphereAPIClient.shared.createGroupPlaylist(title: title)
            await MainActor.run {
                createdPlaylist = playlist
                createStep = .tracks
                newTitle = ""
            }
            await loadSuggestedTracksIfNeeded()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveTracksAndOpenPlaylist() async {
        guard let playlist = createdPlaylist else { return }
        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }

        for track in selectedTracks {
            try? await SphereAPIClient.shared.addTrackToGroupPlaylist(playlistID: playlist.id, track: track)
        }

        let updated = (try? await SphereAPIClient.shared.listMyGroupPlaylists()) ?? playlists
        await MainActor.run {
            playlists = updated
            openedPlaylist = updated.first(where: { $0.id == playlist.id }) ?? playlist
            createStep = .name
            createdPlaylist = nil
            selectedTracks = []
            searchResults = []
            searchQuery = ""
        }
    }

    private func loadSuggestedTracksIfNeeded() async {
        if !suggestedTracks.isEmpty { return }
        let recs = try? await SphereAPIClient.shared.getRecommendations()
        await MainActor.run {
            suggestedTracks = Array((recs?.tracks ?? []).prefix(30))
        }
    }

    private func scheduleSearch(for rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            let response = try? await SphereAPIClient.shared.search(query: query, limit: 30)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                searchResults = response?.tracks ?? []
                isSearching = false
            }
        }
    }

    private func reloadPlaylists() async {
        let mine = (try? await SphereAPIClient.shared.listMyGroupPlaylists()) ?? []
        await MainActor.run { playlists = mine }
    }
}

struct GroupPlaylistDetailView: View {
    let playlistID: String
    let isEnglish: Bool
    let accent: Color
    @State private var detail: GroupPlaylistDetail?

    var body: some View {
        List {
            if let d = detail {
                ForEach(d.tracks) { t in
                    Text("\(t.title) — \(t.artist)")
                }
            }
        }
        .navigationTitle(detail?.title ?? "")
        .task {
            detail = try? await SphereAPIClient.shared.getGroupPlaylist(id: playlistID)
        }
    }
}

// MARK: - Uploads

struct UploadsHubView: View {
    let isEnglish: Bool
    let accent: Color
    @State private var uploads: [UserUpload] = []
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showPicker = true
                } label: {
                    Label(isEnglish ? "Pick audio file" : "Выбрать аудиофайл", systemImage: "plus.circle.fill")
                }
                ForEach(uploads) { u in
                    VStack(alignment: .leading) {
                        Text(u.title).font(.headline)
                        Text(u.artist_name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEnglish ? "Uploads" : "Загрузки")
            .task { await reload() }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { url in
                    Task { await upload(url: url) }
                }
            }
        }
    }

    private func reload() async {
        uploads = (try? await SphereAPIClient.shared.listUploads()) ?? []
    }

    private func upload(url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        _ = try? await SphereAPIClient.shared.uploadAudioFile(
            data: data,
            fileName: name,
            title: name,
            artistName: isEnglish ? "Unknown" : "Неизвестно"
        )
        await reload()
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio], asCopy: true)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let u = urls.first else { return }
            onPick(u)
        }
    }
}

// MARK: - Daily mix cover (first track + MIX badge)

struct DailyMixCoverArtwork: View {
    let mix: DailyMix
    let mixIndex: Int
    var size: CGFloat = 140
    var accent: Color = .accentColor

    private var badgeText: String { mix.badgeLabel(mixIndex: mixIndex) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverImage
            mixBadge
                .padding(10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = catalogRemoteImageURL(mix.artworkCoverURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [accent, accent.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var mixBadge: some View {
        Text(badgeText)
            .font(.system(size: badgeFontSize, weight: .heavy))
            .foregroundStyle(.black)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.88).opacity(0.92))
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var badgeFontSize: CGFloat {
        size > 120 ? 15 : 13
    }
}

// MARK: - Daily mixes section

struct DailyMixesHomeSection: View {
    let mixes: [DailyMix]
    let isEnglish: Bool
    let isDarkMode: Bool
    let accent: Color
    let onOpenMix: (DailyMix) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        if !mixes.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEnglish ? "Made for you" : "Для вас")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 4)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(mixes.prefix(4).enumerated()), id: \.element.id) { index, mix in
                        Button { onOpenMix(mix) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                DailyMixCoverArtwork(
                                    mix: mix,
                                    mixIndex: index + 1,
                                    size: 160,
                                    accent: accent
                                )
                                .frame(height: 160)
                                Text(mix.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

// MARK: - Daily mix detail (Spotify-style layout, Node styling)

struct DailyMixDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let mix: DailyMix
    let mixIndex: Int
    let accent: Color
    let isDarkMode: Bool
    let isEnglish: Bool
    let onPlayTrack: (CatalogTrack, [CatalogTrack]) -> Void
    let onPlayAll: ([CatalogTrack]) -> Void
    let onShuffle: ([CatalogTrack]) -> Void

    @State private var dominantColor: Color?
    @State private var coverImage: UIImage?

    private var tracks: [CatalogTrack] { mix.tracks }
    private var themeColor: Color { dominantColor ?? accent }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                        actionRow
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                        trackList
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 48)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 64)
                    .scaleEffect(1.25)
                    .clipped()
            }
            LinearGradient(
                colors: [
                    themeColor.opacity(0.55),
                    (isDarkMode ? Color.black : Color(.systemBackground)).opacity(0.75),
                    isDarkMode ? Color.black : Color(.systemBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 14) {
            DailyMixCoverArtwork(mix: mix, mixIndex: mixIndex, size: 300, accent: accent)
                .shadow(color: themeColor.opacity(0.45), radius: 28, y: 14)
                .onAppear { loadCoverColor() }

            VStack(spacing: 6) {
                Text(mix.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 20)

                if !mix.artistsLine.isEmpty {
                    Text(mix.artistsLine)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                }

                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.caption)
                    Text(isEnglish ? "Node Mix" : "Микс Node")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.tertiary)

                if !tracks.isEmpty {
                    let duration = mix.formattedTotalDuration(isEnglish: isEnglish)
                    let countLabel = isEnglish
                        ? "\(tracks.count) tracks"
                        : "\(tracks.count) \(tracks.count == 1 ? "трек" : (tracks.count < 5 ? "трека" : "треков"))"
                    Text([duration, countLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 12)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                onShuffle(tracks)
                dismiss()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .disabled(tracks.isEmpty)
            .buttonStyle(.plain)

            Button {
                onPlayAll(tracks)
                dismiss()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color(white: 0.92)))
            }
            .disabled(tracks.isEmpty)
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracks.isEmpty {
                Text(isEnglish ? "No tracks in this mix yet" : "В миксе пока нет треков")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.compositeKey) { idx, track in
                        ArtistTrackRow(
                            index: idx + 1,
                            track: track,
                            isDarkMode: isDarkMode,
                            onTap: {
                                onPlayTrack(track, tracks)
                                dismiss()
                            }
                        )
                        if idx < tracks.count - 1 {
                            Divider()
                                .overlay(Color(.systemGray5).opacity(0.45))
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func loadCoverColor() {
        guard let url = catalogRemoteImageURL(mix.artworkCoverURL) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let uiImage = UIImage(data: data) else { return }
            await MainActor.run {
                coverImage = uiImage
                dominantColor = uiImage.averageColor.map { Color($0) }
            }
        }
    }
}

private extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: CIVector(cgRect: inputImage.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

// MARK: - My Wave button

struct MyWaveLaunchButton: View {
    let isEnglish: Bool
    let isDarkMode: Bool
    let accent: Color
    let isActive: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Animated waveform bars instead of circle icon
                MyWaveBars(isActive: isActive, accent: accent)
                    .frame(width: 28, height: 28)

                Text(isEnglish ? "My Wave" : "Моя волна")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(accent))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPressed = pressing }
        }, perform: {})
    }
}

/// Simple animated waveform bars for the My Wave button
private struct MyWaveBars: View {
    let isActive: Bool
    let accent: Color

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 0.3)) { _ in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(accent)
                            .frame(width: 3, height: CGFloat.random(in: 6...24))
                    }
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.4))
                        .frame(width: 3, height: [8, 16, 12, 20][i])
                }
            }
        }
    }
}
