import SwiftUI
import AnumCore

struct SecretaryNeedOfferPanel: View {
    enum Mode {
        case need
        case offer
    }

    let mode: Mode
    let title: String
    let summary: String
    let examples: [String]

    let sellerWorkspace: ExchangeModels.SellerWorkspaceSummary?
    let sellerValidationIssues: [ExchangeSellerValidationIssue]

    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onCreateProfile: (() -> Void)?
    let onAddOffer: (() -> Void)?
    let onPublishSurface: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            UnifyDarkBackground(showsSubtleVignette: true)

            LinearGradient(
                colors: [
                    SecretaryTheme.darkOrange.opacity(0.10),
                    SecretaryTheme.darkOrange.opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryCard

                    if mode == .offer {
                        surfaceStatusCard
                        surfaceIssuesCard
                        surfaceOffersCard
                    } else {
                        examplesCard
                    }

                    actionCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func needOfferDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func needOfferSectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SecretaryTheme.darkOrangeSoft.opacity(0.38))
                )
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
            Spacer(minLength: 0)
        }
    }

    private func needOfferAttentionChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.48))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.38), lineWidth: 1)
            )
    }

    private func needOfferMutedChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )
    }

    private func needOfferPrimaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrange)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func needOfferSecondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            needOfferAttentionChip(mode == .need ? "Looking For" : "Outward Lane")

            Text(title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                mode == .need
                ? "Turn a need into movement through search, trusted paths, and counterparties."
                : "Shape how your secretary represents you publicly, and what concrete active lanes people can discover."
            )
            .font(.system(size: 15))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryCard: some View {
        needOfferDarkCard {
            VStack(alignment: .leading, spacing: 12) {
                needOfferSectionHeader(
                    title: mode == .need ? "What you want moved toward you" : "What you are putting outward",
                    systemImage: mode == .need ? "magnifyingglass" : "shippingbox"
                )

                Text(summary)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var surfaceStatusCard: some View {
        needOfferDarkCard {
            VStack(alignment: .leading, spacing: 12) {
                needOfferSectionHeader(
                    title: "Public surface",
                    systemImage: "shippingbox"
                )

                if let workspace = sellerWorkspace {
                    if let profile = workspace.publicProfile {
                        Text(profile.summaryLine ?? workspace.statusLine)
                            .font(.system(size: 15))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let intro = nonEmpty(profile.publicIntroLine) {
                            Text(intro)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let discoverability = nonEmpty(workspace.discoverabilityLine ?? profile.discoverabilityLine) {
                            Text(discoverability)
                                .font(.system(size: 13))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(workspace.statusLine)
                            .font(.system(size: 15))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(
                        "\(workspace.activeOfferCount) active · \(workspace.draftOfferCount) draft · \(workspace.pausedOfferCount) paused · \(workspace.archivedOfferCount) archived"
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    if let detail = nonEmpty(workspace.publicationDetailLine) {
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let next = nonEmpty(workspace.nextStepText) {
                        Text(next)
                            .font(.system(size: 14))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let profile = workspace.publicProfile {
                        VStack(alignment: .leading, spacing: 8) {
                            if let openTo = nonEmpty(profile.openToLine) {
                                sellerMetaLine(title: "Open to", value: openTo)
                            }

                            if let offers = nonEmpty(profile.offerLine) {
                                sellerMetaLine(title: "General offers", value: offers)
                            }

                            if let interests = nonEmpty(profile.interestLine) {
                                sellerMetaLine(title: "Interests", value: interests)
                            }

                            if let activities = nonEmpty(profile.activityLine) {
                                sellerMetaLine(title: "Activities", value: activities)
                            }

                            if let regions = nonEmpty(profile.regionLine) {
                                sellerMetaLine(title: "Regions", value: regions)
                            }
                        }
                    }
                } else {
                    Text("No outward surface has been set up yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var surfaceIssuesCard: some View {
        if mode == .offer, !sellerValidationIssues.isEmpty {
            needOfferDarkCard {
                VStack(alignment: .leading, spacing: 12) {
                    needOfferSectionHeader(
                        title: "What needs attention",
                        systemImage: "exclamationmark.triangle"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sellerValidationIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(
                                        issue.severity == .error
                                        ? SecretaryTheme.darkOrange
                                        : SecretaryTheme.darkOrange.opacity(0.55)
                                    )
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)

                                Text(issue.summary)
                                    .font(.system(size: 15))
                                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var surfaceOffersCard: some View {
        needOfferDarkCard {
            VStack(alignment: .leading, spacing: 12) {
                needOfferSectionHeader(
                    title: "Active lanes",
                    systemImage: "cube.box"
                )

                if let workspace = sellerWorkspace, !workspace.offers.isEmpty {
                    let visibleOffers = Array(workspace.offers.prefix(5))

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleOffers) { offer in
                            surfaceOfferRow(
                                offer,
                                isLast: offer.id == visibleOffers.last?.id
                            )
                        }
                    }
                } else {
                    Text("No active lanes yet. Add at least one concrete lane so your public surface has something specific to project outward.")
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func surfaceOfferRow(
        _ offer: ExchangeModels.OfferView,
        isLast: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(offer.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                if let subtitle = nonEmpty(offer.subtitle) {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("\(offer.statusText) · \(offer.visibilityText)")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    if let fulfillment = nonEmpty(offer.fulfillmentText) {
                        Text("• \(fulfillment)")
                            .font(.system(size: 12))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let region = nonEmpty(offer.regionText) {
                    Text("Region: \(region)")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                if let tags = nonEmpty(offer.tagLine) {
                    Text(tags)
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(1)
                }

                if let contact = nonEmpty(offer.contactSummary) {
                    Text("Contact: \(contact)")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !isLast {
                Divider()
                    .overlay(SecretaryTheme.darkStroke.opacity(0.55))
            }
        }
    }

    private var examplesCard: some View {
        needOfferDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                needOfferSectionHeader(
                    title: "Examples",
                    systemImage: "lightbulb"
                )

                if examples.isEmpty {
                    Text("No examples yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(SecretaryTheme.darkOrange.opacity(0.70))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)

                                Text(example)
                                    .font(.system(size: 15))
                                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var shouldShowCreateProfileButton: Bool {
        sellerWorkspace?.publicProfile == nil
    }

    private var shouldShowAddOfferButton: Bool {
        guard let workspace = sellerWorkspace else { return false }
        return workspace.publicProfile != nil && workspace.offers.isEmpty
    }

    private var actionCard: some View {
        needOfferDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                needOfferSectionHeader(
                    title: "Next move",
                    systemImage: "arrow.right.circle"
                )

                Text(
                    mode == .need
                    ? "The secretary can help search, compare, and prepare a bounded outreach path."
                    : "Set up your public surface, make at least one active lane legible, then publish only when the surface is actually ready."
                )
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

                if mode == .offer {
                    if let workspace = sellerWorkspace {
                        if let hint = nonEmpty(workspace.primaryCTAHint) {
                            Text(hint)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let detail = nonEmpty(workspace.publicationDetailLine) {
                            Text(detail)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        if shouldShowCreateProfileButton, let onCreateProfile {
                            needOfferSecondaryButton(
                                title: "Create profile",
                                systemImage: "person.crop.square",
                                action: onCreateProfile
                            )
                            .frame(maxWidth: .infinity)
                        }

                        if shouldShowAddOfferButton, let onAddOffer {
                            needOfferSecondaryButton(
                                title: "Add active lane",
                                systemImage: "plus",
                                action: onAddOffer
                            )
                            .frame(maxWidth: .infinity)
                        }

                        needOfferSecondaryButton(
                            title: "See threads",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            action: onSecondaryAction
                        )
                        .frame(maxWidth: .infinity)
                    }

                    needOfferPrimaryButton(
                        title: primaryOfferButtonTitle,
                        systemImage: "wand.and.stars",
                        action: onPrimaryAction
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 10) {
                        needOfferSecondaryButton(
                            title: "See trusted paths",
                            systemImage: "person.2",
                            action: onSecondaryAction
                        )
                        .frame(maxWidth: .infinity)

                        needOfferPrimaryButton(
                            title: "Start search",
                            systemImage: "magnifyingglass",
                            action: onPrimaryAction
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var primaryOfferButtonTitle: String {
        if let hint = nonEmpty(sellerWorkspace?.primaryCTAHint) {
            return hint
        }

        guard let workspace = sellerWorkspace else {
            return "Set up outward lane"
        }

        if workspace.publicProfile == nil {
            return "Create profile"
        }

        if !sellerValidationIssues.isEmpty {
            return "Fix surface"
        }

        if workspace.offers.isEmpty {
            return "Add active lane"
        }

        if workspace.publicationState?.status != .published {
            return "Publish surface"
        }

        return "Manage outward lane"
    }

    @ViewBuilder
    private func sellerMetaLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(title):")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
