import SwiftUI
import UIKit
import AnumCore

// MARK: - Intent composer (UIKit text view for `.dark` keyboard appearance)

#if DEBUG
@inline(__always)
private func secComposerLog(_ message: @autoclosure () -> String) {
    Swift.print("[SEC][Composer] \(message())")
}

@inline(__always)
private func secComposerFocusLog(_ message: @autoclosure () -> String) {
    Swift.print("[SEC][ComposerFocus] \(message())")
}

@inline(__always)
private func secComposerTimingLog(_ event: String, detail: String = "") {
    IntentComposerTiming.log(event, detail: detail)
}

private enum IntentComposerTiming {
    private static var anchor: CFAbsoluteTime = 0

    static func reset() {
        anchor = CFAbsoluteTimeGetCurrent()
    }

    static func log(_ event: String, detail: String = "") {
        let ms = Int((CFAbsoluteTimeGetCurrent() - anchor) * 1000)
        if detail.isEmpty {
            Swift.print("[SEC][ComposerTiming] t+\(ms)ms \(event)")
        } else {
            Swift.print("[SEC][ComposerTiming] t+\(ms)ms \(event) \(detail)")
        }
    }
}
#else
@inline(__always)
private func secComposerLog(_ message: @autoclosure () -> String) {}

@inline(__always)
private func secComposerFocusLog(_ message: @autoclosure () -> String) {}

@inline(__always)
private func secComposerTimingLog(_ event: String, detail: String = "") {}

private enum IntentComposerTiming {
    static func reset() {}
    static func log(_ event: String, detail: String = "") {}
}
#endif

/// Shared keyboard traits for the intent search composer (must match launch prewarm field).
private enum SecretaryIntentComposerTextTraits {
    static func applySearchComposerTraits(to textView: UITextView) {
        textView.keyboardAppearance = .dark
        textView.returnKeyType = .default
        textView.keyboardType = .default
        textView.textContentType = nil
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
    }
}

/// UIKit-backed composer field. Identity is stable across body recomputes:
/// `makeUIView` configures the field once (font, tint, keyboard appearance, autocorrection,
/// delegate, container insets), and `updateUIView` only mutates state that actually changed.
/// Focus is driven by a strictly-increasing `focusPulse` and is idempotent: we never call
/// `becomeFirstResponder()` while the field is already first responder.
private struct SecretaryIntentComposerTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isPresented: Bool
    var focusPulse: Int
    var focusSessionGeneration: Int
    var latestScheduledFocusPulse: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SecretaryIntentComposerTextViewRepresentable
        /// Last `focusPulse` applied; focus only when pulse strictly increases (avoids auto-focus on first `0` frame).
        var appliedFocusPulse: Int = 0
        weak var placeholderLabel: UILabel?
        var lastPlaceholder: String = ""
        private var keyboardWillShowObserver: NSObjectProtocol?
        private var keyboardDidShowObserver: NSObjectProtocol?
        #if DEBUG
        private var hasLoggedFirstKeystroke = false
        private var hasLoggedFirstDeleteToEmpty = false
        #endif

        private let caretAccent = UIColor(red: 1.0, green: 0.42, blue: 0.18, alpha: 1.0)
        private let caretIdle = UIColor(white: 0.55, alpha: 1.0)

        init(_ parent: SecretaryIntentComposerTextViewRepresentable) {
            self.parent = parent
        }

        deinit {
            if let keyboardWillShowObserver {
                NotificationCenter.default.removeObserver(keyboardWillShowObserver)
            }
            if let keyboardDidShowObserver {
                NotificationCenter.default.removeObserver(keyboardDidShowObserver)
            }
        }

        func registerKeyboardTimingObservers() {
            guard keyboardWillShowObserver == nil, keyboardDidShowObserver == nil else { return }
            keyboardWillShowObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { _ in
                secComposerTimingLog("keyboardWillShow")
            }
            keyboardDidShowObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { _ in
                secComposerTimingLog("keyboardDidShow")
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            let trimmed = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            if !hasLoggedFirstKeystroke, !trimmed.isEmpty {
                hasLoggedFirstKeystroke = true
                secComposerTimingLog("firstKeystroke", detail: "len=\(trimmed.count)")
            }
            if hasLoggedFirstKeystroke, !hasLoggedFirstDeleteToEmpty, trimmed.isEmpty {
                hasLoggedFirstDeleteToEmpty = true
                secComposerTimingLog("firstDeleteToEmpty")
            }
            #endif
            parent.text = textView.text ?? ""
            refreshPlaceholder(textView: textView)
            updateCaretTint(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Caret stays neutral on focus while empty; turns orange only once the user types.
            updateCaretTint(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.tintColor != caretIdle {
                textView.tintColor = caretIdle
            }
        }

        func refreshPlaceholder(textView: UITextView) {
            let empty = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let target = !empty
            if placeholderLabel?.isHidden != target {
                placeholderLabel?.isHidden = target
            }
        }

        func updateCaretTint(for textView: UITextView) {
            let empty = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let target = empty ? caretIdle : caretAccent
            if textView.tintColor != target {
                textView.tintColor = target
            }
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 16, weight: .regular)
        tv.textColor = .white
        tv.tintColor = UIColor(white: 0.55, alpha: 1.0)
        tv.isScrollEnabled = true
        SecretaryIntentComposerTextTraits.applySearchComposerTraits(to: tv)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        tv.delegate = context.coordinator
        context.coordinator.registerKeyboardTimingObservers()

        let pl = UILabel()
        pl.text = placeholder
        pl.textColor = UIColor.white.withAlphaComponent(0.42)
        pl.font = .systemFont(ofSize: 16, weight: .regular)
        pl.numberOfLines = 0
        pl.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(pl)
        NSLayoutConstraint.activate([
            pl.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 2),
            pl.trailingAnchor.constraint(equalTo: tv.trailingAnchor, constant: -2),
            pl.topAnchor.constraint(equalTo: tv.topAnchor, constant: 5)
        ])
        context.coordinator.placeholderLabel = pl
        context.coordinator.lastPlaceholder = placeholder
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if context.coordinator.lastPlaceholder != placeholder {
            context.coordinator.placeholderLabel?.text = placeholder
            context.coordinator.lastPlaceholder = placeholder
        }
        context.coordinator.refreshPlaceholder(textView: uiView)

        context.coordinator.parent = self

        guard isPresented else {
            #if DEBUG
            secComposerFocusLog(
                "skip reason=notPresented pulse=\(focusPulse) generation=\(focusSessionGeneration)"
            )
            #endif
            return
        }
        guard focusPulse > 0 else { return }
        guard focusPulse == latestScheduledFocusPulse else {
            #if DEBUG
            secComposerFocusLog(
                "skip reason=staleRepresentablePulse captured=\(focusPulse) latest=\(latestScheduledFocusPulse) current=\(focusPulse)"
            )
            #endif
            return
        }
        guard context.coordinator.appliedFocusPulse < focusPulse || !uiView.isFirstResponder else { return }

        if uiView.isFirstResponder {
            context.coordinator.appliedFocusPulse = focusPulse
            #if DEBUG
            secComposerFocusLog(
                "apply pulse=\(focusPulse) generation=\(focusSessionGeneration) focusedBefore=true"
            )
            secComposerLog("focusPulse=\(focusPulse) noop (already firstResponder)")
            #endif
            return
        }

        let pulseToApply = focusPulse
        let generationToApply = focusSessionGeneration
        #if DEBUG
        secComposerTimingLog(
            "updateUIViewFocusQueued",
            detail: "pulse=\(pulseToApply) generation=\(generationToApply)"
        )
        #endif
        DispatchQueue.main.async { [weak uiView] in
            guard let uiView else { return }
            let parent = context.coordinator.parent

            guard parent.isPresented else {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=notPresented pulse=\(pulseToApply) generation=\(generationToApply)"
                )
                #endif
                return
            }
            guard parent.focusSessionGeneration == generationToApply else {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=staleRepresentableGeneration pulse=\(pulseToApply) captured=\(generationToApply) current=\(parent.focusSessionGeneration)"
                )
                #endif
                return
            }
            guard parent.focusPulse == pulseToApply else {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=staleRepresentablePulse captured=\(pulseToApply) latest=\(parent.latestScheduledFocusPulse) current=\(parent.focusPulse)"
                )
                #endif
                return
            }
            guard parent.latestScheduledFocusPulse == pulseToApply else {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=staleRepresentablePulse captured=\(pulseToApply) latest=\(parent.latestScheduledFocusPulse) current=\(parent.focusPulse)"
                )
                #endif
                return
            }
            guard uiView.window != nil else {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=noWindow pulse=\(pulseToApply) generation=\(generationToApply)"
                )
                #endif
                return
            }
            guard context.coordinator.appliedFocusPulse < pulseToApply || !uiView.isFirstResponder else { return }

            if uiView.isFirstResponder {
                context.coordinator.appliedFocusPulse = pulseToApply
                #if DEBUG
                secComposerFocusLog(
                    "apply pulse=\(pulseToApply) generation=\(generationToApply) focusedBefore=true"
                )
                #endif
                return
            }

            #if DEBUG
            secComposerFocusLog(
                "apply pulse=\(pulseToApply) generation=\(generationToApply) focusedBefore=false"
            )
            secComposerTimingLog("becomeFirstResponderBegin", detail: "pulse=\(pulseToApply)")
            #endif
            let didFocus = uiView.becomeFirstResponder()
            #if DEBUG
            secComposerTimingLog(
                "becomeFirstResponderEnd",
                detail: "pulse=\(pulseToApply) success=\(didFocus)"
            )
            secComposerLog("becomeFirstResponder pulse=\(pulseToApply) success=\(didFocus)")
            #endif
            guard didFocus || uiView.isFirstResponder else { return }
            context.coordinator.appliedFocusPulse = pulseToApply
        }
    }
}

/// Compact dark-glass desk composer (Plus / seeded prompts). Keystrokes stay local to this subtree.
private struct SecretaryDeskHomeComposer: View {
    @EnvironmentObject private var services: AppServices
    @Binding var draftText: String
    var isPresented: Bool
    var focusPulse: Int
    var focusSessionGeneration: Int
    var latestScheduledFocusPulse: Int
    var onCancel: () -> Void
    var onSendComplete: () -> Void

    private static let barHeight: CGFloat = 57
    private static let buttonTapSize: CGFloat = 40
    private static let textFieldHeight: CGFloat = 36

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .buttonStyle(.plain)
            .frame(width: Self.buttonTapSize, height: Self.buttonTapSize)
            .accessibilityLabel("Dismiss composer")

            SecretaryIntentComposerTextViewRepresentable(
                text: $draftText,
                placeholder: "Search people, services, offers, or opportunities",
                isPresented: isPresented,
                focusPulse: focusPulse,
                focusSessionGeneration: focusSessionGeneration,
                latestScheduledFocusPulse: latestScheduledFocusPulse
            )
            .frame(maxWidth: .infinity)
            .frame(height: Self.textFieldHeight)

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(
                        trimmedDraft.isEmpty
                        ? SecretaryTheme.darkMutedText
                        : SecretaryTheme.darkOrange
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedDraft.isEmpty)
            .opacity(trimmedDraft.isEmpty ? 0.38 : 1.0)
            .frame(width: Self.buttonTapSize, height: Self.buttonTapSize)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SecretaryTheme.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
        // Composer height/seam must not animate while keyboard is mounting, even if an ancestor
        // (e.g. tab/route change) is inside a `withAnimation` block.
        .transaction { $0.animation = nil }
        #if DEBUG
        .onAppear {
            secComposerTimingLog("composerMounted", detail: "textEmpty=\(trimmedDraft.isEmpty)")
            print(
                "[ComposerLayout] mounted strategy=safeAreaInset focused=pending textEmpty=\(trimmedDraft.isEmpty) heightStable=true barHeight=\(Self.barHeight)"
            )
        }
        .onChange(of: focusPulse) { _, newPulse in
            secComposerTimingLog("focusPulseReceived", detail: "pulse=\(newPulse) generation=\(focusSessionGeneration)")
            print(
                "[ComposerLayout] mounted strategy=safeAreaInset focused=true textEmpty=\(trimmedDraft.isEmpty) heightStable=true barHeight=\(Self.barHeight)"
            )
        }
        .onChange(of: trimmedDraft.isEmpty) { _, isEmpty in
            print(
                "[ComposerLayout] mounted strategy=safeAreaInset focused=unchanged textEmpty=\(isEmpty) heightStable=true barHeight=\(Self.barHeight)"
            )
        }
        #endif
    }

    private func sendDraft() {
        let prompt = trimmedDraft
        guard !prompt.isEmpty else { return }

        services.chat.input = prompt
        draftText = ""
        services.chat.sendAsSecretary()
        onSendComplete()
    }
}

#if DEBUG
@inline(__always)
private func secSendBridgeLogUI(_ message: @autoclosure () -> String) {
    Swift.print("[SEC][SendBridge] \(message())")
}
#else
@inline(__always)
private func secSendBridgeLogUI(_ message: @autoclosure () -> String) {}
#endif

#if DEBUG
@inline(__always)
private func secTrustedLogUI(_ message: @autoclosure () -> String) {
    Swift.print("[SEC][Trusted] \(message())")
}
#else
@inline(__always)
private func secTrustedLogUI(_ message: @autoclosure () -> String) {}
#endif

struct SecretaryWorkspaceView: View {
    /// Top-level tabs kept in the view hierarchy once visited so local `@State` survives route switches.
    private struct SecretaryRetainedTopTab: OptionSet {
        let rawValue: UInt8
        static let dashboard = SecretaryRetainedTopTab(rawValue: 1 << 0)
        static let threads = SecretaryRetainedTopTab(rawValue: 1 << 1)
        static let inbound = SecretaryRetainedTopTab(rawValue: 1 << 2)
        static let trust = SecretaryRetainedTopTab(rawValue: 1 << 3)
        static let blocked = SecretaryRetainedTopTab(rawValue: 1 << 4)
        static let profile = SecretaryRetainedTopTab(rawValue: 1 << 5)
    }

    enum Route: Hashable {
        case dashboard
        case threads
        case inbound
        case trust
        case blocked
        case profile
        case thread(ExchangeThread.ID)
        case clarification(ExchangeThread.ID)
        case directMessage(
            counterpartyNodeID: String,
            displayName: String?,
            existingThreadID: ExchangeThread.ID?
        )
    }

    enum SheetRoute: Identifiable, Hashable {
        case approval(SecretaryApprovalPanelDisplay)
        case recovery(SecretaryRecoveryPanelDisplay)
        case compare(SecretaryComparePanelDisplay)
        /// “Looking for” guidance only; public seller surface is owned by Profile (`openProfileSurfaceSetup`).
        case needOffer
        case trustedPath(SecretaryTrustedPathPanelDisplay)
        case trustNodeCompose(
            displayName: String,
            nodeID: String,
            existingThreadID: ExchangeThread.ID?
        )
        case secretaryStyleSettings
        /// Same flow as `SecretaryTrustView` “+ Add Contact” (`SecretaryAddTrustedContactSheet`).
        case addTrustedContact

