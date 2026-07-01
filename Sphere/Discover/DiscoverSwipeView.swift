import SwiftUI

/// Tinder-style discover screen for catalog tracks.
/// Swipe right (or tap heart) — like the track and queue it for next.
/// Swipe left (or tap X) — skip and remove from deck.
/// Tap center play — open the player on this track.
struct DiscoverSwipeView: View {
    let isEnglish: Bool
    let isDarkMode: Bool
    let accent: Color

    var seedTracks: [CatalogTrack] = []
    var onPlay: (CatalogTrack, [CatalogTrack]) -> Void
    var onLike: (CatalogTrack) -> Void
    var onClose: () -> Void

    @State private var deck: [CatalogTrack] = []
    @State private var topOffset: CGSize = .zero
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var likedCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.95)
            content
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 8)
            cardStack
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
            Spacer(minLength: 14)
            controlsBar
                .padding(.bottom, 28)
        }
        .padding(.top, 12)
        .task { await loadInitialDeck() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(isEnglish ? "Discover" : "Найди новое")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(isEnglish ? "Swipe to explore" : "Свайпай и слушай")
                    .font(.nodeMono(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            ZStack {
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                Text("\(likedCount)")
                    .font(.nodeMono(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Card stack

    private var cardStack: some View {
        ZStack {
            if deck.isEmpty {
                emptyState
            } else {
                ForEach(Array(deck.prefix(3).enumerated()).reversed(), id: \.element.compositeKey) { idx, track in
                    let depth = CGFloat(idx)
                    DiscoverTrackCard(
                        track: track,
                        accent: accent,
                        topVisible: idx == 0
                    )
                    .scaleEffect(1 - depth * 0.05)
                    .offset(y: depth * 14)
                    .rotationEffect(.degrees(idx == 0 ? Double(topOffset.width / 14) : 0))
                    .offset(idx == 0 ? topOffset : .zero)
                    .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.85), value: topOffset)
                    .gesture(idx == 0 ? swipeGesture(for: track) : nil)
                    .onTapGesture(count: 1) {
                        if idx == 0 { handlePlay(track) }
                    }
                }
            }
        }
        .frame(height: 480)
    }

    private func swipeGesture(for track: CatalogTrack) -> some Gesture {
        DragGesture()
            .onChanged { value in topOffset = value.translation }
            .onEnded { value in
                let dx = value.translation.width
                if dx > 110 {
                    finalizeSwipe(track: track, liked: true, exitX: 540)
                } else if dx < -110 {
                    finalizeSwipe(track: track, liked: false, exitX: -540)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { topOffset = .zero }
                }
            }
    }

    private func finalizeSwipe(track: CatalogTrack, liked: Bool, exitX: CGFloat) {
        withAnimation(reduceMotion ? .linear(duration: 0.18) : .spring(response: 0.36, dampingFraction: 0.78)) {
            topOffset = CGSize(width: exitX, height: topOffset.height)
        }
        Task {
            await SphereAPIClient.shared.sendDiscoverFeedback(track: track, action: liked ? "like" : "skip")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            advance(removing: track)
            if liked {
                likedCount += 1
                onLike(track)
            }
        }
    }

    private func advance(removing track: CatalogTrack) {
        deck.removeAll { $0.compositeKey == track.compositeKey }
        topOffset = .zero
        if deck.count <= 2 {
            Task { await loadMore() }
        }
    }

    private func handlePlay(_ track: CatalogTrack) {
        onPlay(track, deck)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 28) {
            controlButton(icon: "xmark", color: Color(red: 0.94, green: 0.34, blue: 0.40)) {
                if let top = deck.first { finalizeSwipe(track: top, liked: false, exitX: -540) }
            }
            controlButton(icon: "play.fill", color: .white, foreground: .black, big: true) {
                if let top = deck.first { handlePlay(top) }
            }
            controlButton(icon: "heart.fill", color: Color(red: 0.20, green: 0.74, blue: 0.40)) {
                if let top = deck.first { finalizeSwipe(track: top, liked: true, exitX: 540) }
            }
        }
    }

    private func controlButton(icon: String, color: Color, foreground: Color = .white, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: big ? 24 : 18, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: big ? 78 : 60, height: big ? 78 : 60)
                .background(Circle().fill(color))
                .shadow(color: color.opacity(0.45), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(deck.isEmpty)
    }

    // MARK: - Empty / loading

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text(isEnglish ? "Looking for tracks…" : "Ищем треки…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else if let loadError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(loadError)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(isEnglish ? "Retry" : "Повторить") {
                    Task { await loadInitialDeck(force: true) }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isEnglish ? "That's all for now" : "Пока всё")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isEnglish ? "Come back later for new picks" : "Загляни позже за новыми треками")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                Button(isEnglish ? "Refresh" : "Обновить") {
                    Task { await loadInitialDeck(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
        }
        .padding(40)
    }

    // MARK: - Loading

    private func loadInitialDeck(force: Bool = false) async {
        if !force && !deck.isEmpty { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        if !seedTracks.isEmpty {
            deck = uniqued(seedTracks)
        }
        await loadMore()
    }

    private func loadMore() async {
        let excluded = deck.map { $0.compositeKey.lowercased() }
        do {
            let tracks = try await SphereAPIClient.shared.getDiscoverFeed(limit: 30, excluded: excluded)
            let merged = uniqued(deck + tracks)
            await MainActor.run { deck = merged }
            return
        } catch {
            // Backend without /discover endpoint or transient error — fall back gracefully.
        }
        do {
            let recs = try await SphereAPIClient.shared.getRecommendations()
            let merged = uniqued(deck + recs.tracks.shuffled())
            await MainActor.run { deck = merged }
        } catch {
            do {
                let queries = ["new", "trending", "indie", "pop", "electro"]
                let q = queries.randomElement() ?? "new"
                let res = try await SphereAPIClient.shared.search(query: q, limit: 20)
                let merged = uniqued(deck + res.tracks.shuffled())
                await MainActor.run { deck = merged }
            } catch {
                await MainActor.run {
                    if deck.isEmpty {
                        loadError = isEnglish ? "Couldn't load tracks" : "Не удалось загрузить треки"
                    }
                }
            }
        }
    }

    private func uniqued(_ tracks: [CatalogTrack]) -> [CatalogTrack] {
        var seen = Set<String>()
        var out: [CatalogTrack] = []
        for t in tracks where !seen.contains(t.compositeKey) {
            seen.insert(t.compositeKey)
            out.append(t)
        }
        return out
    }
}

// MARK: - Card

private struct DiscoverTrackCard: View {
    let track: CatalogTrack
    let accent: Color
    let topVisible: Bool

    var body: some View {
        ZStack {
            cover
            gradientFooter
            footerContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.9)
        }
        .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 12)
    }

    @ViewBuilder
    private var cover: some View {
        let url = catalogRemoteImageURL(track.coverURL)
        ZStack {
            Color.black
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            accent.opacity(0.45)
                            Image(systemName: "music.note")
                                .font(.system(size: 60, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            } else {
                ZStack {
                    accent.opacity(0.45)
                    Image(systemName: "music.note")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var gradientFooter: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.05), .black.opacity(0.65), .black.opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var footerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            HStack(spacing: 8) {
                Text(track.provider.uppercased())
                    .font(.nodeMono(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.18)))
                if !track.durationFormatted.isEmpty {
                    Text(track.durationFormatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if topVisible {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                }
            }
            Text(track.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(track.artist)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(20)
    }
}
