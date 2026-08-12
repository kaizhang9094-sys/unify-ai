import SwiftUI
import UIKit
import Dispatch
import Combine

/// Secretary APNs is wired via `AnumAPNsAppDelegate` + `AppServices` (token registration + sync on delivery).
///
/// Xcode **Signing & Capabilities** (manual):
/// - Enable **Push Notifications**.
/// - **Background Modes** → enable **Remote notifications**.
///
/// APNs upload environment follows the signed `aps-environment` entitlement (`APNsSignedEntitlementEnvironment`).
/// Invoke `requestSecretaryNotificationPermission()` when the user opts in — not automatically at cold boot.

@main
@MainActor
struct AnumAPPApp: App {

    @UIApplicationDelegateAdaptor(AnumAPNsAppDelegate.self) private var apnsDelegate

    @StateObject private var services: AppServices
    @StateObject private var launch: LaunchResourceMonitor

    init() {
        CrashCapture.shared.enable()

        let orch = AppOrchestrator(model: StubModelProvider())
        let svc = AppServices(orchestrator: orch)

        _services = StateObject(wrappedValue: svc)
        _launch = StateObject(wrappedValue: LaunchResourceMonitor())
    }

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .environmentObject(services)
                .environmentObject(services.chat)
                .environmentObject(launch)
                .onAppear {
                    apnsDelegate.services = services
                }
        }
    }
}

// MARK: - Launch gating for low disk / memory pressure

@MainActor
final class LaunchResourceMonitor: ObservableObject {

    enum Mode: Equatable {
        case checking
        case ready
    }

    private static let activeModelFilename = "Unify1.0.gguf"

    private let installMinImportantBytes: Int64 = 2 * 1024 * 1024 * 1024
    private let installMinOpportunisticBytes: Int64 = 3 * 1024 * 1024 * 1024
    private let installedMinImportantBytes: Int64 = 1 * 1024 * 1024 * 1024
    private let installedSoftWarningBytes: Int64 = 2 * 1024 * 1024 * 1024

    @Published var mode: Mode = .checking
    @Published var message: String = "Checking device resources…"
    @Published var softWarningBanner: String? = nil
    @Published var isUnderMemoryWarning: Bool = false

    private var runtimeNoticePolicy = RuntimeNoticePolicy()
    private var activeBannerSeverity: RuntimeNoticeSeverity?
    private var activeBannerDismiss: (() -> Void)?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var memoryWarningObserver: NSObjectProtocol?

    var shouldRecheckOnForeground: Bool {
        mode != .ready
    }

    var showsDismissOnActiveBanner: Bool {
        activeBannerSeverity == .caution
    }

