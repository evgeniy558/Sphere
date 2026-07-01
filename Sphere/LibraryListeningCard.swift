//
//  LibraryListeningCard.swift
//  Recent listening row matching library reference layout.
//

import SwiftUI

struct LibraryListeningCard: View {
    let item: RecentlyPlayedStore.Item
    let isEnglish: Bool
    let isDarkMode: Bool
    let durationLabel: String?
    var onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(relativePlayedAt(item.playedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }

            if !item.artist.isEmpty {
                Text(item.artist)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }

            Text(snippetText)
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.48))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(durationLabel ?? (isEnglish ? "Play" : "Слушать"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .modifier(LibraryPlayGlassButtonModifier())
                }
                .buttonStyle(.plain)

                LibraryGlassCircleButton(systemName: "ellipsis")
                LibraryGlassCircleButton(systemName: "square.and.arrow.up")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cover: some View {
        AsyncImage(url: catalogRemoteImageURL(item.coverURL)) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(white: 0.18))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private var snippetText: String {
        if isEnglish {
            return "Continue where you left off — \(item.artist.isEmpty ? item.title : item.artist)."
        }
        return "Продолжи с того места — \(item.artist.isEmpty ? item.title : item.artist)."
    }

    private func relativePlayedAt(_ date: Date) -> String {
        let sec = max(0, Int(Date().timeIntervalSince(date)))
        if sec < 60 {
            return isEnglish ? "Just now" : "Только что"
        }
        if sec < 3600 {
            let m = sec / 60
            return isEnglish ? "\(m) min ago" : "\(m) мин назад"
        }
        if sec < 86400 {
            let h = sec / 3600
            return isEnglish ? "\(h) hour\(h == 1 ? "" : "s") ago" : "\(h) ч назад"
        }
        let d = sec / 86400
        return isEnglish ? "\(d) day\(d == 1 ? "" : "s") ago" : "\(d) дн назад"
    }
}

private struct LibraryPlayGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.16)).interactive(), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                }
        } else {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                        }
                }
        }
    }
}
