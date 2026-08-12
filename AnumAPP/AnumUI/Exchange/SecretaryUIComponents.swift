import SwiftUI
import UIKit
import AnumCore

// MARK: - Secretary Theme

enum SecretaryTheme {

    // MARK: - Strict palette
    // Design rule:
    // Black = structure / text / primary action
    // White = room / glass / cards
    // Orange = energy / attention / active accent
    //
    // No green. No blue. No yellow. No violet. No sage.

    static let orange = Color(red: 1.000, green: 0.365, blue: 0.145)
    static let orangeDeep = Color(red: 0.820, green: 0.210, blue: 0.055)
    static let orangeSoft = Color(red: 1.000, green: 0.580, blue: 0.330).opacity(0.16)
    static let orangeGlass = Color(red: 1.000, green: 0.455, blue: 0.210).opacity(0.10)

    static let black = Color.black
    static let white = Color.white

    // MARK: - Compatibility aliases
    // Keep these names because the rest of the app already references them.
    // They intentionally collapse into black / white / orange only.

    static let coral = orange
    static let cream = white
    static let sand = orange
    static let sienna = black.opacity(0.88)

    static let coralSoft = orangeSoft
    static let coralDeep = orangeDeep
    static let sandDeep = orangeDeep
    static let siennaDeep = black.opacity(0.94)
    static let brownInk = black.opacity(0.92)

    // MARK: - Foundation

    static let background = Color(red: 0.965, green: 0.970, blue: 0.972)
    static let backgroundDeep = Color.black.opacity(0.055)
    static let parchment = white
    static let porcelain = white
    static let warmMist = Color.black.opacity(0.035)

    static let cardFill = white.opacity(0.82)
    static let cardFillStrong = white.opacity(0.94)
    static let cardFillQuiet = white.opacity(0.72)
    static let softFill = white.opacity(0.70)
    static let secondaryFill = black.opacity(0.045)

    static let ink = black.opacity(0.92)
    static let espresso = black.opacity(0.90)
    static let espressoSoft = black.opacity(0.68)

    static let mutedText = black.opacity(0.62)
    static let softText = black.opacity(0.42)
    static let faintText = black.opacity(0.26)

    static let stroke = black.opacity(0.09)
    static let strokeSoft = black.opacity(0.055)

    /// Unread / attention indicators (bell, tab dots, numeric badges). Matches chat row unread capsules (`darkOrange`, not system red).
    static let notificationUnreadFill = SecretaryTheme.darkOrange

    // MARK: - Dark premium (Unify)
    // Additive tokens for dark presentation surfaces. Light-theme colors above are unchanged.

    /// Near-black / charcoal app canvas.
    static let darkBackground = Color(red: 0.06, green: 0.06, blue: 0.08)
    /// Slightly lifted canvas (behind chrome stacks).
    static let darkBackgroundElevated = Color(red: 0.09, green: 0.09, blue: 0.11)
    /// Default dark card / panel fill (subtle lift from canvas).
    static let darkSurface = Color.white.opacity(0.06)
    /// Stronger panel fill (pressed / emphasis).
    static let darkSurfaceStrong = Color.white.opacity(0.11)
    /// Flat “glass” tint layered under material or as soft fill.
    static let darkGlass = Color.white.opacity(0.08)
    /// Hairline / edge on dark glass.
    static let darkStroke = Color.white.opacity(0.14)
    static let darkPrimaryText = Color.white.opacity(0.96)
    static let darkSecondaryText = Color.white.opacity(0.62)
    static let darkMutedText = Color.white.opacity(0.38)
    /// Accent on dark (same hue family as `orange`; tuned for contrast on charcoal).
    static let darkOrange = Color(red: 1.000, green: 0.420, blue: 0.180)
    static let darkOrangeSoft = Color(red: 1.000, green: 0.420, blue: 0.180).opacity(0.22)
    static let darkActivityDot = darkOrange
    /// Floating tab capsule fill.
    static let darkTabBarFill = Color.white.opacity(0.07)
    /// Selected tab segment fill inside the capsule.
    static let darkTabSelectedFill = Color.white.opacity(0.14)
    /// Unselected tab label + icon tint.
    static let darkTabUnselectedText = darkSecondaryText
    /// Soft elevation behind floating chrome.
    static let darkShadow = Color.black.opacity(0.42)

    // MARK: - Semantic aliases, still black / white / orange only

    static let gold = orange
    static let warmGold = orange
    static let goldSoft = orangeSoft

    static let liveBlue = black.opacity(0.74)
    static let liveBlueSoft = white.opacity(0.70)

    static let approvalAmber = orangeDeep
    static let approvalAmberSoft = orangeSoft

    static let trustSage = black.opacity(0.74)
    static let trustSageSoft = white.opacity(0.70)

    static let recoveryRose = orangeDeep
    static let recoveryRoseSoft = orangeSoft

    static let socialViolet = black.opacity(0.74)
    static let socialVioletSoft = white.opacity(0.70)

    static let personPeach = orange
    static let personPeachSoft = orangeSoft

    // MARK: - Elevation

    static func glassShadow(_ opacity: Double = 0.050) -> Color {
        black.opacity(opacity)
    }

    static var premiumShadow: Color {
        black.opacity(0.105)
    }

    static var quietShadow: Color {
        black.opacity(0.045)
    }

    // MARK: - Semantic helpers

    static func semanticColor(for style: SecretaryStateChip.Style) -> Color {
        switch style {
        case .warning, .blocked:
            return orangeDeep
        case .neutral, .active, .success:
            return black.opacity(0.72)
        }
    }

    static func semanticSoftFill(for style: SecretaryStateChip.Style) -> Color {
        switch style {
        case .warning, .blocked:
            return orangeSoft
        case .neutral, .active, .success:
            return white.opacity(0.72)
        }
    }

    static func semanticStroke(for style: SecretaryStateChip.Style) -> Color {
        switch style {
        case .warning, .blocked:
            return orange.opacity(0.28)
        case .neutral, .active, .success:
            return black.opacity(0.10)
        }
    }

    // MARK: - Layout tokens

    enum Layout {
        static let radiusSmall: CGFloat = 18
        static let radiusMedium: CGFloat = 26
        static let radiusLarge: CGFloat = 34
        static let radiusXL: CGFloat = 40
        static let cardSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 18
        static let cardInteriorPadding: CGFloat = 18
        static let heroInnerPadding: CGFloat = 22
        static let compactPadding: CGFloat = 14
    }