        var id: String {
            switch self {
            case .approval(let display):
                if let threadID = display.threadID, let approvalID = display.approvalID {
                    return "approval-\(threadID)-\(approvalID)"
                }
                if let threadID = display.threadID {
                    return "approval-\(threadID)"
                }
                return "approval-\(display.title)"

            case .recovery(let display):
                if let threadID = display.threadID {
                    return "recovery-\(threadID)"
                }
                return "recovery-\(display.title)"

            case .compare(let display):
                if let threadID = display.threadID {
                    return "compare-\(threadID)"
                }
                return "compare-\(display.title)"

            case .needOffer:
                return "need-offer-need"

            case .trustedPath(let display):
                if let threadID = display.threadID {
                    return "trusted-path-\(threadID)"
                }
                return "trusted-path-\(display.title)"

            case .trustNodeCompose(_, let nodeID, let existingThreadID):
                return "trust-compose-\(nodeID)-\(existingThreadID?.uuidString ?? "new")"

            case .secretaryStyleSettings:
                return "secretary-style-settings"

            case .addTrustedContact:
                return "add-trusted-contact"
            }
        }
    }

    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    let onReturnToCompanion: () -> Void

    @State private var route: Route
    @State private var previousTopLevelRoute: Route = .dashboard
    @State private var activeSheet: SheetRoute?
    @State private var recentlyTouchedThreadID: ExchangeThread.ID?
    @State private var chromeProjection = WorkspaceChromeProjection.empty
    @State private var appliedChromeSnapshotGeneration: UInt64 = 0
    @State private var chromeApplyTask: Task<Void, Never>?
    @State private var chromeRefreshTask: Task<Void, Never>?
    /// Serial “tail” refresh for inbound tab attention dot: coalesces bursts without canceling an in-flight `refreshWorkspaceChrome`.
    @State private var inboundBadgeChromeTailRequested = false
    @State private var inboundBadgeChromeChainTask: Task<Void, Never>?
    @State private var isIntentComposerPresented: Bool = false
    @State private var intentComposerDraft: String = ""
    @State private var intentComposerFocusPulse: Int = 0
    /// Cancellable handle for any pending focus pulse; ensures repeat Plus taps don't stack focus tasks.
    @State private var intentComposerFocusTask: Task<Void, Never>?
    /// Invalidates pending focus work on dismiss/reopen so stale tasks cannot apply older pulses.
    @State private var intentComposerPresentationGeneration: Int = 0
    @State private var latestScheduledIntentComposerFocusPulse: Int = 0

    @State private var showSecretaryNotificationCenter = false
    @State private var secretaryNotificationsList: [SecretaryNotification] = []
    @State private var secretaryNotificationUnreadBadge: Int = 0
    @State private var hasInboundMessagingUnreadAttention: Bool = false
    @State private var hasExchangeThreadUnreadAttention: Bool = false
    @State private var notificationCenterPayloadRefreshTask: Task<Void, Never>?
    /// Tabs that have entered the hierarchy at least once; stays a superset as the user explores.
    @State private var mountedTopTabs: SecretaryRetainedTopTab

    /// Social discovery search: profile inspection sheet (not exchange desk thread view).
    @State private var socialDiscoveryProfileItem: ExchangeModels.ForYouItem?
    @State private var socialDiscoveryConnectBusy = false
    @State private var socialDiscoveryPendingNodeIDs: Set<String> = []
    @State private var socialDiscoveryTrustedNodeIDs: Set<String> = []
    @State private var socialDiscoveryConnectError: String?
    @State private var socialDiscoveryImageGallery: SecretaryImageGalleryPresentation?

    /// After first appearance, union all main top tabs so hidden views mount once (avoids first-click jitter).
    @State private var hasWarmMountedTopTabs = false

    private func workspaceRenderTraceKey() -> String {
        let routeLabel: String = {
            switch route {
            case .dashboard: return "dashboard"
            case .threads: return "threads"
            case .inbound: return "inbound"
            case .trust: return "trust"
            case .blocked: return "blocked"
            case .profile: return "profile"
            case .thread(let id): return "thread:\(id.uuidString.prefix(8))"
            case .clarification(let id): return "clarification:\(id.uuidString.prefix(8))"
            case .directMessage(let nodeID, _, let threadID):
                return "direct:\(nodeID.prefix(8)):\(threadID?.uuidString.prefix(8) ?? "new")"
            }
        }()
        return
            "\(routeLabel)|refresh:\(services.secretaryRefreshID)|sheet:\(activeSheet != nil)|active:\(chromeProjection.activeCount)|pending:\(chromeProjection.pendingCount)|recent:\(recentlyTouchedThreadID?.uuidString.prefix(8) ?? "nil")"
    }

    private var routeDebugLabel: String {
        switch route {
        case .dashboard: return "dashboard"
        case .threads: return "threads"
        case .inbound: return "inbound"
        case .trust: return "trust"
        case .blocked: return "blocked"
        case .profile: return "profile"
        case .thread(let id): return "thread(\(id.uuidString.prefix(8)))"
        case .clarification(let id): return "clarification(\(id.uuidString.prefix(8)))"
        case .directMessage(let nodeID, _, let threadID):
            return "directMessage(node=\(nodeID.prefix(8)),thread=\(threadID?.uuidString.prefix(8) ?? "nil"))"
        }
    }

    init(
        initialRoute: Route = .dashboard,
        onReturnToCompanion: @escaping () -> Void
    ) {
        self.onReturnToCompanion = onReturnToCompanion
        _route = State(initialValue: initialRoute)
        _mountedTopTabs = State(initialValue: Self.initialMountedTopTabs(for: initialRoute))
    }

    private static func retainedTabMask(for route: Route) -> SecretaryRetainedTopTab {
        switch route {
        case .dashboard: return .dashboard
        case .threads: return .threads
        case .inbound: return .inbound
        case .trust: return .trust
        case .blocked: return .blocked
        case .profile: return .profile
        case .thread, .clarification, .directMessage:
            return SecretaryRetainedTopTab()
        }
    }

    /// Home is always retained so the composer route and desk state stay warm.
    private static func initialMountedTopTabs(for route: Route) -> SecretaryRetainedTopTab {
        var mask: SecretaryRetainedTopTab = .dashboard
        mask.formUnion(retainedTabMask(for: route))
        return mask
    }

    /// Stable `task(id:)` so foreground inbox polling is not tied to `route` / `secretaryRefreshID` identity churn.
    private static let foregroundInboxPollTaskStableID = "secretary.foregroundInboxPoll.v1"

