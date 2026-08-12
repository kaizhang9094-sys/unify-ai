import SwiftUI
import AnumCore

/// Large photo-first card for matched search results on the Threads Recent tab.
/// Intentionally separate from the compact `SecretarySearchResultsRecoveryCard` (no-match only).
struct SecretarySearchResultCardView: View {
    let card: SecretarySearchResultCardProjection
    let onPrimaryTap: () -> Void
    /// Child coordination path; set when `card.isActivatedCoordinationPath` (Recent dual-CTA).
    let onOpenPathTap: (() -> Void)?
    let onCompareTap: (() -> Void)?

    private let cardCornerRadius: CGFloat = 22
    /// Hero image area (150–190pt target for immersive cards).
    private let heroImageHeight: CGFloat = 180
    private let detailsPadding: CGFloat = 18
    private let detailsSpacing: CGFloat = 12
    /// Keeps sparse fallback cards taller than a History list row (~70–90pt).
    private let detailsMinHeight: CGFloat = 132

    var body: some View {
        UnifyDarkCard(cornerRadius: cardCornerRadius, strokeOpacity: 0.9) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                details
            }
        }
        #if DEBUG
        .onAppear {
            guard card.publicSupporterPresentation?.showsGuardianCrown == true else { return }
            GuardianCrownDebugLog.log(
                "Render",
                "surface=searchCard nodeID=\(card.nodeID ?? "nil") profileID=\(card.publicProfileID ?? "nil") " +
                "presentation=guardian/crown"
            )
        }
        #endif
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlString = card.primaryImageURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty, .failure:
                            heroFallback
                        @unknown default:
                            heroFallback
                        }
                    }
                } else {
                    heroFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroImageHeight)
            .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.35),
                    .black.opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 6) {
                    if card.publicSupporterPresentation?.showsGuardianCrown == true {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                            .accessibilityHidden(true)
                    }
                    Text(card.displayName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                        .layoutPriority(-1)
                }

                Spacer(minLength: 8)

                if let badge = card.strengthBadge {
                    matchStatusChip(badge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(height: heroImageHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPrimaryTap)
    }

    @ViewBuilder
    private func matchStatusChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(card.isPreferred ? SecretaryTheme.darkOrange : SecretaryTheme.white.opacity(0.18))
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private var heroFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SecretaryTheme.orangeDeep.opacity(0.35),
                    SecretaryTheme.black.opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initials(from: card.displayName))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.88))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: detailsSpacing) {
            if let headline = card.headline, !headline.isEmpty {
                Text(headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(2)
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(3)
            }

            if let area = card.serviceAreaLine ?? card.socialTagsLine, !area.isEmpty {
                Label(area, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .lineLimit(2)
            }

            if let reason = card.matchReasonSummary, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why it matched")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)

                    Text(reason)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(3)
                }
            }

            if !card.knownFactLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Known facts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)

                    ForEach(card.knownFactLines, id: \.self) { fact in
                        Text(fact)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(2)
                    }
                }
            }

            if let scoreText = card.scoreText {
                Text(scoreText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
            }

            Spacer(minLength: 0)

            ctaRow
        }
        .frame(minHeight: detailsMinHeight, alignment: .topLeading)
        .padding(detailsPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsPathCTA: Bool {
        onOpenPathTap != nil && card.pathAccess != .none
    }

    private var showsDualProfileAndPathCTA: Bool {
        showsPathCTA && card.primaryCTA == .connect
    }

    private var showsPathOnlyCTA: Bool {
        showsPathCTA && !showsDualProfileAndPathCTA
    }

    private var pathCTALabel: String {
        switch card.pathAccess {
        case .exactChild:
            return "Open path"
        case .umbrellaPaths:
            return "View active paths"
        case .none:
            return ""
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            if showsDualProfileAndPathCTA, let onOpenPathTap {
                Button(action: onPrimaryTap) {
                    Text(primaryCTALabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(SecretaryTheme.darkMutedText.opacity(0.55), lineWidth: 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(SecretaryTheme.white.opacity(0.08))
                                )
                        )
                }
                .buttonStyle(.plain)

                pathCTAButton(label: pathCTALabel, action: onOpenPathTap)
            } else if showsPathOnlyCTA, let onOpenPathTap {
                pathCTAButton(label: pathCTALabel, action: onOpenPathTap)
            } else {
                Button(action: onPrimaryTap) {
                    Text(primaryCTALabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func pathCTAButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkOrange)
                )
        }
        .buttonStyle(.plain)
    }

    private var primaryCTALabel: String {
        switch card.primaryCTA {
        case .openPath:
            return "Open path"
        case .openPaths:
            return "View active paths"
        case .openThread:
            return "Open thread"
        case .viewDetails:
            return "View details"
        case .compare:
            return "Compare"
        case .connect:
            return "View profile"
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }
        let joined = letters.joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }
}
