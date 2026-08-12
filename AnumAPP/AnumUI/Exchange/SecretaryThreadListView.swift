import SwiftUI
import PhotosUI
import UIKit
import AnumCore

struct SecretaryThreadListView: View {
    private enum ThreadsSecretaryHeroOrbMetrics {
        /// ~20% larger than prior 44pt baseline; visual only (companion storage unchanged).
        static let diameter: CGFloat = 53
    }

    enum ListMode: String, CaseIterable, Identifiable {
        case recentResults = "Recent"
        case history = "History"

        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        /// Composite: judgment, recovery, or waiting (no new projection buckets).
        case needsYou = "Needs you"
        case judgment = "Approval"
        /// Compare / multi-candidate review posture (`ProjectedRow.isReviewable`).
        case decisionReady = "Review"

        var id: String { rawValue }
    }

    private struct ProjectedRow: Identifiable {
        let item: ExchangeModels.InboxItem
        let bucket: SecretaryProjectionEngine.Bucket
        let primaryLine: String
        let contextLine: String?
        let boundaryLine: String
        let relativeTimeText: String
        var id: ExchangeThread.ID { item.threadID }
        var threadID: ExchangeThread.ID { item.threadID }
        var updatedAt: Date { item.updatedAt }

        var isWaiting: Bool { SecretaryProjectionEngine.isWaiting(item) }
        var isJudgment: Bool { bucket == .pending }
        var isRecovery: Bool { bucket == .recovery }
        var isMoving: Bool {
            bucket == .active && !SecretaryProjectionEngine.isWaiting(item)
        }
        var isReviewable: Bool {
            SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: item)
        }
    }

    /// History list: one umbrella workbench row plus structural child path summaries.
    private struct HistoryUmbrellaGroup: Identifiable {
        let umbrella: ProjectedRow
        let children: [ExchangeModels.CoordinationChildThreadSummary]

        var id: ExchangeThread.ID { umbrella.threadID }
    }

    private struct ProjectionSummary {
        let rows: [ProjectedRow]
        let movingCount: Int
        let waitingCount: Int
        let judgmentCount: Int
        let recoveryCount: Int
        let pendingApprovalThreadIDs: Set<ExchangeThread.ID>

        static let empty = ProjectionSummary(
            rows: [],
            movingCount: 0,
            waitingCount: 0,
            judgmentCount: 0,
            recoveryCount: 0,
            pendingApprovalThreadIDs: []
        )
    }

    @EnvironmentObject private var services: AppServices

    let isTabActive: Bool

    /// Opens Profile / public-surface setup from the parent workspace (Discovery uses your profile).
    let onOpenDiscoverySetup: () -> Void

    let onOpenThread: (ExchangeThread.ID) -> Void
    let onViewDiscoveryResults: (ExchangeThread.ID) -> Void

    @AppStorage(SecretaryThreadListSetupNudge.dismissedUserDefaultsKey) private var threadListSetupNudgeDismissed = false

    @State private var items: [ExchangeModels.InboxItem] = []
    @State private var appliedDeskSnapshotGeneration: UInt64 = 0
    @State private var deskSnapshotApplyTask: Task<Void, Never>?
    @State private var pendingApprovals: [ExchangeModels.PendingApproval] = []
    @State private var projectionSummary = ProjectionSummary.empty
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorText: String?
    @State private var listMode: ListMode = .recentResults
    @State private var selectedFilter: Filter = .all
    @State private var recentSession: SecretarySearchResultSessionProjection?
    @State private var isLoadingRecentSession = false
    @State private var recentSessionLoadTask: Task<Void, Never>?
    @State private var recentSessionThreadID: ExchangeThread.ID?
    @State private var recentSessionCoordinationSignature: String?

    @State private var openHistorySwipeRowID: String?
    @State private var pendingDeleteHistoryRow: ProjectedRow?
    @State private var historyDeleteErrorText: String?
    @State private var expandedHistoryUmbrellaIDs: Set<String> = []

    @State private var isThreadSearchMode = false
    @State private var threadSearchText = ""
    @FocusState private var isThreadSearchFieldFocused: Bool

    /// Batched `listCounterpartyProfileImageURLs` keyed by node id + lowercase (fallback when match metadata has no offer image).
    @State private var threadCounterpartyProfileImageByNodeID: [String: String] = [:]
    @State private var threadCounterpartySupporterByNodeID: [String: ExchangeSupporterPresentation] = [:]

    @AppStorage("secretary.threads.pin.slots.v1") private var pinnedSlotsEncoded: String = ""

    /// Reuses companion disk keys + `CompanionAvatarDiskStorage.saveReplacingAvatar` (same portrait as companion mode).
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if shouldShowFirstLoad {
                    Spacer(minLength: 0)
                    threadsFirstLoadCard
                        .padding(.horizontal, 16)
                        .padding(.top, geo.safeAreaInsets.top + UnifyMainTabScrollLayout.paddingBelowSafeArea)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        threadsFixedChrome
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, geo.safeAreaInsets.top + UnifyMainTabScrollLayout.paddingBelowSafeArea)

                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 0) {
                                if listMode == .recentResults {
                                    SecretaryRecentResultsView(
                                        session: recentSession,
                                        isLoading: isLoadingRecentSession,
                                        onOpenThread: onOpenThread
                                    )
                                    .padding(.top, 10)
                                } else if let errorText, items.isEmpty {
                                    threadsErrorCard(message: errorText)
                                        .padding(.top, 16)
                                } else if historyFilteredUmbrellaRows.isEmpty {
                                    threadsEmptyState
                                } else if shouldShowThreadSearchNoMatches {
                                    threadSearchNoMatchesEmpty
                                        .padding(.top, 16)
                                } else {
                                    historyGroupedExchangeList
                                        .padding(.top, 10)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .refreshable {
                            services.refreshSecretaryDeskSnapshot(
                                reason: "threadListPullToRefresh",
                                force: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: isTabActive) {
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(
                generation: services.secretaryDeskSnapshot?.generation,
                showSpinner: false
            )
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            scheduleApplyDeskSnapshot(
                generation: services.secretaryDeskSnapshot?.generation,
                showSpinner: false
            )
        }
        .onChange(of: services.secretaryDeskSnapshot?.generation) { _, generation in
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(generation: generation, showSpinner: false)
        }
        .onDisappear {
            deskSnapshotApplyTask?.cancel()
            deskSnapshotApplyTask = nil
            recentSessionLoadTask?.cancel()
            recentSessionLoadTask = nil
        }
        .onChange(of: listMode) { _, newMode in
            openHistorySwipeRowID = nil
            expandedHistoryUmbrellaIDs = []
            if newMode == .recentResults, isTabActive {
                scheduleRecentSessionLoad()
            }
        }
        .confirmationDialog(
            historyRemoveConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteHistoryRow != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteHistoryRow = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let row = pendingDeleteHistoryRow else { return }
                pendingDeleteHistoryRow = nil
                Task { await archiveHistoryThread(row) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteHistoryRow = nil
            }
        } message: {
            Text(historyRemoveConfirmationMessage)
        }
        .alert(
            "Couldn't remove thread",
            isPresented: Binding(
                get: { historyDeleteErrorText != nil },
                set: { isPresented in
                    if !isPresented {
                        historyDeleteErrorText = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                historyDeleteErrorText = nil
            }
        } message: {
            Text(historyDeleteErrorText ?? "Try again.")
        }
    }

    /// Title, status, pinned rail, optional nudge, and filter pills — scrolls with the thread list in the primary column.
    private var threadsFixedChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isThreadSearchMode {
                threadSearchModeHeader
            } else {
                HStack(alignment: .center) {
                    Text("Threads")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 12)

                    threadsScreenChrome
                }
            }

            threadsPinnedQuickRail
                .padding(.top, 10)

            if shouldShowThreadListSetupNudge {
                threadListSetupNudgeCard
                    .padding(.top, 16)
            }

            SecretaryThreadsListModeSegment(
                selection: $listMode
            )
            .padding(.top, 10)

            if listMode == .history {
                filterBar
                    .padding(.top, 12)
            }
        }
    }

    private var threadsFirstLoadCard: some View {
        UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.9) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(SecretaryTheme.darkOrange)
                        .scaleEffect(1.05)

                    Text("Loading desk")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                Text("Opening exchanges.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Checking what is moving, waiting, blocked, or ready for you.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func threadsErrorCard(message: String) -> some View {
        UnifyDarkCard(cornerRadius: 22, strokeOpacity: 0.88) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn’t load exchanges")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    private var shouldShowFirstLoad: Bool {
        !hasLoadedOnce && items.isEmpty && errorText == nil
    }

    private var shouldShowThreadListSetupNudge: Bool {
        SecretaryThreadListSetupNudge.shouldShowCard(
            hasLoadedInbox: hasLoadedOnce,
            threadRowCount: projectedRows.count,
            isDismissed: threadListSetupNudgeDismissed,
            allowSafeAutoFollowUps: services.allowSafeAutoFollowUps,
            secretaryConstitutionText: services.secretaryConstitutionText,
            sellerWorkspace: services.sellerWorkspace
        )
    }

    private var projectedRows: [ProjectedRow] {
        projectionSummary.rows
    }

    private var historyRemoveConfirmationTitle: String {
        guard let row = pendingDeleteHistoryRow else { return "Remove from History?" }
        if row.item.threadRole == .umbrellaSearch {
            return "Remove this search?"
        }
        return "Remove from History?"
    }

    private var historyRemoveConfirmationMessage: String {
        guard let row = pendingDeleteHistoryRow else {
            return "This hides the thread from your history on this device."
        }
        if row.item.threadRole == .umbrellaSearch {
            return "This hides the search and its active paths from your history on this device."
        }
        return "This hides the thread from your history on this device."
    }

    private var filteredRows: [ProjectedRow] {
        switch selectedFilter {
        case .all:
            return projectedRows
        case .needsYou:
            return projectedRows.filter { $0.isJudgment || $0.isRecovery || $0.isWaiting }
        case .judgment:
            return projectedRows.filter(\.isJudgment)
        case .decisionReady:
            return projectedRows.filter(\.isReviewable)
        }
    }

    /// History umbrellas visible for the active filter (parent or any child path matches).
    private var historyFilteredUmbrellaRows: [ProjectedRow] {
        switch selectedFilter {
        case .all:
            return projectedRows
        case .needsYou:
            return projectedRows.filter { row in
                row.isJudgment || row.isRecovery || row.isWaiting
                    || row.item.coordinationChildSummaries.contains {
                        SecretaryProjectionEngine.historyChildMatchesNeedsYouFilter($0)
                    }
            }
        case .judgment:
            return projectedRows.filter { row in
                row.isJudgment
                    || row.item.coordinationChildSummaries.contains {
                        SecretaryProjectionEngine.historyChildMatchesJudgmentFilter($0)
                    }
            }
        case .decisionReady:
            return projectedRows.filter(\.isReviewable)
        }
    }

    private var historyDisplayGroups: [HistoryUmbrellaGroup] {
        historyFilteredUmbrellaRows.map { row in
            HistoryUmbrellaGroup(
                umbrella: row,
                children: row.item.coordinationChildSummaries
            )
        }
    }

    private var trimmedThreadSearchQuery: String {
        threadSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var threadListRowsForDisplay: [ProjectedRow] {
        let base = filteredRows
        guard isThreadSearchMode, !trimmedThreadSearchQuery.isEmpty else { return base }
        let lowered = trimmedThreadSearchQuery.lowercased()
        return base.filter { threadRowMatchesSearch($0, loweredQuery: lowered) }
    }

    private var historyGroupsForDisplay: [HistoryUmbrellaGroup] {
        let base = historyDisplayGroups
        guard isThreadSearchMode, !trimmedThreadSearchQuery.isEmpty else { return base }
        let lowered = trimmedThreadSearchQuery.lowercased()
        return base.filter { historyGroupMatchesSearch($0, loweredQuery: lowered) }
    }

    private var shouldShowThreadSearchNoMatches: Bool {
        isThreadSearchMode
            && !trimmedThreadSearchQuery.isEmpty
            && !historyFilteredUmbrellaRows.isEmpty
            && historyGroupsForDisplay.isEmpty
    }

    private var movingCount: Int { projectionSummary.movingCount }
    private var waitingCount: Int { projectionSummary.waitingCount }
    private var judgmentCount: Int { projectionSummary.judgmentCount }
    private var recoveryCount: Int { projectionSummary.recoveryCount }

    private var decisionReadyCount: Int {
        projectedRows.filter(\.isReviewable).count
    }

    private var needsYouAttentionCount: Int {
        projectedRows.filter { $0.isJudgment || $0.isRecovery || $0.isWaiting }.count
    }

    // MARK: - Header & status

    private var threadsScreenChrome: some View {
        threadsHeaderIconButton(systemName: "magnifyingglass") {
            enterThreadSearchMode()
        }
    }

    private func threadsHeaderIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                .frame(width: 40, height: 40)
                .background {
                    UnifyGlassIconDisk(diameter: 40, strokeOpacity: 0.65)
                }
        }
        .buttonStyle(.plain)
    }

    private var threadSearchModeHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                TextField("Search threads", text: $threadSearchText)
                    .focused($isThreadSearchFieldFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !threadSearchText.isEmpty {
                    Button {
                        threadSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnifyFrostedSearchFieldChrome(cornerRadius: 20, strokeOpacity: 0.75)
            }

            Button("Cancel") {
                exitThreadSearchMode()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .buttonStyle(.plain)
        }
    }

    private var threadSearchNoMatchesEmpty: some View {
        Text("No matching threads.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func enterThreadSearchMode() {
        isThreadSearchMode = true
        DispatchQueue.main.async {
            isThreadSearchFieldFocused = true
        }
    }

    @MainActor
    private func exitThreadSearchMode() {
        isThreadSearchMode = false
        threadSearchText = ""
        isThreadSearchFieldFocused = false
    }

    private func threadRowMatchesSearch(_ row: ProjectedRow, loweredQuery: String) -> Bool {
        threadSearchHaystack(for: row).lowercased().contains(loweredQuery)
    }

    /// Raw uniqued chain before ``WorkThreadLeadImageURLNormalizer`` (surface list + batched counterparty URLs).
    private func threadListLeadImageRawUniquedStrings(for row: ProjectedRow) -> [String] {
        let item = row.item
        var ordered: [String] = item.surfaceListImageURLCandidates
        if let id = item.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            let lowered = id.lowercased()
            if let u = threadCounterpartyProfileImageByNodeID[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                ordered.append(u)
            }
            if let u = threadCounterpartyProfileImageByNodeID[lowered]?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                ordered.append(u)
            }
        }
        return uniquedThreadListImageURLs(ordered)
    }

    /// Ordered image candidates: facade-hydrated surface list (offer/profile/match), then batched counterparty profile URLs; normalized for `AsyncImage`.
    private func threadListLeadImageURLCandidates(for row: ProjectedRow) -> [String] {
        WorkThreadLeadImageURLNormalizer.normalizedChain(from: threadListLeadImageRawUniquedStrings(for: row))
    }

    private func threadListSupporterPresentation(for row: ProjectedRow) -> ExchangeSupporterPresentation? {
        guard let id = row.item.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
            return nil
        }
        return threadCounterpartySupporterByNodeID[id]
            ?? threadCounterpartySupporterByNodeID[id.lowercased()]
    }

    private func resolvedThreadListLeadImageURL(for row: ProjectedRow) -> String? {
        threadListLeadImageURLCandidates(for: row).first
    }

    private func uniquedThreadListImageURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for v in values {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private func normalizedThreadListAvatarURLMap(from raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw {
            let trimmedKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedVal = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty, !trimmedVal.isEmpty else { continue }
            out[trimmedKey] = trimmedVal
            out[trimmedKey.lowercased()] = trimmedVal
        }
        return out
    }

    private func threadSearchHaystack(for row: ProjectedRow) -> String {
        let item = row.item
        let pieces: [String] = [
            userRequestTitle(for: row),
            row.primaryLine,
            row.contextLine ?? "",
            row.boundaryLine,
            cleanStatusLabel(for: row),
            cleanExchangeSummary(for: row),
            workThreadFootnote(for: row) ?? "",
            row.relativeTimeText,
            resolvedThreadListLeadImageURL(for: row) ?? "",
            item.title,
            item.subtitle,
            item.stateTitle,
            item.visibleSummary ?? "",
            item.capturedRequestText ?? "",
            item.selectedCounterpartyName ?? "",
            item.cardInboundSenderLabel ?? "",
            item.cardInboundRequesterPreview ?? "",
            item.nextStepText ?? "",
            item.latestFailureSummary ?? "",
            item.draftedSubject ?? "",
            item.draftedBodyPreview ?? "",
            item.selectedMatchSummary ?? "",
            item.outcomeStatusText ?? "",
            item.coordinationChildSummaries
                .map { SecretaryProjectionEngine.historyPathSearchHaystack(for: $0) }
                .joined(separator: " "),
            SecretaryProjectionEngine.historyUmbrellaPathsFootnote(for: item) ?? "",
            item.deliveryStatusText ?? "",
            item.interpretationSummary ?? ""
        ]
        return pieces.joined(separator: " ")
    }

    // MARK: - Pinned thread slots (drag from list; orange accent stroke only when filled)

    private enum ThreadPinRailMetrics {
        /// ~10% larger than prior 72×72 baseline; clipping + orange border unchanged.
        static let tileWidth: CGFloat = 79
        static let photoTileHeight: CGFloat = 79
        static let cornerRadius: CGFloat = 18
        static let slotCount = 10
        static let captionToTileSpacing: CGFloat = 6
        static let interSlotSpacing: CGFloat = 11
        static let statusCaptionFontSize: CGFloat = 11
        static let filledSlotIndexFontSize: CGFloat = 10
        static let emptySlotIndexFontSize: CGFloat = 11
        static let emptySlotDashInset: CGFloat = 7
    }

    private var threadsPinnedQuickRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: ThreadPinRailMetrics.interSlotSpacing) {
                ForEach(0..<ThreadPinRailMetrics.slotCount, id: \.self) { index in
                    threadPinSlot(index: index)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
    }

    private func threadPinSlot(index: Int) -> some View {
        let stored = pinnedThreadIDString(at: index)
        let row = projectedRow(forPinnedUUIDString: stored)

        return Group {
            if let row {
                VStack(spacing: ThreadPinRailMetrics.captionToTileSpacing) {
                    Button {
                        openPrimary(row)
                    } label: {
                        threadPinPhotoSlotBody(index: index, row: row)
                    }
                    .buttonStyle(.plain)

                    Text(cleanStatusLabel(for: row))
                        .font(.system(size: ThreadPinRailMetrics.statusCaptionFontSize, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .multilineTextAlignment(.center)
                        .frame(width: ThreadPinRailMetrics.tileWidth)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first else { return false }
                    return assignPinnedThread(at: index, uuidString: first)
                }
                .contextMenu {
                    Button("Remove pin", role: .destructive) {
                        setPinnedThreadID(at: index, to: "")
                    }
                }
                .accessibilityLabel("Pinned slot \(index + 1), \(userRequestTitle(for: row))")
            } else {
                threadPinEmptySlotBody(index: index)
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first else { return false }
                        return assignPinnedThread(at: index, uuidString: first)
                    }
                    .accessibilityLabel("Pinned slot \(index + 1), empty")
            }
        }
    }

    private func threadPinPhotoSlotBody(index: Int, row: ProjectedRow) -> some View {
        let urls = threadListLeadImageURLCandidates(for: row)
        let title = userRequestTitle(for: row)
        let w = ThreadPinRailMetrics.tileWidth
        let h = ThreadPinRailMetrics.photoTileHeight
        let cr = ThreadPinRailMetrics.cornerRadius
        return ZStack {
            UnifySoftVeilRoundedRectangle(cornerRadius: cr, strokeOpacity: 0.92)

            SecretaryPinSlotRemoteImage(
                urls: urls,
                initials: initials(from: title),
                cornerRadius: cr,
                width: w,
                height: h,
                debugPinnedLabel: {
                    #if DEBUG
                    "slot\(index):\(String(row.threadID.uuidString.prefix(8)))"
                    #else
                    nil
                    #endif
                }()
            )

            Text("\(index + 1)")
                .font(.system(size: ThreadPinRailMetrics.filledSlotIndexFontSize, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkMutedText.opacity(0.95))
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .stroke(SecretaryTheme.darkOrange, lineWidth: 2)
        )
        #if DEBUG
        .onAppear {
            let rawUniq = threadListLeadImageRawUniquedStrings(for: row)
            let norm = urls
            let urlValid = norm.first.flatMap { URL(string: $0) != nil } ?? false
            ThreadImagePipelineDebug.logPinned(
                slotID: index,
                threadShort: String(row.threadID.uuidString.prefix(8)),
                rawOrderedUniqueCount: rawUniq.count,
                normalizedCount: norm.count,
                selectedSource: norm.isEmpty ? "none" : "pinChain",
                urlValid: urlValid,
                frameW: Int(w),
                frameH: Int(h)
            )
        }
        #endif
    }

    private func threadPinEmptySlotBody(index: Int) -> some View {
        ZStack {
            UnifySoftVeilRoundedRectangle(cornerRadius: ThreadPinRailMetrics.cornerRadius, strokeOpacity: 0.92)

            RoundedRectangle(cornerRadius: ThreadPinRailMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    SecretaryTheme.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                )
                .padding(ThreadPinRailMetrics.emptySlotDashInset)

            Text("\(index + 1)")
                .font(.system(size: ThreadPinRailMetrics.emptySlotIndexFontSize, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(ThreadPinRailMetrics.emptySlotDashInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: ThreadPinRailMetrics.tileWidth, height: ThreadPinRailMetrics.photoTileHeight)
        .overlay(
            RoundedRectangle(cornerRadius: ThreadPinRailMetrics.cornerRadius, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
        )
    }

    private func pinnedThreadSlotsArray() -> [String] {
        let raw = pinnedSlotsEncoded
        if raw.isEmpty {
            return Array(repeating: "", count: ThreadPinRailMetrics.slotCount)
        }
        var parts = raw.components(separatedBy: "|")
        while parts.count < ThreadPinRailMetrics.slotCount {
            parts.append("")
        }
        if parts.count > ThreadPinRailMetrics.slotCount {
            parts = Array(parts.prefix(ThreadPinRailMetrics.slotCount))
        }
        return parts
    }

    private func persistPinnedThreadSlots(_ parts: [String]) {
        var ten = Array(parts.prefix(ThreadPinRailMetrics.slotCount))
        while ten.count < ThreadPinRailMetrics.slotCount {
            ten.append("")
        }
        pinnedSlotsEncoded = ten.joined(separator: "|")
    }

    private func pinnedThreadIDString(at index: Int) -> String {
        let parts = pinnedThreadSlotsArray()
        guard index >= 0, index < parts.count else { return "" }
        return parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setPinnedThreadID(at index: Int, to value: String) {
        var parts = pinnedThreadSlotsArray()
        guard index >= 0, index < ThreadPinRailMetrics.slotCount else { return }
        parts[index] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        persistPinnedThreadSlots(parts)
    }

    @discardableResult
    private func assignPinnedThread(at slotIndex: Int, uuidString: String) -> Bool {
        let trimmed = uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed),
              projectedRows.contains(where: { $0.threadID == uuid })
        else { return false }
        var parts = pinnedThreadSlotsArray()
        for i in 0..<ThreadPinRailMetrics.slotCount where i != slotIndex {
            if parts[i] == trimmed {
                parts[i] = ""
            }
        }
        parts[slotIndex] = trimmed
        persistPinnedThreadSlots(parts)
        return true
    }

    private func projectedRow(forPinnedUUIDString s: String) -> ProjectedRow? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = UUID(uuidString: trimmed) else { return nil }
        return projectedRows.first { $0.threadID == u }
    }

    private func purgeInvalidPinnedSlots() {
        let valid = Set(projectedRows.map(\.threadID.uuidString))
        var parts = pinnedThreadSlotsArray()
        var changed = false
        for i in 0..<ThreadPinRailMetrics.slotCount {
            let s = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, !valid.contains(s) {
                parts[i] = ""
                changed = true
            }
        }
        if changed {
            persistPinnedThreadSlots(parts)
        }
    }

    private func threadDragPreview(for row: ProjectedRow) -> some View {
        Text(userRequestTitle(for: row))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                UnifySoftVeilRoundedRectangle(cornerRadius: 12, strokeOpacity: 0.9)
            }
    }

    private var threadListSetupNudgeCard: some View {
        UnifyDarkCard(cornerRadius: 22, strokeOpacity: 0.88) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Let Unify help with follow-ups")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "Finish your public profile so Discovery can surface better matches. Enable Safe auto-follow-ups when you want Unify to draft low-risk clarifications for you."
                        )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenDiscoverySetup()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Set up Profile")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.orangeDeep.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        threadListSetupNudgeDismissed = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Not now")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background {
                            UnifySoftVeilCapsule(strokeOpacity: 0.9)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Filters

    /// Same horizontal filter rail as Chat (`SecretaryInboundView.chatsFilterPills`): `UnifyFilterPill` + `HStack(spacing: 10)` + trailing padding.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Filter.allCases) { filter in
                    let value = count(for: filter)
                    let isSelected = selectedFilter == filter
                    UnifyFilterPill(
                        title: "\(filter.rawValue) \(value > 99 ? "99+" : "\(value)")",
                        isSelected: isSelected,
                        selectedUsesNeutralChrome: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func count(for filter: Filter) -> Int {
        switch filter {
        case .all:
            return projectedRows.count
        case .needsYou:
            return needsYouAttentionCount
        case .judgment:
            return judgmentCount
        case .decisionReady:
            return decisionReadyCount
        }
    }

    // MARK: - List

    private var historyGroupedExchangeList: some View {
        LazyVStack(spacing: 8) {
            ForEach(historyGroupsForDisplay) { group in
                historyUmbrellaGroupView(group)
            }
        }
    }

    private func historyGroupMatchesSearch(_ group: HistoryUmbrellaGroup, loweredQuery: String) -> Bool {
        if threadRowMatchesSearch(group.umbrella, loweredQuery: loweredQuery) {
            return true
        }
        return group.children.contains {
            SecretaryProjectionEngine.historyPathSearchHaystack(for: $0)
                .lowercased()
                .contains(loweredQuery)
        }
    }

    private func toggleHistoryUmbrellaExpanded(_ threadID: ExchangeThread.ID) {
        let key = threadID.uuidString
        if expandedHistoryUmbrellaIDs.contains(key) {
            expandedHistoryUmbrellaIDs.remove(key)
        } else {
            expandedHistoryUmbrellaIDs.insert(key)
        }
    }

    @MainActor
    private func handleHistoryUmbrellaRowTap(_ group: HistoryUmbrellaGroup) {
        let row = group.umbrella
        let key = row.threadID.uuidString

        if openHistorySwipeRowID == key {
            openHistorySwipeRowID = nil
            return
        }

        guard !group.children.isEmpty else {
            if SecretaryProjectionEngine.isTerminalSearchReceipt(row.item) {
                onViewDiscoveryResults(row.threadID)
            }
            return
        }

        toggleHistoryUmbrellaExpanded(row.threadID)
    }

    private func historyUmbrellaFootnote(for row: ProjectedRow) -> String? {
        var pieces: [String] = []
        if let paths = SecretaryProjectionEngine.historyUmbrellaPathsFootnote(for: row.item) {
            pieces.append(paths)
        }
        if let review = historyDiscoveryReviewFootnote(for: row) {
            pieces.append(review)
        }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    /// History umbrella subtitle: real request/provider copy only (no "Find Provider" desk fallback).
    private func historyUmbrellaSubtitle(for row: ProjectedRow) -> String {
        if let review = SecretaryProjectionEngine.historyDiscoveryReviewSubtitle(for: row.item) {
            return review
        }

        let item = row.item

        if let name = SecretaryProjectionEngine.historyListPresentableLine(item.selectedCounterpartyName) {
            return name
        }

        if let joined = SecretaryProjectionEngine.historyListPresentableJoinedContext(row.contextLine) {
            let cleaned = historyCleanPublicSummary(joined)
            if !cleaned.isEmpty, cleaned != "Open exchange." {
                return cleaned
            }
        }

        // Factual inbox fields only — never card/status projection lines (`primaryLine`, `subtitle`).
        for candidate in [
            item.selectedMatchSummary,
            item.visibleSummary,
        ] {
            if let line = SecretaryProjectionEngine.historyListPresentableLine(candidate) {
                let cleaned = historyCleanPublicSummary(line)
                if !cleaned.isEmpty, cleaned != "Open exchange." {
                    return cleaned
                }
            }
        }

        let fallback = cleanExchangeSummary(for: row)
        if let line = SecretaryProjectionEngine.historyListPresentableLine(fallback) {
            return line
        }
        return ""
    }

    private func historyUmbrellaSubtitleFallback(for row: ProjectedRow) -> String {
        switch row.bucket {
        case .pending:
            return SecretaryProjectionEngine.isClarification(row.item)
                ? "A detail is needed before this can continue."
                : "Waiting for your review."
        case .recovery:
            return "This exchange needs attention before it can move again."
        case .searchResult:
            if row.isWaiting {
                return "Waiting for the other side."
            }
            if case .noViableMatch = row.item.state {
                return "No match found."
            }
            if case .matchCandidatesWeak = row.item.state {
                if let grade = row.item.discoveryProjectedGrade, grade != .weak {
                    switch grade {
                    case .strong:
                        return "Found strong matches — review before outreach."
                    case .moderate:
                        return "Review matches before choosing."
                    case .weak:
                        break
                    }
                }
                return "Weak matches — review or refine."
            }
            return "Open this thread for the latest update."
        case .active:
            return row.isWaiting
                ? "Waiting for the other side."
                : "Coordination is in motion."
        case .trusted:
            return "A known contact is available."
        case .none:
            return "Open exchange."
        }
    }

    private func historyDiscoveryReviewFootnote(for row: ProjectedRow) -> String? {
        let alts = row.item.alternateCandidateHeadlines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !SecretaryProjectionEngine.isGenericProviderSearchFallbackCopy($0) }
        guard !alts.isEmpty else { return nil }
        return "Other matches: \(alts.joined(separator: ", "))."
    }

    private func historyUmbrellaGroupView(_ group: HistoryUmbrellaGroup) -> some View {
        let row = group.umbrella
        let hasPaths = !group.children.isEmpty
        let expandKey = row.threadID.uuidString
        let isExpanded = expandedHistoryUmbrellaIDs.contains(expandKey)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 2) {
                historyUmbrellaWorkRow(
                    for: row,
                    pathsFootnote: historyUmbrellaFootnote(for: row),
                    onRowTap: { handleHistoryUmbrellaRowTap(group) }
                )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasPaths {
                    Button {
                        toggleHistoryUmbrellaExpanded(row.threadID)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse paths" : "Expand paths")
                }
            }

            if hasPaths, isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.children) { child in
                        SecretaryHistoryPathRowView(child: child) {
                            onOpenThread(child.childThreadID)
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, 4)
            }
        }
    }

    private func historyUmbrellaWorkRow(
        for row: ProjectedRow,
        pathsFootnote: String?,
        onRowTap: @escaping () -> Void
    ) -> some View {
        let title = userRequestTitle(for: row)
        let showsReview = SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: row.item)

        return VStack(alignment: .leading, spacing: 0) {
            SecretarySwipeActionRow(
                rowID: row.threadID.uuidString,
                openRowID: $openHistorySwipeRowID,
                onDelete: {
                    openHistorySwipeRowID = nil
                    pendingDeleteHistoryRow = row
                }
            ) {
                UnifyWorkThreadRow(
                    title: title,
                    statusTag: cleanStatusLabel(for: row),
                    subtitle: historyUmbrellaSubtitle(for: row),
                    footnote: pathsFootnote,
                    timestamp: row.relativeTimeText,
                    systemImage: cardIcon(for: row),
                    avatarImageURLCandidates: threadListLeadImageURLCandidates(for: row),
                    avatarInitials: initials(from: title),
                    showsAttentionDot: workThreadShowsAttentionDot(row),
                    showsAttentionRing: workThreadShowsAttentionRing(row),
                    publicSupporterPresentation: threadListSupporterPresentation(for: row),
                    debugSupporterNodeID: row.item.selectedCounterpartyID,
                    debugSupporterProfileID: row.item.selectedPublicProfileID,
                    debugThreadImageRowID: {
                        #if DEBUG
                        String(row.threadID.uuidString.prefix(8))
                        #else
                        nil
                        #endif
                    }(),
                    onTap: onRowTap
                )
                .draggable(row.threadID.uuidString) {
                    threadDragPreview(for: row)
                }
            }

            if showsReview {
                discoveryCandidateReviewCTAButton(for: row)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }
        }
    }

    private func workThreadRow(for row: ProjectedRow) -> some View {
        let title = userRequestTitle(for: row)
        let showsReview = SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: row.item)

        return VStack(alignment: .leading, spacing: 0) {
            SecretarySwipeActionRow(
                rowID: row.threadID.uuidString,
                openRowID: $openHistorySwipeRowID,
                onDelete: {
                    openHistorySwipeRowID = nil
                    pendingDeleteHistoryRow = row
                }
            ) {
                UnifyWorkThreadRow(
                    title: title,
                    statusTag: cleanStatusLabel(for: row),
                    subtitle: discoveryReviewSubtitle(for: row) ?? cleanExchangeSummary(for: row),
                    footnote: discoveryReviewFootnote(for: row),
                    timestamp: row.relativeTimeText,
                    systemImage: cardIcon(for: row),
                    avatarImageURLCandidates: threadListLeadImageURLCandidates(for: row),
                    avatarInitials: initials(from: title),
                    showsAttentionDot: workThreadShowsAttentionDot(row),
                    showsAttentionRing: workThreadShowsAttentionRing(row),
                    publicSupporterPresentation: threadListSupporterPresentation(for: row),
                    debugSupporterNodeID: row.item.selectedCounterpartyID,
                    debugSupporterProfileID: row.item.selectedPublicProfileID,
                    debugThreadImageRowID: {
                        #if DEBUG
                        String(row.threadID.uuidString.prefix(8))
                        #else
                        nil
                        #endif
                    }(),
                    onTap: {
                        if openHistorySwipeRowID == row.threadID.uuidString {
                            openHistorySwipeRowID = nil
                        } else {
                            openPrimary(row)
                        }
                    }
                )
                .draggable(row.threadID.uuidString) {
                    threadDragPreview(for: row)
                }
            }

            if showsReview {
                discoveryCandidateReviewCTAButton(for: row)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }
        }
    }

    private func discoveryReviewSubtitle(for row: ProjectedRow) -> String? {
        SecretaryProjectionEngine.discoveryCandidateReviewPrimaryLine(for: row.item)
    }

    private func discoveryReviewFootnote(for row: ProjectedRow) -> String? {
        SecretaryProjectionEngine.discoveryCandidateReviewAlternateLine(for: row.item)
    }

    @ViewBuilder
    private func discoveryCandidateReviewCTAButton(for row: ProjectedRow) -> some View {
        Button {
            openDiscoveryCandidateReview(for: row)
        } label: {
            Text(SecretaryProjectionEngine.discoveryCandidateReviewCTATitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)
        }
        .buttonStyle(.plain)
    }

    private func openDiscoveryCandidateReview(for row: ProjectedRow) {
        onViewDiscoveryResults(row.threadID)
    }

    private func workThreadShowsAttentionDot(_ row: ProjectedRow) -> Bool {
        row.isJudgment || row.isRecovery || row.isWaiting
    }

    private func workThreadShowsAttentionRing(_ row: ProjectedRow) -> Bool {
        row.isJudgment || row.isRecovery
    }

    private func workThreadFootnote(for row: ProjectedRow) -> String? {
        guard row.isJudgment || row.isRecovery else { return nil }
        return row.isJudgment
            ? "Boundary: approval required before outbound sends."
            : "Boundary: care required before this can move again."
    }

    // MARK: - Empty

    /// True empty (no history rows) or filter-empty; not used when search has no matches (`threadSearchNoMatchesEmpty`).
    private var threadsEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(threadsEmptyPrimaryLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            if let secondary = threadsEmptySecondaryLine {
                Text(secondary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }

    private var threadsEmptyPrimaryLine: String {
        if projectedRows.isEmpty {
            return "No activities yet."
        }
        switch selectedFilter {
        case .all:
            return "No activities yet."
        case .needsYou:
            return "Nothing needs you right now."
        case .judgment:
            return "Nothing in approval."
        case .decisionReady:
            return "Nothing to review."
        }
    }

    private var threadsEmptySecondaryLine: String? {
        if projectedRows.isEmpty {
            return "Your past exchanges will appear here."
        }
        return nil
    }

    // MARK: - Opening

    private func openPrimary(_ row: ProjectedRow) {
        if SecretaryProjectionEngine.isTerminalSearchReceipt(row.item) {
            #if DEBUG
            print(
                "[NoMatchProjectionPolicy] action=receiptRoute surface=threadsOpen " +
                "threadID=\(row.threadID.uuidString)"
            )
            #endif
            onViewDiscoveryResults(row.threadID)
            return
        }
        onOpenThread(row.threadID)
    }

    @MainActor
    private func archiveHistoryThread(_ row: ProjectedRow) async {
        let threadID = row.threadID
        openHistorySwipeRowID = nil

        let snapshotItems = items
        let snapshotProjection = projectionSummary
        let snapshotRecentSession = recentSession
        let snapshotRecentThreadID = recentSessionThreadID

        items.removeAll { $0.threadID == threadID }
        projectionSummary = buildProjectionSummary(
            items: items,
            pendingApprovals: pendingApprovals
        )

        if recentSessionThreadID == threadID {
            recentSession = nil
            recentSessionThreadID = nil
            recentSessionCoordinationSignature = nil
        }

        do {
            try await services.exchangeFacade.archiveThreadRespectingCoordinationFamily(id: threadID)
            services.refreshSecretaryDeskSnapshot(reason: "threadListArchive", force: true)
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil
            )
            if listMode == .recentResults {
                scheduleRecentSessionLoad()
            }
        } catch {
            items = snapshotItems
            projectionSummary = snapshotProjection
            recentSession = snapshotRecentSession
            recentSessionThreadID = snapshotRecentThreadID
            historyDeleteErrorText = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "SecretaryThreadListView.archiveThread"
            )
        }
    }

    // MARK: - Projection copy

    private func projectedPrimaryLine(
        for item: ExchangeModels.InboxItem,
        bucket: SecretaryProjectionEngine.Bucket,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> String {
        switch bucket {
        case .pending:
            return SecretaryProjectionEngine.pendingReason(for: item)

        case .recovery:
            return SecretaryProjectionEngine.failureWhatHappened(for: item)

        case .searchResult, .active, .trusted, .none:
            let cardSubtitle = SecretaryProjectionEngine.displayExchangeCardSubtitlePreferringVisibleStatus(
                for: item,
                bucket: bucket,
                pendingApprovalThreadIDs: pendingApprovalThreadIDs,
                surface: "exchange"
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if !cardSubtitle.isEmpty {
                return cardSubtitle
            }

            return SecretaryProjectionEngine.activityLatestMovement(for: item)
        }
    }

    private func projectedContextLine(for item: ExchangeModels.InboxItem) -> String? {
        var parts: [String] = []

        if let counterparty = SecretaryProjectionEngine.historyListPresentableLine(item.selectedCounterpartyName) {
            parts.append(counterparty)
        } else if item.candidateCount > 1 {
            parts.append("\(item.candidateCount) options considered")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Row text

    private func userRequestTitle(for row: ProjectedRow) -> String {
        let item = row.item

        if let cap = SecretaryProjectionEngine.nonEmpty(item.capturedRequestText) {
            return polishedTitle(cap)
        }

        return polishedTitle(SecretaryProjectionEngine.displayTitle(for: item, surface: "exchange"))
    }

    private func cleanStatusLabel(for row: ProjectedRow) -> String {
        SecretaryProjectionEngine.exchangeListStatusLabel(
            for: row.item,
            bucket: row.bucket,
            pendingApprovalThreadIDs: projectionSummary.pendingApprovalThreadIDs
        )
    }

    private func visibleRowStatus(for row: ProjectedRow) -> SecretaryProjectionEngine.ExchangeVisibleThreadStatus {
        SecretaryProjectionEngine.visibleThreadStatus(
            for: row.item,
            bucket: row.bucket,
            pendingApprovalThreadIDs: projectionSummary.pendingApprovalThreadIDs
        )
    }

    private func cleanExchangeSummary(for row: ProjectedRow) -> String {
        let item = row.item

        if let counterparty = SecretaryProjectionEngine.historyListPresentableLine(item.selectedCounterpartyName) {
            return counterparty
        }

        if let context = row.contextLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !context.isEmpty {
            let cleaned = cleanPublicSummary(context)
            if !cleaned.isEmpty { return cleaned }
        }

        if let match = SecretaryProjectionEngine.nonEmpty(item.selectedMatchSummary) {
            let cleaned = cleanPublicSummary(match)
            if !cleaned.isEmpty { return cleaned }
        }

        if let visible = SecretaryProjectionEngine.nonEmpty(item.visibleSummary) {
            let cleaned = cleanPublicSummary(visible)
            if !cleaned.isEmpty { return cleaned }
        }

        if let subtitle = SecretaryProjectionEngine.nonEmpty(item.subtitle) {
            let cleaned = cleanPublicSummary(subtitle)
            if !cleaned.isEmpty { return cleaned }
        }

        let primary = cleanPublicSummary(row.primaryLine)
        if !primary.isEmpty && primary != "Open exchange." {
            return primary
        }

        switch row.bucket {
        case .pending:
            return SecretaryProjectionEngine.isClarification(item)
                ? "A detail is needed before this can continue."
                : "Waiting for your review."

        case .recovery:
            return "This exchange needs attention before it can move again."

        case .searchResult:
            if row.isWaiting {
                return "Waiting for the other side."
            }
            if case .noViableMatch = row.item.state {
                return "No match found."
            }
            if case .matchCandidatesWeak = row.item.state {
                if let grade = row.item.discoveryProjectedGrade, grade != .weak {
                    switch grade {
                    case .strong:
                        return "Found strong matches — review before outreach."
                    case .moderate:
                        return "Review matches before choosing."
                    case .weak:
                        break
                    }
                }
                return "Weak matches — review or refine."
            }
            return "Open this thread for the latest update."

        case .active:
            return row.isWaiting
                ? "Waiting for the other side."
                : "Coordination is in motion."

        case .trusted:
            return "A known contact is available."

        case .none:
            return "Open exchange."
        }
    }

    private func isDiscoverySystemLogCopy(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower.contains("provider-facing") { return true }
        if lower.hasPrefix("i found") && lower.contains("public surfaces") { return true }
        if lower.contains("public surfaces with") { return true }
        if lower.contains("capability-oriented public surfaces") { return true }
        if lower.contains("affinity-oriented public surfaces") { return true }
        return false
    }

    /// History-only summary cleanup: strips generic provider-search scaffold segments before display.
    private func historyCleanPublicSummary(_ raw: String) -> String {
        if let presentable = SecretaryProjectionEngine.historyListPresentableLine(raw) {
            return cleanPublicSummary(presentable)
        }
        return ""
    }

    private func cleanPublicSummary(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Open exchange." }
        if isDiscoverySystemLogCopy(value) { return "" }
        if SecretaryProjectionEngine.isGenericProviderSearchFallbackCopy(value) { return "" }

        let bannedFragments = [
            "draft ready",
            "prepared locally",
            "waiting for approval",
            "ready to review",
            "nothing commitment-bearing",
            "safe for autonomous coordination",
            "appears safe",
            "boundary",
            "approval",
            "commitment-bearing",
            "undisclosed",
            "thread id",
            "threadid",
            "node-"
        ]

        let separators = [" · ", " - ", " — ", ", "]
        var parts = [value]

        for separator in separators where value.contains(separator) {
            parts = value
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            break
        }

        let cleanedParts = parts.filter { part in
            guard !part.isEmpty else { return false }
            if SecretaryProjectionEngine.isGenericProviderSearchFallbackCopy(part) { return false }
            if SecretaryProjectionEngine.isExchangeVisibleStatusCoachCopy(part) { return false }
            let lower = part.lowercased()
            return !bannedFragments.contains { lower.contains($0) }
        }

        if !cleanedParts.isEmpty {
            let joined = Array(cleanedParts.prefix(4)).joined(separator: " · ")
            return joined.replacingOccurrences(of: "thread", with: "exchange")
        }

        let lower = value.lowercased()

        if lower.contains("piano") {
            return "Piano teacher search."
        }

        if lower.contains("teacher") {
            return "Teacher search."
        }

        if lower.contains("service") {
            return "Service search."
        }

        if lower.contains("match") || lower.contains("path") {
            return "Option search."
        }

        return "Open exchange."
    }

    // MARK: - Visual helpers

    private func cardIcon(for row: ProjectedRow) -> String {
        visibleRowStatus(for: row).systemImage
    }

    private func polishedTitle(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "Untitled exchange" }

        let lower = raw.lowercased()

        if lower == "find match" || lower == "match" || lower == "search" {
            return "Finding an option"
        }

        if lower.hasPrefix("help me find ") {
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }

        if lower.hasPrefix("find ") {
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }

        if lower.hasPrefix("searching local candidates · ") {
            let request = String(raw.dropFirst("searching local candidates · ".count))
            return request.prefix(1).uppercased() + request.dropFirst()
        }

        if lower.hasPrefix("searching local candidates. ") {
            let request = String(raw.dropFirst("searching local candidates. ".count))
            return request.prefix(1).uppercased() + request.dropFirst()
        }

        return raw.prefix(1).uppercased() + raw.dropFirst()
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
        return result.isEmpty ? "EX" : result
    }

    // MARK: - Loading

    @MainActor
    private func scheduleApplyDeskSnapshot(
        generation: UInt64?,
        showSpinner: Bool = false
    ) {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Threads active=false skip=applyDeskSnapshot " +
                "reason=hiddenRetainedMount generation=\(generation ?? 0)"
            )
            #endif
            return
        }

        guard let generation else {
            if !hasLoadedOnce {
                isLoading = true
            }
            return
        }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Threads active=true source=snapshot " +
            "generation=\(generation)"
        )
        #endif

        deskSnapshotApplyTask?.cancel()
        deskSnapshotApplyTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let snapshot = services.secretaryDeskSnapshot,
                  snapshot.generation == generation else { return }
            await applyDeskSnapshot(snapshot, showSpinner: showSpinner)
        }
    }

    @MainActor
    private func applyDeskSnapshot(
        _ snapshot: SecretaryDeskSnapshot,
        showSpinner: Bool = false
    ) async {
        guard snapshot.generation != appliedDeskSnapshotGeneration else { return }

        if !hasLoadedOnce && items.isEmpty {
            isLoading = true
        } else if showSpinner && items.isEmpty {
            isLoading = true
        }

        errorText = nil

        let nextItems = snapshot.threadItems
        let nextApprovals = snapshot.pendingApprovals

        var nextAvatarMap = threadCounterpartyProfileImageByNodeID
        if isTabActive {
            let counterpartyIDsForAvatars = Array(
                Set(
                    nextItems.compactMap { item -> String? in
                        guard let raw = item.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !raw.isEmpty else { return nil }
                        return raw
                    }
                )
            )
            if !counterpartyIDsForAvatars.isEmpty {
                if let fetched = try? await services.exchangeFacade.listCounterpartyProfileImageURLs(
                    nodeIDs: counterpartyIDsForAvatars
                ) {
                    nextAvatarMap = normalizedThreadListAvatarURLMap(from: fetched)
                }
                if let supporters = try? await services.exchangeFacade.listCounterpartySupporterPresentations(
                    nodeIDs: counterpartyIDsForAvatars
                ) {
                    threadCounterpartySupporterByNodeID = supporters
                }
            }
        }

        let nextProjection = buildProjectionSummary(
            items: nextItems,
            pendingApprovals: nextApprovals
        )

        items = nextItems
        pendingApprovals = nextApprovals
        threadCounterpartyProfileImageByNodeID = nextAvatarMap
        projectionSummary = nextProjection
        appliedDeskSnapshotGeneration = snapshot.generation
        purgeInvalidPinnedSlots()
        errorText = nil
        hasLoadedOnce = true
        isLoading = false

        if listMode == .recentResults, isTabActive {
            scheduleRecentSessionLoad()
        }

        #if DEBUG
        threadImagePipelineDebugLogAfterInboxRefresh()
        #endif
    }

    private func scheduleRecentSessionLoad() {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Threads active=false skip=getThread " +
                "reason=hiddenRetainedMount"
            )
            #endif
            return
        }

        recentSessionLoadTask?.cancel()

        let pendingIDs = Set(pendingApprovals.map(\.threadID))
        guard let inboxItem = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingIDs,
            preferredThreadID: services.secretaryDeskPreferredThreadID,
            surface: "threadsRecent"
        ) else {
            recentSession = nil
            recentSessionThreadID = nil
            recentSessionCoordinationSignature = nil
            isLoadingRecentSession = false
            return
        }

        #if DEBUG
        let dashboardEquivalent = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingIDs,
            preferredThreadID: services.secretaryDeskPreferredThreadID,
            surface: "dashboardStrip"
        )
        print(
            "[CurrentSearchConsistency] dashboardLatest=\(dashboardEquivalent?.threadID.uuidString ?? "nil") " +
            "recent=\(inboxItem.threadID.uuidString) " +
            "match=\(dashboardEquivalent?.threadID == inboxItem.threadID)"
        )
        #endif

        let coordinationSignature = recentCoordinationSignature(for: inboxItem)
        let shouldReload =
            recentSessionThreadID != inboxItem.threadID
            || recentSession == nil
            || recentSessionCoordinationSignature != coordinationSignature

        #if DEBUG
        let reloadReason: String = {
            if recentSessionThreadID != inboxItem.threadID { return "threadChanged" }
            if recentSession == nil { return "noSession" }
            if recentSessionCoordinationSignature != coordinationSignature { return "signatureChanged" }
            return "unchanged"
        }()
        print(
            "[RecentSession] selected=\(inboxItem.threadID.uuidString) " +
            "currentSession=\(recentSessionThreadID?.uuidString ?? "nil") " +
            "reload=\(shouldReload) reason=\(reloadReason)"
        )
        #endif

        if !shouldReload {
            return
        }

        recentSessionLoadTask = Task { @MainActor in
            await loadRecentSession(for: inboxItem, coordinationSignature: coordinationSignature)
        }
    }

    private func recentCoordinationSignature(for inboxItem: ExchangeModels.InboxItem) -> String {
        let childIDs = inboxItem.coordinationChildThreadIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        let stateKey = String(describing: inboxItem.state)
        let offerID = inboxItem.selectedOfferID ?? "nil"
        let counterpartyID = inboxItem.selectedCounterpartyID ?? "nil"
        return [
            inboxItem.threadID.uuidString,
            stateKey,
            String(inboxItem.candidateCount),
            offerID,
            counterpartyID,
            inboxItem.hasPendingApproval ? "pendingApproval" : "noPendingApproval",
            childIDs,
            String(inboxItem.updatedAt.timeIntervalSince1970),
        ].joined(separator: "|")
    }

    @MainActor
    private func loadRecentSession(
        for inboxItem: ExchangeModels.InboxItem,
        coordinationSignature: String
    ) async {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Threads active=false skip=getThread " +
                "reason=hiddenRetainedMount threadID=\(inboxItem.threadID.uuidString)"
            )
            #endif
            return
        }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Threads active=true load=getThread " +
            "reason=recentResultsCard threadID=\(inboxItem.threadID.uuidString)"
        )
        #endif

        isLoadingRecentSession = true
        defer { isLoadingRecentSession = false }

        guard !Task.isCancelled else { return }

        do {
            let detail = try await services.exchangeFacade.getThread(threadID: inboxItem.threadID)
            guard !Task.isCancelled else { return }

            let pendingIDs = Set(pendingApprovals.map(\.threadID))
            recentSession = SecretarySearchResultProjection.buildSession(
                inboxItem: inboxItem,
                detail: detail,
                supplementalProfileImageURLsByNodeID: threadCounterpartyProfileImageByNodeID,
                pendingApprovalThreadIDs: pendingIDs
            )
            recentSessionThreadID = inboxItem.threadID
            recentSessionCoordinationSignature = coordinationSignature
        } catch {
            guard !Task.isCancelled else { return }
            recentSession = nil
            recentSessionThreadID = nil
            recentSessionCoordinationSignature = nil
        }
    }

    #if DEBUG
    /// DEBUG-only: trace thread image pipeline after inbox + avatar map refresh (no URLs or private text).
    private func threadImagePipelineDebugLogAfterInboxRefresh() {
        let inbox = items
        let rows = projectionSummary.rows
        let itemsWithSurface = inbox.filter { item in
            item.surfaceListImageURLCandidates.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
        let rowsWithNormalizedLead = rows.filter { !threadListLeadImageURLCandidates(for: $0).isEmpty }.count
        ThreadImagePipelineDebug.logTab(
            inboxCount: inbox.count,
            projectedRowCount: rows.count,
            itemsWithNonemptySurfaceCandidates: itemsWithSurface,
            rowsWithNonemptyNormalizedLead: rowsWithNormalizedLead
        )

        for row in rows.prefix(8) {
            let item = row.item
            let rawUniq = threadListLeadImageRawUniquedStrings(for: row)
            let normalized = threadListLeadImageURLCandidates(for: row)
            let rawSurface = item.surfaceListImageURLCandidates.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            let hadSurface = rawSurface > 0
            let hasCpMapURL: Bool = {
                guard let id = item.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !id.isEmpty else { return false }
                let lowered = id.lowercased()
                if let u = threadCounterpartyProfileImageByNodeID[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    return true
                }
                if let u = threadCounterpartyProfileImageByNodeID[lowered]?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    return true
                }
                return false
            }()
            let selectedSource: String = {
                if normalized.isEmpty { return "none" }
                if hadSurface && hasCpMapURL { return "surface+counterparty" }
                if hadSurface { return "surface" }
                if hasCpMapURL { return "counterparty" }
                return "ordered"
            }()
            let urlValid = normalized.first.flatMap { URL(string: $0) != nil } ?? false
            let twice = WorkThreadLeadImageURLNormalizer.normalizedChain(from: normalized)
            ThreadImagePipelineDebug.logRow(
                rowID: String(row.threadID.uuidString.prefix(8)),
                rawSurfaceCount: rawSurface,
                rawOrderedUniqueCount: rawUniq.count,
                normalizedCount: normalized.count,
                selectedSource: selectedSource,
                urlValid: urlValid,
                hasSurfaceListImageCandidates: hadSurface,
                hasPrimaryImageURL: item.selectedPublicProfileID != nil,
                hasOfferImageURL: item.selectedOfferID != nil,
                hasCounterpartyImageURL: item.selectedCounterpartyID != nil,
                incomingToRowCandidatesCount: normalized.count,
                afterLeadAvatarNormalizeCount: twice.count,
                frameW: 50,
                frameH: 50
            )
        }
    }
    #endif

    private func buildProjectionSummary(
        items: [ExchangeModels.InboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval]
    ) -> ProjectionSummary {
        let pendingApprovalThreadIDs = Set(pendingApprovals.map(\.threadID))

        let rows = items
            .compactMap { item -> ProjectedRow? in
                if item.threadRole == .candidateCoordination {
                    return nil
                }

                let bucket = SecretaryProjectionEngine.bucket(
                    for: item,
                    pendingApprovalThreadIDs: pendingApprovalThreadIDs
                )

                guard bucket != .none else { return nil }

                return ProjectedRow(
                    item: item,
                    bucket: bucket,
                    primaryLine: projectedPrimaryLine(
                        for: item,
                        bucket: bucket,
                        pendingApprovalThreadIDs: pendingApprovalThreadIDs
                    ),
                    contextLine: projectedContextLine(for: item),
                    boundaryLine: SecretaryProjectionEngine.boundaryLine(for: item),
                    relativeTimeText: SecretaryRelativeTime.string(from: item.updatedAt)
                )
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.threadID.uuidString < rhs.threadID.uuidString
            }

        let movingCount = rows.filter(\.isMoving).count
        let waitingCount = rows.filter(\.isWaiting).count
        let judgmentCount = rows.filter(\.isJudgment).count
        let recoveryCount = rows.filter(\.isRecovery).count

        return ProjectionSummary(
            rows: rows,
            movingCount: movingCount,
            waitingCount: waitingCount,
            judgmentCount: judgmentCount,
            recoveryCount: recoveryCount,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        )
    }
}