    var body: some View {
        ZStack {
            UnifyIceShellBackground()

            VStack(spacing: 0) {
                header

                SecretaryWorkspaceRetainedTabHost(
                    route: $route,
                    mountedTopTabs: $mountedTopTabs,
                    previousTopLevelRoute: $previousTopLevelRoute,
                    activeSheet: $activeSheet,
                    recentlyTouchedThreadID: $recentlyTouchedThreadID,
                    secretaryRefreshID: services.secretaryRefreshID,
                    secretaryNotificationUnreadBadge: secretaryNotificationUnreadBadge,
                    isProfileTabActive: isSelectedTopLevelRoute(.profile),
                    callbacks: retainedTabHostCallbacks()
                )
                .environmentObject(services)
                .overlay {
                    if isIntentComposerPresented {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissIntentComposer(preserveDraft: true)
                            }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .onChange(of: route) { oldValue, newValue in
                    if case .profile = newValue {
                        services.setSecretaryProfileTabActive(true)
                    } else if !isThreadLikeRoute(newValue) {
                        services.setSecretaryProfileTabActive(false)
                    }
                    mountedTopTabs.formUnion(Self.retainedTabMask(for: newValue))
                    if isIntentComposerPresented, isThreadLikeRoute(newValue) {
                        dismissIntentComposer(preserveDraft: true)
                    }
                    if case .directMessage = oldValue {
                        requestInboundBadgeChromeRefresh(trigger: "routeLeftDirectMessage")
                    }
                    if case .thread = oldValue {
                        requestInboundBadgeChromeRefresh(trigger: "routeLeftThread")
                    }
                    // Inbound tab owns gated reload via `SecretaryInboundView` (snapshot + watermarks).
                    // Do not enqueue a desk-wide `manual` refresh on every tab switch.
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomArea
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isIntentComposerPresented {
                    intentComposerInsetContent
                }
            }
            .transaction { $0.animation = nil }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Exchange shell is dark-native; legacy light editors scope their own `.preferredColorScheme(.light)`.
        .preferredColorScheme(.dark)
        .tint(SecretaryTheme.darkOrange)
        .sheet(item: $activeSheet) { sheet in
            sheetView(for: sheet)
                .presentationDetents(sheetDetents(for: sheet))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .sheet(item: $socialDiscoveryProfileItem) { item in
            socialDiscoveryProfileSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .fullScreenCover(item: $socialDiscoveryImageGallery) { presentation in
            SecretaryImageGalleryViewer(presentation: presentation) {
                socialDiscoveryImageGallery = nil
            }
        }
        .sheet(isPresented: $showSecretaryNotificationCenter) {
            SecretaryNotificationCenterSheet(
                notifications: secretaryNotificationsList,
                onDismiss: {
                    scheduleWorkspaceChromeRefresh(delayNanoseconds: 0)
                },
                onSelect: { notification in
                    Task { await handleSecretaryNotificationSelection(notification) }
                },
                onMarkAllRead: {
                    await markAllSecretaryNotificationsReadViaCenter()
                }
            )
            .presentationDetents([.fraction(0.52), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
        .task {
            if case .profile = route {
                services.setSecretaryProfileTabActive(true)
            }
            services.secretaryDeskPreferredThreadID = recentlyTouchedThreadID
            await services.refreshSecretaryDeskSnapshotAwaiting(
                reason: "workspaceMount",
                preferredThreadID: recentlyTouchedThreadID
            )
            await refreshWorkspaceNotificationAttention()
        }
        .task {
            warmMountTopTabsIfNeeded()
        }
        .onChange(of: services.secretaryDeskSnapshot?.generation) { _, generation in
            scheduleApplyDeskChromeFromSnapshot(generation: generation)
        }
        .task(id: Self.foregroundInboxPollTaskStableID) {
            Swift.print(
                "[ForegroundInboxPoll][taskModifierEntered] route=\(routeDebugLabel) " +
                "appScenePhase=\(services.canonicalAppScenePhaseLogLabel()) " +
                "uiApplicationState=\(services.canonicalUIApplicationStateLogLabel())"
            )

            await runFederationPollingWhileSecretaryWorkspaceVisible()
        }
        .onChange(of: services.secretaryRefreshID) { _, _ in
            requestInboundBadgeChromeRefresh(trigger: "secretaryRefreshID")
            if showSecretaryNotificationCenter {
                scheduleNotificationCenterPayloadRefresh(trigger: "refreshID")
            }
        }
        .onChange(of: services.pendingExchangeThreadPushOpenRouteGeneration) { _, _ in
            Task { await consumePendingExchangeThreadPushOpenRouteIfNeeded() }
        }
        .onChange(of: recentlyTouchedThreadID) { _, newValue in
            services.secretaryDeskPreferredThreadID = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryWorkspaceShouldRefresh)) { notification in
            ingestSecretaryWorkspaceRefreshNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryNotificationsDidChange)) { _ in
            requestInboundBadgeChromeRefresh(trigger: "notificationsDidChange")
            if showSecretaryNotificationCenter {
                scheduleNotificationCenterPayloadRefresh(trigger: "notificationChanged")
            }
        }
        .onChange(of: showSecretaryNotificationCenter) { _, isVisible in
            if isVisible {
                scheduleNotificationCenterPayloadRefresh(
                    trigger: "sheetOpen",
                    delayNanoseconds: 0
                )
            } else {
                notificationCenterPayloadRefreshTask?.cancel()
                notificationCenterPayloadRefreshTask = nil
            }
        }
        .onDisappear {
            chromeApplyTask?.cancel()
            chromeApplyTask = nil
            chromeRefreshTask?.cancel()
            chromeRefreshTask = nil
            inboundBadgeChromeChainTask?.cancel()
            inboundBadgeChromeChainTask = nil
            inboundBadgeChromeTailRequested = false
            notificationCenterPayloadRefreshTask?.cancel()
            notificationCenterPayloadRefreshTask = nil
            intentComposerFocusTask?.cancel()
            intentComposerFocusTask = nil
        }
        .onAppear {
            if case .profile = route {
                services.setSecretaryProfileTabActive(true)
            }
        }
        .onChange(of: isSelectedTopLevelRoute(.profile)) { _, isActive in
            services.setSecretaryProfileTabActive(isActive)
        }
        .onDisappear {
            services.setSecretaryProfileTabActive(false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                if await services.automaticFederationSyncSkipReason(trigger: .appBecameActive) != nil {
                    return
                }
                _ = await services.syncFederationInboxNow(
                    requestDeskRefreshAfter: true,
                    recordAttentionDigests: true,
                    trigger: .appBecameActive
                )
            }
        }
#if DEBUG
.onAppear {
    Swift.print(
        "[ForegroundInboxPoll][workspaceAppearProbe] route=\(routeDebugLabel) scenePhase=\(foregroundInboxPollScenePhaseLabel(scenePhase))"
    )
    SecretaryRenderTrace.workspaceBodyIfChanged(workspaceRenderTraceKey())
}
.onChange(of: workspaceRenderTraceKey()) { _, newValue in
    SecretaryRenderTrace.workspaceBodyIfChanged(newValue)
}
#endif
    }

    /// Tabs that render their own title row (and Discovery, which inlines bell + companion) hide this chrome to avoid duplicate headers.
    private func shouldShowGlobalTopChrome(for route: Route) -> Bool {
        switch route {
        case .threads, .inbound, .profile, .dashboard, .directMessage, .thread:
            return false
        case .trust, .blocked, .clarification:
            return true
        }
    }

    private func retainedTabHostCallbacks() -> SecretaryWorkspaceRetainedTabHost.Callbacks {
        SecretaryWorkspaceRetainedTabHost.Callbacks(
            onOpenProfileSurfaceSetup: { openProfileSurfaceSetup() },
            onOpenThread: { threadID, origin in
                openThread(threadID, from: origin)
            },
            onOpenDiscoveryResults: { threadID in
                openDiscoveryResultsInThreadsTab(threadID: threadID)
            },
            onOpenDirectMessageFromInbound: { rowID, counterpartyNodeID, displayName, linkedThreadID, intent, source in
                openDirectMessageFromInbound(
                    rowID: rowID,
                    counterpartyNodeID: counterpartyNodeID,
                    displayName: displayName,
                    linkedThreadID: linkedThreadID,
                    intent: intent,
                    source: source
                )
            },
            onOpenDirectMessage: { source, counterpartyNodeID, displayName, existingThreadID, origin in
                openDirectMessage(
                    source: source,
                    counterpartyNodeID: counterpartyNodeID,
                    displayName: displayName,
                    existingThreadID: existingThreadID,
                    origin: origin
                )
            },
            onOpenAddTrustedContact: {
                activeSheet = .addTrustedContact
            },
            onAskSecretaryAboutTrustedNode: { displayName, nodeID in
                seedAskSecretaryForTrustedNode(displayName: displayName, nodeID: nodeID)
            },
            onOpenRecoveryPanel: { display in
                activeSheet = .recovery(display)
            },
            onOpenApprovalSheet: { display in
                activeSheet = .approval(display)
            },
            onOpenComparePanel: { display in
                presentCompareSheet(display)
            },
            onOpenClarification: { threadID in
                openClarification(threadID)
            },
            onSwitchTopLevelRoute: { newRoute in
                switchTopLevelRoute(to: newRoute)
            },
            onRefreshSearch: { threadID in
                recentlyTouchedThreadID = threadID
                Task {
                    _ = try? await services.exchangeFacade.refreshSearch(threadID: threadID)
                    NotificationCenter.default.post(
                        name: .secretaryWorkspaceShouldRefresh,
                        object: nil,
                        userInfo: ["threadID": threadID.uuidString]
                    )
                }
            },
            onOpenSecretaryNotifications: {
                Task { @MainActor in
                    await refreshSecretaryNotificationCenterPayload(trigger: "sheetOpen")
                    showSecretaryNotificationCenter = true
                }
            },
            onReturnToCompanion: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    onReturnToCompanion()
                }
            }
        )
    }

    @ViewBuilder
    private var header: some View {
        if shouldShowGlobalTopChrome(for: route) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    if case .thread = route {
                        backButton {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = previousTopLevelRoute
                            }
                        }
                    } else if case .clarification(let threadID) = route {
                        backButton {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = .thread(threadID)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headerTitle)
                            .font(
                                route == .dashboard
                                ? .system(size: 26, weight: .regular, design: .serif)
                                : .system(size: 18, weight: .semibold)
                            )
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        if let subtitle = headerSubtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }
                    }

                    Spacer(minLength: 10)

                    secretaryNotificationsBellButton

                    modeSwitchButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
            .padding(.bottom, 8)
        }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private struct WorkspaceChromeProjection: Equatable {
        let activeCount: Int
        let pendingCount: Int
        let trustedCount: Int
        let recoveryCount: Int

        static let empty = WorkspaceChromeProjection(
            activeCount: 0,
            pendingCount: 0,
            trustedCount: 0,
            recoveryCount: 0
        )
    }

    private func projectWorkspaceChrome(
        threads: [ExchangeModels.InboxItem],
        inbox: [ExchangeInboxItem],
        approvals: [ExchangeModels.PendingApproval]
    ) -> WorkspaceChromeProjection {
        let pendingApprovalThreadIDs = Set(approvals.map(\.threadID))

        let buckets = threads.map {
            SecretaryProjectionEngine.bucket(
                for: $0,
                pendingApprovalThreadIDs: pendingApprovalThreadIDs,
                preferredThreadID: recentlyTouchedThreadID
            )
        }

        let visibleInboxCount = inbox.filter {
            switch $0.processingState {
            case .received, .deferred, .awaitingOrderingGapResolution:
                return true
            case .duplicateIgnored, .reconciledIntoThread, .rejected, .archived:
                return false
            }
        }.count

        let activeThreadCount = buckets.filter { $0 == .active }.count
        let pendingThreadCount = buckets.filter { $0 == .pending }.count
        let trustedThreadCount = buckets.filter { $0 == .trusted }.count
        let recoveryThreadCount = buckets.filter { $0 == .recovery }.count

        return WorkspaceChromeProjection(
            activeCount: activeThreadCount + visibleInboxCount,
            pendingCount: pendingThreadCount,
            trustedCount: trustedThreadCount,
            recoveryCount: recoveryThreadCount
        )
    }

    /// Chat bubbles: tap returns to Companion / chat room. Action unchanged from prior mode control.
    private var modeSwitchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                onReturnToCompanion()
            }
        } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkSurface.opacity(0.92))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
                )
                .shadow(color: SecretaryTheme.darkShadow.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to Chat")
    }

    private enum IntentComposerFocusScheduleReason: String {
        case activate
        case reopen
        case seedTrustedNode
    }

    private func beginIntentComposerFocusSession() {
        intentComposerPresentationGeneration += 1
    }

    /// Debounced focus: composer mounts immediately; first-responder is requested once after layout settles.
    private func scheduleIntentComposerFocus(
        reason: IntentComposerFocusScheduleReason,
        delayNanoseconds: UInt64? = nil
    ) {
        if intentComposerFocusTask != nil {
            intentComposerFocusTask?.cancel()
            intentComposerFocusTask = nil
            #if DEBUG
            secComposerFocusLog("cancel reason=newPulse generation=\(intentComposerPresentationGeneration)")
            #endif
        }

        let delayNs = delayNanoseconds ?? {
            switch reason {
            case .activate:
                return 200_000_000
            case .reopen:
                return 150_000_000
            case .seedTrustedNode:
                return 220_000_000
            }
        }()

        let capturedGeneration = intentComposerPresentationGeneration
        let capturedPulse = intentComposerFocusPulse + 1
        latestScheduledIntentComposerFocusPulse = capturedPulse
        #if DEBUG
        secComposerFocusLog(
            "schedule reason=\(reason.rawValue) delayMs=\(delayNs / 1_000_000) pulse=\(capturedPulse) generation=\(capturedGeneration)"
        )
        secComposerTimingLog(
            "focusScheduled",
            detail: "reason=\(reason.rawValue) delayMs=\(delayNs / 1_000_000) pulse=\(capturedPulse) generation=\(capturedGeneration)"
        )
        #endif

        intentComposerFocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            if Task.isCancelled {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=cancelled pulse=\(capturedPulse) generation=\(capturedGeneration)"
                )
                #endif
                return
            }
            if !isIntentComposerPresented {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=dismiss pulse=\(capturedPulse) generation=\(capturedGeneration)"
                )
                #endif
                return
            }
            if capturedGeneration != intentComposerPresentationGeneration {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=staleGeneration pulse=\(capturedPulse) captured=\(capturedGeneration) current=\(intentComposerPresentationGeneration)"
                )
                #endif
                return
            }
            if capturedPulse != latestScheduledIntentComposerFocusPulse {
                #if DEBUG
                secComposerFocusLog(
                    "skip reason=stalePulse captured=\(capturedPulse) latest=\(latestScheduledIntentComposerFocusPulse)"
                )
                #endif
                return
            }
            intentComposerFocusPulse = capturedPulse
            #if DEBUG
            secComposerLog("focusPulse=\(intentComposerFocusPulse) (\(reason.rawValue))")
            secComposerTimingLog(
                "focusPulseAssigned",
                detail: "pulse=\(intentComposerFocusPulse) generation=\(intentComposerPresentationGeneration)"
            )
            #endif
        }
    }

    /// Single entry point for opening the Plus composer.
    /// - Mounts the composer (and therefore hides the bottom dock) before scheduling focus.
    /// - Cancels any previously-scheduled focus pulse so repeat Plus taps coalesce into one.
    /// - Defers focus until safeAreaInset layout and launch chrome settle (avoids keyboard mount churn).
    private func activateIntentComposer() {
        let wasPresented = isIntentComposerPresented

        #if DEBUG
        IntentComposerTiming.reset()
        secComposerTimingLog("plusTap", detail: wasPresented ? "reopen" : "activate")
        #endif

        if !wasPresented {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isIntentComposerPresented = true
            }
            #if DEBUG
            secComposerLog("presented (activate)")
            #endif
        }

        beginIntentComposerFocusSession()
        scheduleIntentComposerFocus(reason: wasPresented ? .reopen : .activate)
    }

    private func dismissIntentComposer(preserveDraft: Bool) {
        beginIntentComposerFocusSession()
        #if DEBUG
        if intentComposerFocusTask != nil {
            secComposerFocusLog("cancel reason=dismiss generation=\(intentComposerPresentationGeneration)")
        }
        #endif
        intentComposerFocusTask?.cancel()
        intentComposerFocusTask = nil
        intentComposerFocusPulse = 0
        latestScheduledIntentComposerFocusPulse = 0
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if !preserveDraft {
            intentComposerDraft = ""
        }
        #if DEBUG
        secComposerLog("dismiss preserveDraft=\(preserveDraft)")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isIntentComposerPresented = false
            }
        }
    }

    private var intentComposerInsetContent: some View {
        SecretaryDeskHomeComposer(
            draftText: $intentComposerDraft,
            isPresented: isIntentComposerPresented,
            focusPulse: intentComposerFocusPulse,
            focusSessionGeneration: intentComposerPresentationGeneration,
            latestScheduledFocusPulse: latestScheduledIntentComposerFocusPulse,
            onCancel: { dismissIntentComposer(preserveDraft: false) },
            onSendComplete: { dismissIntentComposer(preserveDraft: true) }
        )
        .environmentObject(services)
        .tint(SecretaryTheme.darkMutedText)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var bottomArea: some View {
        if case .directMessage = route {
            EmptyView()
        } else {
            bottomNavigation
                .opacity(isIntentComposerPresented ? 0 : 1)
                .allowsHitTesting(!isIntentComposerPresented)
                .accessibilityHidden(isIntentComposerPresented)
                .frame(height: isIntentComposerPresented ? 0 : nil, alignment: .bottom)
                .clipped()
                .animation(nil, value: isIntentComposerPresented)
        }
    }

    private var bottomNavigation: some View {
        HStack(alignment: .center, spacing: 14) {
            UnifyFloatingTabBar(
                horizontalPadding: 4,
                expandsToAvailableWidth: false,
                maxInnerWidth: 263,
                verticalPadding: 8
            ) {
                UnifyFloatingTabItem(
                    title: "Discovery",
                    systemImage: "sparkles",
                    isSelected: isSelectedTopLevelRoute(.dashboard),
                    onSelect: { switchTopLevelRoute(to: .dashboard) }
                )
                UnifyFloatingTabItem(
                    title: "Threads",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isSelected: isSelectedTopLevelRoute(.threads),
                    showsAttentionDot: hasExchangeThreadUnreadAttention,
                    onSelect: { switchTopLevelRoute(to: .threads) }
                )
                UnifyFloatingTabItem(
                    title: "Chat",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    isSelected: isSelectedTopLevelRoute(.inbound),
                    showsAttentionDot: hasInboundMessagingUnreadAttention,
                    onSelect: { switchTopLevelRoute(to: .inbound) }
                )
                UnifyFloatingTabItem(
                    title: "Profile",
                    systemImage: "person.crop.circle",
                    isSelected: isSelectedTopLevelRoute(.profile),
                    onSelect: { switchTopLevelRoute(to: .profile) }
                )
            }

            UnifyPlusIntentButton(diameter: 57, style: .detachedFAB) {
                activateIntentComposer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func sheetDetents(for sheet: SheetRoute) -> Set<PresentationDetent> {
        switch sheet {
        case .compare:
            return [.medium, .large]

        case .secretaryStyleSettings:
            // Match Profile subpanels (Offering / Help / Guardians): half-height first, user can drag to large.
            return [.medium, .large]

        case .approval,
             .recovery,
             .trustedPath,
             .needOffer,
             .addTrustedContact:
            return [.large]

        case .trustNodeCompose:
            return [.medium, .large]
        }
    }

    // MARK: - Trust Action

    @MainActor
    private func addCompareDisplayToTrusted(
        _ display: SecretaryComparePanelDisplay,
        chosenOption: SecretaryComparePanel.Option?
    ) async {
        guard let threadID = display.threadID else {
            activeSheet = nil
            return
        }

        do {
            let detail = try await services.exchangeFacade.getThread(threadID: threadID)

            guard let sourceNodeID = cleanedNodeID(await services.exchangeNodeID) else {
                activeSheet = nil
                openThread(threadID, from: previousTopLevelRoute)
                return
            }

            guard let targetNodeID = resolveTrustedTargetNodeID(
                from: detail,
                chosenOption: chosenOption
            ) else {
                activeSheet = nil
                openThread(threadID, from: previousTopLevelRoute)
                return
            }

            _ = try await services.exchangeFacade.addOrUpdateTrustedNode(
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                relationshipType: .preferredNode,
                trustLevel: .standard,
                scopes: [.generalCommunication, .sourcing],
                propagation: .privateOnly,
                sourceKind: .manual,
                note: "Added from compare paths.",
                now: Date()
            )

            recentlyTouchedThreadID = threadID
            activeSheet = nil

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": threadID.uuidString]
            )

            switchTopLevelRoute(to: .trust)
        } catch {
            activeSheet = nil
            openThread(threadID, from: previousTopLevelRoute)
        }
    }

    private func resolveTrustedTargetNodeID(
        from detail: ExchangeModels.ThreadDetail,
        chosenOption: SecretaryComparePanel.Option?
    ) -> String? {
        let chosenCounterpartyID = cleanedNodeID(chosenOption?.candidateCounterpartyID)

        let chosenCounterparty = chosenCounterpartyID.flatMap { id in
            detail.counterparties.first(where: { $0.id == id })
        }

        if let nodeID = cleanedNodeID(chosenCounterparty?.identity?.nodeID) {
            return nodeID
        }

        if let nodeID = cleanedNodeID(detail.selectedCounterparty?.identity?.nodeID) {
            return nodeID
        }

        if let chosenCounterpartyID,
           let match = detail.matches.first(where: { $0.counterpartyID == chosenCounterpartyID }),
           let nodeID = trustedNodeID(from: match) {
            return nodeID
        }

        if let selectedCounterpartyID = cleanedNodeID(detail.thread.selectedCounterpartyID),
           let match = detail.matches.first(where: { $0.counterpartyID == selectedCounterpartyID }),
           let nodeID = trustedNodeID(from: match) {
            return nodeID
        }

        if let match = detail.selectedMatch,
           let nodeID = trustedNodeID(from: match) {
            return nodeID
        }

        if let chosenCounterpartyID,
           looksLikeExchangeNodeID(chosenCounterpartyID) {
            return chosenCounterpartyID
        }

        if let selectedID = cleanedNodeID(detail.thread.selectedCounterpartyID),
           looksLikeExchangeNodeID(selectedID) {
            return selectedID
        }

        if let selectedCounterpartyID = cleanedNodeID(detail.selectedCounterparty?.id),
           looksLikeExchangeNodeID(selectedCounterpartyID) {
            return selectedCounterpartyID
        }

        return nil
    }
    
    private func trustedNodeID(from match: ExchangeMatch) -> String? {
        let keys = [
            "nodeID",
            "node_id",
            "target_node_id",
            "counterparty_node_id",
            "public_profile_node_id",
            "publicProfileNodeID",
            "profile_node_id",
            "owner_node_id",
            "ownerNodeID"
        ]

        for key in keys {
            if let value = cleanedNodeID(match.metadata[key]) {
                return value
            }
        }

        if let candidate = cleanedNodeID(match.counterpartyID),
           looksLikeExchangeNodeID(candidate) {
            return candidate
        }

        return nil
    }

    private func cleanedNodeID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeExchangeNodeID(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("node-") ||
        lowered.hasPrefix("node.") ||
        lowered.contains("node-") ||
        lowered.contains("node.")
    }

    // MARK: - Approval Actions

    @MainActor
    private func approveFromDisplay(_ display: SecretaryApprovalPanelDisplay) async {
        guard let threadID = display.threadID else {
            activeSheet = nil
            return
        }

        do {
            if display.prefersSecondHalfPreparedSend, display.approvalID == nil {
                secSendBridgeLogUI(
                    "user directed send | thread=\(threadID.uuidString) | path=secondHalfPrepared | approvalID=nil"
                )
            }

            let ok = try await SecretaryOutboundApproveSend.perform(
                display: display,
                exchangeFacade: services.exchangeFacade,
                permit: .userApproved(source: "SecretaryWorkspaceView.approveFromDisplay")
            )

            if display.prefersSecondHalfPreparedSend, display.approvalID == nil {
                secSendBridgeLogUI(
                    "user directed send | thread=\(threadID.uuidString) | outcome=\(ok ? "queued" : "notQueued")"
                )
            }

            guard ok else {
                #if DEBUG
                Swift.print(
                    "[SecretaryWorkspaceView] approveFromDisplay failed ok=false thread=\(threadID.uuidString) " +
                        "displayApprovalID=\(display.approvalID?.uuidString ?? "nil") prefersPreparedSend=\(display.prefersSecondHalfPreparedSend) " +
                        "requiresHumanApproval=\(display.requiresHumanApproval) canRunPrimary=\(display.canRunPrimaryAction) " +
                        "primaryTitle=\(display.primaryTitle)"
                )
                #endif
                return
            }

            recentlyTouchedThreadID = threadID
            activeSheet = nil

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": threadID.uuidString]
            )

            Task {
                await services.exchangeSyncEngine.runPass(
                    trigger: .afterApprovalGranted,
                    now: Date()
                )
            }
        } catch {
            #if DEBUG
            Swift.print(
                "[SecretaryWorkspaceView] approveFromDisplay threw thread=\(threadID.uuidString) error=\(error)"
            )
            #endif
        }
    }

    @MainActor
    private func rejectFromDisplay(_ display: SecretaryApprovalPanelDisplay) async {
        guard let threadID = display.threadID else {
            activeSheet = nil
            return
        }

        do {
            let approvalID: ExchangeApproval.ID?

            if let existing = display.approvalID {
                approvalID = existing
            } else {
                let detail = try await services.exchangeFacade.getThread(threadID: threadID)
                approvalID = SecretaryProjectionEngine.latestPendingApproval(for: detail)?.id
            }

            guard let approvalID else {
                #if DEBUG
                Swift.print(
                    "[SecretaryWorkspaceView] rejectFromDisplay no approvalID thread=\(threadID.uuidString) " +
                        "displayApprovalID=\(display.approvalID?.uuidString ?? "nil") canRunReject=\(display.canRunRejectAction)"
                )
                #endif
                return
            }

            _ = try await services.exchangeFacade.reject(
                threadID: threadID,
                approvalID: approvalID
            )

            recentlyTouchedThreadID = threadID
            activeSheet = nil

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: ["threadID": threadID.uuidString]
            )
        } catch {
            #if DEBUG
            Swift.print(
                "[SecretaryWorkspaceView] rejectFromDisplay threw thread=\(threadID.uuidString) error=\(error)"
            )
            #endif
        }
    }

    // MARK: - Sheets

    /// Multi-candidate discovery review lives on Threads → Recent; single-path decision review may still use the compare sheet.
    @MainActor
    private func openDiscoveryResultsInThreadsTab(threadID: ExchangeThread.ID) {
        recentlyTouchedThreadID = threadID
        switchTopLevelRoute(to: .threads)
    }

    @MainActor
    private func openHydratedCompare(threadID: ExchangeThread.ID?) {
        guard let threadID else { return }

        Task { @MainActor in
            do {
                let detail = try await services.exchangeFacade.getThread(threadID: threadID)
                let compareThreadID = detail.compareWorkbenchThreadID
                let compareDetail: ExchangeModels.ThreadDetail
                if compareThreadID == threadID {
                    compareDetail = detail
                } else {
                    compareDetail = try await services.exchangeFacade.getThread(threadID: compareThreadID)
                }

                let display = SecretaryProjectionEngine.compareDisplay(for: compareDetail)
                if display.options.count > 1 {
                    openDiscoveryResultsInThreadsTab(threadID: compareThreadID)
                } else if display.hasOpportunityReviewDepth {
                    activeSheet = .compare(display)
                } else {
                    await routeThreadOrSocialProfile(threadID: compareThreadID, from: previousTopLevelRoute)
                }
            } catch {
                openThreadDirectly(threadID, from: previousTopLevelRoute)
            }
        }
    }

    @MainActor
    private func presentCompareSheet(_ display: SecretaryComparePanelDisplay) {
        if display.options.count > 1 {
            if let threadID = display.threadID {
                openDiscoveryResultsInThreadsTab(threadID: threadID)
            }
            return
        }
        activeSheet = .compare(display)
    }
    @ViewBuilder
    private func sheetView(for sheet: SheetRoute) -> some View {
        switch sheet {
        case .approval(let display):
            SecretaryApprovalSheet(
                display: display,
                onApprove: {
                    await approveFromDisplay(display)
                },
                onReject: {
                    await rejectFromDisplay(display)
                },
                onOpenThread: { threadID in
                    closeSheetAndOpenThread(threadID)
                }
            )
            .onAppear {
                markSecretaryAttentionReadAfterOpeningApproval(display)
            }

        case .recovery(let display):
            SecretaryRecoveryPanel(
                display: display,
                onPrimaryAction: {
                    closeSheetAndOpenThread(display.threadID)
                },
                onSecondaryAction: {
                    activeSheet = nil
                },
                onOpenThread: { threadID in
                    closeSheetAndOpenThread(threadID)
                }
            )
            .onAppear {
                markSecretaryAttentionReadAfterOpeningRecovery(display)
            }

        case .compare(let display):
            SecretaryComparePanel(
                display: display,
                onChooseOption: { option in
                    await addCompareDisplayToTrusted(
                        display,
                        chosenOption: option
                    )
                },
                onSecondaryAction: {
                    activeSheet = nil
                },
                onOpenThread: { threadID in
                    closeSheetAndOpenThread(threadID)
                }
            )

        case .needOffer:
            SecretaryNeedOfferPanel(
                mode: .need,
                title: "Needs",
                summary: "Use the secretary to turn a need into search, matching, and bounded outreach.",
                examples: [
                    "Find a supplier through open and trusted paths.",
                    "Ask for a direct introduction through a friend.",
                    "Prepare an outreach draft before anything is sent."
                ],
                sellerWorkspace: nil,
                sellerValidationIssues: [],
                onPrimaryAction: {
                    activeSheet = nil
                },
                onSecondaryAction: {
                    activeSheet = nil
                    switchTopLevelRoute(to: .trust)
                },
                onCreateProfile: nil,
                onAddOffer: nil,
                onPublishSurface: nil
            )

        case .trustedPath(let display):
            SecretaryTrustedPathPanel(
                display: display,
                onPrimaryAction: {
                    if display.trustComposerFallback {
                        activeSheet = nil
                        seedAskSecretaryForTrustedNode(
                            displayName: display.trustedNodeDisplayName ?? display.title,
                            nodeID: display.trustedNodeID ?? ""
                        )
                        return
                    }
                    guard let threadID = display.threadID else {
                        activeSheet = nil
                        return
                    }
                    if display.sendPreparedDraftAvailable {
                        secTrustedLogUI(
                            "send action tapped | thread=\(threadID.uuidString) | path=preparedDraft"
                        )
                        Task { @MainActor in
                            do {
                                let outcome = try await services.exchangeFacade
                                    .queuePreparedSecondHalfOutboundSend(
                                        threadID: threadID,
                                        draftID: nil,
                                        userInitiatedOverride: true,
                                        now: Date()
                                    )
                                secTrustedLogUI(
                                    "send action result | thread=\(threadID.uuidString) | outcome=\(outcome.rawValue)"
                                )
                                recentlyTouchedThreadID = threadID
                                activeSheet = nil
                                NotificationCenter.default.post(
                                    name: .secretaryWorkspaceShouldRefresh,
                                    object: nil,
                                    userInfo: ["threadID": threadID.uuidString]
                                )
                                Task {
                                    await services.exchangeSyncEngine.runPass(
                                        trigger: .afterApprovalGranted,
                                        now: Date()
                                    )
                                }
                            } catch {
                                secTrustedLogUI(
                                    "send action failed | thread=\(threadID.uuidString) | error=\(error)"
                                )
                                closeSheetAndOpenThread(threadID)
                            }
                        }
                    } else {
                        closeSheetAndOpenThread(display.threadID)
                    }
                },
                onSecondaryAction: {
                    if display.trustComposerFallback {
                        activeSheet = .trustNodeCompose(
                            displayName: display.trustedNodeDisplayName ?? display.title,
                            nodeID: display.trustedNodeID ?? "",
                            existingThreadID: display.threadID
                        )
                        return
                    }
                    if display.sendPreparedDraftAvailable, let threadID = display.threadID {
                        closeSheetAndOpenThread(threadID)
                    } else {
                        activeSheet = nil
                    }
                }
            )
            .onAppear {
                markSecretaryAttentionReadAfterOpeningTrustedContact(display.trustedNodeID)
            }

        case .trustNodeCompose(let displayName, let nodeID, let existingThreadID):
            SecretaryDirectMessageComposeSheet(
                displayName: displayName,
                nodeID: nodeID,
                onSend: { messageBody in
                    try await services.exchangeFacade.sendManualMessageToTrustedNode(
                        trustedNodeID: nodeID,
                        existingThreadID: existingThreadID,
                        subject: nil,
                        body: messageBody,
                        now: Date()
                    )
                },
                onSuccess: { threadID in
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    activeSheet = nil
                    openThread(threadID, from: .trust)
                    recentlyTouchedThreadID = threadID
                    NotificationCenter.default.post(
                        name: .secretaryWorkspaceShouldRefresh,
                        object: nil,
                        userInfo: ["threadID": threadID.uuidString]
                    )
                    Task {
                        await services.exchangeSyncEngine.runPass(
                            trigger: .afterApprovalGranted,
                            now: Date()
                        )
                    }
                },
                onCancel: {
                    activeSheet = nil
                }
            )
            .onAppear {
                markSecretaryAttentionReadAfterOpeningTrustedContact(nodeID)
            }

        case .secretaryStyleSettings:
            SecretaryStyleSettingsView(
                onClose: {
                    activeSheet = nil
                }
            )
            .environmentObject(services)

        case .addTrustedContact:
            SecretaryAddTrustedContactSheet { nodeID, displayName, action in
                if action == .addedLocal, let nodeID, !nodeID.isEmpty {
                    openDirectMessage(
                        source: "inbound",
                        counterpartyNodeID: nodeID,
                        displayName: displayName,
                        existingThreadID: nil,
                        origin: .inbound
                    )
                }
            }
            .environmentObject(services)
        }
    }

    private func closeSheetAndOpenThread(_ threadID: ExchangeThread.ID?) {
        activeSheet = nil

        if let threadID {
            openThread(threadID, from: previousTopLevelRoute)
        }
    }

    // MARK: - Prompt

    private func seedAskSecretaryForTrustedNode(displayName: String, nodeID: String) {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleanName.isEmpty ? cleanID : cleanName

        intentComposerDraft = "About my trusted contact \(label) (\(cleanID)): "
        switchTopLevelRoute(to: .dashboard)

        let alreadyShown = isIntentComposerPresented
        #if DEBUG
        IntentComposerTiming.reset()
        secComposerTimingLog("seedTrustedNode", detail: alreadyShown ? "reopen" : "activate")
        #endif
        if !alreadyShown {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isIntentComposerPresented = true
            }
            #if DEBUG
            secComposerLog("presented (seedTrustedNode)")
            #endif
        }

        beginIntentComposerFocusSession()
        scheduleIntentComposerFocus(
            reason: .seedTrustedNode,
            delayNanoseconds: alreadyShown ? 150_000_000 : 220_000_000
        )
    }

    // MARK: - Routing

    /// Pre-mounts all main Secretary top tabs once after the workspace appears so first tab taps do not cold-mount.
    @MainActor
    private func warmMountTopTabsIfNeeded() {
        guard !hasWarmMountedTopTabs else { return }
        hasWarmMountedTopTabs = true

        let secondaryTabs =
            SecretaryRetainedTopTab.threads
                .union(.inbound)
                .union(.trust)
                .union(.blocked)
                .union(.profile)

        #if DEBUG
        let before = mountedTopTabs.rawValue
        #endif

        // Keep dashboard paint un-contended: defer mounting hidden inbox/threads/trust stacks so they
        // do not `.task`/list on the same frame as `SecretaryDashboardView` hydration.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 480_000_000)

            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mountedTopTabs.formUnion(secondaryTabs)
            }

            #if DEBUG
            Swift.print(
                "[SecretaryWorkspaceView] warmMountTopTabs deferred rawValue before=\(before) after=\(mountedTopTabs.rawValue)"
            )
            #endif
        }
    }

    private func switchTopLevelRoute(to newRoute: Route) {
        guard !isThreadLikeRoute(newRoute) else {
            route = newRoute
            return
        }

        previousTopLevelRoute = newRoute
        route = newRoute
        mountedTopTabs.formUnion(Self.retainedTabMask(for: newRoute))
    }

    /// Canonical destination for normal public-surface setup (Profile tab).
    private func openProfileSurfaceSetup() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switchTopLevelRoute(to: .profile)
        }
    }

    private func openThread(_ threadID: ExchangeThread.ID, from origin: Route) {
        Task { @MainActor in
            await routeThreadOrSocialProfile(threadID: threadID, from: origin)
        }
    }

    @MainActor
    private func routeThreadOrSocialProfile(threadID: ExchangeThread.ID, from origin: Route) async {
        recentlyTouchedThreadID = threadID
        previousTopLevelRoute = normalizedTopLevelRoute(from: origin)

        do {
            let detail = try await services.exchangeFacade.getThread(threadID: threadID)
            if detail.thread.threadRole != .candidateCoordination,
               SocialDiscoveryOpenRouting.shouldPresentProfileDetail(for: detail.thread) {
                await presentSocialDiscoveryProfile(detail: detail)
                return
            }
        } catch {
            #if DEBUG
            Swift.print("[SocialDiscoveryRoute] thread lookup failed id=\(threadID.uuidString) error=\(error)")
            #endif
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            route = .thread(threadID)
        }
    }

    @MainActor
    private func presentSocialDiscoveryProfile(detail: ExchangeModels.ThreadDetail) async {
        let item = SocialDiscoveryProfileAdapter.forYouItem(from: detail)
        await refreshSocialDiscoveryProfileRelationshipState(for: item)
        socialDiscoveryProfileItem = item
    }

    @MainActor
    private func refreshSocialDiscoveryProfileRelationshipState(
        for item: ExchangeModels.ForYouItem
    ) async {
        guard let source = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return
        }

        if let trustedRows = try? await services.exchangeFacade.listTrustedNodes(
            sourceNodeID: source,
            limit: 500
        ) {
            socialDiscoveryTrustedNodeIDs = Set(
                trustedRows
                    .map { $0.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        if let pendingRows = try? await services.exchangeFacade.listPendingOutgoingContactRequests(limit: 500) {
            let targetNode = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPending = pendingRows.contains {
                $0.targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines) == targetNode
            }
            if hasPending, !targetNode.isEmpty {
                socialDiscoveryPendingNodeIDs.insert(targetNode)
            }
        }
    }

    @ViewBuilder
    private func socialDiscoveryProfileSheet(item: ExchangeModels.ForYouItem) -> some View {
        let imageURLs = socialDiscoveryImageURLs(for: item)
        let subtitle = socialDiscoveryCollapsedSubtitle(for: item)
        let detailSections = SocialDiscoveryProfileProjection.canonicalSocialDetailsSections(for: item)
        let useGroupedSections = !detailSections.isEmpty
        let detailLines = useGroupedSections
            ? []
            : socialDiscoveryExpandedDetailLines(item: item, collapsedSubtitle: subtitle)
        let nodeID = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPending = !nodeID.isEmpty && socialDiscoveryPendingNodeIDs.contains(nodeID)
        let isTrusted = socialDiscoveryIsTrusted(item)

        PublicProfileDetailSheet(
            item: item,
            imageURLs: imageURLs,
            subtitle: subtitle,
            detailLines: detailLines,
            detailSections: useGroupedSections ? detailSections : nil,
            onClose: {
                socialDiscoveryProfileItem = nil
            },
            onOpenGallery: { presentation in
                socialDiscoveryImageGallery = presentation
            },
            toolbarTrailing: {
                socialDiscoveryProfileToolbar(
                    item: item,
                    isPending: isPending,
                    isTrusted: isTrusted
                )
            }
        )
        .task(id: item.id) {
            await refreshSocialDiscoveryProfileRelationshipState(for: item)
        }
    }

    @ViewBuilder
    private func socialDiscoveryProfileToolbar(
        item: ExchangeModels.ForYouItem,
        isPending: Bool,
        isTrusted: Bool
    ) -> some View {
        if isTrusted {
            Button {
                socialDiscoveryProfileItem = nil
                openDirectMessage(
                    source: "social_discovery_profile",
                    counterpartyNodeID: item.nodeID,
                    displayName: item.displayName,
                    existingThreadID: nil,
                    origin: previousTopLevelRoute
                )
            } label: {
                Text("Message")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SecretaryTheme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.94))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open direct message with this profile")
        } else if isPending {
            Text("Pending")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .accessibilityAddTraits(.isStaticText)
        } else {
            Button {
                Task { @MainActor in
                    await sendSocialDiscoveryConnectRequest(for: item)
                }
            } label: {
                Group {
                    if socialDiscoveryConnectBusy {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                    } else {
                        Text("Connect")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(
                    socialDiscoveryConnectBusy
                        ? SecretaryTheme.darkMutedText
                        : SecretaryTheme.darkOrange
                )
            }
            .buttonStyle(.plain)
            .disabled(socialDiscoveryConnectBusy)
            .accessibilityLabel("Send contact request to this profile")
        }
    }

    @MainActor
    private func sendSocialDiscoveryConnectRequest(for item: ExchangeModels.ForYouItem) async {
        guard !socialDiscoveryConnectBusy else { return }
        socialDiscoveryConnectError = nil

        guard let sourceNodeID = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceNodeID.isEmpty else {
            socialDiscoveryConnectError = "Your local node is not ready yet."
            return
        }

        let targetNodeID = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetNodeID.isEmpty else {
            socialDiscoveryConnectError = "This profile is missing a node id."
            return
        }

        let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        socialDiscoveryConnectBusy = true
        defer { socialDiscoveryConnectBusy = false }

        do {
            _ = try await services.exchangeFacade.sendContactRequestToNode(
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                displayNameOverride: displayName.isEmpty ? nil : displayName,
                note: nil
            )
            socialDiscoveryPendingNodeIDs.insert(targetNodeID)
            socialDiscoveryConnectError = nil
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: nil
            )
        } catch {
            socialDiscoveryConnectError = ExchangeUserFacingCopySanitizer.userFacingLoadFailure(
                for: error,
                debugLabel: "SocialDiscoveryConnectSend"
            )
        }
    }

    private func socialDiscoveryIsTrusted(_ item: ExchangeModels.ForYouItem) -> Bool {
        let node = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !node.isEmpty, socialDiscoveryTrustedNodeIDs.contains(node) { return true }
        if !itemID.isEmpty, socialDiscoveryTrustedNodeIDs.contains(itemID) { return true }
        return false
    }

    private func socialDiscoveryImageURLs(for item: ExchangeModels.ForYouItem) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func append(_ raw: String?) {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            let key = raw.lowercased()
            guard seen.insert(key).inserted else { return }
            ordered.append(raw)
        }
        append(item.primaryImageURL)
        for url in item.surfacedOfferImageURLs {
            append(url)
        }
        return ordered
    }

    private func socialDiscoveryCollapsedSubtitle(for item: ExchangeModels.ForYouItem) -> String? {
        if let match = item.matchReasonSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !match.isEmpty {
            return match
        }
        if let headline = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !headline.isEmpty {
            return headline
        }
        return item.discoveryFactLines.first
    }

    private func socialDiscoveryExpandedDetailLines(
        item: ExchangeModels.ForYouItem,
        collapsedSubtitle: String?
    ) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: item.discoveryFactLines)
        lines.append(contentsOf: item.publicFactLines)
        if !item.dominantTags.isEmpty {
            lines.append("Shared themes: \(item.dominantTags.prefix(6).joined(separator: ", "))")
        }

        var seen = Set<String>()
        var output: [String] = []
        let collapsed = collapsedSubtitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let collapsed, trimmed.lowercased() == collapsed { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
            if output.count >= 12 { break }
        }
        return ExchangeProviderDetailsLegacyLineGate.filterDetailsFallbackLines(
            output,
            source: "socialDiscoveryLegacy"
        )
    }

    private func openThreadDirectly(_ threadID: ExchangeThread.ID, from origin: Route) {
        recentlyTouchedThreadID = threadID
        previousTopLevelRoute = normalizedTopLevelRoute(from: origin)

        withAnimation(.easeInOut(duration: 0.18)) {
            route = .thread(threadID)
        }
    }

    private func openDirectMessage(
        source: String,
        counterpartyNodeID: String,
        displayName: String?,
        existingThreadID: ExchangeThread.ID?,
        origin: Route
    ) {
        let trimmed = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        previousTopLevelRoute = normalizedTopLevelRoute(from: origin)
        #if DEBUG
        print(
            "[DirectMessageRoute] source=\(source) counterpartyNodeID=\(trimmed.isEmpty ? "nil" : trimmed) linkedThreadID=\(existingThreadID?.uuidString ?? "nil") existingThreadIDPassed=\(existingThreadID?.uuidString ?? "nil")"
        )
        #endif
        withAnimation(.easeInOut(duration: 0.18)) {
            route = .directMessage(
                counterpartyNodeID: trimmed,
                displayName: displayName,
                existingThreadID: existingThreadID
            )
        }
    }

    private func isDirectMessageThread(_ threadID: ExchangeThread.ID) async -> Bool {
        guard let thread = try? await services.exchangeFacade.loadThreadRow(threadID: threadID) else {
            return false
        }
        return thread.metadata["direct_message_thread"] == "true"
    }

    /// Resolves the DM / messaging-attention thread to open from Inbound (row-linked thread may be a non-DM
    /// conversation while unread `.newReply` rows point at the DM thread for the same counterparty).
    private func resolveInboundOpenDMThreadIDForCounterparty(
        rowLinkedThreadID: ExchangeThread.ID?,
        counterpartyNodeID: String?,
        intent: ExchangeInboundConversationOpenIntent
    ) async -> (resolved: ExchangeThread.ID?, reason: String) {
        let trimmedNode = counterpartyNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedNode.isEmpty else {
            if let rowLinkedThreadID {
                if intent == .directMessage {
                    if await isDirectMessageThread(rowLinkedThreadID) {
                        return (rowLinkedThreadID, "fallback_linked_dm_thread_no_counterparty_node")
                    }
                    return (nil, "no_dm_linked_thread_no_counterparty_node")
                }
                return (rowLinkedThreadID, "fallback_linked_thread_no_counterparty_node")
            }
            return (nil, "no_thread_no_counterparty_node")
        }
        let loweredCounterparty = trimmedNode.lowercased()

        if let rows = try? await services.exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 500
            )
        ) {
            for n in rows {
                let trustedTrim = n.trustedNodeID?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let matchesTrusted =
                    !trustedTrim.isEmpty && trustedTrim.lowercased() == loweredCounterparty

                var matchesViaThreadCounterparty = false
                if let tid = n.threadID,
                   let thread = try? await services.exchangeFacade.loadThreadRow(threadID: tid) {
                    let sel = thread.selectedCounterpartyID?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !sel.isEmpty, sel.lowercased() == loweredCounterparty {
                        matchesViaThreadCounterparty = true
                    }
                }

                guard matchesTrusted || matchesViaThreadCounterparty else { continue }

                if let tid = n.threadID {
                    return (tid, "unread_messaging_attention")
                }
            }
        }

        if let dm = try? await services.exchangeFacade.resolveExistingDirectMessageThreadIDIfPresent(
            counterpartyNodeID: trimmedNode
        ) {
            return (dm, "existing_dm_metadata")
        }

        if let rowLinkedThreadID {
            if intent == .directMessage {
                if await isDirectMessageThread(rowLinkedThreadID) {
                    return (rowLinkedThreadID, "fallback_linked_dm_thread")
                }
                return (nil, "no_dm_linked_thread")
            }
            return (rowLinkedThreadID, "fallback_linked_thread")
        }
        return (nil, "no_resolved_thread")
    }

    /// Marks every unread inbound messaging-surface notification that belongs to this counterparty open
    /// (trusted node match, thread id hints from resolve/row link, or thread.selectedCounterpartyID match).
    private func markUnreadInboundMessagingAttentionMatchingCounterpartyOpen(
        counterpartyNodeID: String?,
        resolvedThreadID: ExchangeThread.ID?,
        rowLinkedThreadID: ExchangeThread.ID?
    ) async {
        let trimmed = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        let lowered = trimmed.lowercased()

        var threadHints = Set<ExchangeThread.ID>()
        if let r = resolvedThreadID { threadHints.insert(r) }
        if let l = rowLinkedThreadID { threadHints.insert(l) }

        guard let rows = try? await services.exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 500
            )
        ) else { return }

        var matched = Set<SecretaryNotification.ID>()
        for n in rows {
            guard SecretaryNotificationKind.inboundMessagingUnreadSurface.contains(n.kind), !n.isRead else { continue }

            let trusted = n.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trusted.isEmpty, trusted.lowercased() == lowered {
                matched.insert(n.id)
                continue
            }

            if let tid = n.threadID {
                if threadHints.contains(tid) {
                    matched.insert(n.id)
                    continue
                }
                if let thread = try? await services.exchangeFacade.loadThreadRow(threadID: tid) {
                    let sel = thread.selectedCounterpartyID?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !sel.isEmpty, sel.lowercased() == lowered {
                        matched.insert(n.id)
                    }
                }
            }
        }

        guard !matched.isEmpty else { return }

        do {
            try await services.exchangeFacade.markSecretaryNotificationsRead(ids: matched)
            #if DEBUG
            let afterRows = try? await services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                    excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )
            let afterKeys = (afterRows ?? []).filter { !$0.isRead }.map(\.inboundMessagingAttentionKey).sorted()
            print(
                "[InboundBadgeClearResult] cleared=\(matched.count) afterKeys=\(afterKeys.joined(separator: ",")) source=inboundCounterpartyOpen"
            )
            #endif
        } catch {
            #if DEBUG
            print("[InboundOpenCounterpartyMessagingClear] failed error=\(error.localizedDescription)")
            #endif
        }
    }

    private enum InboundConversationOpenKind: Sendable {
        case exchangeThread(ExchangeThread.ID)
        case directMessage(ExchangeThread.ID)
        case createDirectMessage(counterpartyNodeID: String)
        case unavailable
    }

    private struct InboundConversationOpenTarget: Sendable {
        var kind: InboundConversationOpenKind
        var reason: String
    }

    private func resolveInboundConversationOpenTarget(
        rowLinkedThreadID: ExchangeThread.ID?,
        resolvedThreadID: ExchangeThread.ID?,
        counterpartyNodeID: String?,
        intent: ExchangeInboundConversationOpenIntent,
        source: ExchangeInboundOpenSource
    ) async -> InboundConversationOpenTarget {
        let candidates = ExchangeInboundDirectMessageOpenResolver.routingCandidateThreadIDs(
            intent: intent,
            rowLinkedThreadID: rowLinkedThreadID,
            resolvedThreadID: resolvedThreadID
        )

        #if DEBUG
        if ExchangeInboundDirectMessageOpenResolver.shouldSkipLinkedExchangeHydration(
            intent: intent,
            rowLinkedThreadID: rowLinkedThreadID,
            resolvedThreadID: resolvedThreadID
        ) {
            print(
                "[DMOpenRootFix] skippedLinkedExchangeHydration " +
                "linked=\(rowLinkedThreadID?.uuidString ?? "nil") " +
                "resolved=\(resolvedThreadID?.uuidString ?? "nil")"
            )
        }
        #endif

        var dmCandidate: ExchangeThread.ID?

        for threadID in candidates {
            guard let thread = try? await services.exchangeFacade.loadThreadRow(threadID: threadID) else {
                continue
            }
            let metadata = thread.metadata
            let decision = ExchangeInboundOpenRouting.routeDecision(
                threadMetadata: metadata,
                intent: intent
            )
            #if DEBUG
            let linkedShort = rowLinkedThreadID.map { String($0.uuidString.prefix(8)) } ?? "nil"
            let candidateShort = String(threadID.uuidString.prefix(8))
            print(
                "[InboundOpenRoute] source=\(source.rawValue) intent=\(intent.rawValue) " +
                "candidateRoute=\(decision.route.rawValue) reason=\(decision.reason) " +
                "linkedThreadID=\(linkedShort) candidateThreadID=\(candidateShort) " +
                "inbound_thread=\(metadata["inbound_thread"] ?? "false") " +
                "direct_message_thread=\(metadata["direct_message_thread"] ?? "false") " +
                "conversation_surface=\(metadata["conversation_surface"] ?? "nil")"
            )
            #endif

            switch decision.route {
            case .exchangeThread:
                return InboundConversationOpenTarget(
                    kind: .exchangeThread(threadID),
                    reason: decision.reason
                )
            case .directMessage:
                if thread.metadata["direct_message_thread"] == "true",
                   dmCandidate == nil {
                    dmCandidate = threadID
                }
            }
        }

        if let dmCandidate {
            return InboundConversationOpenTarget(
                kind: .directMessage(dmCandidate),
                reason: "direct_message_thread"
            )
        }

        if let nodeID = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nodeID.isEmpty {
            return InboundConversationOpenTarget(
                kind: .createDirectMessage(counterpartyNodeID: nodeID),
                reason: "open_or_create_direct_message"
            )
        }

        return InboundConversationOpenTarget(kind: .unavailable, reason: "no_route")
    }

    private func logInboundOpenRouteDecision(
        source: ExchangeInboundOpenSource,
        intent: ExchangeInboundConversationOpenIntent,
        openTarget: InboundConversationOpenTarget
    ) {
        #if DEBUG
        let action: String = {
            switch openTarget.kind {
            case .exchangeThread:
                return "exchangeThread"
            case .directMessage, .createDirectMessage:
                return "directMessage"
            case .unavailable:
                return "unavailable"
            }
        }()
        print(
            "[InboundOpenRoute] source=\(source.rawValue) intent=\(intent.rawValue) " +
            "action=\(action) reason=\(openTarget.reason)"
        )
        #endif
    }

    private func openDirectMessageFromInbound(
        rowID: String,
        counterpartyNodeID: String?,
        displayName: String,
        linkedThreadID: ExchangeThread.ID?,
        intent: ExchangeInboundConversationOpenIntent,
        source: ExchangeInboundOpenSource
    ) {
        Task { @MainActor in
            let resolution = await resolveInboundOpenDMThreadIDForCounterparty(
                rowLinkedThreadID: linkedThreadID,
                counterpartyNodeID: counterpartyNodeID,
                intent: intent
            )
            #if DEBUG
            print(
                "[InboundDMThreadResolution] rowLinkedThreadID=\(linkedThreadID?.uuidString ?? "nil") " +
                    "resolvedThreadID=\(resolution.resolved?.uuidString ?? "nil") reason=\(resolution.reason)"
            )
            print(
                "[InboundOpenClearBasis] linkedThreadID=\(linkedThreadID?.uuidString ?? "nil") " +
                    "resolvedThreadID=\(resolution.resolved?.uuidString ?? "nil") " +
                    "counterpartyNodeID=\(counterpartyNodeID ?? "nil")"
            )
            #endif

            let openTarget: InboundConversationOpenTarget
            if intent == .directMessage,
               let canonicalDM = resolution.resolved,
               await isDirectMessageThread(canonicalDM) {
                #if DEBUG
                print(
                    "[DMOpenRootFix] resolvedFirst threadID=\(canonicalDM.uuidString) " +
                    "reason=\(resolution.reason) rowLinked=\(linkedThreadID?.uuidString ?? "nil")"
                )
                #endif
                openTarget = InboundConversationOpenTarget(
                    kind: .directMessage(canonicalDM),
                    reason: resolution.reason
                )
            } else {
                openTarget = await resolveInboundConversationOpenTarget(
                    rowLinkedThreadID: linkedThreadID,
                    resolvedThreadID: resolution.resolved,
                    counterpartyNodeID: counterpartyNodeID,
                    intent: intent,
                    source: source
                )
            }
            logInboundOpenRouteDecision(source: source, intent: intent, openTarget: openTarget)

            switch openTarget.kind {
            case .exchangeThread(let exchangeThreadID):
                #if DEBUG
                print(
                    "[InboundConversationOpen] action=exchangeThread rowID=\(rowID) " +
                    "threadID=\(exchangeThreadID.uuidString) reason=\(openTarget.reason) " +
                    "counterpartyNodeID=\(counterpartyNodeID ?? "nil")"
                )
                #endif
                do {
                    try await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                        threadID: exchangeThreadID,
                        counterpartyNodeID: counterpartyNodeID
                    )
                } catch {
                    #if DEBUG
                    print("[InboundOpenExchangeMarkRead] failed error=\(error.localizedDescription)")
                    #endif
                }
                await markUnreadInboundMessagingAttentionMatchingCounterpartyOpen(
                    counterpartyNodeID: counterpartyNodeID,
                    resolvedThreadID: exchangeThreadID,
                    rowLinkedThreadID: linkedThreadID
                )
                openThread(exchangeThreadID, from: .inbound)
                return

            case .directMessage(let dmThreadID):
                #if DEBUG
                print(
                    "[InboundConversationOpen] action=directMessage rowID=\(rowID) " +
                    "threadID=\(dmThreadID.uuidString) reason=\(openTarget.reason) " +
                    "counterpartyNodeID=\(counterpartyNodeID ?? "nil")"
                )
                print(
                    "[DMOpenRootFix] hydratedFinalThread threadID=\(dmThreadID.uuidString) " +
                    "hydration=deferredToDirectMessageView"
                )
                #endif
                openDirectMessage(
                    source: "inbound",
                    counterpartyNodeID: counterpartyNodeID ?? "",
                    displayName: displayName,
                    existingThreadID: dmThreadID,
                    origin: .inbound
                )
                do {
                    try await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                        threadID: dmThreadID,
                        counterpartyNodeID: counterpartyNodeID
                    )
                } catch {
                    #if DEBUG
                    print("[InboundOpenDMMarkRead] failed error=\(error.localizedDescription)")
                    #endif
                }
                await markUnreadInboundMessagingAttentionMatchingCounterpartyOpen(
                    counterpartyNodeID: counterpartyNodeID,
                    resolvedThreadID: dmThreadID,
                    rowLinkedThreadID: linkedThreadID
                )
                return

            case .createDirectMessage(let nodeID):
                #if DEBUG
                print(
                    "[InboundConversationOpen] action=createDirectMessage rowID=\(rowID) " +
                    "counterpartyNodeID=\(nodeID) reason=\(openTarget.reason)"
                )
                #endif
                do {
                    let ensuredThreadID = try await services.exchangeFacade.openOrCreateDirectMessageThread(
                        counterpartyNodeID: nodeID,
                        displayName: displayName,
                        now: Date()
                    )
                    openDirectMessage(
                        source: "inbound",
                        counterpartyNodeID: nodeID,
                        displayName: displayName,
                        existingThreadID: ensuredThreadID,
                        origin: .inbound
                    )
                    try await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                        threadID: ensuredThreadID,
                        counterpartyNodeID: counterpartyNodeID
                    )
                    await markUnreadInboundMessagingAttentionMatchingCounterpartyOpen(
                        counterpartyNodeID: counterpartyNodeID,
                        resolvedThreadID: ensuredThreadID,
                        rowLinkedThreadID: linkedThreadID
                    )
                } catch {
                    #if DEBUG
                    print(
                        "[DMRoute][openFailedKeepUnread] senderNodeID=\(nodeID) reason=\(error.localizedDescription)"
                    )
                    #endif
                    return
                }
                return

            case .unavailable:
                #if DEBUG
                print(
                    "[InboundConversationOpen] action=unavailable rowID=\(rowID) reason=\(openTarget.reason)"
                )
                #endif
                return
            }
        }
    }

    private func openClarification(_ threadID: ExchangeThread.ID) {
        recentlyTouchedThreadID = threadID

        withAnimation(.easeInOut(duration: 0.18)) {
            route = .clarification(threadID)
        }
    }

    private func normalizedTopLevelRoute(from route: Route) -> Route {
        switch route {
        case .thread, .clarification:
            return previousTopLevelRoute
        case .dashboard, .threads, .inbound, .trust, .blocked, .profile, .directMessage:
            return route
        }
    }

    private func isThreadLikeRoute(_ route: Route) -> Bool {
        switch route {
        case .thread, .clarification, .directMessage:
            return true
        case .dashboard, .threads, .inbound, .trust, .blocked, .profile:
            return false
        }
    }

    private func isSelectedTopLevelRoute(_ candidate: Route) -> Bool {
        switch (route, candidate) {
        case (.dashboard, .dashboard),
             (.threads, .threads),
             (.inbound, .inbound),
             (.trust, .trust),
             (.blocked, .blocked),
             (.profile, .profile):
            return true
        case (.thread, _), (.clarification, _), (.directMessage, _):
            return previousTopLevelRoute == candidate
        default:
            return false
        }
    }

    // MARK: - Federation polling (visible workspace)

    private func ingestSecretaryWorkspaceRefreshNotification(_ notification: Notification) {
        if let rawThreadID = notification.userInfo?["threadID"] as? String,
           let parsedThreadID = UUID(uuidString: rawThreadID) {
            recentlyTouchedThreadID = parsedThreadID
            services.secretaryDeskPreferredThreadID = parsedThreadID
        }

        if notification.userInfo?["source"] as? String == "localSubmit" {
            #if DEBUG
            let tid = recentlyTouchedThreadID?.uuidString ?? "nil"
            print(
                "[RecentSearchTrace][handoff] discoveryHeroActive=\(services.discoveryHeroProgress?.isActive == true) " +
                "snapshotHasSubmittedThread=deferred preferredThreadID=\(tid) source=localSubmit"
            )
            #endif
            return
        }

        let reason: SecretaryRefreshReason = {
            if let raw = notification.userInfo?["secretaryRefreshReason"] as? String,
               let decoded = SecretaryRefreshReason(rawValue: raw) {
                return decoded
            }
            if notification.userInfo?["threadID"] != nil {
                return .threadChanged
            }
            return .manual
        }()

        services.requestSecretaryRefresh(reason)
    }

    private func foregroundInboxPollScenePhaseLabel(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
    
    private func foregroundInboxPollAppStateLabel(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }

    /// Per-route poll cadence (nanoseconds). Recomputed each loop so tab / overlay route changes take effect immediately.
    private func foregroundInboxPollIntervalNanoseconds(for route: Route, stableSeed: UInt64) -> UInt64 {
        let seconds = services.foregroundPollIntervalSeconds(
            routeLabel: routeDebugLabel,
            stableSeed: stableSeed
        )
        return UInt64(max(1, seconds)) * 1_000_000_000
    }

    private func foregroundInboxPollIntervalSeconds(for route: Route, stableSeed: UInt64) -> Int {
        Int(foregroundInboxPollIntervalNanoseconds(for: route, stableSeed: stableSeed) / 1_000_000_000)
    }

    /// While this view is in the hierarchy, periodically pull remote inbox when the app is effectively active.
    /// Cancelled automatically when the view disappears (`.task` lifetime).
    @MainActor
    private func runFederationPollingWhileSecretaryWorkspaceVisible() async {
        let pollStableSeed = await services.foregroundPollStableSeed()
        let pollInitialDelayNs = UInt64(services.foregroundPollInitialDelaySeconds(stableSeed: pollStableSeed)) * 1_000_000_000
        let inactiveSleepNs: UInt64 = 5_000_000_000
        let inFlightSleepNs: UInt64 = 6_000_000_000

        Swift.print(
            "[ForegroundInboxPoll][taskStart] route=\(routeDebugLabel) " +
            "appScenePhase=\(services.canonicalAppScenePhaseLogLabel()) " +
            "uiApplicationState=\(services.canonicalUIApplicationStateLogLabel())"
        )

        defer {
            Swift.print(
                "[ForegroundInboxPoll][taskEnd] route=\(routeDebugLabel) cancelled=\(Task.isCancelled)"
            )
        }

        try? await Task.sleep(nanoseconds: pollInitialDelayNs)

        Swift.print(
            "[ForegroundInboxPoll][afterInitialDelay] route=\(routeDebugLabel) " +
            "appScenePhase=\(services.canonicalAppScenePhaseLogLabel()) " +
            "uiApplicationState=\(services.canonicalUIApplicationStateLogLabel()) " +
            "effectiveActive=\(services.isForegroundPollingEligible) " +
            "cancelled=\(Task.isCancelled)"
        )

        while !Task.isCancelled {
            let routeLabel = routeDebugLabel
            let appSceneLabel = services.canonicalAppScenePhaseLogLabel()
            let uiApplicationLabel = services.canonicalUIApplicationStateLogLabel()

            if let ineligibleReason = services.foregroundPollingIneligibleReason {
                Swift.print(
                    "[ForegroundInboxPoll][skip] reason=notForegroundEligible detail=\(ineligibleReason) " +
                    "route=\(routeLabel) appScenePhase=\(appSceneLabel) uiApplicationState=\(uiApplicationLabel) " +
                    "sleepSeconds=5"
                )
                try? await Task.sleep(nanoseconds: inactiveSleepNs)
                continue
            }

            let engineStatus = await services.exchangeSyncEngine.currentStatus()

            if engineStatus.isRunning {
                Swift.print(
                    "[ForegroundInboxPoll][skip] reason=inFlight route=\(routeLabel) " +
                    "appScenePhase=\(appSceneLabel) uiApplicationState=\(uiApplicationLabel)"
                )
                try? await Task.sleep(nanoseconds: inFlightSleepNs)
                continue
            }

            if let lastDone = engineStatus.lastCompletedAt,
               services.shouldSkipForegroundPollDueToRecentSync(lastCompletedAt: lastDone) {
                let recentSyncSleepSec = services.foregroundPollIntervalSeconds(
                    routeLabel: routeLabel,
                    stableSeed: pollStableSeed
                )
                Swift.print(
                    "[ForegroundInboxPoll][skip] reason=recentSync route=\(routeLabel) " +
                    "appScenePhase=\(appSceneLabel) uiApplicationState=\(uiApplicationLabel) " +
                    "sleepSeconds=\(recentSyncSleepSec)"
                )
                try? await Task.sleep(nanoseconds: UInt64(max(1, recentSyncSleepSec)) * 1_000_000_000)
                continue
            }

            if services.shouldSkipForegroundPollDueToRecentPushSync(routeLabel: routeLabel) {
                let pushBackedIntervalSec = services.foregroundPollIntervalSeconds(
                    routeLabel: routeLabel,
                    stableSeed: pollStableSeed
                )
                Swift.print(
                    "[ForegroundInboxPoll][skip] reason=backoff route=\(routeLabel) " +
                    "pushDeliveryEffective=\(services.secretaryPushNotificationDeliveryEffectiveOn) " +
                    "sleepSeconds=\(pushBackedIntervalSec)"
                )
                try? await Task.sleep(nanoseconds: UInt64(max(1, pushBackedIntervalSec)) * 1_000_000_000)
                continue
            }

            let intervalSec = foregroundInboxPollIntervalSeconds(for: route, stableSeed: pollStableSeed)

            Swift.print(
                "[ForegroundInboxPoll][start] reason=timer route=\(routeLabel) " +
                "intervalSeconds=\(intervalSec) pushDeliveryEffective=\(services.secretaryPushNotificationDeliveryEffectiveOn) " +
                "appScenePhase=\(appSceneLabel) uiApplicationState=\(uiApplicationLabel)"
            )

            let beforeSnap = await services.exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot()

            await services.syncFederationInboxNowRetryingSilentPushIfEngineNoOp(
                requestDeskRefreshAfter: true,
                recordAttentionDigests: true,
                trigger: .foregroundInboxPoll
            )

            let afterSnap = await services.exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot()

            if afterSnap.sequence > beforeSnap.sequence {
                Swift.print(
                    "[ForegroundInboxPoll][result] route=\(routeLabel) " +
                    "pagesFetched=\(afterSnap.pagesFetched) inboundItemCount=\(afterSnap.itemCount) " +
                    "relaySequence=\(afterSnap.sequence)"
                )
            } else {
                Swift.print(
                    "[ForegroundInboxPoll][skip] reason=engineNoOp route=\(routeLabel) " +
                    "appScenePhase=\(services.canonicalAppScenePhaseLogLabel()) " +
                    "uiApplicationState=\(services.canonicalUIApplicationStateLogLabel())"
                )
            }

            let sleepNs = foregroundInboxPollIntervalNanoseconds(for: route, stableSeed: pollStableSeed)
            try? await Task.sleep(nanoseconds: sleepNs)
        }
    }

    // MARK: - Chrome Refresh

    private func scheduleWorkspaceChromeRefresh(
        delayNanoseconds: UInt64 = 300_000_000
    ) {
        chromeRefreshTask?.cancel()

        chromeRefreshTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await refreshWorkspaceChrome()
        }
    }

    private func requestInboundBadgeChromeRefresh(trigger: String) {
        #if DEBUG
        print(
            "[InboundBadgeRefreshTrigger] source=\(trigger) route=\(routeDebugLabel) oldAttentionDot=\(hasInboundMessagingUnreadAttention)"
        )
        #endif
        inboundBadgeChromeTailRequested = true
        guard inboundBadgeChromeChainTask == nil else { return }
        inboundBadgeChromeChainTask = Task { @MainActor in
            defer {
                inboundBadgeChromeChainTask = nil
            }
            repeat {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                let hadScheduled = inboundBadgeChromeTailRequested
                inboundBadgeChromeTailRequested = false
                guard hadScheduled else { break }
                await refreshWorkspaceChrome()
            } while inboundBadgeChromeTailRequested
        }
    }

    @MainActor
    private func scheduleApplyDeskChromeFromSnapshot(generation: UInt64?) {
        guard let generation else { return }

        #if DEBUG
        print("[DeskSnapshotActor] onChange generation=\(generation)")
        #endif

        chromeApplyTask?.cancel()
        chromeApplyTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            applyDeskChromeFromSnapshot(generation: generation)
        }
    }

    @MainActor
    private func applyDeskChromeFromSnapshot(generation: UInt64) {
        guard generation != appliedChromeSnapshotGeneration else { return }
        guard let snapshot = services.secretaryDeskSnapshot,
              snapshot.generation == generation else { return }

        #if DEBUG
        print("[DeskSnapshotActor] applyChrome generation=\(generation)")
        #endif

        let projection = WorkspaceChromeProjection(
            activeCount: snapshot.chrome.activeCount,
            pendingCount: snapshot.chrome.pendingCount,
            trustedCount: snapshot.chrome.trustedCount,
            recoveryCount: snapshot.chrome.recoveryCount
        )
        if chromeProjection != projection {
            chromeProjection = projection
        }
        appliedChromeSnapshotGeneration = generation
    }

    private func refreshWorkspaceNotificationAttention() async {
        let oldInboundAttentionDot = hasInboundMessagingUnreadAttention
        let oldExchangeThreadAttentionDot = hasExchangeThreadUnreadAttention
        do {
            async let globalUnreadRows = services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                    excludingPriorityLow: true,
                    limit: 600
                )
            )
            async let inboundMessagingRows = services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                    excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )

            let globalUnreadFetched = try await globalUnreadRows
            let unreadBell = SecretaryNotification.collapseGlobalUnreadForDistinctAttention(globalUnreadFetched).count
            let inboundMessagingNotifications = try await inboundMessagingRows

            if let generation = services.secretaryDeskSnapshot?.generation {
                scheduleApplyDeskChromeFromSnapshot(generation: generation)
            }

            if secretaryNotificationUnreadBadge != unreadBell {
                secretaryNotificationUnreadBadge = unreadBell
            }

            let unreadMessagingRows = inboundMessagingNotifications.filter { !$0.isRead }
            let inboundAttentionKeys = Set(unreadMessagingRows.map(\.inboundMessagingAttentionKey))
            var byKindCounts: [String: Int] = [:]
            for n in unreadMessagingRows {
                byKindCounts[n.kind.rawValue, default: 0] += 1
            }
            let distinctAttentionKeyCount = inboundAttentionKeys.count
            let threadKeyCount = inboundAttentionKeys.filter { $0.hasPrefix("thread:") }.count
            let nodeKeyCount = inboundAttentionKeys.filter { $0.hasPrefix("node:") }.count
            let dedupeKeyCount = inboundAttentionKeys.filter { $0.hasPrefix("dedupe:") }.count
            let threadlessRows = inboundMessagingNotifications.filter { $0.threadID == nil }.count
            let distinctThreadIDs = Set(inboundMessagingNotifications.compactMap(\.threadID)).count
            let distinctTrustedNodeIDs = Set(
                inboundMessagingNotifications.compactMap { n -> String? in
                    let t = n.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return t.isEmpty ? nil : t
                }
            ).count
            let chatTabAttentionVisible = try await services.exchangeFacade
                .hasUnreadInboundChatMessagingAttention(among: unreadMessagingRows)
            #if DEBUG
            print(
                "[BottomInboundDotBasis] unreadRows=\(unreadMessagingRows.count) hasDot=\(chatTabAttentionVisible)"
            )
            #endif
            if hasInboundMessagingUnreadAttention != chatTabAttentionVisible {
                hasInboundMessagingUnreadAttention = chatTabAttentionVisible
            }

            let exchangeThreadAttentionVisible = try await services.exchangeFacade
                .hasUnreadExchangeThreadMessagingAttention(among: unreadMessagingRows)
            if hasExchangeThreadUnreadAttention != exchangeThreadAttentionVisible {
                hasExchangeThreadUnreadAttention = exchangeThreadAttentionVisible
            }
            #if DEBUG
            if oldExchangeThreadAttentionDot != exchangeThreadAttentionVisible {
                print(
                    "[BottomThreadsDotState] old=\(oldExchangeThreadAttentionDot) new=\(exchangeThreadAttentionVisible)"
                )
            }
            #endif
            #if DEBUG
            if oldInboundAttentionDot != chatTabAttentionVisible {
                print(
                    "[BottomInboundDotState] old=\(oldInboundAttentionDot) new=\(chatTabAttentionVisible)"
                )
            }
            let keysSorted = inboundAttentionKeys.sorted().joined(separator: ",")
            print(
                "[InboundBadgeCountBasis] unreadRowCount=\(unreadMessagingRows.count) attentionDotVisible=\(chatTabAttentionVisible) keys=\(keysSorted)"
            )
            print(
                "[InboundBadgeCountBasis] mode=distinctAttentionKeys rowCount=\(unreadMessagingRows.count) distinctAttentionKeys=\(distinctAttentionKeyCount) byKind=\(byKindCounts) threadKeys=\(threadKeyCount) nodeKeys=\(nodeKeyCount) dedupeKeys=\(dedupeKeyCount) threadless=\(threadlessRows) distinctThreads=\(distinctThreadIDs) distinctNodes=\(distinctTrustedNodeIDs) keys=\(keysSorted)"
            )
            print(
                "[InboundBadgeCountResult] rows=\(unreadMessagingRows.count) distinct=\(distinctAttentionKeyCount) byKind=\(byKindCounts) attentionDotVisible=\(chatTabAttentionVisible)"
            )
            for n in inboundMessagingNotifications.filter({ !$0.isRead }).prefix(25) {
                print(
                    "[InboundBadgeStaleCandidate] id=\(n.id.uuidString) kind=\(n.kind.rawValue) threadID=\(n.threadID?.uuidString ?? "nil") trustedNodeID=\(n.trustedNodeID ?? "nil") dedupeKey=\(n.dedupeKey) attentionKey=\(n.inboundMessagingAttentionKey) isRead=\(n.isRead)"
                )
            }
            if let snapshot = services.secretaryDeskSnapshot {
                print(
                    "[RefreshTrace][UIRefresh] reason=workspaceNotificationAttention secretaryRefreshID=\(services.secretaryRefreshID) threads=\(snapshot.threadItems.count) inbox=\(snapshot.visibleInboxItems.count) pending=\(snapshot.pendingApprovals.count) time=\(Date())"
                )
            }
            #endif
        } catch {
            // Keep last good notification/chrome state on transient failures.
        }
    }

    /// Legacy entry for notification-only refresh paths (no desk list facade calls).
    private func refreshWorkspaceChrome() async {
        if let generation = services.secretaryDeskSnapshot?.generation {
            scheduleApplyDeskChromeFromSnapshot(generation: generation)
        }
        await refreshWorkspaceNotificationAttention()
    }

    private var secretaryNotificationsBellButton: some View {
        Button {
            Task { @MainActor in
                await refreshSecretaryNotificationCenterPayload(trigger: "sheetOpen")
                showSecretaryNotificationCenter = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .frame(width: 36, height: 36)

                if secretaryNotificationUnreadBadge > 0 {
                    Text(secretaryNotificationUnreadBadge > 99 ? "99+" : "\(secretaryNotificationUnreadBadge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                        .offset(x: 8, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Updates")
    }

    /// Loads rows + badge for the Updates sheet affordance.
    private func refreshSecretaryNotificationCenterPayload(trigger: String) async {
        let beforeCount = secretaryNotificationsList.count
        let priorBell = await MainActor.run { secretaryNotificationUnreadBadge }
        do {
            let rows = try await services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )
            let visible = SecretaryNotification.collapseGlobalUnreadForDistinctAttention(rows)
            let byKind = Dictionary(grouping: visible, by: { $0.kind.rawValue }).mapValues { $0.count }
            #if DEBUG
            print(
                "[GlobalNotificationListBasis] totalFetched=\(rows.count) visible=\(visible.count) byKind=\(byKind) unreadOnly=true excludedKinds=inboundDigest,messageSent"
            )
            print(
                "[GlobalNotificationBellBasis] unreadBefore=\(priorBell) unreadAfter=\(visible.count) distinctCollapsed=true"
            )
            print(
                "[NotificationListLoad] trigger=\(trigger) count=\(visible.count)"
            )
            #endif
            await MainActor.run {
                secretaryNotificationsList = visible
                secretaryNotificationUnreadBadge = visible.count
            }
            #if DEBUG
            print(
                "[SecretaryNotificationRefresh] source=\(trigger) sheetVisible=\(showSecretaryNotificationCenter) beforeCount=\(beforeCount) afterCount=\(visible.count)"
            )
            #endif
        } catch {}
    }

    private func scheduleNotificationCenterPayloadRefresh(
        trigger: String,
        delayNanoseconds: UInt64 = 90_000_000
    ) {
        notificationCenterPayloadRefreshTask?.cancel()
        notificationCenterPayloadRefreshTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard showSecretaryNotificationCenter else { return }
            await refreshSecretaryNotificationCenterPayload(trigger: trigger)
        }
    }

    private func markAllSecretaryNotificationsReadViaCenter() async {
        let beforeList = try? await services.exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 600
            )
        )
        let beforeBell = SecretaryNotification.collapseGlobalUnreadForDistinctAttention(beforeList ?? []).count

        guard
            let rows = try? await services.exchangeFacade.listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                    excludingPriorityLow: true,
                    limit: 800
                )
            )
        else { return }

        let ids = Set(rows.map(\.id))
        guard !ids.isEmpty else { return }

        var affectedKinds: [String: Int] = [:]
        for row in rows {
            affectedKinds[row.kind.rawValue, default: 0] += 1
        }

        #if DEBUG
        print(
            "[GlobalNotificationMarkAllRead] visibleUnread=\(beforeBell) rawUnreadRows=\(rows.count) ids=\(ids.count) affectedKinds=\(affectedKinds)"
        )
        #endif

        try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: ids)

        await refreshWorkspaceChrome()
        await refreshSecretaryNotificationCenterPayload(trigger: "markAllRead")

        #if DEBUG
        let afterList = try? await services.exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 600
            )
        )
        let afterVisible = SecretaryNotification.collapseGlobalUnreadForDistinctAttention(afterList ?? []).count
        await MainActor.run {
            print(
                "[GlobalNotificationAfterMarkAllRead] visible=\(afterVisible) bell=\(secretaryNotificationUnreadBadge) listCount=\(secretaryNotificationsList.count)"
            )
        }
        #endif
    }

    @MainActor
    private static let inboundAttentionSurfaceMetadataKey = "inbound_attention_surface"
    private static let inboundAttentionSurfaceExchangeThread = "exchange_thread"

    private func isExchangeThreadInboundAttentionNotification(_ item: SecretaryNotification) -> Bool {
        item.metadata[Self.inboundAttentionSurfaceMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == Self.inboundAttentionSurfaceExchangeThread
    }

    @MainActor
    private func consumePendingExchangeThreadPushOpenRouteIfNeeded() async {
        guard let threadID = services.takePendingExchangeThreadPushOpenRoute() else { return }
        try? await services.exchangeFacade.markSecretaryExchangeThreadMessagingAttentionReadForOpen(
            threadID: threadID
        )
        openThread(threadID, from: route)
    }

    @MainActor
    private func handleSecretaryNotificationSelection(_ item: SecretaryNotification) async {
        // Important:
        // The Updates sheet collapses multiple raw notification rows into one visible row.
        // So tapping one visible row must clear the whole attention scope, not only item.id.
        switch item.kind {
        case .newReply:
            if isExchangeThreadInboundAttentionNotification(item),
               let threadID = item.threadID {
                try? await services.exchangeFacade.markSecretaryExchangeThreadMessagingAttentionReadForOpen(
                    threadID: threadID
                )
            } else {
                try? await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                    threadID: item.threadID,
                    counterpartyNodeID: item.trustedNodeID
                )
            }

        case .needsAnswer:
            try? await services.exchangeFacade.markSecretaryInboundMessagingAttentionReadForOpen(
                threadID: item.threadID,
                counterpartyNodeID: item.trustedNodeID
            )

        case .matchReady:
            if let tid = item.threadID {
                try? await services.exchangeFacade.markSecretaryThreadPeekNotificationsRead(threadID: tid)
            } else {
                try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: [item.id])
            }

        case .needsApproval:
            if let approvalID = item.approvalID {
                try? await services.exchangeFacade.markSecretaryNotificationsReadForApproval(
                    approvalID: approvalID
                )
            } else {
                try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: [item.id])
            }

        case .recoveryNeeded, .sendFailed:
            if let tid = item.threadID {
                try? await services.exchangeFacade.markSecretaryRecoveryRouteNotificationsRead(
                    threadID: tid
                )
            } else {
                try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: [item.id])
            }

        case .trustedContactAdded:
            if let nodeID = item.trustedNodeID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !nodeID.isEmpty {
                try? await services.exchangeFacade.markSecretaryTrustedContactSurfaceNotificationsRead(
                    nodeID: nodeID
                )
            } else {
                try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: [item.id])
            }

        case .publicationIssue,
             .discoveryMatch,
             .approvalDigest,
             .inboundDigest,
             .messageSent:
            try? await services.exchangeFacade.markSecretaryNotificationsRead(ids: [item.id])
        }

        await refreshWorkspaceChrome()
        await refreshSecretaryNotificationCenterPayload(trigger: "notificationSelect")

        switch item.kind {
        case .trustedContactAdded:
            switchTopLevelRoute(to: .trust)

        case .needsAnswer:
            if let tid = item.threadID {
                openClarification(tid)
            }

        case .needsApproval:
            await openSecretaryApprovalFromNotification(item)

        case .recoveryNeeded, .sendFailed:
            await openSecretaryRecoveryFromNotification(item)

        case .newReply:
            if isExchangeThreadInboundAttentionNotification(item),
               let exchangeThreadID = item.threadID {
                showSecretaryNotificationCenter = false
                openThread(exchangeThreadID, from: route)
            } else if let tid = item.threadID {
                openDirectMessage(
                    source: "notification",
                    counterpartyNodeID: item.trustedNodeID ?? "",
                    displayName: nil,
                    existingThreadID: tid,
                    origin: route
                )
            } else if let nodeID = item.trustedNodeID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                      !nodeID.isEmpty {
                openDirectMessage(
                    source: "notification",
                    counterpartyNodeID: nodeID,
                    displayName: nil,
                    existingThreadID: nil,
                    origin: route
                )
            } else {
                switchTopLevelRoute(to: .inbound)
            }

        case .matchReady, .messageSent:
            if let tid = item.threadID {
                openThread(tid, from: route)
            }

        case .inboundDigest:
            switchTopLevelRoute(to: .inbound)

        case .approvalDigest:
            switchTopLevelRoute(to: .threads)

        case .discoveryMatch:
            switchTopLevelRoute(to: .dashboard)

        case .publicationIssue:
            showSecretaryNotificationCenter = false
            openProfileSurfaceSetup()
        }
    }

    private func openSecretaryApprovalFromNotification(_ item: SecretaryNotification) async {
        guard let tid = item.threadID else { return }

        do {
            let detail = try await services.exchangeFacade.getThread(threadID: tid)
            var panel = SecretaryProjectionEngine.approvalDisplay(for: detail)
            if let aid = item.approvalID,
               detail.approvals.contains(where: { $0.id == aid }) {
                panel = panel.withPreferredApprovalID(aid)
            }
            await MainActor.run {
                activeSheet = .approval(panel)
            }
        } catch {
            await MainActor.run {
                openThread(tid, from: route)
            }
        }
    }

    private func openSecretaryRecoveryFromNotification(_ item: SecretaryNotification) async {
        guard let tid = item.threadID else { return }

        do {
            let detail = try await services.exchangeFacade.getThread(threadID: tid)
            let display = SecretaryProjectionEngine.recoveryDisplay(for: detail)
            await MainActor.run {
                activeSheet = .recovery(display)
            }
        } catch {
            await MainActor.run {
                openThread(tid, from: route)
            }
        }
    }

    private func markSecretaryAttentionReadAfterOpeningApproval(_ display: SecretaryApprovalPanelDisplay) {
        guard let approvalID = display.approvalID else { return }
        Task {
            try? await services.exchangeFacade.markSecretaryNotificationsReadForApproval(
                approvalID: approvalID
            )
        }
    }

    private func markSecretaryAttentionReadAfterOpeningRecovery(_ display: SecretaryRecoveryPanelDisplay) {
        guard let threadID = display.threadID else { return }
        Task {
            try? await services.exchangeFacade.markSecretaryRecoveryRouteNotificationsRead(
                threadID: threadID
            )
        }
    }

    private func markSecretaryAttentionReadAfterOpeningTrustedContact(_ nodeID: String?) {
        let trimmed = nodeID?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        Task {
            try? await services.exchangeFacade.markSecretaryTrustedContactSurfaceNotificationsRead(
                nodeID: trimmed
            )
        }
    }

    // MARK: - Copy

    private var headerTitle: String {
        switch route {
        case .dashboard: return "Secretary"
        case .threads: return "Threads"
        case .inbound: return "Chat"
        case .trust: return "Trusted paths"
        case .blocked: return "Recovery"
        case .profile: return "Profile"
        case .thread: return "Thread"
        case .clarification: return "Clarification"
        case .directMessage: return "Direct message"
        }
    }

    private var headerSubtitle: String? {
        switch route {
        case .dashboard: return "Discovery, threads, chat, and recovery"
        case .threads: return "Work your AI is tracking"
        case .inbound: return "Conversations and messages"
        case .trust: return "People and coordination you trust"
        case .blocked: return "Recovery for blocked, failed, and stalled work"
        case .profile: return "Public surface and identity"
        case .thread: return "Live coordination detail"
        case .clarification: return "Answer one detail so Discovery can keep going"
        case .directMessage: return "Private conversation"
        }
    }

    private var operationalText: String {
        switch route {
        case .dashboard:
            return "Your secretary helps you discover matches, track active threads, stay on top of chat, keep trusted paths clear, and recover when things stall."
        case .threads:
            return "Threads keep coordination visible until the work is done."
        case .inbound:
            return "Catch up on messages, requests, and threads you already care about."
        case .trust:
            return "Trusted paths are how you stay in touch with people you already know."
        case .blocked:
            return "Recovery turns hidden failure into visible next steps."
        case .profile:
            return "Finish your public profile so Discovery and your secretary can represent you accurately."
        case .thread:
            return "A thread should show live state, action boundary, and what happens next."
        case .clarification:
            return "Answer the clarification once, then your secretary can resume finding matches."
        case .directMessage:
            return "Direct messages use the existing thread and federation send path."
        }
    }

    // MARK: - Retained tab host (extracted to reduce main `body` generic metadata)

    private struct SecretaryWorkspaceRetainedTabHost: View {
        struct Callbacks {
            let onOpenProfileSurfaceSetup: () -> Void
            let onOpenThread: (ExchangeThread.ID, Route) -> Void
            let onOpenDiscoveryResults: (ExchangeThread.ID) -> Void
            let onOpenDirectMessageFromInbound: (
                String,
                String?,
                String,
                ExchangeThread.ID?,
                ExchangeInboundConversationOpenIntent,
                ExchangeInboundOpenSource
            ) -> Void
            let onOpenDirectMessage: (
                String,
                String,
                String?,
                ExchangeThread.ID?,
                Route
            ) -> Void
            let onOpenAddTrustedContact: () -> Void
            let onAskSecretaryAboutTrustedNode: (String, String) -> Void
            let onOpenRecoveryPanel: (SecretaryRecoveryPanel.Display) -> Void
            let onOpenApprovalSheet: (SecretaryApprovalSheet.Display) -> Void
            let onOpenComparePanel: (SecretaryComparePanel.Display) -> Void
            let onOpenClarification: (ExchangeThread.ID) -> Void
            let onSwitchTopLevelRoute: (Route) -> Void
            let onRefreshSearch: (ExchangeThread.ID) -> Void
            let onOpenSecretaryNotifications: () -> Void
            let onReturnToCompanion: () -> Void
        }

        @EnvironmentObject private var services: AppServices

        @Binding var route: Route
        @Binding var mountedTopTabs: SecretaryRetainedTopTab
        @Binding var previousTopLevelRoute: Route
        @Binding var activeSheet: SheetRoute?
        @Binding var recentlyTouchedThreadID: ExchangeThread.ID?

        let secretaryRefreshID: Int
        let secretaryNotificationUnreadBadge: Int
        let isProfileTabActive: Bool
        let callbacks: Callbacks

        private var activeRetainedTabMask: SecretaryRetainedTopTab {
            SecretaryWorkspaceView.retainedTabMask(for: route)
        }

        private func retainedTabOpacity(_ tab: SecretaryRetainedTopTab) -> CGFloat {
            activeRetainedTabMask.contains(tab) ? 1 : 0
        }

        private func retainedTabHitTesting(_ tab: SecretaryRetainedTopTab) -> Bool {
            activeRetainedTabMask.contains(tab)
        }

        var body: some View {
            ZStack {
                if mountedTopTabs.contains(.dashboard) {
                    SecretaryDashboardView(
                        isTabActive: retainedTabHitTesting(.dashboard),
                        refreshID: secretaryRefreshID,
                        preferredThreadID: recentlyTouchedThreadID,
                        onOpenThread: { threadID in
                            callbacks.onOpenThread(threadID, .dashboard)
                        },
                        onOpenThreads: {
                            callbacks.onSwitchTopLevelRoute(.threads)
                        },
                        onOpenApprovals: {
                            callbacks.onSwitchTopLevelRoute(.threads)
                        },
                        onOpenTrust: {
                            callbacks.onSwitchTopLevelRoute(.trust)
                        },
                        onOpenBlocked: {
                            callbacks.onSwitchTopLevelRoute(.blocked)
                        },
                        onOpenClarification: { threadID in
                            callbacks.onOpenClarification(threadID)
                        },
                        onRefreshSearch: { threadID in
                            callbacks.onRefreshSearch(threadID)
                        },
                        onOpenApprovalSheet: { display in
                            callbacks.onOpenApprovalSheet(display)
                        },
                        onOpenRecoveryPanel: { display in
                            callbacks.onOpenRecoveryPanel(display)
                        },
                        onViewDiscoveryResults: { threadID in
                            callbacks.onOpenDiscoveryResults(threadID)
                        },
                        onOpenProfileForPublicSurface: {
                            callbacks.onOpenProfileSurfaceSetup()
                        },
                        secretaryNotificationUnreadBadge: secretaryNotificationUnreadBadge,
                        onOpenSecretaryNotifications: {
                            callbacks.onOpenSecretaryNotifications()
                        },
                        onReturnToCompanion: {
                            callbacks.onReturnToCompanion()
                        }
                    )
                    .opacity(retainedTabOpacity(.dashboard))
                    .allowsHitTesting(retainedTabHitTesting(.dashboard))
                }

                if mountedTopTabs.contains(.threads) {
                    SecretaryThreadListView(
                        isTabActive: retainedTabHitTesting(.threads),
                        onOpenDiscoverySetup: {
                            callbacks.onOpenProfileSurfaceSetup()
                        },
                        onOpenThread: { threadID in
                            callbacks.onOpenThread(threadID, .threads)
                        },
                        onViewDiscoveryResults: { threadID in
                            callbacks.onOpenDiscoveryResults(threadID)
                        }
                    )
                    .opacity(retainedTabOpacity(.threads))
                    .allowsHitTesting(retainedTabHitTesting(.threads))
                }

                if mountedTopTabs.contains(.inbound) {
                    SecretaryInboundView(
                        isTabActive: retainedTabHitTesting(.inbound),
                        onOpenConversation: { rowID, counterpartyNodeID, displayName, linkedThreadID, intent, source in
                            callbacks.onOpenDirectMessageFromInbound(
                                rowID,
                                counterpartyNodeID,
                                displayName,
                                linkedThreadID,
                                intent,
                                source
                            )
                        },
                        onOpenDirectMessage: { nodeID, displayName, existingThreadID in
                            callbacks.onOpenDirectMessage(
                                "inbound",
                                nodeID,
                                displayName,
                                existingThreadID,
                                .inbound
                            )
                        },
                        onOpenAddTrustedContact: {
                            callbacks.onOpenAddTrustedContact()
                        }
                    )
                    .opacity(retainedTabOpacity(.inbound))
                    .allowsHitTesting(retainedTabHitTesting(.inbound))
                }

                if mountedTopTabs.contains(.trust) {
                    SecretaryTrustView(
                        isTabActive: retainedTabHitTesting(.trust),
                        onOpenDirectMessage: { nodeID, displayName, _ in
                            callbacks.onOpenDirectMessage(
                                "trusted",
                                nodeID,
                                displayName,
                                nil,
                                .trust
                            )
                        },
                        onAskSecretaryAboutTrustedNode: { node in
                            callbacks.onAskSecretaryAboutTrustedNode(node.displayName, node.nodeID)
                        }
                    )
                    .opacity(retainedTabOpacity(.trust))
                    .allowsHitTesting(retainedTabHitTesting(.trust))
                }

                if mountedTopTabs.contains(.blocked) {
                    SecretaryBlockedView(
                        isTabActive: retainedTabHitTesting(.blocked),
                        onOpenThread: { threadID in
                            callbacks.onOpenThread(threadID, .blocked)
                        },
                        onOpenRecoveryPanel: { display in
                            callbacks.onOpenRecoveryPanel(display)
                        }
                    )
                    .opacity(retainedTabOpacity(.blocked))
                    .allowsHitTesting(retainedTabHitTesting(.blocked))
                }

                if mountedTopTabs.contains(.profile) {
                    UnifyWorkspaceProfileShellView(isTabActive: isProfileTabActive)
                    .opacity(retainedTabOpacity(.profile))
                    .allowsHitTesting(retainedTabHitTesting(.profile))
                }

                switch route {
                case .thread(let threadID):
                    SecretaryThreadView(
                        threadID: threadID,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = previousTopLevelRoute
                            }
                        },
                        onOpenApprovalSheet: { display in
                            callbacks.onOpenApprovalSheet(display)
                        },
                        onOpenRecoveryPanel: { display in
                            callbacks.onOpenRecoveryPanel(display)
                        },
                        onOpenComparePanel: { display in
                            callbacks.onOpenComparePanel(display)
                        },
                        onOpenClarification: { threadID in
                            callbacks.onOpenClarification(threadID)
                        },
                        onOpenThread: { childThreadID in
                            callbacks.onOpenThread(childThreadID, .threads)
                        }
                    )

                case .clarification(let threadID):
                    SecretaryClarificationView(
                        threadID: threadID,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = .thread(threadID)
                            }
                        },
                        onSubmitted: {
                            recentlyTouchedThreadID = threadID
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = .thread(threadID)
                            }
                            NotificationCenter.default.post(
                                name: .secretaryWorkspaceShouldRefresh,
                                object: nil,
                                userInfo: ["threadID": threadID.uuidString]
                            )
                        }
                    )

                case .directMessage(let counterpartyNodeID, let displayName, let existingThreadID):
                    SecretaryDirectMessageView(
                        counterpartyNodeID: counterpartyNodeID,
                        displayName: displayName,
                        existingThreadID: existingThreadID,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = previousTopLevelRoute
                            }
                        }
                    )

                case .dashboard, .threads, .inbound, .trust, .blocked, .profile:
                    EmptyView()
                }
            }
        }
    }
}
