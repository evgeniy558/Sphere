import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case guide, genres, artists, setup
}

struct OnboardingView: View {
    let accent: Color
    let isDarkMode: Bool
    let isEnglish: Bool
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .guide
    @State private var guidePage = 0
    @State private var selectedGenres: Set<String> = []
    @State private var selectedArtists: Set<String> = []
    @State private var selectedTracks: Set<String> = []
    @State private var artistSearch = ""
    @State private var searchResults: [CatalogArtist] = []
    @State private var genreArtists: [String: [CatalogArtist]] = [:]
    @State private var recommendedTracks: [CatalogTrack] = []
    @State private var isSearching = false
    @State private var isLoadingArtists = false
    @State private var isLoadingTracks = false
    @State private var searchDebounce: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var setupStatusIndex = 0
    @State private var setupOrbitPhase: CGFloat = 0
    @State private var didSeedGenres = false

    private let genreOptions: [GenreOption] = GenreOption.catalog

    private var guidePages: [GuidePageData] { GuidePageData.pages(isEnglish: isEnglish) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .guide: guideStep
            case .genres: genresStep
            case .artists: artistsStep
            case .setup: setupStep
            }
        }
        .preferredColorScheme(.dark)
        .alert(isEnglish ? "Couldn't save" : "Не удалось сохранить", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Guide

    private var guideStep: some View {
        let page = guidePages[guidePage]
        return VStack(spacing: 0) {
            HStack {
                if guidePage > 0 {
                    OnboardingCircleButton(systemName: "chevron.left") {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { guidePage -= 1 }
                    }
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                OnboardingOutlinePill(title: skipLabel) { skipToGenres() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            TabView(selection: $guidePage) {
                ForEach(Array(guidePages.enumerated()), id: \.offset) { idx, p in
                    OnboardingPhoneFrame {
                        GuidePreviewContent(kind: p.preview)
                    }
                    .frame(maxWidth: .infinity)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: 470)
            .animation(.spring(response: 0.48, dampingFraction: 0.86), value: guidePage)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<guidePages.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == guidePage ? Color.white : Color.white.opacity(0.22))
                            .frame(width: idx == guidePage ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: guidePage)
                    }
                }
                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(OnboardingPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .animation(.easeInOut(duration: 0.25), value: guidePage)

            OnboardingPrimaryButton(
                title: guidePage < guidePages.count - 1
                    ? (isEnglish ? "Continue" : "Далее")
                    : (isEnglish ? "Get Started" : "Начать")
            ) {
                if guidePage < guidePages.count - 1 {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { guidePage += 1 }
                } else {
                    seedGenresIfNeeded()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .genres }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Genres

    private var genresStep: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingCircleButton(systemName: "chevron.left") {
                    withAnimation { step = .guide; guidePage = guidePages.count - 1 }
                }
                Spacer()
                OnboardingOutlinePill(title: skipLabel) { Task { await skipAndSavePreferences() } }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(isEnglish ? "Pick what you love" : "Выбери, что любишь")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(isEnglish
                     ? "Everything's on to start — tap to skip what's not for you. Node keeps learning as you listen."
                     : "Сначала всё включено — снимай то, что не твоё. Node подстраивается, когда ты слушаешь.")
                    .font(.system(size: 15))
                    .foregroundStyle(OnboardingPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .onAppear { seedGenresIfNeeded() }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(genreOptions) { option in
                        let selected = selectedGenres.contains(option.id)
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                if selected { selectedGenres.remove(option.id) }
                                else { selectedGenres.insert(option.id) }
                            }
                        } label: {
                            GenrePickerCard(title: option.title, color: option.color, selected: selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OnboardingPalette.pickGreen)
                Text(isEnglish ? "\(selectedGenres.count) selected" : "Выбрано: \(selectedGenres.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.bottom, 10)

            OnboardingPrimaryButton(
                title: isEnglish ? "Continue" : "Далее",
                enabled: !selectedGenres.isEmpty && !isSaving
            ) {
                Task { await loadArtistsForGenres() }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .artists }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Artists + tracks

    private var artistsStep: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingCircleButton(systemName: "chevron.left") {
                    withAnimation { step = .genres }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(isEnglish ? "Pick artists you want to follow" : "Выбери артистов")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text(isEnglish
                     ? "Follow a few favorites. Search any artist or pick from your genres below."
                     : "Выбери любимых. Поиск или подборки по жанрам ниже.")
                    .font(.system(size: 15))
                    .foregroundStyle(OnboardingPalette.muted)
                Text(isEnglish ? "\(selectedArtists.count) followed" : "Выбрано: \(selectedArtists.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            OnboardingSearchField(
                text: $artistSearch,
                placeholder: isEnglish ? "Search artists" : "Поиск артистов"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: artistSearch) { searchArtists($0) }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !artistSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        artistRowSection(title: isEnglish ? "Results" : "Результаты", artists: searchResults)
                    } else {
                        if isLoadingArtists {
                            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 24)
                        }
                        ForEach(Array(selectedGenres).sorted(), id: \.self) { genre in
                            if let list = genreArtists[genre], !list.isEmpty {
                                artistRowSection(
                                    title: isEnglish ? "Top in \(genre)" : "Топ: \(genre)",
                                    artists: list
                                )
                            }
                        }
                    }

                    if !recommendedTracks.isEmpty {
                        Text(isEnglish ? "Recommended tracks" : "Рекомендованные треки")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recommendedTracks) { track in
                                    trackTile(track)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 100)
            }

            OnboardingPrimaryButton(
                title: isEnglish ? "Continue" : "Далее",
                enabled: !isSaving
            ) { saveThenSetup() }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .task {
            await loadRecommendedTracks()
            if genreArtists.isEmpty { await loadArtistsForGenres() }
        }
    }

    private func artistRowSection(title: String, artists: [CatalogArtist]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.muted)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(artists) { artist in
                        ArtistPickerTile(
                            name: artist.name,
                            subtitle: artist.provider.isEmpty ? nil : artist.provider,
                            imageURL: artist.imageURL,
                            selected: selectedArtists.contains(artist.name)
                        ) {
                            toggleArtist(artist.name)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func trackTile(_ track: CatalogTrack) -> some View {
        let key = track.compositeKey
        let picked = selectedTracks.contains(key)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if picked { selectedTracks.remove(key) }
                else { selectedTracks.insert(key) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: catalogRemoteImageURL(track.coverURL)) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Rectangle().fill(OnboardingPalette.surfaceRaised) }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Image(systemName: picked ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(picked ? .white : .white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(picked ? OnboardingPalette.pickGreen : Color.black.opacity(0.45)))
                        .padding(8)
                }
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(width: 140, alignment: .leading)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingPalette.muted)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Setup

    private var setupStep: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 48)
                let hubSide = min(geo.size.width, geo.size.height) * 0.24

                ForEach(setupFlyingItems(in: geo.size), id: \.id) { item in
                    setupFlyingView(item, center: center, hubSide: hubSide, size: geo.size)
                }

                Image("NodeAuthIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: hubSide, height: hubSide)
                    .clipShape(RoundedRectangle(cornerRadius: hubSide * 0.22, style: .continuous))
                    .shadow(color: Color.white.opacity(0.18), radius: 18, y: 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: hubSide * 0.22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .position(center)
            }

            VStack {
                Spacer()
                Text(setupStatusTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.35), value: setupStatusIndex)
                Text(isEnglish ? "Getting things ready…" : "Готовим всё для тебя…")
                    .font(.system(size: 16))
                    .foregroundStyle(OnboardingPalette.muted)
                    .padding(.top, 6)
                Spacer().frame(height: 80)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                setupOrbitPhase = 1
            }
            cycleSetupStatus()
        }
    }

    // MARK: - Helpers

    private var skipLabel: String { isEnglish ? "Skip" : "Пропустить" }

    private func seedGenresIfNeeded() {
        guard !didSeedGenres else { return }
        didSeedGenres = true
        if selectedGenres.isEmpty {
            selectedGenres = Set(genreOptions.map(\.id))
        }
    }

    private func skipToGenres() {
        seedGenresIfNeeded()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .genres }
    }

    private func toggleArtist(_ name: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedArtists.contains(name) { selectedArtists.remove(name) }
            else { selectedArtists.insert(name) }
        }
    }

    private var setupStatusTitle: String {
        let titles = isEnglish
            ? ["Setting up your tracks", "Setting up your playlists", "Setting up your artists"]
            : ["Настраиваем треки", "Настраиваем плейлисты", "Настраиваем артистов"]
        return titles[min(setupStatusIndex, titles.count - 1)]
    }

    private struct SetupFloatItem: Identifiable {
        let id: String
        let symbol: String
        let angle: CGFloat
        let lane: CGFloat
        let delay: CGFloat
    }

    private func setupFlyingItems(in size: CGSize) -> [SetupFloatItem] {
        [
            SetupFloatItem(id: "1", symbol: "music.note.list", angle: 0.2, lane: 0.42, delay: 0.0),
            SetupFloatItem(id: "2", symbol: "music.note", angle: 1.4, lane: 0.48, delay: 0.18),
            SetupFloatItem(id: "3", symbol: "opticaldisc.fill", angle: 2.6, lane: 0.38, delay: 0.36),
            SetupFloatItem(id: "4", symbol: "waveform", angle: 3.8, lane: 0.44, delay: 0.54),
            SetupFloatItem(id: "5", symbol: "heart.fill", angle: 5.0, lane: 0.40, delay: 0.72),
        ]
    }

    private func setupFlyingView(_ item: SetupFloatItem, center: CGPoint, hubSide: CGFloat, size: CGSize) -> some View {
        let cycle = (setupOrbitPhase + item.delay).truncatingRemainder(dividingBy: 1)
        let approach = sin(cycle * .pi)
        let radius = (1 - approach) * min(size.width, size.height) * item.lane
        let spin = item.angle + cycle * .pi * 2
        let x = center.x + cos(spin) * radius
        let y = center.y + sin(spin) * radius
        let iconScale = 0.55 + approach * 0.45

        return Image(systemName: item.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55 + approach * 0.35))
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08 + approach * 0.10))
            )
            .scaleEffect(iconScale)
            .opacity(0.35 + approach * 0.65)
            .position(x: x, y: y)
    }

    private func cycleSetupStatus() {
        Task {
            for i in 0..<3 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run { withAnimation { setupStatusIndex = i } }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run { onComplete() }
        }
    }

    // MARK: - API

    private func searchArtists(_ query: String) {
        searchDebounce?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await SphereAPIClient.shared.search(query: trimmed, limit: 12)
                await MainActor.run {
                    searchResults = results.artists
                    isSearching = false
                }
            } catch {
                await MainActor.run { isSearching = false }
            }
        }
    }

    private func loadArtistsForGenres() async {
        await MainActor.run { isLoadingArtists = true }
        var map: [String: [CatalogArtist]] = [:]
        for genre in selectedGenres {
            do {
                let results = try await SphereAPIClient.shared.search(query: genre, limit: 8)
                map[genre] = results.artists
            } catch { map[genre] = [] }
        }
        await MainActor.run {
            genreArtists = map
            isLoadingArtists = false
        }
    }

    private func loadRecommendedTracks() async {
        await MainActor.run { isLoadingTracks = true }
        var tracks: [CatalogTrack] = []
        do {
            let reco = try await SphereAPIClient.shared.getRecommendations()
            tracks.append(contentsOf: reco.tracks.prefix(12))
        } catch { }
        if tracks.count < 8, let genre = selectedGenres.first {
            do {
                let search = try await SphereAPIClient.shared.search(query: genre, limit: 10)
                for t in search.tracks where !tracks.contains(where: { $0.compositeKey == t.compositeKey }) {
                    tracks.append(t)
                }
            } catch { }
        }
        await MainActor.run {
            recommendedTracks = Array(tracks.prefix(16))
            isLoadingTracks = false
        }
    }

    private func saveThenSetup() {
        Task {
            await MainActor.run { isSaving = true; saveError = nil }
            do {
                try await SphereAPIClient.shared.savePreferences(
                    artists: Array(selectedArtists),
                    genres: Array(selectedGenres)
                )
                await MainActor.run {
                    isSaving = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .setup }
                }
            } catch {
                await MainActor.run { isSaving = false; saveError = error.localizedDescription }
            }
        }
    }

    private func skipAndSavePreferences() async {
        await MainActor.run { isSaving = true; saveError = nil }
        do {
            try await SphereAPIClient.shared.savePreferences(artists: [], genres: [])
            await MainActor.run {
                isSaving = false
                withAnimation { step = .setup }
            }
        } catch {
            await MainActor.run { isSaving = false; saveError = error.localizedDescription }
        }
    }
}

