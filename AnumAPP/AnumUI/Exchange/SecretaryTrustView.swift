import SwiftUI
import AnumCore

struct SecretaryTrustView: View {
    struct TrustedPathLaunch: Hashable, Sendable {
        let title: String
        let summary: String
        let examples: [String]
        let linkedThreadID: ExchangeThread.ID?
        let trustedNodeID: String
        let trustedNodeDisplayName: String
    }

    private struct TrustedCardSummaryPack {
        let text: String
        /// When true, omit provenance-only trust-edge notes from detail examples.
        let suppressProvenanceDetail: Bool
    }

    private struct TrustedRow: Identifiable {
        let node: ExchangeModels.TrustedNodeItem
        let title: String
        let subtitle: String
        let detailExamples: [String]
        let relativeTimeText: String
        let latestTimestamp: Date?
        let isDirect: Bool
        let isWarm: Bool
        let isActive: Bool
        let avatarURL: String?
        let avatarInitial: String
        let publicSupporterPresentation: ExchangeSupporterPresentation?
        let contactRelationshipLabel: String?

        var id: String { node.nodeID }
        var updatedAt: Date { node.lastConfirmedAt ?? .distantPast }
    }

    private struct TrustProjection {
        let rows: [TrustedRow]

        static let empty = TrustProjection(rows: [])
    }

    private struct ContactContextSheetItem: Identifiable {
        let nodeID: String
        let displayName: String
        var id: String { nodeID }
    }

    @EnvironmentObject private var services: AppServices

    let isTabActive: Bool

    let onOpenDirectMessage: (_ nodeID: String, _ displayName: String, _ linkedThreadID: ExchangeThread.ID?) -> Void
    let onAskSecretaryAboutTrustedNode: (ExchangeModels.TrustedNodeItem) -> Void

