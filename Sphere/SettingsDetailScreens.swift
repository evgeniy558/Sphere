//
//  SettingsDetailScreens.swift
//  Экраны «Оформление», «Другое», «Кастомизация» из настроек.
//

import SwiftUI
import UIKit

// MARK: - Оформление

struct SettingsAppearanceScreen: View {
    let accent: Color
    let isEnglish: Bool
    let resolvedColorSchemeFromMainApp: ColorScheme
    @AppStorage("playerStyleIndex") private var playerStyleIndex: Int = 0
    @AppStorage("enableCoverPaging") private var enableCoverPaging: Bool = true
    @AppStorage("enableRoundPlayerCover") private var enableRoundPlayerCover: Bool = false
    @AppStorage("enableCoverSeekAnimation") private var enableCoverSeekAnimation: Bool = false
    @AppStorage("coverSeekShakeDotIndex") private var coverSeekShakeDotIndex: Int = 0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: String = ""

    private var appliedColorScheme: ColorScheme { .dark }

    private var isDark: Bool { true }
    private var screenBg: Color { isDark ? .black : Color(.systemBackground) }

    private var playerStyleTitle: String { isEnglish ? "Player style \(playerStyleIndex + 1)" : "Стиль плеера \(playerStyleIndex + 1)" }
    private var coverPagingTitle: String { isEnglish ? "Cover paging" : "Перелистывание обложки" }
    private var roundCoverTitle: String { isEnglish ? "Round cover" : "Круглая обложка" }
    private var coverSeekAnimationTitle: String { isEnglish ? "Cover animation on seek" : "Анимация обложки при перемотке" }

    private var themeButtonIcon: String {
        switch preferredColorSchemeRaw {
        case "": return "moon.fill"
        case "dark": return "sun.max.fill"
        case "light": return "circle.lefthalf.filled"
        default: return "moon.fill"
        }
    }

    private var themeButtonTitle: String {
        switch preferredColorSchemeRaw {
        case "": return isEnglish ? "Dark" : "Тёмная"
        case "dark": return isEnglish ? "Light" : "Светлая"
        case "light": return isEnglish ? "System" : "Системная"
        default: return isEnglish ? "Dark" : "Тёмная"
        }
    }

