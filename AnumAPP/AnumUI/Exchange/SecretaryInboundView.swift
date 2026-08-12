import SwiftUI
import AnumCore

/// Stable user-facing strings for Secretary inbound / reception (single source for UI + regression tests).
enum SecretaryInboundUserFacingCopy {
    static let linkedConversationSectionTitle = "Linked to conversation"
    static let linkedThreadChip = "In thread"
    static let unlinkedThreadChip = "Unlinked"

    static func processingHeadline(for state: ExchangeInboxItem.ProcessingState) -> String {
        switch state {
        case .received:
            return "New"
        case .deferred:
            return "Later"
        case .duplicateIgnored:
            return "Duplicate"
        case .awaitingOrderingGapResolution:
            return "Waiting"
        case .reconciledIntoThread:
            return "In thread"
        case .rejected:
            return "Rejected"
        case .archived:
            return "Archived"
        }
    }

    /// Card title fallback when inbound metadata is noisy and the item is already tied to a thread.
    static let linkedConversationCardTitleFallback = "Linked to conversation"
}

struct SecretaryInboundView: View {
    @EnvironmentObject private var services: AppServices

    let isTabActive: Bool

    /// Slight fan to the right for the three quick-chat favorite tiles (presentation only).
    private enum InboundQuickChatFanMetrics {
        private static let rotationsDegrees: [Double] = [-5, 0, 5]
        private static let offsetX: [CGFloat] = [0, 2, 4]

        static func rotationDegrees(for index: Int) -> Double {
            guard index >= 0, index < rotationsDegrees.count else { return 0 }
            return rotationsDegrees[index]
        }

        static func horizontalOffset(for index: Int) -> CGFloat {
            guard index >= 0, index < offsetX.count else { return 0 }
            return offsetX[index]
        }
    }

    /// Matches `SecretaryThreadListView.ThreadPinRailMetrics` tile chrome (pinned threads).
    private enum InboundQuickChatSlotMetrics {
        static let tileWidth: CGFloat = 72
        static let tileHeight: CGFloat = 78
        static let cornerRadius: CGFloat = 16
    }

    /// Metadata keys that may carry a counterparty node id when `senderNodeID` is blank (read-only projection).
    private static let inboundAvatarMetadataNodeKeys: [String] = [
        "sender_node_id",
        "counterparty_node_id",
        "trusted_node_id",
        "source_sender_node_id",
        "first_inbound_sender_node_id",
        "inbound_sender_node",
        "inbound_thread_sender_node"
    ]

    let onOpenConversation: (
        _ rowID: String,
        _ counterpartyNodeID: String?,
        _ displayName: String,
        _ linkedThreadID: ExchangeThread.ID?,
        _ intent: ExchangeInboundConversationOpenIntent,
        _ source: ExchangeInboundOpenSource
    ) -> Void
    let onOpenDirectMessage: (_ nodeID: String, _ displayName: String, _ existingThreadID: ExchangeThread.ID?) -> Void
    /// Presents the same add-trusted-contact sheet as the Trusted paths tab (`SecretaryAddTrustedContactSheet`).
    let onOpenAddTrustedContact: () -> Void

    private enum ConversationSource: String {
        case direct
        case thread
        case unknown
    }

    private struct InboundConversationRow: Identifiable {
        let id: String
        let counterpartyNodeID: String?
        let displayName: String
        let avatarURL: String?
        /// From inbox metadata (`primary_image_url` / `offer_image_url` / `image_url`); UI fallback after profile image.
        let offerPrimaryImageURL: String?
        /// First gallery URL from metadata lists; UI fallback after primary offer image.
        let offerGalleryFirstImageURL: String?
        let avatarInitial: String
        let latestPreview: String
        let latestTimestamp: Date
        let latestTimestampText: String
        let unreadCount: Int
        let linkedThreadID: ExchangeThread.ID?
        let trustState: String?
        let source: ConversationSource
        let underlyingInboxItemIDs: [ExchangeInboxItem.ID]
    }

    private struct InboundProjection {
        let rows: [InboundConversationRow]
        let withThreadCount: Int
        let withoutThreadCount: Int
        let unknownCounterpartyCount: Int

        static let empty = InboundProjection(
            rows: [],
            withThreadCount: 0,
            withoutThreadCount: 0,
            unknownCounterpartyCount: 0
        )
    }
    
    private struct ChatRowActionTarget: Identifiable {
        let id: String
        let rowID: String
        let nodeID: String
        let displayName: String
    }

