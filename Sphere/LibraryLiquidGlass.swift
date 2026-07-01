//
//  LibraryLiquidGlass.swift
//  Liquid-glass surfaces for Library.
//

import SwiftUI

// MARK: - Modifiers

struct LibraryGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(NodeDesignStyle.glassStrokePrimary, lineWidth: 0.8)
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(NodeDesignStyle.glassStrokePrimary, lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                }
        }
    }
}

struct LibrarySectionGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(NodeDesignStyle.glassStrokeSecondary, lineWidth: 0.8)
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(NodeDesignStyle.glassStrokeSecondary, lineWidth: 0.8)
                        }
                }
        }
    }
}

struct LibraryGlassPillModifier: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(isSelected ? NodeDesignStyle.glassTintSelected : NodeDesignStyle.glassTintIdle)
                        .interactive(),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.24 : 0.12), lineWidth: 0.8)
                }
        } else {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(isSelected ? NodeDesignStyle.glassTintSelected : NodeDesignStyle.glassTintIdle)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.24 : 0.12), lineWidth: 0.8)
                        }
                }
        }
    }
}

struct LibraryGlassCircleButton: View {
    let systemName: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
                .modifier(LibraryCircleGlassBackground())
        }
        .buttonStyle(.plain)
    }
}

/// Wavy glass footer for playlist folder tiles.
struct LibraryLiquidGlassFooter: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NodeDesignStyle.glassStrokePrimary, lineWidth: 0.8)
            }
            .frame(height: 74)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

private struct LibraryCircleGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .overlay {
                    Circle().strokeBorder(NodeDesignStyle.glassStrokeSecondary, lineWidth: 0.8)
                }
        } else {
            content
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().strokeBorder(NodeDesignStyle.glassStrokeSecondary, lineWidth: 0.8)
                        }
                }
        }
    }
}

extension View {
    func libraryGlassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(LibraryGlassCardModifier(cornerRadius: cornerRadius))
    }

    func libraryGlassPill(selected: Bool) -> some View {
        modifier(LibraryGlassPillModifier(isSelected: selected))
    }

    func librarySectionGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(LibrarySectionGlassModifier(cornerRadius: cornerRadius))
    }
}
