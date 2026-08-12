import SwiftUI
import AnumCore

struct SecretaryDashboardView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("companionName") private var companionName: String = "Uni"

    let isTabActive: Bool
    let refreshID: Int
    let preferredThreadID: ExchangeThread.ID?
    let onOpenThread: (ExchangeThread.ID) -> Void
    let onOpenThreads: () -> Void
    let onOpenApprovals: () -> Void
    let onOpenTrust: () -> Void
    let onOpenBlocked: () -> Void
    let onOpenClarification: (ExchangeThread.ID) -> Void
    let onRefreshSearch: (ExchangeThread.ID) -> Void
    let onOpenApprovalSheet: (SecretaryApprovalSheet.Display) -> Void
    let onOpenRecoveryPanel: (SecretaryRecoveryPanel.Display) -> Void
    let onViewDiscoveryResults: (ExchangeThread.ID) -> Void
    /// Profile is the canonical public-surface UI; kept for workspace wiring (no Home card in this view).
    let onOpenProfileForPublicSurface: () -> Void

    let secretaryNotificationUnreadBadge: Int
    let onOpenSecretaryNotifications: () -> Void
    let onReturnToCompanion: () -> Void

    @State private var threadItems: [ExchangeModels.InboxItem] = []
    @State private var inboxItems: [ExchangeInboxItem] = []
    @State private var pendingApprovals: [ExchangeModels.PendingApproval] = []
    @State private var appliedDeskSnapshotGeneration: UInt64 = 0
    @State private var deskSnapshotApplyTask: Task<Void, Never>?
    @State private var hasLoadedDeskOnce = false
    @State private var isDeskLoading = true

    @State private var projectedThreadsCache: [ProjectedThread] = []
    @State private var pendingProjectedCache: [ProjectedThread] = []
    @State private var searchProjectedCache: [ProjectedThread] = []
    @State private var activeProjectedCache: [ProjectedThread] = []
    @State private var trustedProjectedCache: [ProjectedThread] = []
    @State private var recoveryProjectedCache: [ProjectedThread] = []
    @State private var visibleInboxItemsCache: [ExchangeInboxItem] = []
    @State private var activeFeedItemsCache: [ActiveFeedItem] = []
    /// Paging index for the For You `TabView` (discovery carousel only).
    @State private var forYouCarouselIndex: Int = 0
    @State private var forYouConnectInFlightIDs: Set<String> = []
    @State private var forYouConnectLastError: String?
    /// Target node IDs from `ExchangeFacade.listTrustedNodes` (refreshed when the For You profile sheet opens).
    @State private var forYouTrustedNodeIDsSnapshot: Set<String> = []
    /// Outbound contact-request targets (`listPendingOutgoingContactRequests`), refreshed with the profile sheet.
    @State private var forYouPendingNodeIDs: Set<String> = []
    /// True while turning the For You rail on and running a forced refresh (non-blocking for the rest of the dashboard).
    @State private var forYouDiscoveryToggleRefreshing = false
    /// Full profile sheet for a For You match (trusted Connect / Open live here, not on the swipe card).
    @State private var forYouProfileSheetItem: ExchangeModels.ForYouItem?
    @State private var imageGalleryPresentation: SecretaryImageGalleryPresentation?

    private struct ProjectedThread: Identifiable {
        let item: ExchangeModels.InboxItem
        let bucket: SecretaryProjectionEngine.Bucket

        var id: ExchangeThread.ID { item.threadID }
        var updatedAt: Date { item.updatedAt }
    }

    private enum ActiveFeedItem: Identifiable {
        case thread(ProjectedThread)
        case inbound(ExchangeInboxItem)

        var id: String {
            switch self {
            case .thread(let row):
                return "thread-\(row.id.uuidString)"
            case .inbound(let item):
                return "inbound-\(item.id.uuidString)"
            }
        }

        var updatedAt: Date {
            switch self {
            case .thread(let row):
                return row.updatedAt
            case .inbound(let item):
                return item.updatedAt
            }
        }
    }

    private var pendingApprovalThreadIDs: Set<ExchangeThread.ID> {
        Set(pendingApprovals.map(\.threadID))
    }

    /// For You carousel items (same gating as discovery rail).
    private var forYouCarouselItems: [ExchangeModels.ForYouItem] {
        guard services.secretaryDiscoveryMode == .discoverOnly else { return [] }
        return Array(services.forYouItems.prefix(10))
    }

    /// Forces `TabView` to rebuild when the canonical rail identity changes (avoids a stuck empty carousel after relaunch).
    private var forYouTabViewIdentity: String {
        guard services.secretaryDiscoveryMode == .discoverOnly else { return "off" }
        return services.forYouItems.prefix(10).map(\.id).joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(spacing: 20) {
                    discoveryPageHeader
                    discoveryRecentActivityStrip
                    briefingHeroDeck(availableWidth: geo.size.width)
                }
                .padding(.horizontal, 16)
                .padding(.top, geo.safeAreaInsets.top + UnifyMainTabScrollLayout.paddingBelowSafeArea)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear {
                    guard isTabActive else { return }
#if DEBUG
                    print(
                        "[ForYouHydration] appear enabled=\(services.secretaryDiscoveryMode == .discoverOnly) " +
                        "items=\(services.forYouItems.count) inFlight=\(services.isForYouDiscoveryPassInFlight)"
                    )
#endif
                    services.ensureForYouHydratedIfNeeded(reason: "discoveryAppear")
                }
                .onChange(of: scenePhase) { _, phase in
                    guard isTabActive, phase == .active else { return }
#if DEBUG
                    print(
                        "[ForYouHydration] scene active enabled=\(services.secretaryDiscoveryMode == .discoverOnly) " +
                        "items=\(services.forYouItems.count) inFlight=\(services.isForYouDiscoveryPassInFlight)"
                    )
#endif
                    services.ensureForYouHydratedIfNeeded(reason: "sceneActive")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $imageGalleryPresentation) { presentation in
            SecretaryImageGalleryViewer(presentation: presentation) {
                imageGalleryPresentation = nil
            }
        }
        .sheet(item: $forYouProfileSheetItem) { item in
            forYouProfileDetailSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(generation: services.secretaryDeskSnapshot?.generation)
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            scheduleApplyDeskSnapshot(generation: services.secretaryDeskSnapshot?.generation)
        }
        .onChange(of: services.secretaryDeskSnapshot?.generation) { _, generation in
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(generation: generation)
        }
        .onChange(of: refreshID) { _, _ in
            guard isTabActive else { return }
            Task { await refreshForYouRelationshipStateFromCanonicalStore() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryWorkspaceShouldRefresh)) { notification in
            guard isTabActive else { return }
            let refreshReason =
                notification.userInfo?["secretaryRefreshReason"] as? String
                ?? notification.userInfo?["reason"] as? String
            guard refreshReason == ExchangeContactRelationshipRefreshNotification.relationshipChangedSecretaryRefreshReason
                || refreshReason == "contactRequestAccepted"
                || refreshReason == "contactRequestAcceptedReceive" else {
                return
            }
            Task { await refreshForYouRelationshipStateFromCanonicalStore() }
        }
        .onDisappear {
            deskSnapshotApplyTask?.cancel()
            deskSnapshotApplyTask = nil
        }
    }

    // MARK: - Discovery chrome

    /// Visual parity with `SecretaryThreadListView.secretaryStatusCard` / `ThreadsSecretaryHeroOrbMetrics` (Threads “Secretary style” row).
    private enum DiscoverySecretaryStripMetrics {
        static let orbDiameter: CGFloat = 53
        static let rowSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let textColumnSpacing: CGFloat = 4
        static let minSpacerAfterText: CGFloat = 6
    }

    private var discoveryPageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Discovery")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    discoveryDeskIconButton(
                        systemName: "bell",
                        accessibilityLabel: "Updates",
                        badgeCount: secretaryNotificationUnreadBadge,
                        action: onOpenSecretaryNotifications
                    )

                    discoveryDeskIconButton(
                        systemName: "bubble.left.and.bubble.right.fill",
                        accessibilityLabel: "Switch to Chat",
                        badgeCount: 0,
                        action: onReturnToCompanion
                    )
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Discovery recent activity (compact lane under header)

    @ViewBuilder
    private var discoveryRecentActivityStrip: some View {
        if shouldKeepDiscoveryHeroProgressForSubmitHandoff,
           let progress = services.discoveryHeroProgress {
            discoveryCompactProgressStrip(progress: progress)
        } else if shouldShowCurrentWorkLoader {
            discoveryCompactLoadingStrip
        } else if let row = effectiveCurrentSearchStripRow {
            discoveryCompactPriorityThreadCard(row: row)
        } else if let feed = activeFeedItems.first {
            discoveryCompactActiveFeedCard(feed: feed)
        }
    }

    private func discoveryCompactProgressStrip(
        progress: DiscoveryHeroProgressProjection
    ) -> some View {
        HStack(alignment: .center, spacing: DiscoverySecretaryStripMetrics.rowSpacing) {
            CompanionAvatarThreadsHeroOrb(
                diameter: DiscoverySecretaryStripMetrics.orbDiameter
            )

            VStack(alignment: .leading, spacing: DiscoverySecretaryStripMetrics.textColumnSpacing) {
                Text(discoveryProgressOriginalRequestLine(progress.originalText))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                DiscoveryHeroAnimatedStageLine(
                    stage: progress.stage,
                    aiDisplayName: progress.aiDisplayName,
                    isActive: progress.isActive
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DiscoverySecretaryStripMetrics.horizontalPadding)
        .padding(.vertical, DiscoverySecretaryStripMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            DiscoveryHeroProgressProjection.accessibilityLabel(
                stage: progress.stage,
                aiDisplayName: progress.aiDisplayName,
                originalText: progress.originalText
            )
        )
    }

    private func discoveryProgressOriginalRequestLine(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New request" }
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(117)) + "..."
    }

    private var discoveryCompactLoadingStrip: some View {
        HStack(alignment: .center, spacing: DiscoverySecretaryStripMetrics.rowSpacing) {
            SecretaryPhotoOrb(
                initials: "S",
                systemImage: "sparkles",
                style: .neutral,
                size: DiscoverySecretaryStripMetrics.orbDiameter
            )

            VStack(alignment: .leading, spacing: DiscoverySecretaryStripMetrics.textColumnSpacing) {
                Text("Current work")
                    .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

                Text("Opening current work.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text("Checking active exchanges and discovery updates.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: DiscoverySecretaryStripMetrics.minSpacerAfterText)

            ProgressView()
                .scaleEffect(0.9)
                .tint(SecretaryTheme.darkOrange)
        }
        .padding(.horizontal, DiscoverySecretaryStripMetrics.horizontalPadding)
        .padding(.vertical, DiscoverySecretaryStripMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
    }

    private func discoveryCompactPriorityThreadCard(row: ProjectedThread) -> some View {
        let item = row.item
        let kind = row.bucket
        let vs = workTileVisibleStatus(for: item, kind: kind)
        let time = SecretaryRelativeTime.string(from: item.updatedAt)
        let reasonSubtitle = compactDiscoveryStripThirdLine(for: item, kind: kind, vs: vs)
        let statusLabel = discoveryCompactStripStatusLabel(for: item, vs: vs)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                routeDiscoveryCompactOpen(item, kind: kind)
            } label: {
                HStack(alignment: .center, spacing: DiscoverySecretaryStripMetrics.rowSpacing) {
                    DiscoveryCompactStripLeadAvatar(
                        normalizedImageCandidates: discoveryCompactStripThreadImageCandidates(for: item),
                        initials: initials(from: heroRequestTitle(for: item)),
                        systemImage: vs.systemImage,
                        orbStyle: workTileToneStyle(vs.tone),
                        diameter: DiscoverySecretaryStripMetrics.orbDiameter
                    )

                    VStack(alignment: .leading, spacing: DiscoverySecretaryStripMetrics.textColumnSpacing) {
                        Text(statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(discoveryStatusLabelColor(for: vs.tone))

                        Text(heroRequestTitle(for: item))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Text(reasonSubtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: DiscoverySecretaryStripMetrics.minSpacerAfterText)

                    HStack(spacing: 4) {
                        Text(discoveryCompactCTA(for: item, kind: kind))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkOrange)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) {
                    Text(time)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText.opacity(0.88))
                        .padding(.trailing, 2)
                        .padding(.bottom, 1)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DiscoverySecretaryStripMetrics.horizontalPadding)
            .padding(.vertical, DiscoverySecretaryStripMetrics.verticalPadding)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                accessibilityDiscoveryCompactThreadSummary(
                    title: heroRequestTitle(for: item),
                    stateLabel: statusLabel,
                    reason: reasonSubtitle,
                    time: time,
                    cta: discoveryCompactCTA(for: item, kind: kind)
                )
            )
        }
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
        #if DEBUG
        .onAppear {
            logDashboardStripState(
                item: item,
                kind: kind,
                vs: vs,
                reasonSubtitle: reasonSubtitle
            )
        }
        #endif
    }

    /// Discovery compact strip status line — aligned with canonical current-search item state.
    private func discoveryCompactStripStatusLabel(
        for item: ExchangeModels.InboxItem,
        vs: SecretaryProjectionEngine.ExchangeVisibleThreadStatus
    ) -> String {
        if case .searching = item.state {
            return "Searching"
        }
        if case .noViableMatch = item.state {
            return "No match found"
        }
        if case .matchCandidatesWeak = item.state {
            return "Weak matches"
        }
        if case .matchFound = item.state, !discoveryCompactHasVerifiedResults(item) {
            return "Open"
        }
        return vs.label
    }

    /// Discovery compact strip **only**: third line under the title. Never uses long ``workTileStatusLine`` / global subtitles.
    /// Always fewer than 5 words (reworded, not truncated).
    private func discoveryCompactHasVerifiedResults(_ item: ExchangeModels.InboxItem) -> Bool {
        if SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: item) { return true }
        guard case .matchFound = item.state else { return false }
        return SecretaryProjectionEngine.hasSummaryDiscoveryResultEvidence(for: item)
    }

    private func compactDiscoveryStripThirdLine(
        for item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket,
        vs: SecretaryProjectionEngine.ExchangeVisibleThreadStatus
    ) -> String {
        if case .searching = item.state {
            return "Still searching"
        }

        if SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: item) {
            return "Results ready"
        }

        if kind == .searchResult || SecretaryProjectionEngine.isSearchResult(item) {
            switch item.state {
            case .noViableMatch:
                return discoveryCompactNoMatchSubtitle(for: item)
            case .matchCandidatesWeak:
                return "Review or refine"
            case .matchFound:
                if discoveryCompactHasVerifiedResults(item) {
                    return "Results ready"
                }
            default:
                return "Open recent results"
            }
        }

        if SecretaryProjectionEngine.isClarification(item) {
            return "Answer needed"
        }

        let rawStatusLine = workTileStatusLine(for: item, kind: kind)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSubtitle = vs.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if discoveryCompactHasVerifiedResults(item),
           discoveryCompactStripLooksLikeCandidateReviewDump(rawStatusLine)
            || discoveryCompactStripLooksLikeCandidateReviewDump(rawSubtitle) {
            return "Results ready"
        }

        // Belt-and-suspenders: long structural copy must not appear in this strip (see ``visibleThreadStatus`` subtitle).
        if rawSubtitle.contains("Something stopped this thread")
            || rawStatusLine.contains("Something stopped this thread") {
            return "Action needed"
        }
        if rawSubtitle.lowercased().contains("try refining the request")
            || rawStatusLine.lowercased().contains("try refining the request") {
            return "Refine your request"
        }
        if rawSubtitle.contains("Review or refine before choosing")
            || rawStatusLine.contains("Review or refine before choosing") {
            return "Review or refine"
        }
        if rawSubtitle.lowercased().contains("approval") && rawSubtitle.lowercased().contains("before")
            && discoveryStripWordCount(rawSubtitle) >= 5 {
            return "Approval needed"
        }

        switch vs.primary {
        case .needsFix:
            return "Action needed"
        case .noConfirmedMatch:
            return "Refine your request"
        case .potentialMatch:
            return "Review or refine"
        case .approvalNeeded:
            return "Approval needed"
        case .waitingForReply:
            return "Waiting for reply"
        case .needsYourInput:
            return "More input needed"
        case .draftReady:
            return "Ready to send"
        case .sending:
            return "Sending message"
        case .replyReceived:
            return "New reply"
        case .needsReviewArtifacts, .needsReview:
            return "Review needed"
        case .pulledOffer:
            return "Offer ready"
        case .pulledProfile:
            return "Profile ready"
        case .completed:
            return "Completed"
        case .openExchange:
            return "Open for details"
        }
    }

    private func discoveryCompactNoMatchSubtitle(for item: ExchangeModels.InboxItem) -> String {
        if let nextStep = SecretaryProjectionEngine.nonEmpty(item.interpretationNextStep) {
            return discoveryCompactStripShortPhrase(from: nextStep, fallback: "Refine search or widen scope")
        }
        return "Refine search or widen scope"
    }

    /// Compact third-line copy: prefer a short phrase from longer next-step guidance.
    private func discoveryCompactStripShortPhrase(from raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if discoveryStripWordCount(trimmed) <= 5 {
            return trimmed
        }
        let lowered = trimmed.lowercased()
        if lowered.contains("widen") {
            return "Refine search or widen scope"
        }
        if lowered.contains("refin") {
            return "Refine your request"
        }
        return fallback
    }

    private func discoveryStripWordCount(_ text: String) -> Int {
        let parts = text.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        return parts.count
    }

    /// Blocks compare/candidate-review dump strings from the compact Discovery strip only.
    private func discoveryCompactStripLooksLikeCandidateReviewDump(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        if lowered.contains("other matches:") { return true }
        if lowered.contains("possible matches") && lowered.contains("checking") { return true }
        if lowered.hasPrefix("found ") && lowered.contains("checking") { return true }
        if lowered.contains("compare path") { return true }
        return false
    }

    private func discoveryCompactShouldRouteToThreads(
        _ item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket
    ) -> Bool {
        if SecretaryProjectionEngine.isTerminalSearchReceipt(item) {
            return true
        }
        if kind == .searchResult { return true }
        if SecretaryProjectionEngine.isSearchResult(item) { return true }
        if SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: item) { return true }

        switch item.state {
        case .searching, .matchFound, .matchCandidatesWeak:
            return true
        case .drafting, .draftReady:
            return item.shouldDiscover
        default:
            return false
        }
    }

    private func accessibilityDiscoveryCompactThreadSummary(
        title: String,
        stateLabel: String,
        reason: String,
        time: String,
        cta: String
    ) -> String {
        if reason.isEmpty {
            return "\(title). \(stateLabel). \(time). \(cta)."
        }
        return "\(title). \(stateLabel). \(reason). \(time). \(cta)."
    }

    @ViewBuilder
    private func discoveryCompactActiveFeedCard(feed: ActiveFeedItem) -> some View {
        switch feed {
        case .thread(let row):
            discoveryCompactPriorityThreadCard(row: row)
        case .inbound(let item):
            Button {
                if let threadID = item.threadID {
                    onOpenThread(threadID)
                } else {
                    onOpenApprovals()
                }
            } label: {
                HStack(alignment: .center, spacing: DiscoverySecretaryStripMetrics.rowSpacing) {
                    DiscoveryCompactStripLeadAvatar(
                        normalizedImageCandidates: discoveryCompactStripInboundImageCandidates(for: item),
                        initials: initials(from: inboundTitle(for: item)),
                        systemImage: nil,
                        orbStyle: inboundBadgeStyle(for: item),
                        diameter: DiscoverySecretaryStripMetrics.orbDiameter
                    )

                    VStack(alignment: .leading, spacing: DiscoverySecretaryStripMetrics.textColumnSpacing) {
                        Text(inboundBadge(for: item))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)

                        Text(inboundTitle(for: item))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Text(inboundCombinedStatusLine(for: item))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DiscoverySecretaryStripMetrics.minSpacerAfterText)

                    Text("Open")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DiscoverySecretaryStripMetrics.horizontalPadding)
            .padding(.vertical, DiscoverySecretaryStripMetrics.verticalPadding)
            .background {
                UnifyProfileTranslucentPanelBackground()
            }
        }
    }

    /// Compact Discovery strip only: CTA copy aligned with ``routeDiscoveryCompactOpen`` branches.
    private func discoveryCompactCTA(for item: ExchangeModels.InboxItem, kind: SecretaryProjectionEngine.Bucket) -> String {
        if SecretaryProjectionEngine.isClarification(item) {
            return "Answer"
        }

        if hasExecutablePendingApproval(item) {
            return "Approve"
        }

        if SecretaryProjectionEngine.isRecovery(item) {
            return "Recover"
        }

        return "Open"
    }

    private func discoveryDeskIconButton(
        systemName: String,
        accessibilityLabel: String,
        badgeCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                    .frame(width: 40, height: 40)
                    .background {
                        UnifyGlassIconDisk(diameter: 40, strokeOpacity: 0.85)
                    }

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                        .offset(x: 9, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - For You (autonomous discovery carousel — not Current Work)

    /// Matches default `UnifyProfileTranslucentPanelBackground` / Threads secretary status card radius.
    private let forYouCardCornerRadius: CGFloat = 24

    /// The For You carousel should fit inside the visible Discovery page instead of using
    /// a feed-tall fixed image card. Height is derived from the available card width.
    private func forYouCardHeight(for cardWidth: CGFloat) -> CGFloat {
        min(max(cardWidth * 1.18, 430), 520)
    }

    private enum ForYouPlaceholderMetrics {
        static let uniImageMaxHeight: CGFloat = 286
        static let uniImageHorizontalInset: CGFloat = 20
        static let copySpacing: CGFloat = 8
        /// Top band so centered art clears the Off/On pill overlay.
        static let topInsetBelowToggle: CGFloat = 48
        static let bottomCopyInset: CGFloat = 28
        /// Lifts off-state title/subtitle only; image layout unchanged.
        static let offStateCopyUpwardOffset: CGFloat = -20
        /// Fallback when asset catalog image is unavailable.
        static let iconDiskDiameter: CGFloat = 88
        static let iconSymbolPointSize: CGFloat = 32
    }

    /// Shared tall glass shell for For You placeholder + profile cards (canonical soft veil, page shows through).
    @ViewBuilder
    private func forYouTallGlassCardShell<Content: View>(
        cardWidth: CGFloat,
        cardHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            UnifyProfileTranslucentPanelBackground(cornerRadius: forYouCardCornerRadius)
            content()
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: forYouCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: forYouCardCornerRadius, style: .continuous)
                .stroke(SecretaryTheme.white.opacity(0.075), lineWidth: 1)
        )
        .shadow(color: SecretaryTheme.darkShadow.opacity(0.2), radius: 14, x: 0, y: 8)
    }

    private func briefingHeroDeck(availableWidth: CGFloat) -> some View {
        let carouselItems = forYouCarouselItems
        let pageCount = carouselItems.count
        let forYouRailOn = services.secretaryDiscoveryMode == .discoverOnly
        let cardWidth = max(0, availableWidth - 32)
        let cardHeight = forYouCardHeight(for: cardWidth)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested for you")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text(briefingHeroSubline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topTrailing) {
                if carouselItems.isEmpty {
                    forYouRailPlaceholderSurface(
                        railOn: forYouRailOn,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight
                    )
                } else {
                    TabView(selection: $forYouCarouselIndex) {
                        ForEach(Array(carouselItems.enumerated()), id: \.element.id) { index, item in
                            forYouPhotoFirstProfileCard(item: item, cardWidth: cardWidth)
                                .frame(width: cardWidth, height: cardHeight)
                                .tag(index)
                        }
                    }
                    .id(forYouTabViewIdentity)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }

                forYouDiscoveryToggleChip(isRailOn: forYouRailOn, overlayCompact: true)
                    .padding(12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .onChange(of: services.forYouItems.count) { _, newCount in
                let capped = min(10, newCount)
                if capped == 0 {
                    forYouCarouselIndex = 0
                } else if forYouCarouselIndex >= capped {
                    forYouCarouselIndex = max(0, capped - 1)
                }
            }

            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(
                                i == forYouCarouselIndex
                                    ? SecretaryTheme.darkOrange.opacity(0.55)
                                    : SecretaryTheme.white.opacity(0.14)
                            )
                            .frame(width: i == forYouCarouselIndex ? 5 : 4, height: i == forYouCarouselIndex ? 5 : 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }

            if let err = forYouConnectLastError {
                Text(err)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var briefingHeroSubline: String {
        if services.secretaryDiscoveryMode != .discoverOnly {
            return "Discovery is off"
        }
        if forYouDiscoveryToggleRefreshing || services.isForYouRefreshInFlight {
            return "Looking for profiles"
        }
        if let failure = services.forYouLastPassFailure {
            switch failure.kind {
            case .needsMoreSpecificFocus:
                return "Add a focus to discover"
            case .invalidRequest, .networkOrServer:
                return "Couldn't refresh suggestions"
            }
        }
        if services.forYouItems.isEmpty {
            switch services.forYouDiscoveryQuality?.tier {
            case .some(.sparse):
                return "Network still growing"
            case .some(.empty):
                return "No strong matches"
            default:
                return "Discovery is on"
            }
        }
        if let q = services.forYouDiscoveryQuality, q.tier == .weak {
            return "Early profile matches"
        }
        if let q = services.forYouDiscoveryQuality, q.tier == .strong {
            return "Profiles found for you"
        }
        return "Discovery is on"
    }

    /// Dashboard-only control: `.discoverOnly` vs `.off`. Does not use draft or auto-send modes.
    @ViewBuilder
    private func forYouDiscoveryToggleChip(isRailOn: Bool, overlayCompact: Bool = false) -> some View {
        Button {
            Task { @MainActor in
                if isRailOn {
                    services.saveSecretaryDiscoveryMode(.off)
                    forYouCarouselIndex = 0
                } else {
                    services.saveSecretaryDiscoveryMode(.discoverOnly)
                    forYouDiscoveryToggleRefreshing = true
                    defer { forYouDiscoveryToggleRefreshing = false }
                    await services.refreshForYouIfEligible(force: true)
                }
            }
        } label: {
            HStack(spacing: overlayCompact ? 4 : 6) {
                if forYouDiscoveryToggleRefreshing {
                    ProgressView()
                        .scaleEffect(overlayCompact ? 0.68 : 0.78)
                        .tint(SecretaryTheme.darkOrange)
                } else {
                    Image(systemName: isRailOn ? "sparkles" : "moon.fill")
                        .font(.system(size: overlayCompact ? 11 : 12, weight: .semibold))
                }
                Text(isRailOn ? "On" : "Off")
                    .font(.system(size: overlayCompact ? 11 : 12.5, weight: .bold))
            }
            .foregroundStyle(isRailOn ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
            .padding(.horizontal, overlayCompact ? 10 : 12)
            .padding(.vertical, overlayCompact ? 6 : 8)
            .background {
                UnifySoftVeilCapsule()
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.white.opacity(0.075), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(forYouDiscoveryToggleRefreshing)
        .accessibilityLabel(isRailOn ? "For You discovery on" : "For You discovery off")
        .accessibilityHint("Toggles profile-based discovery for the For You rail")
    }

    private var forYouEmptyCompanionDisplayName: String {
        let trimmed = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Uni" : trimmed
    }

    /// Quiet placeholder when the rail has no swipeable profiles.
    @ViewBuilder
    private func forYouRailPlaceholderSurface(
        railOn: Bool,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> some View {
        if railOn {
            forYouRailActiveEmptySurface(cardWidth: cardWidth, cardHeight: cardHeight)
        } else {
            forYouRailOffSurface(cardWidth: cardWidth, cardHeight: cardHeight)
        }
    }

    /// Discovery off: Uni art + resting copy.
    private func forYouRailOffSurface(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let name = forYouEmptyCompanionDisplayName
        let restingTitle = "\(name) is resting"
        let restingSubtitle = "Turn it on to let \(name) find people and opportunities."

        return forYouTallGlassCardShell(cardWidth: cardWidth, cardHeight: cardHeight) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: ForYouPlaceholderMetrics.topInsetBelowToggle)

                ZStack {
                    if discoveryEmptyUniAssetAvailable {
                        Image("DiscoveryEmptyUniSleeping")
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, ForYouPlaceholderMetrics.uniImageHorizontalInset)
                            .frame(maxWidth: .infinity, maxHeight: ForYouPlaceholderMetrics.uniImageMaxHeight)
                            .accessibilityHidden(true)
                    } else {
                        forYouRailPlaceholderSymbolFallback(railOn: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: ForYouPlaceholderMetrics.copySpacing) {
                    Text(restingTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                        .multilineTextAlignment(.center)

                    Text(restingSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, ForYouPlaceholderMetrics.bottomCopyInset)
                .offset(y: ForYouPlaceholderMetrics.offStateCopyUpwardOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(restingTitle). \(restingSubtitle)")
    }

    /// Discovery on but no carousel items yet: clean glass only — no Uni art or resting copy.
    private func forYouRailActiveEmptySurface(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let isLoading = forYouDiscoveryToggleRefreshing || services.isForYouRefreshInFlight
        let failure = services.forYouLastPassFailure

        let title: String
        let body: String
        let accessibilityLabel: String

        if isLoading {
            title = ""
            body = "Looking for suggestions…"
            accessibilityLabel = "Looking for suggestions"
        } else if let failure {
            switch failure.kind {
            case .needsMoreSpecificFocus:
                title = "Give Uni a focus"
                body = "Add what you're looking for so For You can find relevant people or offers."
                accessibilityLabel = "\(title). \(body)"
            case .invalidRequest, .networkOrServer:
                title = "Couldn't refresh For You"
                body = failure.message
                accessibilityLabel = "\(title). \(body)"
            }
        } else {
            title = ""
            body = "Suggestions will appear here when Uni finds a match."
            accessibilityLabel = "No suggestions yet"
        }

        return forYouTallGlassCardShell(cardWidth: cardWidth, cardHeight: cardHeight) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .tint(SecretaryTheme.darkOrange)
                }

                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                        .multilineTextAlignment(.center)
                }

                Text(body)
                    .font(.system(size: title.isEmpty ? 13 : 13, weight: .medium))
                    .foregroundStyle(
                        title.isEmpty ? SecretaryTheme.darkMutedText : SecretaryTheme.darkSecondaryText
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var discoveryEmptyUniAssetAvailable: Bool {
        #if canImport(UIKit)
        UIImage(named: "DiscoveryEmptyUniSleeping") != nil
        #else
        false
        #endif
    }

    @ViewBuilder
    private func forYouRailPlaceholderSymbolFallback(railOn: Bool) -> some View {
        UnifyGlassIconDisk(
            diameter: ForYouPlaceholderMetrics.iconDiskDiameter,
            strokeOpacity: 0.88
        )
        .overlay {
            Image(systemName: railOn ? "sparkles" : "moon.stars.fill")
                .font(.system(size: ForYouPlaceholderMetrics.iconSymbolPointSize, weight: .light))
                .foregroundStyle(SecretaryTheme.darkSecondaryText.opacity(0.78))
        }
        .accessibilityHidden(true)
    }

    private func forYouRailDisplayName(for item: ExchangeModels.ForYouItem) -> String {
        let fromCard = item.displayCard?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromCard.isEmpty { return fromCard }
        return item.displayName
    }

    /// Photo-first card subtitle only (display name is separate). Profile/intro first — never commercial policy skim.
    private func forYouCardSubtitle(for item: ExchangeModels.ForYouItem) -> String {
        if let card = item.displayCard {
            if let preview = card.previewLines.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                return preview
            }
            if let subtitle = card.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                return subtitle
            }
        }
        if let about = forYouProfileAboutSummary(from: item.discoveryFactLines) {
            return about
        }
        if let headline = forYouSanitizedCardSubtitleCandidate(item.headline) {
            return headline
        }
        if let offerTitle = forYouSanitizedCardSubtitleCandidate(item.topOfferTitle) {
            return offerTitle
        }
        if let offerFromDiscovery = forYouProfileOffersSummary(from: item.discoveryFactLines) {
            return offerFromDiscovery
        }
        return "View profile details"
    }

    /// Photo-first swipe card: real profile imagery + name/intro only; actions in sheet.
    private func forYouPhotoFirstProfileCard(
        item: ExchangeModels.ForYouItem,
        cardWidth: CGFloat
    ) -> some View {
        let isLinked = item.linkedThreadID != nil
        let presentationURLs = forYouImagePresentationURLs(item)
        let heroString = presentationURLs.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrimaryImageURL = !(heroString ?? "").isEmpty
        let imageURL = heroString.flatMap { URL(string: $0) }
        let displayNameTrimmed = forYouRailDisplayName(for: item).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = displayNameTrimmed.isEmpty ? item.displayName : displayNameTrimmed
        let initials = forYouDisplayInitials(from: displayName)
        let introLine = forYouCardSubtitle(for: item)
        let cardHeight = forYouCardHeight(for: cardWidth)

        let card = ZStack(alignment: .topLeading) {
            forYouCardFullBleedImage(
                imageURL: imageURL,
                initials: initials,
                hasPrimaryImageURL: hasPrimaryImageURL,
                cardWidth: cardWidth,
                cardHeight: cardHeight
            )

            forYouCardBottomScrim(
                item: item,
                displayName: displayName,
                introLine: introLine,
                cardWidth: cardWidth
            )

            forYouDismissButton(item: item, isLinked: isLinked)
        }
        .frame(width: cardWidth, height: cardHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            forYouProfileSheetItem = item
        }

        return forYouTallGlassCardShell(cardWidth: cardWidth, cardHeight: cardHeight) {
            card
        }
        #if DEBUG
        .onAppear {
            guard item.publicSupporterPresentation?.showsGuardianCrown == true else { return }
            GuardianCrownDebugLog.log(
                "Render",
                "surface=forYouRail nodeID=\(item.nodeID) profileID=\(item.publicProfileID ?? "nil") " +
                "presentation=guardian/crown"
            )
        }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [displayName, introLine]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
        )
    }
    
    @ViewBuilder
    private func forYouCardFullBleedImage(
        imageURL: URL?,
        initials: String,
        hasPrimaryImageURL: Bool,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> some View {
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            // Blurred fill backdrop — hides letterboxing without black side bands.
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: cardHeight)
                                .blur(radius: 16)
                                .opacity(0.55)
                                .clipped()

                            // Immersive hero — full-bleed fill inside the large card.
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        }

                    case .empty:
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)

                    case .failure:
                        Color.black.opacity(0.14)

                    @unknown default:
                        Color.black.opacity(0.14)
                    }
                }
            } else {
                Color.black.opacity(0.14)
            }

            if !hasPrimaryImageURL {
                forYouMissingImageInitialsMark(initials: initials, height: cardHeight)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.00),
                    .init(color: .black.opacity(0.00), location: 0.42),
                    .init(color: .black.opacity(0.28), location: 0.68),
                    .init(color: .black.opacity(0.76), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
    }
    
    private func forYouCardBottomScrim(
        item: ExchangeModels.ForYouItem,
        displayName: String,
        introLine: String,
        cardWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if item.publicSupporterPresentation?.showsGuardianCrown == true {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
                        .accessibilityLabel("Guardian supporter")
                }
                Text(displayName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(introLine)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.38), radius: 4, x: 0, y: 1)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button {
                    forYouProfileSheetItem = item
                } label: {
                    Text("Details")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.96))
                        }
                        .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Details")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .frame(width: cardWidth, alignment: .bottomLeading)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(true)
    }


    /// Whether this discovery counterparty is in the local trusted book (`listTrustedNodes` snapshot per sheet open).
    private func isForYouItemTrusted(_ item: ExchangeModels.ForYouItem) -> Bool {
        let node = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let iid = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !node.isEmpty, forYouTrustedNodeIDsSnapshot.contains(node) { return true }
        if !iid.isEmpty, forYouTrustedNodeIDsSnapshot.contains(iid) { return true }
        return false
    }

    private func isForYouItemPending(_ item: ExchangeModels.ForYouItem) -> Bool {
        if isForYouItemTrusted(item) { return false }
        let node = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !node.isEmpty && forYouPendingNodeIDs.contains(node)
    }

    /// Loads trusted + outbound pending contact-request state from canonical Exchange stores.
    @MainActor
    private func refreshForYouRelationshipStateFromCanonicalStore() async {
        guard let source = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return
        }

        if let trustedRows = try? await services.exchangeFacade.listTrustedNodes(
            sourceNodeID: source,
            limit: 500
        ) {
            forYouTrustedNodeIDsSnapshot = Set(
                trustedRows
                    .map { $0.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        if let pendingRows = try? await services.exchangeFacade.listPendingOutgoingContactRequests(limit: 500) {
            let trusted = forYouTrustedNodeIDsSnapshot
            forYouPendingNodeIDs = Set(
                pendingRows
                    .map { $0.targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !trusted.contains($0) }
            )
        }

        #if DEBUG
        print(
            "[ForYouConnectStatus] refresh trusted=\(forYouTrustedNodeIDsSnapshot.count) " +
                "pending=\(forYouPendingNodeIDs.count) refreshID=\(refreshID)"
        )
        #endif
    }

    /// Loads trusted + outbound pending contact-request state when the For You profile sheet is shown.
    @MainActor
    private func forYouRefreshProfileRelationshipState(for item: ExchangeModels.ForYouItem) async {
        await refreshForYouRelationshipStateFromCanonicalStore()
        #if DEBUG
        let node = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: String = {
            switch ForYouConnectionToolbarProjection.resolve(
                isTrusted: isForYouItemTrusted(item),
                isPending: isForYouItemPending(item)
            ) {
            case .connected: return "connected"
            case .pending: return "pending"
            case .connect: return "connect"
            }
        }()
        print(
            "[ForYouConnectStatus] sheet node=\(node) chosen=\(status) source=canonicalStore"
        )
        #endif
    }

    @ViewBuilder
    private func forYouProfileDetailSheet(item: ExchangeModels.ForYouItem) -> some View {
        let itemID = item.id
        let presentationURLs = forYouImagePresentationURLs(item)
        let collapsedSubtitle = forYouCollapsedSubtitle(for: item)
        let sheetTopSubtitle = forYouSheetTopSubtitle(
            item: item,
            collapsedSubtitle: collapsedSubtitle
        )
        let detailSections = forYouSheetDetailSections(
            item: item,
            sheetTopSubtitle: sheetTopSubtitle
        )
        let useGroupedSections = !(detailSections?.isEmpty ?? true)
        let detailLines = useGroupedSections
            ? []
            : forYouExpandedDetailLines(item: item, collapsedSubtitle: sheetTopSubtitle)
        let isTrusted = isForYouItemTrusted(item)
        let isPending = isForYouItemPending(item)

        PublicProfileDetailSheet(
            item: item,
            imageURLs: presentationURLs,
            subtitle: sheetTopSubtitle,
            detailLines: detailLines,
            detailSections: useGroupedSections ? detailSections : nil,
            onClose: {
                forYouProfileSheetItem = nil
            },
            onOpenGallery: { presentation in
                imageGalleryPresentation = presentation
            },
            toolbarTrailing: {
                forYouProfileConnectToolbarControl(
                    item: item,
                    itemID: itemID,
                    isTrusted: isTrusted,
                    isPending: isPending
                )
            }
        )
        .task(id: item.id) {
            await forYouRefreshProfileRelationshipState(for: item)
        }
    }

    @ViewBuilder
    private func forYouProfileInfoDetailRow(line: String) -> some View {
        if let (symbol, body) = forYouInfoLineIconAndBody(line) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .frame(width: 22, alignment: .center)
                Text(body)
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(line)
                .font(.system(size: 14.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Maps known `Label: value` discovery rows to SF Symbol + body (value only). Returns `nil` to render the line as plain text.
    private func forYouInfoLineIconAndBody(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
        let head = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return nil }

        let key = head.lowercased()
        let symbol: String? = {
            switch key {
            case "region":
                return "map"
            case "open to":
                return "arrow.left.arrow.right"
            case "roles":
                return "person.3"
            case "looking for":
                return "text.magnifyingglass"
            case "about":
                return "text.alignleft"
            case "offer", "offers":
                return "tag.fill"
            case "shared themes":
                return "square.grid.2x2"
            default:
                return nil
            }
        }()

        guard let symbol else { return nil }
        guard !value.isEmpty else { return nil }
        return (symbol, value)
    }

    /// Drops Info rows that repeat the headline or collapsed intro already shown above the card.
    private func forYouInfoLineRedundantWithIntro(
        _ line: String,
        headline: String?,
        subtitle: String?
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let valueAfterColon: String? = {
            guard let idx = trimmed.firstIndex(of: ":") else { return nil }
            let v = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }()

        let intros = [headline, subtitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for intro in intros {
            if normalizeForYouLine(trimmed) == normalizeForYouLine(intro) { return true }
            if let v = valueAfterColon, normalizeForYouLine(v) == normalizeForYouLine(intro) { return true }
        }

        return false
    }

    // MARK: - For You card copy helpers (social discovery; filter directory/commerce noise)

    private func forYouCollapsedSubtitle(for item: ExchangeModels.ForYouItem) -> String? {
        if let subtitle = item.displayCard?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty {
            return subtitle
        }
        let card = forYouCardSubtitle(for: item)
        if card == "View profile details" { return nil }
        return card
    }

    /// For You Details sheet: one intro line under the title.
    private func forYouSheetTopSubtitle(
        item: ExchangeModels.ForYouItem,
        collapsedSubtitle: String?
    ) -> String? {
        if let fromCard = item.displayCard?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fromCard.isEmpty {
            return fromCard
        }
        if let headline = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headline.isEmpty {
            return headline
        }
        return collapsedSubtitle
    }

    private func forYouSheetDetailSections(
        item: ExchangeModels.ForYouItem,
        sheetTopSubtitle: String?
    ) -> [ExchangeDisplaySection]? {
        guard let raw = item.displayCard?.detailSections, !raw.isEmpty else { return nil }

        let titleName = item.displayCard?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let sections = raw.compactMap { section -> ExchangeDisplaySection? in
            var lines = section.lines
            if section.title == "Public profile" {
                lines = lines.filter { line in
                    !forYouSheetLineDuplicatesHeader(
                        line.text,
                        sheetTopSubtitle: sheetTopSubtitle,
                        titleName: titleName,
                        displayName: displayName
                    )
                }
            }
            guard !lines.isEmpty else { return nil }
            return ExchangeDisplaySection(
                title: section.title,
                sourceGroup: section.sourceGroup,
                lines: lines
            )
        }

        return sections.isEmpty ? nil : sections
    }

    private func forYouSheetLineDuplicatesHeader(
        _ lineText: String,
        sheetTopSubtitle: String?,
        titleName: String?,
        displayName: String
    ) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let headerKeys = [sheetTopSubtitle, titleName, displayName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(forYouSheetDedupKey)

        guard !headerKeys.isEmpty else { return false }

        if headerKeys.contains(forYouSheetDedupKey(trimmed)) {
            return true
        }

        if let value = forYouSheetLineValueAfterLabel(trimmed),
           headerKeys.contains(forYouSheetDedupKey(value)) {
            return true
        }

        return false
    }

    private func forYouSheetLineValueAfterLabel(_ line: String) -> String? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let value = String(line[line.index(after: colonIdx)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Case- and punctuation-insensitive key for sheet header / section dedup.
    private func forYouSheetDedupKey(_ text: String) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        return collapsed.filter { $0.isLetter || $0.isNumber }
    }

    private static let forYouCardSubtitleMaxLength = 140

    private func forYouProfileAboutSummary(from discoveryLines: [String]) -> String? {
        for raw in discoveryLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("about:") else { continue }
            if let value = forYouExtractLabeledValue(trimmed, label: "about"),
               let sanitized = forYouSanitizedCardSubtitleCandidate(value) {
                return sanitized
            }
        }
        return nil
    }

    private func forYouProfileOffersSummary(from discoveryLines: [String]) -> String? {
        for raw in discoveryLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix("offers:") || lower.hasPrefix("offer:") else { continue }
            let label = lower.hasPrefix("offers:") ? "offers" : "offer"
            if let value = forYouExtractLabeledValue(trimmed, label: label),
               let sanitized = forYouSanitizedCardSubtitleCandidate(value) {
                return sanitized
            }
        }
        return nil
    }

    private func forYouExtractLabeledValue(_ line: String, label: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let head = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard head == label.lowercased() else { return nil }
        let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func forYouSanitizedCardSubtitleCandidate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if forYouIsUnacceptableCardSubtitleText(trimmed) { return nil }
        if trimmed.count > Self.forYouCardSubtitleMaxLength {
            let end = trimmed.index(trimmed.startIndex, offsetBy: Self.forYouCardSubtitleMaxLength)
            return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return trimmed
    }

    private func forYouIsUnacceptableCardSubtitleText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if forYouIsSystemLikePublicFactLine(trimmed) { return true }
        if forYouIsLogLikeMatchSummary(trimmed) { return true }

        let lower = trimmed.lowercased()
        let blockedPhrases = [
            "unify node",
            "seller surface",
            "public coordination surface",
            "seller-side discovery",
            "public coordination",
            "retrieval document",
            "public profile document",
            "profile-node",
            "node-owned",
            "not provided",
            "coordination surface"
        ]
        if blockedPhrases.contains(where: { lower.contains($0) }) { return true }
        if lower.hasPrefix("about:") && forYouExtractLabeledValue(trimmed, label: "about") == nil { return true }

        if lower.contains("node ") && (lower.contains("profile") || lower.contains("unify")) { return true }
        if lower.hasPrefix("node-") || lower.contains("node-") { return true }
        if lower.contains("profile-node") { return true }

        if forYouLooksLikeNodeIDFragment(trimmed) { return true }
        return false
    }

    private func forYouLooksLikeNodeIDFragment(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 24, t.filter({ $0 == "-" }).count >= 3 {
            let hexish = t.filter { $0.isHexDigit || $0 == "-" }
            if Double(hexish.count) / Double(max(t.count, 1)) > 0.85 { return true }
        }
        if t.lowercased().hasPrefix("unify node") { return true }
        let uuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-"#
        if t.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }

    private func forYouFirstDiscoveryFactLine(_ lines: [String]) -> String? {
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if forYouIsSystemLikePublicFactLine(trimmed) { continue }
            if forYouReadsLikeDiscoveryLine(trimmed) { return trimmed }
        }
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !forYouIsSystemLikePublicFactLine(trimmed) { return trimmed }
        }
        return nil
    }

    private func forYouReadsLikeDiscoveryLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if let colon = line.firstIndex(of: ":") {
            let head = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let friendlyHeads = [
                "about", "open to", "interests", "hobbies", "roles", "bio", "summary", "looking for",
                "offers", "industries/categories", "industries", "categories", "region", "shared themes"
            ]
            if friendlyHeads.contains(where: { head.contains($0) }) { return true }
        }
        let keywords = [
            "about ", " open to", "interest", "hobby", "passion", "enjoy ", "looking for",
            "offer", "industry", "category", "region", "theme"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    private func forYouIsSystemLikePublicFactLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()

        if forYouIsAutomationOrPolicyFactLine(trimmed, lower: lower) { return true }

        if lower.contains("unify node") { return true }
        if lower.contains("seller surface") { return true }
        if lower.contains("public coordination surface") { return true }
        if lower.contains("seller-side discovery") { return true }
        if lower.contains("public coordination") && lower.contains("surface") { return true }
        if lower.contains("profile-node") { return true }
        if lower.hasPrefix("shared themes") { return true }
        if lower.hasPrefix("industries/categories") { return true }
        if lower.hasPrefix("industries:") { return true }
        if lower.hasPrefix("categories:") { return true }
        if lower.hasPrefix("tags:") { return true }
        if lower.contains("fulfillment") { return true }
        if lower.contains("commercial facts") { return true }
        if lower.contains("pricingmode") || lower.contains("commitmentmode") { return true }
        if lower.contains("pricing mode") || lower.contains("commitment mode") { return true }
        if lower.hasPrefix("price") || lower.contains("price:") { return true }
        if lower.contains("retrieval") || lower.contains("fit score") || lower.contains("score:") { return true }
        if lower.contains("directory") || lower.contains("discovery source") { return true }
        if lower.contains("standing intent") { return true }
        if lower.contains("query class") { return true }
        if lower.contains("surface preference") { return true }
        if lower.contains("schema") { return true }
        if lower.contains("route requirement") || lower.contains("routerequirement") { return true }
        if lower.contains("directcontactallowedonly") { return true }
        if lower.contains("federationcapable") || lower.contains("federation capable") { return true }
        if lower.contains("boundary") || lower.contains("posture") { return true }
        if lower.contains("boundary:") || lower.contains("posture:") { return true }
        if lower.contains("role:") || lower.contains("state:") { return true }
        if lower.contains("qualification:") || lower.contains("qualification") { return true }
        if lower.contains("deterministic") { return true }
        if lower.contains("pass 1") || lower.contains("pass 2") || lower.contains("pass 3") { return true }
        if lower.contains("matched because") { return true }
        if lower.contains("remote-friendly") && lower.contains("onsite") { return true }
        return false
    }

    /// Commercial automation / policy skim lines (not user-facing intro copy).
    private func forYouIsAutomationOrPolicyFactLine(_ line: String, lower: String) -> Bool {
        if lower.contains("faq auto-answer") { return true }
        if lower.contains("auto-answer") || lower.contains("auto answer") { return true }
        if lower.contains("autoanswer") { return true }
        if lower.contains("can answer faqs") { return true }
        if lower.contains("autoanswerpolicy") || lower.contains("faqautoanswerallowed") { return true }

        if let colon = line.firstIndex(of: ":") {
            let head = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let automationHeads = [
                "faq auto-answer",
                "required buyer input",
                "policy",
                "pricing mode",
                "commitment mode",
                "fulfillment",
                "commercial facts"
            ]
            if automationHeads.contains(where: { head == $0 || head.hasPrefix($0) }) { return true }
            if head == "faq" || head.hasPrefix("faq ") { return true }
        }

        if lower.hasPrefix("required buyer input") || lower.contains("required buyer input:") { return true }
        if lower.contains("buyer input:") { return true }
        if lower.contains("answerability") { return true }
        if lower.hasPrefix("policy:") { return true }
        return false
    }

    private func forYouIsLogLikeMatchSummary(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("pass ") || lower.contains("pass:") { return true }
        if lower.contains("score") && lower.contains("rank") { return true }
        if lower.contains("standing intent") { return true }
        if lower.contains("query class") { return true }
        if lower.contains("surface preference") { return true }
        if lower.contains("schema") { return true }
        if lower.contains("route requirement") || lower.contains("routerequirement") { return true }
        if lower.contains("directcontactallowedonly") { return true }
        if lower.contains("federationcapable") || lower.contains("federation capable") { return true }
        if lower.contains("fit score") || lower.contains("score:") { return true }
        if lower.contains("boundary:") || lower.contains("posture:") { return true }
        if lower.contains("role:") || lower.contains("state:") { return true }
        if lower.contains("qualification:") { return true }
        if lower.contains("commercial facts") { return true }
        if lower.contains("deterministic") { return true }
        if lower.contains("pass 1") || lower.contains("pass 2") || lower.contains("pass 3") { return true }
        if lower.contains("embedding") || lower.contains("retrieval") { return true }
        return false
    }

    // MARK: - For You expanded “Details” (user-facing reach / region / offer; no system echo)

    private func normalizeForYouLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.lowercased()
    }

    private func forYouOfferComparableValue(_ text: String) -> String {
        var t = normalizeForYouLine(text)
        for prefix in ["offers:", "offer:"] {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
                return parts
            }
        }
        return t
    }

    private func forYouIsDuplicateLine(_ line: String, against other: String?) -> Bool {
        guard let other, !other.isEmpty else { return false }
        if normalizeForYouLine(line) == normalizeForYouLine(other) { return true }
        return forYouOfferComparableValue(line) == forYouOfferComparableValue(other)
    }

    private func forYouIsDuplicateLine(
        _ line: String,
        collapsedSubtitle: String?,
        topOfferTitle: String?
    ) -> Bool {
        if forYouIsDuplicateLine(line, against: collapsedSubtitle) { return true }
        if forYouIsDuplicateLine(line, against: topOfferTitle) { return true }
        return false
    }

    private func forYouIsInternalDiscoveryLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()

        if lower.contains("remote federation directory match") { return true }
        if lower.contains("directory match") { return true }
        if lower.contains("federation directory") && lower.contains("match") { return true }
        if lower.contains("retrieval") { return true }
        if lower.contains("fit score") { return true }
        if lower.contains("matched because") { return true }
        if lower == "commercial facts" || lower.hasPrefix("commercial facts:") { return true }
        if lower.contains("embedding") { return true }
        if lower.contains("query class") { return true }
        if lower.contains("surface preference") { return true }
        if lower.contains("schema") { return true }
        if lower.contains("deterministic") { return true }
        if lower.contains("score:") && lower.contains("fit") { return true }
        if lower.contains("routerequirement") || lower.contains("route requirement") { return true }
        if lower.contains("discovery source") { return true }
        if forYouIsLogLikeMatchSummary(trimmed) { return true }
        if lower.hasPrefix("industries/categories:") { return true }
        if lower.hasPrefix("shared themes:") { return true }
        if lower.hasPrefix("tags:") { return true }
        if forYouIsSystemLikePublicFactLine(trimmed) { return true }
        return false
    }

    private func forYouFulfillmentModalitySuffix(from item: ExchangeModels.ForYouItem) -> String? {
        for raw in item.publicFactLines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = t.lowercased()
            guard lower.hasPrefix("fulfillment:") else { continue }
            if lower.contains("remote-friendly") { return "remote-friendly" }
            if lower.contains("onsite-leaning") { return "onsite-leaning" }
        }
        return nil
    }

    private func forYouFormattedRegionLine(item: ExchangeModels.ForYouItem, collapsedSubtitle: String?) -> String? {
        var base: String?
        for raw in item.discoveryFactLines + item.publicFactLines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.lowercased().hasPrefix("region:") else { continue }
            if forYouIsInternalDiscoveryLine(t) { continue }
            base = t
            break
        }

        let modality = forYouFulfillmentModalitySuffix(from: item)
        let merged: String? = {
            guard let b = base else {
                return modality.map { "Region: \($0)" }
            }
            guard let m = modality, !b.lowercased().contains(m) else { return b }
            return "\(b) / \(m)"
        }()

        guard let line = merged else { return nil }
        if forYouIsDuplicateLine(line, against: collapsedSubtitle) { return nil }
        return line
    }

    private func forYouFormattedOfferLine(item: ExchangeModels.ForYouItem, collapsedSubtitle: String?) -> String? {
        guard let title = item.topOfferTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        let line = "Offer: \(title)"
        if forYouIsDuplicateLine(line, against: collapsedSubtitle) { return nil }
        return line
    }

    private func forYouFormattedAboutLine(item: ExchangeModels.ForYouItem, collapsedSubtitle: String?) -> String? {
        for raw in item.discoveryFactLines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.lowercased().hasPrefix("about:") else { continue }
            if forYouIsInternalDiscoveryLine(t) { continue }
            if forYouIsDuplicateLine(t, collapsedSubtitle: collapsedSubtitle, topOfferTitle: item.topOfferTitle) {
                continue
            }
            return t
        }

        if let h = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            if forYouIsInternalDiscoveryLine(h) { return nil }
            if forYouIsDuplicateLine(h, collapsedSubtitle: collapsedSubtitle, topOfferTitle: item.topOfferTitle) {
                return nil
            }
            return h
        }
        return nil
    }

    private func forYouIsCommercialUserFacingDetailLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("region:") { return false }
        if lower.hasPrefix("about:") { return false }
        if lower.hasPrefix("offers:") { return false }
        if lower.hasPrefix("offer:") { return false }
        if lower.hasPrefix("fulfillment:") { return false }

        let signals = [
            "service area", "service region", "located", "location", "$", "€", "£",
            "availability", "available", "weekday", "weekend", "ships", "shipping",
            "delivery", "pickup", "lead time", "turnaround", "/hr", " per ",
            "price", "pricing", "remote", "on-site", "onsite", "in-person"
        ]
        return signals.contains { lower.contains($0) }
    }

    private func forYouLinesAreNearDuplicate(_ a: String, _ b: String) -> Bool {
        let na = normalizeForYouLine(a)
        let nb = normalizeForYouLine(b)
        if na == nb { return true }
        guard na.count >= 14, nb.count >= 14 else { return false }
        return na.contains(nb) || nb.contains(na)
    }

    private func forYouDedupedOrderedExpandedLines(
        _ candidates: [String],
        collapsedSubtitle: String?,
        item: ExchangeModels.ForYouItem,
        maxLines: Int
    ) -> [String] {
        let reachOpen = "Reach: Open to contact"
        let reachIntro = "Reach: Introduction preferred"

        var out: [String] = []
        var seenNormalized = Set<String>()

        for raw in candidates {
            guard out.count < maxLines else { break }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isReachLine = trimmed == reachOpen || trimmed == reachIntro
            if !isReachLine {
                if forYouIsInternalDiscoveryLine(trimmed) { continue }
                if forYouIsDuplicateLine(trimmed, collapsedSubtitle: collapsedSubtitle, topOfferTitle: item.topOfferTitle) {
                    continue
                }
            }

            let n = normalizeForYouLine(trimmed)
            if seenNormalized.contains(n) { continue }
            if out.contains(where: { forYouLinesAreNearDuplicate($0, trimmed) }) { continue }

            seenNormalized.insert(n)
            out.append(trimmed)
        }

        return out
    }

    private func forYouTierProfileSocialLines(
        item: ExchangeModels.ForYouItem,
        collapsedSubtitle: String?
    ) -> [String] {
        var rows: [String] = []
        for raw in item.discoveryFactLines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if forYouIsInternalDiscoveryLine(t) { continue }
            if forYouIsCommercialUserFacingDetailLine(t) { continue }
            let lower = t.lowercased()
            if forYouReadsLikeDiscoveryLine(t)
                || lower.hasPrefix("about:")
                || lower.hasPrefix("shared themes")
                || lower.hasPrefix("open to") {
                rows.append(t)
            }
        }

        if let about = forYouFormattedAboutLine(item: item, collapsedSubtitle: collapsedSubtitle) {
            rows.append(about)
        }

        return rows
    }

    private func forYouAdditionalCommercialLines(
        item: ExchangeModels.ForYouItem,
        collapsedSubtitle: String?,
        maxCount: Int
    ) -> [String] {
        var out: [String] = []
        for raw in item.publicFactLines + item.discoveryFactLines {
            guard out.count < maxCount else { break }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if forYouIsInternalDiscoveryLine(t) { continue }
            guard forYouIsCommercialUserFacingDetailLine(t) else { continue }
            if forYouIsDuplicateLine(t, collapsedSubtitle: collapsedSubtitle, topOfferTitle: item.topOfferTitle) {
                continue
            }
            out.append(t)
        }
        return out
    }

    private func forYouBuyerHintLines(item: ExchangeModels.ForYouItem) -> [String] {
        item.suggestedBuyerInputHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { hint in
                let lower = hint.lowercased()
                if lower.hasPrefix("need ") || lower.hasPrefix("bring ") || lower.hasPrefix("please ") {
                    return hint
                }
                return "Need from you: \(hint)"
            }
    }

    private func forYouContactDetailLines(item: ExchangeModels.ForYouItem) -> [String] {
        guard let contact = item.publicOfferContactInfo?.normalized(), !contact.isEmpty else {
            return []
        }

        var lines: [String] = []
        if let preferred = contact.preferredContactMethod?.rawValue {
            lines.append("Preferred: \(preferred.capitalized)")
        }
        if let email = contact.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            lines.append("Email: \(email)")
        }
        if let phone = contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            lines.append("Phone: \(phone)")
        }
        if let website = contact.website?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty {
            lines.append("Website: \(website)")
        }
        if let area = contact.serviceAddressOrArea?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty {
            lines.append("Service area: \(area)")
        }
        if let note = contact.availabilityNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            lines.append("Availability: \(note)")
        }
        return lines
    }

    private func forYouExpandedDetailLines(
        item: ExchangeModels.ForYouItem,
        collapsedSubtitle: String?
    ) -> [String] {
        var tierContactReach: [String] = []
        tierContactReach.append(contentsOf: forYouContactDetailLines(item: item))
        if let region = forYouFormattedRegionLine(item: item, collapsedSubtitle: collapsedSubtitle) {
            tierContactReach.append(region)
        }

        let tierProfileSocial = forYouTierProfileSocialLines(item: item, collapsedSubtitle: collapsedSubtitle)

        var tierOfferCommercial: [String] = []
        if let offer = forYouFormattedOfferLine(item: item, collapsedSubtitle: collapsedSubtitle) {
            tierOfferCommercial.append(offer)
        }
        tierOfferCommercial.append(
            contentsOf: forYouAdditionalCommercialLines(
                item: item,
                collapsedSubtitle: collapsedSubtitle,
                maxCount: 4
            )
        )

        let tierHints = forYouBuyerHintLines(item: item)

        let merged = tierContactReach + tierProfileSocial + tierOfferCommercial + tierHints
        let deduped = forYouDedupedOrderedExpandedLines(
            merged,
            collapsedSubtitle: collapsedSubtitle,
            item: item,
            maxLines: 10
        )
        let headlineTrimmed = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = deduped.filter { line in
            !forYouInfoLineRedundantWithIntro(line, headline: headlineTrimmed, subtitle: collapsedSubtitle)
        }
        return ExchangeProviderDetailsLegacyLineGate.filterDetailsFallbackLines(
            filtered,
            source: "forYouExpandedDetailLines"
        )
    }

    private func forYouDisplayInitials(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        if parts.count >= 2 {
            let a = parts[0].prefix(1)
            let b = parts[1].prefix(1)
            return "\(a)\(b)".uppercased()
        }
        let single = parts[0]
        if single.count >= 2 { return String(single.prefix(2)).uppercased() }
        return String(single.prefix(1)).uppercased()
    }

    /// Sends a friend/contact request (same path as Chat tab “Send request”), without creating a local trust edge.
    @MainActor
    private func forYouSendContactRequest(for item: ExchangeModels.ForYouItem) async {
        let id = item.id
        guard !forYouConnectInFlightIDs.contains(id) else { return }
        forYouConnectLastError = nil
        forYouConnectInFlightIDs.insert(id)
        defer { forYouConnectInFlightIDs.remove(id) }

        guard let sourceNodeID = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceNodeID.isEmpty else {
            forYouConnectLastError = "Your Exchange node isn’t ready yet."
            return
        }

        let targetNodeID = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetNodeID.isEmpty else {
            forYouConnectLastError = "This card is missing a node id."
            return
        }

        let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await services.exchangeFacade.sendContactRequestToNode(
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                displayNameOverride: displayName.isEmpty ? nil : displayName,
                note: nil
            )
            await refreshForYouRelationshipStateFromCanonicalStore()
            forYouConnectLastError = nil
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: [
                    "secretaryRefreshReason": ExchangeContactRelationshipRefreshNotification.relationshipChangedSecretaryRefreshReason,
                    "reason": "forYouConnectSent"
                ]
            )
        } catch {
            forYouConnectLastError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "ForYouConnectSend"
            )
        }
    }

    private func forYouImagePresentationURLs(_ item: ExchangeModels.ForYouItem) -> [String] {
        let maxCount = ExchangeOffer.maxPublicOfferImageCount
        var ordered: [String] = []
        var seenLowercased = Set<String>()

        func appendUnique(_ raw: String) {
            guard ordered.count < maxCount else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seenLowercased.insert(key).inserted else { return }
            ordered.append(trimmed)
        }

        if let card = item.displayCard {
            if let primary = card.imageURL {
                appendUnique(primary)
            }
            for url in card.galleryImageURLs {
                appendUnique(url)
            }
            if !ordered.isEmpty {
                return ordered
            }
        }

        if let primary = item.primaryImageURL {
            appendUnique(primary)
        }
        for url in item.surfacedOfferImageURLs {
            appendUnique(url)
        }
        return ordered
    }

    /// Friend/contact relationship action in the For You Details sheet navigation bar.
    /// Thread linkage (`linkedThreadID`) is intentionally excluded — use card tap for existing threads.
    @ViewBuilder
    private func forYouProfileConnectToolbarControl(
        item: ExchangeModels.ForYouItem,
        itemID: String,
        isTrusted: Bool,
        isPending: Bool
    ) -> some View {
        switch ForYouConnectionToolbarProjection.resolve(isTrusted: isTrusted, isPending: isPending) {
        case .connected:
            Text("Connected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .accessibilityAddTraits(.isStaticText)
        case .pending:
            Text("Pending")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .accessibilityAddTraits(.isStaticText)
        case .connect:
            Button {
                Task { @MainActor in
                    await forYouSendContactRequest(for: item)
                }
            } label: {
                Group {
                    if forYouConnectInFlightIDs.contains(itemID) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                    } else {
                        Text("Connect")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(
                    forYouConnectInFlightIDs.contains(itemID)
                        ? SecretaryTheme.darkMutedText
                        : SecretaryTheme.darkOrange
                )
            }
            .buttonStyle(.plain)
            .disabled(forYouConnectInFlightIDs.contains(itemID))
            .accessibilityLabel("Send contact request to this profile")
        }
    }

    @ViewBuilder
    private func forYouDismissButton(item: ExchangeModels.ForYouItem, isLinked: Bool) -> some View {
        if isLinked {
            EmptyView()
        } else {
            Button {
                services.dismissForYouItem(nodeID: item.nodeID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.26))
                    )
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    /// Low-contrast mark when there is no `primaryImageURL` (keeps the gradient card from reading as empty).
    @ViewBuilder
    private func forYouMissingImageInitialsMark(initials: String, height: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.11))
                .frame(width: 112, height: 112)

            if initials.isEmpty {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.3))
            } else {
                Text(initials)
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .allowsHitTesting(false)
    }

    private var briefingOpportunityGradient: some View {
        LinearGradient(
            colors: [
                SecretaryTheme.darkSurfaceStrong.opacity(0.95),
                SecretaryTheme.darkOrange.opacity(0.18),
                SecretaryTheme.darkBackground.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var priorityThreadsForBoard: [ProjectedThread] {
        var rows: [ProjectedThread] = []
        rows.append(contentsOf: pendingProjected)
        rows.append(contentsOf: recoveryProjected)
        rows.append(contentsOf: searchProjected)
        rows.append(contentsOf: activeProjected)

        var seen = Set<ExchangeThread.ID>()
        var result: [ProjectedThread] = []

        for row in rows {
            guard !seen.contains(row.id) else { continue }
            seen.insert(row.id)
            result.append(row)
        }

        return Array(
            result
                .sorted { lhs, rhs in
                    if lhs.id == preferredThreadID && rhs.id != preferredThreadID { return true }
                    if rhs.id == preferredThreadID && lhs.id != preferredThreadID { return false }

                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }

                    return dashboardStripBucketRank(lhs.bucket) < dashboardStripBucketRank(rhs.bucket)
                }
                .prefix(5)
        )
    }

    private func dashboardStripBucketRank(_ bucket: SecretaryProjectionEngine.Bucket) -> Int {
        switch bucket {
        case .pending: return 0
        case .searchResult: return 1
        case .active: return 2
        case .recovery: return 3
        case .trusted: return 4
        case .none: return 5
        }
    }

    /// Latest submitted search for the discovery strip (not priority/current-work queue).
    private var currentSearchStripProjectedRow: ProjectedThread? {
        projectedSearchStripRow(
            from: threadItems,
            preferPreferredWhenEligible: services.localCurrentSearchStripItem != nil
        )
    }

    /// Immediate submit override, then snapshot-backed picker row.
    private var effectiveCurrentSearchStripRow: ProjectedThread? {
        if let override = services.localCurrentSearchStripItem {
            let matchesPreferred = preferredThreadID.map { override.threadID == $0 } ?? true
            if matchesPreferred {
                return projectedSearchStripRow(from: [override], preferPreferredWhenEligible: false)
            }
        }
        return currentSearchStripProjectedRow
    }

    private func projectedSearchStripRow(
        from items: [ExchangeModels.InboxItem],
        preferPreferredWhenEligible: Bool
    ) -> ProjectedThread? {
        guard let item = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            preferredThreadID: preferredThreadID,
            surface: "dashboardStrip",
            preferPreferredWhenEligible: preferPreferredWhenEligible
        ) else {
            return nil
        }

        let bucket = SecretaryProjectionEngine.bucket(
            for: item,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            preferredThreadID: preferredThreadID
        )

        return ProjectedThread(item: item, bucket: bucket)
    }

    private var shouldShowCurrentWorkLoader: Bool {
        !hasLoadedDeskOnce && isDeskLoading
    }

    /// Keep hero progress until desk snapshot includes the just-submitted preferred thread.
    private var shouldKeepDiscoveryHeroProgressForSubmitHandoff: Bool {
        if let override = services.localCurrentSearchStripItem,
           preferredThreadID.map({ override.threadID == $0 }) ?? true {
            return false
        }
        guard let progress = services.discoveryHeroProgress, progress.isActive else { return false }
        guard let submittedID = preferredThreadID else { return true }
        let snapshotHasThread = threadItems.contains { $0.threadID == submittedID }
        #if DEBUG
        print(
            "[RecentSearchTrace][handoff] discoveryHeroActive=true " +
            "snapshotHasSubmittedThread=\(snapshotHasThread) submittedThreadID=\(submittedID.uuidString)"
        )
        #endif
        return !snapshotHasThread
    }

    /// Same visible thread status as list/detail (``SecretaryProjectionEngine.visibleThreadStatus``).
    private func workTileVisibleStatus(
        for item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket
    ) -> SecretaryProjectionEngine.ExchangeVisibleThreadStatus {
        SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: kind,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        )
    }

    private func workTileToneStyle(
        _ tone: SecretaryProjectionEngine.ExchangeVisibleThreadStatusTone
    ) -> SecretaryStateChip.Style {
        switch tone {
        case .neutral: return .neutral
        case .warning: return .warning
        case .blocked: return .blocked
        case .success: return .success
        case .active: return .active
        }
    }

    /// Discovery-only status tint: grey by default, orange only for attention-bearing tones.
    private func discoveryStatusLabelColor(
        for tone: SecretaryProjectionEngine.ExchangeVisibleThreadStatusTone
    ) -> Color {
        switch tone {
        case .warning, .blocked:
            SecretaryTheme.darkOrange
        case .neutral, .active, .success:
            SecretaryTheme.darkSecondaryText
        }
    }

    private func workTileCTA(_ kind: SecretaryProjectionEngine.Bucket) -> String {
        switch kind {
        case .pending:
            return "Review"
        case .recovery:
            return "Recover"
        case .searchResult, .active, .trusted, .none:
            return "Open"
        }
    }

    private func workTileStatusLine(
        for item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket
    ) -> String {
        let merged = SecretaryProjectionEngine.displayExchangeCardSubtitlePreferringVisibleStatus(
            for: item,
            bucket: kind,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            surface: "home"
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        if !merged.isEmpty {
            return merged
        }

        switch kind {
        case .pending:
            return SecretaryProjectionEngine.pendingReason(for: item)
        case .recovery:
            return SecretaryProjectionEngine.failureWhatHappened(for: item)
        case .searchResult:
            return SecretaryProjectionEngine.searchResultPrimaryLine(for: item)
        case .active, .trusted:
            return threadActivityStatusLine(for: item)
        case .none:
            return heroCurrentStateLine
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func activeFeedRow(_ feedItem: ActiveFeedItem) -> some View {
        switch feedItem {
        case .thread(let row):
            threadActivityRow(row.item)
        case .inbound(let item):
            inboundActivityRow(item)
        }
    }

    private func threadActivityRow(_ item: ExchangeModels.InboxItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            SecretaryPhotoOrb(
                initials: initials(from: heroRequestTitle(for: item)),
                systemImage: avatarIcon(for: item),
                style: SecretaryProjectionEngine.isWaiting(item) ? .warning : .active,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(heroRequestTitle(for: item))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(1)

                Text(threadActivityStatusLine(for: item))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Text(SecretaryRelativeTime.string(from: item.updatedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
        }
        .padding(.horizontal, SecretaryTheme.Layout.cardSpacing + 2)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenThread(item.threadID)
        }
    }

    private func threadActivityStatusLine(for item: ExchangeModels.InboxItem) -> String {
        let movement = threadCurrentStateLine(for: item)
        let boundary = SecretaryProjectionEngine.boundaryLine(for: item)
        if boundary.isEmpty { return movement }
        return "\(movement) · \(boundary)"
    }

    private func inboundActivityRow(_ item: ExchangeInboxItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            SecretaryPhotoOrb(
                initials: initials(from: inboundTitle(for: item)),
                systemImage: nil,
                style: inboundBadgeStyle(for: item),
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(inboundTitle(for: item))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(1)

                Text(inboundCombinedStatusLine(for: item))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Text(SecretaryRelativeTime.string(from: item.updatedAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .padding(.horizontal, SecretaryTheme.Layout.cardSpacing + 2)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if let threadID = item.threadID {
                onOpenThread(threadID)
            } else {
                onOpenApprovals()
            }
        }
    }

    private func inboundCombinedStatusLine(for item: ExchangeInboxItem) -> String {
        let badge = inboundBadge(for: item)
        let summary = inboundSummary(for: item)

        if let secondary = inboundSecondaryLine(for: item), !secondary.isEmpty {
            return "\(badge) · \(summary) · \(secondary)"
        }

        return "\(badge) · \(summary)"
    }

    private func threadCurrentStateLine(for item: ExchangeModels.InboxItem) -> String {
        if let trace = item.workTrace {
            if let active = trace.activeStep {
                return compactSentence(
                    title: active.title,
                    detail: SecretaryProjectionEngine.nonEmpty(active.detail),
                    fallback: SecretaryProjectionEngine.activityLatestMovement(for: item)
                )
            }

            if let latest = trace.latestStep {
                return compactSentence(
                    title: latest.title,
                    detail: SecretaryProjectionEngine.nonEmpty(latest.detail),
                    fallback: SecretaryProjectionEngine.activityLatestMovement(for: item)
                )
            }
        }

        return SecretaryProjectionEngine.activityLatestMovement(for: item)
    }

    // MARK: - Data loading

    @MainActor
    private func pullToRefreshSecretaryDesk() async {
        #if DEBUG
        print("[SecretaryDashboardView] manual federation sync begin")
        #endif

        await services.syncFederationInboxNow(
            requestDeskRefreshAfter: false,
            recordAttentionDigests: false
        )

        #if DEBUG
        print("[SecretaryDashboardView] manual federation sync end → desk snapshot refresh")
        #endif

        services.refreshSecretaryDeskSnapshot(
            reason: "dashboardPullToRefresh",
            force: true,
            preferredThreadID: preferredThreadID
        )
    }

    @MainActor
    private func scheduleApplyDeskSnapshot(generation: UInt64?) {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Dashboard active=false skip=applyDeskSnapshot " +
                "reason=hiddenRetainedMount generation=\(generation ?? 0)"
            )
            #endif
            return
        }

        guard let generation else {
            if !hasLoadedDeskOnce {
                isDeskLoading = true
            }
            return
        }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Dashboard active=true source=snapshot " +
            "generation=\(generation)"
        )
        #endif

        deskSnapshotApplyTask?.cancel()
        deskSnapshotApplyTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let snapshot = services.secretaryDeskSnapshot,
                  snapshot.generation == generation else { return }
            applyDeskSnapshot(snapshot)
        }
    }

    @MainActor
    private func applyDeskSnapshot(_ snapshot: SecretaryDeskSnapshot) {
        guard snapshot.generation != appliedDeskSnapshotGeneration else { return }

        let orderedThreads = SecretaryDeskSnapshotBuilder.orderThreads(
            snapshot.threadItems,
            preferredThreadID: preferredThreadID
        )

        let projection = buildProjectionCaches(
            threads: orderedThreads,
            inbox: snapshot.visibleInboxItems,
            approvals: snapshot.pendingApprovals,
            preferredThreadID: preferredThreadID
        )

        withTransaction(Transaction(animation: nil)) {
            threadItems = orderedThreads
            inboxItems = snapshot.visibleInboxItems
            pendingApprovals = snapshot.pendingApprovals

            projectedThreadsCache = projection.projectedThreads
            pendingProjectedCache = projection.pendingProjected
            searchProjectedCache = projection.searchProjected
            activeProjectedCache = projection.activeProjected
            trustedProjectedCache = projection.trustedProjected
            recoveryProjectedCache = projection.recoveryProjected
            visibleInboxItemsCache = projection.visibleInboxItems
            activeFeedItemsCache = projection.activeFeedItems

            appliedDeskSnapshotGeneration = snapshot.generation
            hasLoadedDeskOnce = true
            isDeskLoading = false
        }

        services.clearLocalCurrentSearchStripItemIfReconciled(with: orderedThreads)

        #if DEBUG
        print(
            "[SecretaryDashboardView] applyDeskSnapshot generation=\(snapshot.generation) " +
            "threads=\(orderedThreads.count) inbox=\(snapshot.visibleInboxItems.count) " +
            "pending=\(snapshot.pendingApprovals.count)"
        )
        logDashboardCurrentSearchSelector(from: orderedThreads)
        #endif
    }

    #if DEBUG
    private func logDashboardCurrentSearchSelector(from items: [ExchangeModels.InboxItem]) {
        let pendingIDs = pendingApprovalThreadIDs
        let selected = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingIDs,
            preferredThreadID: preferredThreadID,
            surface: "dashboardStrip"
        )
        let priorityPick = SecretarySearchResultProjection.pickCurrentSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingIDs,
            preferredThreadID: preferredThreadID
        )
        print(
            "[DashboardCurrentSearchSelector] latestSearch=\(selected?.threadID.uuidString ?? "nil") " +
            "priorityPick=\(priorityPick?.threadID.uuidString ?? "nil") " +
            "state=\(selected.map { String(describing: $0.state) } ?? "nil") " +
            "source=latestSearchSelector pendingCount=\(pendingIDs.count) " +
            "preferred=\(preferredThreadID?.uuidString ?? "nil") itemCount=\(items.count)"
        )
        print(
            "[CurrentSearchConsistency] dashboardLatest=\(selected?.threadID.uuidString ?? "nil") " +
            "priority=\(priorityPick?.threadID.uuidString ?? "nil") " +
            "match=\(selected?.threadID == priorityPick?.threadID)"
        )
    }
    #endif

    private struct ProjectionCaches {
        let projectedThreads: [ProjectedThread]
        let pendingProjected: [ProjectedThread]
        let searchProjected: [ProjectedThread]
        let activeProjected: [ProjectedThread]
        let trustedProjected: [ProjectedThread]
        let recoveryProjected: [ProjectedThread]
        let visibleInboxItems: [ExchangeInboxItem]
        let activeFeedItems: [ActiveFeedItem]
    }

    private func buildProjectionCaches(
        threads: [ExchangeModels.InboxItem],
        inbox: [ExchangeInboxItem],
        approvals: [ExchangeModels.PendingApproval],
        preferredThreadID: ExchangeThread.ID?
    ) -> ProjectionCaches {
        let pendingApprovalThreadIDs = Set(approvals.map(\.threadID))

        let projectedThreads = threads
            .map { item in
                ProjectedThread(
                    item: item,
                    bucket: SecretaryProjectionEngine.bucket(
                        for: item,
                        pendingApprovalThreadIDs: pendingApprovalThreadIDs,
                        preferredThreadID: preferredThreadID
                    )
                )
            }
            .filter { $0.bucket != .none }
            .sorted { lhs, rhs in
                if lhs.id == preferredThreadID && rhs.id != preferredThreadID { return true }
                if rhs.id == preferredThreadID && lhs.id != preferredThreadID { return false }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let pendingProjected = projectedThreads.filter { $0.bucket == .pending }
        let searchProjected = projectedThreads.filter { $0.bucket == .searchResult }
        let activeProjected = projectedThreads.filter { $0.bucket == .active }
        let trustedProjected = projectedThreads.filter { $0.bucket == .trusted }
        let recoveryProjected = projectedThreads.filter { $0.bucket == .recovery }

        let visibleInboxItems = inbox
            .filter {
                switch $0.processingState {
                case .received, .deferred, .awaitingOrderingGapResolution:
                    return true
                case .duplicateIgnored, .reconciledIntoThread, .rejected, .archived:
                    return false
                }
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }

        let activeFeedItems = (activeProjected.map(ActiveFeedItem.thread) + visibleInboxItems.map(ActiveFeedItem.inbound))
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }

        return ProjectionCaches(
            projectedThreads: projectedThreads,
            pendingProjected: pendingProjected,
            searchProjected: searchProjected,
            activeProjected: activeProjected,
            trustedProjected: trustedProjected,
            recoveryProjected: recoveryProjected,
            visibleInboxItems: visibleInboxItems,
            activeFeedItems: activeFeedItems
        )
    }

    // MARK: - Projection

    private var projectedThreads: [ProjectedThread] {
        projectedThreadsCache
    }

    private var preferredProjected: ProjectedThread? {
        guard let preferredThreadID else { return nil }
        return projectedThreadsCache.first(where: { $0.id == preferredThreadID })
    }

    private var runningTraceProjected: ProjectedThread? {
        projectedThreadsCache.first { row in
            guard let trace = row.item.workTrace else { return false }
            return trace.status == .running || trace.status == .blocked
        }
    }

    private var currentFocusItem: ExchangeModels.InboxItem? {
        if let item = pendingProjectedCache.first?.item { return item }
        if let item = recoveryProjectedCache.first?.item { return item }
        if let item = preferredProjected?.item,
           SecretaryProjectionEngine.isOperationalThreadOpenAllowed(item) {
            return item
        }
        if let item = preferredProjected?.item { return item }
        if let item = searchProjectedCache.first?.item { return item }
        if let item = activeProjectedCache.first?.item { return item }
        if let item = trustedProjectedCache.first?.item { return item }

        return projectedThreadsCache.first?.item
    }

    private var pendingProjected: [ProjectedThread] {
        pendingProjectedCache
    }

    private var searchProjected: [ProjectedThread] {
        searchProjectedCache
    }

    private var activeProjected: [ProjectedThread] {
        activeProjectedCache
    }

    private var recoveryProjected: [ProjectedThread] {
        recoveryProjectedCache
    }

    private var visibleInboxItems: [ExchangeInboxItem] {
        visibleInboxItemsCache
    }

    private var activeFeedItems: [ActiveFeedItem] {
        activeFeedItemsCache
    }

    private func hasExecutablePendingApproval(_ item: ExchangeModels.InboxItem) -> Bool {
        item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID)
    }

    #if DEBUG
    private func logDashboardStripState(
        item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket,
        vs: SecretaryProjectionEngine.ExchangeVisibleThreadStatus,
        reasonSubtitle: String
    ) {
        let hasVerifiedResults = discoveryCompactHasVerifiedResults(item)
        let shouldRouteToThreads = discoveryCompactShouldRouteToThreads(item, kind: kind)
        print(
            "[DashboardStripState] thread=\(item.threadID.uuidString) " +
            "state=\(item.state) bucket=\(kind) " +
            "title=\(vs.label) subtitle=\(reasonSubtitle) " +
            "hasVerifiedResults=\(hasVerifiedResults) shouldRouteToThreads=\(shouldRouteToThreads) " +
            "candidateCount=\(item.candidateCount) " +
            "selectedOffer=\(item.selectedOfferID != nil) " +
            "selectedCounterparty=\(item.selectedCounterpartyID != nil) " +
            "requiresHumanDecision=\(item.requiresHumanDecision) " +
            "hasPendingApproval=\(item.hasPendingApproval)"
        )
    }

    private func logDashboardStripRouteDecision(
        item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket,
        cta: String,
        action: String
    ) {
        let isSearchResult = SecretaryProjectionEngine.isSearchResult(item)
        let shouldRouteToThreads = discoveryCompactShouldRouteToThreads(item, kind: kind)
        let hasVerifiedResults = discoveryCompactHasVerifiedResults(item)
        let hasExecutableApproval = hasExecutablePendingApproval(item)
        print(
            "[DashboardStripRouteDecision] thread=\(item.threadID.uuidString) " +
            "state=\(item.state) bucket=\(kind) " +
            "isSearchResult=\(isSearchResult) shouldRouteToThreads=\(shouldRouteToThreads) " +
            "hasVerifiedResults=\(hasVerifiedResults) " +
            "hasExecutablePendingApproval=\(hasExecutableApproval) " +
            "cta=\(cta) action=\(action)"
        )
    }
    #endif

    // MARK: - Hero copy

    private var heroItem: ExchangeModels.InboxItem? {
        preferredProjected?.item ?? runningTraceProjected?.item ?? currentFocusItem
    }

    private func heroRequestTitle(for item: ExchangeModels.InboxItem) -> String {
        switch item.state {
        case .matchFound:
            if item.selectedOfferID != nil || item.selectedPublicProfileID != nil || item.selectedCounterpartyID != nil {
                let title = localClean(SecretaryProjectionEngine.displayTitle(for: item, surface: "home"))
                if !title.isEmpty {
                    return polishedHumanRequest(title)
                }

                if let match = SecretaryProjectionEngine.nonEmpty(item.selectedMatchSummary) {
                    return polishedHumanRequest(match)
                }
            }

        default:
            break
        }

        if let cap = SecretaryProjectionEngine.nonEmpty(item.capturedRequestText) {
            return polishedHumanRequest(cap)
        }

        return polishedDisplayTitle(for: item)
    }

    private var heroCurrentStateLine: String {
        guard let item = heroItem else {
            if let inbound = visibleInboxItems.first {
                return inboundSummary(for: inbound)
            }

            return "Tell me what you want moved forward. I’ll search, prepare, and ask before anything meaningful leaves your boundary."
        }

        let cardSubtitle = SecretaryProjectionEngine.displayCardSubtitle(for: item, surface: "home")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !cardSubtitle.isEmpty {
            return cardSubtitle
        }

        if let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: item) {
            return SecretaryProjectionEngine.secondHalfSummaryLine(secondHalf)
                ?? SecretaryProjectionEngine.nonEmpty(secondHalf.hero.statusLine)
                ?? SecretaryProjectionEngine.nonEmpty(secondHalf.subtitle)
                ?? "I’m qualifying this before asking you to decide."
        }

        if let trace = item.workTrace {
            if let active = trace.activeStep {
                return compactSentence(
                    title: active.title,
                    detail: SecretaryProjectionEngine.nonEmpty(active.detail),
                    fallback: "I’m working on this. Nothing meaningful has left your boundary without approval."
                )
            }

            if let latest = trace.latestStep {
                return compactSentence(
                    title: latest.title,
                    detail: SecretaryProjectionEngine.nonEmpty(latest.detail),
                    fallback: "I have recent progress on this."
                )
            }

            if let headline = SecretaryProjectionEngine.nonEmpty(trace.headline) {
                return headline
            }
        }

        if SecretaryProjectionEngine.isSearchResult(item) {
            return SecretaryProjectionEngine.searchResultPrimaryLine(for: item)
        }

        return SecretaryProjectionEngine.firstNonEmpty(
            item.nextStepText.map { "Next: \($0)" },
            item.outcomeStatusText,
            fallback: "I’m holding the thread and preparing the next useful move."
        )
    }

    private func routeDiscoveryCompactOpen(
        _ item: ExchangeModels.InboxItem,
        kind: SecretaryProjectionEngine.Bucket
    ) {
        let cta = discoveryCompactCTA(for: item, kind: kind)

        if SecretaryProjectionEngine.isClarification(item) {
            #if DEBUG
            logDashboardStripRouteDecision(item: item, kind: kind, cta: cta, action: "clarification")
            #endif
            onOpenClarification(item.threadID)
        } else if hasExecutablePendingApproval(item) {
            #if DEBUG
            logDashboardStripRouteDecision(item: item, kind: kind, cta: cta, action: "approval")
            #endif
            onOpenApprovalSheet(SecretaryProjectionEngine.approvalDisplay(for: item))
        } else if SecretaryProjectionEngine.isRecovery(item) {
            #if DEBUG
            logDashboardStripRouteDecision(item: item, kind: kind, cta: cta, action: "recovery")
            #endif
            onOpenRecoveryPanel(SecretaryProjectionEngine.recoveryDisplay(for: item))
        } else if discoveryCompactShouldRouteToThreads(item, kind: kind) {
            #if DEBUG
            logDashboardStripRouteDecision(item: item, kind: kind, cta: cta, action: "threads")
            #endif
            onViewDiscoveryResults(item.threadID)
        } else {
            #if DEBUG
            logDashboardStripRouteDecision(item: item, kind: kind, cta: cta, action: "threadDetail")
            #endif
            onOpenThread(item.threadID)
        }
    }

    private func compactSentence(title: String, detail: String?, fallback: String) -> String {
        let cleanTitle = localClean(title)
        let cleanDetail = localClean(detail)

        if !cleanTitle.isEmpty && !cleanDetail.isEmpty {
            if cleanDetail.lowercased().contains(cleanTitle.lowercased()) {
                return cleanDetail
            }

            return "\(cleanTitle). \(cleanDetail)"
        }

        if !cleanDetail.isEmpty { return cleanDetail }
        if !cleanTitle.isEmpty { return cleanTitle }
        return fallback
    }

    // MARK: - Inbound copy

    private func inboundBadge(for item: ExchangeInboxItem) -> String {
        switch item.processingState {
        case .received:
            return "New"
        case .deferred:
            return "Later"
        case .awaitingOrderingGapResolution:
            return "Waiting"
        case .reconciledIntoThread:
            return "Added"
        case .duplicateIgnored:
            return "Duplicate"
        case .rejected:
            return "Rejected"
        case .archived:
            return "Archived"
        }
    }

    private func inboundBadgeStyle(for item: ExchangeInboxItem) -> SecretaryStateChip.Style {
        switch item.processingState {
        case .received:
            return .active
        case .deferred, .awaitingOrderingGapResolution:
            return .warning
        case .reconciledIntoThread:
            return .success
        case .duplicateIgnored, .archived:
            return .neutral
        case .rejected:
            return .blocked
        }
    }

    private func inboundTitle(for item: ExchangeInboxItem) -> String {
        let subjectPreview = localClean(item.metadata["subject_preview"])

        if !subjectPreview.isEmpty,
           !ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(subjectPreview) {
            let sanitized = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                subjectPreview,
                field: .title,
                fallback: "New message"
            )

            return sanitized.count > 64 ? String(sanitized.prefix(64)) + "…" : sanitized
        }

        let subject = localClean(item.metadata["subject"])

        if !subject.isEmpty,
           !ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(subject) {
            let sanitized = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                subject,
                field: .title,
                fallback: "New message"
            )

            return sanitized.count > 64 ? String(sanitized.prefix(64)) + "…" : sanitized
        }

        let sender = localClean(item.senderDisplayName)
        if !sender.isEmpty { return sender }

        let summary = localClean(item.visibleSummary)

        if !summary.isEmpty,
           !ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(summary) {
            let sanitized = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                summary,
                field: .title,
                fallback: "New message"
            )

            return sanitized.count > 64 ? String(sanitized.prefix(64)) + "…" : sanitized
        }

        if let threadID = item.threadID {
            return "Someone replied · \(threadID.uuidString.prefix(6))"
        }

        return "New message"
    }

    private func inboundSummary(for item: ExchangeInboxItem) -> String {
        let summary = localClean(item.visibleSummary)

        if !summary.isEmpty {
            return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                summary,
                field: .body,
                fallback: "New activity in this thread"
            )
        }

        switch item.processingState {
        case .received:
            return "A reply or request came in. I’ll connect it to the right thread."
        case .deferred:
            return "Something came in, but I’m holding it for later."
        case .awaitingOrderingGapResolution:
            return "A message arrived out of order. Waiting before it’s added to your thread."
        case .reconciledIntoThread:
            return "Added to your thread."
        case .duplicateIgnored:
            return "I ignored a duplicate message."
        case .rejected:
            return "I rejected this message."
        case .archived:
            return "This message is archived."
        }
    }

    private func inboundSecondaryLine(for item: ExchangeInboxItem) -> String? {
        if let threadID = item.threadID {
            return "Thread \(threadID.uuidString.prefix(8))…"
        }

        let senderNodeID = localClean(item.senderNodeID)
        return senderNodeID.isEmpty ? nil : "From \(senderNodeID)"
    }

    // MARK: - Copy helpers

    private func localClean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localClean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func avatarIcon(for item: ExchangeModels.InboxItem) -> String {
        let text = [
            localClean(SecretaryProjectionEngine.displayTitle(for: item, surface: "home")),
            localClean(item.visibleSummary),
            localClean(item.subtitle),
            localClean(item.selectedMatchSummary)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()

        if text.contains("friend") ||
            text.contains("girlfriend") ||
            text.contains("boyfriend") ||
            text.contains("social") ||
            text.contains("partner") ||
            text.contains("meet") {
            return "person.2"
        }

        if text.contains("product") ||
            text.contains("buy") ||
            text.contains("sell") ||
            text.contains("shipping") ||
            text.contains("offer") {
            return "shippingbox"
        }

        if text.contains("service") ||
            text.contains("planner") ||
            text.contains("electrician") ||
            text.contains("bookkeeper") ||
            text.contains("contractor") ||
            text.contains("provider") {
            return "sparkles"
        }

        return "person.crop.circle"
    }

    private func polishedDisplayTitle(for item: ExchangeModels.InboxItem) -> String {
        if let cap = SecretaryProjectionEngine.nonEmpty(item.capturedRequestText) {
            return polishedHumanRequest(cap)
        }

        let raw = localClean(SecretaryProjectionEngine.displayTitle(for: item, surface: "home"))

        if raw.isEmpty {
            return "Untitled thread"
        }

        let lower = raw.lowercased()

        if lower == "find match" || lower == "match" || lower == "search" {
            return SecretaryProjectionEngine.firstNonEmpty(
                item.visibleSummary,
                item.selectedMatchSummary,
                fallback: "Finding a path"
            )
        }

        return polishedHumanRequest(raw)
    }

    private func polishedHumanRequest(_ raw: String) -> String {
        let clean = localClean(raw)
        guard !clean.isEmpty else { return "Untitled request" }

        let lower = clean.lowercased()

        if lower.hasPrefix("help me find ") {
            return clean.prefix(1).uppercased() + clean.dropFirst()
        }

        if lower.hasPrefix("find ") {
            return clean.prefix(1).uppercased() + clean.dropFirst()
        }

        if lower.hasPrefix("searching local candidates · ") {
            let request = String(clean.dropFirst("searching local candidates · ".count))
            return request.prefix(1).uppercased() + request.dropFirst()
        }

        if lower.hasPrefix("searching local candidates. ") {
            let request = String(clean.dropFirst("searching local candidates. ".count))
            return request.prefix(1).uppercased() + request.dropFirst()
        }

        return clean.prefix(1).uppercased() + clean.dropFirst()
    }

    /// Same URL normalization as thread list rows; ordering comes from ``InboxItem.surfaceListImageURLCandidates`` (facade / surface-aware).
    private func discoveryCompactStripThreadImageCandidates(for item: ExchangeModels.InboxItem) -> [String] {
        WorkThreadLeadImageURLNormalizer.normalizedChain(from: item.surfaceListImageURLCandidates)
    }

    /// Best-effort inbound preview URLs from federation metadata only (no new ranking).
    private func discoveryCompactStripInboundImageCandidates(for item: ExchangeInboxItem) -> [String] {
        var raw: [String] = []
        let metadata = item.metadata
        for key in [
            "primary_image_url",
            "image_url",
            "sender_image_url",
            "avatar_url",
            "sender_avatar_url",
            "offer_image_url"
        ] {
            if let v = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                raw.append(v)
            }
        }
        return WorkThreadLeadImageURLNormalizer.normalizedChain(from: raw)
    }

    private func initials(from value: String) -> String {
        let clean = value
            .replacingOccurrences(of: "Find ", with: "")
            .replacingOccurrences(of: "find ", with: "")
            .replacingOccurrences(of: "Help me find ", with: "")
            .replacingOccurrences(of: "help me find ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pieces = clean
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let result = String(pieces).uppercased()
        return result.isEmpty ? "S" : result
    }
}

