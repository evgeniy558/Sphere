import SwiftUI

/// Brink-style colorful square tile reused for genres, library quick tiles and mood cards.
/// Always dark-friendly: the tile is fully colored, white text, optional checkmark / icon.
struct NodeColorTile: View {
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    var selected: Bool = false
    var stackedThumbs: Bool = true
    var trailing: String? = nil
    var aspectRatio: CGFloat? = 1

    init(
        title: String,
        subtitle: String? = nil,
        icon: String = "music.note",
        color: Color,
        selected: Bool = false,
        stackedThumbs: Bool = true,
        trailing: String? = nil,
        aspectRatio: CGFloat? = 1
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.selected = selected
        self.stackedThumbs = stackedThumbs
        self.trailing = trailing
        self.aspectRatio = aspectRatio
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            iconDecor
            label
            checkmarkOverlay
        }
        .applyAspect(aspectRatio)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { liquidGlassBorder }
        .shadow(color: color.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var background: some View {
        LinearGradient(
            colors: [color.opacity(0.98), color.opacity(0.78)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Glassy edge: a bright top-leading highlight fading to a faint bottom edge,
    /// plus a soft inner sheen — reads like a liquid-glass rim.
    private var liquidGlassBorder: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.22),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
            .overlay {
                shape
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    .blur(radius: 1)
                    .padding(1)
            }
    }

    @ViewBuilder
    private var iconDecor: some View {
        Image(systemName: icon)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .padding(16)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(14)
    }

    @ViewBuilder
    private var checkmarkOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white))
                } else if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.22)))
                }
            }
            Spacer()
        }
        .padding(12)
    }
}

private extension View {
    @ViewBuilder
    func applyAspect(_ aspect: CGFloat?) -> some View {
        if let aspect {
            aspectRatio(aspect, contentMode: .fit)
        } else {
            self
        }
    }
}
