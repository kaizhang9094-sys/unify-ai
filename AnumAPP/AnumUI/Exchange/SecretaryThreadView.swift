import SwiftUI
import AnumCore

#if DEBUG
@inline(__always)
private func threadViewRefreshLog(_ message: @autoclosure () -> String) {
    Swift.print("[ThreadViewRefresh] \(message())")
}
#else
@inline(__always)
private func threadViewRefreshLog(_ message: @autoclosure () -> String) {}
#endif

/// Shared horizontal inset for thread detail so hero, conversation, and work cards share one rhythm.
private enum SecretaryThreadLayout {
    static let contentHorizontalPadding: CGFloat = 20
    static let sectionVerticalSpacing: CGFloat = 18
    /// One corner radius for thread work / section cards (hero uses the same large radius).
    static let detailCardCornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge
    /// Matches `UnifyMainTabScrollLayout.paddingBelowSafeArea` used by Profile / Threads scroll roots.
    static let pulledSurfaceScrollTopInsetBelowSafeArea: CGFloat = UnifyMainTabScrollLayout.paddingBelowSafeArea
    /// Photo-first pulled surface hero: target height range (width-driven clamp happens in `surfaceCard`).
}

struct SecretaryThreadView: View {
    @EnvironmentObject private var services: AppServices

    let threadID: ExchangeThread.ID
    let onBack: () -> Void
    let onOpenApprovalSheet: ((SecretaryApprovalSheet.Display) -> Void)?
    let onOpenRecoveryPanel: ((SecretaryRecoveryPanel.Display) -> Void)?
    let onOpenComparePanel: ((SecretaryComparePanel.Display) -> Void)?
    let onOpenClarification: ((ExchangeThread.ID) -> Void)?
    let onOpenThread: ((ExchangeThread.ID) -> Void)?

    @State private var detail: ExchangeModels.ThreadDetail?
    @State private var situation: ExchangeThreadSituation?
    @State private var providerDetailsCard: ExchangeProviderDetailsCardDisplay?
    @State private var providerDetailsPresentation: ThreadProviderDetailsPresentation?
    @State private var isLoading = false
    @State private var loadFailureCard: (title: String, message: String)?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration: Int = 0
    @State private var showArchiveConfirmation = false
    @State private var showMoreContext = false
    @State private var directMessageCompose: SecretaryDirectMessageComposeRoute?
    @State private var connectTarget: ExchangeFacade.ThreadConnectTarget?
    @State private var connectBusy = false
    @State private var connectResultMessage: String?
    @State private var outboundApproveBusy = false
    @State private var outboundApproveError: String?
    @State private var imageGalleryPresentation: SecretaryImageGalleryPresentation?
    /// Index into `surfaceImageURLsForHeroCard` for the hero image that actually loaded (AsyncImage success). Used so gallery opens the same URL as the visible hero, not always index 0.
    @State private var heroSuccessfulGalleryIndex: Int?
    /// Selected page when the hero shows multiple photos in a paging `TabView`.
    @State private var heroPagerIndex: Int = 0

