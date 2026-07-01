//
//  OnboardingComponents.swift
//  Shared dark onboarding UI (phone mockups, pills, genre cards).
//

import SwiftUI

enum OnboardingPalette {
    static let background = Color.black
    static let surface = Color.white.opacity(0.10)
    static let surfaceRaised = Color.white.opacity(0.14)
    static let chip = Color.white.opacity(0.16)
    static let muted = Color.white.opacity(0.62)
    static let stroke = Color.white.opacity(0.20)
    static let pickGreen = Color(red: 0.16, green: 0.80, blue: 0.46)
    static let setupGlow = Color(red: 1.0, green: 0.45, blue: 0.12)
}

struct OnboardingCircleButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay {
                    Circle().strokeBorder(OnboardingPalette.stroke, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingOutlinePill: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous).stroke(OnboardingPalette.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color.white, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct OnboardingMutedPillButton: View {
    let title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous).stroke(OnboardingPalette.stroke, lineWidth: 0.9)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct OnboardingSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OnboardingPalette.muted)
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(OnboardingPalette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OnboardingPalette.stroke, lineWidth: 0.8)
        }
    }
}

enum GuidePreviewKind {
    case welcome, lyrics, mixes, trending, playlists, releases
}

struct OnboardingPhoneFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color(white: 0.06))
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.black)
                .padding(8)
                .overlay { content().clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous)) }
        }
        .frame(width: 226, height: 452)
    }
}

struct GuidePreviewContent: View {
    let kind: GuidePreviewKind

    /// Real screenshot asset name for each guide page. Drop screenshots into the
    /// asset catalog under these names and they'll be shown instead of the
    /// code-drawn placeholders.
    private var assetName: String {
        switch kind {
        case .welcome: return "GuideHome"
        case .lyrics: return "GuideLyrics"
        case .mixes: return "GuidePlayer"
        case .trending: return "GuideDiscover"
        case .playlists: return "GuideLibrary"
        case .releases: return "GuideStudio"
        }
    }

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            drawnPreview
        }
    }

    @ViewBuilder
    private var drawnPreview: some View {
        switch kind {
        case .welcome: welcomePreview
        case .lyrics: lyricsPreview
        case .mixes: chaptersPreview
        case .trending: trendingPreview
        case .playlists: playlistsPreview
        case .releases: releasesPreview
        }
    }

    private var welcomePreview: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.45, green: 0.22, blue: 0.95), Color(red: 0.12, green: 0.08, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 14) {
                HStack {
                    Circle().fill(.white.opacity(0.15)).frame(width: 32, height: 32)
                    Spacer()
                    Capsule().fill(.white.opacity(0.15)).frame(width: 72, height: 28)
                    Circle().fill(.white.opacity(0.15)).frame(width: 32, height: 32)
                }
                .padding(.horizontal, 16).padding(.top, 12)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .overlay(Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.white.opacity(0.5)))
                Text("NODE").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text("Your wave, tuned").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
                previewTabBar
            }
        }
    }

    private var lyricsPreview: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.1, blue: 0.42), .black], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                previewLine("Earlier verse…", opacity: 0.3, bold: false)
                previewLine("This line is highlighted", opacity: 1, bold: true)
                previewLine("Next line follows", opacity: 0.5, bold: false)
                Spacer()
                previewTabBar
            }
            .padding(20)
            .font(.system(size: 15, design: .serif))
        }
    }

    private var chaptersPreview: some View {
        VStack(spacing: 0) {
            Text("Chapters").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).padding(.vertical, 12)
            ForEach(["Intro", "Verse", "Chorus"], id: \.self) { ch in
                HStack {
                    Text("0:00").font(.system(size: 12)).foregroundStyle(OnboardingPalette.muted)
                    Text(ch).font(.system(size: 14, weight: ch == "Chorus" ? .semibold : .regular))
                        .foregroundStyle(ch == "Chorus" ? .white : OnboardingPalette.muted)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ch == "Chorus" ? OnboardingPalette.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
            }
            Spacer()
        }
        .background(Color(white: 0.08))
    }

    private var trendingPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.top, 14)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.35, green: 0.38, blue: 0.28))
                .frame(height: 140)
                .padding(.horizontal, 12)
            Spacer()
        }
        .background(Color(white: 0.07))
    }

    private var playlistsPreview: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.12, blue: 0.18), .black], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 10) {
                Text("Queue").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.top, 16)
                Capsule().fill(Color(red: 0.95, green: 0.35, blue: 0.45)).frame(height: 36).padding(.horizontal, 14)
                Spacer()
                previewTabBar
            }
        }
    }

    private var releasesPreview: some View {
        VStack(spacing: 10) {
            Text("New").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).padding(.top, 14)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 160).padding(.horizontal, 12)
            Spacer()
            previewTabBar
        }
        .background(Color(white: 0.08))
    }

    private var previewTabBar: some View {
        HStack {
            ForEach(["music.note", "books.vertical", "heart", "sparkles"], id: \.self) { icon in
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule(style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    private func previewLine(_ text: String, opacity: Double, bold: Bool) -> some View {
        Text(text).foregroundStyle(.white.opacity(opacity)).fontWeight(bold ? .semibold : .regular)
    }
}

struct GenrePickerCard: View {
    let title: String
    let color: Color
    let selected: Bool

    var body: some View {
        NodeColorTile(
            title: title,
            subtitle: nil,
            icon: "music.note",
            color: color,
            selected: selected,
            stackedThumbs: true,
            aspectRatio: 1.7
        )
    }
}

struct ArtistPickerTile: View {
    let name: String
    let subtitle: String?
    let imageURL: String?
    let selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: catalogRemoteImageURL(imageURL)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(OnboardingPalette.surfaceRaised)
                        }
                    }
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    Group {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(OnboardingPalette.pickGreen))
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(8)
                }

                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(width: 148, alignment: .leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingPalette.muted)
                        .lineLimit(1)
                        .frame(width: 148, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