    /// Central gate: raw memory/disk/runtime events must not call `showTimedSoftWarning` directly.
    func routeRuntimeNotice(_ request: RuntimeNoticeRequest) {
        let evaluation = runtimeNoticePolicy.evaluate(request)
        RuntimeNoticePolicy.log(evaluation)

        switch evaluation.decision {
        case .logOnly, .suppress:
            return

        case .show:
            guard let message = evaluation.userMessage else { return }
            runtimeNoticePolicy.recordShown(evaluation)
            showTimedSoftWarning(message, severity: evaluation.severity)
        }
    }

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleMemoryPressure(kind: .iOSWarning)
            }
        }

        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )

        src.setEventHandler { [weak self, weak src] in
            Task { @MainActor [weak self, weak src] in
                guard let self, let src else { return }

                let event = src.data

                if event.contains(.critical) {
                    self.handleMemoryPressure(kind: .dispatchCritical)
                } else if event.contains(.warning) {
                    self.handleMemoryPressure(kind: .dispatchWarning)
                } else if event.contains(.normal) {
                    self.handleMemoryPressure(kind: .dispatchNormal)
                }
            }
        }

        src.resume()
        memoryPressureSource = src
    }

    deinit {
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }

        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func stagedModelURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Models")
            .appendingPathComponent(Self.activeModelFilename)
    }

    private func isModelAlreadyInstalled() -> Bool {
        FileManager.default.fileExists(atPath: stagedModelURL().path)
    }

    func noteForegroundResume() {
        let evaluation = runtimeNoticePolicy.noteForegroundResume()
        RuntimeNoticePolicy.log(evaluation)
    }

    func recheck() {
        let wasReady = mode == .ready

        if !wasReady {
            mode = .checking
            message = "Checking device resources…"
        }

        let modelInstalled = isModelAlreadyInstalled()
        let disk = diskStatus(modelInstalled: modelInstalled)

        if disk.isInsufficient {
            mode = .checking
            message = disk.userMessage
            return
        }

        if !wasReady {
            mode = .ready
            message = ""
        }

        if let warning = disk.softWarning {
            routeRuntimeNotice(
                RuntimeNoticeRequest(
                    source: .diskSoftWarning,
                    messageKind: .diskSpace,
                    customMessage: warning
                )
            )
        }
    }

    private enum PressureKind {
        case dispatchNormal
        case dispatchWarning
        case dispatchCritical
        case iOSWarning
    }

    private func handleMemoryPressure(kind: PressureKind) {
        switch kind {
        case .dispatchNormal:
            routeRuntimeNotice(RuntimeNoticeRequest(source: .dispatchSourceNormal))
            isUnderMemoryWarning = false

            if mode == .checking {
                let disk = diskStatus(modelInstalled: isModelAlreadyInstalled())

                if !disk.isInsufficient {
                    mode = .ready
                    message = ""
                }
            }

        case .dispatchWarning:
            routeRuntimeNotice(RuntimeNoticeRequest(source: .dispatchSourceWarning))

        case .dispatchCritical:
            isUnderMemoryWarning = true
            routeRuntimeNotice(
                RuntimeNoticeRequest(source: .dispatchSourceCritical, messageKind: .memorySlowdown)
            )

        case .iOSWarning:
            isUnderMemoryWarning = true
            routeRuntimeNotice(
                RuntimeNoticeRequest(source: .iOSMemoryWarning, messageKind: .memorySlowdown)
            )
        }
    }

    func dismissActiveUserNoticeBanner() {
        if activeBannerSeverity == .caution {
            runtimeNoticePolicy.recordDismissed(severity: .caution)
        }
        activeBannerSeverity = nil
        activeBannerDismiss = nil
        softWarningBanner = nil
    }

    /// Only invoked when `RuntimeNoticePolicy` returns `.show`.
    private func showTimedSoftWarning(_ text: String, severity: RuntimeNoticeSeverity) {
        activeBannerSeverity = severity
        softWarningBanner = text

        let current = text

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)

            guard let self else { return }
            if self.softWarningBanner == current {
                self.softWarningBanner = nil
                self.activeBannerSeverity = nil
            }
        }
    }

    private func diskStatus(modelInstalled: Bool) -> (
        isInsufficient: Bool,
        userMessage: String,
        softWarning: String?
    ) {
        do {
            let home = URL(fileURLWithPath: NSHomeDirectory())

            let values = try home.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeAvailableCapacityKey
            ])

            let general = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? general
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage ?? general

            if !modelInstalled {
                if important < installMinImportantBytes || opportunistic < installMinOpportunisticBytes {
                    let impGB = bytesToGB(important)
                    let oppGB = bytesToGB(opportunistic)

                    return (
                        true,
                        "Not enough storage to set up Unify (Free: Important ~\(impGB) GB, Opportunistic ~\(oppGB) GB). Unify needs about 2–3 GB free for first-run setup with the current model. Please free up space and try again.",
                        nil
                    )
                }

                return (false, "", nil)
            }

            if important < installedMinImportantBytes {
                let impGB = bytesToGB(important)

                return (
                    true,
                    "Storage is critically low (~\(impGB) GB free for important usage). Please free some space and try again.",
                    nil
                )
            }

            if important < installedSoftWarningBytes {
                let impGB = bytesToGB(important)

                return (
                    false,
                    "",
                    "Storage is getting low (~\(impGB) GB free). Unify can still run, but you may want to free some space."
                )
            }

            return (false, "", nil)
        } catch {
            return fallbackDiskStatus(modelInstalled: modelInstalled)
        }
    }

    private func fallbackDiskStatus(modelInstalled: Bool) -> (
        isInsufficient: Bool,
        userMessage: String,
        softWarning: String?
    ) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )

            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0

            if !modelInstalled {
                if free < installMinImportantBytes {
                    let freeGB = bytesToGB(free)

                    return (
                        true,
                        "Not enough storage to set up Unify (Free ~\(freeGB) GB). Unify needs about 2–3 GB free for first-run setup with the current model. Please free up space and try again.",
                        nil
                    )
                }

                return (false, "", nil)
            }

            if free < installedMinImportantBytes {
                let freeGB = bytesToGB(free)

                return (
                    true,
                    "Storage is critically low (~\(freeGB) GB free). Please free some space and try again.",
                    nil
                )
            }

            if free < installedSoftWarningBytes {
                let freeGB = bytesToGB(free)

                return (
                    false,
                    "",
                    "Storage is getting low (~\(freeGB) GB free). Unify can still run, but you may want to free some space."
                )
            }

            return (false, "", nil)
        } catch {
            if modelInstalled {
                return (false, "", nil)
            }

            return (
                true,
                "Unable to verify available storage. To safely set up Unify, please ensure you have at least 2–3 GB free, then try again.",
                nil
            )
        }
    }

    private func bytesToGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2f", gb)
    }
}

