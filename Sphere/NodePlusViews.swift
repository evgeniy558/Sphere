import SwiftUI

struct SettingsProfileIdentityCard: View {
    let name: String
    let email: String
    let avatarURL: String?
    let isDarkMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(email)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(14)
        .libraryGlassCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = avatarURL,
           let url = catalogRemoteImageURL(avatarURL) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(isDarkMode ? 0.10 : 0.16))
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white.opacity(0.75))
            )
    }
}

struct SettingsNodePlusCard: View {
    let isDarkMode: Bool
    let isEnglish: Bool

    @State private var selectedPlan: NodePlusPlan = .yearly
    @State private var isHoveringBuy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Badge
            Text("nodeplus.badge")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.yellow.opacity(0.9))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.yellow.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.3), lineWidth: 0.8))

            // Title
            Text("nodeplus.title")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("nodeplus.subtitle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.bottom, 2)

            // Plan selector cards
            HStack(spacing: 10) {
                ForEach(NodePlusPlan.allCases) { plan in
                    planCell(plan)
                }
            }

            // Features
            Text("nodeplus.features.title")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            VStack(spacing: 0) {
                featureRow(icon: "arrow.down.circle", color: .blue, title: "nodeplus.feature.offline")
                featureRow(icon: "message.badge", color: .orange, title: "nodeplus.feature.priority")
                featureRow(icon: "megaphone.slash", color: .red, title: "nodeplus.feature.noads")
                featureRow(icon: "slider.horizontal.3", color: .purple, title: "nodeplus.feature.eq")
                featureRow(icon: "music.mic", color: .pink, title: "nodeplus.feature.karaoke")
                featureRow(icon: "waveform.badge.plus", color: .teal, title: "nodeplus.feature.lossless")
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )

            // Buy row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPlan.priceLabel(isEnglish: isEnglish))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(selectedPlan.captionKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                Button(action: {}) {
                    Text("nodeplus.buy")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.yellow, Color.yellow.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .shadow(color: Color.yellow.opacity(0.35), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Subtle golden glow at top
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.yellow.opacity(0.05), .clear, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
    }

    private func planCell(_ plan: NodePlusPlan) -> some View {
        let isSel = selectedPlan == plan
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { selectedPlan = plan }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.titleKey)
                    .font(.system(size: 14, weight: isSel ? .bold : .semibold))
                    .foregroundStyle(isSel ? .white : Color.white.opacity(0.65))
                Text(plan.priceLabel(isEnglish: isEnglish))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(isSel ? Color.yellow : .white)
                Text(plan.captionKey)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isSel ? 0.7 : 0.5))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSel ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSel ? Color.yellow.opacity(0.8) : Color.white.opacity(0.08),
                        lineWidth: isSel ? 1.2 : 0.7
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSel ? 1.02 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSel)
    }

    private func featureRow(icon: String, color: Color = .white, title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(color.opacity(0.14)))
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
                .padding(.horizontal, 12)
        }
    }
}

struct NodePlusSubscriptionScreen: View {
    let isDarkMode: Bool
    let isEnglish: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            SettingsNodePlusCard(isDarkMode: isDarkMode, isEnglish: isEnglish)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 28)
        }
        .background((isDarkMode ? Color.black : Color(.systemBackground)).ignoresSafeArea())
        .navigationTitle("Node+")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsProfileHeroCard: View {
    let profile: UserProfile?
    let name: String
    let email: String
    let accent: Color
    let isEnglish: Bool
    let onOpenProfile: () -> Void

    @ObservedObject private var recents = RecentlyPlayedStore.shared
    @State private var listeningMinutes: Int?

    private var displayedMinutes: Int {
        if let listeningMinutes { return listeningMinutes }
        return max(0, recents.items.count * 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpenProfile) {
                HStack(spacing: 14) {
                    ProfileAvatarCoreView(profile: profile, side: 60, accent: accent)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(email)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

            Text(isEnglish ? "YOU'VE LISTENED FOR" : "ВЫ СЛУШАЛИ")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)

            Text("\(displayedMinutes) \(isEnglish ? "min" : "мин")")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())
                .shadow(color: accent.opacity(0.2), radius: 12, x: 0, y: 4)
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.5))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .task { await loadListeningMinutes() }
    }

    private func loadListeningMinutes() async {
        do {
            let summary = try await SphereAPIClient.shared.getStudioSummary()
            await MainActor.run { listeningMinutes = summary.listening_minutes }
        } catch {
            // Keep local estimate from recents.
        }
    }
}

struct SettingsUpgradeInlineRow: View {
    let isEnglish: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.yellow)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.yellow.opacity(0.14)))
            Text("Node+")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(isEnglish ? "Unlock" : "Открыть")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.8))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.yellow.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.25), lineWidth: 0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
        )
    }
}

struct SettingsPanelCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .librarySectionGlass(cornerRadius: 20)
    }
}

struct SettingsPanelRowLabel: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private enum NodePlusPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .monthly: return "nodeplus.plan.monthly"
        case .yearly: return "nodeplus.plan.yearly"
        case .lifetime: return "nodeplus.plan.lifetime"
        }
    }

    var captionKey: LocalizedStringKey {
        switch self {
        case .monthly: return "nodeplus.caption.monthly"
        case .yearly: return "nodeplus.caption.yearly"
        case .lifetime: return "nodeplus.caption.lifetime"
        }
    }

    func priceLabel(isEnglish: Bool) -> String {
        switch self {
        case .monthly: return isEnglish ? "99 ₽" : "99 ₽"
        case .yearly: return isEnglish ? "599 ₽" : "599 ₽"
        case .lifetime: return isEnglish ? "4 490 ₽" : "4 490 ₽"
        }
    }
}