// MARK: - Models

private struct GuidePageData {
    let title: String
    let subtitle: String
    let preview: GuidePreviewKind

    static func pages(isEnglish: Bool) -> [GuidePageData] {
        if isEnglish {
            return [
                GuidePageData(title: "Welcome to Node", subtitle: "A music-first home with recommendations tuned to you.", preview: .welcome),
                GuidePageData(title: "Lyrics", subtitle: "Read along, search the words, revisit the line that stuck.", preview: .lyrics),
                GuidePageData(title: "Chapters", subtitle: "Tap a chapter, land in the moment — no more scrubbing.", preview: .mixes),
                GuidePageData(title: "Trending", subtitle: "See what listeners are tuning into right now.", preview: .trending),
                GuidePageData(title: "Playlists", subtitle: "Build queues for what you want next.", preview: .playlists),
                GuidePageData(title: "New releases", subtitle: "Fresh drops and updates from artists you follow.", preview: .releases),
            ]
        }
        return [
            GuidePageData(title: "Добро пожаловать в Node", subtitle: "Музыка и рекомендации, подстроенные под тебя.", preview: .welcome),
            GuidePageData(title: "Тексты", subtitle: "Читай строки, ищи слова, возвращайся к любимым местам.", preview: .lyrics),
            GuidePageData(title: "Главы", subtitle: "Тап по главе — сразу в нужный момент трека.", preview: .mixes),
            GuidePageData(title: "В тренде", subtitle: "Что слушают прямо сейчас.", preview: .trending),
            GuidePageData(title: "Плейлисты", subtitle: "Собирай очередь под настроение.", preview: .playlists),
            GuidePageData(title: "Новые релизы", subtitle: "Свежие дропы от любимых артистов.", preview: .releases),
        ]
    }
}

private struct GenreOption: Identifiable {
    let id: String
    let title: String
    let color: Color

    static let catalog: [GenreOption] = {
        let titles = [
            "Pop", "Hip-Hop", "Rock", "Electronic", "Indie", "R&B",
            "K-Pop", "Russian Rap", "Metal", "Jazz", "Lo-Fi", "Classical",
        ]
        return titles.enumerated().map { index, title in
            GenreOption(
                id: title,
                title: title,
                color: NodeDesignStyle.tilePalette[index % NodeDesignStyle.tilePalette.count]
            )
        }
    }()
}