    enum Elevation {
        struct Spec {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        static let flat = Spec(color: Color.clear, radius: 0, y: 0)
        static let rest = Spec(color: SecretaryTheme.quietShadow, radius: 12, y: 6)
        static let raised = Spec(color: SecretaryTheme.premiumShadow, radius: 20, y: 10)
        static let hero = Spec(color: SecretaryTheme.premiumShadow, radius: 26, y: 13)
        static let floating = Spec(color: SecretaryTheme.black.opacity(0.14), radius: 30, y: 16)
    }

    enum Photo {
        static let photoRadius: CGFloat = 24
        static let photoHeightSmall: CGFloat = 118
        static let photoHeightLarge: CGFloat = 164
        static let photoHeightHero: CGFloat = 220

        static var bottomScrimGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.74)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.30),
                endPoint: .bottom
            )
        }
    }

    enum SectionAccent {
        static let opportunity = SecretaryTheme.orange
        static let opportunitySoft = SecretaryTheme.orangeSoft
        static let progress = SecretaryTheme.black.opacity(0.74)
        static let progressSoft = SecretaryTheme.white.opacity(0.70)
        static let warning = SecretaryTheme.orangeDeep
        static let warningSoft = SecretaryTheme.orangeSoft
        static let trust = SecretaryTheme.black.opacity(0.74)
        static let trustSoft = SecretaryTheme.white.opacity(0.70)
    }
}

// MARK: - Background

struct SecretaryWorkspaceBackground: View {
    var body: some View {
        ZStack {
            SecretaryTheme.background
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    Color.white.opacity(0.76),
                    Color.black.opacity(0.035),
                    SecretaryTheme.orangeGlass
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.84))
                .frame(width: 320, height: 320)
                .blur(radius: 76)
                .offset(x: 128, y: -245)

            Circle()
                .fill(SecretaryTheme.orange.opacity(0.085))
                .frame(width: 300, height: 300)
                .blur(radius: 92)
                .offset(x: -168, y: 90)

            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 360, height: 360)
                .blur(radius: 96)
                .offset(x: 185, y: 410)
        }
    }
}

// MARK: - Surface Card

struct SecretarySurfaceCard<Content: View>: View {
    let padding: CGFloat
    let radius: CGFloat
    let emphasis: Bool
    let heroPresentation: Bool
    @ViewBuilder let content: Content

    init(
        padding: CGFloat = SecretaryTheme.Layout.cardInteriorPadding,
        radius: CGFloat = SecretaryTheme.Layout.radiusMedium,
        emphasis: Bool = false,
        heroPresentation: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.emphasis = emphasis
        self.heroPresentation = heroPresentation
        self.content = content()
    }

    private var elevation: SecretaryTheme.Elevation.Spec {
        if heroPresentation, emphasis { return SecretaryTheme.Elevation.hero }
        if emphasis { return SecretaryTheme.Elevation.raised }
        return SecretaryTheme.Elevation.rest
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardStroke)
            .shadow(color: elevation.color, radius: elevation.radius, x: 0, y: elevation.y)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(emphasis ? SecretaryTheme.cardFillStrong : SecretaryTheme.cardFill)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(emphasis ? 0.62 : 0.42),
                        Color.white.opacity(0.10),
                        SecretaryTheme.orangeGlass.opacity(emphasis ? 1.0 : 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(
                emphasis ? SecretaryTheme.black.opacity(0.13) : SecretaryTheme.stroke.opacity(0.90),
                lineWidth: 1
            )
    }
}

// MARK: - Hero Surface

struct SecretaryHeroSurface<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SecretarySurfaceCard(
                padding: SecretaryTheme.Layout.heroInnerPadding,
                radius: SecretaryTheme.Layout.radiusLarge,
                emphasis: true,
                heroPresentation: true
            ) {
                content
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.48),
                            SecretaryTheme.orange.opacity(0.085),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 170, height: 170)
                .blur(radius: 26)
                .offset(x: 48, y: -66)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Section Header

struct SecretarySectionHeader: View {
    let title: String
    let systemImage: String
    let trailingTitle: String?
    let trailingAction: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        trailingTitle: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 10) {
            SecretaryIconBadge(systemImage: systemImage, style: .brand, size: 32)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink)

            Spacer(minLength: 8)

            if let trailingTitle, let trailingAction {
                Button(action: trailingAction) {
                    HStack(spacing: 5) {
                        Text(trailingTitle)
                            .font(.system(size: 13, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(SecretaryTheme.black.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.74))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SecretaryTheme.stroke.opacity(0.95), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Notification count badge

struct SecretaryNotificationCountBadge: View {
    let count: Int
    var maxDisplay: Int = 99

    private var text: String {
        count > maxDisplay ? "\(maxDisplay)+" : "\(count)"
    }

    var body: some View {
        if count > 0 {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(minWidth: 18, minHeight: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.notificationUnreadFill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.orangeDeep.opacity(0.45), lineWidth: 1)
                )
                .accessibilityLabel("\(count) unread")
        }
    }
}

/// Boolean unread indicator (e.g. bottom Inbound tab); matches `SecretaryNotificationCountBadge` fill.
struct SecretaryNotificationDot: View {
    var showsBorder: Bool = true
    var diameter: CGFloat = 18

    var body: some View {
        Circle()
            .fill(SecretaryTheme.notificationUnreadFill)
            .frame(width: diameter, height: diameter)
            .overlay {
                if showsBorder {
                    Circle()
                        .stroke(SecretaryTheme.white, lineWidth: 2)
                }
            }
            .accessibilityLabel("Unread")
    }
}

// MARK: - Icon Badge

struct SecretaryIconBadge: View {
    enum IconStyle {
        case brand
        case live
        case approval
        case trust
        case recovery
        case person
        case quiet
    }

    let systemImage: String
    let style: IconStyle
    var size: CGFloat = 42

    init(systemImage: String, style: IconStyle = .brand, size: CGFloat = 42) {
        self.systemImage = systemImage
        self.style = style
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.40, style: .continuous)
                .fill(fillGradient)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.40, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )

            Image(systemName: systemImage)
                .font(.system(size: max(12, size * 0.42), weight: .semibold))
                .foregroundStyle(foreground)
        }
        .shadow(color: SecretaryTheme.quietShadow, radius: 7, x: 0, y: 4)
    }

    private var foreground: Color {
        switch style {
        case .approval, .recovery:
            return SecretaryTheme.orangeDeep
        case .brand:
            return SecretaryTheme.orange
        case .live, .trust, .person, .quiet:
            return SecretaryTheme.black.opacity(0.74)
        }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                fill.opacity(1.0),
                Color.white.opacity(0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var fill: Color {
        switch style {
        case .approval, .recovery, .brand:
            return SecretaryTheme.orangeSoft
        case .live, .trust, .person, .quiet:
            return Color.white.opacity(0.78)
        }
    }

    private var stroke: Color {
        switch style {
        case .approval, .recovery, .brand:
            return SecretaryTheme.orange.opacity(0.24)
        case .live, .trust, .person, .quiet:
            return SecretaryTheme.black.opacity(0.10)
        }
    }
}

// MARK: - Unify main tab scroll layout

/// Shared scroll metrics for Discovery, Threads, Chats (inbound), and Profile tab roots.
enum UnifyMainTabScrollLayout {
    /// Padding below the safe area for primary tab `ScrollView` content (formerly 20pt).
    static let paddingBelowSafeArea: CGFloat = -28
}

// MARK: - State Chip

struct SecretaryStateChip: View {
    enum Style {
        case neutral
        case active
        case warning
        case blocked
        case success
    }

    let title: String
    let style: Style

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.semanticColor(for: style))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.semanticSoftFill(for: style))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
            )
    }
}