    @State private var trustedNodes: [ExchangeModels.TrustedNodeItem] = []
    @State private var projection = TrustProjection.empty
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorText: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var showAddContactSheet = false
    @State private var contactContextByNodeID: [String: ExchangeModels.ContactContext] = [:]
    @State private var editingContactContextItem: ContactContextSheetItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if shouldShowFirstLoad {
                    UnifyDarkLoadingView(
                        title: "Opening trusted paths.",
                        subtitle: "Checking saved contacts and relationship routes."
                    )
                } else {
                    trustSummaryCard

                    if let errorText, projection.rows.isEmpty {
                        UnifyDarkStateCard(
                            title: "I couldn’t open trusted paths.",
                            message: errorText,
                            systemImage: "exclamationmark.triangle",
                            minHeight: 170
                        )
                    } else if projection.rows.isEmpty {
                        emptyTrustCard
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(projection.rows) { row in
                                trustedContactRow(row)
                                if row.id != projection.rows.last?.id {
                                    Divider()
                                        .overlay(SecretaryTheme.darkStroke.opacity(0.55))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await load(showSpinner: true)
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            scheduleLoad(delayNanoseconds: 0)
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            scheduleLoad(delayNanoseconds: 0)
        }
        .onChange(of: services.secretaryRefreshID) { _, _ in
            guard isTabActive else { return }
            scheduleLoad(delayNanoseconds: 100_000_000)
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryWorkspaceShouldRefresh)) { _ in
            guard isTabActive else { return }
            scheduleLoad(delayNanoseconds: 120_000_000)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .sheet(isPresented: $showAddContactSheet) {
            SecretaryAddTrustedContactSheet { nodeID, displayName, action in
                scheduleLoad(delayNanoseconds: 0)
                if action == .addedLocal, let nodeID, !nodeID.isEmpty {
                    onOpenDirectMessage(nodeID, displayName ?? nodeID, nil)
                }
            }
            .environmentObject(services)
        }
        .sheet(item: $editingContactContextItem) { item in
            SecretaryContactContextSheet(
                remoteNodeID: item.nodeID,
                displayName: item.displayName
            ) { saved in
                contactContextByNodeID[saved.remoteNodeID] = saved
                #if DEBUG
                print("[ContactContextProjection] surface=trusted nodeID=\(saved.remoteNodeID) relationship=\(saved.relationshipType.rawValue) goal=\(saved.relationshipGoal.rawValue)")
                #endif
            }
            .environmentObject(services)
        }
    }

    private var shouldShowFirstLoad: Bool {
        !hasLoadedOnce && trustedNodes.isEmpty && errorText == nil
    }

    // MARK: - Summary

    @ViewBuilder
    private func trustDarkCard<Content: View>(
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private var trustSummaryCard: some View {
        trustDarkCard {
            HStack(alignment: .center, spacing: 13) {
                SecretaryPhotoOrb(
                    initials: "T",
                    systemImage: "person.2",
                    style: .neutral,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trusted paths")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text(trustDeskLine)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                }

                Spacer(minLength: 0)

                Button {
                    showAddContactSheet = true
                } label: {
                    Text("+ Add Contact")
                        .font(
                            .system(
                                size: SecretaryHumanLabelLayout.textFontSize,
                                weight: SecretaryHumanLabelLayout.textWeight
                            )
                        )
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, SecretaryHumanLabelLayout.paddingHorizontal)
                        .padding(.vertical, SecretaryHumanLabelLayout.paddingVertical)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.darkOrange.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add trusted contact")
            }
        }
    }

    private var trustDeskLine: String {
        if projection.rows.isEmpty {
            return "No trusted contacts are saved yet."
        }

        return "\(projection.rows.count) trusted contact\(projection.rows.count == 1 ? "" : "s") saved."
    }

    // MARK: - Empty

    private var emptyTrustCard: some View {
        UnifyDarkStateCard(
            title: emptyTitle,
            message: emptyMessage,
            systemImage: "person.2",
            minHeight: 170
        )
    }

    private var emptyTitle: String {
        "No trusted contacts yet."
    }

    private var emptyMessage: String {
        "When you save a useful contact or route, it will appear here."
    }

    // MARK: - Cards

    private func trustedContactRow(_ row: TrustedRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                #if DEBUG
                print(
                    "[TrustedRowTapRoute] nodeID=\(row.node.nodeID) action=openDirectMessage existingThreadID=nil"
                )
                #endif
                onOpenDirectMessage(row.node.nodeID, row.title, nil)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    trustedAvatarView(row: row)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)

                        if let label = row.contactRelationshipLabel {
                            Text(label)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                                .lineLimit(1)
                        }

                        Text(row.subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if !row.relativeTimeText.isEmpty {
                        Text(row.relativeTimeText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            #if DEBUG
            .onAppear {
                print(
                    "[TrustedInfoControlRemoved] rowID=\(row.node.nodeID) nodeID=\(row.node.nodeID)"
                )
            }
            #endif

            Button {
                editingContactContextItem = ContactContextSheetItem(
                    nodeID: row.node.nodeID,
                    displayName: row.title
                )
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit contact context")
        }
    }

    /// Dark shell: avoid `.success` (reads as “green lane” elsewhere); use neutral + orange-adjacent `.warning` only for motion/warmth.
    private func rowStyle(_ row: TrustedRow) -> SecretaryStateChip.Style {
        if row.isWarm || row.isActive { return .warning }
        return .neutral
    }

    @ViewBuilder
    private func trustedAvatarView(row: TrustedRow) -> some View {
        GuardianCrownAvatarFrame(
            showsCrown: row.publicSupporterPresentation?.showsGuardianCrown == true,
            avatarDiameter: 46,
            debugSurface: "trustedNode",
            debugNodeID: row.node.nodeID,
            debugProfileID: nil
        ) {
            if let avatarURL = row.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !avatarURL.isEmpty,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        SecretaryPhotoOrb(
                            initials: row.avatarInitial,
                            systemImage: "person.crop.circle",
                            style: rowStyle(row),
                            size: 46
                        )
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                )
            } else {
                SecretaryPhotoOrb(
                    initials: row.avatarInitial,
                    systemImage: "person.crop.circle",
                    style: rowStyle(row),
                    size: 46
                )
            }
        }
    }

    private func initials(from value: String) -> String {
        let pieces = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let result = String(pieces).uppercased()
        return result.isEmpty ? "T" : result
    }

    // MARK: - Loading

    @MainActor
    private func scheduleLoad(
        delayNanoseconds: UInt64 = 200_000_000
    ) {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Trust active=false skip=loadTrustedNodes " +
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
            await load(showSpinner: false)
        }
    }

    @MainActor
    private func load(showSpinner: Bool = true) async {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Trust active=false skip=loadTrustedNodes " +
                "reason=hiddenRetainedMount"
            )
            #endif
            return
        }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Trust active=true load=trustedNodes " +
            "reason=becameActive"
        )
        #endif

        if !hasLoadedOnce && trustedNodes.isEmpty {
            isLoading = true
        } else if showSpinner && trustedNodes.isEmpty {
            isLoading = true
        }

        errorText = nil

        do {
            guard let sourceNodeID = await services.exchangeNodeID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !sourceNodeID.isEmpty else {
                trustedNodes = []
                projection = .empty
                errorText = "Your local Exchange node is not ready yet."
                hasLoadedOnce = true
                isLoading = false
                return
            }

            let nodes = try await services.exchangeFacade.listTrustedNodes(
                sourceNodeID: sourceNodeID
            )

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            let contextMap = services.listContactContextsByNodeID(nodeIDs: nodes.map(\.nodeID))
            let nodeIDs = nodes.map(\.nodeID)
            let counterpartyAvatars =
                (try? await services.exchangeFacade.listCounterpartyProfileImageURLs(
                    nodeIDs: nodeIDs
                )) ?? [:]
            let counterpartySupporters =
                (try? await services.exchangeFacade.listCounterpartySupporterPresentations(
                    nodeIDs: nodeIDs
                )) ?? [:]

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            trustedNodes = nodes
            contactContextByNodeID = contextMap
            projection = buildProjection(
                nodes: nodes,
                contextsByNodeID: contextMap,
                counterpartyAvatarByNodeID: counterpartyAvatars,
                counterpartySupporterByNodeID: counterpartySupporters
            )
            #if DEBUG
            print(
                "[TrustedContactProjection] count=\(projection.rows.count) withAvatar=\(projection.rows.filter { $0.avatarURL != nil }.count) withSummary=\(projection.rows.filter { !$0.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) latestConfirmed=\(projection.rows.compactMap(\.latestTimestamp).max()?.description ?? "nil")"
            )
            #endif
            errorText = nil
            hasLoadedOnce = true
            isLoading = false
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            errorText = error.localizedDescription
            projection = buildProjection(
                nodes: trustedNodes,
                contextsByNodeID: contactContextByNodeID,
                counterpartyAvatarByNodeID: [:],
                counterpartySupporterByNodeID: [:]
            )
            hasLoadedOnce = true
            isLoading = false
        }
    }