// MARK: - Intent composer keyboard prewarm (one-time per process, during launch splash)

#if DEBUG
@inline(__always)
private func secComposerPrewarmLog(_ message: @autoclosure () -> String) {
    Swift.print("[SEC][ComposerPrewarm] \(message())")
}
#else
@inline(__always)
private func secComposerPrewarmLog(_ message: @autoclosure () -> String) {}
#endif

/// Pays the first `becomeFirstResponder()` keyboard cold-start cost off-screen while launch UI is visible.
@MainActor
private enum IntentComposerKeyboardPrewarm {
    private static var didSchedule = false
    private static var prewarmWindow: UIWindow?
    private static weak var previousKeyWindow: UIWindow?

    static func scheduleIfNeededOnSceneActive() {
        guard !didSchedule else { return }
        didSchedule = true
        secComposerPrewarmLog("schedule sceneActive delayMs=50")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            runFocusedPrewarm(attempt: 0)
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    private static func applyIntentComposerTraits(to textView: UITextView) {
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

    private static func runFocusedPrewarm(attempt: Int) {
        guard prewarmWindow == nil else { return }

        guard let windowScene = activeWindowScene() else {
            if attempt < 2 {
                secComposerPrewarmLog("retry reason=noWindowScene attempt=\(attempt + 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    runFocusedPrewarm(attempt: attempt + 1)
                }
                return
            }
            secComposerPrewarmLog("skipped reason=noWindowScene")
            didSchedule = false
            return
        }

        let bounds = windowScene.screen.bounds
        let window = IntentComposerPrewarmWindow(windowScene: windowScene)
        // Full-screen invisible window (on-screen + key; field must stay user-interaction enabled).
        window.frame = bounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.backgroundColor = .clear
        window.alpha = 0
        window.isUserInteractionEnabled = true

        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = true

        let field = UITextView()
        field.backgroundColor = .clear
        field.font = .systemFont(ofSize: 16, weight: .regular)
        field.isScrollEnabled = true
        field.isUserInteractionEnabled = true
        field.textContainer.lineFragmentPadding = 0
        field.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        applyIntentComposerTraits(to: field)
        host.view.addSubview(field)

        previousKeyWindow = windowScene.windows.first(where: { $0.isKeyWindow })

        window.rootViewController = host
        window.makeKeyAndVisible()

        host.view.frame = bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()

        let fieldHeight: CGFloat = 44
        field.frame = CGRect(
            x: 0,
            y: max(0, host.view.bounds.height - fieldHeight),
            width: host.view.bounds.width,
            height: fieldHeight
        )
        field.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]

        prewarmWindow = window
        secComposerPrewarmLog(
            "mounted invisibleOnScreen attempt=\(attempt) isKey=\(window.isKeyWindow) " +
            "canBecome=\(field.canBecomeFirstResponder) fieldBounds=\(field.frame.integral)"
        )

        DispatchQueue.main.async {
            attemptBecomeFirstResponder(field: field, window: window, windowScene: windowScene, attempt: attempt)
        }
    }

    private static func attemptBecomeFirstResponder(
        field: UITextView,
        window: UIWindow,
        windowScene: UIWindowScene,
        attempt: Int
    ) {
        if !field.canBecomeFirstResponder {
            secComposerPrewarmLog(
                "retry reason=cannotBecomeFirstResponder attempt=\(attempt) isKey=\(window.isKeyWindow) " +
                "hasWindow=\(field.window != nil) userInteraction=\(field.isUserInteractionEnabled)"
            )
            if attempt < 2 {
                teardownPrewarm(field: field, windowScene: windowScene)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    runFocusedPrewarm(attempt: attempt + 1)
                }
            } else {
                teardownPrewarm(field: field, windowScene: windowScene)
            }
            return
        }

        let wallStart = CFAbsoluteTimeGetCurrent()
        secComposerPrewarmLog("becomeFirstResponderBegin attempt=\(attempt)")
        let didFocus = field.becomeFirstResponder()
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wallStart) * 1000)
        secComposerPrewarmLog("becomeFirstResponderEnd success=\(didFocus) elapsedMs=\(elapsedMs)")

        if !didFocus {
            secComposerPrewarmLog(
                "retry reason=focusFailed attempt=\(attempt) isKey=\(window.isKeyWindow) hasWindow=\(field.window != nil) bounds=\(field.bounds.integral)"
            )
            if attempt < 2 {
                teardownPrewarm(field: field, windowScene: windowScene)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    runFocusedPrewarm(attempt: attempt + 1)
                }
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            teardownPrewarm(field: field, windowScene: windowScene)
        }
    }

    private static func teardownPrewarm(field: UITextView, windowScene: UIWindowScene) {
        if field.isFirstResponder {
            field.resignFirstResponder()
        }
        prewarmWindow?.isHidden = true
        prewarmWindow?.rootViewController = nil
        prewarmWindow = nil

        if let previousKeyWindow, !previousKeyWindow.isHidden {
            previousKeyWindow.makeKey()
        } else if let fallback = windowScene.windows.first(where: {
            $0.windowLevel == .normal && !$0.isHidden
        }) {
            fallback.makeKey()
        }

        previousKeyWindow = nil
        secComposerPrewarmLog("teardown complete")
    }
}