// MARK: - Human Label

/// Capsule metrics for ``SecretaryHumanLabel``; reuse for hero trailing bubbles that should match thread presentation.
enum SecretaryHumanLabelLayout {
    static let hStackSpacing: CGFloat = 7
    static let iconFontSize: CGFloat = 11
    static let iconWeight: Font.Weight = .semibold
    static let textFontSize: CGFloat = 12.5
    static let textWeight: Font.Weight = .semibold
    static let paddingHorizontal: CGFloat = 11
    static let paddingVertical: CGFloat = 7
}

struct SecretaryHumanLabel: View {
    let text: String
    let systemImage: String?
    let style: SecretaryStateChip.Style

    init(
        _ text: String,
        systemImage: String? = nil,
        style: SecretaryStateChip.Style = .neutral
    ) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(spacing: SecretaryHumanLabelLayout.hStackSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(
                        .system(
                            size: SecretaryHumanLabelLayout.iconFontSize,
                            weight: SecretaryHumanLabelLayout.iconWeight
                        )
                    )
            }

            Text(text)
                .font(
                    .system(
                        size: SecretaryHumanLabelLayout.textFontSize,
                        weight: SecretaryHumanLabelLayout.textWeight
                    )
                )
                .lineLimit(1)
        }
        .foregroundStyle(SecretaryTheme.semanticColor(for: style))
        .padding(.horizontal, SecretaryHumanLabelLayout.paddingHorizontal)
        .padding(.vertical, SecretaryHumanLabelLayout.paddingVertical)
        .background(
            Capsule(style: .continuous)
                .fill(SecretaryTheme.semanticSoftFill(for: style))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
        )
    }
}

// MARK: - Action Button

struct SecretaryActionButton: View {
    enum Tone {
        case primary
        case brand
        case live
        case approval
        case trust
        case recovery
        case secondary
    }

    /// Presentation chrome for capsules. ``exchangeDark`` restyles ``Tone.secondary`` for charcoal Exchange shells; other tones unchanged.
    enum ChromeSurface: Sendable {
        case `default`
        case exchangeDark
    }

    let title: String
    let systemImage: String?
    let prominent: Bool
    let tone: Tone
    let isLoading: Bool
    let chrome: ChromeSurface
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        prominent: Bool = false,
        tone: Tone? = nil,
        isLoading: Bool = false,
        chrome: ChromeSurface = .default,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.tone = tone ?? (prominent ? .primary : .secondary)
        self.isLoading = isLoading
        self.chrome = chrome
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                        .scaleEffect(0.9)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 17)
            .frame(height: 45)
            .background {
                if usesDarkSecondaryChrome {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(SecretaryTheme.darkGlass.opacity(0.85))
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    }
                } else {
                    Capsule(style: .continuous)
                        .fill(background)
                }
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: prominent ? shadow : Color.clear, radius: prominent ? 13 : 0, x: 0, y: prominent ? 7 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isBusyTitle || isLoading)
        .opacity(isBusyTitle || isLoading ? 0.72 : 1.0)
    }

    private var isBusyTitle: Bool {
        let lower = title.lowercased()
        return lower.contains("publishing") || lower.contains("withdrawing")
    }

    private var usesDarkSecondaryChrome: Bool {
        chrome == .exchangeDark && tone == .secondary
    }

    private var foreground: Color {
        if usesDarkSecondaryChrome {
            return SecretaryTheme.darkPrimaryText
        }
        switch tone {
        case .primary, .live, .trust:
            return .white
        case .brand, .approval, .recovery:
            return .white
        case .secondary:
            return SecretaryTheme.ink.opacity(0.82)
        }
    }

    private var background: Color {
        if usesDarkSecondaryChrome {
            // Glass stack is applied in `body` for this chrome path.
            return Color.clear
        }
        switch tone {
        case .primary, .live, .trust:
            return SecretaryTheme.black.opacity(0.90)
        case .brand, .approval, .recovery:
            return SecretaryTheme.orange
        case .secondary:
            return SecretaryTheme.white.opacity(0.78)
        }
    }

    private var border: Color {
        if usesDarkSecondaryChrome {
            return SecretaryTheme.darkStroke.opacity(0.82)
        }
        switch tone {
        case .primary, .live, .trust:
            return SecretaryTheme.black.opacity(0.90)
        case .brand, .approval, .recovery:
            return SecretaryTheme.orangeDeep.opacity(0.45)
        case .secondary:
            return SecretaryTheme.stroke.opacity(1.0)
        }
    }

    private var shadow: Color {
        switch tone {
        case .primary, .live, .trust:
            return SecretaryTheme.black.opacity(0.22)
        case .brand, .approval, .recovery:
            return SecretaryTheme.orange.opacity(0.22)
        case .secondary:
            return .clear
        }
    }
}

// MARK: - Dual Button Row

struct SecretaryPanelDualCommitmentRow: View {
    let secondaryTitle: String
    let secondarySystemImage: String
    let isBusy: Bool
    let secondaryAction: () -> Void

    let primaryTitle: String
    let primarySystemImage: String
    let primaryIsLoading: Bool
    let primaryTone: SecretaryActionButton.Tone
    let primaryAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SecretaryActionButton(
                title: secondaryTitle,
                systemImage: secondarySystemImage,
                prominent: false,
                tone: .secondary,
                action: secondaryAction
            )
            .disabled(isBusy)
            .opacity(isBusy ? 0.55 : 1.0)
            .frame(maxWidth: .infinity)

