import SwiftUI

// MARK: - Dark canvas & cards

/// Full-screen dark premium canvas (presentation only).
/// Uses the same warm charcoal-to-black ice shell as the main Exchange tabs so secondary flows
/// never fall back to a flat matte canvas.
struct UnifyDarkBackground: View {
    var showsSubtleVignette: Bool = true

    var body: some View {
        ZStack {
            UnifyIceShellBackground()

            if showsSubtleVignette {
                RadialGradient(
                    colors: [
                        SecretaryTheme.darkBackgroundElevated.opacity(0.55),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 40,
                    endRadius: 520
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// Full-screen ice canvas for the Exchange shell (all main tabs). Warm, bright bloom from the upper-trailing region
/// reaches roughly mid-screen before the canvas transitions to deep charcoal toward the bottom (presentation only).
struct UnifyIceShellBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let bloomRadius = max(w, h) * 0.78

            ZStack {
                SecretaryTheme.darkBackground

                RadialGradient(
                    colors: [
                        Color(red: 0.34, green: 0.20, blue: 0.14),
                        Color(red: 0.24, green: 0.14, blue: 0.11).opacity(0.92),
                        Color(red: 0.16, green: 0.10, blue: 0.09).opacity(0.45),
                        SecretaryTheme.darkOrange.opacity(0.09),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.98, y: 0.02),
                    startRadius: 0,
                    endRadius: bloomRadius
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

                RadialGradient(
                    colors: [
                        Color(red: 0.20, green: 0.12, blue: 0.10).opacity(0.38),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.68, y: 0.26),
                    startRadius: 40,
                    endRadius: bloomRadius * 0.92
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: Color.clear, location: 0.38),
                        .init(color: Color.clear, location: 0.52),
                        .init(color: SecretaryTheme.darkBackground.opacity(0.26), location: 0.68),
                        .init(color: SecretaryTheme.darkBackground.opacity(0.48), location: 0.88),
                        .init(color: Color.black.opacity(0.42), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                RadialGradient(
                    colors: [
                        SecretaryTheme.white.opacity(0.065),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.08, y: 0.10),
                    startRadius: 2,
                    endRadius: min(w, h) * 0.38
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Soft veil (Profile “Your offering” canonical chrome)

/// Rounded-rect fill only (no hairline). Caller adds strokes (e.g. orange slot borders).
struct UnifySoftVeilRoundedFill: View {
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SecretaryTheme.darkSurface.opacity(0.09))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.48)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Rounded rect matching **Your offering**: soft tint + partial material + light hairline.
struct UnifySoftVeilRoundedRectangle: View {
    var cornerRadius: CGFloat
    /// Scales the hairline (1.0 matches profile panels).
    var strokeOpacity: Double = 1.0

    var body: some View {
        UnifySoftVeilRoundedFill(cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SecretaryTheme.white.opacity(0.075 * strokeOpacity), lineWidth: 1)
            )
    }
}

/// Capsule fill only (no hairline). Caller adds selection / accent overlays.
struct UnifySoftVeilCapsuleFill: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(SecretaryTheme.darkSurface.opacity(0.09))
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.48)
        }
        .clipShape(Capsule(style: .continuous))
    }
}

/// Capsule with the same hairline as profile panels (floating tab shell, compact pills).
struct UnifySoftVeilCapsule: View {
    var strokeOpacity: Double = 1.0

    var body: some View {
        UnifySoftVeilCapsuleFill()
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.white.opacity(0.075 * strokeOpacity), lineWidth: 1)
            )
    }
}

/// Circular fill only (no hairline).
struct UnifySoftVeilCircleFill: View {
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.darkSurface.opacity(0.09))
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.48)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}

/// Dark card container aligned with **Your offering** (soft veil, no heavy grey slab shadow).
struct UnifyDarkCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var strokeOpacity: Double = 1.0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                UnifySoftVeilRoundedRectangle(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity)
            }
    }
}

// MARK: - Thread / chat list header chrome (shared)

/// Soft rounded slab (no extra hairline). Caller supplies overlays (e.g. orange slot border).
struct UnifyGlassPlateBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        UnifySoftVeilRoundedFill(cornerRadius: cornerRadius)
    }
}

/// Circular soft icon disk (Discovery desk, Threads/Chats search, profile chrome).
struct UnifyGlassIconDisk: View {
    var diameter: CGFloat = 40
    var strokeOpacity: Double = 0.65

    var body: some View {
        UnifySoftVeilCircleFill(diameter: diameter)
            .overlay(
                Circle()
                    .stroke(SecretaryTheme.white.opacity(0.075 * strokeOpacity), lineWidth: 1)
            )
    }
}

/// Search / banner field chrome (same veil + hairline as profile panels).
struct UnifyFrostedSearchFieldChrome: View {
    var cornerRadius: CGFloat = 20
    var strokeOpacity: Double = 0.75

    var body: some View {
        UnifySoftVeilRoundedRectangle(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity)
    }
}

/// Capsule fill for nested chips (caller adds strokes).
struct UnifyGlassCapsuleChrome: View {
    var body: some View {
        UnifySoftVeilCapsuleFill()
    }
}

/// Inset text field / multiline editor chrome (profile & offering sheets).
struct UnifyGlassTextFieldChrome: View {
    var cornerRadius: CGFloat = 14
    var strokeOpacity: Double = 0.72

    var body: some View {
        UnifySoftVeilRoundedRectangle(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity)
    }
}