    private enum ChatListFilter: String, CaseIterable, Identifiable {
        /// Order defines pill order: All → Pending → Direct → Contacts → Unread → Blocked.
        case all, requests, inbound, trusted, unread, blocked

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .requests: return "Pending"
            case .inbound: return "Direct"
            case .trusted: return "Contacts"
            case .unread: return "Unread"
            case .blocked: return "Blocked"
            }
        }
    }

    @State private var inboxItems: [ExchangeInboxItem] = []
    @State private var contactRequests: [ExchangeModels.ContactRequestItem] = []
    @State private var outgoingContactRequests: [OutgoingContactRequest] = []
    @State private var trustedChatContacts: [ExchangeModels.TrustedNodeItem] = []
    @State private var projection = InboundProjection.empty
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var lastFullLoadSecretaryRefreshID: Int = -1
    @State private var lastFullLoadSyncCompletedAt: Date?
    @State private var errorText: String?
    @State private var loadTask: Task<Void, Never>?

    private static var trustedContactsSessionCache: (
        localNodeID: String,
        contacts: [ExchangeModels.TrustedNodeItem],
        fetchedAt: Date
    )?
    private static let trustedContactsCacheTTL: TimeInterval = 300
    @State private var showContactRequestsSheet = false
    @State private var contactActionBusyRequestID: String?
    @State private var avatarByNodeID: [String: String] = [:]
    @State private var profileSummaryByNodeID: [String: (displayName: String?, avatarURL: String?)] = [:]
    @State private var chatListFilter: ChatListFilter = .all
    @State private var openChatSwipeRowID: String?
    @State private var pendingClearChatTarget: ChatRowActionTarget?
    @State private var pendingBlockChatTarget: ChatRowActionTarget?
    @State private var pendingUnblockContactTarget: ChatRowActionTarget?
    @State private var chatRowActionInFlightID: String?
    @State private var pendingNotificationProjectionReload = false

    @State private var isChatSearchMode = false
    @State private var chatSearchText = ""
    @FocusState private var isChatSearchFieldFocused: Bool

    @AppStorage("secretary.inbound.quickChat.0") private var inboundQuickChatRowID0: String = ""
    @AppStorage("secretary.inbound.quickChat.1") private var inboundQuickChatRowID1: String = ""
    @AppStorage("secretary.inbound.quickChat.2") private var inboundQuickChatRowID2: String = ""

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if shouldShowFirstLoad {
                    VStack {
                        Spacer(minLength: max(80, geo.safeAreaInsets.top + 48))
                        UnifyDarkLoadingView(
                            title: "Checking inbox.",
                            subtitle: "Looking for incoming messages and replies."
                        )
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        chatsFixedChrome
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, geo.safeAreaInsets.top + UnifyMainTabScrollLayout.paddingBelowSafeArea)

                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 0) {
                                if let errorText, projection.rows.isEmpty {
                                    chatsErrorCard(message: errorText)
                                        .padding(.top, 18)
                                } else {
                                    chatsConversationSection
                                        .padding(.top, 16)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 112)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .refreshable {
                            await load(showSpinner: true, force: true)
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
            handleInboundTabBecameActive()
        }
        .onChange(of: services.secretaryDeskSnapshot?.generation) { _, _ in
            guard isTabActive else { return }
            applyDeskSnapshotInboxSeedIfAvailable()
        }
        .onChange(of: services.secretaryRefreshID) { _, _ in
            guard isTabActive else { return }
            scheduleLoad(delayNanoseconds: 100_000_000)
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryWorkspaceShouldRefresh)) { _ in
            guard isTabActive else { return }
            scheduleLoad(delayNanoseconds: 120_000_000)
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryNotificationsDidChange)) { _ in
            handleSecretaryNotificationsDidChange()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .sheet(isPresented: $showContactRequestsSheet) {
            contactRequestsSheet
        }
        .confirmationDialog(
            "Clear chat history?",
            isPresented: Binding(
                get: { pendingClearChatTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingClearChatTarget = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingClearChatTarget {
                Button("Clear", role: .destructive) {
                    Task { @MainActor in
                        await clearChatHistoryFromList(target)
                        pendingClearChatTarget = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingClearChatTarget = nil
            }
        } message: {
            Text("This removes messages from this chat on this device.")
        }
        .confirmationDialog(
            "Block chat?",
            isPresented: Binding(
                get: { pendingBlockChatTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingBlockChatTarget = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingBlockChatTarget {
                Button("Block", role: .destructive) {
                    Task { @MainActor in
                        await blockChatFromList(target)
                        pendingBlockChatTarget = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingBlockChatTarget = nil
            }
        } message: {
            Text(
                "Hide this chat from your list on this device. Future messages from this contact may be hidden."
            )
        }
        .confirmationDialog(
            "Unblock contact?",
            isPresented: Binding(
                get: { pendingUnblockContactTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingUnblockContactTarget = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingUnblockContactTarget {
                Button("Unblock Contact") {
                    Task { @MainActor in
                        await unblockContactFromList(target)
                        pendingUnblockContactTarget = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingUnblockContactTarget = nil
            }
        } message: {
            if let target = pendingUnblockContactTarget {
                Text("\(target.displayName) will be allowed to appear in Chats and contact requests again.")
            } else {
                Text("This contact will be allowed to appear in Chats and contact requests again.")
            }
        }
    }

    /// Chats title chrome, story rail, filter pills, and optional requests banner — scrolls with the chat list in the primary column.
    private var chatsFixedChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            chatsHeader

            chatsStoryRail
                .padding(.top, 10)

            chatsFilterPills
                .padding(.top, 18)

            if !contactRequests.isEmpty, chatListFilter != .requests {
                chatsRequestsBanner
                    .padding(.top, 12)
            }
        }
    }

    private func chatFilterCount(for filter: ChatListFilter) -> Int {
        switch filter {
        case .all:
            return projection.rows.filter { $0.trustState != "blocked_contact" }.count
        case .unread:
            return projection.rows.filter { $0.unreadCount > 0 && $0.trustState != "blocked_contact" }.count
        case .requests:
            return projection.rows.filter {
                $0.trustState == "pending_outgoing_contact_request"
            }.count
        case .inbound:
            return projection.rows.filter {
                $0.source == .direct && $0.trustState != "blocked_contact"
            }.count
        case .trusted:
            return projection.rows.filter {
                $0.trustState == "trusted_contact"
            }.count
        case .blocked:
            return projection.rows.filter {
                $0.trustState == "blocked_contact"
            }.count
        }
    }

    private func chatFilterTitle(for filter: ChatListFilter) -> String {
        let count = chatFilterCount(for: filter)
        guard count > 0 else { return filter.title }
        let countText = count > 99 ? "99+" : "\(count)"
        return "\(filter.title) \(countText)"
    }

    private var filteredConversationRows: [InboundConversationRow] {
        switch chatListFilter {
        case .all:
            return projection.rows.filter { $0.trustState != "blocked_contact" }
        case .unread:
            return projection.rows.filter { $0.unreadCount > 0 && $0.trustState != "blocked_contact" }
        case .requests:
            return projection.rows.filter {
                $0.trustState == "pending_outgoing_contact_request"
            }
        case .inbound:
            return projection.rows.filter {
                $0.source == .direct && $0.trustState != "blocked_contact"
            }
        case .trusted:
            return projection.rows.filter {
                $0.trustState == "trusted_contact"
            }
        case .blocked:
            return projection.rows.filter {
                $0.trustState == "blocked_contact"
            }
        }
    }

    private var trimmedChatSearchQuery: String {
        chatSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chatRowsForDisplay: [InboundConversationRow] {
        let base = filteredConversationRows
        guard isChatSearchMode, !trimmedChatSearchQuery.isEmpty else { return base }
        let lowered = trimmedChatSearchQuery.lowercased()
        return base.filter { inboundChatRowMatchesSearch($0, loweredQuery: lowered) }
    }

    private var shouldShowChatSearchNoMatches: Bool {
        isChatSearchMode
            && !trimmedChatSearchQuery.isEmpty
            && !filteredConversationRows.isEmpty
            && chatRowsForDisplay.isEmpty
    }

    // MARK: - Chats chrome (dark)

    private var chatsHeader: some View {
        Group {
            if isChatSearchMode {
                chatSearchModeHeader
            } else {
                HStack(alignment: .center) {
                    Text("Chats")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 12)

                    chatsHeaderChromeButton(systemImage: "magnifyingglass") {
                        enterChatSearchMode()
                    }
                }
            }
        }
    }

    private var chatSearchModeHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                TextField("Search chats", text: $chatSearchText)
                    .focused($isChatSearchFieldFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !chatSearchText.isEmpty {
                    Button {
                        chatSearchText = ""
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
                exitChatSearchMode()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func enterChatSearchMode() {
        isChatSearchMode = true
        DispatchQueue.main.async {
            isChatSearchFieldFocused = true
        }
    }

    @MainActor
    private func exitChatSearchMode() {
        isChatSearchMode = false
        chatSearchText = ""
        isChatSearchFieldFocused = false
    }

    private func inboundChatRowMatchesSearch(_ row: InboundConversationRow, loweredQuery: String) -> Bool {
        inboundChatSearchHaystack(for: row).lowercased().contains(loweredQuery)
    }

    private func inboundChatSearchHaystack(for row: InboundConversationRow) -> String {
        var parts: [String] = [
            row.displayName,
            row.latestPreview,
            row.avatarInitial,
            row.latestTimestampText,
            row.trustState ?? ""
        ]
        if let node = row.counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !node.isEmpty {
            parts.append(node)
        }
        if let tid = row.linkedThreadID {
            parts.append(tid.uuidString)
        }
        return parts.joined(separator: " ")
    }

    /// Matches `SecretaryThreadListView.threadsHeaderIconButton` (shared frosted icon disk).
    private func chatsHeaderChromeButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                .frame(width: 40, height: 40)
                .background {
                    UnifyGlassIconDisk(diameter: 40, strokeOpacity: 0.65)
                }
        }
        .buttonStyle(.plain)
    }

    /// Compact quick-chat rail. Keep the slot band tight now that the header chrome is fixed.
    private var chatsStoryRail: some View {
        HStack(alignment: .bottom, spacing: 14) {
            chatsYouStoryCell

            Spacer(minLength: 8)

            inboundQuickChatFavoriteStrip
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var inboundQuickChatFavoriteStrip: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                inboundQuickChatSlot(index: index)
                    .rotationEffect(
                        .degrees(InboundQuickChatFanMetrics.rotationDegrees(for: index)),
                        anchor: UnitPoint(x: 0.5, y: 1.0)
                    )
                    .offset(x: InboundQuickChatFanMetrics.horizontalOffset(for: index))
            }
        }
    }

    private var chatsYouStoryCell: some View {
        Button {
            onOpenAddTrustedContact()
        } label: {
            VStack(spacing: 6) {
                inboundAddTrustedSlotChrome

                Text("Add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .frame(width: InboundQuickChatSlotMetrics.tileWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add trusted contact")
    }

    /// Same shell as an empty pinned thread slot (`threadPinSlotChrome`), with centered plus for “add trusted path”.
    private var inboundAddTrustedSlotChrome: some View {
        ZStack {
            UnifyGlassPlateBackground(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius)

            RoundedRectangle(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    SecretaryTheme.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                )
                .padding(6)

            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .frame(width: InboundQuickChatSlotMetrics.tileWidth, height: InboundQuickChatSlotMetrics.tileHeight)
        .overlay(
            RoundedRectangle(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
        )
    }

    private func inboundQuickChatRowID(at index: Int) -> String {
        switch index {
        case 0: inboundQuickChatRowID0
        case 1: inboundQuickChatRowID1
        case 2: inboundQuickChatRowID2
        default: ""
        }
    }

    private func setInboundQuickChatRowID(at index: Int, to newValue: String) {
        switch index {
        case 0: inboundQuickChatRowID0 = newValue
        case 1: inboundQuickChatRowID1 = newValue
        case 2: inboundQuickChatRowID2 = newValue
        default: break
        }
    }

    private func assignInboundQuickChatSlot(slotIndex: Int, rowID: String) {
        let trimmed = rowID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for i in 0..<3 where i != slotIndex {
            if inboundQuickChatRowID(at: i) == trimmed {
                setInboundQuickChatRowID(at: i, to: "")
            }
        }
        setInboundQuickChatRowID(at: slotIndex, to: trimmed)
    }

    private func inboundQuickChatDisplayInitials(for row: InboundConversationRow) -> String {
        let t = row.avatarInitial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(2)).uppercased() }
        let parts = row.displayName.split(separator: " ")
        if parts.count >= 2 {
            let a = parts[0].first.map(String.init) ?? ""
            let b = parts[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        return String(row.displayName.prefix(1)).uppercased()
    }

    @ViewBuilder
    private func inboundQuickChatSlot(index: Int) -> some View {
        let rowID = inboundQuickChatRowID(at: index)
        let row = projection.rows.first { $0.id == rowID }

        Group {
            if let row {
                Button {
                    onOpenConversation(
                        row.id,
                        row.counterpartyNodeID,
                        row.displayName,
                        row.linkedThreadID,
                        .directMessage,
                        .chatTab
                    )
                } label: {
                    VStack(spacing: 5) {
                        inboundQuickChatSlotChrome(
                            index: index,
                            isFilled: true,
                            imageURL: cacheBustedInboundAvatarURL(resolvedFavoriteSlotImageURL(for: row)),
                            initials: inboundQuickChatDisplayInitials(for: row)
                        )

                        Text(row.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.center)
                            .frame(width: InboundQuickChatSlotMetrics.tileWidth)
                    }
                }
                .buttonStyle(.plain)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first else { return false }
                    assignInboundQuickChatSlot(slotIndex: index, rowID: first)
                    return true
                }
                .contextMenu {
                    Button("Remove from quick chat", role: .destructive) {
                        setInboundQuickChatRowID(at: index, to: "")
                    }
                }
                .accessibilityLabel("Quick chat, \(row.displayName)")
                .accessibilityHint("Drop a conversation here to replace this shortcut.")
            } else {
                inboundQuickChatSlotChrome(index: index, isFilled: false, imageURL: nil, initials: "")
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first else { return false }
                        assignInboundQuickChatSlot(slotIndex: index, rowID: first)
                        return true
                    }
                    .accessibilityLabel("Quick chat slot \(index + 1), empty")
                    .accessibilityHint("Drag a conversation from the list and drop it here.")
            }
        }
        .onAppear {
            if !rowID.isEmpty, row == nil {
                setInboundQuickChatRowID(at: index, to: "")
            }
        }
    }

    /// Same structure as `SecretaryThreadListView.threadPinSlotChrome` (dashed empty interior, index badge, orange stroke when filled).
    @ViewBuilder
    private func inboundQuickChatSlotChrome(index: Int, isFilled: Bool, imageURL: String?, initials: String) -> some View {
        ZStack {
            UnifyGlassPlateBackground(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius)

            if isFilled {
                Group {
                    if let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !raw.isEmpty,
                       let url = URL(string: raw),
                       raw.lowercased().hasPrefix("http") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                inboundQuickChatSlotInitialsFill(initials: initials)
                            }
                        }
                    } else {
                        inboundQuickChatSlotInitialsFill(initials: initials)
                    }
                }
                .frame(width: InboundQuickChatSlotMetrics.tileWidth, height: InboundQuickChatSlotMetrics.tileHeight)
                .clipShape(RoundedRectangle(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        SecretaryTheme.white.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                    )
                    .padding(6)
            }

            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: InboundQuickChatSlotMetrics.tileWidth, height: InboundQuickChatSlotMetrics.tileHeight)
        .overlay(
            RoundedRectangle(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius, style: .continuous)
                .stroke(
                    isFilled ? SecretaryTheme.darkOrange : SecretaryTheme.darkStroke.opacity(0.75),
                    lineWidth: isFilled ? 2 : 1
                )
        )
    }

    private func inboundQuickChatSlotInitialsFill(initials: String) -> some View {
        Text(initials)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                UnifyGlassPlateBackground(cornerRadius: InboundQuickChatSlotMetrics.cornerRadius)
            }
    }

    private var chatsFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ChatListFilter.allCases) { filter in
                    UnifyFilterPill(
                        title: chatFilterTitle(for: filter),
                        isSelected: chatListFilter == filter,
                        selectedUsesNeutralChrome: true
                    ) {
                        chatListFilter = filter
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private var chatsRequestsBanner: some View {
        Button {
            #if DEBUG
            print("[ContactRequestOpen] count=\(contactRequests.count)")
            #endif
            showContactRequestsSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Contact requests")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Text(contactRequestsSummaryLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                UnifyFrostedSearchFieldChrome(cornerRadius: 20, strokeOpacity: 0.75)
            }
        }
        .buttonStyle(.plain)
    }

    private func chatsErrorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SecretaryTheme.darkOrange)
                Text("Couldn’t refresh")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
            }
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SecretaryTheme.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
                )
        )
    }

    private var chatsRequestsFilterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Requests")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            if contactRequests.isEmpty {
                Text("No pending contact requests.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            } else {
                Button {
                    #if DEBUG
                    print("[ContactRequestOpen] count=\(contactRequests.count)")
                    #endif
                    showContactRequestsSheet = true
                } label: {
                    HStack {
                        Text("Review \(contactRequests.count) request\(contactRequests.count == 1 ? "" : "s")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chatsConversationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if shouldShowChatSearchNoMatches {
                chatsSearchNoMatchesEmpty
            } else if filteredConversationRows.isEmpty {
                if projection.rows.isEmpty {
                    chatsEmptyCalm
                } else {
                    chatsEmptyFilterCalm
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(chatRowsForDisplay) { row in
                        inboundDarkChatRow(row)
                        if row.id != chatRowsForDisplay.last?.id {
                            Rectangle()
                                .fill(SecretaryTheme.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 66)
                        }
                    }
                }
            }
        }
    }

    private var chatsSearchNoMatchesEmpty: some View {
        Text("No matching chats.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private var chatsEmptyCalm: some View {
        Text("No conversations yet.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
    }

    private var chatsEmptyFilterCalm: some View {
        Text("Nothing matches this filter.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
    }

    private func inboundDarkChatRow(_ row: InboundConversationRow) -> some View {
        SecretarySwipeActionsRow(
            rowID: row.id,
            openRowID: $openChatSwipeRowID,
            actions: chatSwipeActions(for: row)
        ) {
            UnifyChatRow(
                title: row.displayName,
                subtitle: row.latestPreview,
                timestamp: row.latestTimestampText,
                avatarURL: cacheBustedInboundAvatarURL(row.avatarURL),
                avatarInitials: row.avatarInitial,
                showsAvatarActivityDot: row.unreadCount > 0,
                unreadBadgeCount: row.unreadCount > 0 ? row.unreadCount : nil
            ) {
                if openChatSwipeRowID == row.id {
                    openChatSwipeRowID = nil
                } else {
                    #if DEBUG
                    print(
                        "[InboundRowTap] source=chatTab intent=directMessage rowID=\(row.id) " +
                        "counterpartyNodeID=\(row.counterpartyNodeID ?? "nil") " +
                        "linkedThreadID=\(row.linkedThreadID?.uuidString ?? "nil")"
                    )
                    #endif
                    onOpenConversation(
                        row.id,
                        row.counterpartyNodeID,
                        row.displayName,
                        row.linkedThreadID,
                        .directMessage,
                        .chatTab
                    )
                }
            }
        }
        .disabled(chatRowActionInFlightID == row.id)
        .opacity(chatRowActionInFlightID == row.id ? 0.55 : 1)
        .draggable(row.id) {
            inboundQuickChatDragPreview(for: row)
        }
    }

    private func chatSwipeActions(for row: InboundConversationRow) -> [SecretarySwipeRowAction] {
        guard let target = chatActionTarget(for: row) else { return [] }

        if row.trustState == "blocked_contact" {
            return [
                SecretarySwipeRowAction(
                    id: "unblock",
                    title: "Unblock",
                    systemImage: "hand.raised.slash.fill",
                    tint: SecretaryTheme.darkOrange.opacity(0.92)
                ) {
                    openChatSwipeRowID = nil
                    pendingUnblockContactTarget = target
                }
            ]
        }

        let mutedClearTint = Color(red: 0.58, green: 0.42, blue: 0.28).opacity(0.94)

        return [
            SecretarySwipeRowAction(
                id: "clear",
                title: "Clear",
                systemImage: "text.badge.xmark",
                tint: mutedClearTint
            ) {
                openChatSwipeRowID = nil
                pendingClearChatTarget = target
            },
            SecretarySwipeRowAction(
                id: "block",
                title: "Block",
                systemImage: "hand.raised.fill",
                tint: Color.red.opacity(0.92)
            ) {
                openChatSwipeRowID = nil
                pendingBlockChatTarget = target
            }
        ]
    }
    
    private func chatActionTarget(for row: InboundConversationRow) -> ChatRowActionTarget? {
        guard let nodeID = row.counterpartyNodeID?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !nodeID.isEmpty else {
            return nil
        }

        return ChatRowActionTarget(
            id: row.id,
            rowID: row.id,
            nodeID: nodeID,
            displayName: row.displayName
        )
    }

    private func directMessageClearWatermarkKey(for nodeID: String) -> String {
        let normalized = nodeID
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()

        return "secretary.directMessage.clearWatermark.\(normalized)"
    }

    private func directMessageBlockedKey(for nodeID: String) -> String {
        let normalized = nodeID
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()

        return "secretary.directMessage.blocked.\(normalized)"
    }

    private var directMessageBlockedNodeIDsIndexKey: String {
        "secretary.directMessage.blockedNodeIDs"
    }

    private func blockedNodeIDsFromIndex() -> [String] {
        let indexed = UserDefaults.standard.stringArray(forKey: directMessageBlockedNodeIDsIndexKey) ?? []

        let prefix = "secretary.directMessage.blocked."
        let scanned = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> String? in
            guard key.hasPrefix(prefix) else { return nil }
            guard (value as? Double ?? 0) > 0 else { return nil }

            let nodeID = String(key.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            guard !nodeID.isEmpty else { return nil }
            return nodeID
        }

        var seen = Set<String>()
        return (indexed + scanned).compactMap { value in
            let nodeID = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !nodeID.isEmpty else { return nil }
            guard isNodeIDBlocked(nodeID) else { return nil }

            let key = nodeID.lowercased()
            guard seen.insert(key).inserted else { return nil }

            return nodeID
        }
    }

    private func saveBlockedNodeIDsIndex(_ nodeIDs: [String]) {
        var seen = Set<String>()
        let cleaned = nodeIDs.compactMap { value -> String? in
            let nodeID = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !nodeID.isEmpty else { return nil }
            let key = nodeID.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return nodeID
        }
        UserDefaults.standard.set(cleaned, forKey: directMessageBlockedNodeIDsIndexKey)
    }

    private func addBlockedNodeIDToIndex(_ nodeID: String) {
        let trimmed = nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var nodes = blockedNodeIDsFromIndex()
        if !nodes.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            nodes.append(trimmed)
        }
        saveBlockedNodeIDsIndex(nodes)
    }

    private func removeBlockedNodeIDFromIndex(_ nodeID: String) {
        let trimmed = nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let raw = UserDefaults.standard.stringArray(forKey: directMessageBlockedNodeIDsIndexKey) ?? []
        let nodes = raw.filter {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) != .orderedSame
        }
        saveBlockedNodeIDsIndex(nodes)
    }

    private func isNodeIDBlocked(_ nodeID: String) -> Bool {
        let trimmed = nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let key = directMessageBlockedKey(for: trimmed)
        return UserDefaults.standard.double(forKey: key) > 0
    }

    private func setDirectMessageBlockedAt(_ date: Date, for nodeID: String) {
        let key = directMessageBlockedKey(for: nodeID)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        addBlockedNodeIDToIndex(nodeID)

        #if DEBUG
        print("[ContactBlock] nodeID=\(nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) blockedAt=\(date)")
        #endif
    }

    private func setDirectMessageClearedAt(_ date: Date, for nodeID: String) {
        let key = directMessageClearWatermarkKey(for: nodeID)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)

        #if DEBUG
        print("[InboundClearChatHistory] nodeID=\(nodeID) clearedAt=\(date)")
        #endif
    }

    @MainActor
    private func clearChatHistoryFromList(_ target: ChatRowActionTarget) async {
        guard chatRowActionInFlightID == nil else { return }
        chatRowActionInFlightID = target.rowID
        defer { chatRowActionInFlightID = nil }

        let nodeID = target.nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !nodeID.isEmpty else { return }

        setDirectMessageClearedAt(Date(), for: nodeID)

        NotificationCenter.default.post(
            name: .secretaryWorkspaceShouldRefresh,
            object: nil,
            userInfo: ["counterpartyNodeID": nodeID]
        )

        await load(showSpinner: false)
    }

    @MainActor
    private func blockChatFromList(_ target: ChatRowActionTarget) async {
        guard chatRowActionInFlightID == nil else { return }
        chatRowActionInFlightID = target.rowID
        defer { chatRowActionInFlightID = nil }

        let targetNodeID = target.nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !targetNodeID.isEmpty else { return }

        let now = Date()
        setDirectMessageBlockedAt(now, for: targetNodeID)

        NotificationCenter.default.post(
            name: .secretaryWorkspaceShouldRefresh,
            object: nil,
            userInfo: ["counterpartyNodeID": targetNodeID]
        )

        await load(showSpinner: false)
        chatListFilter = .blocked
    }

    @MainActor
    private func unblockContactFromList(_ target: ChatRowActionTarget) async {
        guard chatRowActionInFlightID == nil else { return }
        chatRowActionInFlightID = target.rowID
        defer { chatRowActionInFlightID = nil }

        let targetNodeID = target.nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !targetNodeID.isEmpty else { return }

        UserDefaults.standard.removeObject(forKey: directMessageBlockedKey(for: targetNodeID))
        removeBlockedNodeIDFromIndex(targetNodeID)

        #if DEBUG
        print("[ContactUnblock] nodeID=\(targetNodeID)")
        #endif

        NotificationCenter.default.post(
            name: .secretaryWorkspaceShouldRefresh,
            object: nil,
            userInfo: ["counterpartyNodeID": targetNodeID]
        )

        await load(showSpinner: false)
    }

    private func inboundQuickChatDragPreview(for row: InboundConversationRow) -> some View {
        HStack(spacing: 10) {
            Text(inboundQuickChatDisplayInitials(for: row))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.92))
                )

            Text(row.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SecretaryTheme.darkSurface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.85), lineWidth: 1)
                )
        )
    }

    private var shouldShowFirstLoad: Bool {
        !hasLoadedOnce && inboxItems.isEmpty && errorText == nil
    }

    private var contactRequestsSummaryLine: String {
        guard let latest = contactRequests.first else {
            return "Review pending contact requests."
        }
        let who = latest.displayName
        if contactRequests.count == 1 {
            return "1 pending from \(who)."
        }
        return "\(contactRequests.count) pending. Latest from \(who)."
    }

    private var contactRequestsSheet: some View {
        NavigationStack {
            ZStack {
                UnifyIceShellBackground()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(contactRequests) { request in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    contactRequestAvatar(request)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                        Text(request.requesterNodeID ?? "Unknown node")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text(SecretaryRelativeTime.string(from: request.receivedAt))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(SecretaryTheme.darkMutedText)
                                }
                                if let note = request.note, !note.isEmpty {
                                    Text(note)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                        .lineLimit(3)
                                }
                                HStack(spacing: 10) {
                                    Button {
                                        Task { @MainActor in await acceptContactRequest(request) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                            Text("Accept")
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        .foregroundStyle(SecretaryTheme.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(SecretaryTheme.darkOrange)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(contactActionBusyRequestID != nil)
                                    .opacity(contactActionBusyRequestID != nil ? 0.55 : 1)

                                    Button {
                                        Task { @MainActor in await declineContactRequest(request) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "xmark.circle")
                                                .font(.system(size: 15, weight: .semibold))
                                            Text("Decline")
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(contactActionBusyRequestID != nil)
                                    .opacity(contactActionBusyRequestID != nil ? 0.55 : 1)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(SecretaryTheme.darkSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(SecretaryTheme.darkStroke.opacity(0.9), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Contact requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SecretaryTheme.darkBackgroundElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showContactRequestsSheet = false
                    } label: {
                        Text("Close")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(SecretaryTheme.darkStroke.opacity(0.85), lineWidth: 1)
                            )
                            .frame(minWidth: 88, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .tint(SecretaryTheme.darkOrange)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Loading

    @MainActor
    private func applyDeskSnapshotInboxSeedIfAvailable() {
        guard isTabActive, let snapshot = services.secretaryDeskSnapshot else { return }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Inbound active=true source=snapshot " +
            "generation=\(snapshot.generation) inbox=\(snapshot.visibleInboxItems.count)"
        )
        #endif

        guard inboxItems.isEmpty else { return }

        inboxItems = snapshot.visibleInboxItems
        projection = buildProjection(
            items: snapshot.visibleInboxItems,
            avatarByNodeID: avatarByNodeID,
            profileSummaryByNodeID: profileSummaryByNodeID,
            messagingAttentionNotifications: []
        )
        hasLoadedOnce = true
        isLoading = false
        errorText = nil
    }

    @MainActor
    private func handleSecretaryNotificationsDidChange() {
        if isTabActive {
            print("[ChatListUnread][notificationChanged] isTabActive=true action=reloadNow")
            scheduleLoad(
                delayNanoseconds: 120_000_000,
                force: true,
                reason: "notificationsDidChange"
            )
        } else {
            pendingNotificationProjectionReload = true
            print("[ChatListUnread][notificationChanged] isTabActive=false action=defer")
            print("[ChatListUnread][deferredReload] reason=notificationsDidChange pending=true")
        }
    }

    @MainActor
    private func handleInboundTabBecameActive() {
        applyDeskSnapshotInboxSeedIfAvailable()
        if pendingNotificationProjectionReload {
            pendingNotificationProjectionReload = false
            scheduleLoad(
                delayNanoseconds: 0,
                force: true,
                reason: "pendingNotificationsDidChange"
            )
        } else {
            scheduleLoad(delayNanoseconds: 0, reason: "normal")
        }
    }

    @MainActor
    private func scheduleLoad(
        delayNanoseconds: UInt64 = 200_000_000,
        force: Bool = false,
        reason: String = "normal"
    ) {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Inbound active=false skip=listInbox " +
                "reason=hiddenRetainedMount"
            )
            #endif
            return
        }

        loadTask?.cancel()

        loadTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await load(showSpinner: false, force: force, reason: reason)
        }
    }
    
    private func directMessageClearedAt(for nodeID: String) -> Date? {
        let key = directMessageClearWatermarkKey(for: nodeID)
        let seconds = UserDefaults.standard.double(forKey: key)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func directMessageClearCandidateNodeIDs(for item: ExchangeInboxItem) -> [String] {
        var out: [String] = []

        if let sender = item.senderNodeID?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !sender.isEmpty {
            out.append(sender)
        }

        for key in Self.inboundAvatarMetadataNodeKeys {
            if let nodeID = item.metadata[key]?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
               !nodeID.isEmpty {
                out.append(nodeID)
            }
        }

        var seen = Set<String>()
        return out.filter { nodeID in
            seen.insert(nodeID.lowercased()).inserted
        }
    }

    private func inboxItemSurvivesDirectMessageClearWatermark(_ item: ExchangeInboxItem) -> Bool {
        let nodeIDs = directMessageClearCandidateNodeIDs(for: item)
        guard !nodeIDs.isEmpty else { return true }

        for nodeID in nodeIDs {
            guard let clearedAt = directMessageClearedAt(for: nodeID) else {
                continue
            }

            if item.receivedAt <= clearedAt {
                #if DEBUG
                print(
                    "[InboundClearWatermarkFilter] nodeID=\(nodeID) hidden=1 kept=0 itemReceivedAt=\(item.receivedAt) clearedAt=\(clearedAt)"
                )
                #endif
                return false
            }
        }

        return true
    }

    private func inboxItemSurvivesBlockFilter(_ item: ExchangeInboxItem) -> Bool {
        let nodeIDs = directMessageClearCandidateNodeIDs(for: item)
        guard !nodeIDs.isEmpty else { return true }

        for nodeID in nodeIDs {
            guard isNodeIDBlocked(nodeID) else { continue }

            #if DEBUG
            print(
                "[InboundBlockFilter] nodeID=\(nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) hidden=1 inboxItemID=\(item.id.uuidString)"
            )
            #endif

            return false
        }

        return true
    }

    @MainActor
    private func inboundRefreshSkipReason(force: Bool) async -> String? {
        if force { return nil }

        let refreshID = services.secretaryRefreshID
        let syncCompletedAt = await services.exchangeSyncEngine.currentStatus().lastCompletedAt
        let refreshUnchanged = refreshID == lastFullLoadSecretaryRefreshID
        let syncUnchanged = syncCompletedAt == lastFullLoadSyncCompletedAt

        if hasLoadedOnce, !projection.rows.isEmpty, refreshUnchanged, syncUnchanged {
            return "noDelta"
        }

        if inboxItems.isEmpty,
           services.secretaryDeskSnapshot != nil,
           refreshUnchanged,
           syncUnchanged {
            return "snapshotSeedOnly"
        }

        return nil
    }

    @MainActor
    private func load(
        showSpinner: Bool = true,
        force: Bool = false,
        reason: String = "normal"
    ) async {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Inbound active=false skip=listInbox " +
                "reason=hiddenRetainedMount"
            )
            #endif
            return
        }

        let rowsBefore = projection.rows.count

        if let skipReason = await inboundRefreshSkipReason(force: force) {
            print(
                "[ChatListUnread][reload] reason=\(reason) force=\(force) " +
                "skipReason=\(skipReason) rowsBefore=\(rowsBefore) rowsAfter=\(rowsBefore)"
            )
            #if DEBUG
            print("[InboundRefreshGate] source=snapshot reason=\(skipReason)")
            #endif
            return
        }

        #if DEBUG
        print(
            "[InboundRefreshGate] source=fresh reason=\(force ? "explicitRefresh" : "becameActiveOrDelta")"
        )
        print(
            "[RetainedTabLoadGate] view=Inbound active=true load=listInbox " +
            "reason=becameActive"
        )
        #endif

        if !hasLoadedOnce && inboxItems.isEmpty {
            isLoading = true
        } else if showSpinner && inboxItems.isEmpty {
            isLoading = true
        }

        errorText = nil

        do {
            let loadedItems = try await services.exchangeFacade.listInboxItems(
                filter: ExchangeInboxFilter(limit: 800, includeReconciledLinkedToThread: true)
            )
            let pendingRequests = try await services.exchangeFacade.listPendingContactRequests(limit: 200)
            let pendingOutgoingRequests = try await services.exchangeFacade.listPendingOutgoingContactRequests(limit: 200)

            let localNodeID = await services.exchangeNodeID?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let trustedContacts: [ExchangeModels.TrustedNodeItem]
            if let localNodeID, !localNodeID.isEmpty {
                if let cached = Self.trustedContactsSessionCache,
                   cached.localNodeID == localNodeID,
                   Date().timeIntervalSince(cached.fetchedAt) < Self.trustedContactsCacheTTL {
                    trustedContacts = cached.contacts
                    #if DEBUG
                    print(
                        "[InboundRefreshGate] trustedContacts=cache count=\(trustedContacts.count)"
                    )
                    #endif
                } else {
                    trustedContacts = try await services.exchangeFacade.listTrustedNodes(
                        sourceNodeID: localNodeID,
                        limit: 500
                    )
                    Self.trustedContactsSessionCache = (
                        localNodeID: localNodeID,
                        contacts: trustedContacts,
                        fetchedAt: Date()
                    )
                }
            } else {
                trustedContacts = []
            }

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            let filteredContactRequests = pendingRequests.filter { request in
                guard let node = request.requesterNodeID?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                    !node.isEmpty else {
                    return true
                }
                return !isNodeIDBlocked(node)
            }

            let allContactRequestInboxItemIDs = Set(pendingRequests.flatMap(\.sourceInboxItemIDs))
            let contactRequestFilteredItems = loadedItems.filter { item in
                !allContactRequestInboxItemIDs.contains(item.id)
            }

            let blockFilteredItems = contactRequestFilteredItems.filter { item in
                inboxItemSurvivesBlockFilter(item)
            }

            let filteredItems = blockFilteredItems.filter { item in
                inboxItemSurvivesDirectMessageClearWatermark(item)
            }

            let hiddenByBlockCount = contactRequestFilteredItems.count - blockFilteredItems.count
            let hiddenByClearWatermarkCount = blockFilteredItems.count - filteredItems.count

            #if DEBUG
            if hiddenByBlockCount > 0 {
                print(
                    "[InboundBlockFilter] hiddenByBlockTotal=\(hiddenByBlockCount) before=\(contactRequestFilteredItems.count) after=\(blockFilteredItems.count)"
                )
            }
            if hiddenByClearWatermarkCount > 0 {
                print(
                    "[InboundClearWatermarkFilter] hiddenTotal=\(hiddenByClearWatermarkCount) before=\(blockFilteredItems.count) after=\(filteredItems.count)"
                )
            }
            #endif

            let trustedContactsForProjection = trustedContacts.filter { contact in
                let node = contact.nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                return !node.isEmpty && !isNodeIDBlocked(node)
            }

            let trustedNodeIDs = trustedContactsForProjection
                .map { $0.nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let trustedNodeIDSet = Set(trustedNodeIDs.map { $0.lowercased() })

            let pendingOutgoingRequestsForProjection = pendingOutgoingRequests.filter { request in
                let target = request.targetNodeID
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    .lowercased()
                guard !target.isEmpty else { return false }
                if isNodeIDBlocked(request.targetNodeID) {
                    return false
                }
                return !trustedNodeIDSet.contains(target)
            }

            let outboundRequestNodeIDs = pendingOutgoingRequestsForProjection
                .map { $0.targetNodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let blockedNodeIDsForProjection = blockedNodeIDsFromIndex()

            let avatarFetchNodeIDs = Array(
                Set(counterpartyNodeIDsForAvatarFetch(from: filteredItems) + outboundRequestNodeIDs + trustedNodeIDs + blockedNodeIDsForProjection)
            )

            async let resolvedProfileSummaries = services.exchangeFacade.listCounterpartyProfileSummaries(
                nodeIDs: avatarFetchNodeIDs
            )

            async let messagingUnread = services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )

            let (profileSummaries, messagingRows) = try await (resolvedProfileSummaries, messagingUnread)

            inboxItems = loadedItems
            contactRequests = filteredContactRequests
            outgoingContactRequests = pendingOutgoingRequests
            trustedChatContacts = trustedContactsForProjection

            let normalizedProfileSummaries = normalizedProfileSummaryMap(from: profileSummaries)
            let normalizedAvatars = avatarURLMap(fromProfileSummaries: normalizedProfileSummaries)

            avatarByNodeID = normalizedAvatars
            profileSummaryByNodeID = normalizedProfileSummaries

            #if DEBUG
            let requested = avatarFetchNodeIDs.count
            let returned = profileSummaries.count
            let rawKeysLower = Set(
                profileSummaries.keys.map {
                    $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
                }
            )
            let missing = avatarFetchNodeIDs.filter {
                !rawKeysLower.contains(
                    $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
                )
            }.count
            print(
                "[InboundAvatarMap] requested=\(requested) returned=\(returned) missing=\(missing)"
            )
            #endif

            let dmPreviewContext = counterpartiesForDMPreview(
                filteredItems: filteredItems,
                trustedContacts: trustedContactsForProjection
            )
            let dmPreviewByNodeID = await DirectMessageTranscriptProjection.buildInboundPreviewByCounterpartyNodeID(
                nodeIDs: dmPreviewContext.nodeIDs,
                linkedThreadIDByNodeID: dmPreviewContext.linkedThreadIDByNodeID,
                facade: services.exchangeFacade
            )

            let baseProjection = buildProjection(
                items: filteredItems,
                avatarByNodeID: normalizedAvatars,
                profileSummaryByNodeID: normalizedProfileSummaries,
                messagingAttentionNotifications: messagingRows,
                dmPreviewByNodeID: dmPreviewByNodeID
            )

            let withOutgoingRequests = projectionByAddingOutgoingContactRequests(
                baseProjection,
                outgoingRequests: pendingOutgoingRequestsForProjection,
                avatarByNodeID: normalizedAvatars,
                profileSummaryByNodeID: normalizedProfileSummaries
            )

            let withTrustedContacts = projectionByAddingTrustedChatContacts(
                withOutgoingRequests,
                trustedContacts: trustedContactsForProjection,
                avatarByNodeID: normalizedAvatars,
                profileSummaryByNodeID: normalizedProfileSummaries,
                dmPreviewByNodeID: dmPreviewByNodeID
            )

            projection = projectionByAddingBlockedContacts(
                withTrustedContacts,
                blockedNodeIDs: blockedNodeIDsForProjection,
                avatarByNodeID: normalizedAvatars,
                profileSummaryByNodeID: normalizedProfileSummaries
            )

            lastFullLoadSecretaryRefreshID = services.secretaryRefreshID
            lastFullLoadSyncCompletedAt = await services.exchangeSyncEngine.currentStatus().lastCompletedAt
            hasLoadedOnce = true

            print(
                "[ChatListUnread][reload] reason=\(reason) force=\(force) " +
                "skipReason=nil rowsBefore=\(rowsBefore) rowsAfter=\(projection.rows.count)"
            )

            #if DEBUG
            let latestReceivedAt = filteredItems.map(\.receivedAt).max()
            print(
                "[InboundLoadResult] items=\(loadedItems.count) rows=\(projection.rows.count) latestReceivedAt=\(latestReceivedAt.map { "\($0)" } ?? "nil") includeReconciled=true"
            )
            let blockedTrusted = trustedContacts.count - trustedContactsForProjection.count
            let blockedInbox = contactRequestFilteredItems.count - blockFilteredItems.count
            let blockedRequests = pendingRequests.count - filteredContactRequests.count
            print(
                "[InboundBlockProjection] blockedTrusted=\(blockedTrusted) blockedInbox=\(blockedInbox) blockedRequests=\(blockedRequests) blockedIndexed=\(blockedNodeIDsForProjection.count)"
            )
            print(
                "[InboundProjection] normalRows=\(projection.rows.count) contactRequests=\(filteredContactRequests.count) outgoingRequests=\(pendingOutgoingRequests.count) outgoingProjected=\(pendingOutgoingRequestsForProjection.count) trustedContacts=\(trustedContactsForProjection.count) excludedContactRequestItems=\(allContactRequestInboxItemIDs.count) hiddenByClearWatermark=\(hiddenByClearWatermarkCount)"
            )
            #endif
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            errorText = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "SecretaryInboundView.listInboxItems"
            )
        }

        hasLoadedOnce = true
        isLoading = false
    }

    @MainActor
    private func acceptContactRequest(_ request: ExchangeModels.ContactRequestItem) async {
        guard contactActionBusyRequestID == nil else { return }
        contactActionBusyRequestID = request.id
        defer { contactActionBusyRequestID = nil }
        do {
            guard let sourceNodeID = await services.exchangeNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sourceNodeID.isEmpty else {
                return
            }
            let edge = try await services.exchangeFacade.acceptContactRequest(
                sourceNodeID: sourceNodeID,
                request: request,
                now: Date()
            )
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: nil
            )
            await load(showSpinner: false)
            if let nodeID = request.requesterNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nodeID.isEmpty {
                onOpenDirectMessage(nodeID, request.displayName, nil)
                showContactRequestsSheet = false
            } else {
                _ = edge
            }
        } catch {
            #if DEBUG
            print("[ContactRequestAccept] nodeID=\(request.requesterNodeID ?? "nil") sourceInboxIDs=\(request.sourceInboxItemIDs.map(\.uuidString).joined(separator: ",")) success=false")
            #endif
        }
    }

    @MainActor
    private func declineContactRequest(_ request: ExchangeModels.ContactRequestItem) async {
        guard contactActionBusyRequestID == nil else { return }
        contactActionBusyRequestID = request.id
        defer { contactActionBusyRequestID = nil }
        do {
            try await services.exchangeFacade.declineContactRequest(
                request: request,
                now: Date()
            )
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: nil
            )
            await load(showSpinner: false)
        } catch {
            #if DEBUG
            print("[ContactRequestDecline] nodeID=\(request.requesterNodeID ?? "nil") sourceInboxIDs=\(request.sourceInboxItemIDs.map(\.uuidString).joined(separator: ",")) success=false")
            #endif
        }
    }
    
    private func counterpartiesForDMPreview(
        filteredItems: [ExchangeInboxItem],
        trustedContacts: [ExchangeModels.TrustedNodeItem]
    ) -> (nodeIDs: [String], linkedThreadIDByNodeID: [String: ExchangeThread.ID]) {
        var nodeIDs = Set<String>()
        var linkedThreadIDByNodeID: [String: ExchangeThread.ID] = [:]

        let groups = Dictionary(grouping: filteredItems, by: Self.conversationGroupKey(for:))
        for groupedItems in groups.values {
            let sorted = groupedItems.sorted {
                if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let latest = sorted.first else { continue }

            let counterparty = nonBlank(latest.senderNodeID)
                ?? Self.firstNonBlankMetadataNodeID(from: sorted)
            guard let counterparty else { continue }

            nodeIDs.insert(counterparty)
            if let threadID = sorted.compactMap(\.threadID).first {
                linkedThreadIDByNodeID[counterparty.lowercased()] = threadID
            }
        }

        for contact in trustedContacts {
            let nodeID = contact.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nodeID.isEmpty else { continue }
            nodeIDs.insert(nodeID)
        }

        return (Array(nodeIDs), linkedThreadIDByNodeID)
    }

    private static func firstNonBlankMetadataNodeID(from items: [ExchangeInboxItem]) -> String? {
        let keys = [
            "sender_node_id",
            "counterparty_node_id",
            "trusted_node_id",
            "source_sender_node_id",
            "first_inbound_sender_node_id",
            "inbound_sender_node",
            "inbound_thread_sender_node",
        ]
        for item in items {
            for key in keys {
                if let value = item.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func projectionByAddingTrustedChatContacts(
        _ base: InboundProjection,
        trustedContacts: [ExchangeModels.TrustedNodeItem],
        avatarByNodeID: [String: String],
        profileSummaryByNodeID: [String: (displayName: String?, avatarURL: String?)],
        dmPreviewByNodeID: [String: String]
    ) -> InboundProjection {
        var rows = base.rows
        var existingNodeIDs = Set(
            rows
                .compactMap { $0.counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        for contact in trustedContacts {
            let nodeID = contact.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nodeID.isEmpty else { continue }
            guard !existingNodeIDs.contains(nodeID) else { continue }

            let profileSummary = profileSummaryFromMap(profileSummaryByNodeID, nodeID: nodeID)
            let displayName =
                profileSummary?.displayName ??
                nonBlank(contact.publicDisplayName) ??
                nonBlank(contact.displayName) ??
                compactNodeID(nodeID)

            let latestPreview = resolvedDMInboundPreview(
                counterpartyNodeID: nodeID,
                dmPreviewByNodeID: dmPreviewByNodeID,
                logAsTrustedContact: true
            )

            let timestamp = contact.lastConfirmedAt ?? Date.distantPast

            rows.append(
                InboundConversationRow(
                    id: "trusted-contact:\(nodeID)",
                    counterpartyNodeID: nodeID,
                    displayName: displayName,
                    avatarURL: profileSummary?.avatarURL ?? contact.publicImageURL ?? avatarURLFromMap(avatarByNodeID, nodeID: nodeID),
                    offerPrimaryImageURL: nil,
                    offerGalleryFirstImageURL: nil,
                    avatarInitial: initials(from: displayName),
                    latestPreview: latestPreview,
                    latestTimestamp: timestamp,
                    latestTimestampText: timestamp == Date.distantPast ? "" : SecretaryRelativeTime.string(from: timestamp),
                    unreadCount: 0,
                    linkedThreadID: nil,
                    trustState: "trusted_contact",
                    source: .direct,
                    underlyingInboxItemIDs: []
                )
            )

            existingNodeIDs.insert(nodeID)
        }

        rows.sort {
            if $0.latestTimestamp != $1.latestTimestamp {
                return $0.latestTimestamp > $1.latestTimestamp
            }
            return $0.id < $1.id
        }

        return InboundProjection(
            rows: rows,
            withThreadCount: base.withThreadCount,
            withoutThreadCount: base.withoutThreadCount + max(0, rows.count - base.rows.count),
            unknownCounterpartyCount: base.unknownCounterpartyCount
        )
    }

    private func projectionByAddingBlockedContacts(
        _ base: InboundProjection,
        blockedNodeIDs: [String],
        avatarByNodeID: [String: String],
        profileSummaryByNodeID: [String: (displayName: String?, avatarURL: String?)]
    ) -> InboundProjection {
        var rows = base.rows
        var existingBlockedNodeIDs = Set(
            rows
                .filter { $0.trustState == "blocked_contact" }
                .compactMap { $0.counterpartyNodeID?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        for nodeIDRaw in blockedNodeIDs {
            let nodeID = nodeIDRaw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !nodeID.isEmpty else { continue }
            guard isNodeIDBlocked(nodeID) else { continue }
            guard !existingBlockedNodeIDs.contains(nodeID.lowercased()) else { continue }

            let profileSummary = profileSummaryFromMap(profileSummaryByNodeID, nodeID: nodeID)
            let displayName = profileSummary?.displayName ?? compactNodeID(nodeID)
            let blockedAt = Date(
                timeIntervalSince1970: UserDefaults.standard.double(forKey: directMessageBlockedKey(for: nodeID))
            )

            rows.append(
                InboundConversationRow(
                    id: "blocked-contact:\(nodeID)",
                    counterpartyNodeID: nodeID,
                    displayName: displayName,
                    avatarURL: profileSummary?.avatarURL ?? avatarURLFromMap(avatarByNodeID, nodeID: nodeID),
                    offerPrimaryImageURL: nil,
                    offerGalleryFirstImageURL: nil,
                    avatarInitial: initials(from: displayName),
                    latestPreview: "Blocked.",
                    latestTimestamp: blockedAt,
                    latestTimestampText: SecretaryRelativeTime.string(from: blockedAt),
                    unreadCount: 0,
                    linkedThreadID: nil,
                    trustState: "blocked_contact",
                    source: .direct,
                    underlyingInboxItemIDs: []
                )
            )

            existingBlockedNodeIDs.insert(nodeID.lowercased())
        }

        rows.sort {
            if $0.latestTimestamp != $1.latestTimestamp {
                return $0.latestTimestamp > $1.latestTimestamp
            }
            return $0.id < $1.id
        }

        return InboundProjection(
            rows: rows,
            withThreadCount: base.withThreadCount,
            withoutThreadCount: base.withoutThreadCount + max(0, rows.count - base.rows.count),
            unknownCounterpartyCount: base.unknownCounterpartyCount
        )
    }

    private func projectionByAddingOutgoingContactRequests(
        _ base: InboundProjection,
        outgoingRequests: [OutgoingContactRequest],
        avatarByNodeID: [String: String],
        profileSummaryByNodeID: [String: (displayName: String?, avatarURL: String?)]
    ) -> InboundProjection {
        var rows = base.rows
        var existingNodeIDs = Set(
            rows
                .compactMap { $0.counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        for request in outgoingRequests {
            let nodeID = request.targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nodeID.isEmpty else { continue }
            guard !existingNodeIDs.contains(nodeID) else { continue }

            let profileSummary = profileSummaryFromMap(profileSummaryByNodeID, nodeID: nodeID)
            let displayName =
                profileSummary?.displayName ??
                nonBlank(request.targetDisplayName) ??
                compactNodeID(nodeID)

            let subtitle: String = {
                switch request.phase {
                case .queued: return "Contact request queued."
                case .sending: return "Sending."
                case .sent: return "Contact request sent."
                case .failed: return request.lastError ?? "Contact request failed."
                case .accepted: return "Contact request accepted."
                }
            }()

            rows.append(
                InboundConversationRow(
                    id: "outgoing-contact-request:\(nodeID)",
                    counterpartyNodeID: nodeID,
                    displayName: displayName,
                    avatarURL: profileSummary?.avatarURL ?? avatarURLFromMap(avatarByNodeID, nodeID: nodeID),
                    offerPrimaryImageURL: nil,
                    offerGalleryFirstImageURL: nil,
                    avatarInitial: initials(from: displayName),
                    latestPreview: subtitle,
                    latestTimestamp: request.updatedAt,
                    latestTimestampText: SecretaryRelativeTime.string(from: request.updatedAt),
                    unreadCount: 0,
                    linkedThreadID: nil,
                    trustState: "pending_outgoing_contact_request",
                    source: .direct,
                    underlyingInboxItemIDs: []
                )
            )

            existingNodeIDs.insert(nodeID)
        }

        rows.sort {
            if $0.latestTimestamp != $1.latestTimestamp {
                return $0.latestTimestamp > $1.latestTimestamp
            }
            return $0.id < $1.id
        }

        return InboundProjection(
            rows: rows,
            withThreadCount: base.withThreadCount,
            withoutThreadCount: base.withoutThreadCount + max(0, rows.count - base.rows.count),
            unknownCounterpartyCount: base.unknownCounterpartyCount
        )
    }

    private func buildProjection(
        items: [ExchangeInboxItem],
        avatarByNodeID: [String: String],
        profileSummaryByNodeID: [String: (displayName: String?, avatarURL: String?)],
        messagingAttentionNotifications: [SecretaryNotification],
        dmPreviewByNodeID: [String: String] = [:]
    ) -> InboundProjection {
        let groups = Dictionary(grouping: items, by: Self.conversationGroupKey(for:))
        var rows: [InboundConversationRow] = []

        for (groupKey, groupedItemsRaw) in groups {
            let groupedItems = groupedItemsRaw.sorted {
                if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let latest = groupedItems.first else { continue }

            let avatarLookupNodeID = resolvedAvatarLookupNodeID(for: groupedItems, latest: latest)
            let counterpartyNodeID = nonBlank(latest.senderNodeID) ?? avatarLookupNodeID
            let linkedThreadID = groupedItems.compactMap(\.threadID).first
            let profileSummary = profileSummaryFromMap(
                profileSummaryByNodeID,
                nodeID: avatarLookupNodeID ?? counterpartyNodeID
            )
            let displayName = resolvedDisplayName(
                for: groupedItems,
                counterpartyNodeID: counterpartyNodeID,
                profileSummary: profileSummary
            )
            let source: ConversationSource = {
                if linkedThreadID != nil { return .thread }
                if counterpartyNodeID != nil { return .direct }
                return .unknown
            }()
            let avatarURL: String? = profileSummary?.avatarURL ?? avatarURLFromMap(avatarByNodeID, nodeID: avatarLookupNodeID)
            let inboxUnread = groupedItems.filter(needsReview).count
            let effectiveCounterpartyForAttention = counterpartyNodeID ?? avatarLookupNodeID
            let messagingUnreadNotifications = messagingAttentionNotifications
                .filter { !$0.isRead }
                .filter {
                    notificationMatchesInboundConversation(
                        $0,
                        groupKey: groupKey,
                        linkedThreadID: linkedThreadID,
                        counterpartyNodeID: effectiveCounterpartyForAttention
                    )
                }
            let messagingUnreadRowCount = messagingUnreadNotifications.count
            let messagingDistinctAttentionKeys = Set(
                messagingUnreadNotifications.map(\.inboundMessagingAttentionKey)
            ).count
            let unreadCount = inboxUnread + messagingUnreadRowCount
            if unreadCount > 0 {
                print(
                    "[ChatListUnread][rowBuild] conversationKey=\(groupKey) " +
                    "messagingUnread=\(messagingUnreadRowCount) inboxUnread=\(inboxUnread) " +
                    "unreadCount=\(unreadCount)"
                )
            }
            #if DEBUG
            if let nodeID = effectiveCounterpartyForAttention {
                print(
                    "[ContactUnreadProjection] source=inboxProcessingState nodeID=\(nodeID) unread=\(unreadCount) inboxUnread=\(inboxUnread) messagingUnreadRows=\(messagingUnreadRowCount) messagingDistinctAttentionKeys=\(messagingDistinctAttentionKeys) latest=\(latest.receivedAt)"
                )
            }
            #endif
            let offerPrimary = inboxMetadataPrimaryOfferImageURL(from: groupedItems)
            let offerGalleryFirst = inboxMetadataFirstGalleryOfferImageURL(from: groupedItems)
            let latestPreview = resolvedInboundLatestPreview(
                groupKey: groupKey,
                latestInboxItem: latest,
                counterpartyNodeID: counterpartyNodeID,
                dmPreviewByNodeID: dmPreviewByNodeID
            )

            let row = InboundConversationRow(
                id: groupKey,
                counterpartyNodeID: counterpartyNodeID,
                displayName: displayName,
                avatarURL: avatarURL,
                offerPrimaryImageURL: offerPrimary,
                offerGalleryFirstImageURL: offerGalleryFirst,
                avatarInitial: initials(from: displayName),
                latestPreview: latestPreview,
                latestTimestamp: latest.receivedAt,
                latestTimestampText: SecretaryRelativeTime.string(from: latest.receivedAt),
                unreadCount: unreadCount,
                linkedThreadID: linkedThreadID,
                trustState: nil,
                source: source,
                underlyingInboxItemIDs: groupedItems.map(\.id)
            )
            #if DEBUG
            let resolveSource: String = {
                if avatarLookupNodeID == nil { return "noNodeId" }
                if avatarURL != nil { return "counterpartyMap" }
                return "noImage"
            }()
            let urlPrefix: String = {
                guard let u = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return "nil" }
                let prefix = u.prefix(48)
                return String(prefix) + (u.count > 48 ? "…" : "")
            }()
            print(
                "[InboundAvatarResolve] rowID=\(groupKey) counterpartyNodeID=\(counterpartyNodeID ?? "nil") avatarLookupNodeID=\(avatarLookupNodeID ?? "nil") hasPublicImage=\(avatarURL != nil) source=\(resolveSource) urlPrefix=\(urlPrefix)"
            )
            #endif
            rows.append(row)
        }

        rows.sort {
            if $0.latestTimestamp != $1.latestTimestamp { return $0.latestTimestamp > $1.latestTimestamp }
            return $0.id < $1.id
        }

        let withThread = rows.filter { $0.linkedThreadID != nil }.count
        let withoutThread = rows.count - withThread
        let unknownCounterparty = rows.filter { $0.counterpartyNodeID == nil }.count
        #if DEBUG
        print(
            "[InboundConversationProjection] rawItems=\(items.count) groupedRows=\(rows.count) " +
            "withThread=\(withThread) withoutThread=\(withoutThread) unknownCounterparty=\(unknownCounterparty)"
        )
        #endif
        return InboundProjection(
            rows: rows,
            withThreadCount: withThread,
            withoutThreadCount: withoutThread,
            unknownCounterpartyCount: unknownCounterparty
        )
    }

    /// Builds a lookup map keyed by trimmed node id and by lowercased node id so UI matches the counterparty store regardless of casing drift.
    private func normalizedAvatarURLMap(from raw: [String: String]) -> [String: String] {
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
    
    private func normalizedProfileSummaryMap(
        from raw: [String: (displayName: String?, avatarURL: String?)]
    ) -> [String: (displayName: String?, avatarURL: String?)] {
        var out: [String: (displayName: String?, avatarURL: String?)] = [:]

        for (k, v) in raw {
            let trimmedKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }

            let rawDisplayName = v.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayName = rawDisplayName.isEmpty ? nil : rawDisplayName

            let rawAvatarURL = v.avatarURL?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let avatarURL = rawAvatarURL.isEmpty ? nil : rawAvatarURL

            guard displayName != nil || avatarURL != nil else { continue }

            let summary = (displayName: displayName, avatarURL: avatarURL)
            out[trimmedKey] = summary
            out[trimmedKey.lowercased()] = summary
        }

        return out
    }

    private func avatarURLMap(
        fromProfileSummaries summaries: [String: (displayName: String?, avatarURL: String?)]
    ) -> [String: String] {
        var out: [String: String] = [:]

        for (nodeID, summary) in summaries {
            guard let avatarURL = summary.avatarURL?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !avatarURL.isEmpty else {
                continue
            }

            out[nodeID] = avatarURL
        }

        return out
    }

    // MARK: - Quick chat / offer image metadata (read-only; keys aligned with `SecretaryThreadListView`)

    private func inboundSanitizedHTTPSURL(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let lower = t.lowercased()
        guard !lower.hasPrefix("file:") else { return nil }
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return t
    }
    
    private func cacheBustedInboundAvatarURL(_ raw: String?) -> String? {
        guard let t = inboundSanitizedHTTPSURL(raw),
              var components = URLComponents(string: t) else {
            return raw
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "unify_avatar_v" }
        queryItems.append(
            URLQueryItem(
                name: "unify_avatar_v",
                value: String(services.secretaryRefreshID)
            )
        )
        components.queryItems = queryItems

        return components.string ?? t
    }

    private func inboxMetadataPrimaryOfferImageURL(from items: [ExchangeInboxItem]) -> String? {
        for item in items {
            let meta = item.metadata
            for key in ["primary_image_url", "offer_image_url", "image_url"] {
                if let u = inboundSanitizedHTTPSURL(meta[key]) { return u }
            }
        }
        return nil
    }

    private func inboxFirstGalleryURLFromItemMetadata(_ metadata: [String: String]) -> String? {
        for key in ["gallery_image_urls", "surfaced_offer_image_urls", "offer_gallery_urls"] {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                for s in decoded {
                    if let u = inboundSanitizedHTTPSURL(s) { return u }
                }
            }
            for part in raw.split(separator: ",") {
                if let u = inboundSanitizedHTTPSURL(String(part)) { return u }
            }
        }
        return nil
    }

    private func inboxMetadataFirstGalleryOfferImageURL(from items: [ExchangeInboxItem]) -> String? {
        for item in items {
            if let u = inboxFirstGalleryURLFromItemMetadata(item.metadata) { return u }
        }
        return nil
    }

    /// Image priority for favorite slots: public profile → offer primary → offer gallery (then initials in chrome).
    private func resolvedFavoriteSlotImageURL(for row: InboundConversationRow) -> String? {
        if let u = inboundSanitizedHTTPSURL(row.avatarURL) { return u }
        if let u = inboundSanitizedHTTPSURL(row.offerPrimaryImageURL) { return u }
        if let u = inboundSanitizedHTTPSURL(row.offerGalleryFirstImageURL) { return u }
        return nil
    }

    private func avatarURLFromMap(_ map: [String: String], nodeID: String?) -> String? {
        guard let raw = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return map[raw] ?? map[raw.lowercased()]
    }
    
    private func profileSummaryFromMap(
        _ map: [String: (displayName: String?, avatarURL: String?)],
        nodeID: String?
    ) -> (displayName: String?, avatarURL: String?)? {
        guard let raw = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return map[raw] ?? map[raw.lowercased()]
    }

    /// Node ids to resolve public profile images (batched `listCounterpartyProfileImageURLs`).
    private func counterpartyNodeIDsForAvatarFetch(from items: [ExchangeInboxItem]) -> [String] {
        var set = Set<String>()
        for item in items {
            if let s = nonBlank(item.senderNodeID) {
                set.insert(s)
            }
            for key in Self.inboundAvatarMetadataNodeKeys {
                if let v = nonBlank(item.metadata[key]) {
                    set.insert(v)
                }
            }
        }
        return Array(set)
    }

    /// Prefer `senderNodeID`, then first metadata-backed node id in the conversation group.
    private func resolvedAvatarLookupNodeID(for groupedItems: [ExchangeInboxItem], latest: ExchangeInboxItem) -> String? {
        if let s = nonBlank(latest.senderNodeID) { return s }
        for item in groupedItems {
            for key in Self.inboundAvatarMetadataNodeKeys {
                if let v = nonBlank(item.metadata[key]) { return v }
            }
        }
        return nil
    }

    // MARK: - Copy helpers

    private func clean(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedDMInboundPreview(
        counterpartyNodeID: String,
        dmPreviewByNodeID: [String: String],
        groupKey: String? = nil,
        logAsTrustedContact: Bool = false
    ) -> String {
        let normalized = counterpartyNodeID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let raw = dmPreviewByNodeID[normalized]
        let display = DirectMessageTranscriptProjection.inboundLatestPreviewDisplay(
            fromCanonicalPreview: raw
        )

        #if DEBUG
        if logAsTrustedContact {
            print(
                "[TrustedContactPreview] nodeID=\(counterpartyNodeID) " +
                "source=\(display.source.rawValue) preview=\(display.text)"
            )
        } else if let groupKey {
            print(
                "[InboundPreviewSource] groupKey=\(groupKey) nodeID=\(counterpartyNodeID) " +
                "source=\(display.source.rawValue) preview=\(display.text)"
            )
        }
        #endif

        return display.text
    }

    /// DM-aligned preview from canonical thread transcript; raw inbox metadata only when no counterparty node.
    private func resolvedInboundLatestPreview(
        groupKey: String,
        latestInboxItem: ExchangeInboxItem,
        counterpartyNodeID: String?,
        dmPreviewByNodeID: [String: String]
    ) -> String {
        if let node = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !node.isEmpty {
            return resolvedDMInboundPreview(
                counterpartyNodeID: node,
                dmPreviewByNodeID: dmPreviewByNodeID,
                groupKey: groupKey,
                logAsTrustedContact: false
            )
        }

        let preview = conversationPreview(for: latestInboxItem)

        #if DEBUG
        print(
            "[InboundPreviewSource] groupKey=\(groupKey) nodeID=nil " +
            "source=\(DirectMessageTranscriptProjection.InboundPreviewSource.rawInboxFallback.rawValue) preview=\(preview)"
        )
        #endif

        return preview
    }

    private func conversationPreview(for item: ExchangeInboxItem) -> String {
        let bodyPreview = clean(item.metadata["body_preview"])
        if !bodyPreview.isEmpty { return cleanDebugText(bodyPreview, fallback: "New message") }
        let summary = clean(item.visibleSummary)
        if !summary.isEmpty { return cleanDebugText(summary, fallback: "New message") }
        let subjectPreview = clean(item.metadata["subject_preview"])
        if !subjectPreview.isEmpty { return cleanDebugText(subjectPreview, fallback: "New message") }
        return "New message"
    }

    private func resolvedDisplayName(
        for items: [ExchangeInboxItem],
        counterpartyNodeID: String?,
        profileSummary: (displayName: String?, avatarURL: String?)?
    ) -> String {
        if let profileName = profileSummary?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !profileName.isEmpty,
           !looksLikeNodeID(profileName) {
            return profileName
        }

        if let sender = items
            .compactMap({ nonBlank($0.senderDisplayName) })
            .first(where: { !looksLikeNodeID($0) }) {
            return sender
        }

        if let node = counterpartyNodeID {
            return compactNodeID(node)
        }

        if let threadID = items.compactMap(\.threadID).first {
            return "Thread \(String(threadID.uuidString.prefix(8)))"
        }

        return "Unknown sender"
    }

    /// Nonisolated static helper so DM preview grouping can be passed to `buildInboundPreviewByGroupKey`
    /// as a `@Sendable` closure (View types are MainActor-isolated by default in Swift 6).
    nonisolated private static func conversationGroupKey(for item: ExchangeInboxItem) -> String {
        if let sender = Self.nonBlank(item.senderNodeID) {
            return "node:\(sender.lowercased())"
        }
        if let threadID = item.threadID {
            return "thread:\(threadID.uuidString.lowercased())"
        }
        return "item:\(item.id.uuidString.lowercased())"
    }

    private func conversationGroupKey(for item: ExchangeInboxItem) -> String {
        Self.conversationGroupKey(for: item)
    }

    private func notificationMatchesInboundConversation(
        _ n: SecretaryNotification,
        groupKey: String,
        linkedThreadID: ExchangeThread.ID?,
        counterpartyNodeID: String?
    ) -> Bool {
        guard SecretaryNotificationKind.inboundMessagingUnreadSurface.contains(n.kind) else { return false }
        if n.inboundMessagingAttentionKey == groupKey { return true }
        if let lt = linkedThreadID, let tid = n.threadID, lt == tid { return true }
        if let cn = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !cn.isEmpty,
           let tn = n.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !tn.isEmpty,
           cn.lowercased() == tn.lowercased() {
            return true
        }
        return false
    }

    private func compactNodeID(_ nodeID: String) -> String {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(6))"
    }

    nonisolated private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonBlank(_ value: String?) -> String? {
        Self.nonBlank(value)
    }

    private func cleanDebugText(_ raw: String, fallback: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return fallback }

        let lower = value.lowercased()

        let blockedFragments = [
            "deterministic pass",
            "insufficient structured data",
            "targeted facts",
            "not confidently resolved",
            "escalation required",
            "node-",
            "inquiry not confidently",
            "malformed",
            "unsupported payload"
        ]

        if blockedFragments.contains(where: { lower.contains($0) }) {
            return fallback
        }

        if value.count > 240 {
            return String(value.prefix(237)) + "…"
        }

        return value
    }

    private func looksLikeNodeID(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("node-") || lower.contains("node-")
    }

    private func needsReview(_ item: ExchangeInboxItem) -> Bool {
        switch item.processingState {
        case .received, .deferred, .awaitingOrderingGapResolution:
            return true
        case .duplicateIgnored, .reconciledIntoThread, .rejected, .archived:
            return false
        }
    }

    private func initials(from value: String) -> String {
        let pieces = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let result = String(pieces).uppercased()
        return result.isEmpty ? "IN" : result
    }

    @ViewBuilder
    private func contactRequestAvatar(_ request: ExchangeModels.ContactRequestItem) -> some View {
        if let raw = request.avatarImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    SecretaryPhotoOrb(
                        initials: initials(from: request.displayName),
                        systemImage: "person.badge.plus",
                        style: .warning,
                        size: 40
                    )
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().stroke(SecretaryTheme.darkStroke.opacity(0.95), lineWidth: 1))
        } else {
            SecretaryPhotoOrb(
                initials: initials(from: request.displayName),
                systemImage: "person.badge.plus",
                style: .warning,
                size: 40
            )
        }
    }
}