            SecretaryActionButton(
                title: primaryTitle,
                systemImage: primarySystemImage,
                prominent: true,
                tone: primaryTone,
                isLoading: primaryIsLoading,
                action: primaryAction
            )
            .disabled(isBusy)
            .opacity(isBusy ? 0.72 : 1.0)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Info Line

struct SecretaryInfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(SecretaryTheme.softText)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Empty / State Card

struct SecretaryStateCard: View {
    let title: String
    let message: String
    let systemImage: String
    var minHeight: CGFloat = 150

    var body: some View {
        SecretarySurfaceCard(emphasis: false) {
            VStack(alignment: .leading, spacing: 14) {
                SecretaryIconBadge(systemImage: systemImage, style: iconStyle, size: 46)

                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(SecretaryTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.system(size: 15.5))
                    .foregroundStyle(SecretaryTheme.mutedText)
                    .lineSpacing(1.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
    }

    private var iconStyle: SecretaryIconBadge.IconStyle {
        let lower = title.lowercased() + " " + message.lowercased()

        if lower.contains("blocked") || lower.contains("failed") || lower.contains("recovery") || lower.contains("care") {
            return .recovery
        }

        if lower.contains("approval") || lower.contains("waiting") || lower.contains("input") || lower.contains("decision") {
            return .approval
        }

        if lower.contains("trusted") || lower.contains("ready") || lower.contains("relationship") {
            return .trust
        }

        if lower.contains("search") || lower.contains("active") || lower.contains("live") || lower.contains("moving") {
            return .live
        }

        if lower.contains("person") || lower.contains("people") || lower.contains("reply") || lower.contains("incoming") {
            return .person
        }

        return .brand
    }
}

// MARK: - Loading

struct SecretaryLoadingView: View {
    let title: String
    let subtitle: String

    var body: some View {
        SecretaryHeroSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(SecretaryTheme.orange)
                        .scaleEffect(1.0)

                    Text("Secretary is checking")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.softText)
                }

                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(SecretaryTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .lineSpacing(1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        }
    }
}

// MARK: - Dark premium (Exchange shell)

/// Full-width loading hero for dark charcoal Exchange surfaces. Async behavior matches ``SecretaryLoadingView`` (local `ProgressView` only).
struct UnifyDarkLoadingView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(SecretaryTheme.darkOrange)
                    .scaleEffect(1.0)

                Text("Secretary is checking")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }

            Text(title)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(size: 15.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SecretaryTheme.Layout.cardInteriorPadding)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(unifyDarkCardChrome(cornerRadius: SecretaryTheme.Layout.radiusLarge))
    }
}

/// Bordered dark glass card for status copy on charcoal surfaces (parity with ``SecretaryStateCard`` API).
struct UnifyDarkStateCard: View {
    let title: String
    let message: String
    let systemImage: String
    var minHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UnifyDarkStateIconPlate(
                systemImage: systemImage,
                size: 46,
                attention: UnifyDarkStateCardIconHeuristic.usesAttentionAccent(title: title, message: message)
            )

            Text(title)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 15.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SecretaryTheme.Layout.cardInteriorPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(unifyDarkCardChrome(cornerRadius: SecretaryTheme.Layout.radiusMedium))
    }
}

/// Centered compact empty state for dark lists and sheets (icon + title + message).
struct UnifyDarkEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkMutedText)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private enum UnifyDarkStateCardIconHeuristic {
    /// Mirrors ``SecretaryStateCard`` icon emphasis so recovery / approval surfaces read with orange energy on dark.
    static func usesAttentionAccent(title: String, message: String) -> Bool {
        let lower = title.lowercased() + " " + message.lowercased()

        if lower.contains("blocked") || lower.contains("failed") || lower.contains("recovery") || lower.contains("care") {
            return true
        }

        if lower.contains("approval") || lower.contains("waiting") || lower.contains("input") || lower.contains("decision") {
            return true
        }

        if lower.contains("trusted") || lower.contains("ready") || lower.contains("relationship") {
            return false
        }

        if lower.contains("search") || lower.contains("active") || lower.contains("live") || lower.contains("moving") {
            return false
        }

        if lower.contains("person") || lower.contains("people") || lower.contains("reply") || lower.contains("incoming") {
            return false
        }

        return true
    }
}

private struct UnifyDarkStateIconPlate: View {
    let systemImage: String
    let size: CGFloat
    var attention: Bool

    private var plateCornerRadius: CGFloat { size * 0.40 }

    var body: some View {
        ZStack {
            Group {
                if attention {
                    RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                        .fill(SecretaryTheme.darkOrangeSoft.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                                .stroke(SecretaryTheme.darkOrange.opacity(0.28), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.85))
                        .background {
                            RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
                        )
                }
            }

            Image(systemName: systemImage)
                .font(.system(size: max(12, size * 0.42), weight: .semibold))
                .foregroundStyle(attention ? SecretaryTheme.darkOrange : SecretaryTheme.darkMutedText)
        }
        .frame(width: size, height: size)
        .shadow(color: SecretaryTheme.darkShadow.opacity(0.22), radius: 8, x: 0, y: 4)
    }
}

@ViewBuilder
private func unifyDarkCardChrome(cornerRadius: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SecretaryTheme.darkGlass.opacity(0.85))
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
    )
    .shadow(color: SecretaryTheme.darkShadow.opacity(0.35), radius: 18, x: 0, y: 10)
}

// MARK: - Thread State Badge

struct SecretaryThreadStateBadge: View {
    let title: String

    var body: some View {
        SecretaryStateChip(title: friendlyTitle, style: style(for: friendlyTitle))
    }

    private var friendlyTitle: String {
        let lower = title.lowercased()

        if lower.contains("stream") { return "Working" }
        if lower.contains("trace") { return "Working" }
        if lower.contains("draft ready") { return "Draft ready" }
        if lower.contains("drafting") { return "Drafting" }
        if lower.contains("draft") { return "In progress" }
        if lower.contains("search") { return "Looking" }
        if lower.contains("approval") { return "Your review" }
        if lower.contains("input") || lower.contains("needs you") { return "Needs you" }
        if lower.contains("recovery") { return "Recover" }
        if lower.contains("failed") { return "Needs care" }
        if lower.contains("published") { return "Visible" }
        if lower.contains("trusted") { return "Trusted" }

        return title
    }