    private func buildProjection(
        nodes: [ExchangeModels.TrustedNodeItem],
        contextsByNodeID: [String: ExchangeModels.ContactContext],
        counterpartyAvatarByNodeID: [String: String],
        counterpartySupporterByNodeID: [String: ExchangeSupporterPresentation]
    ) -> TrustProjection {
        let rows = nodes
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastConfirmedAt ?? .distantPast
                let rhsDate = rhs.lastConfirmedAt ?? .distantPast

                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .map { node in
                makeRow(
                    from: node,
                    contactContext: contextsByNodeID[node.nodeID],
                    counterpartyAvatarByNodeID: counterpartyAvatarByNodeID,
                    counterpartySupporterByNodeID: counterpartySupporterByNodeID
                )
            }

        return TrustProjection(rows: rows)
    }

    private func makeRow(
        from node: ExchangeModels.TrustedNodeItem,
        contactContext: ExchangeModels.ContactContext?,
        counterpartyAvatarByNodeID: [String: String],
        counterpartySupporterByNodeID: [String: ExchangeSupporterPresentation]
    ) -> TrustedRow {
        let relationship = userFacingRelationshipLabel(node.relationshipType)
        let scopes = scopeLabels(node.scopes)
        let isDirect = isDirectTrust(node)
        let isWarm = isWarmTrust(node)
        let isActive = isActiveTrust(node)

        let displayTimeSource: String
        let displayTimeDate: Date?
        if let confirmed = node.lastConfirmedAt {
            displayTimeSource = "lastConfirmedAt"
            displayTimeDate = confirmed
        } else if let surfaceAt = node.publicProfileUpdatedAt {
            displayTimeSource = "publicProfileUpdatedAt"
            displayTimeDate = surfaceAt
        } else {
            displayTimeSource = "none"
            displayTimeDate = nil
        }

        let relativeTimeText: String = {
            guard let date = displayTimeDate else { return "" }
            return SecretaryRelativeTime.string(from: date)
        }()

        let latestTimestamp = node.lastConfirmedAt

        let title = humanTrustedTitle(for: node)
        let summaryPack = trustedCardSummaryPack(
            node: node,
            scopes: scopes,
            isDirect: isDirect,
            isWarm: isWarm
        )
        let subtitle = summaryPack.text

        let detailExamples = trustExamples(
            node: node,
            relationship: relationship,
            scopes: scopes,
            isDirect: isDirect,
            isWarm: isWarm,
            suppressProvenanceDetail: summaryPack.suppressProvenanceDetail
        )

        #if DEBUG
        print(
            "[TrustView][ResolvedRow] nodeID=\(node.nodeID) " +
                "title=\(title) summary=\(summaryPack.text) " +
                "linkedThreadTitle=nil " +
                "publicPrimaryOfferLine=\(node.publicPrimaryOfferLine ?? "nil") " +
                "preferredOfferID=\(node.preferredOfferID ?? "nil") " +
                "publicHeadline=\(node.publicHeadline ?? "nil") " +
                "publicSummaryLine=\(node.publicSummaryLine ?? "nil") " +
                "publicIntroLine=\(node.publicIntroLine ?? "nil") " +
                "displayNameDTO=\(node.displayName) " +
                "hasPublicSurface=\(node.hasPublicSurface)"
        )
        #endif

        #if DEBUG
        print(
            "[TrustedContactOnlyProjection] nodeID=\(node.nodeID) title=\(title) summary=\(subtitle) hasMessageButton=false hasUnreadBadge=false usesMessagePreview=false"
        )
        #endif

        let trimmedDTOImage = node.publicImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dtoImage = trimmedDTOImage.isEmpty ? nil : trimmedDTOImage
        let mapTrimmed = counterpartyAvatarByNodeID[node.nodeID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mapImage = mapTrimmed.isEmpty ? nil : mapTrimmed
        let resolvedAvatarURL = dtoImage ?? mapImage
        let supporterPresentation =
            counterpartySupporterByNodeID[node.nodeID]
            ?? counterpartySupporterByNodeID[node.nodeID.lowercased()]

        #if DEBUG
        let avatarSource: String = {
            if dtoImage != nil { return "publicProfileDTO" }
            if mapImage != nil { return "counterpartyLookup" }
            return "fallback"
        }()
        print(
            "[TrustedAvatarBasis] nodeID=\(node.nodeID) hasProfileImage=\(resolvedAvatarURL != nil) source=\(avatarSource)"
        )
        print(
            "[TrustedTimeBasis] nodeID=\(node.nodeID) timeSource=\(displayTimeSource) timestamp=\(displayTimeDate.map { "\($0)" } ?? "nil")"
        )
        print(
            "[ContactAvatarProjection] surface=trusted nodeID=\(node.nodeID) hasProfile=\(node.hasPublicProfileForMessaging) hasAvatar=\(resolvedAvatarURL != nil) source=\(avatarSource)"
        )
        #endif

        return TrustedRow(
            node: node,
            title: title,
            subtitle: subtitle,
            detailExamples: detailExamples,
            relativeTimeText: relativeTimeText,
            latestTimestamp: latestTimestamp,
            isDirect: isDirect,
            isWarm: isWarm,
            isActive: isActive,
            avatarURL: resolvedAvatarURL,
            avatarInitial: initials(from: title),
            publicSupporterPresentation: supporterPresentation,
            contactRelationshipLabel: relationshipLabel(for: contactContext)
        )
    }

    private func relationshipLabel(for context: ExchangeModels.ContactContext?) -> String? {
        guard let context else { return nil }
        let label: String
        switch context.relationshipType {
        case .friend: label = "Friend"
        case .client: label = "Client"
        case .colleague: label = "Colleague"
        case .supplier: label = "Supplier"
        case .family: label = "Family"
        case .investor: label = "Investor"
        case .broker: label = "Broker"
        case .contractor: label = "Contractor"
        case .lead: label = "Lead"
        case .professionalContact: label = "Professional"
        case .custom:
            label = context.customRelationshipLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Custom"
        }
        #if DEBUG
        print("[ContactContextProjection] surface=trusted nodeID=\(context.remoteNodeID) relationship=\(context.relationshipType.rawValue) goal=\(context.relationshipGoal.rawValue)")
        #endif
        return label
    }

    private func humanTrustedTitle(for node: ExchangeModels.TrustedNodeItem) -> String {
        if let pub = trustedVisibleLine(node.publicDisplayName),
           !looksLikeNodeID(pub) {
            return pub
        }

        let displayName = node.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty,
           !looksLikeNodeID(displayName),
           !looksDebuggy(displayName),
           !isProvenanceNote(displayName),
           !looksGenericTrustedTitle(displayName) {
            return displayName
        }

        if let offer = trustedVisibleLine(node.publicPrimaryOfferLine),
           !looksLikeNodeID(offer) {
            return clampLineForTrustedTitle(offer)
        }

        if let headline = trustedVisibleLine(node.publicHeadline),
           !looksLikeNodeID(headline) {
            return clampLineForTrustedTitle(headline)
        }

        return humanTrustedRelationshipFallbackTitle(node.relationshipType)
    }

    /// True for relationship-scale placeholders that must not suppress richer identity (offers / thread titles).
    private func looksGenericTrustedTitle(_ value: String) -> Bool {
        let t = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let generics: Set<String> = [
            "trusted contact",
            "trusted friend",
            "trusted family contact",
            "trusted colleague",
            "trusted client",
            "trusted provider",
            "trusted collaborator",
            "known contact",
            "saved contact"
        ]
        return generics.contains(t)
    }

    private func humanTrustedRelationshipFallbackTitle(
        _ relationshipType: ExchangeTrustEdge.RelationshipType
    ) -> String {
        switch relationshipType {
        case .friend:
            return "Trusted friend"
        case .family:
            return "Trusted family contact"
        case .colleague:
            return "Trusted colleague"
        case .client:
            return "Trusted client"
        case .provider:
            return "Trusted provider"
        case .collaborator:
            return "Trusted collaborator"
        case .knownContact:
            return "Known contact"
        case .preferredNode:
            return "Trusted contact"
        case .other:
            return "Trusted contact"
        }
    }

    private func clampLineForTrustedTitle(_ value: String, maxCharacters: Int = 72) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxCharacters else { return t }
        let endIdx = t.index(t.startIndex, offsetBy: max(1, maxCharacters - 1))
        return String(t[..<endIdx]) + "…"
    }

