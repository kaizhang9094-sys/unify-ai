import SwiftUI

// MARK: - Floating tab bar

/// Horizontal floating tab capsule; place exactly the tab `UnifyFloatingTabItem` views inside (no Plus).
struct UnifyFloatingTabBar<Content: View>: View {
    var horizontalPadding: CGFloat = 12
    /// When `true`, the pill expands so four tabs share width inside an `HStack` next to a detached FAB.
    var expandsToAvailableWidth: Bool = false
    /// Caps the inner tab row width so the pill can sit narrower than the screen (benchmark-style).
    var maxInnerWidth: CGFloat? = nil
    /// Extra vertical inset makes the capsule read rounder next to the FAB.
    var verticalPadding: CGFloat = 6
    @ViewBuilder var content: () -> Content

    private var resolvedInnerMaxWidth: CGFloat? {
        if expandsToAvailableWidth { return .infinity }
        return maxInnerWidth
    }

    var body: some View {
        HStack(spacing: 4) {
            content()
        }
        .frame(maxWidth: resolvedInnerMaxWidth, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, verticalPadding)
        .background {
            UnifySoftVeilCapsule(strokeOpacity: 1.0)
                .shadow(color: SecretaryTheme.darkShadow.opacity(0.18), radius: 12, x: 0, y: 7)
        }
        .padding(.horizontal, horizontalPadding)
    }
}

/// One segment inside `UnifyFloatingTabBar` (plain button; no system chrome).
struct UnifyFloatingTabItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var showsAttentionDot: Bool = false
    var badgeCount: Int? = nil
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(foregroundColor)

                    if let badgeCount, badgeCount > 0 {
                        Text(badgeText(badgeCount))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.darkOrange)
                            )
                            .offset(x: 10, y: -7)
                    } else if showsAttentionDot {
                        Circle()
                            .fill(SecretaryTheme.darkActivityDot)
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(SecretaryTheme.darkTabBarFill, lineWidth: 1.5)
                            )
                            .offset(x: 9, y: -6)
                    }
                }

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkTabSelectedFill)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var foregroundColor: Color {
        isSelected ? SecretaryTheme.darkPrimaryText : SecretaryTheme.darkTabUnselectedText
    }

    private func badgeText(_ n: Int) -> String {
        n > 99 ? "99+" : "\(n)"
    }
}

// MARK: - Search FAB & filter

/// Circular search launcher for dark chrome (parent supplies action). Not a tab; keep outside `UnifyFloatingTabBar`.
struct UnifyPlusIntentButton: View {
    enum VisualStyle: Equatable {
        /// Softer glass, similar fill to the tab capsule.
        case glassAdjacent
        /// Solid accent circle, visually detached from the pill (reference FAB).
        case detachedFAB
    }

    var diameter: CGFloat = 52
    var style: VisualStyle = .glassAdjacent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                searchChromeBackdrop
                    .shadow(color: SecretaryTheme.darkShadow.opacity(shadowOpacity), radius: style == .detachedFAB ? 14 : 12, x: 0, y: style == .detachedFAB ? 9 : 7)

                Image(systemName: searchSystemImage)
                    .font(.system(size: max(17, diameter * 0.404), weight: .semibold))
                    .foregroundStyle(SecretaryTheme.white)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start search")
    }

    private var searchSystemImage: String {
        if #available(iOS 18.0, *) {
            return "sparkle.magnifyingglass"
        }
        return "magnifyingglass"
    }

    @ViewBuilder
    private var searchChromeBackdrop: some View {
        Circle()
            .fill(SecretaryTheme.darkOrange)
            .overlay(
                Circle()
                    .stroke(SecretaryTheme.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var shadowOpacity: Double {
        switch style {
        case .glassAdjacent: return 0.22
        case .detachedFAB: return 0.24
        }
    }
}

/// Compact filter / segment pill for dark headers (plain button).
struct UnifyFilterPill: View {
    let title: String
    let isSelected: Bool
    /// When `true`, selected state uses neutral lifted grey (chat filter rail); when `false`, soft orange tint.
    var selectedUsesNeutralChrome: Bool = false
    let onSelect: () -> Void

    private var selectedFill: Color {
        if selectedUsesNeutralChrome {
            return SecretaryTheme.darkTabSelectedFill
        }
        return SecretaryTheme.darkOrangeSoft
    }

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? SecretaryTheme.darkPrimaryText : SecretaryTheme.darkSecondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        UnifySoftVeilCapsuleFill()
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(selectedFill)
                        }
                    }
                    .clipShape(Capsule(style: .continuous))
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? (selectedUsesNeutralChrome
                                    ? SecretaryTheme.white.opacity(0.12)
                                    : SecretaryTheme.darkOrange.opacity(0.38))
                                : SecretaryTheme.white.opacity(0.075),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