    private func style(for value: String) -> SecretaryStateChip.Style {
        let lower = value.lowercased()

        if lower.contains("blocked") ||
            lower.contains("failed") ||
            lower.contains("declined") ||
            lower.contains("recover") ||
            lower.contains("stalled") ||
            lower.contains("care") {
            return .blocked
        }

        if lower.contains("approval") ||
            lower.contains("attention") ||
            lower.contains("selection") ||
            lower.contains("needs you") ||
            lower.contains("input") ||
            lower.contains("review") ||
            lower.contains("choose") {
            return .warning
        }

        if lower.contains("resolved") ||
            lower.contains("done") ||
            lower.contains("sent") ||
            lower.contains("trusted") ||
            lower.contains("ready") ||
            lower.contains("visible") ||
            lower.contains("published") {
            return .success
        }

        if lower.contains("active") ||
            lower.contains("reply") ||
            lower.contains("draft") ||
            lower.contains("search") ||
            lower.contains("looking") ||
            lower.contains("live") ||
            lower.contains("working") ||
            lower.contains("qualifying") {
            return .active
        }

        return .neutral
    }
}

// MARK: - Live Glyph

struct SecretaryLiveGlyph: View {
    let isActive: Bool

    var body: some View {
        SecretaryIconBadge(
            systemImage: isActive ? "waveform.path.ecg" : "sparkles",
            style: isActive ? .live : .brand,
            size: 40
        )
    }
}

// MARK: - Discovery Hero Progress

/// Left-to-right flowing highlight for Discovery hero stage copy.
/// Glyph colors are driven by a masked overlay gradient (not background blend).
/// Uses `TimelineView` so animation stays visible when ancestors disable implicit animations.
struct DiscoveryHeroFlowingStageText: View {
    let text: String
    let isActive: Bool

    private let stageFont = Font.system(size: 15, weight: .semibold)
    private let cycleDuration: TimeInterval = 2.0
    private let phaseStart: CGFloat = -1.2
    private let phaseEnd: CGFloat = 1.2
    private let bandWidthRatio: CGFloat = 0.55

    var body: some View {
        Group {
            if isActive, !UIAccessibility.isReduceMotionEnabled {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    flowingStageContent(animatedPhase: animatedPhase(at: timeline.date))
                }
            } else if isActive {
                flowingStageContent(animatedPhase: 0)
            } else {
                Text(text)
                    .font(stageFont)
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
            }
        }
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func flowingStageContent(animatedPhase: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(stageFont)
                .multilineTextAlignment(.leading)
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.68))

            Text(text)
                .font(stageFont)
                .multilineTextAlignment(.leading)
                .foregroundStyle(highlightGradient)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let bandWidth = max(80, width * bandWidthRatio)

                        highlightBandMask
                            .frame(width: bandWidth, height: max(proxy.size.height, 1))
                            .offset(x: animatedPhase * width)
                            .mask(alignment: .leading) {
                                Text(text)
                                    .font(stageFont)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: width, height: proxy.size.height, alignment: .topLeading)
                            }
                    }
                }
                .allowsHitTesting(false)
        }
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                SecretaryTheme.darkPrimaryText.opacity(0.20),
                SecretaryTheme.darkOrange.opacity(0.95),
                Color.white.opacity(0.95),
                SecretaryTheme.darkOrange.opacity(0.95),
                SecretaryTheme.darkPrimaryText.opacity(0.20)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var highlightBandMask: LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.55),
                Color.white,
                Color.white.opacity(0.55),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func animatedPhase(at date: Date) -> CGFloat {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return phaseStart + (phaseEnd - phaseStart) * CGFloat(progress)
    }
}

/// Primary animated stage line for the Discovery compact progress strip.
struct DiscoveryHeroAnimatedStageLine: View {
    let stage: DiscoveryHeroProgressProjection.Stage
    let aiDisplayName: String
    let isActive: Bool

    private var baseText: String {
        DiscoveryHeroProgressProjection.statusLine(stage: stage, aiDisplayName: aiDisplayName)
    }

    var body: some View {
        DiscoveryHeroFlowingStageText(text: baseText, isActive: isActive)
    }
}

// MARK: - Pulse Label

struct SecretaryPulseLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? SecretaryTheme.orange : SecretaryTheme.black.opacity(0.72))
                .frame(width: 7, height: 7)
                .shadow(
                    color: (isActive ? SecretaryTheme.orange : SecretaryTheme.black).opacity(0.22),
                    radius: 4,
                    x: 0,
                    y: 0
                )

            Text(friendlyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.74))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? SecretaryTheme.orangeSoft : SecretaryTheme.white.opacity(0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isActive ? SecretaryTheme.orange.opacity(0.22) : SecretaryTheme.black.opacity(0.10), lineWidth: 1)
        )
    }

    private var friendlyTitle: String {
        let lower = title.lowercased()
        if lower.contains("refresh") { return "Checking" }
        if lower.contains("live") { return "With you" }
        if lower.contains("quiet") { return "Quiet" }
        return title
    }
}

// MARK: - Mini Stage Pill

struct SecretaryMiniStagePill: View {
    let title: String
    let style: SecretaryStateChip.Style

    var body: some View {
        Text(friendlyTitle)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(SecretaryTheme.semanticColor(for: style))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SecretaryTheme.semanticSoftFill(for: style))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
            )
    }

    private var friendlyTitle: String {
        let lower = title.lowercased()

        if lower.contains("stream") { return "Working" }
        if lower.contains("trace") { return "Working" }
        if lower.contains("active") { return "Moving" }
        if lower.contains("search") { return "Looking" }
        if lower.contains("draft") { return "Drafting" }
        if lower.contains("reply") { return "Reply" }

        return title
    }
}

// MARK: - Metric Strip

struct SecretaryMetricStrip: View {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let value: String

        init(title: String, value: String) {
            self.id = "\(title)-\(value)"
            self.title = title
            self.value = value
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                metricCell(item)
            }
        }
    }

    private func metricCell(_ item: Item) -> some View {
        HStack(spacing: 6) {
            Text(item.value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SecretaryTheme.ink)

            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SecretaryTheme.softText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(SecretaryTheme.white.opacity(0.76))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(SecretaryTheme.stroke.opacity(0.90), lineWidth: 1)
        )
    }
}

// MARK: - Breathing Summary

struct SecretaryBreathingSummary: View {
    let headline: String
    let subline: String
    let systemImage: String
    let style: SecretaryStateChip.Style
    var trailingText: String?

    init(
        headline: String,
        subline: String,
        systemImage: String,
        style: SecretaryStateChip.Style = .neutral,
        trailingText: String? = nil
    ) {
        self.headline = headline
        self.subline = subline
        self.systemImage = systemImage
        self.style = style
        self.trailingText = trailingText
    }

