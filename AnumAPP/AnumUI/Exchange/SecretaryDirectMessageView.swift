import SwiftUI
import AnumCore
import Combine
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
import QuickLook
#endif

private struct DMAttachmentPreviewPresentation: Identifiable {
    let id = UUID()
    let fileURL: URL
    let filename: String
    let mimeType: String
    let isImage: Bool
}

struct SecretaryDirectMessageView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    private static let transcriptBottomAnchorID = "transcript-bottom"

    /// One-line bubble + timestamp + gap; keeps sender/receiver rows aligned.
    private enum DMLayoutMetrics {
        static let avatarSize: CGFloat = 42
        static let maxBubbleWidth: CGFloat = 280
        static let rowSideSpacer: CGFloat = 52
        static let topBarMinHeight: CGFloat = 52
        static let topBarTopBreathing: CGFloat = 6
        /// Extra scrollable padding so the last row clears the composer above the keyboard.
        static let transcriptExtraBottomScrollMargin: CGFloat = 18
        /// Anchor spacer below the last bubble so `scrollTo(anchor: .bottom)` leaves breathing room.
        static let transcriptBottomAnchorSpacerHeight: CGFloat = 18
        /// Gentle transcript follow after keyboard layout settles (single `keyboardOpenComposerFocus` scroll).
        static let keyboardOpenTranscriptEaseDuration: Double = 0.24
        /// Fade-in after the first bottom scroll so the list does not flash from top-of-scroll.
        static let initialTranscriptRevealFadeDuration: Double = 0.2
    }

    let counterpartyNodeID: String
    let displayName: String?
    let existingThreadID: ExchangeThread.ID?
    let onBack: () -> Void

    private typealias DirectMessageBubble = DirectMessageTranscriptBubble
    private typealias DirectTranscriptRenderResult = DirectMessageTranscriptRenderResult

    private struct PendingDMAttachment: Identifiable {
        let id = UUID()
        let stagingURL: URL
        let filename: String
        let mimeType: String
        let byteSize: Int
    }

    @State private var resolvedThreadID: ExchangeThread.ID?
    @State private var transcript: [DirectMessageBubble] = []
    /// Starts true so the first frame never shows the empty state before `loadTranscript` runs.
    @State private var isLoading = true
    /// Set true after the first `loadTranscript` attempt finishes (success or failure), so empty UI only shows when truly empty.
    @State private var hasCompletedInitialTranscriptLoad = false
    @State private var sendBody: String = ""
    @FocusState private var isComposerFocused: Bool
    /// Bumped after a successful send so the `TextField` is recreated unfocused (avoids keyboard re-assertion).
    @State private var composerFieldGeneration: Int = 0
    /// Blocks programmatic refocus while true; cleared shortly after send + transcript refresh (user taps still set focus via `TextField`).
    @State private var shouldSuppressComposerAutofocus = false
    @State private var sendError: String?
    @State private var sendInFlight = false
    @State private var headerDisplayName: String?
    @State private var remoteAvatarURL: String?
    @State private var remoteSupporterPresentation: ExchangeSupporterPresentation?
    @State private var localAvatarURL: String?
    @State private var localAvatarTitleForInitials: String = "Me"
    @State private var contactContext: ExchangeModels.ContactContext?
    @State private var showContactContextEditor = false
    @State private var suggestion: ExchangeModels.DirectReplySuggestionOutput?
    @State private var suggestionBusy = false
    @State private var suggestionError: String?
    @State private var previousDirectReplySuggestions: [String] = []
    @State private var directReplyRegenerationCount: Int = 0
    @State private var lastDirectReplyTargetKey: String?
    @State private var profileSummaryForSuggest: String?
    @State private var commercialSummaryForSuggest: String?
    @State private var lastRenderResult: DirectTranscriptRenderResult?
    /// After first successful bottom scroll, subsequent loads keep the list visible (no top flash gate).
    @State private var didApplyInitialTranscriptReveal = false
    @State private var pendingInitialTranscriptScroll = false
    /// Coalesces keyboard/focus-driven bottom scrolls so layout + keyboard safe-area can settle without stacked animations.
    @State private var transcriptBottomScrollTask: Task<Void, Never>?
    /// Pulled from `UIKeyboard` notifications (duration only) to match scroll timing to the keyboard without reading frame height.
    @State private var keyboardDrivenScrollAnimationDuration: Double = 0.25
    @State private var clearTranscriptInFlight = false
    @State private var livePullInFlight = false
    @State private var transcriptReloadGeneration: UInt64 = 0
    @State private var pendingAttachment: PendingDMAttachment?
    @State private var showAttachmentSourceDialog = false
    @State private var showDocumentImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var attachmentActionError: String?
    @State private var openingAttachmentID: UUID?
    @State private var attachmentPreviewPresentation: DMAttachmentPreviewPresentation?
    @State private var showAttachmentShareSheet = false
    @State private var shareAttachmentURL: URL?

    private var titleText: String {
        let preferred = headerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }

        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }

        if counterpartyNodeID.count > 16 {
            return "\(counterpartyNodeID.prefix(8))...\(counterpartyNodeID.suffix(6))"
        }

        return counterpartyNodeID
    }

    var body: some View {
        ZStack {
            messageBackground

            VStack(spacing: 0) {
                dmCompactTopBar

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if !hasCompletedInitialTranscriptLoad {
                                loadingTranscriptView
                                    .padding(.top, 28)
                            } else if transcript.isEmpty {
                                if isLoading {
                                    loadingTranscriptView
                                        .padding(.top, 28)
                                } else {
                                    emptyTranscriptView
                                        .padding(.top, 38)
                                }
                            } else {
                                ForEach(transcript) { row in
                                    messageRow(row)
                                }

                                Color.clear
                                    .frame(height: DMLayoutMetrics.transcriptBottomAnchorSpacerHeight)
                                    .id(Self.transcriptBottomAnchorID)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .opacity(
                            transcript.isEmpty || didApplyInitialTranscriptReveal ? 1 : 0
                        )
                        .animation(
                            .easeOut(duration: DMLayoutMetrics.initialTranscriptRevealFadeDuration),
                            value: didApplyInitialTranscriptReveal
                        )
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await pullLatestFederationAndReloadTranscript(
                            reason: "pullToRefresh",
                            trigger: .manualRefresh
                        )
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .contentMargins(
                        .bottom,
                        DMLayoutMetrics.transcriptExtraBottomScrollMargin,
                        for: .scrollContent
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            if showAttachmentSourceDialog {
                                showAttachmentSourceDialog = false
                            }
                            if isComposerFocused {
                                isComposerFocused = false
                            }
                        }
                    )
                    .onChange(of: pendingInitialTranscriptScroll) { _, pending in
                        guard pending, !transcript.isEmpty, !didApplyInitialTranscriptReveal else { return }
                        Task { @MainActor in
                            #if DEBUG
                            print("[DMTranscriptInitialScroll] phase=start rows=\(transcript.count)")
                            #endif

                            await Task.yield()
                            try? await Task.sleep(nanoseconds: 50_000_000)

                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
                            }

                            #if DEBUG
                            print("[DMTranscriptInitialScroll] phase=scrolled rows=\(transcript.count)")
                            #endif

                            await Task.yield()
                            didApplyInitialTranscriptReveal = true
                            pendingInitialTranscriptScroll = false

                            #if DEBUG
                            print("[DMTranscriptInitialScroll] phase=visible rows=\(transcript.count)")
                            #endif
                        }
                    }
                    .onChange(of: transcript.count) { oldCount, newCount in
                        guard didApplyInitialTranscriptReveal else { return }
                        guard newCount > 0, newCount != oldCount else { return }
                        scheduleTranscriptScrollToBottom(
                            proxy: proxy,
                            reason: "newMessage",
                            debounceNanoseconds: 55_000_000,
                            animated: true
                        )
                    }
                    .onChange(of: isComposerFocused) { _, focused in
                        guard focused else { return }
                        guard didApplyInitialTranscriptReveal, !transcript.isEmpty else { return }
                        // One stable delayed scroll with a soft ease (not per-frame keyboardWillChangeFrame).
                        scheduleTranscriptScrollToBottom(
                            proxy: proxy,
                            reason: "keyboardOpenComposerFocus",
                            debounceNanoseconds: 195_000_000,
                            animated: true,
                            softKeyboardOpenEase: true
                        )
                    }
                    #if canImport(UIKit)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                        ingestKeyboardScrollAnimationDuration(from: note)
                    }
                    #endif
                    .onDisappear {
                        transcriptBottomScrollTask?.cancel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let sendError {
                    sendErrorView(sendError)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .preferredColorScheme(.dark)
        .tint(SecretaryTheme.darkOrange)
        .sheet(isPresented: $showContactContextEditor) {
            SecretaryContactContextSheet(
                remoteNodeID: counterpartyNodeID,
                displayName: titleText
            ) { saved in
                contactContext = saved

                #if DEBUG
                print("[ContactContextProjection] surface=dm nodeID=\(saved.remoteNodeID) relationship=\(saved.relationshipType.rawValue) goal=\(saved.relationshipGoal.rawValue)")
                #endif
            }
            .environmentObject(services)
        }
        
        .task {
            await resolveAndLoadTranscript()
            guard scenePhase == .active else { return }
            await pullLatestFederationAndReloadTranscript(
                reason: "dm_screen_open_after_resolve",
                trigger: .appBecameActive
            )
        }
        .onChange(of: services.secretaryRefreshID) { _, _ in
            Task { @MainActor in
                await reloadTranscriptIfResolved(reason: "secretaryRefreshID")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .directMessageTranscriptDidChange)) { notification in
            Task { @MainActor in
                await handleDirectMessageTranscriptDidChange(notification)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await pullLatestFederationAndReloadTranscript(
                    reason: "sceneBecameActive",
                    trigger: .appBecameActive
                )
            }
        }
        .fullScreenCover(item: $attachmentPreviewPresentation) { presentation in
            if presentation.isImage {
                DMAttachmentLocalImagePreview(
                    presentation: presentation,
                    onDismiss: { attachmentPreviewPresentation = nil },
                    onShare: { presentDMAttachmentShare(for: presentation.fileURL) }
                )
            } else {
                DMAttachmentFilePreviewSheet(
                    presentation: presentation,
                    onDismiss: { attachmentPreviewPresentation = nil },
                    onShare: { presentDMAttachmentShare(for: presentation.fileURL) }
                )
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showAttachmentShareSheet, onDismiss: { shareAttachmentURL = nil }) {
            if let shareAttachmentURL {
                DMAttachmentActivityShareSheet(items: [shareAttachmentURL])
            }
        }
        #endif
    }

    /// Lets the workspace `UnifyIceShellBackground` read through (same baseline as main tabs).
    private var messageBackground: some View {
        Color.clear
    }

    private var loadingTranscriptView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(SecretaryTheme.darkOrange)

            Text("Loading conversation…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTranscriptView: some View {
        VStack(spacing: 12) {
            SecretaryCompactProfileAvatar(
                imageURL: remoteAvatarURL,
                initials: initials(from: titleText),
                systemImage: "person.crop.circle",
                style: .neutral,
                size: 58,
                publicSupporterPresentation: remoteSupporterPresentation,
                debugSurface: "dmEmpty",
                debugNodeID: counterpartyNodeID
            )

            Text("No messages yet")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Text("Send the first message to start this conversation.")
                .font(.system(size: 14.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    private func sendErrorView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.6), lineWidth: 1)
            )
    }

    #if canImport(UIKit)
    private func ingestKeyboardScrollAnimationDuration(from notification: Notification) {
        guard let number = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return
        }
        let duration = number.doubleValue
        guard duration > 0.01, duration < 10 else { return }
        keyboardDrivenScrollAnimationDuration = min(max(duration, 0.17), 0.42)
    }
    #endif

    private var transcriptBottomScrollAnimation: Animation {
        .easeOut(duration: keyboardDrivenScrollAnimationDuration)
    }

    /// Single debounced path for “stay pinned above composer/keyboard” without stacking competing `withAnimation` calls.
    @MainActor
    private func scheduleTranscriptScrollToBottom(
        proxy: ScrollViewProxy,
        reason: String,
        debounceNanoseconds: UInt64 = 95_000_000,
        animated: Bool = true,
        softKeyboardOpenEase: Bool = false
    ) {
        guard !transcript.isEmpty else { return }

        transcriptBottomScrollTask?.cancel()
        transcriptBottomScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled, !transcript.isEmpty else { return }

            #if DEBUG
            print(
                "[DMTranscriptScrollPerform] reason=\(reason) animated=\(animated) " +
                    "softKeyboardEase=\(softKeyboardOpenEase) rows=\(transcript.count) focused=\(isComposerFocused)"
            )
            #endif

            if animated {
                let animation: Animation = softKeyboardOpenEase
                    ? .easeOut(duration: DMLayoutMetrics.keyboardOpenTranscriptEaseDuration)
                    : transcriptBottomScrollAnimation
                withAnimation(animation) {
                    proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Top bar (focused room; no page-level chrome)

    private var dmCompactTopBar: some View {
        ZStack {
            Text(displayTitleForHeader)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                        .frame(width: 38, height: 38)
                        .background {
                            UnifyGlassIconDisk(diameter: 38, strokeOpacity: 0.82)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        showContactContextEditor = true
                    } label: {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .frame(width: 38, height: 38)
                            .background {
                                UnifyGlassIconDisk(diameter: 38, strokeOpacity: 0.82)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reply context")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: DMLayoutMetrics.topBarMinHeight)
        .padding(.top, DMLayoutMetrics.topBarTopBreathing)
        .padding(.horizontal, 10)
    }

    private var displayTitleForHeader: String {
        if looksLikeRawNodeID(titleText) {
            return compactNodeTitle(titleText)
        }

        return titleText
    }

    private func looksLikeRawNodeID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("node-") || trimmed.contains("node-")
    }

    private func compactNodeTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 24 else { return trimmed }
        return "\(trimmed.prefix(10))…\(trimmed.suffix(8))"
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let suggestionError, !suggestionError.isEmpty {
                Text(suggestionError)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if let attachmentActionError, !attachmentActionError.isEmpty {
                Text(attachmentActionError)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if let suggestion {
                suggestedReplyCard(suggestion)
            }

            dmComposerUnifiedBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var resolvedContactContextForSuggest: ExchangeModels.ContactContext {
        contactContext ?? services.getContactContext(remoteNodeID: counterpartyNodeID)
    }

    private var latestIncomingMessageForSuggest: String? {
        let text = transcript
            .suffix(4)
            .last(where: { !$0.isOutgoing })?
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private var isDirectReplySuggestionAvailable: Bool {
        guard !isCounterpartyBlockedForSend else { return false }
        guard resolvedContactContextForSuggest.aiAssistLevel != .autoReplyDisabled else { return false }
        return latestIncomingMessageForSuggest != nil
    }

    private var dmComposerUnifiedBar: some View {
        let trimmed = sendBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = isCounterpartyBlockedForSend
        let canSend = (!trimmed.isEmpty || pendingAttachment != nil) && !sendInFlight && !blocked
        let suggestDisabled = !isDirectReplySuggestionAvailable

        return VStack(alignment: .leading, spacing: 8) {
            if let pendingAttachment {
                pendingAttachmentChip(pendingAttachment)
            }

            HStack(alignment: .center, spacing: 8) {
            Button {
                showAttachmentSourceDialog.toggle()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        showAttachmentSourceDialog
                            ? SecretaryTheme.darkOrange
                            : SecretaryTheme.darkPrimaryText.opacity(0.92)
                    )
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(sendInFlight || blocked)
            .accessibilityLabel("Attach photo or file")

            Button {
                Task { @MainActor in
                    await suggestReply()
                }
            } label: {
                Group {
                    if suggestionBusy {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(suggestionBusy || blocked || suggestDisabled)
            .accessibilityLabel(suggestionBusy ? "Suggesting reply" : "Suggest reply")

            TextField("Message", text: $sendBody, axis: .vertical)
                .id("dmComposerField-\(composerFieldGeneration)")
                .focused($isComposerFocused)
                .lineLimit(1...5)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .tint(SecretaryTheme.darkOrange)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(sendInFlight || blocked)

            Button {
                Task { @MainActor in
                    await send()
                }
            } label: {
                Group {
                    if sendInFlight {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                            .scaleEffect(0.88)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(
                                canSend ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText.opacity(0.72)
                            )
                    }
                }
                .frame(width: 40, height: 40)
                .background {
                    if canSend, !sendInFlight {
                        Circle()
                            .fill(SecretaryTheme.darkOrange.opacity(0.16))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sendInFlight)
            .accessibilityLabel(sendInFlight ? "Sending" : "Send")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    UnifySoftVeilRoundedRectangle(cornerRadius: 26, strokeOpacity: 0.92)
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(SecretaryTheme.darkBackground.opacity(0.28))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showAttachmentSourceDialog {
                    dmAttachmentSourceTray
                        .padding(.bottom, 52)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading))
                        )
                        .zIndex(2)
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showAttachmentSourceDialog)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await handlePickedDMPhoto(item: newItem)
                pickedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: Self.dmAllowedDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                Task { @MainActor in
                    await handlePickedDMAttachment(url: picked)
                }
            case .failure:
                attachmentActionError = "Could not open the document picker."
            }
        }
    }

    private var dmAttachmentSourceTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                dmAttachmentTrayActionButton(title: "Photo", systemImage: "photo") {
                    showAttachmentSourceDialog = false
                    showPhotoPicker = true
                }
                dmAttachmentTrayActionButton(title: "File", systemImage: "doc") {
                    showAttachmentSourceDialog = false
                    showDocumentImporter = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    UnifySoftVeilRoundedRectangle(cornerRadius: 16, strokeOpacity: 0.9)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SecretaryTheme.darkBackground.opacity(0.34))
                        .allowsHitTesting(false)
                }
            }

            DMAttachmentTrayTail()
                .fill(SecretaryTheme.darkBackground.opacity(0.42))
                .frame(width: 12, height: 5)
                .overlay {
                    DMAttachmentTrayTail()
                        .stroke(SecretaryTheme.white.opacity(0.08), lineWidth: 0.5)
                }
                .padding(.leading, 24)
                .offset(y: -0.5)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func dmAttachmentTrayActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(SecretaryTheme.darkOrange)
            .frame(minWidth: 64)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SecretaryTheme.darkBackground.opacity(0.42))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(SecretaryTheme.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private static var dmAllowedDocumentTypes: [UTType] {
        var types: [UTType] = [
            .pdf,
            .plainText,
            .commaSeparatedText,
            .jpeg,
            .png,
            .webP
        ]
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    private func pendingAttachmentChip(_ pending: PendingDMAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: dmAttachmentIconName(mimeType: pending.mimeType))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(1)
                Text(dmAttachmentSizeLabel(pending.byteSize))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }

            Spacer(minLength: 0)

            Button {
                pendingAttachment = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SecretaryTheme.darkBackground.opacity(0.35))
        }
    }

    private func suggestedReplyCard(_ suggestion: ExchangeModels.DirectReplySuggestionOutput) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested reply")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)

            Text(suggestion.reply)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Use draft") {
                    sendBody = suggestion.reply
                    shouldSuppressComposerAutofocus = false
                    requestComposerFocus(true, source: "useDraft")

                    #if DEBUG
                    print("[DirectReplyUseDraft] nodeID=\(counterpartyNodeID) chars=\(suggestion.reply.count)")
                    #endif
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkOrange)
                )
                .buttonStyle(.plain)

                Button("Regenerate") {
                    Task { @MainActor in
                        await suggestReply(regenerate: true)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    UnifySoftVeilCapsule(strokeOpacity: 0.88)
                }
                .buttonStyle(.plain)

                Button("Dismiss") {
                    self.suggestion = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            UnifySoftVeilRoundedRectangle(cornerRadius: 22, strokeOpacity: 0.92)
        }
    }

    // MARK: - Message Bubbles

    /// Cheaper than `SecretaryPhotoOrb` (no multi-stop gradient / shadow): used for DM rows with no image URL.
    private func dmGlassAvatarPlaceholder(style: SecretaryStateChip.Style, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.semanticSoftFill(for: style).opacity(0.68))
            Circle()
                .stroke(SecretaryTheme.semanticStroke(for: style), lineWidth: 1)
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(SecretaryTheme.semanticColor(for: style))
        }
        .frame(width: size, height: size)
    }

    private func dmHasRenderableAvatarURL(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return false }
        return true
    }

    @ViewBuilder
    private func dmRowAvatarDisk(
        outgoing: Bool,
        avatarSize: CGFloat,
        remoteInitials: String,
        localInitials: String
    ) -> some View {
        if outgoing {
            if dmHasRenderableAvatarURL(localAvatarURL) {
                SecretaryCompactProfileAvatar(
                    imageURL: localAvatarURL,
                    initials: localInitials,
                    systemImage: "person.crop.circle",
                    style: .active,
                    size: avatarSize
                )
                .frame(width: avatarSize, height: avatarSize)
            } else {
                dmGlassAvatarPlaceholder(style: .active, size: avatarSize)
            }
        } else {
            if dmHasRenderableAvatarURL(remoteAvatarURL) {
                SecretaryCompactProfileAvatar(
                    imageURL: remoteAvatarURL,
                    initials: remoteInitials,
                    systemImage: "person.crop.circle",
                    style: .neutral,
                    size: avatarSize,
                    publicSupporterPresentation: remoteSupporterPresentation,
                    debugSurface: "dmBubble",
                    debugNodeID: counterpartyNodeID
                )
                .frame(width: avatarSize, height: avatarSize)
            } else {
                dmGlassAvatarPlaceholder(style: .neutral, size: avatarSize)
            }
        }
    }

    private func dmBubbleContent(_ row: DirectMessageBubble, outgoing: Bool) -> some View {
        let fileAttachments = row.attachments.filter { !isDMAttachmentImage($0) }
        let imageAttachments = row.attachments.filter { isDMAttachmentImage($0) }
        let hasTextBody = !row.body.isEmpty
        let hasFileBubbleContent = hasTextBody || !fileAttachments.isEmpty

        return VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
            ForEach(imageAttachments) { attachment in
                dmAttachmentBubbleCard(attachment, outgoing: outgoing)
            }

            if hasFileBubbleContent {
                dmTextAndFileBubbleChrome(
                    body: row.body,
                    fileAttachments: fileAttachments,
                    outgoing: outgoing,
                    timestamp: row.timestamp
                )
            } else if !imageAttachments.isEmpty {
                dmMessageTimestampLabel(row.timestamp, outgoing: outgoing)
            }
        }
    }

    @ViewBuilder
    private func dmTextAndFileBubbleChrome(
        body: String,
        fileAttachments: [DirectMessageAttachmentDescriptor],
        outgoing: Bool,
        timestamp: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(fileAttachments) { attachment in
                dmAttachmentBubbleCard(attachment, outgoing: outgoing)
            }

            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(outgoing ? Color.white : SecretaryTheme.darkPrimaryText)
                    .lineSpacing(1.2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dmMessageTimestampLabel(timestamp, outgoing: outgoing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if outgoing {
                ZStack {
                    UnifyGlassPlateBackground(cornerRadius: 20)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SecretaryTheme.darkBackground.opacity(0.38))
                        .allowsHitTesting(false)
                }
            } else {
                UnifySoftVeilRoundedRectangle(cornerRadius: 20, strokeOpacity: 0.9)
            }
        }
        .overlay {
            if outgoing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(SecretaryTheme.white.opacity(0.11), lineWidth: 1)
            }
        }
        .shadow(
            color: SecretaryTheme.darkShadow.opacity(outgoing ? 0.22 : 0.14),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    private func dmMessageTimestampLabel(_ timestamp: Date, outgoing: Bool) -> some View {
        Text(SecretaryRelativeTime.string(from: timestamp))
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(
                outgoing ? Color.white.opacity(0.62) : SecretaryTheme.darkSecondaryText
            )
    }

    private func messageRow(_ row: DirectMessageBubble) -> some View {
        let outgoing = row.isOutgoing
        let remoteInitials = initials(from: titleText)
        let localInitials = initials(from: localAvatarTitleForInitials)
        let avatarSize = DMLayoutMetrics.avatarSize

        return Group {
            if outgoing {
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: DMLayoutMetrics.rowSideSpacer)

                    dmBubbleContent(row, outgoing: true)
                        .frame(maxWidth: DMLayoutMetrics.maxBubbleWidth, alignment: .trailing)

                    dmRowAvatarDisk(
                        outgoing: true,
                        avatarSize: avatarSize,
                        remoteInitials: remoteInitials,
                        localInitials: localInitials
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    dmRowAvatarDisk(
                        outgoing: false,
                        avatarSize: avatarSize,
                        remoteInitials: remoteInitials,
                        localInitials: localInitials
                    )

                    dmBubbleContent(row, outgoing: false)
                        .frame(maxWidth: DMLayoutMetrics.maxBubbleWidth, alignment: .leading)

                    Spacer(minLength: DMLayoutMetrics.rowSideSpacer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Load / Send

    private func directMessageBlockedKey(for nodeID: String) -> String {
        let normalized = nodeID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return "secretary.directMessage.blocked.\(normalized)"
    }
    
    private var directMessageBlockedNodeIDsIndexKey: String {
        "secretary.directMessage.blockedNodeIDs"
    }

    private func addBlockedNodeIDToIndex(_ nodeID: String) {
        let trimmed = nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let raw = UserDefaults.standard.stringArray(forKey: directMessageBlockedNodeIDsIndexKey) ?? []

        var seen = Set<String>()
        var cleaned = raw.compactMap { value -> String? in
            let existing = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !existing.isEmpty else { return nil }

            let key = existing.lowercased()
            guard seen.insert(key).inserted else { return nil }

            return existing
        }

        if !cleaned.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            cleaned.append(trimmed)
        }

        UserDefaults.standard.set(cleaned, forKey: directMessageBlockedNodeIDsIndexKey)
    }

    private func removeBlockedNodeIDFromIndex(_ nodeID: String) {
        let trimmed = nodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let raw = UserDefaults.standard.stringArray(forKey: directMessageBlockedNodeIDsIndexKey) ?? []
        let nodes = raw.filter {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) != .orderedSame
        }

        UserDefaults.standard.set(nodes, forKey: directMessageBlockedNodeIDsIndexKey)
    }

    private var isCounterpartyBlockedForSend: Bool {
        let trimmed = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let key = directMessageBlockedKey(for: trimmed)
        return UserDefaults.standard.double(forKey: key) > 0
    }

    private static let blockedContactComposerMessage = "This contact is blocked."

    private func setDirectMessageBlockedAt(_ date: Date, for nodeID: String) {
        let key = directMessageBlockedKey(for: nodeID)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        addBlockedNodeIDToIndex(nodeID)

        #if DEBUG
        print("[ContactBlock] nodeID=\(nodeID.trimmingCharacters(in: .whitespacesAndNewlines)) blockedAt=\(date)")
        #endif
    }

    @MainActor
    private func refreshComposerBlockedState() {
        if isCounterpartyBlockedForSend {
            sendError = Self.blockedContactComposerMessage
        } else if sendError == Self.blockedContactComposerMessage {
            sendError = nil
        }
    }

    @MainActor
    private func clearChatHistoryForCurrentContact() async {
        guard !clearTranscriptInFlight else { return }

        let nodeID = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else { return }

        clearTranscriptInFlight = true
        defer { clearTranscriptInFlight = false }

        let now = Date()
        DirectMessageTranscriptProjection.setClearWatermark(at: now, for: nodeID)

        if let tid = resolvedThreadID {
            await loadTranscript(threadID: tid)
        } else {
            transcript = []
            hasCompletedInitialTranscriptLoad = true
            didApplyInitialTranscriptReveal = true
            pendingInitialTranscriptScroll = false
        }

        suggestion = nil
        suggestionError = nil
        lastRenderResult = nil

        refreshComposerBlockedState()

        NotificationCenter.default.post(
            name: .secretaryWorkspaceShouldRefresh,
            object: nil,
            userInfo: ["counterpartyNodeID": nodeID]
        )
    }
    
    @MainActor
    private func markInboundMessagingAttentionReadForResolvedDM(threadID: ExchangeThread.ID) async {
        do {
            try await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                threadID: threadID,
                counterpartyNodeID: counterpartyNodeID
            )
        } catch {
            #if DEBUG
            print(
                "[DirectMessageInboundAttentionMarkRead] failed threadID=\(threadID.uuidString) " +
                    "error=\(error.localizedDescription)"
            )
            #endif
        }
    }

    @MainActor
    private func resolveAndLoadTranscript() async {
        do {
            let threadID = try await services.exchangeFacade.openOrCreateDirectMessageThread(
                counterpartyNodeID: counterpartyNodeID,
                displayName: displayName,
                now: Date()
            )

            #if DEBUG
            if let existingThreadID, existingThreadID != threadID {
                print(
                    "[DirectMessageThreadResolve] nodeID=\(counterpartyNodeID) providedExistingThreadID=\(existingThreadID.uuidString) reusedThreadID=\(threadID.uuidString) createdThreadID=nil rejectedOldThreadID=\(existingThreadID.uuidString) reason=redirected_to_canonical_dm_thread"
                )
            } else if let existingThreadID {
                print(
                    "[DirectMessageThreadResolve] nodeID=\(counterpartyNodeID) providedExistingThreadID=\(existingThreadID.uuidString) reusedThreadID=\(threadID.uuidString) createdThreadID=nil rejectedOldThreadID=nil reason=reused_canonical_dm_thread"
                )
            } else {
                print(
                    "[DirectMessageThreadResolve] nodeID=\(counterpartyNodeID) providedExistingThreadID=nil reusedThreadID=\(threadID.uuidString) createdThreadID=nil rejectedOldThreadID=nil reason=open_or_create_dm_thread"
                )
            }
            print("[DMTranscriptScroll] event=open threadID=\(threadID.uuidString) action=scrollBottom")
            #endif

            resolvedThreadID = threadID
            await markInboundMessagingAttentionReadForResolvedDM(threadID: threadID)
            await loadTranscript(threadID: threadID)
            print(
                "[DMTranscript][open] conversationKey=\(counterpartyNodeID) " +
                "initialRows=\(transcript.count)"
            )
        } catch {
            transcript = []
            isLoading = false
            hasCompletedInitialTranscriptLoad = true
            didApplyInitialTranscriptReveal = true
            pendingInitialTranscriptScroll = false
            sendError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "DirectMessageResolveThread"
            )
        }
    }

    /// Receiver-side live DM: federation pull then transcript reload (checkpoint advances after reconcile/ack).
    @MainActor
    private func pullLatestFederationAndReloadTranscript(
        reason: String,
        trigger: ExchangeSyncEngine.Trigger = .appBecameActive
    ) async {
        guard let tid = resolvedThreadID else {
            #if DEBUG
            print(
                "[DMReceiveLive][visibleThreadMatch] openThreadID=nil counterparty=\(counterpartyNodeID) shouldReload=false reason=\(reason)"
            )
            #endif
            return
        }

        #if DEBUG
        print("[DMReceiveLive][syncTrigger] threadID=\(tid.uuidString) reason=\(reason)")
        #endif

        guard !livePullInFlight else {
            #if DEBUG
            print("[DMReceiveLive][syncSkipped] reason=\(reason) alreadyInFlight=true")
            #endif
            return
        }

        livePullInFlight = true
        defer { livePullInFlight = false }

        if let skipReason = await services.directMessageReceiveLiveSyncSkipReason(
            isSceneActive: scenePhase == .active
        ) {
            #if DEBUG
            print("[DMReceiveLive] skipSync reason=\(skipReason)")
            #endif
            return
        }

        let inboxDigestBefore = services.currentSecretaryInboxDigestCount()

        let syncRan = await services.syncFederationInboxNow(
            requestDeskRefreshAfter: false,
            recordAttentionDigests: false,
            trigger: trigger
        )

        guard syncRan else {
            #if DEBUG
            print("[DMReceiveLive] skipSync reason=backoffOrUnavailable")
            #endif
            return
        }

        let inboxDigestAfter = services.currentSecretaryInboxDigestCount()
        guard inboxDigestAfter != inboxDigestBefore else {
            #if DEBUG
            print("[DMReceiveLive] skipReload reason=noLocalDeltaAfterFailedSync")
            #endif
            return
        }

        await reloadTranscriptIfResolved(reason: "\(reason)|afterSync")
    }

    @MainActor
    private func handleDirectMessageTranscriptDidChange(_ notification: Notification) async {
        guard let event = DirectMessageTranscriptChangeEvent(userInfo: notification.userInfo) else { return }

        let openConversationKey = counterpartyNodeID
        let matchesThread = resolvedThreadID.map { $0 == event.threadID } ?? false
        let matchesCounterparty = event.counterpartyNodeID == openConversationKey
        let matches = matchesThread || matchesCounterparty

        print(
            "[DMTranscript][observerReceived] openConversationKey=\(openConversationKey) " +
            "eventConversationKey=\(event.conversationKey) matches=\(matches)"
        )

        guard matches else { return }
        await reloadTranscriptIfResolved(reason: "changeEvent|\(event.source.rawValue)")
    }

    @MainActor
    private func reloadTranscriptIfResolved(reason: String) async {
        guard let tid = resolvedThreadID else {
            print(
                "[DMTranscript][reload] reason=\(reason) skipped=true rowsBefore=0 rowsAfter=0 " +
                "note=noResolvedThreadID"
            )
            return
        }

        transcriptReloadGeneration &+= 1
        let generation = transcriptReloadGeneration
        let rowsBefore = transcript.count

        await loadTranscript(threadID: tid)

        guard generation == transcriptReloadGeneration else {
            print(
                "[DMTranscript][reload] reason=\(reason) skipped=true rowsBefore=\(rowsBefore) " +
                "rowsAfter=\(transcript.count) note=staleGeneration"
            )
            return
        }

        print(
            "[DMTranscript][reload] reason=\(reason) rowsBefore=\(rowsBefore) rowsAfter=\(transcript.count)"
        )
    }

    /// Same ordered rows (id, body, direction, timestamp): skip `transcript =` to avoid pointless list invalidation.
    private static func transcriptRowListsEquivalent(_ a: [DirectMessageBubble], _ b: [DirectMessageBubble]) -> Bool {
        guard a.count == b.count else { return false }
        for (left, right) in zip(a, b) {
            if left.id != right.id { return false }
            if left.body != right.body { return false }
            if left.isOutgoing != right.isOutgoing { return false }
            if left.timestamp != right.timestamp { return false }
        }
        return true
    }

    #if DEBUG
    private func dmTranscriptAssignTraceIfChanged(
        oldRows: [DirectMessageBubble],
        newRows: [DirectMessageBubble],
        isFocused: Bool
    ) {
        guard !Self.transcriptRowListsEquivalent(oldRows, newRows) else { return }
        let oldHead = oldRows.first?.id ?? "nil"
        let newHead = newRows.first?.id ?? "nil"
        let oldTail = oldRows.last?.id ?? "nil"
        let newTail = newRows.last?.id ?? "nil"
        print(
            "[DMTranscriptAssign] oldCount=\(oldRows.count) newCount=\(newRows.count) " +
                "oldHead=\(oldHead) newHead=\(newHead) oldTail=\(oldTail) newTail=\(newTail) focused=\(isFocused)"
        )
    }
    #endif

    @MainActor
    private func loadTranscript(threadID: ExchangeThread.ID) async {
        let hadExistingRows = !transcript.isEmpty
        if !hadExistingRows {
            isLoading = true
        }

        do {
            var detail = try await services.exchangeFacade.getThread(
                threadID: threadID,
                hydrationMode: .directMessage
            )
            if DirectMessageTranscriptProjection.shouldMergeUnfiledInboundForTranscript(detail: detail) {
                detail = await DirectMessageTranscriptProjection.detailMergingUnfiledSenderInbox(
                    detail,
                    counterpartyNodeID: counterpartyNodeID,
                    facade: services.exchangeFacade
                )
            }

            resolvedThreadID = threadID
            applyHeaderIdentity(detail: detail)
            await resolveMessagingAvatarURLs(detail: detail)

            let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
                detail: detail,
                counterpartyNodeID: counterpartyNodeID
            )
            let newRows = DirectMessageTranscriptProjection.rowsAfterClearWatermark(
                rendered.rows,
                counterpartyNodeID: counterpartyNodeID
            )

            #if DEBUG
            dmTranscriptAssignTraceIfChanged(oldRows: transcript, newRows: newRows, isFocused: isComposerFocused)
            #endif

            if Self.transcriptRowListsEquivalent(transcript, newRows) {
                lastRenderResult = rendered
            } else {
                transcript = newRows
                lastRenderResult = rendered
            }

            let latestMessageID = newRows.last?.id ?? "nil"
            print(
                "[DMTranscript][apply] rows=\(newRows.count) latestMessageID=\(latestMessageID)"
            )

            isLoading = false
            hasCompletedInitialTranscriptLoad = true

            if transcript.isEmpty {
                didApplyInitialTranscriptReveal = true
                pendingInitialTranscriptScroll = false
            } else if !didApplyInitialTranscriptReveal {
                pendingInitialTranscriptScroll = true
            }

            refreshComposerBlockedState()

            #if DEBUG
            print(
                "[DirectMessageLoad] threadID=\(threadID.uuidString) metadata.direct_message_thread=\(detail.thread.metadata["direct_message_thread"] ?? "false") metadata.inbound_thread=\(detail.thread.metadata["inbound_thread"] ?? "false") turns=\(detail.turns.count) inbox=\(detail.inboxItems.count) renderedMessage=\(rendered.rows.count) visibleAfterClear=\(newRows.count)"
            )
            let included = !newRows.isEmpty
            let preview = String((newRows.last?.body ?? "").prefix(120))
            let reason: String
            if included {
                reason = "has_rendered_bubbles"
            } else if detail.turns.isEmpty, detail.drafts.isEmpty, detail.inboxItems.isEmpty {
                reason = "empty_thread_detail"
            } else if !rendered.rows.isEmpty, newRows.isEmpty {
                reason = "hidden_by_local_clear_watermark"
            } else {
                reason = "filtered_or_empty_after_render"
            }
            print(
                "[DMRoute][chatProjection] threadID=\(threadID.uuidString) included=\(included) reason=\(reason) " +
                    "turnCount=\(detail.turns.count) latestMessagePreview=\(preview)"
            )
            #endif
        } catch {
            isLoading = false
            hasCompletedInitialTranscriptLoad = true
            didApplyInitialTranscriptReveal = true
            pendingInitialTranscriptScroll = false
            if transcript.isEmpty {
                transcript = []
            }
            sendError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "DirectMessageLoadTranscript"
            )
        }
    }

    private func applyHeaderIdentity(detail: ExchangeModels.ThreadDetail) {
        let profileName = detail.selectedCounterparty?.publicProfile?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let counterpartyName = detail.selectedCounterparty?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !profileName.isEmpty {
            headerDisplayName = profileName
        } else if !counterpartyName.isEmpty {
            headerDisplayName = counterpartyName
        } else if !fallbackName.isEmpty {
            headerDisplayName = fallbackName
        } else {
            if headerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                headerDisplayName = nil
            }
        }

        let profileSummary = [
            detail.selectedCounterparty?.publicProfile?.headline,
            detail.selectedCounterparty?.publicProfile?.summary
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        profileSummaryForSuggest = profileSummary.isEmpty ? nil : profileSummary

        let commercial = detail.selectedCounterparty?.publicProfile?.offers.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        commercialSummaryForSuggest = commercial.isEmpty ? nil : commercial

        contactContext = services.getContactContext(remoteNodeID: counterpartyNodeID)
        if let context = contactContext {
            #if DEBUG
            print("[ContactContextProjection] surface=dm nodeID=\(context.remoteNodeID) relationship=\(context.relationshipType.rawValue) goal=\(context.relationshipGoal.rawValue)")
            #endif
        }
    }

    /// Resolves remote/local public profile image URLs once per transcript load (not per row or keystroke).
    @MainActor
    private func resolveMessagingAvatarURLs(detail: ExchangeModels.ThreadDetail) async {
        let fromProfile = detail.selectedCounterparty?.publicProfile?.primaryImageURL?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var remote: String? = fromProfile.isEmpty ? nil : fromProfile

        let route = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !route.isEmpty,
           let summaries = try? await services.exchangeFacade.listCounterpartyProfileSummaries(nodeIDs: [route]),
           let summary = summaries[route] ?? summaries[route.lowercased()] {
            let freshName = summary.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !freshName.isEmpty, !freshName.lowercased().contains("node-") {
                headerDisplayName = freshName
            }

            if remote == nil {
                let trimmed = summary.avatarURL?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                remote = trimmed.isEmpty ? nil : trimmed
            }
        }

        if let remote, !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remoteAvatarURL = remote
        } else if remoteAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            remoteAvatarURL = nil
        }

        remoteSupporterPresentation = detail.selectedCounterparty?.publicProfile?.publicSupporterPresentation

        let localImg = services.sellerWorkspace?.publicProfile?.profile.primaryImageURL?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !localImg.isEmpty {
            localAvatarURL = localImg
        } else if localAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            localAvatarURL = nil
        }

        let localName = [
            services.sellerWorkspace?.ownerDisplayName,
            services.sellerWorkspace?.publicProfile?.displayName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if let localName {
            localAvatarTitleForInitials = localName
        } else if let node = await services.exchangeNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !node.isEmpty {
            localAvatarTitleForInitials = node.count > 18 ? "\(node.prefix(8))…\(node.suffix(6))" : node
        } else {
            localAvatarTitleForInitials = "Me"
        }

        #if DEBUG
        let tagList = ["Direct message"] + (relationshipLabel.map { [$0] } ?? [])
        print(
            "[DMHeaderProjection] nodeID=\(counterpartyNodeID) hasRemoteAvatar=\(remote != nil) hasLocalAvatar=\(localAvatarURL != nil) tags=\(tagList.joined(separator: "|"))"
        )
        #endif
    }

    private var relationshipLabel: String? {
        guard let context = contactContext else { return nil }

        switch context.relationshipType {
        case .friend:
            return "Friend"
        case .client:
            return "Client"
        case .colleague:
            return "Colleague"
        case .supplier:
            return "Supplier"
        case .family:
            return "Family"
        case .investor:
            return "Investor"
        case .broker:
            return "Broker"
        case .contractor:
            return "Contractor"
        case .lead:
            return "Lead"
        case .professionalContact:
            return "Professional"
        case .custom:
            return context.customRelationshipLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? context.customRelationshipLabel
                : "Custom"
        }
    }

    @MainActor
    private func resignComposerKeyboardIfNeeded() {
        isComposerFocused = false

        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// Use for any future programmatic focus; respects post-send suppression window.
    private func requestComposerFocus(_ focused: Bool, source: String) {
        guard focused else {
            isComposerFocused = false

            #if DEBUG
            print("[DMKeyboardFocus] event=focusRequested source=\(source) allowed=true focused=false")
            #endif

            return
        }

        if shouldSuppressComposerAutofocus {
            #if DEBUG
            print("[DMKeyboardFocus] event=autofocusBlocked reason=postSend source=\(source)")
            #endif

            return
        }

        isComposerFocused = true

        #if DEBUG
        print("[DMKeyboardFocus] event=focusRequested source=\(source) allowed=true focused=true")
        #endif
    }

    @MainActor
    private func send() async {
        let trimmedBody = sendBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty || pendingAttachment != nil else { return }

        if isCounterpartyBlockedForSend {
            sendError = Self.blockedContactComposerMessage
            return
        }

        sendError = nil
        sendInFlight = true
        defer { sendInFlight = false }

        #if DEBUG
        print("[DMKeyboardFocus] event=sendStart focused=\(isComposerFocused) sendInFlight=\(sendInFlight)")
        #endif

        do {
            let threadID = try await ensuredThreadIDForSend()
            let detail = try await services.exchangeFacade.getThread(
                threadID: threadID,
                hydrationMode: .directMessage
            )

            let returnedThreadID: ExchangeThread.ID
            if detail.thread.metadata["inbound_thread"] == "true" {
                if pendingAttachment != nil {
                    throw ExchangeStoreError.storageFailure(
                        reason: "File attachments can only be sent in a direct message to a trusted contact."
                    )
                }
                returnedThreadID = try await services.exchangeFacade.sendInboundProviderManualReply(
                    existingThreadID: threadID,
                    subject: nil,
                    body: trimmedBody,
                    now: Date()
                )
            } else {
                guard let targetNodeID = resolvedCounterpartyNodeIDForSend(detail: detail) else {
                    throw ExchangeStoreError.storageFailure(
                        reason: "This chat does not have a routable trusted contact."
                    )
                }

                let outboundAttachment: DirectMessageOutboundAttachmentInput? = pendingAttachment.map {
                    DirectMessageOutboundAttachmentInput(
                        fileURL: $0.stagingURL,
                        filename: $0.filename,
                        mimeType: $0.mimeType
                    )
                }

                returnedThreadID = try await services.exchangeFacade.sendManualMessageToTrustedNode(
                    trustedNodeID: targetNodeID,
                    existingThreadID: threadID,
                    subject: nil,
                    body: trimmedBody,
                    attachment: outboundAttachment,
                    now: Date()
                )
            }

            resolvedThreadID = returnedThreadID
            pendingAttachment = nil

            #if DEBUG
            print(
                "[DirectMessageSend] threadID=\(returnedThreadID.uuidString) nodeID=\(counterpartyNodeID) bodyChars=\(trimmedBody.count) result=success"
            )
            #endif

            // Clear sending state *before* transcript reload so the composer is not toggled
            // `.disabled(sendInFlight)` after a large layout pass (common iOS keyboard snap-back).
            sendInFlight = false

            sendBody = ""
            composerFieldGeneration &+= 1
            shouldSuppressComposerAutofocus = true
            resignComposerKeyboardIfNeeded()

            #if DEBUG
            print(
                "[DMKeyboardFocus] event=sendSuccessDismiss focused=false suppressAutofocus=true fieldGen=\(composerFieldGeneration)"
            )
            print(
                "[DMKeyboardDismiss] reason=sendSuccess threadID=\(returnedThreadID.uuidString) bodyChars=\(trimmedBody.count)"
            )
            #endif

            await loadTranscript(threadID: returnedThreadID)

            resignComposerKeyboardIfNeeded()

            #if DEBUG
            print("[DMKeyboardFocus] event=sendSuccessPostTranscriptDismiss focused=\(isComposerFocused)")
            #endif

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": returnedThreadID.uuidString]
            )

            Task {
                await services.exchangeSyncEngine.runPass(trigger: .afterApprovalGranted, now: Date())
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                shouldSuppressComposerAutofocus = false

                #if DEBUG
                print("[DMKeyboardFocus] event=suppressAutofocusCleared (no automatic refocus)")
                #endif
            }
        } catch {
            #if DEBUG
            print(
                "[DirectMessageSend] threadID=\(resolvedThreadID?.uuidString ?? "nil") nodeID=\(counterpartyNodeID) bodyChars=\(trimmedBody.count) result=failed"
            )
            print("[DMKeyboardFocus] event=sendFailedKeepFocus focused=\(isComposerFocused)")
            #endif

            sendError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "DirectMessageSend"
            )
        }
    }

    @MainActor
    private func ensuredThreadIDForSend() async throws -> ExchangeThread.ID {
        if let resolvedThreadID {
            return resolvedThreadID
        }

        let created = try await services.exchangeFacade.openOrCreateDirectMessageThread(
            counterpartyNodeID: counterpartyNodeID,
            displayName: displayName,
            now: Date()
        )
        resolvedThreadID = created
        return created
    }

    private func resolvedCounterpartyNodeIDForSend(detail: ExchangeModels.ThreadDetail) -> String? {
        let routeNode = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !routeNode.isEmpty { return routeNode }

        let threadNode = detail.thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !threadNode.isEmpty { return threadNode }

        return nil
    }

    private func initials(from value: String) -> String {
        let initials = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let output = String(initials).uppercased()
        return output.isEmpty ? "DM" : output
    }

    // MARK: - Suggestions

    /// Display name for direct-chat voice anchoring: onboarding / identity / workspace / fallback.
    @MainActor
    private func resolveLocalUserDisplayNameForSuggest() async -> String {
        let ud = UserDefaults.standard
        let fromDefaults = [
            ud.string(forKey: "userName"),
            ud.string(forKey: "onboarding.userName")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let fromDefaults {
            return fromDefaults
        }
        if let identity = await services.localExchangeDisplayName()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            return identity
        }
        let workspaceLine = [
            services.sellerWorkspace?.ownerDisplayName,
            services.sellerWorkspace?.publicProfile?.displayName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let workspaceLine {
            return workspaceLine
        }
        return "Me"
    }

    private static func normalizeDirectReplySuggestionForRepeatCheck(_ value: String?) -> String {
        let trimmed = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased() ?? ""

        return trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func debugDirectReplyPreview(_ value: String?, maxLength: Int) -> String {
        let cleaned = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") ?? "nil"

        return String(cleaned.prefix(maxLength))
    }

    @MainActor
    private func suggestReply(regenerate: Bool = false) async {
        #if DEBUG
        let perfSuggestStart = CFAbsoluteTimeGetCurrent()
        print("[DirectReplyPerf] tap_start")
        defer {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - perfSuggestStart) * 1000)
            print("[DirectReplyPerf] ui_done totalMs=\(totalMs)")
        }
        #endif

        suggestionError = nil

        let capped = Array(transcript.suffix(4))
        let transcriptMessages = capped.map { row in
            ExchangeModels.DirectReplyTranscriptMessage(
                role: row.isOutgoing ? .localUser : .remoteContact,
                text: row.body,
                timestamp: row.timestamp,
                source: row.source
            )
        }

        let context = contactContext ?? services.getContactContext(remoteNodeID: counterpartyNodeID)
        let latestIncoming = latestIncomingMessageForSuggest
        let hasTone = !(context.toneOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if context.aiAssistLevel == .autoReplyDisabled {
            #if DEBUG
            print("[DirectReplySuggestBlocked] reason=auto_reply_disabled")
            DirectChatReplySuggestionService.logDirectReplySummary(
                promptChars: 0,
                recentCount: transcriptMessages.count,
                hasInbound: latestIncoming != nil,
                hasTone: hasTone,
                replyChars: 0
            )
            #endif
            suggestionError = "AI suggestions are turned off for this contact."
            return
        }

        guard let latestIncoming else {
            #if DEBUG
            print("[DirectReplySuggestBlocked] reason=no_inbound_messages")
            DirectChatReplySuggestionService.logDirectReplySummary(
                promptChars: 0,
                recentCount: transcriptMessages.count,
                hasInbound: false,
                hasTone: hasTone,
                replyChars: 0
            )
            #endif
            suggestionError = "No incoming message to reply to yet."
            return
        }

        suggestionBusy = true
        defer { suggestionBusy = false }

        let latestIncomingForKey = latestIncoming
        let directReplyTargetKey = "\(counterpartyNodeID)|\(latestIncomingForKey)"

        if lastDirectReplyTargetKey != directReplyTargetKey {
            previousDirectReplySuggestions = []
            directReplyRegenerationCount = 0
            lastDirectReplyTargetKey = directReplyTargetKey
        }

        if regenerate {
            directReplyRegenerationCount += 1

            #if DEBUG
            print("[DirectReplyRegenerate] count=\(directReplyRegenerationCount) previousCount=\(previousDirectReplySuggestions.count)")
            #endif
        }

        #if DEBUG
        let excludedCount: Int = {
            guard let rendered = lastRenderResult else { return 0 }
            return rendered.skippedSystemRows + rendered.skippedAgencyRows + rendered.skippedContactRequestRows + rendered.dedupedRows
        }()
        let oldest = transcriptMessages.first?.timestamp?.description ?? "nil"
        let newest = transcriptMessages.last?.timestamp?.description ?? "nil"
        let latestChars = latestIncoming.count
        print(
            "[DirectReplyTranscript] nodeID=\(counterpartyNodeID) included=\(transcriptMessages.count) excluded=\(excludedCount) latestIncomingChars=\(latestChars) oldestIncluded=\(oldest) newestIncluded=\(newest)"
        )
        #endif

        let localUserDisplayName = await resolveLocalUserDisplayNameForSuggest()
        let input = ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: counterpartyNodeID,
            localUserDisplayName: localUserDisplayName,
            contactDisplayName: titleText,
            latestIncomingMessage: latestIncoming,
            recentTranscript: transcriptMessages,
            contactContext: context,
            relationshipType: context.relationshipType,
            relationshipGoal: context.relationshipGoal,
            relationshipNotes: context.notes,
            toneOverride: context.toneOverride,
            userSecretaryStyle: nil,
            userSecretaryConstitution: nil,
            contactPublicProfileSummary: profileSummaryForSuggest,
            contactCommercialProfileSummary: commercialSummaryForSuggest,
            safetyRules: []
        )

        let regenerationInstruction: String? = {
            guard regenerate else { return nil }

            let previous = previousDirectReplySuggestions
                .suffix(5)
                .map { "- \($0)" }
                .joined(separator: "\n")

            if previous.isEmpty {
                return """
                Generate a different reply option. Keep it natural, concise, and directly responsive to latestIncomingMessage.
                Use a different opening and sentence shape than any prior suggestion.
                """
            }

            return """
            Generate a different reply option from the previous suggestions below.
            Do not repeat or closely paraphrase any previous suggestion.
            Use a clearly different opening and wording.
            Keep it natural, concise, and directly responsive to latestIncomingMessage.

            Previous suggestions:
            \(previous)
            """
        }()

        #if DEBUG
        if let regenerationInstruction {
            print("[DirectReplyRegenerateInstruction] chars=\(regenerationInstruction.count)")
        }
        #endif

        #if DEBUG
        let inputReadyMs = Int((CFAbsoluteTimeGetCurrent() - perfSuggestStart) * 1000)
        print(
            "[DirectReplyPerf] input_ready elapsedMs=\(inputReadyMs) transcriptCount=\(transcriptMessages.count) recentMessagesCount=\(transcriptMessages.count)"
        )
        #endif

        var result = await services.suggestDirectReply(
            input: input,
            userInstruction: regenerationInstruction,
            previousSuggestions: previousDirectReplySuggestions
        )

        if regenerate, isNearRepeatOfPreviousSuggestions(result.reply) {
            #if DEBUG
            print("[DirectReplyRegenerateAutoRetry] phase=start previousCount=\(previousDirectReplySuggestions.count)")
            #endif

            let autoRetryInstruction = """
            Generate a clearly different reply option.
            Do not repeat or closely paraphrase any previous suggestion or latestIncomingMessage.
            Use a different opening and sentence shape.
            """

            result = await services.suggestDirectReply(
                input: input,
                userInstruction: autoRetryInstruction,
                previousSuggestions: previousDirectReplySuggestions
            )
        }

        if result.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            suggestionError = "No suggestion available."
            return
        }

        let normalizedResultReply = Self.normalizeDirectReplySuggestionForRepeatCheck(result.reply)
        let repeatedPreviousSuggestion = previousDirectReplySuggestions.contains { previous in
            Self.normalizeDirectReplySuggestionForRepeatCheck(previous) == normalizedResultReply
        }

        if regenerate, repeatedPreviousSuggestion || isNearRepeatOfPreviousSuggestions(result.reply) {
            #if DEBUG
            print("[DirectReplyRegenerateDuplicateRejected] replyPreview=\(Self.debugDirectReplyPreview(result.reply, maxLength: 180))")
            print("[DirectReplyAudit] regenerateDuplicateNoOp=true previousSuggestionsCount=\(previousDirectReplySuggestions.count)")
            #endif
            suggestionError = "Couldn't generate a different reply. Try again."
            return
        }

        let trimmedResultReply = result.reply.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !trimmedResultReply.isEmpty {
            let alreadyStored = previousDirectReplySuggestions.contains { previous in
                Self.normalizeDirectReplySuggestionForRepeatCheck(previous)
                    == Self.normalizeDirectReplySuggestionForRepeatCheck(trimmedResultReply)
            }

            if !alreadyStored {
                previousDirectReplySuggestions.append(trimmedResultReply)
                if previousDirectReplySuggestions.count > 5 {
                    previousDirectReplySuggestions = Array(previousDirectReplySuggestions.suffix(5))
                }
            }
        }

        suggestion = result
    }

    private func isNearRepeatOfPreviousSuggestions(_ reply: String) -> Bool {
        let normalizedReply = Self.normalizeDirectReplySuggestionForRepeatCheck(reply)
        guard !normalizedReply.isEmpty else { return false }

        let replyTokens = Set(
            normalizedReply
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        guard replyTokens.count >= 4 else { return false }

        for previous in previousDirectReplySuggestions {
            let priorNorm = Self.normalizeDirectReplySuggestionForRepeatCheck(previous)
            guard !priorNorm.isEmpty else { continue }

            let priorTokens = Set(
                priorNorm
                    .split(separator: " ")
                    .map(String.init)
                    .filter { !$0.isEmpty }
            )
            guard !priorTokens.isEmpty else { continue }

            let overlap = Double(replyTokens.intersection(priorTokens).count) / Double(replyTokens.count)
            if overlap >= 0.70 {
                return true
            }

            let replyOpening = normalizedReply
                .split(separator: " ")
                .prefix(3)
                .joined(separator: " ")
            let priorOpening = priorNorm
                .split(separator: " ")
                .prefix(3)
                .joined(separator: " ")
            if replyOpening.count >= 8, replyOpening == priorOpening {
                return true
            }
        }

        return false
    }

    // MARK: - DM attachments (no AI ingestion)

    @ViewBuilder
    private func dmAttachmentBubbleCard(
        _ attachment: DirectMessageAttachmentDescriptor,
        outgoing: Bool
    ) -> some View {
        let isOpening = openingAttachmentID == attachment.attachmentID
        let openPreview: () -> Void = {
            Task { @MainActor in
                await openAttachmentPreview(attachment)
            }
        }

        if isDMAttachmentImage(attachment) {
            #if canImport(UIKit)
            DMAttachmentImageBubbleCard(
                attachment: attachment,
                outgoing: outgoing,
                isOpening: isOpening,
                onTap: openPreview,
                fileRowFallback: {
                    dmAttachmentFileBubbleCard(
                        attachment,
                        outgoing: outgoing,
                        isOpening: isOpening,
                        onTap: openPreview
                    )
                }
            )
            #else
            dmAttachmentFileBubbleCard(
                attachment,
                outgoing: outgoing,
                isOpening: isOpening,
                onTap: openPreview
            )
            #endif
        } else {
            dmAttachmentFileBubbleCard(
                attachment,
                outgoing: outgoing,
                isOpening: isOpening,
                onTap: openPreview
            )
        }
    }

    private func dmAttachmentFileBubbleCard(
        _ attachment: DirectMessageAttachmentDescriptor,
        outgoing: Bool,
        isOpening: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: dmAttachmentIconName(mimeType: attachment.mimeType))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(outgoing ? Color.white : SecretaryTheme.darkOrange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(outgoing ? Color.white : SecretaryTheme.darkPrimaryText)
                            .lineLimit(2)
                        Text(dmAttachmentSizeLabel(attachment.byteSize))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(
                                outgoing ? Color.white.opacity(0.7) : SecretaryTheme.darkSecondaryText
                            )
                    }

                    Spacer(minLength: 0)

                    if isOpening {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(outgoing ? .white : SecretaryTheme.darkOrange)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                outgoing ? Color.white.opacity(0.55) : SecretaryTheme.darkSecondaryText
                            )
                    }
                }

                Text("Tap to preview or share")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(outgoing ? Color.white.opacity(0.85) : SecretaryTheme.darkOrange)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        outgoing
                            ? Color.white.opacity(0.12)
                            : SecretaryTheme.darkBackground.opacity(0.22)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .accessibilityLabel("Preview attachment \(attachment.filename)")
    }

    @MainActor
    private func handlePickedDMAttachment(url: URL) async {
        attachmentActionError = nil
        do {
            let staged = try stageDMAttachmentForUpload(from: url)
            pendingAttachment = staged
        } catch {
            attachmentActionError = error.localizedDescription
        }
    }

    @MainActor
    private func handlePickedDMPhoto(item: PhotosPickerItem) async {
        attachmentActionError = nil
        #if canImport(UIKit)
        do {
            guard let image = await SharedPhotoEditFlow.loadUIImage(from: item, context: "dmAttachment") else {
                attachmentActionError = "Could not load the selected photo."
                return
            }
            let prepared = try prepareDMPhotoAttachmentJPEG(from: image)
            let staged = try stageDMAttachmentForUpload(
                data: prepared.data,
                filename: prepared.filename,
                mimeType: prepared.mimeType
            )
            pendingAttachment = staged
        } catch {
            attachmentActionError = error.localizedDescription
        }
        #else
        attachmentActionError = "Photo attachments are not available on this platform."
        #endif
    }

    @MainActor
    private func stageDMAttachmentForUpload(from url: URL) throws -> PendingDMAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let filename = (url.lastPathComponent as NSString).lastPathComponent
        let mimeType = dmMimeType(for: url, data: data)
        return try stageDMAttachmentForUpload(data: data, filename: filename, mimeType: mimeType)
    }

    @MainActor
    private func stageDMAttachmentForUpload(
        data: Data,
        filename: String,
        mimeType: String
    ) throws -> PendingDMAttachment {
        guard !data.isEmpty else {
            throw NSError(domain: "DMAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is empty."])
        }
        guard data.count <= 10 * 1024 * 1024 else {
            throw NSError(
                domain: "DMAttachment",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Attachments must be 10 MB or smaller."]
            )
        }

        guard dmIsAllowedMimeType(mimeType) else {
            throw NSError(
                domain: "DMAttachment",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "This file type is not supported for DM attachments."]
            )
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-attachment-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagingURL = stagingDir.appendingPathComponent("\(UUID().uuidString)-\(filename)")

        try data.write(to: stagingURL, options: [.atomic])
        return PendingDMAttachment(
            stagingURL: stagingURL,
            filename: filename,
            mimeType: mimeType,
            byteSize: data.count
        )
    }

    #if canImport(UIKit)
    private func prepareDMPhotoAttachmentJPEG(from image: UIImage) throws -> (data: Data, filename: String, mimeType: String) {
        let resized = dmResizePhotoLongestEdge(image, maxEdge: 2048)
        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality)
        while let current = data, current.count > 10 * 1024 * 1024, quality > 0.5 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        guard let jpegData = data, !jpegData.isEmpty else {
            throw NSError(
                domain: "DMAttachment",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not prepare the selected photo."]
            )
        }
        guard jpegData.count <= 10 * 1024 * 1024 else {
            throw NSError(
                domain: "DMAttachment",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Attachments must be 10 MB or smaller."]
            )
        }
        return (jpegData, "photo-\(UUID().uuidString.prefix(8)).jpg", "image/jpeg")
    }

    private func dmResizePhotoLongestEdge(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif

    @MainActor
    private func openAttachmentPreview(_ attachment: DirectMessageAttachmentDescriptor) async {
        attachmentActionError = nil
        openingAttachmentID = attachment.attachmentID
        defer { openingAttachmentID = nil }

        do {
            let fileURL = try await services.exchangeFacade.resolveDirectMessageAttachmentFile(attachment)
            attachmentPreviewPresentation = DMAttachmentPreviewPresentation(
                fileURL: fileURL,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                isImage: isDMAttachmentImage(attachment)
            )
        } catch {
            attachmentActionError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "DMAttachmentPreview"
            )
        }
    }

    #if canImport(UIKit)
    @MainActor
    private func presentDMAttachmentShare(for url: URL) {
        shareAttachmentURL = url
        showAttachmentShareSheet = true
    }
    #endif

    private func isDMAttachmentImage(_ attachment: DirectMessageAttachmentDescriptor) -> Bool {
        isDMAttachmentImage(mimeType: attachment.mimeType, filename: attachment.filename)
    }

    private func isDMAttachmentImage(mimeType: String, filename: String) -> Bool {
        let mime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mime.hasPrefix("image/") { return true }
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"].contains(ext)
    }

    private func dmMimeType(for url: URL, data: Data) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime.lowercased()
        }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
        return "application/octet-stream"
    }

    private func dmIsAllowedMimeType(_ mime: String) -> Bool {
        let allowed: Set<String> = [
            "application/pdf",
            "text/plain",
            "text/csv",
            "image/jpeg",
            "image/png",
            "image/webp",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ]
        return allowed.contains(mime.lowercased())
    }

    private func dmAttachmentIconName(mimeType: String) -> String {
        let m = mimeType.lowercased()
        if m.hasPrefix("image/") { return "photo" }
        if m == "application/pdf" { return "doc.fill" }
        if m.hasPrefix("text/") { return "doc.text" }
        return "paperclip"
    }

    private func dmAttachmentSizeLabel(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

private struct DMAttachmentTrayTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - DM inline image thumbnail (transcript bubble)

#if canImport(UIKit)
private struct DMAttachmentImageBubbleCard<Fallback: View>: View {
    @EnvironmentObject private var services: AppServices

    let attachment: DirectMessageAttachmentDescriptor
    let outgoing: Bool
    let isOpening: Bool
    let onTap: () -> Void
    @ViewBuilder let fileRowFallback: () -> Fallback

    @State private var uiImage: UIImage?
    @State private var loadFailed = false
    @State private var decryptFailureMessage: String?

    /// Stable in-chat thumbnail frame (1:1). Full uncropped image is shown only in tap-to-preview.
    private let photoFrameWidth: CGFloat = 252
    private let photoFrameAspect: CGFloat = 1
    private let photoCornerRadius: CGFloat = 16

    private var photoFrameHeight: CGFloat {
        photoFrameWidth / photoFrameAspect
    }

    var body: some View {
        Group {
            if let decryptFailureMessage {
                Text(decryptFailureMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(outgoing ? Color.white.opacity(0.82) : Color.primary.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                            .fill(outgoing ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    )
            } else if loadFailed {
                fileRowFallback()
            } else {
                imageBubbleBody
            }
        }
        .task(id: attachment.storageKey) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var imageBubbleBody: some View {
        Button(action: onTap) {
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoFrameWidth, height: photoFrameHeight)
                        .clipped()
                        .clipShape(
                            RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(outgoing ? 0.14 : 0.08), lineWidth: 0.5)
                        }
                        .overlay {
                            if isOpening {
                                ZStack {
                                    Color.black.opacity(0.28)
                                    ProgressView()
                                        .tint(.white)
                                }
                                .clipShape(
                                    RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                                )
                            }
                        }
                } else {
                    photoLoadingPlaceholder
                }
            }
            .frame(width: photoFrameWidth, height: photoFrameHeight)
            .contentShape(
                RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .shadow(
            color: SecretaryTheme.darkShadow.opacity(outgoing ? 0.2 : 0.12),
            radius: 6,
            x: 0,
            y: 3
        )
        .accessibilityLabel("Preview image \(attachment.filename)")
    }

    private var photoLoadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                .fill(SecretaryTheme.darkBackground.opacity(0.32))
            if outgoing {
                UnifyGlassPlateBackground(cornerRadius: photoCornerRadius)
                    .opacity(0.55)
            }
            ProgressView()
                .scaleEffect(0.9)
                .tint(outgoing ? .white : SecretaryTheme.darkOrange)
        }
        .frame(width: photoFrameWidth, height: photoFrameHeight)
        .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
    }

    @MainActor
    private func loadThumbnail() async {
        loadFailed = false
        decryptFailureMessage = nil
        uiImage = nil

        if DirectMessageAttachmentCache.isCached(
            storageKey: attachment.storageKey,
            filename: attachment.filename
        ),
           let cached = try? DirectMessageAttachmentCache.cachedFileURL(
               storageKey: attachment.storageKey,
               filename: attachment.filename
           ),
           let image = UIImage(contentsOfFile: cached.path) {
            uiImage = image
            return
        }

        do {
            let fileURL = try await services.exchangeFacade.resolveDirectMessageAttachmentFile(attachment)
            if let image = UIImage(contentsOfFile: fileURL.path) {
                uiImage = image
            } else {
                loadFailed = true
            }
        } catch {
            if case ExchangeDMAttachmentClientError.encryptedDecryptFailed = error {
                decryptFailureMessage = "Encrypted attachment could not be opened."
            } else if error is ExchangeAttachmentOpenerError {
                decryptFailureMessage = "Encrypted attachment could not be opened."
            } else {
                loadFailed = true
            }
        }
    }
}
#endif

// MARK: - DM attachment preview (local file / QuickLook)

#if canImport(UIKit)
private struct DMAttachmentActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DMAttachmentQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct DMAttachmentLocalImagePreview: View {
    let presentation: DMAttachmentPreviewPresentation
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var uiImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    Spacer()

                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Text(presentation.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                Group {
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else if loadFailed {
                        Text("Could not load this photo.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            }
        }
        .task(id: presentation.fileURL) {
            loadFailed = false
            uiImage = UIImage(contentsOfFile: presentation.fileURL.path)
            loadFailed = uiImage == nil
        }
    }
}

private struct DMAttachmentFilePreviewSheet: View {
    let presentation: DMAttachmentPreviewPresentation
    let onDismiss: () -> Void
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            DMAttachmentQuickLookPreview(url: presentation.fileURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(presentation.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onDismiss)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Share", action: onShare)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