private extension SecretaryDashboardView {
    /// Discovery compact strip: real surface photos when URL candidates exist; otherwise preserves ``SecretaryPhotoOrb`` (status icon / initials).
    struct DiscoveryCompactStripLeadAvatar: View {
        let normalizedImageCandidates: [String]
        let initials: String
        let systemImage: String?
        let orbStyle: SecretaryStateChip.Style
        let diameter: CGFloat

        var body: some View {
            Group {
                if normalizedImageCandidates.isEmpty {
                    SecretaryPhotoOrb(
                        initials: initials,
                        systemImage: systemImage,
                        style: orbStyle,
                        size: diameter
                    )
                } else {
                    ZStack {
                        UnifySoftVeilCircleFill(diameter: diameter)
                            .overlay(
                                Circle()
                                    .stroke(SecretaryTheme.semanticStroke(for: orbStyle), lineWidth: 1)
                            )
                        WorkThreadLeadAsyncImage(
                            urls: normalizedImageCandidates,
                            initials: initials,
                            diameter: diameter
                        )
                    }
                    .frame(width: diameter, height: diameter)
                }
            }
        }
    }

    func displayTitle(for item: ExchangeModels.InboxItem) -> String {
        SecretaryProjectionEngine.displayTitle(for: item, surface: "home")
    }
}