    var body: some View {
        SecretarySurfaceCard(padding: 16, radius: 24) {
            HStack(alignment: .center, spacing: 13) {
                SecretaryIconBadge(systemImage: systemImage, style: iconStyle, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.ink)
                        .lineLimit(1)

                    Text(subline)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.semanticColor(for: style))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.semanticSoftFill(for: style))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
                        )
                }
            }
        }
    }

    private var iconStyle: SecretaryIconBadge.IconStyle {
        switch style {
        case .warning:
            return .approval
        case .blocked:
            return .recovery
        case .neutral:
            return .brand
        case .active:
            return .live
        case .success:
            return .trust
        }
    }
}

// MARK: - Concierge Panel

struct SecretaryConciergePanel<Content: View>: View {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String
    let style: SecretaryStateChip.Style
    @ViewBuilder let content: Content

    init(
        eyebrow: String,
        title: String,
        message: String,
        systemImage: String,
        style: SecretaryStateChip.Style = .neutral,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.style = style
        self.content = content()
    }

    var body: some View {
        SecretaryHeroSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    SecretaryIconBadge(systemImage: systemImage, style: iconStyle, size: 40)

                    Text(eyebrow)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.ink)

                    Spacer(minLength: 0)

                    SecretaryStateChip(title: statusWord, style: style)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(title)
                        .font(.system(size: 29, weight: .regular, design: .rounded))
                        .foregroundStyle(SecretaryTheme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .lineSpacing(1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
        }
    }

    private var iconStyle: SecretaryIconBadge.IconStyle {
        switch style {
        case .warning:
            return .approval
        case .blocked:
            return .recovery
        case .neutral:
            return .brand
        case .active:
            return .live
        case .success:
            return .trust
        }
    }

    private var statusWord: String {
        switch style {
        case .neutral: return "Quiet"
        case .active: return "Moving"
        case .warning: return "Needs you"
        case .blocked: return "Care needed"
        case .success: return "Ready"
        }
    }
}

// MARK: - Reception Card

struct SecretaryReceptionCard: View {
    let title: String
    let message: String
    let companionName: String
    let systemImage: String
    let isQuiet: Bool

    init(
        title: String,
        message: String,
        companionName: String = "Secretary",
        systemImage: String = "tray.and.arrow.down",
        isQuiet: Bool = true
    ) {
        self.title = title
        self.message = message
        self.companionName = companionName
        self.systemImage = systemImage
        self.isQuiet = isQuiet
    }

    var body: some View {
        SecretarySurfaceCard(padding: 18, radius: 28, emphasis: !isQuiet) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    SecretaryPhotoOrb(
                        initials: initials(from: companionName),
                        systemImage: nil,
                        style: isQuiet ? .neutral : .active,
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(companionName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.ink)

                        Text(isQuiet ? "At the desk" : "Handling replies")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.softText)
                    }

                    Spacer(minLength: 0)

                    SecretaryIconBadge(systemImage: systemImage, style: isQuiet ? .quiet : .live, size: 38)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 23, weight: .regular, design: .rounded))
                        .foregroundStyle(SecretaryTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .lineSpacing(1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func initials(from value: String) -> String {
        let pieces = value.split(separator: " ").prefix(2).compactMap { $0.first }
        let result = String(pieces).uppercased()
        return result.isEmpty ? "S" : result
    }
}

// MARK: - Photo Components

struct SecretaryPhotoOrb: View {
    let initials: String
    let systemImage: String?
    let style: SecretaryStateChip.Style
    var size: CGFloat = 48

    init(
        initials: String = "",
        systemImage: String? = nil,
        style: SecretaryStateChip.Style = .neutral,
        size: CGFloat = 48
    ) {
        self.initials = initials
        self.systemImage = systemImage
        self.style = style
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            SecretaryTheme.semanticSoftFill(for: style),
                            Color.white.opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
                )
                .shadow(color: SecretaryTheme.quietShadow, radius: 8, x: 0, y: 4)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.semanticColor(for: style))
            } else {
                Text(initials.isEmpty ? "S" : initials)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.semanticColor(for: style))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Optional Guardian crown ring around a circular avatar (presentation only).
struct GuardianCrownAvatarFrame<Content: View>: View {
    let showsCrown: Bool
    let avatarDiameter: CGFloat
    var debugSurface: String? = nil
    var debugNodeID: String? = nil
    var debugProfileID: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            content()
            if showsCrown {
                Image(systemName: "crown.fill")
                    .font(.system(size: max(10, avatarDiameter * 0.22), weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .shadow(color: SecretaryTheme.darkShadow.opacity(0.35), radius: 2, x: 0, y: 1)
                    .offset(y: -avatarDiameter * 0.14)
                    .accessibilityLabel("Guardian supporter")
            }
        }
        #if DEBUG
        .onAppear {
            guard showsCrown else { return }
            GuardianCrownDebugLog.log(
                "Render",
                "surface=\(debugSurface ?? "avatarFrame") nodeID=\(debugNodeID ?? "nil") " +
                "profileID=\(debugProfileID ?? "nil") size=\(Int(avatarDiameter)) " +
                "presentation=guardian/crown"
            )
        }
        #endif
    }
}

/// Compact circle avatar for message rows (public profile URL + `SecretaryPhotoOrb` fallback).
struct SecretaryCompactProfileAvatar: View {
    let imageURL: String?
    let initials: String
    var systemImage: String? = "person.crop.circle"
    var style: SecretaryStateChip.Style = .active
    var size: CGFloat = 30
    var publicSupporterPresentation: ExchangeSupporterPresentation? = nil
    var debugSurface: String? = nil
    var debugNodeID: String? = nil
    var debugProfileID: String? = nil

    private var showsGuardianCrown: Bool {
        publicSupporterPresentation?.showsGuardianCrown == true
    }

    var body: some View {
        GuardianCrownAvatarFrame(
            showsCrown: showsGuardianCrown,
            avatarDiameter: size,
            debugSurface: debugSurface,
            debugNodeID: debugNodeID,
            debugProfileID: debugProfileID
        ) {
            Group {
                if let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty,
                   let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            SecretaryPhotoOrb(
                                initials: initials,
                                systemImage: systemImage,
                                style: style,
                                size: size
                            )
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(SecretaryTheme.stroke.opacity(0.8), lineWidth: 1))
                } else {
                    SecretaryPhotoOrb(
                        initials: initials,
                        systemImage: systemImage,
                        style: style,
                        size: size
                    )
                }
            }
        }
    }
}

struct SecretaryPhotoHeader: View {
    let imageURL: String?
    var title: String?
    let initials: String
    let systemImage: String?
    let style: SecretaryStateChip.Style
    var height: CGFloat