    private func toggleTheme() {
        withAnimation(.easeInOut(duration: 0.35)) {
            switch preferredColorSchemeRaw {
            case "": preferredColorSchemeRaw = "dark"
            case "dark": preferredColorSchemeRaw = "light"
            case "light": preferredColorSchemeRaw = ""
            default: preferredColorSchemeRaw = ""
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if #available(iOS 26.0, *) {
                    VStack(alignment: .leading, spacing: 12) {
                        DeveloperMenuPlayerStyleRowIOS26(
                            playerStyleIndex: $playerStyleIndex,
                            title: playerStyleTitle,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12
                        )
                        DeveloperMenuCoverPagingRowIOS26(
                            enableCoverPaging: $enableCoverPaging,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: coverPagingTitle
                        )
                        DeveloperMenuCoverSeekAnimationRowIOS26(
                            enableCoverSeekAnimation: $enableCoverSeekAnimation,
                            coverSeekShakeDotIndex: $coverSeekShakeDotIndex,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: coverSeekAnimationTitle,
                            isEnglish: isEnglish
                        )
                        DeveloperMenuRoundCoverRowIOS26(
                            enableRoundPlayerCover: $enableRoundPlayerCover,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: roundCoverTitle
                        )
                        InitialScreenStyleCapsuleIconButtonIOS26(
                            systemDark: isDark,
                            accent: accent,
                            systemImage: themeButtonIcon,
                            title: themeButtonTitle,
                            action: toggleTheme
                        )
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        DeveloperMenuPlayerStyleRowLegacy(
                            playerStyleIndex: $playerStyleIndex,
                            title: playerStyleTitle,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12
                        )
                        DeveloperMenuCoverPagingRowLegacy(
                            enableCoverPaging: $enableCoverPaging,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: coverPagingTitle
                        )
                        DeveloperMenuCoverSeekAnimationRowLegacy(
                            enableCoverSeekAnimation: $enableCoverSeekAnimation,
                            coverSeekShakeDotIndex: $coverSeekShakeDotIndex,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: coverSeekAnimationTitle,
                            isEnglish: isEnglish
                        )
                        DeveloperMenuRoundCoverRowLegacy(
                            enableRoundPlayerCover: $enableRoundPlayerCover,
                            isDark: isDark,
                            accent: accent,
                            horizontalPadding: 12,
                            title: roundCoverTitle
                        )
                        InitialScreenStyleCapsuleIconButtonLegacy(
                            systemDark: isDark,
                            accent: accent,
                            systemImage: themeButtonIcon,
                            title: themeButtonTitle,
                            action: toggleTheme
                        )
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(
            NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.3).ignoresSafeArea()
        )
        .navigationTitle(isEnglish ? "Appearance" : "Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Другое

struct SettingsOtherScreen: View {
    let accent: Color
    let isEnglish: Bool
    let isDarkMode: Bool
    @AppStorage("sphereStreamLossless") private var streamLossless: Bool = false
    @ObservedObject private var discord = DiscordRPC.shared
    var onAddMusic: () -> Void

    private var addMusicTitle: String { isEnglish ? "Add music from device" : "Добавить музыку с устройства" }

    private var losslessTitle: String {
        let onWord = isEnglish ? "On" : "Вкл"
        let offWord = isEnglish ? "Off" : "Выкл"
        let label = isEnglish ? "Lossless audio" : "Lossless-аудио"
        return "\(label): \(streamLossless ? onWord : offWord)"
    }

    private var discordButtonTitle: String {
        if let name = discord.discordUsername {
            return "Discord: \(name)"
        }
        return isEnglish ? "Connect Discord" : "Подключить Discord"
    }
    private var discordDisconnectTitle: String { isEnglish ? "Disconnect Discord" : "Отключить Discord" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsGroupContainer(isDarkMode: isDarkMode) {
                    SettingsGroupRowLabel(icon: "plus.circle.fill", title: addMusicTitle, showsChevron: false)
                        .contentShape(Rectangle())
                        .onTapGesture { onAddMusic() }

                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)

                    SettingsGroupRowLabel(icon: streamLossless ? "waveform.badge.plus" : "waveform", title: losslessTitle, showsChevron: false)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { streamLossless.toggle() } }

                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)

                    Button {
                        if discord.discordUsername != nil { discord.disconnect() } else { discord.authorize() }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color(red: 0.35, green: 0.42, blue: 0.96).opacity(0.16))
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.35, green: 0.42, blue: 0.96))
                            }
                            .frame(width: 34, height: 34)
                            Text(discordButtonTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if discord.discordUsername != nil {
                        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)
                        SettingsGroupRowLabel(icon: "xmark.circle.fill", title: discordDisconnectTitle, showsChevron: false)
                            .contentShape(Rectangle())
                            .onTapGesture { discord.disconnect() }
                    }
                }
                .padding(.horizontal, 16)

                if let status = discord.statusText {
                    Text(status).font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 20)
                }
            }
            .padding(.top, 20).padding(.bottom, 32)
        }
        .background(NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.3).ignoresSafeArea())
        .navigationTitle(isEnglish ? "Other" : "Другое")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Кастомизация (цвет приложения)

struct SettingsCustomizationScreen: View {
    let accent: Color
    let isEnglish: Bool
    let isDarkMode: Bool
    @AppStorage("sphereUseCustomAccent") private var useCustomAccent: Bool = false
    @AppStorage("sphereAccentR") private var accentR: Double = 217.0 / 255.0
    @AppStorage("sphereAccentG") private var accentG: Double = 252.0 / 255.0
    @AppStorage("sphereAccentB") private var accentB: Double = 1.0
    @State private var pickerUIColor: UIColor = .systemPurple
    @State private var showColorPicker = false