    init(
        threadID: ExchangeThread.ID,
        onBack: @escaping () -> Void,
        onOpenApprovalSheet: ((SecretaryApprovalSheet.Display) -> Void)? = nil,
        onOpenRecoveryPanel: ((SecretaryRecoveryPanel.Display) -> Void)? = nil,
        onOpenComparePanel: ((SecretaryComparePanel.Display) -> Void)? = nil,
        onOpenClarification: ((ExchangeThread.ID) -> Void)? = nil,
        onOpenThread: ((ExchangeThread.ID) -> Void)? = nil
    ) {
        self.threadID = threadID
        self.onBack = onBack
        self.onOpenApprovalSheet = onOpenApprovalSheet
        self.onOpenRecoveryPanel = onOpenRecoveryPanel
        self.onOpenComparePanel = onOpenComparePanel
        self.onOpenClarification = onOpenClarification
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        ZStack(alignment: .top) {
            UnifyDarkBackground(showsSubtleVignette: true)

            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: SecretaryThreadLayout.sectionVerticalSpacing) {
                        if isLoading && detail == nil {
                            UnifyDarkLoadingView(
                                title: "Opening the thread.",
                                subtitle: ""
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let failure = loadFailureCard, detail == nil {
                            loadFailureView(failure)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let detail {
                            surfaceCard(detail)

                            if let postApprovalNotice = SecretaryProjectionEngine.threadViewOutstandingPostApprovalNoticeLine(for: detail) {
                                Text(postApprovalNotice)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if detail.thread.threadRole == .umbrellaSearch,
                               !detail.coordinationChildren.isEmpty {
                                umbrellaCoordinationResultsSection(detail)
                            }

                            conversationSection(detail)

                            if showDraftOrPreparedMessage(detail) {
                                draftOrPreparedMessageCard(detail)
                            }

                            requesterAssessmentSection(detail)

                            if showProviderAssessment(detail) {
                                providerAssessmentCard(detail)
                            }

                            if threadViewShouldShowApprovalRequiredCard(detail) {
                                approvalRequiredCard(detail)
                            }

                            if showDeliveryFailure(detail) {
                                deliveryFailureCard(detail)
                            }
                            autonomousSendAuditTraceSection(detail)
                        }
                    }
                    .padding(.horizontal, SecretaryThreadLayout.contentHorizontalPadding)
                    .padding(
                        .top,
                        geo.safeAreaInsets.top + SecretaryThreadLayout.pulledSurfaceScrollTopInsetBelowSafeArea
                    )
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await services.exchangeSyncEngine.runPass(
                        trigger: .manualRefresh,
                        now: Date()
                    )
                    await load(showSpinner: true, source: "pullToRefresh")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: threadID) {
            showMoreContext = false
            providerDetailsPresentation = nil
            await services.exchangeSyncEngine.runPass(
                trigger: .appBecameActive,
                now: Date()
            )
            scheduleLoad(delayNanoseconds: 0, source: "taskThreadID")
        }
        .onChange(of: services.secretaryRefreshID) { _, _ in
            // Coalesced desk refresh (e.g. federation sync / silent push): reload open thread without list churn.
            scheduleLoad(delayNanoseconds: 0, source: "secretaryRefreshID")
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryWorkspaceShouldRefresh)) { notification in
            let shouldReload = shouldReloadForSecretaryWorkspaceRefresh(notification)
            #if DEBUG
            let payloadKeys = (notification.userInfo?.keys.map { "\($0)" } ?? []).sorted().joined(separator: ",")
            threadViewRefreshLog(
                "source=secretaryWorkspaceShouldRefresh thread=\(threadID.uuidString) shouldReload=\(shouldReload) payloadKeys=\(payloadKeys.isEmpty ? "none" : payloadKeys)"
            )
            #endif
            guard shouldReload else { return }
            scheduleLoad(delayNanoseconds: 0, source: "secretaryWorkspaceShouldRefresh")
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .alert("Outbound send", isPresented: Binding(
            get: { outboundApproveError != nil },
            set: { if !$0 { outboundApproveError = nil } }
        )) {
            Button("OK", role: .cancel) { outboundApproveError = nil }
        } message: {
            Text(outboundApproveError ?? "")
        }
        .alert("Connect", isPresented: Binding(
            get: { connectResultMessage != nil },
            set: { if !$0 { connectResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { connectResultMessage = nil }
        } message: {
            Text(connectResultMessage ?? "")
        }
        .confirmationDialog(
            archiveConfirmationTitle,
            isPresented: $showArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(archiveConfirmationButtonTitle, role: .destructive) {
                guard let d = detail else { return }
                Task {
                    await archiveThreadFromDetail(d)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(archiveConfirmationMessage)
        }
        .fullScreenCover(item: $imageGalleryPresentation) { presentation in
            SecretaryImageGalleryViewer(presentation: presentation) {
                imageGalleryPresentation = nil
            }
        }
        .sheet(item: $directMessageCompose) { route in
            SecretaryDirectMessageComposeSheet(
                displayName: route.displayName,
                nodeID: route.nodeIDForTrustedSend,
                onSend: { messageBody in
                    let isDirectMessageThread = detail?.thread.metadata["direct_message_thread"] == "true"
                    let isInboundThread = detail?.thread.metadata["inbound_thread"] == "true"
                    let usesDirectMessagePipeline = isDirectMessageThread == true && !isInboundThread
                    #if DEBUG
                    Swift.print(
                        "[ConversationCardSend] threadID=\(threadID.uuidString) " +
                            "isDirectMessageThread=\(usesDirectMessagePipeline) isInboundThread=\(isInboundThread) " +
                            "route=\(usesDirectMessagePipeline ? "directMessage" : (isInboundThread ? "inboundReply" : "sameThread")) " +
                            "bodyChars=\(messageBody.trimmingCharacters(in: .whitespacesAndNewlines).count)"
                    )
                    #endif

                    if usesDirectMessagePipeline {
                        let routeTrusted = route.trustedNodeID?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let trustedID: String? = routeTrusted.isEmpty
                            ? detail.flatMap { SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: $0) }
                            : routeTrusted
                        guard let trustedID else {
                            throw ExchangeStoreError.storageFailure(
                                reason: "No trusted contact is available for direct message on this thread."
                            )
                        }
                        return try await services.exchangeFacade.sendManualMessageToTrustedNode(
                            trustedNodeID: trustedID,
                            existingThreadID: threadID,
                            subject: nil,
                            body: messageBody,
                            now: Date()
                        )
                    }
                    if isInboundThread {
                        return try await services.exchangeFacade.sendInboundProviderManualReply(
                            existingThreadID: threadID,
                            subject: nil,
                            body: messageBody,
                            now: Date()
                        )
                    }
                    let passedTarget = route.trustedNodeID?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let targetCounterpartyID: String? = (passedTarget?.isEmpty == false) ? passedTarget : nil
                    return try await services.exchangeFacade.sendManualConversationMessageOnThread(
                        threadID: threadID,
                        targetCounterpartyID: targetCounterpartyID,
                        subject: nil,
                        body: messageBody,
                        now: Date()
                    )
                },
                onSuccess: { _ in
                    directMessageCompose = nil
                    NotificationCenter.default.post(
                        name: .secretaryWorkspaceShouldRefresh,
                        object: nil,
                        userInfo: ["threadID": threadID.uuidString]
                    )
                    Task {
                        await load(showSpinner: false, source: "conversationCardSendSuccess")
                        await services.exchangeSyncEngine.runPass(
                            trigger: .afterApprovalGranted,
                            now: Date()
                        )
                    }
                },
                onCancel: {
                    directMessageCompose = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
    }

    // MARK: - Load failure

    private func loadFailureView(_ failure: (title: String, message: String)) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            backButton

            UnifyDarkStateCard(
                title: failure.title,
                message: failure.message,
                systemImage: "exclamationmark.triangle",
                minHeight: 180
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thread detail glass chrome (local)

    @ViewBuilder
    private func threadGlassCircleBackground(diameter: CGFloat, strokeOpacity: Double = 0.85) -> some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(SecretaryTheme.darkStroke.opacity(strokeOpacity), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func threadGlassCapsuleBackground() -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func threadGlassRoundedRectangleBackground(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .frame(width: 38, height: 38)
                .background {
                    threadGlassCircleBackground(diameter: 38, strokeOpacity: 0.85)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dark premium chrome (thread detail)

    @ViewBuilder
    private func threadDarkWorkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryThreadLayout.detailCardCornerRadius,
        emphasizeAttention: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()

        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                // ScrollView + VStack can propose a loose width; force thread sub-cards to the same full width.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
        .overlay {
            if emphasizeAttention {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.42), lineWidth: 1.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func threadDarkStatusPill(
        label: String,
        systemImage: String,
        chipStyle: SecretaryStateChip.Style
    ) -> some View {
        let attention =
            chipStyle == .warning ||
            chipStyle == .blocked ||
            chipStyle == .active

        return HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(attention ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            if attention {
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.55))
            } else {
                threadGlassCapsuleBackground()
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    attention
                    ? SecretaryTheme.darkOrange.opacity(0.38)
                    : SecretaryTheme.darkStroke.opacity(0.65),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func threadDarkFocusIcon(systemImage: String, chipStyle: SecretaryStateChip.Style, size: CGFloat = 40) -> some View {
        let warm = chipStyle == .warning || chipStyle == .blocked || chipStyle == .active

        let plateCorner = size * 0.38
        ZStack {
            Group {
                if warm {
                    RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                        .fill(SecretaryTheme.darkOrangeSoft.opacity(0.5))
                } else {
                    RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.85))
                        .background {
                            RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: plateCorner, style: .continuous))
                }
            }

            Image(systemName: systemImage)
                .font(.system(size: max(14, size * 0.38), weight: .semibold))
                .foregroundStyle(
                    (chipStyle == .warning || chipStyle == .blocked)
                    ? SecretaryTheme.darkOrange
                    : SecretaryTheme.darkMutedText
                )
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
        )
    }

    private func threadDarkThumbnailOrb(
        initials: String,
        systemImage: String,
        style: SecretaryStateChip.Style,
        size: CGFloat
    ) -> some View {
        let accent = style == .warning || style == .blocked || style == .active
        return ZStack {
            ZStack {
                Circle()
                    .fill(SecretaryTheme.darkGlass.opacity(0.85))
                    .frame(width: size, height: size)
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: size, height: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if accent {
                Circle()
                    .stroke(SecretaryTheme.darkOrange.opacity(0.45), lineWidth: 1.5)
                    .frame(width: size, height: size)
            }
            if !systemImage.isEmpty {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(accent ? SecretaryTheme.darkOrange : SecretaryTheme.darkPrimaryText)
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - State

    private enum ThreadStage {
        case needsApproval
        case needsAnswer
        case needsCare
        case readyToReview
        case waiting
        case moving
    }

    private func visibleSurfaceStatus(for detail: ExchangeModels.ThreadDetail) -> SecretaryProjectionEngine.ExchangeVisibleThreadStatus {
        SecretaryProjectionEngine.visibleThreadStatus(for: detail)
    }

    /// Maps unified visible status into the older `ThreadStage` switch used by focus content and layout.
    private func stage(for detail: ExchangeModels.ThreadDetail) -> ThreadStage {
        derivedLegacyThreadStage(visibleSurfaceStatus(for: detail), detail: detail)
    }

    private func derivedLegacyThreadStage(
        _ v: SecretaryProjectionEngine.ExchangeVisibleThreadStatus,
        detail: ExchangeModels.ThreadDetail
    ) -> ThreadStage {
        switch v.primary {
        case .approvalNeeded:
            if SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail) {
                return .moving
            }
            return .needsApproval
        case .draftReady:
            if SecretaryProjectionEngine.latestPendingApproval(for: detail) != nil,
               !SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail) {
                return .needsApproval
            }
            return .readyToReview
        case .sending:
            return .moving
        case .needsReviewArtifacts:
            return .readyToReview
        case .needsReview:
            return .readyToReview
        case .replyReceived:
            return .moving
        case .waitingForReply:
            return .waiting
        case .pulledOffer, .pulledProfile, .potentialMatch, .noConfirmedMatch, .openExchange:
            return .moving
        case .needsYourInput:
            return .needsAnswer
        case .needsFix:
            return .needsCare
        case .completed:
            return .waiting
        }
    }

    private func secretaryChipStyleFromVisible(
        _ tone: SecretaryProjectionEngine.ExchangeVisibleThreadStatusTone
    ) -> SecretaryStateChip.Style {
        switch tone {
        case .neutral:
            return .neutral
        case .warning:
            return .warning
        case .blocked:
            return .blocked
        case .success:
            return .success
        case .active:
            return .active
        }
    }

    private func iconStyle(for style: SecretaryStateChip.Style) -> SecretaryIconBadge.IconStyle {
        switch style {
        case .neutral:
            return .brand
        case .active:
            return .live
        case .warning:
            return .approval
        case .blocked:
            return .recovery
        case .success:
            return .trust
        }
    }

    private func compactPulledSurfaceStatusLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "draft ready": return "Ready"
        case "pulled offer", "pulled profile": return "Pulled"
        case "waiting for reply": return "Waiting"
        case "needs approval": return "Review"
        case "reply received": return "Reply"
        case "search in progress": return "Search"
        case "no viable match": return "None"
        case "weak matches": return "Weak"
        default:
            let first = trimmed.split(separator: " ").first.map(String.init) ?? ""
            return first.isEmpty ? "Open" : String(first.prefix(12))
        }
    }

    private func normalizeFitPercentDisplay(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasSuffix("%") {
            let num = String(t.dropLast()).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if let v = Double(num), v >= 0, v <= 100 {
                return "\(Int(v.rounded()))%"
            }
            if let v = Double(num), v > 0, v <= 1 {
                return "\(Int((v * 100).rounded()))%"
            }
            return nil
        }
        if let v = Double(t), v >= 0, v <= 1 {
            return "\(Int((v * 100).rounded()))%"
        }
        if let v = Double(t), v >= 0, v <= 100 {
            return "\(Int(v.rounded()))%"
        }
        return nil
    }

    private func compactPulledSurfaceFitLabel(detail: ExchangeModels.ThreadDetail) -> String? {
        let compare = SecretaryProjectionEngine.compareDisplay(for: detail)
        let lines = compare.extraSections
            .flatMap(\.lines)
            .filter(\.isRenderable)
        for line in lines where line.label.caseInsensitiveCompare("Score") == .orderedSame {
            let v = clean(line.value)
            return normalizeFitPercentDisplay(v)
        }
        return nil
    }

    @ViewBuilder
    private func compactPulledSurfaceStatusTag(
        label: String,
        systemImage: String,
        chipStyle: SecretaryStateChip.Style
    ) -> some View {
        let attention =
            chipStyle == .warning ||
            chipStyle == .blocked ||
            chipStyle == .active

        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(attention ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if attention {
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.5))
            } else {
                threadGlassCapsuleBackground()
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    attention
                        ? SecretaryTheme.darkOrange.opacity(0.35)
                        : SecretaryTheme.darkStroke.opacity(0.65),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func compactPulledSurfaceFitTag(_ percentLabel: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(percentLabel)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.92))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            threadGlassCapsuleBackground()
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.6), lineWidth: 1)
        )
    }

    private struct CompactPulledSurfaceField: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private struct CompactPulledSurfaceIconFact: Identifiable {
        let id: String
        let systemImage: String
        let value: String
    }

    private func compactPulledSurfaceMissingValue(_ preferred: String = "Not listed") -> String {
        preferred
    }

    private func compactPulledSurfaceIsHeroPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("Not provided") == .orderedSame
            || trimmed.caseInsensitiveCompare("Not listed") == .orderedSame
    }

    /// Hero chips only — omit empty values and editor-style placeholders.
    private func compactPulledSurfaceHeroChipValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = clean(value)
        guard !cleaned.isEmpty, !compactPulledSurfaceIsHeroPlaceholder(cleaned) else { return nil }
        return cleaned
    }

    private func compactContactEnumPhrase(_ raw: String) -> String {
        var spaced = ""
        for ch in raw {
            if ch.isUppercase, !spaced.isEmpty, let last = spaced.last, last.isLetter, !last.isUppercase {
                spaced.append(" ")
            }
            spaced.append(ch)
        }
        return spaced.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    private func compactPulledSurfaceNonEmptyClean(_ value: String?) -> String? {
        guard let value else { return nil }
        let c = clean(value)
        return c.isEmpty ? nil : c
    }

    /// Remote node anchor for optional contact relationship rows (no guessing when absent).
    private func compactPulledSurfaceContactRemoteNodeID(_ detail: ExchangeModels.ThreadDetail) -> String? {
        if let raw = detail.selectedCounterparty?.identity?.nodeID {
            let t = clean(raw)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Only returns context the user has explicitly saved for this node (avoids inventing defaults).
    private func compactPulledSurfaceExplicitContactContext(_ detail: ExchangeModels.ThreadDetail) -> ExchangeModels.ContactContext? {
        guard let id = compactPulledSurfaceContactRemoteNodeID(detail) else { return nil }
        return services.listContactContextsByNodeID(nodeIDs: [id])[id]
    }

    private func compactPulledSurfaceUseCommercialRows(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> Bool {
        switch ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID
        ) {
        case .offerLed:
            return true
        case .profileLed:
            return false
        case .ambiguous:
            if pulled.kindTitle.localizedCaseInsensitiveContains("offer") {
                return true
            }
            if compactPulledSurfaceNonEmptyClean(pulled.category) != nil {
                return true
            }
            if pulledCommercialSurface(detail).hasContent {
                return true
            }
            return false
        }
    }

    private func compactPulledSurfaceCompareLineValue(
        detail: ExchangeModels.ThreadDetail,
        labels: [String]
    ) -> String? {
        let compare = SecretaryProjectionEngine.compareDisplay(for: detail)
        let lines = compare.extraSections
            .flatMap(\.lines)
            .filter(\.isRenderable)
        for want in labels {
            if let line = lines.first(where: { $0.label.caseInsensitiveCompare(want) == .orderedSame }) {
                let c = clean(line.value)
                if !c.isEmpty { return c }
            }
        }
        return nil
    }

    /// Compact icon facts for pulled **public profile** surfaces — uses compare `extraSections` and
    /// `pulledPublicSurface` fields only (no private `ContactContext`).
    private func compactPulledSurfacePublicProfileIconFacts(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> [CompactPulledSurfaceIconFact] {
        let aboutValue: String? = {
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: [
                "About you", "About You", "About", "Profile Summary", "Bio", "Profile Bio", "Public Profile Summary",
            ]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let s = pulled.summary {
                let o = cleanSurfaceSubtitle(s)
                if !o.isEmpty { return o }
            }
            if let h = pulled.headline {
                let o = cleanSurfaceSubtitle(h)
                if !o.isEmpty { return o }
            }
            return nil
        }()

        let lookingForValue: String? = {
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: [
                "Looking for", "Looking For", "Seeking", "Interested in",
            ]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: ["Open To", "Open to"]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let raw = pulled.openTo {
                let o = cleanSurfaceSubtitle(raw)
                if !o.isEmpty { return o }
            }
            return nil
        }()

        let interestsValue: String? = {
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: ["Interests"]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: ["Profile Tags", "Tags"]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let raw = pulled.tags {
                let o = cleanSurfaceSubtitle(raw)
                if !o.isEmpty { return o }
            }
            return nil
        }()

        let rolesValue: String? = {
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: [
                "Current roles", "Current Roles", "Roles", "Profile Roles", "Occupation", "Work", "Job title", "Job Title",
            ]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            return nil
        }()

        let regionValue: String? = {
            if let v = compactPulledSurfaceCompareLineValue(detail: detail, labels: [
                "Region", "Regions", "Profile Regions", "Location", "Area", "City",
            ]) {
                let o = cleanSurfaceSubtitle(v)
                if !o.isEmpty { return o }
            }
            if let r = compactPulledSurfaceNonEmptyClean(pulled.regions) {
                let o = cleanSurfaceSubtitle(r)
                if !o.isEmpty { return o }
            }
            return nil
        }()

        let candidates: [(String, String, String?)] = [
            ("about", "person.text.rectangle", aboutValue),
            ("lookingFor", "magnifyingglass", lookingForValue),
            ("interests", "sparkles", interestsValue),
            ("currentRoles", "briefcase", rolesValue),
            ("region", "mappin.and.ellipse", regionValue),
        ]

        return candidates.compactMap { id, symbol, raw in
            guard let value = compactPulledSurfaceHeroChipValue(raw) else { return nil }
            return CompactPulledSurfaceIconFact(id: id, systemImage: symbol, value: value)
        }
    }

    private func compactPulledSurfaceCommercialRegionLine(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        commercial: PulledCommercialSurface
    ) -> String {
        if let r = compactPulledSurfaceNonEmptyClean(pulled.regions) { return r }
        if let sa = compactPulledSurfaceNonEmptyClean(commercial.serviceArea) { return sa }
        if let fromCompare = compactPulledSurfaceCompareLineValue(
            detail: detail,
            labels: ["Regions", "Region", "Service Area", "Service area"]
        ) {
            return fromCompare
        }
        return compactPulledSurfaceMissingValue("Not listed")
    }

    private func compactPulledSurfaceCommercialSummary(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> String {
        if let s = pulled.summary {
            let out = cleanSurfaceSubtitle(s)
            if !out.isEmpty { return out }
        }
        if let sub = fallbackSurfaceSubtitle(detail) {
            if SecretaryProjectionEngine.isBlockedSystemArtifactText(sub) {
                return compactPulledSurfaceMissingValue("Not provided")
            }
            let out = cleanSurfaceSubtitle(sub)
            if !out.isEmpty { return out }
        }
        return compactPulledSurfaceMissingValue("Not provided")
    }

    private func compactPulledSurfaceSocialSummary(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> String {
        if let s = pulled.summary {
            let out = cleanSurfaceSubtitle(s)
            if !out.isEmpty { return out }
        }
        if let h = pulled.headline {
            let out = cleanSurfaceSubtitle(h)
            if !out.isEmpty { return out }
        }
        if let sub = fallbackSurfaceSubtitle(detail) {
            if SecretaryProjectionEngine.isBlockedSystemArtifactText(sub) {
                return compactPulledSurfaceMissingValue("Not provided")
            }
            let out = cleanSurfaceSubtitle(sub)
            if !out.isEmpty { return out }
        }
        return compactPulledSurfaceMissingValue("Not provided")
    }

    private func compactPulledSurfaceRelationshipLine(_ ctx: ExchangeModels.ContactContext) -> String {
        if let custom = ctx.customRelationshipLabel {
            let c = clean(custom)
            if !c.isEmpty { return c }
        }
        if ctx.relationshipType != .custom {
            let phrase = compactContactEnumPhrase(ctx.relationshipType.rawValue)
            let c = clean(phrase)
            if !c.isEmpty { return c }
        }
        return compactPulledSurfaceMissingValue("Not listed")
    }

    private func compactPulledSurfaceGoalLine(_ ctx: ExchangeModels.ContactContext) -> String {
        if let custom = ctx.customRelationshipGoal {
            let c = clean(custom)
            if !c.isEmpty { return c }
        }
        let phrase = compactContactEnumPhrase(ctx.relationshipGoal.rawValue)
        let c = clean(phrase)
        return c.isEmpty ? compactPulledSurfaceMissingValue("Not listed") : c
    }

    private func compactPulledSurfaceFields(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> [CompactPulledSurfaceField] {
        let commercial = pulledCommercialSurface(detail)
        if compactPulledSurfaceUseCommercialRows(detail: detail, pulled: pulled) {
            let category = compactPulledSurfaceNonEmptyClean(pulled.category)
                ?? compactPulledSurfaceMissingValue("Not listed")
            let region = compactPulledSurfaceCommercialRegionLine(
                detail: detail,
                pulled: pulled,
                commercial: commercial
            )
            let summary = compactPulledSurfaceCommercialSummary(detail: detail, pulled: pulled)
            return [
                CompactPulledSurfaceField(id: "category", label: "Category", value: category),
                CompactPulledSurfaceField(id: "region", label: "Region", value: region),
                CompactPulledSurfaceField(id: "summary", label: "Summary", value: summary),
            ]
        } else {
            let explicitContext = compactPulledSurfaceExplicitContactContext(detail)
            let relationship = explicitContext.map { compactPulledSurfaceRelationshipLine($0) }
                ?? compactPulledSurfaceMissingValue("Not listed")
            let goal = explicitContext.map { compactPulledSurfaceGoalLine($0) }
                ?? compactPulledSurfaceMissingValue("Not listed")
            let summary = compactPulledSurfaceSocialSummary(detail: detail, pulled: pulled)
            return [
                CompactPulledSurfaceField(id: "relationship", label: "Relationship", value: relationship),
                CompactPulledSurfaceField(id: "goal", label: "Goal", value: goal),
                CompactPulledSurfaceField(id: "summary", label: "Summary", value: summary),
            ]
        }
    }

    private func compactPulledSurfaceIconFacts(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> [CompactPulledSurfaceIconFact] {
        if compactPulledSurfaceUseCommercialRows(detail: detail, pulled: pulled) {
            return compactPulledSurfaceFields(detail: detail, pulled: pulled).compactMap { field in
                guard let value = compactPulledSurfaceHeroChipValue(field.value) else { return nil }
                let symbol: String = {
                    switch field.id {
                    case "category": return "tag"
                    case "region": return "mappin.and.ellipse"
                    case "relationship": return "person.2"
                    case "goal": return "scope"
                    case "summary": return "text.alignleft"
                    default: return "circle.fill"
                    }
                }()
                return CompactPulledSurfaceIconFact(id: field.id, systemImage: symbol, value: value)
            }
        }
        return compactPulledSurfacePublicProfileIconFacts(detail: detail, pulled: pulled)
    }

    private func compactPulledSurfaceIconFactLineLimit(_ id: String) -> Int {
        switch id {
        case "about", "lookingFor", "summary":
            return 2
        case "category", "region", "interests", "currentRoles", "relationship", "goal":
            return 1
        default:
            return 1
        }
    }

    @ViewBuilder
    private func compactPulledSurfaceIconFactsRow(_ facts: [CompactPulledSurfaceIconFact]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(facts) { fact in
                    HStack(spacing: 5) {
                        Image(systemName: fact.systemImage)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.82))

                        Text(fact.value)
                            .font(.system(size: 11.8, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                            .lineLimit(compactPulledSurfaceIconFactLineLimit(fact.id))
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        threadGlassCapsuleBackground()
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SecretaryTheme.darkStroke.opacity(0.48), lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func pulledSurfaceHeroPagerDots(count: Int, selectedIndex: Int) -> some View {
        if count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == selectedIndex
                            ? SecretaryTheme.darkPrimaryText.opacity(0.92)
                            : SecretaryTheme.darkPrimaryText.opacity(0.35)
                        )
                        .frame(width: index == selectedIndex ? 14 : 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    }
                    .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private func pulledSurfaceHeroSubtitleLine(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        useCommercial: Bool
    ) -> String? {
        if useCommercial {
            if let s = pulled.summary {
                let out = cleanSurfaceSubtitle(s)
                if !out.isEmpty { return out }
            }
            let cat = compactPulledSurfaceNonEmptyClean(pulled.category)
            let reg = compactPulledSurfaceNonEmptyClean(pulled.regions)
            if cat != nil || reg != nil {
                return [cat, reg].compactMap { $0 }.joined(separator: " · ")
            }
            if let fb = fallbackSurfaceSubtitle(detail) {
                let out = cleanSurfaceSubtitle(fb)
                if !out.isEmpty { return out }
            }
            return nil
        } else {
            if let h = pulled.headline {
                let out = cleanSurfaceSubtitle(h)
                if !out.isEmpty { return out }
            }
            if let s = pulled.summary {
                let out = cleanSurfaceSubtitle(s)
                if !out.isEmpty { return out }
            }
            if let fb = fallbackSurfaceSubtitle(detail) {
                let out = cleanSurfaceSubtitle(fb)
                if !out.isEmpty { return out }
            }
            return nil
        }
    }

    @ViewBuilder
    private func pulledSurfaceHeroTabPage(
        urlString: String,
        size: CGSize,
        title: String,
        detail: ExchangeModels.ThreadDetail,
        orbSystemImage: String,
        style: SecretaryStateChip.Style
    ) -> some View {
        let trimmed = clean(urlString)
        Group {
            if trimmed.isEmpty {
                thumbnailFallback(title: title, detail: detail, orbSystemImage: orbSystemImage, style: style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.38))
            } else if let url = URL(string: trimmed) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        ZStack {
                            Color.black.opacity(0.38)
                            thumbnailFallback(
                                title: title,
                                detail: detail,
                                orbSystemImage: orbSystemImage,
                                style: style
                            )
                            .scaleEffect(1.2)
                        }
                    @unknown default:
                        Color.black.opacity(0.38)
                    }
                }
            } else {
                thumbnailFallback(title: title, detail: detail, orbSystemImage: orbSystemImage, style: style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.38))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func pulledSurfaceHeroPhotoStack(
        urls: [String],
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        title: String,
        detail: ExchangeModels.ThreadDetail,
        orbSystemImage: String,
        style: SecretaryStateChip.Style
    ) -> some View {
        let capped = Array(
            urls.map { clean($0) }.filter { !$0.isEmpty }.prefix(ExchangeOffer.maxPublicOfferImageCount)
        )
        let size = CGSize(width: max(width, 1), height: max(height, 1))

        if capped.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [
                        SecretaryTheme.darkSurfaceStrong.opacity(0.95),
                        Color.black.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                thumbnailFallback(title: title, detail: detail, orbSystemImage: orbSystemImage, style: style)
                    .scaleEffect(1.35)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if capped.count == 1 {
            SecretaryThreadHeroAsyncImage(
                candidates: capped,
                successfulCandidateIndex: $heroSuccessfulGalleryIndex,
                fillSize: size,
                clipCornerRadius: cornerRadius,
                showStroke: false,
                debugThreadShort: {
                    #if DEBUG
                    String(detail.thread.id.uuidString.prefix(8))
                    #else
                    nil
                    #endif
                }()
            ) {
                thumbnailFallback(title: title, detail: detail, orbSystemImage: orbSystemImage, style: style)
            }
        } else {
            TabView(selection: $heroPagerIndex) {
                ForEach(Array(capped.enumerated()), id: \.offset) { pair in
                    pulledSurfaceHeroTabPage(
                        urlString: pair.element,
                        size: size,
                        title: title,
                        detail: detail,
                        orbSystemImage: orbSystemImage,
                        style: style
                    )
                    .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    // MARK: - Surface card
    //
    // Commercial facts audit:
    // - `pulledCommercialSurface` previously read only `SecretaryProjectionEngine.compareDisplay(for:).extraSections`.
    // - `compareMatchExtraSections` supplies pulled offer/profile rows (title, category, regions…) but does NOT
    //   include seller commercial fields (price, packages, service area). Those live on `ExchangeOffer.CommercialFacts`
    //   and are emitted as skim strings via `commercialSurfaceSkimLines`.
    // - `SecretaryThreadSituationCard` / More Context show commercial lines from `ExchangeThreadSituation
    //   .commercialSurfaceFactLines`, built in `ExchangeThreadSituationBuilder` from the resolved offer — the
    //   canonical UI source for the same thread.
    // - Multi-path compare displays can also omit extraSections; the situation path remains authoritative for
    //   single-thread review.
    // Top card therefore prefers `situation?.commercialSurfaceFactLines`, then falls back to compare extraSections.

    private func surfaceCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let vs = visibleSurfaceStatus(for: detail)
        _ = stage(for: detail)
        let style = secretaryChipStyleFromVisible(vs.tone)
        let pulled = pulledPublicSurface(detail)
        let surfaceImageURLs = surfaceImageURLsForHeroCard(detail)
        let title = pulled.title ?? fallbackSurfaceTitle(detail)
        let useCommercial = compactPulledSurfaceUseCommercialRows(detail: detail, pulled: pulled)
        let compactFields: [CompactPulledSurfaceField] = useCommercial
            ? compactPulledSurfaceFields(detail: detail, pulled: pulled)
            : []
        let subtitleLine = pulledSurfaceHeroSubtitleLine(
            detail: detail,
            pulled: pulled,
            useCommercial: useCommercial
        )
        let notProvidedPlaceholder = compactPulledSurfaceMissingValue("Not provided")
        let galleryCaption: String? = {
            if let s = subtitleLine, !s.isEmpty { return s }
            if useCommercial {
                guard let v = compactFields.first(where: { $0.id == "summary" })?.value else { return nil }
                if v == notProvidedPlaceholder { return nil }
                return v
            }
            let about = compactPulledSurfacePublicProfileIconFacts(detail: detail, pulled: pulled)
                .first(where: { $0.id == "about" })?
                .value
            guard let about, about != notProvidedPlaceholder, !about.isEmpty else { return nil }
            return about
        }()
        let fitPercentTag = compactPulledSurfaceFitLabel(detail: detail)
        let corner = SecretaryThreadLayout.detailCardCornerRadius
        let iconFacts = compactPulledSurfaceIconFacts(detail: detail, pulled: pulled)

        return VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 74)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    backButton

                    Spacer(minLength: 0)

                    if let fitPercentTag {
                        compactPulledSurfaceFitTag(fitPercentTag)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Color.clear
                .aspectRatio(335.0 / 468.0, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        let photoHeight = max(geo.size.height, 1)
                        let capped = Array(
                            surfaceImageURLs.map { clean($0) }.filter { !$0.isEmpty }
                                .prefix(ExchangeOffer.maxPublicOfferImageCount)
                        )

                        ZStack(alignment: .bottomLeading) {
                            pulledSurfaceHeroPhotoStack(
                                urls: surfaceImageURLs,
                                width: width,
                                height: photoHeight,
                                cornerRadius: corner,
                                title: title,
                                detail: detail,
                                orbSystemImage: vs.systemImage,
                                style: style
                            )
                            .frame(width: width, height: photoHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !capped.isEmpty else { return }
                                let start: Int = {
                                    if capped.count > 1 {
                                        return min(max(0, heroPagerIndex), capped.count - 1)
                                    }
                                    return min(
                                        max(0, heroSuccessfulGalleryIndex ?? 0),
                                        capped.count - 1
                                    )
                                }()
                                presentImageGallery(
                                    urls: capped,
                                    startIndex: start,
                                    title: title,
                                    caption: galleryCaption
                                )
                            }

                            VStack {
                                pulledSurfaceHeroPagerDots(
                                    count: capped.count,
                                    selectedIndex: min(max(0, heroPagerIndex), max(0, capped.count - 1))
                                )

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 12)

                            VStack(alignment: .leading, spacing: 10) {
                                compactPulledSurfaceIconFactsRow(iconFacts)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .padding(.top, 34)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.0),
                                        Color.black.opacity(0.28),
                                        Color.black.opacity(0.42),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        }
                        .frame(width: width, height: photoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
            
            pulledSurfaceDetailsToggle(
                detail: detail,
                pulled: pulled
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: detail.thread.id) { _, _ in
            heroPagerIndex = 0
            heroSuccessfulGalleryIndex = nil
        }
    }

    /// Offer gallery URLs plus profile/primary fallback, de-duplicated, capped — ordering respects
    /// ``ExchangePresentationSurfaceLead`` (profile-led does not lead with offer gallery URLs).
    private func surfaceImageURLsForHeroCard(_ detail: ExchangeModels.ThreadDetail) -> [String] {
        let lead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID
        )
        let pulled = pulledPublicSurface(detail)
        let fromOffer = situation?.selectedOfferImageURLs ?? []
        let primary = clean(pulled.imageURL ?? situation?.primaryImageURL)

        var ordered: [String] = []
        switch lead {
        case .offerLed:
            for raw in fromOffer {
                let c = clean(raw)
                guard !c.isEmpty else { continue }
                ordered.append(c)
            }
            if !primary.isEmpty {
                ordered.append(primary)
            }
        case .profileLed:
            if !primary.isEmpty {
                ordered.append(primary)
            }
            for raw in fromOffer {
                let c = clean(raw)
                guard !c.isEmpty else { continue }
                ordered.append(c)
            }
        case .ambiguous:
            for raw in fromOffer {
                let c = clean(raw)
                guard !c.isEmpty else { continue }
                ordered.append(c)
            }
            if !primary.isEmpty {
                ordered.append(primary)
            }
        }
        let merged = unique(ordered)
        let capped = Array(merged.prefix(ExchangeOffer.maxPublicOfferImageCount))
        let normalized = WorkThreadLeadImageURLNormalizer.normalizedChain(from: capped)
        #if DEBUG
        let leadLabel: String = {
            switch lead {
            case .offerLed: return "offerLed"
            case .profileLed: return "profileLed"
            case .ambiguous: return "ambiguous"
            }
        }()
        ThreadImagePipelineDebug.logDetail(
            threadID: String(detail.thread.id.uuidString.prefix(8)),
            rawOrderedUniqueCount: merged.count,
            normalizedCount: normalized.count,
            selectedSource: leadLabel,
            urlValid: normalized.first.flatMap { URL(string: $0) != nil } ?? false,
            frameW: Int(SecretaryThreadHeroMetrics.width),
            frameH: Int(SecretaryThreadHeroMetrics.height)
        )
        #endif
        return normalized
    }

    private func presentImageGallery(urls: [String], startIndex: Int, title: String, caption: String?) {
        let trimmed = urls.map { clean($0) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }
        imageGalleryPresentation = SecretaryImageGalleryPresentation(
            imageURLs: trimmed,
            initialIndex: startIndex,
            title: title,
            caption: caption
        )
    }

    private func publicSurfaceImageColumn(
        imageURLs: [String],
        title: String,
        summary: String?,
        pulled: PulledPublicSurface,
        detail: ExchangeModels.ThreadDetail,
        orbSystemImage: String,
        style: SecretaryStateChip.Style,
        successfulHeroGalleryIndex: Binding<Int?>
    ) -> some View {
        let capped = Array(imageURLs.prefix(ExchangeOffer.maxPublicOfferImageCount))
        let extras = Array(capped.dropFirst())
        let caption: String? = {
            guard let summary else { return nil }
            let c = cleanSurfaceSubtitle(summary)
            return c.isEmpty ? nil : c
        }()

        return VStack(alignment: .leading, spacing: 7) {
            publicSurfaceHeroThumbnail(
                imageURLs: capped,
                title: title,
                detail: detail,
                orbSystemImage: orbSystemImage,
                style: style,
                successfulHeroGalleryIndex: successfulHeroGalleryIndex
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !capped.isEmpty else { return }
                guard let idx = successfulHeroGalleryIndex.wrappedValue else { return }
                presentImageGallery(urls: capped, startIndex: idx, title: title, caption: caption)
            }

            if !extras.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(extras.enumerated()), id: \.offset) { pair in
                            let idx = pair.offset
                            let urlStr = clean(pair.element)
                            if !urlStr.isEmpty, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure, .empty:
                                        threadGlassRoundedRectangleBackground(cornerRadius: 10)
                                            .frame(width: 40, height: 40)
                                    @unknown default:
                                        threadGlassRoundedRectangleBackground(cornerRadius: 10)
                                            .frame(width: 40, height: 40)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    presentImageGallery(urls: capped, startIndex: idx + 1, title: title, caption: caption)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 104)
            }
        }
        .onChange(of: detail.thread.id) { _, _ in
            successfulHeroGalleryIndex.wrappedValue = nil
        }
    }

    private func publicSurfaceHeroThumbnail(
        imageURLs: [String],
        title: String,
        detail: ExchangeModels.ThreadDetail,
        orbSystemImage: String,
        style: SecretaryStateChip.Style,
        successfulHeroGalleryIndex: Binding<Int?>
    ) -> some View {
        SecretaryThreadHeroAsyncImage(
            candidates: imageURLs.map { clean($0) }.filter { !$0.isEmpty },
            successfulCandidateIndex: successfulHeroGalleryIndex,
            debugThreadShort: {
                #if DEBUG
                String(detail.thread.id.uuidString.prefix(8))
                #else
                nil
                #endif
            }()
        ) {
            thumbnailFallback(title: title, detail: detail, orbSystemImage: orbSystemImage, style: style)
        }
    }

    private func thumbnailFallback(
        title: String,
        detail: ExchangeModels.ThreadDetail,
        orbSystemImage: String,
        style: SecretaryStateChip.Style
    ) -> some View {
        VStack(spacing: 8) {
            threadDarkThumbnailOrb(
                initials: initials(from: title),
                systemImage: orbSystemImage,
                style: style,
                size: 52
            )
        }
    }

    private func compactChipWrap(_ chips: [String]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 74), spacing: 7)
            ],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(chips.prefix(6), id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background {
                        threadGlassCapsuleBackground()
                    }
                    .overlay(
                        Capsule()
                            .stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
                    )
            }
        }
    }

    private func surfaceInfoGroup(
        title: String,
        systemImage: String,
        facts: [(label: String, value: String)]
    ) -> some View {
        UnifyDarkCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(facts.prefix(8).enumerated()), id: \.offset) { _, fact in
                        compactFactLine(label: fact.label, value: fact.value)
                    }
                }
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fallbackSurfaceTitle(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let selected = SecretaryProjectionEngine.selectedCounterpartyName(for: detail) {
            return selected
        }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
            if let title = SecretaryProjectionEngine.nonEmpty(display.hero.title) {
                return title
            }
            if let title = SecretaryProjectionEngine.nonEmpty(display.title) {
                return title
            }
        }

        return SecretaryProjectionEngine.threadTitle(detail)
    }

    private func fallbackSurfaceSubtitle(_ detail: ExchangeModels.ThreadDetail) -> String? {
        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        if let subtitle = vs.subtitle,
           !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subtitle
        }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
            let candidate =
                SecretaryProjectionEngine.secondHalfSummaryLine(display)
                ?? SecretaryProjectionEngine.nonEmpty(display.hero.statusLine)
                ?? SecretaryProjectionEngine.nonEmpty(display.subtitle)

            if let candidate, !SecretaryProjectionEngine.isBlockedSystemArtifactText(candidate) {
                return candidate
            }
        }

        if let situationSummary = situation.flatMap({ situationSummary($0) }) {
            return situationSummary
        }

        let hero = SecretaryProjectionEngine.threadHeroSummary(detail)
        return SecretaryProjectionEngine.isBlockedSystemArtifactText(hero) ? nil : hero
    }

    private func surfaceChips(
        _ detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> [String] {
        var values: [String] = []

        if let category = pulled.category {
            values.append(category)
        }

        if let regions = pulled.regions {
            values.append(regions)
        }

        if let tags = pulled.tags {
            values.append(tags)
        }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
            if let role = SecretaryProjectionEngine.nonEmpty(display.roleLabel) {
                values.append(role)
            }

            if let quality = SecretaryProjectionEngine.nonEmpty(display.status.quality),
               quality.lowercased() != "unknown" {
                let lower = quality.lowercased()
                if !lower.contains("promising") && !lower.contains("strong") {
                    values.append(quality)
                }
            }
        }

        if SecretaryProjectionEngine.hasMultipleComparePaths(for: detail) {
            values.append("Multiple paths")
        }

        if detail.thread.awaitingResponseLike {
            values.append("Waiting for reply")
        }

        return Array(unique(values).prefix(6))
    }

    private func publicSurfaceFacts(_ surface: PulledPublicSurface) -> [(label: String, value: String)] {
        var facts: [(String, String)] = []

        if let headline = surface.headline {
            facts.append(("Headline", headline))
            if let summary = surface.summary {
                let cleaned = clean(summary)
                if !cleaned.isEmpty {
                    facts.append(("About", cleaned))
                }
            }
        }

        if let category = surface.category {
            facts.append(("Category", category))
        }

        if let regions = surface.regions {
            facts.append(("Regions", regions))
        }

        if let tags = surface.tags {
            facts.append(("Tags", tags))
        }

        if let openTo = surface.openTo {
            facts.append(("Open to", openTo))
        }

        return facts
    }

    private struct ThreadProviderDetailsPresentation {
        var compactSections: [PulledSurfaceDetailsSection]
        var expandedSections: [PulledSurfaceDetailsSection]
        var hasMoreDetails: Bool
        var compactVisualLayout: ThreadDetailsVisualLayout?
        var expandedVisualLayout: ThreadDetailsVisualLayout?

        var hasAnyContent: Bool {
            !compactSections.isEmpty || !expandedSections.isEmpty
        }
    }

    private struct PulledSurfaceDetailsSection: Identifiable {
        let id: String
        let title: String
        let labeledRows: [(label: String, value: String)]
        let valueLines: [String]

        init(
            id: String,
            title: String,
            labeledRows: [(label: String, value: String)] = [],
            valueLines: [String] = []
        ) {
            self.id = id
            self.title = title
            self.labeledRows = labeledRows
            self.valueLines = valueLines
        }

        var hasContent: Bool {
            !labeledRows.isEmpty || !valueLines.isEmpty
        }
    }
    
    private struct PulledCommercialSurface {
        var price: String?
        var priceRange: String?
        var currency: String?
        var unit: String?
        var availability: String?
        var serviceArea: String?
        var minimum: String?
        var packagesJoined: String?
        var packageLines: [String] = []
        var policyLines: [String] = []
        var policies: String?
        var fulfillmentLine: String?
        var contactSummary: String?
        var requiredBuyerInputs: [String] = []
        var faqLines: [String] = []

        var hasContent: Bool {
            !priceFacts.isEmpty ||
            !packageLines.isEmpty ||
            serviceArea != nil ||
            availability != nil ||
            fulfillmentLine != nil ||
            !requiredBuyerInputs.isEmpty ||
            !policyLines.isEmpty ||
            policies != nil ||
            !faqLines.isEmpty ||
            contactSummary != nil
        }

        var priceFacts: [(label: String, value: String)] {
            var output: [(String, String)] = []

            if let price {
                output.append(("Price", price))
            }

            if let priceRange {
                output.append(("Range", priceRange))
            }

            if let currency {
                output.append(("Currency", currency))
            }

            if let unit {
                output.append(("Unit", unit))
            }

            if let minimum {
                output.append(("Minimum", minimum))
            }

            return output
        }

        /// Legacy flat list for callers that still expect combined facts.
        var facts: [(label: String, value: String)] {
            priceFacts
        }

        static func formattedFAQSkimLine(_ tail: String) -> String {
            let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return trimmed }

            if let answerMarker = trimmed.range(of: "/ A:", options: .caseInsensitive) {
                var question = String(trimmed[..<answerMarker.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if question.lowercased().hasPrefix("q:") {
                    question = String(question.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let answer = String(trimmed[answerMarker.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty, !answer.isEmpty {
                    return "\(question) — \(answer)"
                }
            }

            return trimmed
        }

        /// Parses `ExchangeOffer.CommercialFacts.surfaceSkimLines` output (same strings as `ExchangeThreadSituation.commercialSurfaceFactLines`).
        static func fromCommercialSkimLines(_ lines: [String]) -> PulledCommercialSurface {
            var price: String?
            var priceRange: String?
            var currency: String?
            var unit: String?
            var availability: String?
            var serviceArea: String?
            var minimum: String?
            var packages: [String] = []
            var policyParts: [String] = []
            var requiredBuyerInputs: [String] = []
            var faqLines: [String] = []

            for raw in lines {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let colon = trimmed.firstIndex(of: ":") else { continue }

                let head = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !head.isEmpty, !tail.isEmpty else { continue }

                let headLower = head.lowercased()
                if headLower.hasPrefix("faq auto-answer") {
                    continue
                }

                switch headLower {
                case "price":
                    price = tail
                case "price range":
                    priceRange = tail
                case "currency":
                    currency = tail
                case "price unit":
                    unit = tail
                case "package":
                    packages.append(tail)
                case "service area":
                    serviceArea = tail
                case "availability":
                    availability = tail
                case "minimum engagement":
                    minimum = tail
                case "cancellation policy", "refund policy", "warranty policy":
                    policyParts.append(tail)
                case "required buyer input":
                    requiredBuyerInputs.append(tail)
                case "faq":
                    faqLines.append(formattedFAQSkimLine(tail))
                default:
                    break
                }
            }

            let packagesJoined = packages.isEmpty ? nil : packages.joined(separator: "\n")
            let policies = policyParts.isEmpty ? nil : policyParts.joined(separator: " · ")

            return PulledCommercialSurface(
                price: price,
                priceRange: priceRange,
                currency: currency,
                unit: unit,
                availability: availability,
                serviceArea: serviceArea,
                minimum: minimum,
                packagesJoined: packagesJoined,
                packageLines: packages,
                policyLines: policyParts,
                policies: policies,
                fulfillmentLine: nil,
                contactSummary: nil,
                requiredBuyerInputs: requiredBuyerInputs,
                faqLines: faqLines
            )
        }

        func mergingSituationStructuredFields(
            _ situation: ExchangeThreadSituation?,
            includeSynthesizedFulfillment: Bool = false
        ) -> PulledCommercialSurface {
            guard let situation else { return self }

            var merged = self

            if includeSynthesizedFulfillment, merged.fulfillmentLine == nil {
                merged.fulfillmentLine = situation.offerFulfillmentLine
            }
            if merged.contactSummary == nil {
                merged.contactSummary = situation.offerContactSummary
            }
            if merged.requiredBuyerInputs.isEmpty {
                merged.requiredBuyerInputs = situation.requiredBuyerInputLines
            }
            if merged.faqLines.isEmpty {
                merged.faqLines = situation.faqDisplayLines
            }
            if merged.packageLines.isEmpty, !situation.packageDisplayLines.isEmpty {
                merged.packageLines = situation.packageDisplayLines
                merged.packagesJoined = situation.packageDisplayLines.joined(separator: "\n")
            }
            if merged.policyLines.isEmpty, let policies = merged.policies {
                merged.policyLines = policies
                    .components(separatedBy: " · ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }

            return merged
        }
    }

    /// Primary: same `commercialSurfaceFactLines` as situation. Fallback: compare panel extra sections.
    private func pulledCommercialSurface(
        _ detail: ExchangeModels.ThreadDetail,
        includeSynthesizedFulfillment: Bool = false
    ) -> PulledCommercialSurface {
        let parsed: PulledCommercialSurface = {
            if let lines = situation?.commercialSurfaceFactLines, !lines.isEmpty {
                let fromSkim = PulledCommercialSurface.fromCommercialSkimLines(lines)
                if fromSkim.hasContent {
                    return fromSkim
                }
            }
            return pulledCommercialSurfaceFromCompareDisplay(
                detail,
                includeSynthesizedFulfillment: includeSynthesizedFulfillment
            )
        }()

        return parsed.mergingSituationStructuredFields(
            situation,
            includeSynthesizedFulfillment: includeSynthesizedFulfillment
        )
    }

    /// Legacy fallback: structured labels from `compareDisplay` extra sections (often absent for price/packages).
    private func pulledCommercialSurfaceFromCompareDisplay(
        _ detail: ExchangeModels.ThreadDetail,
        includeSynthesizedFulfillment: Bool = false
    ) -> PulledCommercialSurface {
        let compare = SecretaryProjectionEngine.compareDisplay(for: detail)
        let lines = compare.extraSections
            .flatMap(\.lines)
            .filter(\.isRenderable)

        func value(_ labels: [String]) -> String? {
            for label in labels {
                if let line = lines.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                    let cleaned = clean(line.value)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
            return nil
        }

        let min = value(["Price Min", "Minimum Price", "Price minimum"])
        let max = value(["Price Max", "Maximum Price", "Price maximum"])

        let range: String? = {
            if let min, let max {
                return "\(min)–\(max)"
            }
            return min ?? max
        }()

        let policyParts = [
            value(["Cancellation Policy", "Cancellation"]),
            value(["Refund Policy", "Refund"]),
            value(["Warranty Policy", "Warranty"])
        ]
        .compactMap { $0 }

        return PulledCommercialSurface(
            price: value(["Price", "Price Display", "Pricing"]),
            priceRange: range,
            currency: value(["Currency"]),
            unit: value(["Price Unit", "Unit"]),
            availability: value(["Availability", "Availability Note"]),
            serviceArea: value(["Service Area", "Service Area Note"]),
            minimum: value(["Minimum Engagement", "Minimum"]),
            packagesJoined: nil,
            packageLines: [],
            policyLines: policyParts,
            policies: policyParts.isEmpty ? nil : policyParts.joined(separator: " · "),
            fulfillmentLine: includeSynthesizedFulfillment
                ? value(["Fulfillment", "Lead Time", "Lead time"])
                : nil,
            contactSummary: value(["Contact", "Contact Summary"]),
            requiredBuyerInputs: [],
            faqLines: []
        )
    }

    private func refreshProviderDetailsPresentation(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) {
        let context = providerDetailsCard?.presentationContext ?? .unknown
        let sourceSections = buildProviderDetailsSourceSections(
            detail: detail,
            pulled: pulled,
            context: context
        )
        let snapshots = providerDetailsSectionSnapshots(from: sourceSections)
        let presentation = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: snapshots,
            context: context
        )
        providerDetailsPresentation = ThreadProviderDetailsPresentation(
            compactSections: providerDetailsSections(from: presentation.compactSections),
            expandedSections: providerDetailsSections(from: presentation.expandedSections),
            hasMoreDetails: presentation.hasMoreDetails,
            compactVisualLayout: ThreadDetailsVisualBlockMapper.map(
                sections: presentation.compactSections,
                context: context,
                mode: .compact
            ),
            expandedVisualLayout: ThreadDetailsVisualBlockMapper.map(
                sections: presentation.expandedSections,
                context: context,
                mode: .expanded
            )
        )
        #if DEBUG
        if let compactVisualLayout = providerDetailsPresentation?.compactVisualLayout {
            ThreadDetailsVisualBlockDebugLog.logMappedLayout(
                compactVisualLayout,
                source: "threadViewCompact"
            )
        }
        if let expandedVisualLayout = providerDetailsPresentation?.expandedVisualLayout {
            ThreadDetailsVisualBlockDebugLog.logMappedLayout(
                expandedVisualLayout,
                source: "threadViewExpanded"
            )
        }
        #endif
        if !presentation.hasMoreDetails {
            showMoreContext = false
        }
    }

    private func providerDetailsVisibleSections(
        for presentation: ThreadProviderDetailsPresentation,
        expanded: Bool
    ) -> [PulledSurfaceDetailsSection] {
        if presentation.hasMoreDetails {
            return expanded ? presentation.expandedSections : presentation.compactSections
        }
        if !presentation.compactSections.isEmpty {
            return presentation.compactSections
        }
        return presentation.expandedSections
    }

    private func buildProviderDetailsSourceSections(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        context: ExchangeProviderDetailsPresentationContext
    ) -> [PulledSurfaceDetailsSection] {
        if let card = providerDetailsCard, card.hasContent {
            return pulledSurfaceDetailsSectionsFromCanonical(card.sections)
        }
        return contextGatedLegacyPulledSurfaceDetailsSections(
            detail: detail,
            pulled: pulled,
            context: context
        )
    }

    private func providerDetailsSectionSnapshots(
        from sections: [PulledSurfaceDetailsSection]
    ) -> [ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot] {
        sections.map { section in
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: section.id,
                title: section.title,
                labeledRows: section.labeledRows.map {
                    ExchangeProviderDetailsLegacyFallbackPresenter.LabeledRow(label: $0.label, value: $0.value)
                },
                valueLines: section.valueLines
            )
        }
    }

    private func providerDetailsSections(
        from snapshots: [ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot]
    ) -> [PulledSurfaceDetailsSection] {
        snapshots.map { snapshot in
            PulledSurfaceDetailsSection(
                id: snapshot.id,
                title: snapshot.title,
                labeledRows: snapshot.labeledRows.map { ($0.label, $0.value) },
                valueLines: snapshot.valueLines
            )
        }
    }

    private func contextGatedLegacyPulledSurfaceDetailsSections(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        context: ExchangeProviderDetailsPresentationContext
    ) -> [PulledSurfaceDetailsSection] {
        let raw = legacyPulledSurfaceDetailsSections(detail: detail, pulled: pulled)
        return presentLegacyFallbackSections(
            raw,
            detail: detail,
            pulled: pulled,
            context: context
        )
    }

    private func presentLegacyFallbackSections(
        _ sections: [PulledSurfaceDetailsSection],
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        context: ExchangeProviderDetailsPresentationContext
    ) -> [PulledSurfaceDetailsSection] {
        let snapshots = sections.map { section in
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: section.id,
                title: section.title,
                labeledRows: section.labeledRows.map {
                    ExchangeProviderDetailsLegacyFallbackPresenter.LabeledRow(label: $0.label, value: $0.value)
                },
                valueLines: section.valueLines
            )
        }

        let contextTitle: String? = {
            let offerTitle = situation?.selectedOfferTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !offerTitle.isEmpty { return offerTitle }
            let profileTitle = situation?.selectedPublicProfileTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !profileTitle.isEmpty { return profileTitle }
            let pulledTitle = pulled.title.map(clean) ?? ""
            return pulledTitle.isEmpty ? nil : pulledTitle
        }()

        let presented = ExchangeProviderDetailsLegacyFallbackPresenter.present(
            ExchangeProviderDetailsLegacyFallbackPresenter.PresentInput(
                sections: snapshots,
                context: context,
                heroDedupeTexts: legacyFallbackHeroDedupeTexts(detail: detail, pulled: pulled),
                contextTitle: contextTitle
            )
        )

        return presented.map { filtered in
            PulledSurfaceDetailsSection(
                id: filtered.id,
                title: filtered.title,
                labeledRows: filtered.labeledRows.map { ($0.label, $0.value) },
                valueLines: filtered.valueLines
            )
        }
    }

    private func legacyFallbackHeroDedupeTexts(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> Set<String> {
        var texts: Set<String> = []
        let heroTitle = pulled.title ?? fallbackSurfaceTitle(detail)
        let normalizedTitle = ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(heroTitle)
        if !normalizedTitle.isEmpty {
            texts.insert(normalizedTitle)
        }

        for fact in compactPulledSurfaceIconFacts(detail: detail, pulled: pulled) {
            if let chipValue = compactPulledSurfaceHeroChipValue(fact.value) {
                let normalized = ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(chipValue)
                if !normalized.isEmpty {
                    texts.insert(normalized)
                }
            }
        }

        if let offerSummary = situation?.selectedOfferSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !offerSummary.isEmpty {
            texts.insert(ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(offerSummary))
        }

        return texts
    }

    private func pulledSurfaceDetailsSectionsFromCanonical(
        _ sections: [ExchangeDisplaySection]
    ) -> [PulledSurfaceDetailsSection] {
        sections.enumerated().compactMap { index, section in
            guard !section.lines.isEmpty else { return nil }

            var labeledRows: [(label: String, value: String)] = []
            var valueLines: [String] = []

            for line in section.lines {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                if let colon = text.firstIndex(of: ":") {
                    let label = String(text[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(text[text.index(after: colon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty, !value.isEmpty {
                        labeledRows.append((label, value))
                        continue
                    }
                }

                valueLines.append(text)
            }

            guard !labeledRows.isEmpty || !valueLines.isEmpty else { return nil }

            let slug = section.title
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "&", with: "and")

            return PulledSurfaceDetailsSection(
                id: "canonical-\(index)-\(slug)",
                title: section.title,
                labeledRows: labeledRows,
                valueLines: valueLines
            )
        }
    }

    private func legacyPulledSurfaceDetailsSections(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface
    ) -> [PulledSurfaceDetailsSection] {
        var sections: [PulledSurfaceDetailsSection] = []
        let commercial = pulledCommercialSurface(
            detail,
            includeSynthesizedFulfillment: false
        )

        let profileRows = publicSurfaceFacts(pulled)
        if !profileRows.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "profile",
                    title: "Profile",
                    labeledRows: profileRows
                )
            )
        }

        var offerRows: [(label: String, value: String)] = []
        if let title = situation?.selectedOfferTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            offerRows.append(("Title", title))
        } else if let title = pulled.title.map(clean), !title.isEmpty {
            offerRows.append(("Title", title))
        }
        if let summary = situation?.selectedOfferSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            offerRows.append(("Summary", summary))
        } else if let summary = pulled.summary.map(clean), !summary.isEmpty {
            offerRows.append(("Summary", summary))
        }
        if !offerRows.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "offer",
                    title: "Offer",
                    labeledRows: offerRows
                )
            )
        }

        if !commercial.priceFacts.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "price",
                    title: "Price & packages",
                    labeledRows: commercial.priceFacts
                )
            )
        }

        let packageLines = Array(commercial.packageLines.prefix(3))
        if !packageLines.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "packages",
                    title: packageLines.count == 1 ? "Package" : "Packages",
                    valueLines: packageLines
                )
            )
        }

        if let serviceArea = commercial.serviceArea.map(clean), !serviceArea.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "serviceArea",
                    title: "Service area",
                    labeledRows: [("Area", serviceArea)]
                )
            )
        }

        var availabilityRows: [(label: String, value: String)] = []
        if let availability = commercial.availability.map(clean), !availability.isEmpty {
            availabilityRows.append(("Availability", availability))
        }
        if let fulfillment = commercial.fulfillmentLine.map(clean),
           !fulfillment.isEmpty,
           ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(fulfillment) {
            availabilityRows.append(("Fulfillment", fulfillment))
        }
        if !availabilityRows.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "availability",
                    title: "Availability",
                    labeledRows: availabilityRows
                )
            )
        }

        let buyerInputs = Array(commercial.requiredBuyerInputs.prefix(8))
        if !buyerInputs.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "buyerInputs",
                    title: "What we need from you",
                    valueLines: buyerInputs
                )
            )
        }

        let policyLines = Array(commercial.policyLines.prefix(3))
        if !policyLines.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "policies",
                    title: "Policies",
                    valueLines: policyLines
                )
            )
        }

        let faqLines = Array(commercial.faqLines.prefix(3))
        if !faqLines.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "faqs",
                    title: "FAQs",
                    valueLines: faqLines
                )
            )
        }

        if let contact = commercial.contactSummary.map(clean), !contact.isEmpty {
            sections.append(
                PulledSurfaceDetailsSection(
                    id: "contact",
                    title: "Contact",
                    labeledRows: [("Contact", contact)]
                )
            )
        }

        return sections
    }

    @ViewBuilder
    private func pulledSurfaceDetailsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkMutedText)
    }

    @ViewBuilder
    private func pulledSurfaceDetailsSectionView(_ section: PulledSurfaceDetailsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            pulledSurfaceDetailsSectionHeader(section.title)

            if !section.labeledRows.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(section.labeledRows.enumerated()), id: \.offset) { _, row in
                        compactFactLine(label: row.label, value: row.value)
                    }
                }
            }

            if !section.valueLines.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(section.valueLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func compactFactLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func surfaceChipRow(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            threadGlassCapsuleBackground()
                        }
                        .overlay(
                            Capsule()
                                .stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func situationSummary(_ situation: ExchangeThreadSituation) -> String? {
        let phase = clean(situation.agencyPhaseTitle ?? situation.phaseLabel)
        let state = clean(situation.stateSummary)

        if phase.isEmpty && state.isEmpty { return nil }
        if phase.isEmpty { return state }
        if state.isEmpty { return phase }
        if state.lowercased().contains(phase.lowercased()) { return state }

        return "\(phase). \(state)"
    }

    // MARK: - Pulled public surface

    private struct PulledPublicSurface {
        var kindTitle: String
        var kindIcon: String
        var title: String?
        var headline: String?
        var summary: String?
        var category: String?
        var tags: String?
        var regions: String?
        var openTo: String?
        var imageURL: String?

        var hasContent: Bool {
            title != nil ||
            headline != nil ||
            summary != nil ||
            category != nil ||
            tags != nil ||
            regions != nil ||
            openTo != nil ||
            imageURL != nil
        }
    }

    private func pulledPublicSurface(_ detail: ExchangeModels.ThreadDetail) -> PulledPublicSurface {
        let lead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID
        )
        let compare = SecretaryProjectionEngine.compareDisplay(for: detail)
        let lines = compare.extraSections
            .flatMap(\.lines)
            .filter(\.isRenderable)

        func value(_ labels: [String]) -> String? {
            for label in labels {
                if let line = lines.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                    let cleaned = clean(line.value)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
            return nil
        }

        let offerTitle = value(["Offer", "Offer Title", "Title"])
        let offerSummary = value(["Offer Summary", "Summary"])
        let offerImage = value(["Offer Image", "Offer Image URL", "Primary Offer Image", "Image", "Image URL"])

        let profileName = value(["Public Profile", "Profile", "Profile Name", "Display Name"])
        let profileHeadline = value(["Profile Headline", "Headline"])
        let profileSummary = value(["Profile Summary", "About"])
        let profileImage = value(["Profile Image", "Profile Image URL", "Primary Profile Image", "Public Profile Image"])

        if lead == .profileLed {
            return PulledPublicSurface(
                kindTitle: "Pulled profile",
                kindIcon: "person.crop.square",
                title: profileName ?? profileHeadline,
                headline: profileHeadline,
                summary: profileSummary ?? profileHeadline,
                category: nil,
                tags: value(["Interests", "Profile Tags", "Tags"]),
                regions: value(["Profile Regions", "Regions"]),
                openTo: value(["Open To", "Open to"]),
                imageURL: profileImage
            )
        }

        if offerTitle != nil || offerSummary != nil || offerImage != nil {
            return PulledPublicSurface(
                kindTitle: "Pulled offer",
                kindIcon: "shippingbox",
                title: offerTitle,
                headline: nil,
                summary: offerSummary,
                category: value(["Category", "Offer Category"]),
                tags: value(["Tags", "Offer Tags"]),
                regions: value(["Regions", "Offer Regions"]),
                openTo: nil,
                imageURL: offerImage ?? profileImage
            )
        }

        return PulledPublicSurface(
            kindTitle: "Pulled profile",
            kindIcon: "person.crop.square",
            title: profileName ?? profileHeadline,
            headline: profileHeadline,
            summary: profileSummary ?? profileHeadline,
            category: nil,
            tags: value(["Interests", "Profile Tags", "Tags"]),
            regions: value(["Profile Regions", "Regions"]),
            openTo: value(["Open To", "Open to"]),
            imageURL: profileImage
        )
    }

    private func cleanSurfaceSubtitle(_ value: String) -> String {
        let cleaned = clean(value)
        let lower = cleaned.lowercased()

        let looksLikeSystemState =
            lower.contains("role:") ||
            lower.contains("state:") ||
            lower.contains("qualification:") ||
            lower.contains("requester posture:") ||
            lower.contains("boundary:") ||
            lower.contains("routine non-binding") ||
            lower.contains("coordination")

        if looksLikeSystemState {
            return "Review the pulled profile or offer, then decide whether this path should continue."
        }

        return cleaned
    }

    // MARK: - Current focus card
    
    private func shouldShowCurrentFocusCard(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        let stage = stage(for: detail)

        switch stage {
        case .needsApproval, .needsAnswer, .needsCare:
            return true

        case .readyToReview:
            // When a decision packet or requester review exists, the focus card is the best place
            // to surface "why / what's missing / next" without duplicating the whole thread body.
            if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
                return display.hasDecisionPacket || display.hasRequesterReview
            }
            return false

        case .waiting, .moving:
            return false
        }
    }

    private func currentFocusCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let vs = visibleSurfaceStatus(for: detail)
        let stage = stage(for: detail)
        let chipStyle = secretaryChipStyleFromVisible(vs.tone)
        let outboundDraftReview = {
            guard stage == .needsAnswer,
                  let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) else { return false }
            return isOutboundSecondHalfClarification(display: display, detail: detail)
        }()

        let emphasize =
            stage == .needsApproval ||
            stage == .needsCare ||
            outboundDraftReview

        return threadDarkWorkCard(
            emphasizeAttention: emphasize
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    threadDarkFocusIcon(
                        systemImage: vs.systemImage,
                        chipStyle: chipStyle,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(focusTitle(detail, stage: stage))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        Text(focusSubtitle(detail, stage: stage))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                focusContent(detail, stage: stage)

                if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
                    if shouldShowSecondHalfDraft(display, detail: detail, stage: stage) {
                        draftPreview(display.draft)
                    }

                    secondHalfButtonsFiltered(display, detail: detail, stage: stage)
                } else if let draft = SecretaryProjectionEngine.latestPersistedActionableExternalOutboundDraft(for: detail),
                          shouldShowLocalDraftInFocus(detail) {
                    localDraftPreview(subject: draft.subject, body: draft.body)
                }

                focusActionRow(detail, stage: stage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func focusTitle(_ detail: ExchangeModels.ThreadDetail, stage: ThreadStage) -> String {
        visibleSurfaceStatus(for: detail).label
    }

    private func focusSubtitle(_ detail: ExchangeModels.ThreadDetail, stage: ThreadStage) -> String {
        let vs = visibleSurfaceStatus(for: detail)

        if let subtitle = vs.subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subtitle
        }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail),
           let oneLine = SecretaryProjectionEngine.nonEmpty(display.plain.plainOneLineSummary),
           !SecretaryProjectionEngine.isBlockedSystemArtifactText(oneLine) {
            return oneLine
        }

        switch stage {
        case .needsApproval:
            return "A prepared step is waiting for your review."
        case .needsAnswer:
            if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail),
               isOutboundSecondHalfClarification(display: display, detail: detail) {
                return "A message is prepared. Review it before it goes out."
            }
            return "Add the missing detail so this can continue."
        case .needsCare:
            return "Something needs attention before this can continue."
        case .readyToReview:
            return "Review the surfaced update."
        case .waiting:
            return "No reply yet after your latest movement."
        case .moving:
            return "Inspect the surfaced path."
        }
    }

    @ViewBuilder
    private func requesterPauseInfoBlocks(_ pause: ExchangeRequesterPauseFrame?) -> some View {
        if let pause {
            if !pause.answeredFacts.isEmpty {
                infoBlock(
                    "Provider answered",
                    userFacingDecisionText(pause.answeredFacts.prefix(5).joined(separator: "\n"))
                )
            }
            if !pause.stillMissingFacts.isEmpty {
                infoBlock(
                    "Still missing or unclear",
                    userFacingDecisionText(pause.stillMissingFacts.prefix(5).joined(separator: "\n"))
                )
            }
            infoBlock("Paused here", userFacingDecisionText(pause.summaryLine))
            infoBlock("Suggested next step", userFacingDecisionText(pause.nextActionLabel))
        }
    }

    @ViewBuilder
    private func focusContent(_ detail: ExchangeModels.ThreadDetail, stage: ThreadStage) -> some View {
        let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail)

        switch stage {
        case .needsApproval:
            if let display, let decision = display.decision {
                infoBlock("Summary", userFacingDecisionText(decision.summary))
                infoBlock("Recommendation", userFacingDecisionText(display.plain.recommendationSummary ?? decision.recommendation))
                infoBlock("Needs your approval", userFacingDecisionText(display.plain.approvalReason))
                requesterPauseInfoBlocks(decision.requesterPause)
            } else if let approval = SecretaryProjectionEngine.latestPendingApproval(for: detail),
                      !clean(approval.rationale).isEmpty {
                infoBlock("Why review is needed", userFacingDecisionText(approval.rationale))
            } else {
                infoBlock("Review", "A prepared step needs your review before it continues.")
            }

        case .needsAnswer:
            if let display {
                if isOutboundSecondHalfClarification(display: display, detail: detail) {
                    infoBlock("Prepared message", "A clarification message is ready for the other side.")
                    infoBlock("Next", "Review or edit it before it is sent.")
                } else {
                    let line = display.plain.primaryUserQuestion
                        ?? localUserClarificationLine(display: display, detail: detail)
                        ?? SecretaryProjectionEngine.clarificationQuestion(detail)
                    infoBlock("Needed from you", userFacingDecisionText(line))
                }
            } else {
                infoBlock("Needed from you", SecretaryProjectionEngine.clarificationQuestion(detail))
            }

        case .needsCare:
            if let failure = detail.thread.latestFailure {
                let next = clean(failure.recommendedNextStep.summaryLine)
                let happened = clean(failure.whatHappened)
                infoBlock(
                    "What to know",
                    !next.isEmpty ? next : (happened.isEmpty ? "This thread needs a quick fix before it can continue." : clipped(happened, max: 280))
                )
            } else if let display {
                infoBlock("What to know", userFacingDecisionText(display.summary))
            } else {
                infoBlock("What to know", "This thread needs a quick fix before it can continue.")
            }

        case .readyToReview:
            if let display {
                infoBlock("Status", userFacingDecisionText(display.plain.plainStatusLabel))
                if let decision = display.decision {
                    infoBlock("Summary", userFacingDecisionText(decision.summary))
                    infoBlock("Recommendation", userFacingDecisionText(display.plain.recommendationSummary ?? decision.recommendation))
                    infoBlock("Still missing", userFacingDecisionText(display.plain.missingInfoSummary))
                    infoBlock("Ask next", userFacingDecisionText(display.plain.followUpReason))
                    requesterPauseInfoBlocks(decision.requesterPause)
                } else if let provider = display.providerReception {
                    infoBlock("They said", display.plain.providerReplySummary ?? provider.requesterAsk ?? provider.inquirySummary ?? provider.subtitle)
                    infoBlock("Fit", display.plain.impliedFlexibilitySummary ?? provider.leadStrength)
                    infoBlock("Contradiction", display.plain.contradictionSummary)
                    infoBlock("Still missing", display.plain.missingInfoSummary)
                    infoBlock("Ask next", display.plain.followUpReason)
                } else if let requester = display.requesterReview {
                    infoBlock("Review", userFacingDecisionText(requester.subtitle))
                    if let recommendation = requester.recommendation {
                        infoBlock("Recommendation", userFacingDecisionText(recommendation))
                    }
                    infoBlock("Still missing", userFacingDecisionText(display.plain.missingInfoSummary))
                    infoBlock("Ask next", userFacingDecisionText(display.plain.followUpReason))
                    requesterPauseInfoBlocks(requester.pauseFrame)
                } else {
                    infoBlock("Now", userFacingDecisionText(display.plain.plainOneLineSummary))
                }
            } else {
                infoBlock("Now", SecretaryProjectionEngine.foundSummary(detail))
                if let selected = SecretaryProjectionEngine.selectedCounterpartyName(for: detail) {
                    infoBlock("Selected path", selected)
                }
            }

        case .waiting:
            if let display {
                let summaryLine =
                    SecretaryProjectionEngine.secondHalfSummaryLine(display) ?? display.plain.plainOneLineSummary
                infoBlock("Now", userFacingDecisionText(clean(summaryLine).isEmpty ? "Waiting for the other side." : summaryLine))
            } else {
                infoBlock("Now", "Waiting for the other side.")
            }

        case .moving:
            if let display {
                infoBlock(
                    "Now",
                    userFacingDecisionText(SecretaryProjectionEngine.secondHalfSummaryLine(display) ?? display.summary)
                )
            } else {
                infoBlock("Now", SecretaryProjectionEngine.threadHeroSummary(detail))
            }
        }
    }

    private func userFacingDecisionText(_ value: String?) -> String? {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return nil }

        let lower = cleaned.lowercased()
        let looksInternal =
            lower.contains("role:") ||
            lower.contains("state:") ||
            lower.contains("qualification:") ||
            lower.contains("requester posture:") ||
            lower.contains("boundary:") ||
            lower.contains("routine non-binding") ||
            lower.contains("outbound probe:") ||
            lower.contains("deterministic") ||
            lower.contains("schema") ||
            lower.contains("pass 1") ||
            lower.contains("pass 2") ||
            lower.contains("pass 3")

        if looksInternal {
            if lower.contains("waiting") {
                return "Waiting for the other side."
            }
            if lower.contains("clarification") {
                return "One clarification may help this move forward."
            }
            return "Review the visible profile, offer, and messages before deciding the next step."
        }

        return cleaned
    }

    @ViewBuilder
    private func focusActionRow(_ detail: ExchangeModels.ThreadDetail, stage: ThreadStage) -> some View {
        let showReview = shouldShowReviewAction(detail, stage: stage)
        let showAnswer = shouldShowAnswerAction(detail, stage: stage)
        let showRecover = stage == .needsCare
        let showDetails = (stage == .waiting || stage == .moving) && hasUsefulMoreContext(detail)

        if showReview || showAnswer || showRecover || showDetails || canArchive(detail) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if showReview {
                    SecretaryActionButton(
                        title: "Review now",
                        systemImage: "checkmark.seal",
                        prominent: true,
                        tone: .approval,
                        chrome: .exchangeDark
                    ) {
                        onOpenApprovalSheet?(SecretaryProjectionEngine.approvalDisplay(for: detail))
                    }
                }

                if showAnswer {
                    SecretaryActionButton(
                        title: "Add detail",
                        systemImage: "questionmark.circle",
                        prominent: true,
                        tone: .approval,
                        chrome: .exchangeDark
                    ) {
                        onOpenClarification?(detail.thread.id)
                    }
                }

                if showRecover {
                    SecretaryActionButton(
                        title: "Recover",
                        systemImage: "arrow.clockwise",
                        prominent: true,
                        tone: .recovery,
                        chrome: .exchangeDark
                    ) {
                        onOpenRecoveryPanel?(SecretaryProjectionEngine.recoveryDisplay(for: detail))
                    }
                }

                if showDetails {
                    SecretaryActionButton(
                        title: "See context",
                        systemImage: "line.3.horizontal",
                        prominent: false,
                        tone: .secondary,
                        chrome: .exchangeDark
                    ) {
                        guard providerDetailsPresentation?.hasMoreDetails == true else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showMoreContext = true
                        }
                    }
                }

                if canArchive(detail) {
                    Button {
                        showArchiveConfirmation = true
                    } label: {
                        Text("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shouldShowReviewAction(
        _ detail: ExchangeModels.ThreadDetail,
        stage: ThreadStage
    ) -> Bool {
        if SecretaryProjectionEngine.threadViewDirectApproveAndSendEligible(for: detail) {
            return false
        }

        if let _ = SecretaryProjectionEngine.latestPendingApproval(for: detail) {
            if SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail) {
                return false
            }
            return true
        }

        guard let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) else {
            guard stage == .needsApproval else { return false }
            return !SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail)
        }

        if display.placement == .needsApproval {
            return !SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail)
        }

        if stage == .needsAnswer, isOutboundSecondHalfClarification(display: display, detail: detail) {
            return SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail)
                && SecretaryProjectionEngine.nonEmpty(display.draft?.bodyPreview) != nil
        }

        return false
    }

    private func shouldShowAnswerAction(
        _ detail: ExchangeModels.ThreadDetail,
        stage: ThreadStage
    ) -> Bool {
        guard stage == .needsAnswer else { return false }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail),
           isOutboundSecondHalfClarification(display: display, detail: detail) {
            return false
        }

        return true
    }

    private func shouldShowSecondHalfDraft(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail,
        stage: ThreadStage
    ) -> Bool {
        let actionable = SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail)
        let hasNonEmptyPreview = SecretaryProjectionEngine.nonEmpty(display.draft?.bodyPreview) != nil
        guard actionable && hasNonEmptyPreview else { return false }
        if stage == .needsApproval { return true }
        if stage == .needsAnswer, isOutboundSecondHalfClarification(display: display, detail: detail) { return true }
        if display.placement == .needsApproval { return true }
        return false
    }

    private func shouldShowLocalDraftInFocus(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        stage(for: detail) == .needsApproval
    }

    // MARK: - Conversation
    
    private func compactConversationActionButton(
        title: String,
        systemImage: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrange.opacity(0.95))
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(
                color: SecretaryTheme.darkOrange.opacity(0.22),
                radius: 8,
                x: 0,
                y: 3
            )
            .opacity(isBusy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func conversationSection(_ detail: ExchangeModels.ThreadDetail) -> some View {
        SecretaryThreadTranscriptView(
            detail: detail,
            trailingAction: conversationIntegratedTrailingAction(detail)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Provider inbound uses ``SecretaryProjectionEngine/providerInboundReplyBarIntent``; requester uses trusted **Message**.
    /// Same footer slot as before — no separate reply surface card.
    private func conversationIntegratedTrailingAction(_ detail: ExchangeModels.ThreadDetail) -> AnyView? {
        if let intent = SecretaryProjectionEngine.providerInboundReplyBarIntent(for: detail) {
            let title: String
            let systemImage: String

            switch intent {
            case .openStructuredClarification:
                title = "Answer"
                systemImage = "questionmark.circle"

            case .openInboundReplyComposer:
                title = SecretaryProjectionEngine.providerInboundConversationActionLabel(for: detail)
                systemImage = "arrow.turn.up.left"
            }

            return AnyView(
                compactConversationActionButton(
                    title: title,
                    systemImage: systemImage
                ) {
                    switch intent {
                    case .openStructuredClarification:
                        onOpenClarification?(detail.thread.id)

                    case .openInboundReplyComposer:
                        let displayName = SecretaryProjectionEngine.directMessageRecipientDisplayName(for: detail)
                        directMessageCompose = SecretaryDirectMessageComposeRoute(
                            trustedNodeID: nil,
                            displayName: displayName
                        )
                    }
                }
            )
        }

        if let message = messageButton(detail) {
            return message
        }

        return connectButton()
    }

    private func messageButton(_ detail: ExchangeModels.ThreadDetail) -> AnyView? {
        guard SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail),
              let nodeID = SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail)
        else {
            return nil
        }

        let displayName = SecretaryProjectionEngine.directMessageRecipientDisplayName(for: detail)

        return AnyView(
            compactConversationActionButton(
                title: "Message",
                systemImage: "bubble.left.and.bubble.right"
            ) {
                directMessageCompose = SecretaryDirectMessageComposeRoute(
                    trustedNodeID: nodeID,
                    displayName: displayName
                )
            }
        )
    }

    private func connectButton() -> AnyView? {
        guard connectTarget != nil else { return nil }

        return AnyView(
            compactConversationActionButton(
                title: connectBusy ? "Connecting…" : "Connect",
                systemImage: "person.badge.plus",
                isBusy: connectBusy
            ) {
                Task { @MainActor in
                    await sendConnectRequest()
                }
            }
        )
    }

    @MainActor
    private func sendConnectRequest() async {
        guard !connectBusy else { return }
        guard let target = connectTarget else {
            connectResultMessage = "No matched contact target is available in this thread."
            return
        }
        guard let sourceNodeID = await services.exchangeNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceNodeID.isEmpty else {
            connectResultMessage = "Your local node is not ready yet."
            return
        }

        connectBusy = true
        defer { connectBusy = false }
        do {
            let result = try await services.exchangeFacade.sendContactRequestToNode(
                sourceNodeID: sourceNodeID,
                targetNodeID: target.nodeID,
                displayNameOverride: target.displayName,
                note: nil,
                now: Date()
            )
            connectResultMessage = "Request sent to \(result.targetNodeID)."
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": threadID.uuidString]
            )
        } catch {
            connectResultMessage = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "ThreadConnectSend"
            )
        }
    }

    // MARK: - Artifact-only middle cards

    private func showDraftOrPreparedMessage(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail)
    }

    @ViewBuilder
    private func draftOrPreparedMessageCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let panelDisplay = SecretaryProjectionEngine.approvalDisplay(for: detail)
        let directApprove = SecretaryProjectionEngine.threadViewDirectApproveAndSendEligible(for: detail)
        let autonomySuppressesSend = SecretaryProjectionEngine.threadViewAutonomousRoutineSuppressesManualSend(for: detail)
        let autonomyBlocked = SecretaryProjectionEngine.threadViewAutonomyGateDeniedExplanation(for: detail)
        let autonomyPipeline = SecretaryProjectionEngine.threadViewAutonomousOutboundPipelineExplanation(for: detail)

        threadDarkWorkCard(
            emphasizeAttention: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)

                    Text("Draft ready")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail),
                   let draft = display.draft,
                   !clean(draft.bodyPreview).isEmpty {
                    inlineDraftPreview(
                        subject: draft.subject,
                        body: draft.bodyPreview
                    )
                } else if let draft = SecretaryProjectionEngine.latestPersistedActionableExternalOutboundDraft(for: detail),
                          !clean(draft.body).isEmpty {
                    inlineDraftPreview(
                        subject: draft.subject,
                        body: draft.body
                    )
                }

                if let blocked = autonomyBlocked, !blocked.isEmpty {
                    Text(blocked)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if autonomySuppressesSend {
                    if let autonomyPipeline, !autonomyPipeline.isEmpty {
                        Text(autonomyPipeline)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        compactConversationActionButton(
                            title: directApprove ? "Send" : "Review",
                            systemImage: directApprove ? "paperplane.fill" : "checkmark.seal",
                            isBusy: outboundApproveBusy
                        ) {
                            if directApprove {
                                Task {
                                    await approveOutboundDraftFromThreadCard(
                                        detail: detail,
                                        panelDisplay: panelDisplay
                                    )
                                }
                            } else {
                                onOpenApprovalSheet?(panelDisplay)
                            }
                        }
                    }
                }

                if let nudge = SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail) {
                    Text(nudge)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor
    private func approveOutboundDraftFromThreadCard(
        detail: ExchangeModels.ThreadDetail,
        panelDisplay: SecretaryApprovalPanelDisplay
    ) async {
        outboundApproveBusy = true
        outboundApproveError = nil
        defer { outboundApproveBusy = false }

        do {
            let ok = try await SecretaryOutboundApproveSend.perform(
                display: panelDisplay,
                exchangeFacade: services.exchangeFacade,
                permit: .userApproved(source: "SecretaryThreadView.draftCard")
            )
            guard ok else {
                outboundApproveError =
                    "Couldn’t queue the send yet. Use Review for details, or try again."
                return
            }

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": detail.thread.id.uuidString]
            )

            await load(showSpinner: false)
            services.requestSecretaryRefresh(.approvalChanged)

            Task {
                await services.exchangeSyncEngine.runPass(
                    trigger: .afterApprovalGranted,
                    now: Date()
                )
            }
        } catch {
            outboundApproveError =
                "Couldn’t complete send. Check connectivity and try again, or open Review."
        }
    }

    @ViewBuilder
    private func requesterAssessmentSection(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let mode = SecretaryProjectionEngine.threadViewRequesterAssessmentMode(for: detail)
        let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail)
        let requesterTitle = ExchangeSecondHalfRole.requester.displayTitle
        let isRequester = display?.status.role == requesterTitle

        switch mode {
        case .hidden:
            EmptyView()
        case .cleanNoMatch:
            if isRequester || display == nil {
                if shouldOfferCleanNoMatchAssessmentStub(detail) {
                    cleanNoMatchAssessmentCard()
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        case .rich:
            if isRequester, let display {
                let facts = filteredRequesterAssessmentFacts(display, detail: detail)
                if !facts.isEmpty {
                    requesterAssessmentCard(facts: facts)
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }

    /// When the thread is busy with drafts, approval, delivery, or provider cards, skip the extra no-match stub (hero already carries the status).
    private func shouldOfferCleanNoMatchAssessmentStub(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        !showDraftOrPreparedMessage(detail)
            && !showProviderAssessment(detail)
            && !threadViewShouldShowApprovalRequiredCard(detail)
            && !showDeliveryFailure(detail)
    }

    private func cleanNoMatchAssessmentCard() -> some View {
        threadDarkWorkCard(
            emphasizeAttention: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                    Text("No match found")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Unify did not find a confirmed offer or profile for this request yet.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Try widening the search or changing the request.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requesterAssessmentCard(facts: [String]) -> some View {
        threadDarkWorkCard(
            emphasizeAttention: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                    Text("Quick read")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(facts.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func showProviderAssessment(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        guard let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) else { return false }
        guard display.status.role == ExchangeSecondHalfRole.provider.displayTitle else { return false }
        return !filteredProviderAssessmentFacts(display, detail: detail).isEmpty
    }

    private func providerAssessmentCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail)
        let facts = display.map { filteredProviderAssessmentFacts($0, detail: detail) } ?? []
        return threadDarkWorkCard(
            emphasizeAttention: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                    Text("Inquiry summary")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(facts.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Sole gate for rendering ``approvalRequiredCard`` (“Approval needed” surface).
    private func threadViewShouldShowApprovalRequiredCard(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        let pending = SecretaryProjectionEngine.latestPendingApproval(for: detail)
        let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail)
        let boundaryWantsAttention = display.map {
            $0.boundary.requiresHumanApproval && !clean($0.boundary.reason).isEmpty
        } ?? false

        let wouldShowApprovalSurface = pending != nil || boundaryWantsAttention
        guard wouldShowApprovalSurface else {
            return false
        }

        if SecretaryProjectionEngine.shouldSuppressProviderInboundApprovalCard(for: detail) {
            #if DEBUG
            Swift.print(
                "[SecretaryThreadView] suppress approval card providerInboundNoDraft thread=\(detail.thread.id.uuidString) pendingApproval=\(pending?.id.uuidString ?? "nil") drafts=\(detail.drafts.count) outbox=\(detail.outboxItems.count)"
            )
            #endif
            return false
        }

        #if DEBUG
        let reason: String
        if pending != nil {
            reason = "pendingApproval"
        } else {
            reason = "boundaryRequiresHumanApproval"
        }
        Swift.print(
            "[SecretaryThreadView] show approval card reason=\(reason) thread=\(detail.thread.id.uuidString)"
        )
        #endif
        return true
    }

    private func approvalRequiredCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let approval = SecretaryProjectionEngine.latestPendingApproval(for: detail)
        let reason = approval?.rationale ?? SecretaryProjectionEngine.secondHalfDisplay(for: detail)?.boundary.reason
        let cleanedReason = clean(reason)
        let lowerReason = cleanedReason.lowercased()
        let specific = lowerReason.contains("money") ||
            lowerReason.contains("payment") ||
            lowerReason.contains("commit") ||
            lowerReason.contains("private")

        return threadDarkWorkCard(
            emphasizeAttention: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    Text("Approval needed")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    specific
                    ? "This needs your approval because it may involve money, a commitment, or private information."
                    : "This message needs your review before it goes out."
                )
                .font(.system(size: 14.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

                if showDraftOrPreparedMessage(detail) {
                    if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail),
                       let draft = display.draft,
                       !clean(draft.bodyPreview).isEmpty {
                        inlineDraftPreview(
                            subject: draft.subject,
                            body: draft.bodyPreview
                        )
                    } else if let draft = SecretaryProjectionEngine.latestPersistedActionableExternalOutboundDraft(for: detail),
                              !clean(draft.body).isEmpty {
                        inlineDraftPreview(
                            subject: draft.subject,
                            body: draft.body
                        )
                    }
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    compactConversationActionButton(
                        title: "Review",
                        systemImage: "checkmark.seal"
                    ) {
                        onOpenApprovalSheet?(SecretaryProjectionEngine.approvalDisplay(for: detail))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func showDeliveryFailure(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        if detail.thread.latestFailure?.kind == .deliveryFailure { return true }
        if detail.thread.delivery?.status == .failed { return true }
        return false
    }

    private func deliveryFailureCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let line = clean(
            detail.thread.latestFailure?.recommendedNextStep.summaryLine ??
                detail.thread.latestFailure?.visibleExplanation ??
                detail.thread.delivery?.note ??
                "Your last message did not send. Retry or edit before sending again."
        )
        return threadDarkWorkCard(
            emphasizeAttention: true
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                    Text("Delivery issue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(line)
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requesterAssessmentFacts(_ display: ExchangeSecondHalfUIAdapter.DisplayModel) -> [String] {
        cleanedArtifactLines([
            display.plain.recommendationSummary,
            display.plain.providerReplySummary,
            display.plain.missingInfoSummary,
            display.plain.followUpReason,
            display.plain.contradictionSummary,
            display.plain.impliedFlexibilitySummary,
            display.decision?.summary,
            display.decision?.recommendation,
            display.requesterReview?.recommendation
        ])
        .map { scrubSystemText($0) }
        .filter { !$0.isEmpty }
    }

    private func shouldSuppressWaitingForProviderAssessmentCopy(detail: ExchangeModels.ThreadDetail) -> Bool {
        ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(
            in: detail.drafts,
            thread: detail.thread,
            turns: detail.turns
        )
    }

    /// Normalized text for Quick read phase heuristics (local only; does not replace global sanitizers).
    private func normalizedRequesterQuickReadLine(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private func shouldRemoveWaitingProviderAssessmentLine(_ line: String) -> Bool {
        let n = normalizedRequesterQuickReadLine(line)

        switch n {
        case "waiting for the provider's reply.",
             "waiting for the provider's reply",
             "once they respond, unify will refresh this summary.",
             "once they respond, unify will refresh this summary",
             "wait for reply",
             "waiting for their reply",
             "waiting for reply",
             "waiting on the other side",
             "waiting for the other side.",
             "waiting for the other side":
            return true
        default:
            break
        }

        if n.hasPrefix("waiting for the provider"), n.contains("reply") {
            return true
        }

        if n.contains("waiting"), n.contains("reply") {
            return true
        }

        if n.contains("once they respond") {
            return true
        }

        if n.contains("waiting on the other side") {
            return true
        }

        return false
    }

    /// How aggressively to trim Quick read lines for requester role (transport-first; local to ThreadView).
    private enum RequesterQuickReadFilterPhase: Equatable {
        case none
        case trimWaitingProviderOnly
        case suppressPreSendDiagnostics
    }

    private func requesterQuickReadPhase(
        for detail: ExchangeModels.ThreadDetail,
        visibleStatus: SecretaryProjectionEngine.ExchangeVisibleThreadStatus
    ) -> RequesterQuickReadFilterPhase {
        switch visibleStatus.primary {
        case .waitingForReply, .replyReceived:
            return .suppressPreSendDiagnostics
        case .draftReady:
            if showDraftOrPreparedMessage(detail) {
                return .suppressPreSendDiagnostics
            }
            fallthrough
        default:
            if shouldSuppressWaitingForProviderAssessmentCopy(detail: detail) {
                return .trimWaitingProviderOnly
            }
            return .none
        }
    }

    private func isPreSendDiagnosticQuickReadLine(_ line: String) -> Bool {
        let n = normalizedRequesterQuickReadLine(line)
        if n.contains("useful asks:") { return true }
        if n.contains("match review") { return true }
        if n.contains("reconcile this concern") { return true }
        if n.contains("trust and verification signal") { return true }
        if n.contains("overall fit is still too weak") { return true }
        if n.contains("fit is still too weak") { return true }
        if n.contains("weak to advance") { return true }
        if n.contains("recommended question") { return true }
        if n.contains("qualification tier") { return true }
        if n.contains("weakness reason") { return true }
        return false
    }

    /// "Still missing:" rollups that read like pre-send review, not a short actionable gap line.
    private func isStaleMissingInfoQuickReadLine(_ line: String) -> Bool {
        let n = normalizedRequesterQuickReadLine(line)
        guard n.contains("still missing:") else { return false }
        if n.count < 100 {
            let reviewSignals = [
                "weak", "fit", "tier", "verification", "review", "match",
                "qualification", "signal", "overall", "trust", "asks:"
            ]
            guard reviewSignals.contains(where: { n.contains($0) }) else { return false }
        }
        return true
    }

    /// Requester-review recommendation prose that describes fit assessment rather than current transport posture.
    private func isRequesterReviewStyleFitReviewLine(_ line: String) -> Bool {
        let n = normalizedRequesterQuickReadLine(line)
        if isPreSendDiagnosticQuickReadLine(line) { return false }
        if n.contains("overall fit") { return true }
        if n.contains("fit is") && (n.contains("weak") || n.contains("uncertain") || n.contains("limited")) {
            return true
        }
        if n.contains("hesitant") && n.contains("advance") { return true }
        if n.contains("not strong enough") { return true }
        if n.contains("confidence") && (n.contains("low") || n.contains("limited")) { return true }
        if n.contains("match") && n.contains("weak") && n.contains("signal") { return true }
        return false
    }

    #if DEBUG
    private func logQuickReadFilterSuppressed(
        reason: String,
        visibleStatus: SecretaryProjectionEngine.ExchangeVisibleThreadStatus,
        line: String
    ) {
        let preview: String
        if line.count > 160 {
            preview = String(line.prefix(160)) + "…"
        } else {
            preview = line
        }
        Swift.print(
            "[QuickReadFilter] suppressed reason=\(reason) status=\(visibleStatus.primary) line=\(preview)"
        )
    }
    #endif

    private func shouldSuppressRequesterQuickReadLine(
        _ line: String,
        visibleStatus: SecretaryProjectionEngine.ExchangeVisibleThreadStatus,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        let phase = requesterQuickReadPhase(for: detail, visibleStatus: visibleStatus)
        let suppress: Bool
        let reason: String
        switch phase {
        case .none:
            return false
        case .trimWaitingProviderOnly:
            suppress = shouldRemoveWaitingProviderAssessmentLine(line)
            reason = "redundantWaitingCopy"
        case .suppressPreSendDiagnostics:
            if shouldRemoveWaitingProviderAssessmentLine(line) {
                suppress = true
                reason = "redundantWaitingCopy"
            } else if isPreSendDiagnosticQuickReadLine(line) {
                suppress = true
                reason = "preSendDiagnostic"
            } else if isStaleMissingInfoQuickReadLine(line) {
                suppress = true
                reason = "staleMissingInfo"
            } else if isRequesterReviewStyleFitReviewLine(line) {
                suppress = true
                reason = "requesterReviewFitReview"
            } else {
                return false
            }
        }
        #if DEBUG
        if suppress {
            logQuickReadFilterSuppressed(
                reason: reason,
                visibleStatus: visibleStatus,
                line: line
            )
        }
        #endif
        return suppress
    }

    private func filteredRequesterAssessmentFacts(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail
    ) -> [String] {
        let visibleStatus = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        let passed = requesterAssessmentFacts(display).filter {
            SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy($0)
        }
        return passed.filter {
            !shouldSuppressRequesterQuickReadLine($0, visibleStatus: visibleStatus, detail: detail)
        }
    }

    private func providerAssessmentFacts(_ display: ExchangeSecondHalfUIAdapter.DisplayModel) -> [String] {
        providerSafeAssessmentLines(from: display)
    }

    private func providerSafeAssessmentLines(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        let result = ExchangeProviderInboundAssessmentProjection.safeAssessmentLines(from: display)
        #if DEBUG
        if result.inputCount != result.outputCount
            || result.removedInternal > 0
            || result.removedDuplicate > 0
            || result.removedPerspectiveLeak > 0 {
            Swift.print(
                "[ProviderAssessmentClean] inputCount=\(result.inputCount) outputCount=\(result.outputCount) " +
                "removedInternal=\(result.removedInternal) removedDuplicate=\(result.removedDuplicate) " +
                "removedPerspectiveLeak=\(result.removedPerspectiveLeak)"
            )
        }
        #endif
        return result.lines
    }

    private func filteredProviderAssessmentFacts(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail
    ) -> [String] {
        providerAssessmentFacts(display).filter { line in
            guard SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy(line) else { return false }
            return !ExchangeModels.ThreadTranscriptBuilder.providerAssessmentLineDuplicatesInboundTranscript(
                line,
                detail: detail
            )
        }
    }

    private func cleanedArtifactLines(_ values: [String?]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            let text = clean(value)
            guard !text.isEmpty else { continue }
            guard !SecretaryProjectionEngine.isBlockedSystemArtifactText(text) else { continue }
            let key = text.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(text)
        }
        return output
    }

    // MARK: - More context

    @ViewBuilder
    private func pulledSurfaceDetailsSectionsBody(
        _ sections: [PulledSurfaceDetailsSection],
        topPadding: CGFloat = 2
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                pulledSurfaceDetailsSectionView(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topPadding)
    }

    @ViewBuilder
    private func pulledSurfaceDetailsHeader(
        presentation: ThreadProviderDetailsPresentation
    ) -> some View {
        if presentation.hasMoreDetails {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showMoreContext.toggle()
                }
            } label: {
                pulledSurfaceDetailsHeaderRow(
                    presentation: presentation,
                    showsExpansionAffordance: true
                )
            }
            .buttonStyle(.plain)
        } else {
            pulledSurfaceDetailsHeaderRow(
                presentation: presentation,
                showsExpansionAffordance: false
            )
        }
    }

    private func pulledSurfaceDetailsHeaderRow(
        presentation: ThreadProviderDetailsPresentation,
        showsExpansionAffordance: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)

            Text("Details")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Spacer(minLength: 0)

            if showsExpansionAffordance {
                Text(showMoreContext ? "Less" : "More")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                Image(systemName: showMoreContext ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func providerDetailsVisibleVisualLayout(
        for presentation: ThreadProviderDetailsPresentation,
        expanded: Bool
    ) -> ThreadDetailsVisualLayout? {
        if presentation.hasMoreDetails {
            return expanded ? presentation.expandedVisualLayout : presentation.compactVisualLayout
        }
        if let compact = presentation.compactVisualLayout, compact.hasContent {
            return compact
        }
        return presentation.expandedVisualLayout
    }

    @ViewBuilder
    private func pulledSurfaceDetailsBody(
        presentation: ThreadProviderDetailsPresentation,
        visibleSections: [PulledSurfaceDetailsSection]
    ) -> some View {
        let useExpanded = showMoreContext && presentation.hasMoreDetails
        let visualLayout = providerDetailsVisibleVisualLayout(
            for: presentation,
            expanded: useExpanded
        )

        if let visualLayout,
           ThreadDetailsVisualCard.hasRenderableContent(for: visualLayout) {
            ThreadDetailsVisualCard(layout: visualLayout)
        } else if !visibleSections.isEmpty {
            pulledSurfaceDetailsSectionsBody(visibleSections, topPadding: 0)
        }
    }

    @ViewBuilder
    private func pulledSurfaceDetailsToggle(
        detail: ExchangeModels.ThreadDetail,
        pulled: PulledPublicSurface,
        heroOverlayExpansionMaxHeight: CGFloat? = nil
    ) -> some View {
        let presentation = providerDetailsPresentation
        let hasAny = presentation?.hasAnyContent ?? false

        if hasAny, let presentation {
            let visibleSections = providerDetailsVisibleSections(
                for: presentation,
                expanded: showMoreContext && presentation.hasMoreDetails
            )

            threadDarkWorkCard(emphasizeAttention: false) {
                VStack(alignment: .leading, spacing: 12) {
                    pulledSurfaceDetailsHeader(presentation: presentation)

                    pulledSurfaceDetailsBody(
                        presentation: presentation,
                        visibleSections: visibleSections
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    

    // MARK: - Autonomous send audit (observability)

    @ViewBuilder
    private func autonomousSendAuditTraceSection(_ detail: ExchangeModels.ThreadDetail) -> some View {
#if DEBUG
        let lines = SecretaryAutonomousSendAuditTrace.displayLines(from: detail.auditRecords)
        if !lines.isEmpty {
            threadDarkWorkCard(emphasizeAttention: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)

                        Text("Autonomous send activity")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
#else
        EmptyView()
#endif
    }

    @ViewBuilder
    private func secondHalfMeaningCard(_ display: ExchangeSecondHalfUIAdapter.DisplayModel) -> some View {
        let unresolved = display.plain.unresolvedConditionChips
        let possibleFit = display.plain.impliedFlexibilitySummary ?? ""
        let contradiction = display.plain.contradictionSummary ?? ""
        let followUp = display.plain.followUpReason ?? ""
        let blocked = display.plain.approvalReason ?? display.plain.blockedReason ?? ""

        if !unresolved.isEmpty || !clean(possibleFit).isEmpty || !clean(contradiction).isEmpty || !clean(followUp).isEmpty || !clean(blocked).isEmpty {
            threadDarkWorkCard(
                emphasizeAttention: false
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                        Text("Why this thread is here")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !clean(contradiction).isEmpty {
                        infoBlock("Main condition contradicted", contradiction)
                    }
                    if !clean(possibleFit).isEmpty {
                        infoBlock("Possible fit", possibleFit)
                    }
                    if !unresolved.isEmpty {
                        infoBlock("Still missing", display.plain.missingInfoSummary ?? unresolved.joined(separator: ", "))
                    }
                    if !clean(followUp).isEmpty {
                        infoBlock("Ask next", followUp)
                    }
                    if !clean(blocked).isEmpty {
                        infoBlock("Needs your approval", blocked)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func hasUsefulMoreContext(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        let pulled = pulledPublicSurface(detail)
        if !publicSurfaceFacts(pulled).isEmpty { return true }
        if pulledCommercialSurface(detail).hasContent { return true }
        return false
    }

    @ViewBuilder
    private func compareReviewContext(
        _ detail: ExchangeModels.ThreadDetail,
        compare: SecretaryComparePanel.Display
    ) -> some View {
        if let option = preferredCompareOption(compare) {
            selectedCompareOptionContext(option)
        } else {
            aggregateCompareContext(compare)
        }

        usefulPanelSections(compare)

        let activity = SecretaryProjectionEngine.activityDisplay(for: detail)
        if !clean(activity.latestMovement).isEmpty ||
            !clean(activity.meaning).isEmpty ||
            !clean(activity.nextMove).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                reviewMiniHeader(
                    title: "Thread update",
                    systemImage: "arrow.triangle.branch"
                )

                if !clean(activity.latestMovement).isEmpty {
                    reviewLine(label: "Latest", value: scrubSystemText(activity.latestMovement))
                }

                if !clean(activity.meaning).isEmpty {
                    reviewLine(label: "Meaning", value: scrubSystemText(activity.meaning))
                }

                if !clean(activity.nextMove).isEmpty {
                    reviewLine(label: "Next", value: scrubSystemText(activity.nextMove))
                }
            }
        }
    }

    @ViewBuilder
    private func selectedCompareOptionContext(_ option: SecretaryCompareOptionDisplay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            reviewMiniHeader(
                title: "Path review",
                systemImage: "sparkles.rectangle.stack"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(scrubSystemText(option.title))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !clean(option.subtitle).isEmpty {
                    Text(scrubSystemText(option.subtitle))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineSpacing(1.2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                reviewMetricPill(
                    value: scrubSystemText(option.trustLine),
                    label: "Trust"
                )

                reviewMetricPill(
                    value: clean(option.readinessLine).isEmpty ? "Unknown" : scrubSystemText(option.readinessLine),
                    label: "Readiness"
                )
            }

            if !clean(option.exposureLine).isEmpty {
                reviewLine(label: "Exposure", value: scrubSystemText(option.exposureLine))
            }

            if !clean(option.recommendationLine).isEmpty {
                reviewLine(label: "Recommendation", value: scrubSystemText(option.recommendationLine))
            }

            if !clean(option.nextMoveLine).isEmpty {
                reviewLine(label: "Next", value: scrubSystemText(option.nextMoveLine))
            }

            reviewList(
                title: "Strengths",
                systemImage: "checkmark.circle",
                values: option.strengthReasons,
                maxItems: 4
            )

            reviewList(
                title: "Missing details",
                systemImage: "questionmark.circle",
                values: option.missingFacts,
                maxItems: 4
            )

            reviewList(
                title: "Risks",
                systemImage: "exclamationmark.circle",
                values: option.weaknessReasons,
                maxItems: 4
            )
        }
    }

    @ViewBuilder
    private func aggregateCompareContext(_ compare: SecretaryComparePanel.Display) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            reviewMiniHeader(
                title: "Review summary",
                systemImage: "rectangle.and.text.magnifyingglass"
            )

            HStack(spacing: 10) {
                reviewMetricPill(
                    value: clean(compare.trustSummary).isEmpty ? "Unknown" : scrubSystemText(compare.trustSummary),
                    label: "Trust"
                )

                reviewMetricPill(
                    value: clean(compare.readinessSummary).isEmpty ? "Unknown" : scrubSystemText(compare.readinessSummary),
                    label: "Readiness"
                )
            }

            if !clean(compare.exposureSummary).isEmpty {
                reviewLine(label: "Exposure", value: scrubSystemText(compare.exposureSummary))
            }

            if !clean(compare.recommendation).isEmpty {
                reviewLine(label: "Recommendation", value: scrubSystemText(compare.recommendation))
            }

            reviewList(
                title: "Strengths",
                systemImage: "checkmark.circle",
                values: compare.strengthReasons,
                maxItems: 4
            )

            reviewList(
                title: "Missing details",
                systemImage: "questionmark.circle",
                values: compare.missingFacts,
                maxItems: 4
            )

            reviewList(
                title: "Risks",
                systemImage: "exclamationmark.circle",
                values: compare.weaknessReasons,
                maxItems: 4
            )
        }
    }

    @ViewBuilder
    private func usefulPanelSections(_ compare: SecretaryComparePanel.Display) -> some View {
        let sections = compare.extraSections.compactMap { usefulPanelSection($0) }

        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections.prefix(3)) { section in
                    usefulPanelSectionView(section)
                }
            }
        }
    }

    private func usefulPanelSection(
        _ section: SecretaryPanelSectionDisplay
    ) -> SecretaryPanelSectionDisplay? {
        let cleanedTitle = clean(section.title)
        guard !cleanedTitle.isEmpty else { return nil }

        let lower = cleanedTitle.lowercased()

        let allowed =
            lower.contains("commercial") ||
            lower.contains("offer") ||
            lower.contains("profile") ||
            lower.contains("surface") ||
            lower.contains("trust") ||
            lower.contains("fit") ||
            lower.contains("readiness")

        guard allowed else { return nil }

        let cleanedLines = section.lines.filter { line in
            let label = clean(line.label)
            let value = clean(line.value)
            guard !label.isEmpty, !value.isEmpty else { return false }

            let combined = "\(label) \(value)".lowercased()
            return !looksLikeSystemNoise(combined)
        }

        guard !cleanedLines.isEmpty else { return nil }

        return SecretaryPanelSectionDisplay(
            id: section.id,
            title: cleanedTitle,
            systemImage: section.systemImage,
            lines: cleanedLines
        )
    }

    private func usefulPanelSectionView(_ section: SecretaryPanelSectionDisplay) -> some View {
        UnifyDarkCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                reviewMiniHeader(
                    title: section.title,
                    systemImage: section.systemImage
                )

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(section.lines.prefix(8)) { line in
                        reviewLine(
                            label: line.label,
                            value: scrubSystemText(line.value)
                        )
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    
    private func preferredCompareOption(
        _ compare: SecretaryComparePanel.Display
    ) -> SecretaryCompareOptionDisplay? {
        if let preferred = compare.options.first(where: { $0.isPreferred }) {
            return preferred
        }

        return compare.options.first
    }

    private func reviewMiniHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))

            Spacer(minLength: 0)
        }
    }

    private func reviewMetricPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(clean(value).isEmpty ? "Unknown" : scrubSystemText(value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            threadGlassRoundedRectangleBackground(cornerRadius: 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
        )
    }

    private func reviewLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clean(label))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text(scrubSystemText(value))
                .font(.system(size: 13.5))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func reviewList(
        title: String,
        systemImage: String,
        values: [String],
        maxItems: Int
    ) -> some View {
        let cleanedValues = cleanedUsefulLines(values)

        if !cleanedValues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                reviewMiniHeader(title: title, systemImage: systemImage)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(cleanedValues.prefix(maxItems).enumerated()), id: \.offset) { _, value in
                        reviewBullet(value)
                    }
                }
            }
        }
    }

    private func reviewBullet(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(SecretaryTheme.darkOrange.opacity(0.85))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Text(scrubSystemText(value))
                .font(.system(size: 14))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func cleanedUsefulLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let cleaned = scrubSystemText(value)
            guard !cleaned.isEmpty else { continue }
            guard !looksLikeSystemNoise(cleaned.lowercased()) else { continue }

            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(cleaned)
        }

        return output
    }

    private func scrubSystemText(_ value: String?) -> String {
        var result = clean(value)
        guard !result.isEmpty else { return "" }

        let lower = result.lowercased()

        if looksLikeSystemNoise(lower) {
            if lower.contains("waiting") || lower.contains("awaiting") {
                return "Waiting for the other side."
            }

            if lower.contains("clarification") || lower.contains("missing") {
                return "More detail may be needed before this can move forward."
            }

            if lower.contains("approval") || lower.contains("review") {
                return "Review is needed before the next step."
            }

            return ""
        }

        let removePhrases = [
            "Outbound probe:",
            "deterministic",
            "Pass 1",
            "Pass 2",
            "Pass 3",
            "schema",
            "agency_decision_",
            "agency_requester_decision_"
        ]

        for phrase in removePhrases {
            result = result.replacingOccurrences(
                of: phrase,
                with: "",
                options: .caseInsensitive
            )
        }

        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeSystemNoise(_ lower: String) -> Bool {
        lower.contains("role:") ||
        lower.contains("state:") ||
        lower.contains("qualification:") ||
        lower.contains("requester posture:") ||
        lower.contains("boundary:") ||
        lower.contains("routine non-binding") ||
        lower.contains("coordination") ||
        lower.contains("outbound probe:") ||
        lower.contains("deterministic") ||
        lower.contains("schema") ||
        lower.contains("pass 1") ||
        lower.contains("pass 2") ||
        lower.contains("pass 3") ||
        lower.contains("agency_decision_") ||
        lower.contains("agency_requester_decision_")
    }
    
    // MARK: - Second-half buttons

    @ViewBuilder
    private func secondHalfButtonsFiltered(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail,
        stage: ThreadStage
    ) -> some View {
        let hiddenKinds: Set<ExchangeSecondHalfUIAdapter.ActionButton.Kind> = {
            var kinds: Set<ExchangeSecondHalfUIAdapter.ActionButton.Kind> = []

            switch stage {
            case .needsApproval:
                kinds.insert(.approve)
                kinds.insert(.review)

            case .needsCare:
                kinds.insert(.recover)

            case .needsAnswer:
                kinds.insert(.answer)
                kinds.insert(.clarify)
                if isOutboundSecondHalfClarification(display: display, detail: detail) {
                    kinds.insert(.review)
                }

            case .readyToReview:
                kinds.insert(.review)

            case .waiting, .moving:
                break
            }

            kinds.insert(.compare)

            return kinds
        }()

        let filtered = display.buttons.filter { button in
            !hiddenKinds.contains(button.kind)
        }

        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(filtered) { button in
                    SecretaryActionButton(
                        title: button.title,
                        systemImage: systemImage(for: button.kind),
                        prominent: button.prominence == .primary,
                        tone: tone(for: button.prominence),
                        chrome: .exchangeDark
                    ) {
                        Task { @MainActor in
                            await handleSecondHalfActionButton(button, detail: detail)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func handleSecondHalfActionButton(
        _ button: ExchangeSecondHalfUIAdapter.ActionButton,
        detail: ExchangeModels.ThreadDetail
    ) async {
        switch button.kind {
        case .letSecretaryHandle:
            await services.exchangeFacade.attemptRequesterSecondHalfAutonomousOutbound(
                threadID: detail.thread.id,
                now: Date()
            )
            await load(showSpinner: false)
            Task {
                await services.exchangeSyncEngine.runPass(
                    trigger: .afterApprovalGranted,
                    now: Date()
                )
            }

        case .approve, .review, .editDraft:
            onOpenApprovalSheet?(SecretaryProjectionEngine.approvalDisplay(for: detail))

        case .answer, .clarify:
            onOpenClarification?(detail.thread.id)

        case .compare:
            break

        case .recover:
            onOpenRecoveryPanel?(SecretaryProjectionEngine.recoveryDisplay(for: detail))

        case .openThread, .configureStyle, .configureReception, .decline, .complete, .pause:
            break
        }
    }

    private func systemImage(for kind: ExchangeSecondHalfUIAdapter.ActionButton.Kind) -> String? {
        switch kind {
        case .letSecretaryHandle: return "sparkles"
        case .approve: return "checkmark"
        case .editDraft: return "square.and.pencil"
        case .review: return "checkmark.seal"
        case .decline: return "xmark"
        case .answer: return "arrow.turn.up.left"
        case .clarify: return "questionmark.circle"
        case .compare: return "arrow.left.arrow.right"
        case .recover: return "arrow.clockwise"
        case .complete: return "flag.checkered"
        case .openThread: return "bubble.left.and.bubble.right"
        case .configureStyle, .configureReception: return "gearshape"
        case .pause: return "pause.circle"
        }
    }

    private func tone(for prominence: ExchangeSecondHalfUIAdapter.ActionButton.Prominence) -> SecretaryActionButton.Tone {
        switch prominence {
        case .primary:
            return .approval
        case .secondary:
            return .trust
        case .destructive:
            return .recovery
        case .quiet:
            return .secondary
        }
    }

    // MARK: - Draft previews
    
    @ViewBuilder
    private func inlineDraftPreview(subject: String?, body: String?) -> some View {
        let cleanedSubject = clean(subject)
        let cleanedBody = scrubDraftPreview(clipped(clean(body), max: 520))

        if !cleanedSubject.isEmpty || !cleanedBody.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !cleanedSubject.isEmpty {
                    Text(cleanedSubject)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !cleanedBody.isEmpty {
                    Text(cleanedBody)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineSpacing(1.6)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func draftPreview(_ draft: ExchangeSecondHalfUIAdapter.DraftSection?) -> some View {
        if let draft,
           let preview = SecretaryProjectionEngine.nonEmpty(draft.bodyPreview) {
            inlineDraftPreview(
                subject: draft.subject,
                body: preview
            )
        }
    }

    @ViewBuilder
    private func localDraftPreview(subject: String?, body: String?) -> some View {
        let cleanedBody = clean(body)
        if !cleanedBody.isEmpty {
            inlineDraftPreview(
                subject: subject,
                body: cleanedBody
            )
        }
    }

    private func previewCard(eyebrow: String, title: String?, body: String) -> some View {
        inlineDraftPreview(
            subject: title,
            body: body
        )
    }

    private func scrubDraftPreview(_ value: String) -> String {
        let cleaned = clean(value)
        let phrasesToRemove = [
            "Outbound probe:",
            "requester asked to",
            "matched-provider details",
            "or simila..."
        ]

        var result = cleaned
        for phrase in phrasesToRemove {
            result = result.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }

        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - User-facing summaries

    private func counterpartySummary(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let selected = SecretaryProjectionEngine.selectedCounterpartyName(for: detail) {
            return selected
        }

        let names = detail.counterparties
            .map(\.bestDisplayLine)
            .map(clean)
            .filter { !$0.isEmpty }

        if !names.isEmpty {
            return names.prefix(3).joined(separator: " · ")
        }

        if let display = SecretaryProjectionEngine.secondHalfDisplay(for: detail) {
            if let provider = display.providerReception {
                if let ask = SecretaryProjectionEngine.nonEmpty(provider.requesterAsk) {
                    return "They asked: \(ask)"
                }
                if let inquiry = SecretaryProjectionEngine.nonEmpty(provider.inquirySummary) {
                    return inquiry
                }
            }

            if let requester = display.requesterReview {
                return requester.recommendation ?? requester.subtitle
            }

            if let decision = display.decision {
                return decision.summary
            }
        }

        return "No clear profile or offer is selected yet."
    }

    private func trustSummary(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let selected = SecretaryProjectionEngine.selectedCounterpartyName(for: detail) {
            return "Current path: \(selected)."
        }

        if !detail.counterparties.isEmpty {
            return "There are visible paths, but none has been selected yet."
        }

        return "No strong path is visible yet."
    }

    private func sendingSummary(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let delivery = detail.thread.delivery {
            switch delivery.status {
            case .notStarted:
                return "Nothing has been sent yet."
            case .pendingApproval:
                return "A message is waiting for your review."
            case .readyToSend:
                return "A message is ready to send."
            case .sending:
                return "Sending…"
            case .sent:
                return detail.inboxItems.isEmpty
                ? "Sent. Waiting for a reply."
                : "Sent. A reply arrived."
            case .failed:
                return "Sending failed."
            @unknown default:
                return "Still updating."
            }
        }

        if SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail) {
            return "A draft exists, but it has not been sent."
        }

        return "Nothing has been sent yet."
    }

    private func userFacingRole(_ role: String?) -> String? {
        let value = clean(role)
        guard !value.isEmpty else { return nil }

        switch value.lowercased() {
        case "requester":
            return "You are looking."
        case "provider":
            return "They came to you."
        default:
            return value
        }
    }

    private func userFacingBoundary(_ value: String?) -> String? {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return nil }

        let lower = cleaned.lowercased()
        if lower.contains("approval") {
            return "Needs review before anything goes out."
        }
        if lower.contains("safe") {
            return "Safe to continue with normal checks."
        }
        if lower.contains("wait") {
            return "Waiting before the next step."
        }
        return cleaned
    }

    private func isOutboundSecondHalfClarification(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        let raw = ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: display)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw == ExchangeSecondHalfAction.askClarification.rawValue else { return false }
        return SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail)
    }

    private func audienceSplitSecondHalfFactsAvailable(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        (detail.thread.secondHalf?.schemaVersion ?? 0) >= 2
    }

    private func localUserClarificationLine(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        detail: ExchangeModels.ThreadDetail
    ) -> String? {
        if let req = SecretaryProjectionEngine.nonEmpty(display.nextMove?.requiredInputs.first) {
            return req
        }

        if audienceSplitSecondHalfFactsAvailable(detail),
           let line = SecretaryProjectionEngine.nonEmpty(display.operatingContext.userFacingMissingFacts.first) {
            return line
        }

        if let title = SecretaryProjectionEngine.nonEmpty(display.nextMove?.title) {
            return title
        }

        return SecretaryProjectionEngine.nonEmpty(SecretaryProjectionEngine.clarificationQuestion(detail))
    }

    private func shouldShowDeskDetails(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        let display = SecretaryProjectionEngine.activityDisplay(for: detail)
        let movement = display.latestMovement.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = display.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = display.nextMove.trimmingCharacters(in: .whitespacesAndNewlines)
        return !movement.isEmpty || !meaning.isEmpty || !next.isEmpty
    }

    @ViewBuilder
    private func umbrellaCoordinationResultsSection(_ detail: ExchangeModels.ThreadDetail) -> some View {
        let cards = SecretarySearchResultProjection.cardProjections(from: detail)
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Text("These paths were checked first. Open a card to review the match.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            LazyVStack(spacing: 16) {
                ForEach(cards) { card in
                    SecretarySearchResultCardView(
                        card: card,
                        onPrimaryTap: {
                            openCoordinationResultCard(card)
                        },
                        onOpenPathTap: {
                            openCoordinationResultCard(card)
                        },
                        onCompareTap: nil
                    )
                }
            }
        }
    }

    private func openCoordinationResultCard(_ card: SecretarySearchResultCardProjection) {
        guard let onOpenThread else { return }
        onOpenThread(card.linkedThreadID)
    }

    private func canArchive(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        if case .resolved = detail.thread.state {
            return false
        }
        return !detail.thread.isArchived
    }

    private var archiveConfirmationTitle: String {
        guard let detail else { return "Close this thread?" }
        switch detail.thread.threadRole {
        case .candidateCoordination:
            return "Close this path?"
        case .umbrellaSearch:
            return "Remove this search?"
        case .standalone:
            return "Close this thread?"
        }
    }

    private var archiveConfirmationMessage: String {
        guard let detail else {
            return "This hides the thread from your active view on this device."
        }
        switch detail.thread.threadRole {
        case .candidateCoordination:
            return "This hides this provider path, but keeps the original search and other paths."
        case .umbrellaSearch:
            return "This hides the search and its active paths from your history on this device."
        case .standalone:
            return "This hides the thread from your active view on this device."
        }
    }

    private var archiveConfirmationButtonTitle: String {
        guard let detail else { return "Close" }
        if detail.thread.threadRole == .candidateCoordination {
            return "Close path"
        }
        if detail.thread.threadRole == .umbrellaSearch {
            return "Remove"
        }
        return "Close"
    }

    @MainActor
    private func archiveThreadFromDetail(_ detail: ExchangeModels.ThreadDetail) async {
        do {
            switch detail.thread.threadRole {
            case .candidateCoordination:
                try await services.exchangeFacade.archiveThread(id: detail.thread.id)
            case .umbrellaSearch:
                try await services.exchangeFacade.archiveThreadRespectingCoordinationFamily(
                    id: detail.thread.id
                )
            case .standalone:
                try await services.exchangeFacade.archiveThread(id: detail.thread.id)
            }
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil
            )
            onBack()
        } catch {
            connectResultMessage = "Couldn't close this thread. Try again."
        }
    }

    // MARK: - Data loading

    private static func userFacingThreadLoadFailure(_ error: Error) -> (title: String, message: String) {
        if let storeError = error as? ExchangeStoreError, case .threadNotFound = storeError {
            return ("This thread is no longer available.", "")
        }
        return ("Couldn’t open this thread.", "")
    }

    private func shouldReloadForSecretaryWorkspaceRefresh(_ notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo, !userInfo.isEmpty else {
            // No payload => conservative reload.
            return true
        }

        let currentID = threadID.uuidString.lowercased()

        func parseUUIDString(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let uuid = UUID(uuidString: trimmed) else { return nil }
            return uuid.uuidString.lowercased()
        }

        func parseAnyThreadID(_ value: Any?) -> String? {
            switch value {
            case let uuid as UUID:
                return uuid.uuidString.lowercased()
            case let string as String:
                return parseUUIDString(string)
            default:
                return nil
            }
        }

        func parseThreadIDList(_ value: Any?) -> [String] {
            switch value {
            case let values as [UUID]:
                return values.map { $0.uuidString.lowercased() }
            case let values as [String]:
                return values.compactMap(parseUUIDString)
            default:
                return []
            }
        }

        var parsedThreadIDs: [String] = []

        parsedThreadIDs.append(contentsOf: [
            parseAnyThreadID(userInfo["threadID"]),
            parseAnyThreadID(userInfo["threadId"]),
            parseAnyThreadID(userInfo["id"])
        ].compactMap { $0 })

        parsedThreadIDs.append(contentsOf: parseThreadIDList(userInfo["threadIDs"]))
        parsedThreadIDs.append(contentsOf: parseThreadIDList(userInfo["reconciledThreadIDs"]))

        if parsedThreadIDs.isEmpty {
            // Payload present but no parseable thread ids => conservative reload.
            return true
        }

        return Set(parsedThreadIDs).contains(currentID)
    }

    @MainActor
    private func scheduleLoad(
        delayNanoseconds: UInt64 = 150_000_000,
        source: String = "scheduled"
    ) {
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await load(showSpinner: false, source: source)
        }
    }

    @MainActor
    private func load(showSpinner: Bool = true, source: String = "direct") async {
        loadGeneration &+= 1
        let generation = loadGeneration
        if showSpinner || detail == nil {
            isLoading = true
        }

        loadFailureCard = nil

        do {
            let loadedDetail = try await services.exchangeFacade.getThread(threadID: threadID)
            guard !Task.isCancelled else { return }

            let loadedSituation = try await services.exchangeFacade.threadSituation(from: loadedDetail)
            guard !Task.isCancelled else { return }
            let detailsContextTitle: String? = {
                let offerTitle = clean(loadedSituation.selectedOfferTitle)
                if !offerTitle.isEmpty { return offerTitle }
                let profileTitle = clean(loadedSituation.selectedPublicProfileTitle)
                return profileTitle.isEmpty ? nil : profileTitle
            }()
            let loadedProviderDetailsCard = try await services.exchangeFacade.providerDetailsCard(
                from: loadedDetail,
                contextTitle: detailsContextTitle
            )
            guard !Task.isCancelled else { return }
            #if DEBUG
            ExchangeProviderDetailsCardDebugLog.logThreadViewUsage(
                threadID: threadID.uuidString,
                display: loadedProviderDetailsCard,
                contextTitle: detailsContextTitle
            )
            #endif
            let resolvedConnectTarget = try await services.exchangeFacade.resolveConnectTargetForThread(threadID: threadID)
            guard !Task.isCancelled else { return }

            let shouldAssign = (generation == loadGeneration)
            #if DEBUG
            let latestTurn = loadedDetail.turns.last
            let latestDetailText = latestTurn?.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let latestSummaryText = latestTurn?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let latestTurnBody = latestDetailText.isEmpty ? latestSummaryText : latestDetailText
            let latestTurnBodyPrefix = latestTurnBody.isEmpty ? "none" : String(latestTurnBody.prefix(80))
            threadViewRefreshLog(
                "[ThreadDetailLoaded] threadID=\(threadID.uuidString) source=\(source) generation=\(generation) " +
                "assigned=\(shouldAssign) turns=\(loadedDetail.turns.count) " +
                "replyTurns=\(loadedDetail.turns.filter { $0.kind == .replyReceived && $0.actor == .counterparty }.count) " +
                "inboxItems=\(loadedDetail.inboxItems.count) latestTurnKind=\(latestTurn?.kind.rawValue ?? "none") " +
                "latestTurnBodyPrefix=\(latestTurnBodyPrefix)"
            )
            #endif
            guard shouldAssign else { return }

            detail = loadedDetail
            situation = loadedSituation
            providerDetailsCard = loadedProviderDetailsCard
            refreshProviderDetailsPresentation(
                detail: loadedDetail,
                pulled: pulledPublicSurface(loadedDetail)
            )
            connectTarget = resolvedConnectTarget

            try? await services.exchangeFacade.markSecretaryExchangeThreadMessagingAttentionReadForOpen(
                threadID: threadID
            )
            try? await services.exchangeFacade.markSecretaryThreadPeekNotificationsRead(threadID: threadID)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == loadGeneration else { return }

            loadFailureCard = Self.userFacingThreadLoadFailure(error)

            if detail == nil {
                situation = nil
                providerDetailsCard = nil
                providerDetailsPresentation = nil
            }
            connectTarget = nil
        }

        isLoading = false
    }

    // MARK: - Shared UI pieces

    private func infoBlock(_ label: String, _ value: String?) -> some View {
        let cleaned = clean(value)

        return Group {
            if !cleaned.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text(cleaned)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                        .lineSpacing(1.2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func infoLine(_ label: String, _ value: String?) -> some View {
        let cleaned = clean(value)

        return Group {
            if !cleaned.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text(cleaned)
                        .font(.system(size: 13.5))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.9))

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Copy helpers

    private func modeTitle(_ mode: ExchangeMode) -> String {
        switch mode {
        case .transactional:
            return "Transactional"
        case .cooperative:
            return "Cooperative"
        case .relational:
            return "Relational"
        @unknown default:
            return String(describing: mode).capitalized
        }
    }

    private func initials(from value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "Find ", with: "")
            .replacingOccurrences(of: "find ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pieces = cleaned
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let result = String(pieces).uppercased()
        return result.isEmpty ? "T" : result
    }

    private func clean(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clipped(_ value: String, max: Int) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > max else { return text }
        return String(text.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

private enum SecretaryThreadHeroMetrics {
    static let cornerRadius: CGFloat = 24
    static let width: CGFloat = 104
    static let height: CGFloat = 124
}

/// Hero image: same ordered URL list as the gallery strip; advances when `AsyncImage` fails or the string is not URL-parseable (fixes “thumbnails load, hero placeholder” when the first URL is dead).
private struct SecretaryThreadHeroAsyncImage<Fallback: View>: View {
    let candidates: [String]
    @Binding var successfulCandidateIndex: Int?
    /// When set, replaces the compact thumbnail metrics (photo-first hero).
    var fillSize: CGSize? = nil
    var clipCornerRadius: CGFloat? = nil
    var showStroke: Bool = true
    var debugThreadShort: String? = nil
    @ViewBuilder var fallback: () -> Fallback

    @State private var resolvedIndex: Int = 0

    private var heroWidth: CGFloat {
        max(1, fillSize?.width ?? SecretaryThreadHeroMetrics.width)
    }

    private var heroHeight: CGFloat {
        max(1, fillSize?.height ?? SecretaryThreadHeroMetrics.height)
    }

    private var heroCornerRadius: CGFloat {
        clipCornerRadius ?? SecretaryThreadHeroMetrics.cornerRadius
    }

    var body: some View {
        ZStack {
            heroGlassPlate(cornerRadius: heroCornerRadius)
                .frame(width: heroWidth, height: heroHeight)

            if candidates.isEmpty {
                fallback()
                    .onAppear { successfulCandidateIndex = nil }
            } else {
                let idx = min(max(0, resolvedIndex), candidates.count - 1)
                let urlString = candidates[idx]
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .onAppear {
                                    successfulCandidateIndex = idx
                                    #if DEBUG
                                    if let t = debugThreadShort {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: "detail", id: t, phase: "success")
                                    }
                                    #endif
                                }

                        case .failure(let error):
                            if idx < candidates.count - 1 {
                                Color.clear
                                    .onAppear {
                                        #if DEBUG
                                        ThreadImagePipelineDebug.logAsyncImageFailure(
                                            context: "detail",
                                            probeID: debugThreadShort ?? "n/a",
                                            url: url,
                                            error: error,
                                            normalizedCandidateCount: candidates.count,
                                            selectedCandidateIndex: idx,
                                            phaseLabel: "failure"
                                        )
                                        #endif
                                        scheduleAdvance(from: idx)
                                    }
                            } else {
                                fallback()
                                    .onAppear {
                                        successfulCandidateIndex = nil
                                        #if DEBUG
                                        ThreadImagePipelineDebug.logAsyncImageFailure(
                                            context: "detail",
                                            probeID: debugThreadShort ?? "n/a",
                                            url: url,
                                            error: error,
                                            normalizedCandidateCount: candidates.count,
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
                                .onAppear {
                                    #if DEBUG
                                    if let t = debugThreadShort {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: "detail", id: t, phase: "empty")
                                    }
                                    #endif
                                }

                        @unknown default:
                            if idx < candidates.count - 1 {
                                Color.clear
                                    .onAppear {
                                        #if DEBUG
                                        if let t = debugThreadShort {
                                            ThreadImagePipelineDebug.logAsyncPhase(context: "detail", id: t, phase: "unknown")
                                        }
                                        #endif
                                        scheduleAdvance(from: idx)
                                    }
                            } else {
                                fallback()
                                    .onAppear { successfulCandidateIndex = nil }
                            }
                        }
                    }
                    .id("\(idx)-\(urlString)")
                } else if idx < candidates.count - 1 {
                    Color.clear
                        .onAppear {
                            #if DEBUG
                            if let t = debugThreadShort {
                                ThreadImagePipelineDebug.logAsyncPhase(context: "detail", id: t, phase: "urlParseFailed")
                            }
                            #endif
                            scheduleAdvance(from: idx)
                        }
                } else {
                    fallback()
                        .onAppear { successfulCandidateIndex = nil }
                }
            }
        }
        .frame(width: heroWidth, height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous))
        .overlay {
            if showStroke {
                RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.82), lineWidth: 1)
            }
        }
        .onChange(of: candidates) { _, _ in
            resolvedIndex = 0
            successfulCandidateIndex = nil
        }
    }

    private func scheduleAdvance(from idx: Int) {
        guard idx == resolvedIndex else { return }
        guard idx + 1 < candidates.count else { return }
        let expected = idx
        DispatchQueue.main.async {
            if resolvedIndex == expected {
                successfulCandidateIndex = nil
                resolvedIndex = expected + 1
            }
        }
    }

    private func heroGlassPlate(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct SecretaryDirectMessageComposeRoute: Identifiable, Hashable {
    let id: UUID
    /// When set on a **direct_message_thread**, sends via ``ExchangeFacade/sendManualMessageToTrustedNode``.
    /// When `nil` on an **inbound_thread**, uses ``ExchangeFacade/sendInboundProviderManualReply``.
    /// On exchange/search threads, send routing uses ``ExchangeFacade/sendManualConversationMessageOnThread`` regardless.
    let trustedNodeID: String?
    let displayName: String

    var nodeIDForTrustedSend: String {
        trustedNodeID ?? ""
    }

    init(trustedNodeID: String?, displayName: String) {
        self.id = UUID()
        self.trustedNodeID = trustedNodeID
        self.displayName = displayName
    }
}

private extension ExchangeThread {
    var awaitingResponseLike: Bool {
        switch state {
        case .awaitingResponse:
            return true
        default:
            return false
        }
    }
}