    init(
        imageURL: String?,
        title: String? = nil,
        initials: String = "",
        systemImage: String? = nil,
        style: SecretaryStateChip.Style = .neutral,
        height: CGFloat? = nil
    ) {
        self.imageURL = imageURL
        self.title = title
        self.initials = initials
        self.systemImage = systemImage
        self.style = style
        self.height = height ?? SecretaryTheme.Photo.photoHeightLarge
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photoContent
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

            if let title, !title.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .shadow(color: Color.black.opacity(0.40), radius: 4, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SecretaryTheme.Layout.cardSpacing)
                        .background(SecretaryTheme.Photo.bottomScrimGradient)
                }
                .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SecretaryTheme.Photo.photoRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SecretaryTheme.Photo.photoRadius, style: .continuous)
                .stroke(SecretaryTheme.stroke.opacity(0.75), lineWidth: 1)
        )
        .shadow(
            color: SecretaryTheme.Elevation.rest.color,
            radius: SecretaryTheme.Elevation.rest.radius,
            x: 0,
            y: SecretaryTheme.Elevation.rest.y
        )
    }

    @ViewBuilder
    private var photoContent: some View {
        if let trimmed = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty,
           let url = URL(string: trimmed) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    fallbackBackground
                @unknown default:
                    fallbackBackground
                }
            }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SecretaryTheme.white.opacity(0.92),
                    SecretaryTheme.black.opacity(0.045),
                    SecretaryTheme.orangeGlass
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SecretaryPhotoOrb(
                initials: initials,
                systemImage: systemImage,
                style: style,
                size: min(56, max(40, height * 0.34))
            )
        }
    }
}

struct SecretaryVisualTile: View {
    enum Kind {
        case person
        case product
        case service
        case social
        case trusted
        case generic

        var fallbackIcon: String {
            switch self {
            case .person: return "person.crop.circle"
            case .product: return "shippingbox"
            case .service: return "sparkles"
            case .social: return "person.2"
            case .trusted: return "checkmark.seal"
            case .generic: return "photo"
            }
        }

        var style: SecretaryStateChip.Style {
            switch self {
            case .product, .service:
                return .warning
            case .trusted:
                return .success
            case .person, .social:
                return .active
            case .generic:
                return .neutral
            }
        }
    }

    let title: String?
    let subtitle: String?
    let kind: Kind
    var height: CGFloat = 132

    init(
        title: String? = nil,
        subtitle: String? = nil,
        kind: Kind = .generic,
        height: CGFloat = 132
    ) {
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.height = height
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusMedium, style: .continuous)
                .fill(tileGradient)

            RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusMedium, style: .continuous)
                .stroke(SecretaryTheme.stroke.opacity(0.70), lineWidth: 1)

            VStack(alignment: .leading, spacing: 8) {
                SecretaryPhotoOrb(systemImage: kind.fallbackIcon, style: kind.style, size: 46)
                Spacer(minLength: 8)

                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.ink)
                        .lineLimit(2)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusMedium, style: .continuous))
        .shadow(
            color: SecretaryTheme.Elevation.rest.color,
            radius: SecretaryTheme.Elevation.rest.radius,
            x: 0,
            y: max(4, SecretaryTheme.Elevation.rest.y * 0.85)
        )
    }

    private var tileGradient: LinearGradient {
        switch kind {
        case .product, .service:
            return LinearGradient(
                colors: [SecretaryTheme.orangeSoft, Color.white.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .person, .social, .trusted, .generic:
            return LinearGradient(
                colors: [Color.white.opacity(0.90), Color.black.opacity(0.040)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct SecretaryRelationshipStrip: View {
    let leftTitle: String
    let rightTitle: String
    let caption: String

    var body: some View {
        HStack(spacing: 10) {
            SecretaryPhotoOrb(initials: initials(from: leftTitle), style: .active, size: 42)

            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(SecretaryTheme.black.opacity(0.50))
                        .frame(width: 5, height: 5)

                    Rectangle()
                        .fill(SecretaryTheme.stroke.opacity(0.95))
                        .frame(height: 1)

                    Circle()
                        .fill(SecretaryTheme.orange.opacity(0.88))
                        .frame(width: 7, height: 7)

                    Rectangle()
                        .fill(SecretaryTheme.stroke.opacity(0.95))
                        .frame(height: 1)

                    Circle()
                        .fill(SecretaryTheme.black.opacity(0.50))
                        .frame(width: 5, height: 5)
                }

                Text(caption)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.softText)
                    .lineLimit(1)
            }

            SecretaryPhotoOrb(initials: initials(from: rightTitle), style: .success, size: 42)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SecretaryTheme.white.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SecretaryTheme.stroke.opacity(0.85), lineWidth: 1)
        )
    }

    private func initials(from value: String) -> String {
        let pieces = value.split(separator: " ").prefix(2).compactMap { $0.first }
        let result = String(pieces).uppercased()
        return result.isEmpty ? "U" : result
    }
}

// MARK: - Person / Offer Row

struct SecretaryPersonPathRow: View {
    let title: String
    let subtitle: String
    let detail: String?
    let initials: String
    let style: SecretaryStateChip.Style
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String,
        detail: String? = nil,
        initials: String = "",
        style: SecretaryStateChip.Style = .neutral,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.initials = initials
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SecretaryPhotoOrb(
                initials: initials.isEmpty ? generatedInitials : initials,
                style: style,
                size: 48
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(SecretaryTheme.mutedText)
                    .lineLimit(2)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.softText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.semanticColor(for: style))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.semanticSoftFill(for: style))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(SecretaryTheme.white.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SecretaryTheme.stroke.opacity(0.85), lineWidth: 1)
        )
    }

    private var generatedInitials: String {
        let pieces = title.split(separator: " ").prefix(2).compactMap { $0.first }
        let result = String(pieces).uppercased()
        return result.isEmpty ? "U" : result
    }
}

// MARK: - Full-screen image gallery

struct SecretaryImageGalleryPresentation: Identifiable, Equatable {
    let id: UUID
    let imageURLs: [String]
    let initialIndex: Int
    let title: String?
    let caption: String?

    init(
        id: UUID = UUID(),
        imageURLs: [String],
        initialIndex: Int = 0,
        title: String?,
        caption: String?
    ) {
        self.id = id
        let cleaned = imageURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.imageURLs = cleaned
        let maxIdx = max(0, cleaned.count - 1)
        self.initialIndex = min(max(0, initialIndex), maxIdx)
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = t.isEmpty ? nil : t
        let c = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.caption = c.isEmpty ? nil : c
    }

