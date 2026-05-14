import SwiftUI

// MARK: - Reusable Shimmer Primitives

struct ShimmerEffect<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { t in
            let phase = abs(sin(t.date.timeIntervalSinceReferenceDate * 1.2))
            content()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12 + phase * 0.08),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(.plusLighter)
                }
                .clipped()
        }
    }
}

struct ShimmerRect: View {
    var corner: CGFloat = 10
    var width: CGFloat? = nil
    var height: CGFloat

    var body: some View {
        ShimmerEffect {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: height)
        }
    }
}

struct ShimmerCircle: View {
    let size: CGFloat

    var body: some View {
        ShimmerEffect {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: size, height: size)
        }
    }
}

struct ShimmerLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        ShimmerEffect {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Skeleton Track Row (for track lists)

struct SkeletonTrackRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ShimmerRect(corner: 8, width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerLine(width: 140, height: 14)
                ShimmerLine(width: 90, height: 11)
            }
            Spacer()
            ShimmerLine(width: 30, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Skeleton Artist Profile

struct SkeletonArtistProfile: View {
    var body: some View {
        VStack(spacing: 0) {
            // Hero area
            ZStack(alignment: .bottom) {
                ShimmerRect(corner: 0, height: 340)
                VStack(spacing: 10) {
                    ShimmerCircle(size: 120)
                    ShimmerLine(width: 180, height: 22)
                    ShimmerLine(width: 100, height: 14)
                }
                .padding(.bottom, 24)
            }

            // Action buttons
            HStack(spacing: 16) {
                ShimmerRect(corner: 22, width: 120, height: 44)
                ShimmerRect(corner: 22, width: 120, height: 44)
            }
            .padding(.top, 16)

            // Stats row
            HStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 4) {
                        ShimmerLine(width: 50, height: 16)
                        ShimmerLine(width: 70, height: 11)
                    }
                }
            }
            .padding(.top, 20)

            // Section title
            ShimmerLine(width: 140, height: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            // Track rows
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonTrackRow()
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Skeleton Playlist Header

struct SkeletonPlaylistHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            // Cover artwork
            ShimmerRect(corner: 16, width: 240, height: 240)

            // Title + subtitle
            VStack(spacing: 8) {
                ShimmerLine(width: 200, height: 20)
                ShimmerLine(width: 120, height: 14)
            }

            // Action buttons
            HStack(spacing: 16) {
                ShimmerRect(corner: 22, width: 140, height: 44)
                ShimmerRect(corner: 22, width: 140, height: 44)
            }
            .padding(.top, 4)

            // Track list
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonTrackRow()
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 20)
    }
}

// MARK: - Skeleton Album Card (for grids)

struct SkeletonAlbumCard: View {
    var size: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerRect(corner: 12, width: size, height: size)
            ShimmerLine(width: size * 0.7, height: 13)
            ShimmerLine(width: size * 0.5, height: 11)
        }
    }
}
