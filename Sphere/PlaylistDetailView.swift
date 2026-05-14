import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let playlist: CatalogPlaylist
    let accent: Color
    let isDarkMode: Bool
    let isEnglish: Bool
    let onPlayTrack: (CatalogTrack, [CatalogTrack]) -> Void
    let onPlayAll: ([CatalogTrack]) -> Void
    let onShuffle: ([CatalogTrack]) -> Void

    @State private var isDownloading = false
    @State private var dominantColor: Color?
    @State private var coverImage: UIImage?

    private var tracks: [CatalogTrack] { playlist.tracks ?? [] }
    private var playlistLabel: String { isEnglish ? "Playlist" : "Плейлист" }
    private var themeColor: Color { dominantColor ?? accent }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: blurred artwork + gradient
                backgroundLayer
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                        actionButtons
                            .padding(.top, 16)
                            .padding(.horizontal, 20)
                        trackList
                            .padding(.top, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .scaleEffect(1.3)
                    .clipped()
            }

            LinearGradient(
                colors: [
                    themeColor.opacity(0.5),
                    (isDarkMode ? Color.black : Color(.systemBackground)).opacity(0.7),
                    (isDarkMode ? Color.black : Color(.systemBackground)),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 16) {
            // Large cover artwork with shadow
            AsyncImage(url: URL(string: playlist.coverURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .onAppear { extractColor(from: phase) }
                default:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(themeColor.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: themeColor.opacity(0.4), radius: 24, y: 12)

            // Title + subtitle
            VStack(spacing: 6) {
                Text(playlist.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(playlistLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                if !tracks.isEmpty {
                    Text("\(tracks.count) \(isEnglish ? "tracks" : (tracks.count == 1 ? "трек" : "треков"))")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }

    // MARK: - Action Buttons (Apple Music capsule style)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Play button
            Button { onPlayAll(tracks) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isEnglish ? "Play" : "Играть")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(themeColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(tracks.isEmpty)

            // Shuffle button
            Button { onShuffle(tracks) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isEnglish ? "Shuffle" : "Перемешать")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(themeColor.opacity(0.18))
                .foregroundStyle(themeColor)
                .clipShape(Capsule())
            }
            .disabled(tracks.isEmpty)
        }
    }

    // MARK: - Secondary actions (download)

    // MARK: - Track List

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Download button row
            HStack {
                Spacer()
                Button {
                    guard !tracks.isEmpty, !isDownloading else { return }
                    isDownloading = true
                    Task { @MainActor in
                        defer { isDownloading = false }
                        for t in tracks {
                            try? await DownloadsStore.shared.download(track: t)
                        }
                    }
                } label: {
                    Image(systemName: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isDownloading || tracks.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if tracks.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    SkeletonPlaylistHeader()
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.compositeKey) { idx, track in
                        ArtistTrackRow(
                            index: idx + 1,
                            track: track,
                            isDarkMode: isDarkMode,
                            onTap: { onPlayTrack(track, tracks) }
                        )
                        if idx < tracks.count - 1 {
                            Divider()
                                .overlay(Color(.systemGray5).opacity(0.5))
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Color Extraction

    private func extractColor(from phase: AsyncImagePhase) {
        guard case .success(let image) = phase else { return }
        let renderer = ImageRenderer(content: image.resizable().frame(width: 50, height: 50))
        renderer.scale = 1
        guard let uiImage = renderer.uiImage else { return }
        coverImage = uiImage
        dominantColor = uiImage.averageColor.map { Color($0) }
    }
}

// MARK: - UIImage Average Color

private extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1.0
        )
    }
}