    private var title: String { isEnglish ? "Customization" : "Кастомизация" }
    private var pickTitle: String { isEnglish ? "App accent color" : "Цвет акцента приложения" }
    private var resetTitle: String { isEnglish ? "Reset to default" : "Сбросить к стандартному" }
    private var pickerSheetTitle: String { isEnglish ? "Accent color" : "Цвет акцента" }
    private var doneTitle: String { isEnglish ? "Done" : "Готово" }
    private var cancelTitle: String { isEnglish ? "Cancel" : "Отмена" }

    /// Превью: при открытом пикере показываем выбранный цвет в реальном времени.
    private var accentPreviewFill: Color {
        if showColorPicker {
            return Color(uiColor: pickerUIColor)
        }
        if useCustomAccent {
            return Color(red: accentR, green: accentG, blue: accentB)
        }
        return accent
    }

    private func commitSelectedAccent() {
        let c = pickerUIColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if c.getRed(&r, green: &g, blue: &b, alpha: &a) {
            accentR = Double(r)
            accentG = Double(g)
            accentB = Double(b)
        } else if let comp = c.cgColor.components, comp.count >= 3 {
            accentR = Double(comp[0])
            accentG = Double(comp[1])
            accentB = Double(comp[2])
        }
        useCustomAccent = true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsGroupContainer(isDarkMode: isDarkMode) {
                    SettingsGroupRowLabel(icon: "paintpalette.fill", title: pickTitle, showsChevron: false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            pickerUIColor = UIColor(red: accentR, green: accentG, blue: accentB, alpha: 1)
                            showColorPicker = true
                        }

                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)

                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(accentPreviewFill.opacity(0.2))
                            Circle().fill(accentPreviewFill).frame(width: 16, height: 16)
                        }
                        .frame(width: 34, height: 34)
                        Text(isEnglish ? "Preview" : "Превью")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentPreviewFill)
                            .frame(width: 40, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)

                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)

                    SettingsGroupRowLabel(icon: "arrow.counterclockwise", title: resetTitle, showsChevron: false)
                        .contentShape(Rectangle())
                        .onTapGesture { useCustomAccent = false }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 20).padding(.bottom, 32)
        }
        .background(NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.3).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showColorPicker) {
            NavigationStack {
                AppAccentUIColorPickerSheet(
                    isPresented: $showColorPicker,
                    selectedUIColor: $pickerUIColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(pickerSheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle) { showColorPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(doneTitle) { commitSelectedAccent(); showColorPicker = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
}

struct SettingsLanguageScreen: View {
    let isDarkMode: Bool
    let accent: Color

    @AppStorage("appLanguageCode") private var appLanguageCode: String = "ru"
    @AppStorage("isEnglish") private var isEnglishStorage: Bool = false

    private var title: String { String(localized: "settings.language.title") }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SettingsGroupContainer(isDarkMode: isDarkMode) {
                    ForEach(Array(AppLanguageOption.allCases.enumerated()), id: \.element.rawValue) { idx, option in
                        Button {
                            appLanguageCode = option.rawValue
                            isEnglishStorage = option == .en
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(NodeDesignStyle.tileColor(for: option.rawValue).opacity(0.16))
                                    Text(String(option.rawValue.prefix(2).uppercased()))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(NodeDesignStyle.tileColor(for: option.rawValue))
                                }
                                .frame(width: 34, height: 34)
                                Text(option.localizedNameKey)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 0)
                                if appLanguageCode == option.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        if idx < AppLanguageOption.allCases.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 20).padding(.bottom, 32)
        }
        .background(NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.3).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

private enum AppLanguageOption: String, CaseIterable {
    case en
    case ru
    case fr
    case de

    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .en: return "settings.language.english"
        case .ru: return "settings.language.russian"
        case .fr: return "settings.language.french"
        case .de: return "settings.language.german"
        }
    }
}