/// Swallows touches so the invisible prewarm window never intercepts user input.
private final class IntentComposerPrewarmWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

private struct LaunchGateView: View {

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var launch: LaunchResourceMonitor

    var body: some View {
        Group {
            switch launch.mode {
            case .ready:
                RootView()
                    .overlay(alignment: .top) {
                        if let banner = launch.softWarningBanner {
                            SoftWarningBannerView(
                                text: banner,
                                onDismiss: launch.showsDismissOnActiveBanner
                                    ? { launch.dismissActiveUserNoticeBanner() }
                                    : nil
                            )
                            .padding(.top, 10)
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

            case .checking:
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()

                        Text(launch.message)
                            .multilineTextAlignment(.center)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: launch.softWarningBanner != nil)
        .onAppear {
            launch.recheck()
            if scenePhase == .active {
                IntentComposerKeyboardPrewarm.scheduleIfNeededOnSceneActive()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                IntentComposerKeyboardPrewarm.scheduleIfNeededOnSceneActive()
                launch.noteForegroundResume()
                if launch.shouldRecheckOnForeground {
                    launch.recheck()
                }
            }
        }
    }
}

private struct SoftWarningBannerView: View {

    let text: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.medium)

            Text(text)
                .font(.callout)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 8)
        .accessibilityLabel(text)
    }
}