    private func userFacingRelationshipLabel(
        _ relationshipType: ExchangeTrustEdge.RelationshipType
    ) -> String {
        switch relationshipType {
        case .friend:
            return "Friend"
        case .family:
            return "Family"
        case .colleague:
            return "Colleague"
        case .client:
            return "Client"
        case .provider:
            return "Provider"
        case .collaborator:
            return "Collaborator"
        case .knownContact:
            return "Known contact"
        case .preferredNode:
            return "Saved contact"
        case .other:
            return "Trusted contact"
        }
    }

    private func trustedCardSummaryPack(
        node: ExchangeModels.TrustedNodeItem,
        scopes: [String],
        isDirect: Bool,
        isWarm: Bool
    ) -> TrustedCardSummaryPack {
        if let headline = trustedVisibleLine(node.publicHeadline) {
            return TrustedCardSummaryPack(text: headline, suppressProvenanceDetail: true)
        }

        if let summaryLine = trustedVisibleLine(node.publicSummaryLine) {
            return TrustedCardSummaryPack(text: summaryLine, suppressProvenanceDetail: true)
        }

        if let intro = trustedVisibleLine(node.publicIntroLine) {
            return TrustedCardSummaryPack(text: intro, suppressProvenanceDetail: true)
        }

        if let offer = trustedVisibleLine(node.publicPrimaryOfferLine) {
            return TrustedCardSummaryPack(text: offer, suppressProvenanceDetail: true)
        }

        for slice in [node.publicOpenToLine, node.publicRegionLine, node.publicActivityLine] {
            if let line = trustedVisibleLine(slice) {
                return TrustedCardSummaryPack(text: line, suppressProvenanceDetail: true)
            }
        }

        if !scopes.isEmpty {
            return TrustedCardSummaryPack(
                text: "Useful for \(scopes.prefix(3).joined(separator: ", ")).",
                suppressProvenanceDetail: true
            )
        }

        if let note = Self.nonBlankTrimmed(node.note),
           !looksDebuggy(note),
           !looksLikeNodeID(note),
           !isProvenanceNote(note) {
            return TrustedCardSummaryPack(text: note, suppressProvenanceDetail: false)
        }

        if isDirect {
            return TrustedCardSummaryPack(text: "Saved as a direct trusted route.", suppressProvenanceDetail: false)
        }

        if isWarm {
            return TrustedCardSummaryPack(text: "Saved as a warm relationship path.", suppressProvenanceDetail: false)
        }

        return TrustedCardSummaryPack(text: "Saved as a trusted contact.", suppressProvenanceDetail: false)
    }

