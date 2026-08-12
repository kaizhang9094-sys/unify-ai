import SwiftUI

// MARK: - Shared glass placeholder chrome

@ViewBuilder
private func unifyGlassPlaceholderCircle(diameter: CGFloat) -> some View {
    UnifyGlassIconDisk(diameter: diameter, strokeOpacity: 0.75)
}

@ViewBuilder
private func unifyGlassPlaceholderSlot(cornerRadius: CGFloat) -> some View {
    UnifySoftVeilRoundedRectangle(cornerRadius: cornerRadius, strokeOpacity: 0.88)
}

// MARK: - Presentation Placeholder

/// Non-interactive story strip placeholder for previews and layout scaffolding.
struct UnifyPlaceholderChatStory: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(SecretaryTheme.darkStroke, lineWidth: 1)
                            .frame(width: 58, height: 58)
                            .overlay {
                                UnifyGlassIconDisk(diameter: 50, strokeOpacity: 0.75)
                            }

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SecretaryTheme.darkMutedText.opacity(0.35))
                            .frame(width: 52, height: 10)
                    }
                    .opacity(0.55 + Double(index) * 0.04)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Non-interactive list row placeholder.
struct UnifyPlaceholderChatRow: View {
    var body: some View {
        HStack(spacing: 12) {
            unifyGlassPlaceholderCircle(diameter: 48)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SecretaryTheme.darkMutedText.opacity(0.4))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SecretaryTheme.darkMutedText.opacity(0.22))
                    .frame(width: 180, height: 12)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Profile media strip (presentation)

/// Frosted panel shared by profile **Your offering**, **Media and photos**, and matching thread hero cards.
/// Delegates to `UnifySoftVeilRoundedRectangle` (canonical Exchange soft veil).
struct UnifyProfileTranslucentPanelBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        UnifySoftVeilRoundedRectangle(cornerRadius: cornerRadius, strokeOpacity: 1.0)
    }
}

/// Layout metrics for profile media thumbnails (presentation only).
enum UnifyProfileMediaStripMetrics {
    /// Prior strip height 84pt; +30% for taller tiles.
    static let slotHeight: CGFloat = (84 * 1.3).rounded()
    /// Fixed slot width in the profile media strip (matches profile shell layout).
    static let slotWidth: CGFloat = 72
    /// Slightly larger corner radius so tall tiles stay balanced (aligned with Offering — Required cards).
    static let slotCornerRadius: CGFloat = 18
}

/// One slot in the profile media strip (view-only).
enum UnifyProfileMediaSlot: Equatable {
    case remoteImage(URL)
    case overflowMore(Int)
    case pad
}

/// Horizontal media thumbnails for the profile shell (non-interactive; no network beyond `AsyncImage`).
struct UnifyProfileMediaStrip: View {
    let slots: [UnifyProfileMediaSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Media and photos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    slotView(slot)
                        .frame(maxWidth: .infinity)
                        .frame(height: UnifyProfileMediaStripMetrics.slotHeight)
                }
            }
        }
        .padding(16)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func slotView(_ slot: UnifyProfileMediaSlot) -> some View {
        switch slot {
        case .remoteImage(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    padTile(opacity: 1.0)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    padTile(opacity: 1.0)
                @unknown default:
                    padTile(opacity: 1.0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
            )

        case .overflowMore(let count):
            ZStack {
                unifyGlassPlaceholderSlot(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius)
                Text("+\(count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
            }

        case .pad:
            padTile(opacity: 1.0)
        }
    }

    private func padTile(opacity: Double) -> some View {
        unifyGlassPlaceholderSlot(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius)
            .opacity(opacity)
    }
}

/// Horizontal media thumbnails with a “+N more” tile (non-interactive).
struct UnifyPlaceholderProfileMediaStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Media and photos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    unifyGlassPlaceholderSlot(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius)
                        .frame(height: UnifyProfileMediaStripMetrics.slotHeight)
                        .opacity(0.9 - Double(index) * 0.06)
                }

                ZStack {
                    unifyGlassPlaceholderSlot(cornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius)
                    Text("+42")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
                .frame(height: UnifyProfileMediaStripMetrics.slotHeight)
            }
        }
        .padding(16)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