    static func == (lhs: SecretaryImageGalleryPresentation, rhs: SecretaryImageGalleryPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

/// Centered glass treatment on the dark gallery scrim — invalid URL, parse failure, or `AsyncImage` failure (not a flat gray block).
private struct SecretaryImageGalleryUnavailablePage: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SecretaryTheme.darkGlass.opacity(0.88))
                    .frame(width: 88, height: 88)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 88, height: 88)
                    }
                    .overlay(
                        Circle()
                            .stroke(SecretaryTheme.white.opacity(0.14), lineWidth: 1)
                    )

                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
            }

            Text("Photo unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SecretaryImageGalleryViewer: View {
    let presentation: SecretaryImageGalleryPresentation
    let onDismiss: () -> Void

    @State private var selection: Int

    init(presentation: SecretaryImageGalleryPresentation, onDismiss: @escaping () -> Void) {
        self.presentation = presentation
        self.onDismiss = onDismiss
        _selection = State(initialValue: presentation.initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    Spacer()

                    if presentation.imageURLs.count > 1 {
                        Text("\(selection + 1) / \(presentation.imageURLs.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if let title = presentation.title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }

                Group {
                    if presentation.imageURLs.isEmpty {
                        Text("No image")
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if presentation.imageURLs.count == 1, let only = presentation.imageURLs.first {
                        if let url = URL(string: only) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                case .failure:
                                    SecretaryImageGalleryUnavailablePage()
                                case .empty:
                                    ProgressView()
                                        .tint(.white)
                                @unknown default:
                                    SecretaryImageGalleryUnavailablePage()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            SecretaryImageGalleryUnavailablePage()
                        }
                    } else {
                        TabView(selection: $selection) {
                            ForEach(Array(presentation.imageURLs.enumerated()), id: \.offset) { index, urlStr in
                                Group {
                                    if let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFit()
                                            case .failure:
                                                SecretaryImageGalleryUnavailablePage()
                                            case .empty:
                                                ProgressView()
                                                    .tint(.white)
                                            @unknown default:
                                                SecretaryImageGalleryUnavailablePage()
                                            }
                                        }
                                    } else {
                                        SecretaryImageGalleryUnavailablePage()
                                    }
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let caption = presentation.caption {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
        }
    }
}

// MARK: - Companion avatar (on-disk; same UserDefaults keys + `Application Support/Avatars` as RoomView)

/// Keys and directory must stay aligned with ``RoomView`` / ``RoomOptionsSheet`` so Threads shows the same portrait as companion mode.
enum CompanionAvatarDiskStorage {
    static let thumbFilenameKey = "companionAvatarThumbFilename"
    static let fullFilenameKey = "companionAvatarFullFilename"

    static func avatarsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Prefers thumb (list-sized) then full, matching companion list performance expectations.
    static func loadUIImage(thumbFilename: String, fullFilename: String) -> UIImage? {
        let dir = avatarsDirectoryURL()
        for name in [thumbFilename, fullFilename] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let url = dir.appendingPathComponent(trimmed)
            guard let data = try? Data(contentsOf: url), let ui = UIImage(data: data) else { continue }
            return ui
        }
        return nil
    }

    /// Same JPEG + UUID filename strategy as ``RoomOptionsSheet`` / ``AvatarPresenceView`` so companion mode stays in sync.
    @MainActor
    static func saveReplacingAvatar(withPickedImage image: UIImage) {
        let oldThumb = UserDefaults.standard.string(forKey: thumbFilenameKey) ?? ""
        let oldFull = UserDefaults.standard.string(forKey: fullFilenameKey) ?? ""
        deleteJPEGIfExists(oldThumb)
        deleteJPEGIfExists(oldFull)

        let stamp = UUID().uuidString
        let thumbName = "companion_avatar_thumb_\(stamp).jpg"
        let fullName = "companion_avatar_full_\(stamp).jpg"

        let full = CompanionAvatarImageProcessing.resizeLongestEdge(image, maxEdge: 2048)
        let square = CompanionAvatarImageProcessing.centerCropSquare(image)
        let thumb = CompanionAvatarImageProcessing.resizeToSquare(square, side: 256)

        #if DEBUG
        let thumbData = thumb.jpegData(compressionQuality: 0.82)
        let fullData = full.jpegData(compressionQuality: 0.85)
        print(
            "[ImageUploadPrep] context=companionAvatarLocal stage=saved " +
            "points=\(Int(image.size.width))x\(Int(image.size.height)) " +
            "pixels=\(image.cgImage?.width ?? 0)x\(image.cgImage?.height ?? 0) " +
            "thumbBytes=\(thumbData?.count ?? 0) fullBytes=\(fullData?.count ?? 0) mime=image/jpeg"
        )
        #endif

        writeJPEG(thumb, filename: thumbName, quality: 0.82)
        writeJPEG(full, filename: fullName, quality: 0.85)

        UserDefaults.standard.set(thumbName, forKey: thumbFilenameKey)
        UserDefaults.standard.set(fullName, forKey: fullFilenameKey)
    }

    private static func deleteJPEGIfExists(_ filename: String) {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = avatarsDirectoryURL().appendingPathComponent(trimmed)
        try? FileManager.default.removeItem(at: url)
    }

    private static func writeJPEG(_ image: UIImage, filename: String, quality: CGFloat) {
        let url = avatarsDirectoryURL().appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

private enum CompanionAvatarImageProcessing {
    static func centerCropSquare(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: side, height: side)).integral
        guard let cg = image.cgImage?.cropping(to: rect) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    static func resizeToSquare(_ image: UIImage, side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    static func resizeLongestEdge(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Glass avatar chip for the Threads “Secretary style” hero; mirrors companion disk asset when present.
struct CompanionAvatarThreadsHeroOrb: View {
    var diameter: CGFloat = 44

    @AppStorage(CompanionAvatarDiskStorage.thumbFilenameKey) private var thumbFilename: String = ""
    @AppStorage(CompanionAvatarDiskStorage.fullFilenameKey) private var fullFilename: String = ""
    @State private var loaded: UIImage?

    var body: some View {
        ZStack {
            UnifySoftVeilCircleFill(diameter: diameter)
                .overlay(
                    Circle()
                        .stroke(SecretaryTheme.white.opacity(0.075 * 0.95), lineWidth: 1)
                )

            if let loaded {
                Image(uiImage: loaded)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .onAppear { reloadFromDisk() }
        .onChange(of: thumbFilename) { _, _ in reloadFromDisk() }
        .onChange(of: fullFilename) { _, _ in reloadFromDisk() }
    }

    private func reloadFromDisk() {
        loaded = CompanionAvatarDiskStorage.loadUIImage(
            thumbFilename: thumbFilename,
            fullFilename: fullFilename
        )
    }
}

// MARK: - Relative Time

enum SecretaryRelativeTime {
    static func string(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86_400))d ago"
    }
}