    private func trustExamples(
        node: ExchangeModels.TrustedNodeItem,
        relationship: String,
        scopes: [String],
        isDirect: Bool,
        isWarm: Bool,
        suppressProvenanceDetail: Bool
    ) -> [String] {
        var values: [String] = []

        if isDirect {
            values.append("This contact can be treated as a direct trusted route.")
        } else if isWarm {
            values.append("This contact has warm-route context.")
        } else {
            values.append("This contact is saved as trusted.")
        }

        values.append("Relationship: \(relationship)")

        if !scopes.isEmpty {
            values.append("Useful for \(scopes.prefix(3).joined(separator: ", ")).")
        }

        if node.isMutual {
            values.append("The relationship is marked as mutual.")
        }

        if node.trustedByYourTrustedCount > 0 {
            values.append("\(node.trustedByYourTrustedCount) trusted bridge\(node.trustedByYourTrustedCount == 1 ? "" : "s") may support warmer routing.")
        }

        if !suppressProvenanceDetail,
           let note = Self.nonBlankTrimmed(node.note),
           isProvenanceNote(note),
           !looksDebuggy(note) {
            values.append(note)
        }

        return dedupe(values)
    }
    
    private func trustedVisibleLine(_ value: String?) -> String? {
        guard let line = Self.nonBlankTrimmed(value) else { return nil }

        if looksLikeNodeID(line) { return nil }
        if looksDebuggy(line) { return nil }
        if isProvenanceNote(line) { return nil }

        return line
    }

