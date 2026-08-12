import SwiftUI
import AnumCore

/// Recent mode on the Threads tab — latest meaningful activity (search, inquiry, coordination).
struct SecretaryRecentResultsView: View {
    let session: SecretarySearchResultSessionProjection?
    let isLoading: Bool
    let onOpenThread: (ExchangeThread.ID) -> Void

    var body: some View {
        Group {
            if isLoading {
                loadingCard
            } else if let session {
                sessionContent(session)
            } else {
                recentEmptyState
            }
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: SecretarySearchResultSessionProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sessionHeader(session)

            switch session.sessionKind {
            case .inboundInquiry:
                if let inquiry = session.inquiryCard {
                    SecretaryRecentInquiryCardView(
                        card: inquiry,
                        onOpenThread: { onOpenThread(inquiry.threadID) }
                    )
                }

            case .noMatch:
                SecretarySearchResultsRecoveryCard()

            case .outboundSearch:
                outboundSearchBody(session)

            case .activeCoordination, .unknown:
                if let activity = session.activityCard {
                    SecretaryRecentActivityCardView(
                        card: activity,
                        onOpenThread: { onOpenThread(activity.threadID) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func outboundSearchBody(_ session: SecretarySearchResultSessionProjection) -> some View {
        if session.cards.isEmpty {
            SecretarySearchResultsRecoveryCard()
        } else {
            LazyVStack(spacing: 16) {
                ForEach(session.cards) { card in
                    SecretarySearchResultCardView(
                        card: card,
                        onPrimaryTap: {
                            if card.primaryCTA == .connect {
                                onOpenThread(card.umbrellaThreadID)
                            } else {
                                onOpenThread(card.linkedThreadID)
                            }
                        },
                        onOpenPathTap: recentPathTapHandler(for: card, onOpenThread: onOpenThread),
                        onCompareTap: nil
                    )
                }
            }
        }
    }

    private func sessionHeader(_ session: SecretarySearchResultSessionProjection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headerEyebrow(for: session.sessionKind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(session.searchTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(session.relativeTimeText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .layoutPriority(1)
            }

            if showsResultCount(session) {
                Text(resultCountLabel(session.resultCount))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            } else if let subtitle = inboundOrActivitySubtitle(session) {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func headerEyebrow(for kind: SecretaryRecentSessionKind) -> String {
        switch kind {
        case .outboundSearch, .noMatch:
            return "Most recent search"
        case .inboundInquiry:
            return "Latest inquiry"
        case .activeCoordination, .unknown:
            return "Latest activity"
        }
    }

    private func showsResultCount(_ session: SecretarySearchResultSessionProjection) -> Bool {
        session.sessionKind == .outboundSearch && session.resultCount > 0
    }

    private func inboundOrActivitySubtitle(_ session: SecretarySearchResultSessionProjection) -> String? {
        switch session.sessionKind {
        case .inboundInquiry:
            return session.inquiryCard?.statusLabel
        case .activeCoordination, .unknown:
            return session.activityCard?.statusLabel
        default:
            return nil
        }
    }

    private func resultCountLabel(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    private var loadingCard: some View {
        UnifyDarkCard(cornerRadius: 20, strokeOpacity: 0.88) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(SecretaryTheme.darkOrange)
                Text("Loading recent activity…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentPathTapHandler(
        for card: SecretarySearchResultCardProjection,
        onOpenThread: @escaping (ExchangeThread.ID) -> Void
    ) -> (() -> Void)? {
        switch card.pathAccess {
        case .exactChild(let childThreadID):
            return { onOpenThread(childThreadID) }
        case .umbrellaPaths(let umbrellaThreadID):
            return { onOpenThread(umbrellaThreadID) }
        case .none:
            return nil
        }
    }

    /// True empty: no recent session exists (not the no-match recovery card for an active search).
    private var recentEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No activities yet.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text("Searches, inquiries, and active threads will appear here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }
}