// MARK: - Pinned slot remote image (rounded rect; same URL chain + advance-on-failure as thread rows)

private struct SecretaryPinSlotRemoteImage: View {
    let urls: [String]
    let initials: String
    let cornerRadius: CGFloat
    let width: CGFloat
    let height: CGFloat
    var debugPinnedLabel: String? = nil

    @State private var resolvedIndex: Int = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                glassInitials
            } else {
                let idx = min(max(0, resolvedIndex), urls.count - 1)
                let urlString = urls[idx]
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: height)
                                .clipped()
                                .onAppear {
                                    #if DEBUG
                                    if let label = debugPinnedLabel {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "success")
                                    }
                                    #endif
                                }
                        case .failure(let error):
                            if idx < urls.count - 1 {
                                Color.clear
                                    .frame(width: width, height: height)
                                    .onAppear {
                                        #if DEBUG
                                        ThreadImagePipelineDebug.logAsyncImageFailure(
                                            context: "pinned",
                                            probeID: debugPinnedLabel ?? "n/a",
                                            url: url,
                                            error: error,
                                            normalizedCandidateCount: urls.count,
                                            selectedCandidateIndex: idx,
                                            phaseLabel: "failure"
                                        )
                                        #endif
                                        scheduleAdvance(from: idx)
                                    }
                            } else {
                                glassInitials
                                    .onAppear {
                                        #if DEBUG
                                        ThreadImagePipelineDebug.logAsyncImageFailure(
                                            context: "pinned",
                                            probeID: debugPinnedLabel ?? "n/a",
                                            url: url,
                                            error: error,
                                            normalizedCandidateCount: urls.count,
                                            selectedCandidateIndex: idx,
                                            phaseLabel: "failureLast"
                                        )
                                        #endif
                                    }
                            }
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                                .tint(SecretaryTheme.darkOrange)
                                .frame(width: width, height: height)
                                .onAppear {
                                    #if DEBUG
                                    if let label = debugPinnedLabel {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "empty")
                                    }
                                    #endif
                                }
                        @unknown default:
                            if idx < urls.count - 1 {
                                Color.clear
                                    .frame(width: width, height: height)
                                    .onAppear {
                                        #if DEBUG
                                        if let label = debugPinnedLabel {
                                            ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "unknown")
                                        }
                                        #endif
                                        scheduleAdvance(from: idx)
                                    }
                            } else {
                                glassInitials
                                    .onAppear {
                                        #if DEBUG
                                        if let label = debugPinnedLabel {
                                            ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "unknownLast")
                                        }
                                        #endif
                                    }
                            }
                        }
                    }
                    .id("\(idx)-\(urlString)")
                } else if idx < urls.count - 1 {
                    Color.clear
                        .frame(width: width, height: height)
                        .onAppear {
                            #if DEBUG
                            if let label = debugPinnedLabel {
                                ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "urlParseFailed")
                            }
                            #endif
                            scheduleAdvance(from: idx)
                        }
                } else {
                    glassInitials
                        .onAppear {
                            #if DEBUG
                            if let label = debugPinnedLabel {
                                ThreadImagePipelineDebug.logAsyncPhase(context: "pinned", id: label, phase: "urlParseFailedLast")
                            }
                            #endif
                        }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: urls) { _, _ in
            resolvedIndex = 0
        }
    }

    private var glassInitials: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            Text(initials)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: width, height: height)
    }

    private func scheduleAdvance(from idx: Int) {
        guard idx == resolvedIndex else { return }
        guard idx + 1 < urls.count else { return }
        let expected = idx
        DispatchQueue.main.async {
            if resolvedIndex == expected {
                resolvedIndex = expected + 1
            }
        }
    }
}