    private func isDirectTrust(_ node: ExchangeModels.TrustedNodeItem) -> Bool {
        switch node.trustLevel {
        case .high:
            return true
        case .standard, .low:
            break
        }

        switch node.relationshipType {
        case .friend,
             .family,
             .colleague,
             .client,
             .provider,
             .collaborator,
             .knownContact,
             .preferredNode:
            return true

        case .other:
            return false
        }
    }

    private func isWarmTrust(_ node: ExchangeModels.TrustedNodeItem) -> Bool {
        if node.isMutual { return true }
        if node.trustedByYourTrustedCount > 0 { return true }
        if node.trustedByCount > 0 { return true }

        switch node.relationshipType {
        case .friend,
             .family,
             .collaborator,
             .knownContact:
            return true

        case .colleague,
             .client,
             .provider,
             .preferredNode,
             .other:
            return false
        }
    }

    private func isActiveTrust(_ node: ExchangeModels.TrustedNodeItem) -> Bool {
        guard let lastConfirmedAt = node.lastConfirmedAt else {
            return false
        }

        let days = Date().timeIntervalSince(lastConfirmedAt) / 86_400
        return days <= 30
    }

    private func scopeLabels(
        _ scopes: Set<ExchangeTrustEdge.TrustScope>
    ) -> [String] {
        scopes
            .map { scope in
                switch scope {
                case .generalCommunication:
                    return "communication"
                case .planning:
                    return "planning"
                case .introductions:
                    return "introductions"
                case .social:
                    return "social"
                case .sourcing:
                    return "sourcing"
                case .negotiation:
                    return "negotiation"
                case .scheduling:
                    return "scheduling"
                case .logistics:
                    return "logistics"
                case .sensitiveTopics:
                    return "sensitive topics"
                }
            }
            .sorted()
    }

    private func looksLikeNodeID(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("node-") || lower.contains("node-")
    }

    private func looksDebuggy(_ value: String) -> Bool {
        let lower = value.lowercased()

        return lower.contains("node-")
            || lower.contains("preferred node")
            || lower.contains("trust:")
            || lower.contains("trusted bridge")
            || lower.contains("standard trust")
            || lower.contains("deterministic pass")
            || lower.contains("insufficient structured data")
            || lower.contains("not confidently resolved")
            || lower.contains("escalation required")
            || lower.contains("targeted facts")
    }

    private func isProvenanceNote(_ value: String) -> Bool {
        let lower = value
            .lowercased()
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let phrases = [
            "opportunity review",
            "added from",
            "auto-added",
            "auto added",
            "imported from",
            "saved from",
            "created from",
            "compare flow",
            "review flow",
            "added after",
            "added during",
            "added via"
        ]

        return phrases.contains { lower.contains($0) }
    }

    private func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }

        return result
    }

    private static func nonBlankTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
