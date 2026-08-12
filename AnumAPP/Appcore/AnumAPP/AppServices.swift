import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Combine
import UniformTypeIdentifiers
import CryptoKit
import InnerSelfCore
import AnumCore

/// Coalescing reasons for secretary desk + chrome replay (foreground/local-first — not APNs).
enum SecretaryRefreshReason: String, Sendable {
    case appLaunch
    case appForeground
    case federationSync
    case pushReceived
    case threadChanged
    case approvalChanged
    case forYouChanged
    case relationshipChanged
    case sellerWorkspaceChanged
    case manual
}

protocol ExchangeContactContextStore: Sendable {
    func getContext(remoteNodeID: String) -> ExchangeModels.ContactContext
    func saveContext(_ context: ExchangeModels.ContactContext) -> ExchangeModels.ContactContext
    func deleteContext(remoteNodeID: String)
    func listContexts() -> [ExchangeModels.ContactContext]
}

struct ExchangeUserDefaultsContactContextStore: ExchangeContactContextStore, Sendable {
    private static let defaultsKey = "exchange.contactContext.v1"
    private static let maxNotesChars = 1500
    private static let maxToneChars = 500
    private static let maxGoalChars = 300
    private static let maxGoalNotesChars = 800
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func getContext(remoteNodeID: String) -> ExchangeModels.ContactContext {
        let nodeID = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else {
            return .defaultFor(remoteNodeID: "")
        }
        let current = loadAll()
        let found = current[nodeID]
        #if DEBUG
        print("[ContactContextLoad] remoteNodeID=\(nodeID) found=\(found != nil)")
        #endif
        return found ?? .defaultFor(remoteNodeID: nodeID)
    }

    func saveContext(_ context: ExchangeModels.ContactContext) -> ExchangeModels.ContactContext {
        var current = loadAll()
        let cleaned = sanitize(context)
        current[cleaned.remoteNodeID] = cleaned
        saveAll(current)
        #if DEBUG
        print(
            "[ContactContextSave] remoteNodeID=\(cleaned.remoteNodeID) relationship=\(cleaned.relationshipType.rawValue) goal=\(cleaned.relationshipGoal.rawValue) notesChars=\(cleaned.notes.count) toneChars=\(cleaned.toneOverride?.count ?? 0)"
        )
        #endif
        return cleaned
    }

    func deleteContext(remoteNodeID: String) {
        let nodeID = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else { return }
        var current = loadAll()
        current.removeValue(forKey: nodeID)
        saveAll(current)
    }

    func listContexts() -> [ExchangeModels.ContactContext] {
        Array(loadAll().values).sorted { $0.updatedAt > $1.updatedAt }
    }

    private struct Persisted: Codable {
        var contexts: [ExchangeModels.ContactContext]
    }

    private func sanitize(_ context: ExchangeModels.ContactContext) -> ExchangeModels.ContactContext {
        let nodeID = context.remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = String(
            context.notes
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maxNotesChars)
        )
        let tone = context.toneOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedTone = tone.map { String($0.prefix(Self.maxToneChars)) }
        let customGoal = context.customRelationshipGoal?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedCustomGoal = customGoal.map { String($0.prefix(Self.maxGoalChars)) }
        let goalNotes = context.goalNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedGoalNotes = goalNotes.map { String($0.prefix(Self.maxGoalNotesChars)) }
        return ExchangeModels.ContactContext(
            remoteNodeID: nodeID,
            displayNameOverride: context.displayNameOverride,
            relationshipType: context.relationshipType,
            customRelationshipLabel: context.customRelationshipLabel,
            relationshipGoal: context.relationshipGoal,
            customRelationshipGoal: clippedCustomGoal,
            goalNotes: clippedGoalNotes,
            notes: notes,
            toneOverride: clippedTone,
            aiAssistLevel: context.aiAssistLevel,
            updatedAt: context.updatedAt
        )
    }

    private func loadAll() -> [String: ExchangeModels.ContactContext] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return [:]
        }
        var output: [String: ExchangeModels.ContactContext] = [:]
        for raw in decoded.contexts {
            let sanitized = sanitize(raw)
            guard !sanitized.remoteNodeID.isEmpty else { continue }
            output[sanitized.remoteNodeID] = sanitized
        }
        return output
    }

    private func saveAll(_ map: [String: ExchangeModels.ContactContext]) {
        let payload = Persisted(contexts: Array(map.values))
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Transient UI projection for live Discovery hero progress during an in-flight search submit.
struct DiscoveryHeroProgressProjection: Identifiable, Equatable, Sendable {
    enum Stage: String, Sendable, Hashable, CaseIterable {
        case understandingRequest
        case searchingPublicNodes
        case rankingResults
        case finalizing
    }

    let id: UUID
    let generation: UInt64
    let originalText: String
    var stage: Stage
    let aiDisplayName: String
    let startedAt: Date
    var updatedAt: Date
    var isActive: Bool

    static func statusLine(stage: Stage, aiDisplayName: String) -> String {
        let name = aiDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? "Uni" : name
        switch stage {
        case .understandingRequest:
            return "\(resolvedName) is understanding your request"
        case .searchingPublicNodes:
            return "\(resolvedName) is searching public nodes"
        case .rankingResults:
            return "\(resolvedName) is ranking search results"
        case .finalizing:
            return "\(resolvedName) is preparing the result"
        }
    }

    static func accessibilityLabel(stage: Stage, aiDisplayName: String, originalText: String) -> String {
        let status = statusLine(stage: stage, aiDisplayName: aiDisplayName)
        let request = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return status }
        return "\(status). Request: \(request)"
    }
}

/// Bridges AnumCore progress reports onto `AppServices` without blocking the pipeline.
final class DiscoveryHeroProgressReporterBox: DiscoveryHeroProgressReporting, @unchecked Sendable {
    private weak var owner: AppServices?

    func bind(_ services: AppServices) {
        owner = services
    }

    nonisolated func reportDiscoveryHeroProgress(_ update: DiscoveryHeroProgressUpdate) {
        Task { @MainActor [weak owner] in
            owner?.applyDiscoveryHeroProgressUpdate(update)
        }
    }
}

enum DiscoveryHeroProgressStageMapping {
    static func projectionStage(
        from updateStage: DiscoveryHeroProgressUpdate.Stage
    ) -> DiscoveryHeroProgressProjection.Stage {
        switch updateStage {
        case .understandingRequest: return .understandingRequest
        case .searchingPublicNodes: return .searchingPublicNodes
        case .rankingResults: return .rankingResults
        case .finalizing: return .finalizing
        }
    }
}

/// Read-only mailbox digest counts for UI gates (inbox + pending approvals).
struct SecretaryMailboxDigestCounts: Equatable, Sendable {
    var inbox: Int
    var pending: Int

    static let zero = SecretaryMailboxDigestCounts(inbox: 0, pending: 0)
}

@MainActor
final class AppServices: ObservableObject {

    let objectWillChange = ObservableObjectPublisher()

    // MARK: - Core app graph

    let orchestrator: AppOrchestrator
    let chat: ChatViewModel
    let requesterLocationService: RequesterLocationService

    // MARK: - Secretary instructions (Exchange)

    @Published var secretaryConstitutionText: String
    @Published var secretaryStyleText: String

    // MARK: - Autonomous For You discovery

    @Published var secretaryDiscoveryMode: ExchangeModels.SecretaryDiscoveryMode = .off
    @Published var threadAutonomyMode: ExchangeModels.ExchangeThreadAutonomyMode = .manualOnly
    @Published var forYouItems: [ExchangeModels.ForYouItem] = []

    /// Transient live progress for the Discovery compact hero strip during an in-flight search submit.
    @Published private(set) var discoveryHeroProgress: DiscoveryHeroProgressProjection?

    /// Immediate dashboard strip row from the latest local submit response (before desk snapshot catches up).
    @Published private(set) var localCurrentSearchStripItem: ExchangeModels.InboxItem?
    private var discoveryHeroProgressGeneration: UInt64 = 0

    private static let discoveryModeKey = "secretary.discovery.mode"
    private static let threadAutonomyModeKey = "secretary.threadAutonomy.mode"
    private static let autonomousContactsKey = "secretary.autonomous.contacts"
    private static let dismissedForYouKey = "secretary.foryou.dismissed"
    private static let forYouLastAutomaticRefreshAtKey = "secretary.foryou.lastAutomaticRefreshAt"
    private static let forYouLastFailureAtKey = "secretary.foryou.lastFailureAt"
    private static let forYouLastFailureKindKey = "secretary.foryou.lastFailureKind"
    private static let forYouDismissTTL: TimeInterval = 7 * 24 * 3600 // 7 days

    // MARK: - Exchange wiring

    @Published var sellerWorkspace: ExchangeModels.SellerWorkspaceSummary?
    /// Bumped whenever ``sellerWorkspace`` is assigned so Profile can observe hydration without tab switches.
    @Published private(set) var sellerWorkspaceHydrationGeneration: Int = 0
    @Published var sellerValidationIssues: [ExchangeSellerValidationIssue] = []
    @Published var exchangeIdentityDebugSummary: ExchangeIdentityDebugSummary?

    #if DEBUG
    @Published var searchIntentSmokeAuditStatus: String?
    @Published var searchIntentSmokeAuditLastArtifactURL: URL?
    @Published private(set) var isSearchIntentSmokeAuditRunning: Bool = false

    @Published var requesterGapSmokeAuditStatus: String?
    @Published var requesterGapSmokeAuditLastArtifactURL: URL?
    @Published private(set) var isRequesterGapSmokeAuditRunning: Bool = false

    @Published var requesterComposeSmokeAuditStatus: String?
    @Published var requesterComposeSmokeAuditLastArtifactURL: URL?
    @Published private(set) var isRequesterComposeSmokeAuditRunning: Bool = false

    @Published var providerInquiryAnswerSmokeAuditStatus: String?
    @Published var providerInquiryAnswerSmokeAuditLastArtifactURL: URL?
    @Published private(set) var isProviderInquiryAnswerSmokeAuditRunning: Bool = false

    @Published var directChatReplySmokeAuditStatus: String?
    @Published var directChatReplySmokeAuditLastArtifactURL: URL?
    @Published private(set) var isDirectChatReplySmokeAuditRunning: Bool = false

    @Published var appSearchSmokeStatus: String?
    @Published var appSearchSmokeLastReport: String?
    @Published var appSearchSmokeLastArtifactURL: URL?
    @Published private(set) var isAppSearchSmokeRunning: Bool = false

    @Published var retrievalE2ESmokeStatus: String?
    @Published var retrievalE2ESmokeLastReport: String?
    @Published var retrievalE2ESmokeLastArtifactURL: URL?
    @Published private(set) var isRetrievalE2ESmokeRunning: Bool = false

    @Published var multilingualE2ESmokeStatus: String?
    @Published var multilingualE2ESmokeLastReport: String?
    @Published var multilingualE2ESmokeLastArtifactURL: URL?
    @Published private(set) var isMultilingualE2ESmokeRunning: Bool = false

    @Published var multilingualLiveSubsetStatus: String?
    @Published var multilingualLiveSubsetLastReport: String?
    @Published var multilingualLiveSubsetLastArtifactURL: URL?
    @Published private(set) var isMultilingualLiveSubsetRunning: Bool = false
    #endif

    /// First `refreshSellerWorkspace` attempt has finished (success, failure, or no-op). Profile uses this to avoid showing placeholder copy as a "loaded" state during cold launch.
    @Published private(set) var hasCompletedSellerWorkspaceHydrationAtLeastOnce: Bool = false
    /// True while a coalesced seller workspace refresh task is running.
    @Published private(set) var isSellerWorkspaceRefreshInFlight: Bool = false

    /// Profile tab or seller editor must be active before cold-path `getSellerWorkspace` runs.
    private var secretaryProfileTabIsActive = false
    private var cachedExchangeNodeID: String?
    private var cachedExchangeNodeIDFetchedAt: Date?
    private static let exchangeNodeIDCacheTTL: TimeInterval = 300
    private var sellerSurfaceEditorIsPresented = false

    private var exchangeGraph: ExchangeGraph?

    var exchangeDependencies: ExchangeBootstrap.Dependencies { requireExchangeGraph().dependencies }
    var exchangeRelayClient: ExchangeHTTPRelayClient? { requireExchangeGraph().relayClient }
    var exchangeBundle: ExchangeBootstrap.Bundle { requireExchangeGraph().bundle }
    var exchangeStore: any ExchangeStore { requireExchangeGraph().store }
    var exchangeFacade: ExchangeFacade { requireExchangeGraph().facade }
    var exchangeChatBridge: ExchangeChatBridge { requireExchangeGraph().chatBridge }
    var exchangeSyncEngine: ExchangeSyncEngine { requireExchangeGraph().syncEngine }
    private var secretaryStyleStore: any ExchangeSecretaryStyleStore {
        requireExchangeGraph().secretaryStyleStore
    }

    private func requireExchangeGraph() -> ExchangeGraph {
        guard let exchangeGraph else {
            preconditionFailure("Exchange runtime is not available")
        }
        return exchangeGraph
    }
    private var contactContextStore: any ExchangeContactContextStore
    private let directChatReplySuggestionService: DirectChatReplySuggestionService
    private let sellerServiceAreaResolver: ExchangeSellerServiceAreaResolver

    // MARK: - Deferred lifecycle work

    private var didStartExchangeBoot = false
    private var exchangeBootTask: Task<Void, Never>?
    /// Foreground-only delayed federation pass (see `syncFederationOnAppActive`).
    private var foregroundFederationSyncTask: Task<Void, Never>?
    private var sellerWorkspaceRefreshTask: Task<Void, Never>?

    // MARK: - Canonical app lifecycle (single writer: RootView)

    @Published private(set) var appScenePhase: ScenePhase = .inactive
    @Published private(set) var uiApplicationState: UIApplication.State = .inactive

    var isForegroundPollingEligible: Bool {
        appScenePhase == .active && uiApplicationState == .active
    }

    var foregroundPollingIneligibleReason: String? {
        if appScenePhase != .active {
            return "scenePhase_\(Self.scenePhaseLogLabel(appScenePhase))"
        }
        if uiApplicationState != .active {
            return "uiApplicationState_\(Self.uiApplicationStateLogLabel(uiApplicationState))"
        }
        return nil
    }

    func updateAppScenePhase(_ phase: ScenePhase, source: String) {
        guard appScenePhase != phase else { return }
        appScenePhase = phase
        #if DEBUG
        print(
            "[AppLifecycle] appScenePhase=\(Self.scenePhaseLogLabel(phase)) source=\(source)"
        )
        #endif
    }

    func updateUIApplicationState(_ state: UIApplication.State, source: String) {
        guard uiApplicationState != state else { return }
        uiApplicationState = state
        #if DEBUG
        print(
            "[AppLifecycle] uiApplicationState=\(Self.uiApplicationStateLogLabel(state)) source=\(source)"
        )
        #endif
    }

    func canonicalAppScenePhaseLogLabel() -> String {
        Self.scenePhaseLogLabel(appScenePhase)
    }

    func canonicalUIApplicationStateLogLabel() -> String {
        Self.uiApplicationStateLogLabel(uiApplicationState)
    }

    static func scenePhaseLogLabel(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    static func uiApplicationStateLogLabel(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    /// Monotonic gate for secretary desk (`SecretaryDashboardView`) — coalesce bursts (~90ms debounce).
    @Published private(set) var secretaryRefreshID: Int = 0
    private var secretaryRefreshTask: Task<Void, Never>?

    // MARK: - Secretary desk snapshot (shared startup state)

    @Published private(set) var secretaryDeskSnapshot: SecretaryDeskSnapshot?

    /// Last committed digest counts (desk snapshot or async store walk); not mutated by callers.
    private var lastCommittedMailboxDigestCounts = SecretaryMailboxDigestCounts.zero

    /// Synchronous mailbox digest for `@MainActor` UI (prefers committed desk snapshot).
    func currentSecretaryMailboxDigestCounts() -> SecretaryMailboxDigestCounts {
        if let snapshot = secretaryDeskSnapshot {
            return SecretaryMailboxDigestCounts(
                inbox: snapshot.visibleInboxItems.count,
                pending: snapshot.pendingApprovals.count
            )
        }
        return lastCommittedMailboxDigestCounts
    }

    func currentSecretaryInboxDigestCount() -> Int {
        currentSecretaryMailboxDigestCounts().inbox
    }

    @MainActor
    func commitSecretaryDeskSnapshot(_ snapshot: SecretaryDeskSnapshot) {
        #if DEBUG
        print("[DeskSnapshotActor] commit generation=\(snapshot.generation)")
        #endif
        secretaryDeskSnapshot = snapshot
        lastCommittedMailboxDigestCounts = SecretaryMailboxDigestCounts(
            inbox: snapshot.visibleInboxItems.count,
            pending: snapshot.pendingApprovals.count
        )
    }
    var secretaryDeskPreferredThreadID: ExchangeThread.ID?
    var secretaryDeskSnapshotGeneration: UInt64 = 0
    var secretaryDeskSnapshotRefreshTask: Task<Void, Never>?
    var secretaryDeskSnapshotPendingReason: String?
    var secretaryDeskSnapshotPendingForce: Bool = false
    var secretaryDeskSnapshotTailCandidateReason: String?
    var secretaryDeskSnapshotTailCandidateForce: Bool = false
    var secretaryDeskSnapshotLastRefreshReason: String?
    var secretaryDeskSnapshotLastRefreshFinishedAt: Date?
    /// Federation sync completion time stamped into the last committed desk snapshot.
    var secretaryDeskSnapshotExchangeSyncCompletedAt: Date?

    /// Effective secretary APNs delivery for this device (iOS permission ∧ local opt-in ∧ token path OK).
    @Published private(set) var secretaryPushNotificationDeliveryEffectiveOn: Bool = false

    /// Last lightweight inbox sync driven by APNs (silent or foreground alert delivery).
    private(set) var lastPushTriggeredSyncAt: Date?
    private(set) var lastPushTriggeredSyncSucceeded: Bool = false

    /// One-shot dedupe for icon-open resume sync keyed to a delivered notification.
    private var lastDeliveredNotificationResumeSyncKey: String?
    private var lastDeliveredNotificationResumeSyncAt: Date?

    /// One-shot exchange-thread deep link after APNs tap sync (`SecretaryWorkspaceView` consumes).
    private(set) var pendingExchangeThreadPushOpenRoute: ExchangeThread.ID?
    private(set) var pendingExchangeThreadPushOpenRouteGeneration: UInt = 0

    private var secretaryNotificationsDidChangeCancellable: AnyCancellable?

    private static let deliveredSecretaryNotificationMaxAge: TimeInterval = 600
    private static let deliveredNotificationResumeSyncDedupeWindow: TimeInterval = 60

    private static let resumeEligibleDeliveredSecretaryKinds: Set<String> = [
        "inbound_message"
    ]

    let exchangeForegroundSyncPolicy = ExchangeForegroundSyncPolicy()

    private static let pendingAPNsTokenHexKey = "secretary.apns.pendingTokenHex.v1"
    private static let lastRegisteredAPNsTokenHexKey = "secretary.apns.lastRegisteredTokenHex.v1"
    private static let lastRegisteredContextKey = PushTokenRegistrationContext.storageKey
    /// User turned off Unify secretary delivery in-app (server token disabled + no upload while true).
    private static let unifyPushDeliveryOptOutKey = "secretary.apns.unifyDeliveryOptOut.v1"
    /// Last federation `registerPushToken` attempt failed (diagnostic; does not permanently block upload).
    private static let pushTokenRegistrationFailedKey = "secretary.apns.registrationAttemptFailed.v1"
    /// UIKit `registerForRemoteNotifications` failed (device-level, not federation upload).
    private static let remoteRegistrationFailedKey = "secretary.apns.remoteRegistrationFailed.v1"

    // MARK: - Secretary attention digest baselines (count/fingerprint snapshots)

    private static let secretaryNotifyBaselineSeededKey = "secretary.notify.baseline.seeded.v1"
    private static let secretaryNotifyLastInboxCountKey = "secretary.notify.lastInboxCount.v1"
    private static let secretaryNotifyLastApprovalsCountKey = "secretary.notify.lastApprovalsCount.v1"
    private static let secretaryNotifyForYouLastNotifiedFingerprintKey = "secretary.notify.forYouLastNotifiedFingerprint.v1"
    private static let llmProviderResponseAssessmentEnabledKey = "exchange.secondhalf.llmProviderResponseAssessment.enabled"
    static let safeAutoFollowUpsUserDefaultsKey = threadAutonomyModeKey

    /// Persisted default for `secretary.threadAutonomy.mode` so policy and in-memory state agree (no implicit `.missing`).
    /// Writes `manualOnly` when absent, blank, or unrecognized; preserves valid stored modes.
    internal static func bootstrapThreadAutonomyModeIfNeeded(defaults: UserDefaults = .standard) {
        let key = threadAutonomyModeKey
        let trimmed = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.set(ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue, forKey: key)
            return
        }
        if ExchangeModels.ExchangeThreadAutonomyMode(rawValue: trimmed) == nil {
            defaults.set(ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue, forKey: key)
        }
    }

    private enum LLMProviderResponseAssessmentFlagSource: String {
        case explicitOverride
        case debugDefault
        case releaseDefault
    }

    private static var llmProviderResponseAssessmentFlagResolution: (enabled: Bool, source: LLMProviderResponseAssessmentFlagSource) {
        if let explicit = UserDefaults.standard.object(forKey: llmProviderResponseAssessmentEnabledKey) as? Bool {
            return (explicit, .explicitOverride)
        }
        #if DEBUG
        return (true, .debugDefault)
        #else
        return (false, .releaseDefault)
        #endif
    }

    init(orchestrator: AppOrchestrator) {
        ExchangeBootstrap.logFederationBaseURLAtStartup()
        APNsSignedEntitlementEnvironment.logBuildConfig()
        APNsSignedEntitlementEnvironment.logEntitlementsCheck()
        ExchangeBootstrap.performDebugExchangeIdentityResetIfRequested()
        #if DEBUG
        print("[ProfileHydration] appServices init start")
        #endif
        self.orchestrator = orchestrator

        let constitutionSource = SecretaryConstitutionStorage.migrateFromLegacyRepresentationIfNeeded()
        let constitutionInitial = SecretaryConstitutionStorage.load()
        let styleInitial = SecretaryStyleTextStorage.load()
        let styleSource = SecretaryStyleTextStorage.loadLoggingSource()
        #if DEBUG
        print(
            "[SecretaryInstructionsSettings] loaded constitutionSource=\(constitutionSource.rawValue)"
        )
        print(
            "[SecretaryInstructionsSettings] loaded styleSource=\(styleSource.rawValue)"
        )
        #endif
        self.secretaryConstitutionText = constitutionInitial
        self.secretaryStyleText = styleInitial

        let constitutionProvider: @Sendable () -> String? = {
            SecretaryConstitutionStorage.loadOptional()
        }
        let styleTextProvider: @Sendable () -> String? = {
            SecretaryStyleTextStorage.loadOptional()
        }

        let discoveryHeroProgressReporter = DiscoveryHeroProgressReporterBox()
        let requesterLocationService = RequesterLocationService()
        self.requesterLocationService = requesterLocationService
        let replySuggestionRunner = LlamaExchangeModelRunner(
            secretaryConstitutionProvider: constitutionProvider
        )

        let builtGraph: ExchangeGraph
        do {
            builtGraph = try Self.buildExchangeGraph(
                databaseURL: Self.makeExchangeDatabaseURL(),
                constitutionProvider: constitutionProvider,
                styleTextProvider: styleTextProvider,
                discoveryHeroProgressReporter: discoveryHeroProgressReporter,
                requesterLocationProvider: requesterLocationService
            )
        } catch {
            fatalError("Failed to initialize ExchangeBootstrap bundle: \(error)")
        }

        self.exchangeGraph = builtGraph
        self.contactContextStore = ExchangeUserDefaultsContactContextStore()
        self.directChatReplySuggestionService = DirectChatReplySuggestionService(runner: replySuggestionRunner)
        self.sellerServiceAreaResolver = ExchangeSellerServiceAreaResolver(
            geocoder: SellerServiceAreaGeocodingService()
        )

        let chat = ChatViewModel(orchestrator: orchestrator)
        chat.configureExchange(
            bridge: builtGraph.chatBridge,
            facade: builtGraph.facade
        )
        self.chat = chat
        chat.appServices = self
        discoveryHeroProgressReporter.bind(self)

        Self.bootstrapThreadAutonomyModeIfNeeded()

        // Restore persisted discovery mode (defaults to .off if absent or unrecognised).
        let rawMode = UserDefaults.standard.string(forKey: Self.discoveryModeKey) ?? ""
        self.secretaryDiscoveryMode = ExchangeModels.SecretaryDiscoveryMode(rawValue: rawMode) ?? .off
        let rawThreadAutonomyMode = UserDefaults.standard.string(forKey: Self.threadAutonomyModeKey) ?? ""
        self.threadAutonomyMode = ExchangeModels.ExchangeThreadAutonomyMode(rawValue: rawThreadAutonomyMode) ?? .manualOnly

        if secretaryDiscoveryMode == .discoverOnly {
            restoreForYouPersistedLifecycleState()
        }

        // IMPORTANT:
        // Do not register/sync/seed/refresh Exchange work inside init.
        // AppServices init should only build the app graph.
        // RootView starts Exchange after first paint/model launch settles.

        secretaryNotificationsDidChangeCancellable = NotificationCenter.default
            .publisher(for: .secretaryNotificationsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.reconcileIOSBadgeWithSecretaryUnread(trigger: "secretaryNotificationsDidChange")
                }
            }

        #if DEBUG
        print("[ProfileHydration] appServices init done")
        #endif
    }

    deinit {
        secretaryNotificationsDidChangeCancellable?.cancel()
        exchangeBootTask?.cancel()
        foregroundFederationSyncTask?.cancel()
        sellerWorkspaceRefreshTask?.cancel()
        secretaryRefreshTask?.cancel()
    }

    // MARK: - Secretary refresh coordinator (coalesced)

    // MARK: - Discovery hero live progress (transient, non-persistent)

    func beginDiscoveryHeroProgress(originalText: String, generation: UInt64) {
        let trimmed = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        discoveryHeroProgressGeneration = generation
        let now = Date()
        discoveryHeroProgress = DiscoveryHeroProgressProjection(
            id: UUID(),
            generation: generation,
            originalText: trimmed,
            stage: .understandingRequest,
            aiDisplayName: resolvedCompanionDisplayName(),
            startedAt: now,
            updatedAt: now,
            isActive: true
        )

        #if DEBUG
        print(
            "[DiscoveryHeroProgress] begin generation=\(generation) stage=understandingRequest"
        )
        #endif
    }

    func applyDiscoveryHeroProgressUpdate(_ update: DiscoveryHeroProgressUpdate) {
        guard update.generation == discoveryHeroProgressGeneration else { return }
        guard var current = discoveryHeroProgress, current.isActive else { return }

        let mappedStage = DiscoveryHeroProgressStageMapping.projectionStage(from: update.stage)
        if current.stage == mappedStage {
            return
        }

        current.stage = mappedStage
        current.updatedAt = update.updatedAt
        discoveryHeroProgress = current
    }

    func endDiscoveryHeroProgress(generation: UInt64, reason: String = "completed") {
        guard generation == discoveryHeroProgressGeneration else { return }
        guard discoveryHeroProgress != nil else { return }

        #if DEBUG
        print("[DiscoveryHeroProgress] end generation=\(generation) reason=\(reason)")
        #endif

        discoveryHeroProgress = nil
    }

    private func resolvedCompanionDisplayName() -> String {
        let raw = UserDefaults.standard
            .string(forKey: "companionName")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "Uni" }
        return raw
    }

    /// Debounced increment of `secretaryRefreshID` so multiple producers collapse to one desk replay.
    @MainActor
    func requestSecretaryRefresh(_ reason: SecretaryRefreshReason) {
        #if DEBUG
        print("[AppServices] requestSecretaryRefresh queued reason=\(reason.rawValue)")
        #endif

        secretaryRefreshTask?.cancel()
        secretaryRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            if let skipCause = await deskSnapshotSkipCauseIfRedundant(reason: reason.rawValue) {
                #if DEBUG
                print(
                    "[DeskSnapshotCoalesce] skip reason=\(reason.rawValue) cause=\(skipCause) " +
                    "generation=\(secretaryDeskSnapshot?.generation ?? 0)"
                )
                print(
                    "[AppServices] secretaryRefresh skipped reason=\(reason.rawValue) cause=\(skipCause)"
                )
                #endif
                return
            }

            secretaryRefreshID &+= 1
            refreshSecretaryDeskSnapshot(
                reason: reason.rawValue,
                preferredThreadID: secretaryDeskPreferredThreadID
            )
            #if DEBUG
            print(
                "[RefreshTrace][UIRefresh] reason=\(reason.rawValue) secretaryRefreshID=\(secretaryRefreshID) " +
                "threads=unknown inbox=unknown pending=unknown time=\(Date())"
            )
            print(
                "[AppServices] secretaryRefresh committed reason=\(reason.rawValue) " +
                "secretaryRefreshID=\(secretaryRefreshID)"
            )
            #endif
        }
    }

    /// Post-submit handoff: prefer the new search thread, show strip immediately, force desk snapshot (no debounce).
    @MainActor
    func recordLocalSearchSubmitHandoff(
        threadID: ExchangeThread.ID,
        userText: String,
        stripItem: ExchangeModels.InboxItem? = nil
    ) {
        secretaryDeskPreferredThreadID = threadID

        if let stripItem {
            localCurrentSearchStripItem = stripItem
            #if DEBUG
            print(
                "[RecentSearchTrace][stripOverride] threadID=\(stripItem.threadID.uuidString) " +
                "state=\(stripItem.state) source=submit"
            )
            #endif
        }

        #if DEBUG
        print(
            "[RecentSearchTrace][preferredSet] threadID=\(threadID.uuidString) source=submit"
        )
        print(
            "[RecentSearchTrace][refreshRequested] threadID=\(threadID.uuidString) " +
            "reason=threadChanged force=true"
        )
        #endif

        secretaryRefreshID &+= 1
        refreshSecretaryDeskSnapshot(
            reason: "localSubmit",
            force: true,
            preferredThreadID: threadID
        )
    }

    @MainActor
    func clearLocalCurrentSearchStripItemIfReconciled(with snapshotThreads: [ExchangeModels.InboxItem]) {
        guard let override = localCurrentSearchStripItem else { return }
        guard SecretarySearchResultProjection.shouldClearLocalStripOverride(
            overrideItem: override,
            snapshotThreads: snapshotThreads
        ) else {
            return
        }
        #if DEBUG
        print(
            "[RecentSearchTrace][stripOverride] action=cleared threadID=\(override.threadID.uuidString) " +
            "reason=snapshotReconciled"
        )
        #endif
        localCurrentSearchStripItem = nil
    }

    // MARK: - Remote push (APNs)

    /// Requests notification permission and registers for a device token (not called at cold boot — invoke from settings/onboarding).
    func requestSecretaryNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let statusBefore = await center.notificationSettings().authorizationStatus
        let optedOut = UserDefaults.standard.bool(forKey: Self.unifyPushDeliveryOptOutKey)
        print(
            "[APNs][RegisterAttempt] authStatus=\(statusBefore.logToken) optedOut=\(optedOut) " +
            "source=requestSecretaryNotificationPermission"
        )
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            let statusAfter = await center.notificationSettings().authorizationStatus
            #if DEBUG
            print(
                "[NotificationPermission] requested=true granted=\(granted) " +
                "error=nil authorizationStatus=\(statusAfter.logToken) " +
                "willRegisterForRemoteNotifications=\(granted)"
            )
            #endif
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            let statusAfter = await center.notificationSettings().authorizationStatus
            print("[APNs][RegisterFailure] error=\(error.localizedDescription)")
            UserDefaults.standard.set(true, forKey: Self.remoteRegistrationFailedKey)
            await refreshSecretaryPushNotificationDeliveryState(logContext: "notificationPermissionRequestFailed")
            #if DEBUG
            print(
                "[NotificationPermission] requested=true granted=false " +
                "error=\(error.localizedDescription) authorizationStatus=\(statusAfter.logToken) " +
                "willRegisterForRemoteNotifications=false previousAuthorizationStatus=\(statusBefore.logToken)"
            )
            #endif
        }
    }

    enum SecretaryProfileNotificationDeliveryToggleOutcome: Sendable, Equatable {
        case none
        case deniedInIOSSettings
        case serverDisableFailed(String)
    }

    /// Recomputes profile toggle state from iOS authorization + local opt-out.
    /// `secretaryPushNotificationDeliveryEffectiveOn` reflects permission + opt-out only — not federation token upload success.
    func refreshSecretaryPushNotificationDeliveryState(logContext: String? = nil) async {
        let auth = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let iosAllows: Bool
        switch auth {
        case .authorized, .provisional, .ephemeral:
            iosAllows = true
        case .denied, .notDetermined:
            iosAllows = false
        @unknown default:
            iosAllows = false
        }

        let optedOut = UserDefaults.standard.bool(forKey: Self.unifyPushDeliveryOptOutKey)
        let profileToggleOn = iosAllows && !optedOut
        if secretaryPushNotificationDeliveryEffectiveOn != profileToggleOn {
            secretaryPushNotificationDeliveryEffectiveOn = profileToggleOn
        }

        let registrationFailed = UserDefaults.standard.bool(forKey: Self.pushTokenRegistrationFailedKey)
        let remoteRegistrationFailed = UserDefaults.standard.bool(forKey: Self.remoteRegistrationFailedKey)
        let pending = UserDefaults.standard.string(forKey: Self.pendingAPNsTokenHexKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedContext = PushTokenRegistrationContext.read(from: UserDefaults.standard)
        let tokenHex = !pending.isEmpty ? pending : (storedContext?.tokenHex ?? "")
        let envResolved = APNsSignedEntitlementEnvironment.resolve()
        let localNodeID = await exchangeNodeID
        let tokenRegistered: Bool = {
            guard let localNodeID,
                  !localNodeID.isEmpty,
                  let uploadEnv = envResolved.uploadEnvironment?.rawValue,
                  !tokenHex.isEmpty,
                  let storedContext
            else {
                return false
            }
            let currentContext = PushTokenRegistrationContext(
                nodeID: localNodeID,
                environment: uploadEnv,
                tokenHex: tokenHex
            )
            return storedContext == currentContext
        }()
        let tokenPathOk = tokenRegistered && !registrationFailed && !remoteRegistrationFailed

        if let logContext {
            print(
                "[PushDeliveryState][\(logContext)] permissionEffective=\(profileToggleOn) " +
                "iosAllows=\(iosAllows) optedOut=\(optedOut) authorizationStatus=\(auth.logToken) " +
                "tokenPending=\(!pending.isEmpty) tokenRegistered=\(tokenRegistered) " +
                "registrationFailed=\(registrationFailed) remoteRegistrationFailed=\(remoteRegistrationFailed) " +
                "tokenPathOk=\(tokenPathOk)"
            )
        }

        #if DEBUG
        print(
            "[NotificationPermission] profileToggleOn=\(profileToggleOn) iosAllows=\(iosAllows) optedOut=\(optedOut) " +
            "tokenPathOk=\(tokenPathOk) authorizationStatus=\(auth.logToken)"
        )
        #endif
    }

    /// Profile “Your offering” notification toggle: Unify delivery (not raw iOS permission alone).
    func applySecretaryProfileNotificationDeliveryToggle(desiredOn: Bool) async -> SecretaryProfileNotificationDeliveryToggleOutcome {
        if desiredOn {
            UserDefaults.standard.set(false, forKey: Self.unifyPushDeliveryOptOutKey)
            UserDefaults.standard.set(false, forKey: Self.pushTokenRegistrationFailedKey)
            let auth = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch auth {
            case .denied:
                await refreshSecretaryPushNotificationDeliveryState()
                return .deniedInIOSSettings
            case .notDetermined:
                await requestSecretaryNotificationPermission()
                await flushPendingPushTokenRegistrationIfNeeded(reason: .permissionToggle)
                await refreshSecretaryPushNotificationDeliveryState()
                let authAfterPrompt = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                if authAfterPrompt == .denied {
                    return .deniedInIOSSettings
                }
                return .none
            case .authorized, .provisional, .ephemeral:
                let optedOut = UserDefaults.standard.bool(forKey: Self.unifyPushDeliveryOptOutKey)
                print(
                    "[APNs][RegisterAttempt] authStatus=\(auth.logToken) optedOut=\(optedOut) " +
                    "source=profileToggleOn"
                )
                UIApplication.shared.registerForRemoteNotifications()
                await flushPendingPushTokenRegistrationIfNeeded(reason: .permissionToggle)
                await refreshSecretaryPushNotificationDeliveryState()
                return .none
            @unknown default:
                await refreshSecretaryPushNotificationDeliveryState()
                return .deniedInIOSSettings
            }
        } else {
            clearPushTokenRegistrationContext()
            let disableResult = await requestUnifyPushTokenDisableOnServer()
            switch disableResult {
            case .success:
                UserDefaults.standard.set(true, forKey: Self.unifyPushDeliveryOptOutKey)
                UserDefaults.standard.set(false, forKey: Self.pushTokenRegistrationFailedKey)
                await refreshSecretaryPushNotificationDeliveryState()
                return .none
            case .failure(let message):
                await refreshSecretaryPushNotificationDeliveryState()
                return .serverDisableFailed(message)
            }
        }
    }

    private enum ServerDisablePushTokenResult: Equatable {
        case success
        case failure(String)
    }

    private func requestUnifyPushTokenDisableOnServer() async -> ServerDisablePushTokenResult {
        guard let relay = exchangeRelayClient else {
            return .failure("Federation isn’t connected yet for this device.")
        }
        guard let nodeID = await exchangeNodeID, !nodeID.isEmpty else {
            return .failure("Workspace identity isn’t ready yet. Try again in a moment.")
        }
        let tokenHex = currentAPNsTokenHexForServerOperations()
        if tokenHex.isEmpty {
            return .success
        }
        do {
            let response = try await relay.disablePushToken(nodeID: nodeID, apnsToken: tokenHex)
            guard response.ok else {
                return .failure(response.note ?? "Could not disable push token on the server.")
            }
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func currentAPNsTokenHexForServerOperations() -> String {
        let pending = UserDefaults.standard.string(forKey: Self.pendingAPNsTokenHexKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !pending.isEmpty { return pending }
        if let storedContext = PushTokenRegistrationContext.read(from: UserDefaults.standard),
           !storedContext.tokenHex.isEmpty {
            return storedContext.tokenHex
        }
        return UserDefaults.standard.string(forKey: Self.lastRegisteredAPNsTokenHexKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func clearPushTokenRegistrationContext() {
        UserDefaults.standard.removeObject(forKey: Self.lastRegisteredContextKey)
        UserDefaults.standard.removeObject(forKey: Self.lastRegisteredAPNsTokenHexKey)
    }

    private func persistPushTokenRegistrationSuccess(_ context: PushTokenRegistrationContext) {
        PushTokenRegistrationContext.write(context, to: UserDefaults.standard)
        UserDefaults.standard.set(context.tokenHex, forKey: Self.lastRegisteredAPNsTokenHexKey)
        UserDefaults.standard.set(false, forKey: Self.pushTokenRegistrationFailedKey)
        UserDefaults.standard.set(false, forKey: Self.remoteRegistrationFailedKey)
    }

    private func invalidateExchangeNodeIDCache() {
        cachedExchangeNodeID = nil
        cachedExchangeNodeIDFetchedAt = nil
    }

    /// Stores the token and attempts federation registration when `exchangeNodeID` is available.
    func handleAPNsDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let tokenHashPrefix = Self.tokenHashPrefix(hex)
        UserDefaults.standard.set(false, forKey: Self.remoteRegistrationFailedKey)
        UserDefaults.standard.set(hex, forKey: Self.pendingAPNsTokenHexKey)
        let envResolved = APNsSignedEntitlementEnvironment.resolve()
        print(
            "[APNs][RegisterSuccess] tokenHashPrefix=\(tokenHashPrefix) " +
            "signedApsEnvironment=\(envResolved.signedApsEnvironmentRaw ?? "nil") " +
            "configuredApsEnvironment=\(envResolved.configuredApsEnvironmentRaw ?? "nil") " +
            "uploadEnv=\(envResolved.uploadEnvironment?.rawValue ?? "nil")"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.flushPendingPushTokenRegistrationIfNeeded(reason: .registerSuccess)
        }
    }

    /// UIKit failed to obtain an APNs device token.
    func handleAPNsRegistrationFailure(_ error: Error) {
        UserDefaults.standard.set(true, forKey: Self.remoteRegistrationFailedKey)
        print("[APNs][RegisterFailure] error=\(error.localizedDescription)")
        Task { @MainActor [weak self] in
            await self?.refreshSecretaryPushNotificationDeliveryState(logContext: "remoteRegistrationFailed")
        }
    }

    /// Visible / alert push: federation inbox pull + reconcile; SQLite secretary notifications remain canonical after sync digests run.
    @MainActor
    func handleRemoteSecretaryNotification(userInfo: [AnyHashable: Any]) async {
        let threadID = secretaryPushThreadID(from: userInfo) ?? "nil"
        let startWall = CFAbsoluteTimeGetCurrent()
        print(
            "[SyncTrigger] trigger=manualRefresh reason=notificationTap path=syncFederationInboxNow " +
            "threadID=\(threadID)"
        )
        print("[BackgroundNotificationTapSync][start] trigger=manualRefresh")
        #if DEBUG
        let hint = secretaryPushHint(from: userInfo) ?? "(no unify.secretary hint)"
        print("[APNs] remote notification routed hint=\(hint)")
        print("[NotificationTapSync] phase=start trigger=notificationTap threadID=\(threadID)")
        #endif

        let didRun = await syncFederationInboxNow(
            requestDeskRefreshAfter: true,
            recordAttentionDigests: true,
            trigger: .manualRefresh
        )

        recordPushTriggeredSyncOutcome(
            success: didRun,
            trigger: .manualRefresh,
            source: "notificationTap"
        )

        await reconcileIOSBadgeWithSecretaryUnread(trigger: "notificationTapSync")

        stagePendingExchangeThreadPushOpenRouteAfterTap(from: userInfo)

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startWall) * 1000)
        print(
            "[BackgroundNotificationTapSync][result] didRun=\(didRun) success=\(didRun) " +
            "durationMs=\(durationMs)"
        )

        #if DEBUG
        let inboxCount = (try? await exchangeFacade.listInboxItems().count) ?? -1
        let approvalsCount = (try? await exchangeFacade.listPendingApprovals().count) ?? -1
        print(
            "[NotificationTapSync] phase=end trigger=notificationTap threadID=\(threadID) " +
            "inboxCount=\(inboxCount) approvalsCount=\(approvalsCount)"
        )
        #endif
    }

    /// Foreground alert delivery: run lightweight inbox sync without requiring a notification tap.
    func handleForegroundSecretaryPushDelivery(userInfo: [AnyHashable: Any]) {
        let threadID = secretaryPushThreadID(from: userInfo) ?? "nil"
        print("[SyncTrigger] trigger=silentPush reason=foregroundAlertDelivery threadID=\(threadID)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.handleSilentSecretaryPush(userInfo: userInfo)
        }
    }

    /// Silent / `content-available` push: **`ExchangeSyncEngine` pass only** (no seller reconcile, discovery, or embeddings).
    func handleSilentSecretaryPush(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let payloadKeys = userInfo.keys.map { "\($0)" }.sorted().joined(separator: ",")
        let secretaryKind = secretaryPushHint(from: userInfo) ?? "nil"
        print("[SyncTrigger] trigger=silentPush reason=remoteNotification payloadKeys=\(payloadKeys.isEmpty ? "none" : payloadKeys)")
        print("[SilentPushSync] phase=start trigger=silentPush secretaryKind=\(secretaryKind)")
        #if DEBUG
        let hint = secretaryPushHint(from: userInfo) ?? "(no unify.secretary hint)"
        print("[APNs] silent push begin hint=\(hint)")
        #endif

        guard exchangeRelayClient != nil else {
            recordPushTriggeredSyncOutcome(success: false, trigger: .silentPush, source: "noRelayClient")
            print("[SilentPushSync] phase=end trigger=silentPush syncResult=noRelayClient fetchResult=noData")
            return .noData
        }

        let before = await exchangeSyncEngine.currentStatus()
        await exchangeSyncEngine.runPass(trigger: .silentPush, now: Date())
        let after = await exchangeSyncEngine.currentStatus()

        if let summary = after.lastErrorSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            recordPushTriggeredSyncOutcome(success: false, trigger: .silentPush, source: "syncError")
            print(
                "[SilentPushSync] phase=end trigger=silentPush syncResult=failed fetchResult=failed " +
                "error=\(summary)"
            )
            return .failed
        }

        if after.lastCompletedAt != before.lastCompletedAt {
            recordPushTriggeredSyncOutcome(success: true, trigger: .silentPush, source: "syncRan")
            print("[SilentPushSync] phase=end trigger=silentPush syncResult=ran fetchResult=newData")
            requestSecretaryRefresh(.pushReceived)
            await reconcileIOSBadgeWithSecretaryUnread(trigger: "silentPushSync")
            return .newData
        }

        recordPushTriggeredSyncOutcome(success: false, trigger: .silentPush, source: "noChange")
        print("[SilentPushSync] phase=end trigger=silentPush syncResult=noChange fetchResult=noData")
        return .noData
    }

    func foregroundPollStableSeed() async -> UInt64 {
        let nodeID = await exchangeNodeID ?? ""
        return ExchangeForegroundSyncPolicy.stableSeed(from: nodeID)
    }

    func foregroundPollIntervalSeconds(
        routeLabel: String,
        stableSeed: UInt64 = 0,
        now: Date = Date()
    ) -> Int {
        let routeKind = exchangeForegroundSyncPolicy.routeKind(routeLabel: routeLabel)
        let recentPush = exchangeForegroundSyncPolicy.recentPushSyncSucceeded(
            lastAt: lastPushTriggeredSyncAt,
            succeeded: lastPushTriggeredSyncSucceeded,
            pushDeliveryEffective: secretaryPushNotificationDeliveryEffectiveOn,
            now: now
        )
        if stableSeed == 0 {
            return exchangeForegroundSyncPolicy.pollIntervalSeconds(
                routeKind: routeKind,
                pushDeliveryEffective: secretaryPushNotificationDeliveryEffectiveOn,
                recentPushSyncSucceeded: recentPush
            )
        }
        return exchangeForegroundSyncPolicy.jitteredPollIntervalSeconds(
            routeKind: routeKind,
            pushDeliveryEffective: secretaryPushNotificationDeliveryEffectiveOn,
            recentPushSyncSucceeded: recentPush,
            stableSeed: stableSeed
        )
    }

    func foregroundPollInitialDelaySeconds(stableSeed: UInt64) -> Int {
        exchangeForegroundSyncPolicy.jitteredInitialDelaySeconds(stableSeed: stableSeed)
    }

    func shouldSkipForegroundPollDueToRecentPushSync(routeLabel: String, now: Date = Date()) -> Bool {
        let routeKind = exchangeForegroundSyncPolicy.routeKind(routeLabel: routeLabel)
        return exchangeForegroundSyncPolicy.shouldSkipPollDueToRecentPushSync(
            routeKind: routeKind,
            lastPushSyncAt: lastPushTriggeredSyncAt,
            lastPushSyncSucceeded: lastPushTriggeredSyncSucceeded,
            pushDeliveryEffective: secretaryPushNotificationDeliveryEffectiveOn,
            now: now
        )
    }

    func shouldSkipForegroundPollDueToRecentSync(lastCompletedAt: Date?, now: Date = Date()) -> Bool {
        exchangeForegroundSyncPolicy.shouldSkipPollDueToRecentSync(
            lastCompletedAt: lastCompletedAt,
            now: now
        )
    }

    enum AutomaticFederationSyncSkipReason: String {
        case recentSync
        case inFlight
        case syncBackoff
    }

    func automaticFederationSyncSkipReason(
        trigger: ExchangeSyncEngine.Trigger,
        now: Date = Date()
    ) async -> AutomaticFederationSyncSkipReason? {
        if trigger == .manualRefresh || trigger == .silentPush {
            return nil
        }

        if await exchangeSyncEngine.isBackoffActive(now: now) {
            return .syncBackoff
        }

        let status = await exchangeSyncEngine.currentStatus()
        if status.isRunning {
            return .inFlight
        }

        if trigger == .appBecameActive {
            if exchangeForegroundSyncPolicy.shouldSkipAutomaticForegroundSync(
                lastCompletedAt: status.lastCompletedAt,
                now: now
            ) {
                return .recentSync
            }
            return nil
        }

        if exchangeForegroundSyncPolicy.shouldSkipPollDueToRecentSync(
            lastCompletedAt: status.lastCompletedAt,
            now: now
        ) {
            return .recentSync
        }

        return nil
    }

    func recordPushTriggeredSyncOutcome(
        success: Bool,
        trigger: ExchangeSyncEngine.Trigger,
        source: String,
        now: Date = Date()
    ) {
        lastPushTriggeredSyncAt = now
        lastPushTriggeredSyncSucceeded = success
        print(
            "[PushSyncCoordination] outcome=\(success ? "success" : "failure") " +
            "trigger=\(trigger.rawValue) source=\(source) " +
            "pushDeliveryEffective=\(secretaryPushNotificationDeliveryEffectiveOn)"
        )
    }

    private func secretaryPushHint(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any],
              let kind = sec["kind"] as? String
        else { return nil }
        return kind
    }

    private func secretaryPushThreadID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any]
        else { return nil }
        let thread = (sec["threadID"] as? String) ?? (sec["threadId"] as? String) ?? ""
        let trimmed = thread.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func secretaryPushConversationSurface(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any],
              let surface = sec["conversationSurface"] as? String
        else { return nil }
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func secretaryPushPayloadKind(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any],
              let kind = sec["payloadKind"] as? String
        else { return nil }
        let trimmed = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stages a one-shot exchange-thread open for `SecretaryWorkspaceView` after APNs tap inbox sync.
    @MainActor
    func stagePendingExchangeThreadPushOpenRouteAfterTap(from userInfo: [AnyHashable: Any]) {
        let secretaryKind = secretaryPushHint(from: userInfo)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if !secretaryKind.isEmpty, secretaryKind != "inbound_message" {
            return
        }

        guard let threadIDString = secretaryPushThreadID(from: userInfo),
              let threadID = UUID(uuidString: threadIDString)
        else { return }

        let surface = secretaryPushConversationSurface(from: userInfo)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let payloadKind = secretaryPushPayloadKind(from: userInfo)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let routesExchangeThread: Bool
        if surface == "exchange_thread" {
            routesExchangeThread = true
        } else if surface == "direct_message" {
            routesExchangeThread = false
        } else if payloadKind == "inquiry" || payloadKind == "introduction" {
            routesExchangeThread = true
        } else {
            return
        }

        guard routesExchangeThread else { return }

        pendingExchangeThreadPushOpenRoute = threadID
        pendingExchangeThreadPushOpenRouteGeneration &+= 1
    }

    /// Returns and clears the staged exchange-thread APNs tap route (single consumer).
    @MainActor
    func takePendingExchangeThreadPushOpenRoute() -> ExchangeThread.ID? {
        let threadID = pendingExchangeThreadPushOpenRoute
        pendingExchangeThreadPushOpenRoute = nil
        return threadID
    }

    private struct DeliveredSecretaryNotificationMatch {
        let notificationID: String
        let dedupeKey: String
        let secretaryKind: String
        let threadID: String?
        let deliveredAt: Date
    }

    private func fetchDeliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    /// Icon-open resume: if Notification Center still has a recent Unify secretary alert, force one manualRefresh sync.
    @MainActor
    private func appActiveDeliveredSecretaryNotificationSyncDecision(
        now: Date = Date()
    ) async -> (willForce: Bool, match: DeliveredSecretaryNotificationMatch?, reason: String) {
        let delivered = await fetchDeliveredNotifications()
        let deliveredCount = delivered.count

        var matchingSecretaryCount = 0
        var recentMatches: [DeliveredSecretaryNotificationMatch] = []

        for notification in delivered {
            let userInfo = notification.request.content.userInfo
            guard let kindRaw = secretaryPushHint(from: userInfo) else { continue }
            let kind = kindRaw.lowercased()
            guard Self.resumeEligibleDeliveredSecretaryKinds.contains(kind) else { continue }
            matchingSecretaryCount += 1

            let age = now.timeIntervalSince(notification.date)
            guard age >= 0, age <= Self.deliveredSecretaryNotificationMaxAge else { continue }

            let notificationID = notification.request.identifier
            recentMatches.append(
                DeliveredSecretaryNotificationMatch(
                    notificationID: notificationID,
                    dedupeKey: notificationID,
                    secretaryKind: kindRaw,
                    threadID: secretaryPushThreadID(from: userInfo),
                    deliveredAt: notification.date
                )
            )
        }

        let recentMatchingCount = recentMatches.count

        if let lastAt = lastPushTriggeredSyncAt,
           lastPushTriggeredSyncSucceeded,
           now.timeIntervalSince(lastAt) <= Self.deliveredNotificationResumeSyncDedupeWindow {
            print(
                "[AppActiveDeliveredNotificationCheck] deliveredCount=\(deliveredCount) " +
                "matchingSecretaryCount=\(matchingSecretaryCount) recentMatchingCount=\(recentMatchingCount) " +
                "willForceManualRefresh=false reason=recentPushSync"
            )
            return (false, nil, "recentPushSync")
        }

        guard let best = recentMatches.max(by: { $0.deliveredAt < $1.deliveredAt }) else {
            print(
                "[AppActiveDeliveredNotificationCheck] deliveredCount=\(deliveredCount) " +
                "matchingSecretaryCount=\(matchingSecretaryCount) recentMatchingCount=\(recentMatchingCount) " +
                "willForceManualRefresh=false reason=none"
            )
            return (false, nil, "none")
        }

        if let lastKey = lastDeliveredNotificationResumeSyncKey,
           lastKey == best.dedupeKey,
           let lastAt = lastDeliveredNotificationResumeSyncAt,
           now.timeIntervalSince(lastAt) <= Self.deliveredNotificationResumeSyncDedupeWindow {
            print(
                "[AppActiveDeliveredNotificationCheck] deliveredCount=\(deliveredCount) " +
                "matchingSecretaryCount=\(matchingSecretaryCount) recentMatchingCount=\(recentMatchingCount) " +
                "willForceManualRefresh=false reason=alreadyHandled"
            )
            return (false, best, "alreadyHandled")
        }

        print(
            "[AppActiveDeliveredNotificationCheck] deliveredCount=\(deliveredCount) " +
            "matchingSecretaryCount=\(matchingSecretaryCount) recentMatchingCount=\(recentMatchingCount) " +
            "willForceManualRefresh=true reason=recentInboundMessage"
        )
        return (true, best, "recentInboundMessage")
    }

    @MainActor
    private func runAppActiveDeliveredSecretaryNotificationSyncIfNeeded(
        nodeID: String?
    ) async -> Bool {
        let decision = await appActiveDeliveredSecretaryNotificationSyncDecision()
        guard decision.willForce, let match = decision.match else { return false }

        let startWall = CFAbsoluteTimeGetCurrent()
        print(
            "[AppActiveDeliveredNotificationSync][start] trigger=manualRefresh " +
            "reason=appActiveRecentDeliveredNotification notificationID=\(match.notificationID) " +
            "secretaryKind=\(match.secretaryKind) threadID=\(match.threadID ?? "nil")"
        )
        print(
            "[SyncTrigger] trigger=manualRefresh reason=appActiveRecentDeliveredNotification " +
            "path=syncFederationInboxNow threadID=\(match.threadID ?? "nil")"
        )

        let didRun = await syncFederationInboxNow(
            requestDeskRefreshAfter: true,
            recordAttentionDigests: true,
            trigger: .manualRefresh
        )

        recordPushTriggeredSyncOutcome(
            success: didRun,
            trigger: .manualRefresh,
            source: "appActiveRecentDeliveredNotification"
        )

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startWall) * 1000)
        print(
            "[AppActiveDeliveredNotificationSync][result] didRun=\(didRun) durationMs=\(durationMs)"
        )

        guard didRun else {
            print(
                "[AppActiveDeliveredNotificationSync][fallback] didRun=false " +
                "allowingNormalAppActivePath=true"
            )
            return false
        }

        lastDeliveredNotificationResumeSyncKey = match.dedupeKey
        lastDeliveredNotificationResumeSyncAt = Date()

        guard !Task.isCancelled else { return true }

        await refreshForYouIfEligible()

        if await pushTokenUploadNetworkSkipReason() == nil {
            let uploadReason: PushTokenUploadFlushReason =
                UserDefaults.standard.bool(forKey: Self.pushTokenRegistrationFailedKey) ? .retry : .appActive
            await flushPendingPushTokenRegistrationIfNeeded(reason: uploadReason)
        }

        await reconcileIOSBadgeWithSecretaryUnread(trigger: "appActiveDeliveredNotificationSync")

        #if DEBUG
        print(
            "[AppActiveFederationSync] phase=end exchangeNodeID=\(nodeID ?? "nil") " +
            "runResult=deliveredNotificationManualRefresh"
        )
        #endif

        return true
    }

    /// Aligns the iOS home-screen badge with canonical SQLite secretary unread (global Updates bell basis).
    @MainActor
    func reconcileIOSBadgeWithSecretaryUnread(trigger: String) async {
        let unreadCount: Int
        do {
            unreadCount = try await exchangeFacade.countGlobalSecretaryUnreadBellBadge()
        } catch {
            print(
                "[IOSBadgeReconcile] trigger=\(trigger) skip reason=queryFailed " +
                "error=\(error.localizedDescription)"
            )
            return
        }

        let applyResult = await applyIOSAppIconBadgeCount(unreadCount)
        let errorLabel = applyResult.error ?? "nil"
        print(
            "[IOSBadgeReconcile] trigger=\(trigger) unreadCount=\(unreadCount) " +
            "method=\(applyResult.method) success=\(applyResult.success) error=\(errorLabel)"
        )
    }

    private struct IOSAppIconBadgeApplyResult {
        let method: String
        let success: Bool
        let error: String?
    }

    @MainActor
    private func applyIOSAppIconBadgeCount(_ count: Int) async -> IOSAppIconBadgeApplyResult {
        let clamped = max(0, count)

        guard #available(iOS 16.0, *) else {
            return IOSAppIconBadgeApplyResult(
                method: "unsupported_pre_iOS16",
                success: false,
                error: "setBadgeCount requires iOS 16.0 or newer"
            )
        }

        let setBadgeError: Error? = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().setBadgeCount(clamped) { error in
                continuation.resume(returning: error)
            }
        }

        if let setBadgeError {
            return IOSAppIconBadgeApplyResult(
                method: "setBadgeCount",
                success: false,
                error: setBadgeError.localizedDescription
            )
        }

        return IOSAppIconBadgeApplyResult(
            method: "setBadgeCount",
            success: true,
            error: nil
        )
    }

    private func flushPendingPushTokenRegistrationIfNeeded(reason: PushTokenUploadFlushReason = .unknown) async {
        await flushPendingPushTokenRegistrationWork(reason: reason)
        await refreshSecretaryPushNotificationDeliveryState()
    }

    private func flushPendingPushTokenRegistrationWork(reason: PushTokenUploadFlushReason) async {
        let envResolved = APNsSignedEntitlementEnvironment.resolve()
        let uploadEnvRaw = envResolved.uploadEnvironment?.rawValue ?? "unknown"
        let signedAps = envResolved.signedApsEnvironmentRaw ?? "unknown"
        let configuredAps = envResolved.configuredApsEnvironmentRaw ?? "unknown"

        let pending = UserDefaults.standard.string(forKey: Self.pendingAPNsTokenHexKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tokenHashPrefix = pending.isEmpty ? "nil" : Self.tokenHashPrefix(pending)
        let localNodeID = await exchangeNodeID
        let nodePrefix = localNodeID.map { String($0.prefix(8)) }

        func logOwnership(willUpload: Bool, skipReason: String) {
            print(
                "[PushTokenUpload][ownership] localNodeID=\(localNodeID ?? "nil") " +
                "tokenHashPrefix=\(tokenHashPrefix) signedApsEnvironment=\(signedAps) " +
                "configuredApsEnvironment=\(configuredAps) uploadEnv=\(uploadEnvRaw) " +
                "reason=\(reason.rawValue) willUpload=\(willUpload) skipReason=\(skipReason)"
            )
        }

        func logSkip(skipReason: String) {
            print(
                "[PushTokenUpload][skip] nodeID=\(nodePrefix ?? "nil") env=\(uploadEnvRaw) " +
                "tokenHashPrefix=\(tokenHashPrefix) reason=\(skipReason)"
            )
        }

        func logFailure(failureReason: String) {
            print(
                "[PushTokenUpload][failure] nodeID=\(nodePrefix ?? "nil") env=\(uploadEnvRaw) " +
                "tokenHashPrefix=\(tokenHashPrefix) reason=\(failureReason)"
            )
        }

        if UserDefaults.standard.bool(forKey: Self.unifyPushDeliveryOptOutKey) {
            logOwnership(willUpload: false, skipReason: "deliveryOptOut")
            logSkip(skipReason: "deliveryOptOut")
            return
        }

        if let networkSkipReason = await pushTokenUploadNetworkSkipReason() {
            logOwnership(willUpload: false, skipReason: networkSkipReason)
            logSkip(skipReason: networkSkipReason)
            return
        }

        guard let relay = exchangeRelayClient else {
            logOwnership(willUpload: false, skipReason: "noRelay")
            logSkip(skipReason: "noRelay")
            return
        }

        guard !pending.isEmpty else {
            logOwnership(willUpload: false, skipReason: "noToken")
            logSkip(skipReason: "noToken")
            return
        }

        guard let nodeID = localNodeID, !nodeID.isEmpty else {
            logOwnership(willUpload: false, skipReason: "noNode")
            logSkip(skipReason: "noNode")
            return
        }

        guard let registrationEnv = envResolved.uploadEnvironment else {
            print(
                "[APNs][EnvironmentResolveFailed] reason=missing_or_invalid_config " +
                "configuredApsEnvironment=\(envResolved.configuredApsEnvironmentRaw ?? "nil")"
            )
            logOwnership(willUpload: false, skipReason: "environment_unresolved")
            logFailure(failureReason: "environment_unresolved")
            return
        }

        let defaults = UserDefaults.standard
        let currentContext = PushTokenRegistrationContext(
            nodeID: nodeID,
            environment: registrationEnv.rawValue,
            tokenHex: pending
        )
        let storedContext = PushTokenRegistrationContext.read(from: defaults)
        let legacyTokenHex = defaults.string(forKey: Self.lastRegisteredAPNsTokenHexKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasStoredContextKey = PushTokenRegistrationContext.hasStoredContext(in: defaults)
        let registrationFailed = defaults.bool(forKey: Self.pushTokenRegistrationFailedKey)
        let remoteRegistrationFailed = defaults.bool(forKey: Self.remoteRegistrationFailedKey)

        if !hasStoredContextKey, let legacyTokenHex, !legacyTokenHex.isEmpty {
            print("[PushTokenUpload] legacyContextMissing forcing upload tokenHashPrefix=\(tokenHashPrefix)")
        }

        let skipDecision = PushTokenRegistrationContext.shouldSkipUpload(
            current: currentContext,
            stored: storedContext,
            legacyTokenHex: legacyTokenHex,
            hasStoredContextKey: hasStoredContextKey,
            registrationFailed: registrationFailed,
            remoteRegistrationFailed: remoteRegistrationFailed
        )

        if skipDecision.skip {
            logOwnership(willUpload: false, skipReason: skipDecision.skipReason ?? "alreadyRegistered")
            logSkip(skipReason: skipDecision.skipReason ?? "alreadyRegistered")
            return
        }

        logOwnership(willUpload: true, skipReason: "none")

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let deviceID = UIDevice.current.identifierForVendor?.uuidString

        do {
            let response = try await relay.registerPushToken(
                nodeID: nodeID,
                apnsToken: pending,
                environment: registrationEnv,
                bundleID: bundleID,
                deviceID: deviceID
            )

            guard response.ok else {
                UserDefaults.standard.set(true, forKey: Self.pushTokenRegistrationFailedKey)
                logFailure(failureReason: "ok_false note=\(response.note ?? "")")
                return
            }

            persistPushTokenRegistrationSuccess(currentContext)
            print(
                "[PushTokenUpload][success] nodeID=\(nodePrefix ?? "nil") env=\(registrationEnv.rawValue) " +
                "tokenHashPrefix=\(tokenHashPrefix)"
            )
        } catch {
            UserDefaults.standard.set(true, forKey: Self.pushTokenRegistrationFailedKey)
            logFailure(failureReason: error.localizedDescription)
        }
    }

    /// Network guards for push token upload (does not block on prior federation upload failure).
    private func pushTokenUploadNetworkSkipReason() async -> String? {
        if ExchangeBootstrap.shouldSkipLaunchFederationNetworkRegistration() {
            return "ephemeral_or_invalid_federation_base_url"
        }
        if await exchangeSyncEngine.isBackoffActive() {
            return "sync_backoff_active"
        }
        return nil
    }

    // MARK: - Secretary instructions persistence

    func saveSecretaryConstitutionText(_ text: String) {
        let cleaned = SecretaryConstitutionStorage.save(text)
        secretaryConstitutionText = cleaned
        requestSecretaryRefresh(.sellerWorkspaceChanged)
    }

    func saveSecretaryStyleText(_ text: String) {
        let cleaned = SecretaryStyleTextStorage.save(text)
        secretaryStyleText = cleaned
        syncTypedSecretaryFreeformToAllThreads(cleaned.isEmpty ? nil : cleaned)
        requestSecretaryRefresh(.sellerWorkspaceChanged)
    }

    func reloadSecretaryInstructionTexts() {
        secretaryConstitutionText = SecretaryConstitutionStorage.load()
        secretaryStyleText = SecretaryStyleTextStorage.load()
    }

    // MARK: - Contact relationship context

    func getContactContext(remoteNodeID: String) -> ExchangeModels.ContactContext {
        contactContextStore.getContext(remoteNodeID: remoteNodeID)
    }

    @discardableResult
    func saveContactContext(_ context: ExchangeModels.ContactContext) -> ExchangeModels.ContactContext {
        contactContextStore.saveContext(context)
    }

    func listContactContextsByNodeID(nodeIDs: [String]) -> [String: ExchangeModels.ContactContext] {
        let wanted = Set(nodeIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var output: [String: ExchangeModels.ContactContext] = [:]
        for context in contactContextStore.listContexts() {
            let nodeID = context.remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard wanted.contains(nodeID) else { continue }
            output[nodeID] = context
        }
        return output
    }

    func suggestDirectReply(
        input: ExchangeModels.DirectReplySuggestionInput,
        userInstruction: String? = nil,
        previousSuggestions: [String] = []
    ) async -> ExchangeModels.DirectReplySuggestionOutput {
        await directChatReplySuggestionService.suggestReply(
            input: input,
            userInstruction: userInstruction,
            previousSuggestions: previousSuggestions
        )
    }

    nonisolated static func buildDirectReplySuggestionPromptForTesting(
        input: ExchangeModels.DirectReplySuggestionInput,
        latestInboundMessage: String?,
        userInstruction: String?
    ) -> String {
        DirectChatReplySuggestionPromptBuilder.buildPromptForTesting(
            input: input,
            latestInboundMessage: latestInboundMessage,
            userInstruction: userInstruction
        )
    }

    private func syncTypedSecretaryFreeformToAllThreads(_ freeformInstructions: String?) {
        Task {
            let roles: [ExchangeSecondHalfRole] = [.requester, .provider]
            let threads = (try? await exchangeStore.listThreads(filter: .init())) ?? []
            let threadIDs = Set(threads.map(\.id))

            for threadID in threadIDs {
                for role in roles {
                    var profile = (try? await secretaryStyleStore.loadStyleProfile(
                        forThreadID: threadID,
                        role: role
                    )) ?? .default
                    profile.freeformInstructions = freeformInstructions
                    try? await secretaryStyleStore.saveStyleProfile(
                        profile,
                        forThreadID: threadID,
                        role: role
                    )
                }
            }

            if let localNodeIDRaw = try? await exchangeDependencies.localNodeIDProvider?(),
               let localNodeID = ExchangeSecretaryStyleScopeID.nodeScopedUUID(from: localNodeIDRaw) {
                for role in roles {
                    var profile = (try? await secretaryStyleStore.loadStyleProfile(
                        forNodeID: localNodeID,
                        role: role
                    )) ?? .default
                    profile.freeformInstructions = freeformInstructions
                    try? await secretaryStyleStore.saveStyleProfile(
                        profile,
                        forNodeID: localNodeID,
                        role: role
                    )
                }
            }
        }
    }

    // MARK: - Autonomous For You discovery

    /// Tracks when the last **successful** For You pass completed (in-memory; mirrored to UserDefaults on success).
    private var lastForYouPassAt: Date?
    /// Last failed For You pass (in-memory; mirrored to UserDefaults on failure).
    private var lastForYouFailureAt: Date?
    /// Minimum interval between non-forced automatic For You directory passes when the rail has items.
    private static let forYouMinimumAutomaticRefreshInterval: TimeInterval = 3 * 60 * 60
    /// When the rail is empty after a pass, limits how often we immediately re-hit directory on appear/foreground.
    private static let forYouMinimumEmptyRetryInterval: TimeInterval = 45

    /// Release-visible For You lifecycle (one line per decision; no query text or node IDs).
    private func logForYouLifecycle(_ tag: String, _ message: String) {
        print("\(tag) \(message)")
    }

    private static func sanitizedForYouCacheLoadError(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? String(describing: type(of: error))
        let collapsed = raw.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return String(collapsed.prefix(120))
    }

    /// Coalesces overlapping `refreshForYouIfEligible` calls (launch + Discovery appear + foreground).
    @Published private(set) var isForYouRefreshInFlight = false

    /// Diagnostics: whether a For You directory pass is currently in flight (not a persisted contract).
    var isForYouDiscoveryPassInFlight: Bool { isForYouRefreshInFlight }

    /// Last autonomous pass outcome summary, for DEBUG visibility.
    @Published var lastAutonomousPassSummary: String?
    /// Latest For You discovery quality from the most recent autonomous pass (nil when discovery is off or pass did not run).
    @Published var forYouDiscoveryQuality: ExchangeModels.ForYouDiscoveryQuality?
    /// User-visible outcome when the latest For You pass failed (cleared on success or when discovery is off).
    @Published var forYouLastPassFailure: ForYouPassFailure?

    func saveSecretaryDiscoveryMode(_ mode: ExchangeModels.SecretaryDiscoveryMode) {
        secretaryDiscoveryMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.discoveryModeKey)
        if mode == .off {
            forYouItems = []
            forYouDiscoveryQuality = nil
            forYouLastPassFailure = nil
            lastForYouFailureAt = nil
            lastForYouPassAt = nil
            clearForYouPersistedLifecycleState()
        }
    }

    /// Resolves seller service-area CSV/chips on save/publish (local gazetteer, then optional geocoder, then H3).
    func resolveSellerServiceAreas(from csvOrChips: String) async -> ExchangeSellerServiceAreaResolveBatchResult {
        await sellerServiceAreaResolver.resolveSellerInput(csvOrChips)
    }

    func saveThreadAutonomyMode(_ mode: ExchangeModels.ExchangeThreadAutonomyMode) {
        threadAutonomyMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.threadAutonomyModeKey)
    }

    var allowSafeAutoFollowUps: Bool {
        Self.modeAllowsSafeAutoFollowUps(threadAutonomyMode)
    }

    func setAllowSafeAutoFollowUps(_ enabled: Bool) {
        if enabled {
            // Re-enable using the existing bounded autonomous-send mode unless the
            // user is already on a stricter/advanced autonomous setting.
            let resumedMode: ExchangeModels.ExchangeThreadAutonomyMode =
                threadAutonomyMode == .fullWithinBoundaries ? .fullWithinBoundaries : .routineAutoRespond
            saveThreadAutonomyMode(resumedMode)
        } else {
            saveThreadAutonomyMode(.manualOnly)
        }
    }

    static func modeAllowsSafeAutoFollowUps(_ mode: ExchangeModels.ExchangeThreadAutonomyMode) -> Bool {
        switch mode {
        case .routineAutoRespond, .fullWithinBoundaries:
            return true
        case .manualOnly, .draftOnly:
            return false
        }
    }

    /// Dismisses a For You item locally for 7 days.
    /// The nodeID is added to a UserDefaults suppression dict (same TTL/prune pattern as
    /// autonomous contacts). The item is removed from the current rail immediately.
    func dismissForYouItem(nodeID: String) {
        var current = loadDismissedForYouNodes()
        current[nodeID] = Date()
        let cutoff = Date().addingTimeInterval(-Self.forYouDismissTTL)
        current = current.filter { $0.value > cutoff }
        if let data = try? JSONEncoder().encode(current.mapValues { $0.timeIntervalSince1970 }) {
            UserDefaults.standard.set(data, forKey: Self.dismissedForYouKey)
        }
        forYouItems = forYouItems.filter { $0.nodeID != nodeID && $0.id != nodeID }
    }

    /// Opens an existing profile-anchored thread for this For You candidate or creates one locally (no outbound send).
    func connectForYouProfile(from item: ExchangeModels.ForYouItem) async throws -> ExchangeThread.ID {
        let localNodeID = await exchangeNodeID
        let threadID = try await exchangeFacade.connectForYouProfile(
            counterpartyNodeID: item.nodeID,
            publicProfileID: item.publicProfileID,
            displayName: item.displayName,
            localNodeID: localNodeID
        )
        applyForYouLinkedThreadID(nodeID: item.nodeID, itemID: item.id, threadID: threadID)
        return threadID
    }

    private func applyForYouLinkedThreadID(nodeID: String, itemID: String, threadID: ExchangeThread.ID) {
        var items = forYouItems
        guard let idx = items.firstIndex(where: { $0.nodeID == nodeID || $0.id == nodeID || $0.id == itemID }) else {
            return
        }
        var row = items[idx]
        row.linkedThreadID = threadID
        items[idx] = row
        forYouItems = items
    }

    private func loadDismissedForYouNodes() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: Self.dismissedForYouKey),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        let cutoff = Date().addingTimeInterval(-Self.forYouDismissTTL)
        return dict.mapValues { Date(timeIntervalSince1970: $0) }.filter { $0.value > cutoff }
    }

    private func loadPersistedForYouAutomaticRefreshAt() -> Date? {
        let ts = UserDefaults.standard.double(forKey: Self.forYouLastAutomaticRefreshAtKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private func persistForYouAutomaticRefreshSuccess(at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.forYouLastAutomaticRefreshAtKey)
        lastForYouPassAt = date
        lastForYouFailureAt = nil
        forYouLastPassFailure = nil
        UserDefaults.standard.removeObject(forKey: Self.forYouLastFailureAtKey)
        UserDefaults.standard.removeObject(forKey: Self.forYouLastFailureKindKey)
    }

    private func persistForYouFailure(_ failure: ForYouPassFailure) {
        lastForYouFailureAt = failure.occurredAt
        forYouLastPassFailure = failure
        UserDefaults.standard.set(failure.occurredAt.timeIntervalSince1970, forKey: Self.forYouLastFailureAtKey)
        UserDefaults.standard.set(failure.kind.rawValue, forKey: Self.forYouLastFailureKindKey)
    }

    private func clearForYouPersistedLifecycleState() {
        UserDefaults.standard.removeObject(forKey: Self.forYouLastAutomaticRefreshAtKey)
        UserDefaults.standard.removeObject(forKey: Self.forYouLastFailureAtKey)
        UserDefaults.standard.removeObject(forKey: Self.forYouLastFailureKindKey)
    }

    private func restoreForYouPersistedLifecycleState() {
        if let refreshAt = loadPersistedForYouAutomaticRefreshAt() {
            lastForYouPassAt = refreshAt
        }

        let failureTS = UserDefaults.standard.double(forKey: Self.forYouLastFailureAtKey)
        guard failureTS > 0 else { return }

        let failureAt = Date(timeIntervalSince1970: failureTS)
        lastForYouFailureAt = failureAt

        let kindRaw = UserDefaults.standard.string(forKey: Self.forYouLastFailureKindKey) ?? ""
        let kind = ForYouPassFailureKind(rawValue: kindRaw) ?? .networkOrServer
        let message: String
        switch kind {
        case .needsMoreSpecificFocus:
            message = "Add a focus so Uni knows what to look for."
        case .invalidRequest:
            message = "Couldn't refresh suggestions. Check your profile focus and try again."
        case .networkOrServer:
            message = "Couldn't refresh suggestions. Try again later."
        }
        forYouLastPassFailure = ForYouPassFailure(kind: kind, message: message, occurredAt: failureAt)
    }

    private func effectiveForYouAutomaticRefreshAnchor(now: Date = Date()) -> Date? {
        let candidates = [
            loadPersistedForYouAutomaticRefreshAt(),
            lastForYouPassAt,
            forYouItems.map(\.discoveredAt).max()
        ].compactMap { $0 }
        return candidates.max()
    }

    private func shouldSkipNonForcedForYouAutomaticRefresh(now: Date = Date()) -> Bool {
        guard !forYouItems.isEmpty else { return false }
        guard let anchor = effectiveForYouAutomaticRefreshAnchor(now: now) else { return false }
        return now.timeIntervalSince(anchor) < Self.forYouMinimumAutomaticRefreshInterval
    }

    /// Hydrates the For You rail from SQLite `cacheSource=forYou` counterparties. Does not run a directory pass.
    @MainActor
    @discardableResult
    func hydrateForYouFromExistingCacheIfNeeded(reason: String) async -> Bool {
#if DEBUG
        print("[ForYouHydration] hydrateFromCache start reason=\(reason)")
#endif
        guard secretaryDiscoveryMode == .discoverOnly else {
#if DEBUG
            print("[ForYouHydration] hydrateFromCache skipped reason=disabled")
#endif
            logForYouLifecycle("[ForYouHydrate]", "reason=\(reason) outcome=disabled")
            return false
        }

        let nodeID = await exchangeNodeID
        let forYouDismissCutoff = Date().addingTimeInterval(-Self.forYouDismissTTL)
        let dismissedForYouRaw = loadDismissedForYouNodes()
        let dismissedForYouKeys = Set(
            dismissedForYouRaw
                .filter { $0.value > forYouDismissCutoff }
                .keys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let cached: [ExchangeModels.ForYouItem]
        do {
            cached = try await exchangeFacade.loadCachedForYouItems(
                dismissedNodeIDs: dismissedForYouKeys,
                localNodeID: nodeID,
                limit: 12,
                now: Date()
            )
        } catch {
#if DEBUG
            print("[ForYouHydration] hydrateFromCache failed reason=\(reason) error=\(error)")
#endif
            logForYouLifecycle(
                "[ForYouHydrate]",
                "reason=\(reason) outcome=loadFailed area=listCounterparties err=\(Self.sanitizedForYouCacheLoadError(error))"
            )
            return false
        }

        guard !cached.isEmpty else {
#if DEBUG
            print("[ForYouHydration] hydrateFromCache empty reason=\(reason)")
#endif
            logForYouLifecycle("[ForYouHydrate]", "reason=\(reason) outcome=empty")
            return false
        }

        forYouItems = cached
        if let newest = cached.map(\.discoveredAt).max() {
            if let existing = lastForYouPassAt {
                lastForYouPassAt = max(existing, newest)
            } else {
                lastForYouPassAt = newest
            }
        }

        forYouDiscoveryQuality = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: cached.count,
                afterLocalFilterCount: cached.count,
                mixedItemCount: cached.count,
                mixedItems: cached,
                mixQualitySummary: "cached_hydration"
            )
        )

#if DEBUG
        print(
            "[ForYouHydration] hydrateFromCache assigned items=\(cached.count) reason=\(reason) " +
            "newestDiscoveredAt=\(cached.map(\.discoveredAt).max().map { "\($0)" } ?? "nil")"
        )
#endif
        logForYouLifecycle("[ForYouHydrate]", "reason=\(reason) outcome=hydrated items=\(cached.count)")
        return true
    }

    /// Runs a discovery pass (and optionally an autonomous send pass) if the current mode
    /// is not `.off`, unless `force` is true.
    ///
    /// Guards:
    /// - Minimum 3-hour interval between non-forced passes when the rail already has items.
    /// - When the rail is empty, a shorter cooldown avoids appear/foreground spamming directory/LLM
    ///   (bypassed when `force: true`).
    /// - Coalesces overlapping non-forced passes via `isForYouRefreshInFlight` (`force: true` may overlap).
    /// - Skips if device is in critical thermal or low-power state (bypassed when `force: true`).
    func refreshForYouIfEligible(force: Bool = false) async {
#if DEBUG
        print(
            "[ForYou DEBUG] federationBaseURL=\(ExchangeBootstrap.resolvedFederationBaseURL().absoluteString)"
        )
        print(
            "[ForYou DEBUG] refreshForYouIfEligible entered | force=\(force) mode=\(secretaryDiscoveryMode.rawValue) forYouItems.count=\(forYouItems.count)"
        )
#endif
        logForYouLifecycle(
            "[ForYouRefresh]",
            "phase=enter force=\(force) mode=\(secretaryDiscoveryMode.rawValue) items=\(forYouItems.count)"
        )
        guard secretaryDiscoveryMode != .off || force else {
#if DEBUG
            print("[ForYou DEBUG] refreshForYouIfEligible skipped | secretaryDiscoveryMode == .off && !force")
#endif
            logForYouLifecycle("[ForYouRefresh]", "phase=skip cause=discoveryOff items=\(forYouItems.count)")
            return
        }

        let now = Date()

        if !force, shouldSkipNonForcedForYouAutomaticRefresh(now: now) {
#if DEBUG
            let anchor = effectiveForYouAutomaticRefreshAnchor(now: now)
            let elapsed = anchor.map { now.timeIntervalSince($0) } ?? -1
            print(
                "[ForYou DEBUG] refreshForYouIfEligible skipped | forYouMinimumAutomaticRefreshInterval " +
                "elapsed=\(elapsed)s required=\(Self.forYouMinimumAutomaticRefreshInterval)s railNonEmpty=true"
            )
#endif
            let elapsedSec = Int(
                effectiveForYouAutomaticRefreshAnchor(now: now)
                    .map { now.timeIntervalSince($0) } ?? -1
            )
            logForYouLifecycle(
                "[ForYouRefresh]",
                "phase=skip cause=interval3h elapsedSec=\(elapsedSec) items=\(forYouItems.count)"
            )
            return
        }

        if !force,
           forYouItems.isEmpty,
           let last = lastForYouPassAt,
           now.timeIntervalSince(last) < Self.forYouMinimumEmptyRetryInterval {
#if DEBUG
            print(
                "[ForYou DEBUG] refreshForYouIfEligible skipped | emptyRailCooldown elapsed=\(now.timeIntervalSince(last))s required=\(Self.forYouMinimumEmptyRetryInterval)s"
            )
#endif
            logForYouLifecycle("[ForYouRefresh]", "phase=skip cause=emptyRailCooldown items=0")
            return
        }

        if !force,
           secretaryDiscoveryMode == .discoverOnly,
           forYouItems.isEmpty,
           let lastFailure = lastForYouFailureAt,
           now.timeIntervalSince(lastFailure) < Self.forYouMinimumEmptyRetryInterval {
#if DEBUG
            print(
                "[ForYouRetryGuard] skip reason=recentFailure elapsed=\(now.timeIntervalSince(lastFailure))s " +
                "required=\(Self.forYouMinimumEmptyRetryInterval)s kind=\(forYouLastPassFailure?.kind.rawValue ?? "nil")"
            )
#endif
            let failureKind = forYouLastPassFailure?.kind.rawValue ?? "unknown"
            logForYouLifecycle("[ForYouRefresh]", "phase=skip cause=recentFailure kind=\(failureKind) items=0")
            return
        }

        // Thermal/power guard: mirror the same check used by ExchangeSyncEngine.canStartRun.
        if !force {
            let runtime = await exchangeDependencies.runtimeMonitor.snapshot()
            if runtime.isThermalCritical || (runtime.isLowPowerModeEnabled && secretaryDiscoveryMode == .safeAutoSend) {
                lastAutonomousPassSummary = "Skipped — device in constrained state (\(runtime.isThermalCritical ? "thermal critical" : "low power, safeAutoSend"))."
#if DEBUG
                print(
                    "[ForYou DEBUG] refreshForYouIfEligible skipped | thermal/lowPower thermalCritical=\(runtime.isThermalCritical) lowPower=\(runtime.isLowPowerModeEnabled) safeAutoSend=\(secretaryDiscoveryMode == .safeAutoSend)"
                )
#endif
                logForYouLifecycle("[ForYouRefresh]", "phase=skip cause=thermalOrLowPower items=\(forYouItems.count)")
                return
            }
        }

        if isForYouRefreshInFlight, !force {
#if DEBUG
            print("[ForYouHydration] skipped reason=inFlight")
#endif
            logForYouLifecycle("[ForYouRefresh]", "phase=skip cause=inFlight items=\(forYouItems.count)")
            return
        }

        logForYouLifecycle("[ForYouRefresh]", "phase=run force=\(force) items=\(forYouItems.count)")
        isForYouRefreshInFlight = true
        defer { isForYouRefreshInFlight = false }

        let nodeID = await exchangeNodeID
        let contacts = loadAutonomousContacts()

        let forYouDismissCutoff = Date().addingTimeInterval(-Self.forYouDismissTTL)
        let dismissedForYouRaw = loadDismissedForYouNodes()
        let dismissedForYouKeys = Set(
            dismissedForYouRaw
                .filter { $0.value > forYouDismissCutoff }
                .keys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        var trustedForYouMixKeys: Set<String> = []
        if let source = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            if let trustedRows = try? await exchangeFacade.listTrustedNodes(sourceNodeID: source, limit: 500) {
                trustedForYouMixKeys = Set(
                    trustedRows
                        .map { $0.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
        }

        var connectedForYouMixKeys = Set(
            forYouItems.compactMap { item -> String? in
                guard item.linkedThreadID != nil else { return nil }
                let trimmed = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        for key in contacts.keys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { connectedForYouMixKeys.insert(trimmed) }
        }

        let previouslyShownForYouNodeIDs = Set(
            forYouItems
                .map { $0.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let forYouMixContext = ForYouResultMixContext(
            mode: .balanced,
            dismissedNodeIDs: dismissedForYouKeys,
            previouslySeenForYouNodeIDs: previouslyShownForYouNodeIDs,
            trustedNodeIDs: trustedForYouMixKeys,
            connectedNodeIDs: connectedForYouMixKeys
        )

        do {
#if DEBUG
            print(
                "[ForYou DEBUG] refreshForYouIfEligible about to call exchangeFacade.runAutonomousForYouPass | localNodeID=\(nodeID ?? "nil") mode=\(secretaryDiscoveryMode.rawValue) mixDismissed=\(dismissedForYouKeys.count) mixTrusted=\(trustedForYouMixKeys.count) mixConnected=\(connectedForYouMixKeys.count) mixPreviouslyShown=\(previouslyShownForYouNodeIDs.count)"
            )
#endif
            let result = try await exchangeFacade.runAutonomousForYouPass(
                localNodeID: nodeID,
                mode: secretaryDiscoveryMode,
                recentContacts: contacts,
                now: now,
                forceStandingInterestRefresh: force,
                forYouMixContext: forYouMixContext
            )

            // Update For You rail.
            // If a thread was contacted this pass, mark the item with its linkedThreadID so
            // the card can show "tap to open" instead of appearing as a stale recommendation.
            // On the next discovery pass, discoverForYou naturally filters this counterparty out.
            let dismissedKeys = dismissedForYouKeys

            var projected: [ExchangeModels.ForYouItem]
            if let contactedID = result.contactedCounterpartyID,
               let threadID = result.contactedThreadID {
                projected = result.forYouItems.map { item in
                    guard (item.nodeID) == contactedID || item.id == contactedID else { return item }
                    var updated = item
                    updated.linkedThreadID = threadID
                    return updated
                }
            } else {
                projected = result.forYouItems
            }
#if DEBUG
            print(
                "[ForYou DEBUG] refreshForYouIfEligible runAutonomousForYouPass returned | result.forYouItems.count=\(result.forYouItems.count) projected.count(beforeDismissalFilter)=\(projected.count)"
            )
#endif
            forYouItems = projected.filter { !dismissedKeys.contains($0.nodeID) && !dismissedKeys.contains($0.id) }
            forYouDiscoveryQuality = result.forYouDiscoveryQuality
            persistForYouAutomaticRefreshSuccess(at: now)
            logForYouLifecycle("[ForYouRefresh]", "phase=success items=\(forYouItems.count)")
#if DEBUG
            if let q = result.forYouDiscoveryQuality {
                let top = projected.compactMap(\.retrievalFitScore).max().map { String(format: "%.1f", $0) } ?? "nil"
                print(
                    "[ForYou DEBUG] quality=\(q.tier.rawValue) raw=\(q.rawDirectoryMatchCount) filtered=\(q.afterLocalFilterCount) resultCount=\(q.resultCount) topScore=\(top)"
                )
            }
#endif
#if DEBUG
            print(
                "[ForYou DEBUG] refreshForYouIfEligible after dismissal filter | final forYouItems.count=\(forYouItems.count)"
            )
            let imagePrefixes: [String] = forYouItems.prefix(8).compactMap { item in
                guard let raw = item.primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty
                else { return nil }
                if let url = URL(string: raw) {
                    let host = url.host ?? ""
                    let pathPrefix = String(url.path.prefix(40))
                    return "\(url.scheme ?? "?")://\(host)\(pathPrefix)"
                }
                return String(raw.prefix(64))
            }
            print("[ForYou DEBUG] refreshForYouIfEligible primaryImageURLPrefixes=\(imagePrefixes)")
            if let first = forYouItems.first {
                print(
                    "[ForYou DEBUG] refreshForYouIfEligible first item | displayName=\(first.displayName) nodeID=\(first.nodeID) discoveryFactLines.count=\(first.discoveryFactLines.count) publicFactLines.count=\(first.publicFactLines.count)"
                )
            } else {
                print("[ForYou DEBUG] refreshForYouIfEligible first item | none (forYouItems empty after filter)")
            }
#endif

            if result.sendOutcome == .queued,
               let counterpartyID = result.contactedCounterpartyID,
               let contactedAt = result.contactedAt {
                saveAutonomousContact(counterpartyID: counterpartyID, at: contactedAt)
            }

            // Build a human-readable pass summary for DEBUG visibility.
            lastAutonomousPassSummary = buildPassSummary(result: result)

            if result.contactedThreadID != nil {
                requestSecretaryRefresh(.threadChanged)
            } else {
                requestSecretaryRefresh(.forYouChanged)
            }

            await recordDiscoveryAttentionIfNeeded()
        } catch {
            lastAutonomousPassSummary = "Pass failed: \(error.localizedDescription)"
            forYouDiscoveryQuality = nil
            persistForYouFailure(Self.mapForYouPassFailure(error, occurredAt: now))
#if DEBUG
            print("[ForYou DEBUG] refreshForYouIfEligible caught error | \(error)")
            if let failure = forYouLastPassFailure {
                print(
                    "[ForYouFailureState] kind=\(failure.kind.rawValue) trigger=refreshForYouIfEligible"
                )
            }
#endif
            let failureKind = forYouLastPassFailure?.kind.rawValue ?? "unknown"
            logForYouLifecycle("[ForYouFailure]", "phase=failed kind=\(failureKind) items=\(forYouItems.count)")
        }
    }

    private static func mapForYouPassFailure(_ error: Error, occurredAt: Date) -> ForYouPassFailure {
        if let directoryError = error as? ExchangeDirectoryClientError {
            switch directoryError {
            case .invalidRequest(let reason):
                let lower = reason.lowercased()
                if lower.contains("too broad")
                    || lower.contains("specific terms")
                    || lower.contains("more specific focus") {
                    return ForYouPassFailure(
                        kind: .needsMoreSpecificFocus,
                        message: "Add a focus so Uni knows what to look for.",
                        occurredAt: occurredAt
                    )
                }
                return ForYouPassFailure(
                    kind: .invalidRequest,
                    message: "Couldn't refresh suggestions. Check your profile focus and try again.",
                    occurredAt: occurredAt
                )
            case .unavailable, .backendFailure, .rateLimited:
                return ForYouPassFailure(
                    kind: .networkOrServer,
                    message: "Couldn't refresh suggestions. Try again later.",
                    occurredAt: occurredAt
                )
            }
        }
        return ForYouPassFailure(
            kind: .networkOrServer,
            message: "Couldn't refresh suggestions. Try again later.",
            occurredAt: occurredAt
        )
    }

    /// Discovery appear / scene active: hydrate from SQLite cache first, then refresh only when due.
    @MainActor
    func ensureForYouHydratedIfNeeded(reason: String) {
#if DEBUG
        print("[ForYouHydration] ensure start reason=\(reason)")
#endif
        guard secretaryDiscoveryMode == .discoverOnly else {
#if DEBUG
            print("[ForYouHydration] skipped reason=disabled")
#endif
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hydrated = await self.hydrateForYouFromExistingCacheIfNeeded(reason: reason)
            if self.shouldSkipNonForcedForYouAutomaticRefresh() {
#if DEBUG
                print(
                    "[ForYouHydration] refresh skipped reason=\(reason) cause=automaticIntervalRailCached " +
                    "items=\(self.forYouItems.count)"
                )
#endif
                logForYouLifecycle(
                    "[ForYouLaunchGuard]",
                    "context=ensure reason=\(reason) hydrated=\(hydrated) skipRefresh=true items=\(self.forYouItems.count)"
                )
                return
            }
#if DEBUG
            print("[ForYouHydration] refresh requested reason=\(reason)")
#endif
            logForYouLifecycle(
                "[ForYouLaunchGuard]",
                "context=ensure reason=\(reason) hydrated=\(hydrated) skipRefresh=false items=\(self.forYouItems.count)"
            )
            await self.refreshForYouIfEligible(force: false)
#if DEBUG
            let count = self.forYouItems.count
            if count > 0 {
                print("[ForYouHydration] assigned items=\(count) source=refreshOrCache")
            }
#endif
        }
    }

    private func buildPassSummary(result: ExchangeModels.AutonomousPassResult) -> String {
        switch result.sendOutcome {
        case .noAction:     return "Pass: discover only. \(result.forYouItems.count) item(s) found."
        case .draftOnly:    return "Pass: draft created. Thread=\(result.contactedThreadID?.uuidString.prefix(8) ?? "—")."
        case .queued:       return "Pass: sent. Counterparty=\(result.contactedCounterpartyID?.prefix(12) ?? "—")."
        case .noCandidates: return "Pass: no eligible candidates found."
        case .cooldownActive:          return "Pass blocked: 24h cooldown active for all candidates."
        case .unsafeBoundary:          return "Pass blocked: second-half boundary was not safe."
        case .notEligible:             return "Pass blocked: send eligibility check failed."
        case .candidateBindingFailed:  return "Pass blocked: could not bind thread to candidate."
        case .disabledByThreadAutonomy:
            return "Pass blocked: thread autonomy does not allow autonomous outbound (UserDefaults secretary.threadAutonomy.mode)."
        }
    }

    private func loadAutonomousContacts() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: Self.autonomousContactsKey),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveAutonomousContact(counterpartyID: String, at date: Date) {
        var current = loadAutonomousContacts()
        current[counterpartyID] = date
        // Prune entries older than 48h to keep the dict small.
        let cutoff = Date().addingTimeInterval(-172_800)
        current = current.filter { $0.value > cutoff }
        if let data = try? JSONEncoder().encode(current.mapValues { $0.timeIntervalSince1970 }) {
            UserDefaults.standard.set(data, forKey: Self.autonomousContactsKey)
        }
    }

    // MARK: - Deferred Exchange boot

    func startDeferredExchangeBoot() {
        guard !didStartExchangeBoot else { return }
        didStartExchangeBoot = true

        exchangeBootTask?.cancel()

        exchangeBootTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Let first paint + model launch settle before heavier federation / sync side work.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            await self.refreshSecretaryPushNotificationDeliveryState(logContext: "deferredBoot")

            #if DEBUG
            let deferredSyncWall = CFAbsoluteTimeGetCurrent()
            print("[ProfileHydration] deferred sync start")
            #endif

            if let skipReason = await self.launchFederationNetworkSideWorkSkipReason() {
                #if DEBUG
                print(
                    "[FederationNetwork][skip] phase=deferredBoot registerNode=true pushToken=true " +
                    "reason=\(skipReason)"
                )
                #endif
            } else {
                await self.registerLocalFederationNodePresence()
            }

            #if DEBUG
            await self.seedExchangeDebugDataIfNeeded()
            #endif

            guard !Task.isCancelled else { return }

            await self.exchangeSyncEngine.runPass(
                trigger: .appLaunch,
                now: Date()
            )

            guard !Task.isCancelled else { return }

            await self.reconcileSellerSurfacePublicationIfPossible()
            #if DEBUG
            await self.refreshExchangeIdentityDebugSummary()
            #endif

            #if DEBUG
            let deferredMs = Int((CFAbsoluteTimeGetCurrent() - deferredSyncWall) * 1000)
            print("[ProfileHydration] deferred sync end durationMs=\(deferredMs)")
            #endif

            guard !Task.isCancelled else { return }

            await self.runExchangeLocalMaintenanceIfNeeded(reason: "deferred_boot_after_sync")

            let hydrated = await self.hydrateForYouFromExistingCacheIfNeeded(reason: "deferredBoot")
            if self.shouldSkipNonForcedForYouAutomaticRefresh() {
#if DEBUG
                print(
                    "[ForYouHydration] deferredBoot refresh skipped cause=automaticIntervalRailCached " +
                    "items=\(self.forYouItems.count)"
                )
#endif
                logForYouLifecycle(
                    "[ForYouLaunchGuard]",
                    "context=deferredBoot hydrated=\(hydrated) skipRefresh=true items=\(self.forYouItems.count)"
                )
            } else {
                logForYouLifecycle(
                    "[ForYouLaunchGuard]",
                    "context=deferredBoot hydrated=\(hydrated) skipRefresh=false items=\(self.forYouItems.count)"
                )
                await self.refreshForYouIfEligible(force: false)
            }

            if await self.launchFederationNetworkSideWorkSkipReason() == nil {
                let uploadReason: PushTokenUploadFlushReason =
                    UserDefaults.standard.bool(forKey: Self.pushTokenRegistrationFailedKey) ? .retry : .startup
                await self.flushPendingPushTokenRegistrationIfNeeded(reason: uploadReason)
            }

            self.requestSecretaryRefresh(.appLaunch)

            #if DEBUG
            ExchangeE2EGate.logBlockedLaunchAutomationIfConfigured()
            #endif
        }
    }

    // MARK: - Exchange local maintenance

    private static let exchangeLocalMaintenanceLastRunKey = "exchange.localMaintenance.lastRunAt"
    private static let exchangeLocalMaintenanceMinInterval: TimeInterval = 24 * 3_600

    /// Explicit local SQLite pruning for Secretary/Exchange tables. Does not touch threads/turns or remote server data.
    func runExchangeLocalMaintenance(reason: String, force: Bool = false) async {
        guard let sqliteStore = exchangeStore as? ExchangeSQLiteStore else {
            #if DEBUG
            print("[AppServices][ExchangeLocalMaintenance] skipped — store is not ExchangeSQLiteStore")
            #endif
            return
        }

        if !force,
           let lastRun = UserDefaults.standard.object(forKey: Self.exchangeLocalMaintenanceLastRunKey) as? Date,
           Date().timeIntervalSince(lastRun) < Self.exchangeLocalMaintenanceMinInterval {
            return
        }

        do {
            let localNodeID = await exchangeNodeID
            let policy = ExchangeLocalMaintenancePolicy(localNodeID: localNodeID)
            let result = try await ExchangeLocalMaintenance.run(
                on: sqliteStore,
                policy: policy,
                reason: reason
            )
            UserDefaults.standard.set(result.completedAt, forKey: Self.exchangeLocalMaintenanceLastRunKey)
            let tables = ExchangeLocalMaintenanceTable.allCases
                .map { "\($0.rawValue)=\(result.deletedCount(for: $0))" }
                .joined(separator: " ")
            print("[AppServices][ExchangeLocalMaintenance] reason=\(reason) \(tables) total=\(result.totalDeleted)")
        } catch {
            print("[AppServices][ExchangeLocalMaintenance] reason=\(reason) failed: \(error)")
        }
    }

    private func runExchangeLocalMaintenanceIfNeeded(reason: String) async {
        await runExchangeLocalMaintenance(reason: reason, force: false)
    }

    // MARK: - Exchange thread hard delete (local only)

    /// Hard-deletes one Exchange thread and linked local rows on this device. Does not delete remote relay data or reset federation identity.
    @discardableResult
    func hardDeleteThreadLocally(threadID: ExchangeThread.ID) async -> ExchangeThreadLocalDeleteReport? {
        let existingThread = try? await exchangeStore.fetchThread(id: threadID)

        do {
            guard let report = try await exchangeFacade.hardDeleteThreadLocally(threadID: threadID) else {
                print("[AppServices][HardDeleteThread] threadID=\(threadID.uuidString) notFound")
                return nil
            }

            if let existingThread {
                await ExchangeDirectMessageThreadLocalCleanup.clearConversationWatermarkIfNoRemainingThread(
                    deletedThread: existingThread,
                    store: exchangeStore
                )
            }

            let tables = ExchangeThreadLocalDeleteTable.allCases
                .map { "\($0.rawValue)=\(report.deletedCount(for: $0))" }
                .joined(separator: " ")
            print(
                "[AppServices][HardDeleteThread] threadID=\(threadID.uuidString) " +
                "\(tables) total=\(report.totalDeleted) note=local_only_not_remote"
            )

            requestSecretaryRefresh(.threadChanged)
            return report
        } catch {
            print("[AppServices][HardDeleteThread] threadID=\(threadID.uuidString) failed: \(error)")
            return nil
        }
    }

    /// Local-only seller snapshot for Profile: runs before federation registration, sync, and reconcile.
    private func hydrateSellerWorkspaceEarlyForLocalProfileIfPossible() async {
        #if DEBUG
        let wall = CFAbsoluteTimeGetCurrent()
        print("[ProfileHydration] early hydrate start")
        #endif

        guard let nodeID = await exchangeNodeID, !nodeID.isEmpty else {
            #if DEBUG
            print("[ProfileHydration] early hydrate localNodeID available=false skip")
            #endif
            return
        }

        #if DEBUG
        print("[ProfileHydration] early hydrate localNodeID available=true")
        #endif

        await refreshSellerWorkspace()

        #if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)
        print("[ProfileHydration] early hydrate await refreshSellerWorkspace done durationMs=\(elapsedMs)")
        #endif
    }

    #if DEBUG
    private func seedExchangeDebugDataIfNeeded() async {
        guard ExchangeBootstrap.isDebugExchangeSeedAllEnabled() else {
            print("[AppServices] Exchange debug seed skipped — set UNIFY_DEBUG_EXCHANGE_SEED_ALL=1 to enable")
            return
        }
        do {
            let seeder = ExchangeDebugSeeder(store: self.exchangeStore)
            try await seeder.seedAll()
            print("[AppServices] Exchange debug seed complete")
        } catch {
            print("[AppServices] Exchange debug seed failed: \(error)")
        }
    }
    #endif

    /// Counts for mailbox digest observers — prefers committed desk snapshot to avoid duplicate facade walks.
    private func secretaryMailboxDigestCounts() async -> SecretaryMailboxDigestCounts {
        if let snapshot = secretaryDeskSnapshot {
            let counts = SecretaryMailboxDigestCounts(
                inbox: snapshot.visibleInboxItems.count,
                pending: snapshot.pendingApprovals.count
            )
            lastCommittedMailboxDigestCounts = counts
            return counts
        }
        let inbox = (try? await exchangeFacade.listInboxItems().count) ?? 0
        let pending = (try? await exchangeFacade.listPendingApprovals(forDeskSnapshot: true).count) ?? 0
        let counts = SecretaryMailboxDigestCounts(inbox: inbox, pending: pending)
        lastCommittedMailboxDigestCounts = counts
        return counts
    }

    /// Launch-time guard for directory registration (non-blocking when skipped).
    private func launchFederationNetworkSideWorkSkipReason() async -> String? {
        if ExchangeBootstrap.shouldSkipLaunchFederationNetworkRegistration() {
            return "ephemeral_or_invalid_federation_base_url"
        }
        if await exchangeSyncEngine.isBackoffActive() {
            return "sync_backoff_active"
        }
        return nil
    }

    // MARK: - Exchange identity helpers

    var exchangeNodeID: String? {
        get async {
            if let cached = cachedExchangeNodeID,
               let fetchedAt = cachedExchangeNodeIDFetchedAt,
               Date().timeIntervalSince(fetchedAt) < Self.exchangeNodeIDCacheTTL {
                return cached
            }

            do {
                let identityService = BootstrappedIdentityService()
                let identity = try await identityService.localIdentity()
                let nodeID = identity.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = nodeID.isEmpty ? nil : nodeID
                cachedExchangeNodeID = normalized
                cachedExchangeNodeIDFetchedAt = Date()
                return normalized
            } catch {
                print("[AppServices] exchangeNodeID lookup failed: \(error)")
                return nil
            }
        }
    }

    /// DM live receive: skip federation pull when offline guards apply or scene is inactive.
    func directMessageReceiveLiveSyncSkipReason(isSceneActive: Bool) async -> String? {
        if !isSceneActive {
            return "sceneInactive"
        }
        if await launchFederationNetworkSideWorkSkipReason() != nil {
            return "backoffOrUnavailable"
        }
        if await automaticFederationSyncSkipReason(trigger: .appBecameActive) == .syncBackoff {
            return "backoffOrUnavailable"
        }
        return nil
    }

    func refreshExchangeIdentityDebugSummary() async {
        do {
            let identityService = BootstrappedIdentityService()
            let identity = try await identityService.localIdentity()
            let nodeID = identity.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)

            let localProfiles = try await exchangeStore.listPublicProfiles(
                filter: .init(nodeID: nodeID, limit: 1)
            )
            let localOffers = try await exchangeStore.listOffers(
                filter: .init(nodeID: nodeID, limit: nil)
            )
            let localThreads = try await exchangeStore.listThreads(
                filter: .init(limit: nil)
            )
            let localInbox = try await exchangeStore.listInboxItems(
                filter: .init(limit: nil)
            )

            let dbURL = Self.makeExchangeDatabaseURL()
            let dbExists = FileManager.default.fileExists(atPath: dbURL.path)
            let databaseStatus = dbExists ? "available" : "missing"

            let hasProfile = !localProfiles.isEmpty
            let offerCount = localOffers.count
            let threadCount = localThreads.count
            let inboxCount = localInbox.count
            let restoredEmpty = hasProfile == false && offerCount == 0 && threadCount == 0

            await MainActor.run {
                self.exchangeIdentityDebugSummary = ExchangeIdentityDebugSummary(
                    nodeID: nodeID,
                    publicKeyID: identity.publicKeyID,
                    displayName: identity.displayName,
                    sourceLabel: "Keychain",
                    localProfileExists: hasProfile,
                    localOfferCount: offerCount,
                    localThreadCount: threadCount,
                    localInboxCount: inboxCount,
                    sellerWorkspaceExists: self.sellerWorkspace != nil,
                    databaseStatus: databaseStatus,
                    databasePath: dbURL.path,
                    restoredIdentityWithEmptyLocalStore: restoredEmpty,
                    restoredMessage: restoredEmpty
                        ? "Node identity was restored, but local Exchange history appears empty."
                        : nil
                )
            }
        } catch {
            await MainActor.run {
                self.exchangeIdentityDebugSummary = ExchangeIdentityDebugSummary(
                    nodeID: nil,
                    publicKeyID: nil,
                    displayName: nil,
                    sourceLabel: "Keychain",
                    localProfileExists: false,
                    localOfferCount: 0,
                    localThreadCount: 0,
                    localInboxCount: 0,
                    sellerWorkspaceExists: self.sellerWorkspace != nil,
                    databaseStatus: "unavailable",
                    databasePath: Self.makeExchangeDatabaseURL().path,
                    restoredIdentityWithEmptyLocalStore: false,
                    restoredMessage: "Unable to load Exchange identity debug summary."
                )
            }
        }
    }

    #if DEBUG
    private func beginManualE2ERun(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode
    ) -> String? {
        guard ExchangeE2EGate.shouldRun(trigger: trigger) else {
            ExchangeE2EGate.logBlocked(trigger: trigger)
            return nil
        }
        guard let source = ExchangeE2EGate.manualSource(from: trigger) else {
            ExchangeE2EGate.logBlocked(trigger: trigger)
            return nil
        }
        ExchangeE2EGate.logAllowed(source: source)
        ExchangeE2EGate.logRunStart(source: source, mode: mode)
        return source
    }

    private func finishManualE2ERun(source: String, result: String) {
        ExchangeE2EGate.logRunDone(source: source, result: result)
    }

    /// Runs 20 fixed search prompts through the live on-device `searchIntentExtraction` path.
    /// Writes JSONL to Documents/Artifacts and logs each row to the console.
    func runSearchIntentExtractionSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .retrievalOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isSearchIntentSmokeAuditRunning else { return }
        guard let extractor = exchangeDependencies.asyncSearchIntentExtractor else {
            searchIntentSmokeAuditStatus = "asyncSearchIntentExtractor is not wired."
            finishManualE2ERun(source: source, result: "extractor_not_wired")
            return
        }

        isSearchIntentSmokeAuditRunning = true
        searchIntentSmokeAuditStatus = "Running \(SearchIntentExtractionSmokeAuditPrompts.all.count) on-device search-intent prompts…"
        defer { isSearchIntentSmokeAuditRunning = false }

        print("[SearchIntentSmokeAudit] begin prompts=\(SearchIntentExtractionSmokeAuditPrompts.all.count)")
        let rows = await SearchIntentExtractionSmokeAuditSupport.run(extractor: extractor)
        let artifactURL = Self.searchIntentSmokeAuditArtifactURL

        do {
            try SearchIntentExtractionSmokeAuditSupport.writeJSONL(rows: rows, to: artifactURL)
            let succeeded = rows.filter(\.success).count
            searchIntentSmokeAuditLastArtifactURL = artifactURL
            searchIntentSmokeAuditStatus =
                "Done: \(succeeded)/\(rows.count) succeeded. JSONL: \(artifactURL.lastPathComponent)"
            print(
                "[SearchIntentSmokeAudit] complete succeeded=\(succeeded)/\(rows.count) " +
                "artifact=\(artifactURL.path)"
            )
            finishManualE2ERun(source: source, result: searchIntentSmokeAuditStatus ?? "done")
        } catch {
            searchIntentSmokeAuditStatus = "Smoke audit failed to write JSONL: \(error.localizedDescription)"
            print("[SearchIntentSmokeAudit] write failed error=\(error)")
            finishManualE2ERun(source: source, result: "write_failed")
        }
    }

    private static var searchIntentSmokeAuditArtifactURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("search_intent_on_device_smoke_audit.jsonl", isDirectory: false)
    }

    /// Runs 10 fixed app search queries through the live ExchangeFacade submit path against localhost federation.
    func runAppSearchSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isAppSearchSmokeRunning else { return }

        isAppSearchSmokeRunning = true
        appSearchSmokeStatus = "Running app search smoke (10 queries)…"
        defer { isAppSearchSmokeRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(mode) {
                let baseURL = try ExchangeAppSearchSmokeGate.validateForManualRun()
                try await ExchangeAppSearchSmokeGate.preflight(baseURL: baseURL)

                print("[AppSearchSmoke] begin queries=\(ExchangeAppSearchSmokeScenarios.mandatory.count) baseURL=\(baseURL.absoluteString)")
                let result = try await ExchangeAppSearchSmokeAuditSupport.run(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                appSearchSmokeLastReport = result.aggregateReportText
                if let path = result.artifactPath {
                    appSearchSmokeLastArtifactURL = URL(fileURLWithPath: path)
                }

                let strictPass = result.runs.filter { $0.strictPassed }.count
                let engineThread = result.runs.filter { !$0.engineVsThreadMismatch.isEmpty }.count
                let threadUI = result.runs.filter { !$0.threadVsUIMismatch.isEmpty }.count
                appSearchSmokeStatus =
                    "Done: strictPass=\(strictPass)/\(result.runs.count) engineVsThread=\(engineThread) threadVsUI=\(threadUI)"
                print("[AppSearchSmoke] complete \(appSearchSmokeStatus ?? "")")
                finishManualE2ERun(source: source, result: appSearchSmokeStatus ?? "done")
            }
        } catch {
            appSearchSmokeStatus = "App search smoke failed: \(error)"
            print("[AppSearchSmoke] failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    private static var appSearchSmokeAuditArtifactURL: URL {
        ExchangeAppSearchSmokeAuditSupport.defaultArtifactURL()
    }

    /// Runs 5 natural-language retrieval E2E queries through the live ExchangeFacade submit path.
    func runRetrievalE2ESmoke(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isRetrievalE2ESmokeRunning else { return }

        isRetrievalE2ESmokeRunning = true
        retrievalE2ESmokeStatus = "Running retrieval E2E smoke (5 queries)…"
        defer { isRetrievalE2ESmokeRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(mode) {
                ExchangeBootstrap.logFederationBaseURLAtStartup()
                let resolvedConfig = ExchangeBootstrap.resolvedFederationBaseURLConfiguration()
                print(
                    "[RetrievalE2E] preflight federationConfig baseURL=\(resolvedConfig.url.absoluteString) source=\(resolvedConfig.source.rawValue)"
                )
                let baseURL = try ExchangeRetrievalE2EGate.validateForManualRun()
                try await ExchangeRetrievalE2EGate.preflight(baseURL: baseURL)

                print("[RetrievalE2E] START")
                print("[RetrievalE2E] begin queries=\(ExchangeRetrievalE2EScenarios.mandatory.count) baseURL=\(baseURL.absoluteString)")
                let result = try await ExchangeRetrievalE2EAuditSupport.run(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    executionMode: mode,
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                retrievalE2ESmokeLastReport = result.aggregateReportText
                if let path = result.artifactPath {
                    retrievalE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                }

                let passCount = result.runs.filter { $0.passed }.count
                retrievalE2ESmokeStatus = "Done: pass=\(passCount)/\(result.runs.count)"
                print("[RetrievalE2E] complete \(retrievalE2ESmokeStatus ?? "")")
                finishManualE2ERun(source: source, result: retrievalE2ESmokeStatus ?? "done")
            }
        } catch let preflight as RetrievalE2EPreflightFailure {
            retrievalE2ESmokeStatus = "Retrieval E2E preflight failed: \(preflight)"
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=\(preflight.logReason)")
            finishManualE2ERun(source: source, result: "preflight_failed")
        } catch {
            retrievalE2ESmokeStatus = "Retrieval E2E smoke failed: \(error)"
            print("[RetrievalE2E] failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    /// Runs one Chinese→English multilingual retrieval E2E scenario through the live ExchangeFacade submit path.
    func runMultilingualRetrievalE2ESmoke(
        trigger: ExchangeE2ETrigger,
        mode: MultilingualRetrievalE2EMode = .injectedCarrierFixture,
        executionMode: ExchangeE2EMode = .discoveryOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: executionMode) else { return }
        guard !isMultilingualE2ESmokeRunning else { return }

        isMultilingualE2ESmokeRunning = true
        multilingualE2ESmokeStatus = "Running multilingual retrieval E2E smoke (\(mode.rawValue))…"
        defer { isMultilingualE2ESmokeRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(executionMode) {
                ExchangeBootstrap.logFederationBaseURLAtStartup()
                let baseURL = try ExchangeRetrievalE2EGate.validateForManualRun()
                try await MultilingualRetrievalE2EAuditSupport.preflightFederation(
                    baseURL: baseURL,
                    runModes: [mode]
                )

                print("[MultilingualE2E] START mode=\(mode.rawValue) executionMode=\(executionMode.rawValue) baseURL=\(baseURL.absoluteString)")
                let intelligenceProvider = exchangeDependencies.intelligenceProvider
                let liveEnricherDependencies = multilingualLiveEnricherDependencies()
                let fullFacadeDependencies = multilingualFullFacadeDependencies()
                let result = try await MultilingualRetrievalE2EAuditSupport.run(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    runMode: mode,
                    executionMode: executionMode,
                    liveEnricherDependencies: { liveEnricherDependencies },
                    fullFacadeDependencies: { fullFacadeDependencies },
                    intelligenceProvider: { intelligenceProvider },
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                multilingualE2ESmokeLastReport = result.aggregateReportText
                if let path = result.artifactPath {
                    multilingualE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                }

                let passCount = result.runs.filter(\.passed).count
                multilingualE2ESmokeStatus = "Done (\(mode.rawValue)): pass=\(passCount)/\(result.runs.count)"
                print("[MultilingualE2E] complete \(multilingualE2ESmokeStatus ?? "")")
                finishManualE2ERun(source: source, result: multilingualE2ESmokeStatus ?? "done")
            }
        } catch let preflight as RetrievalE2EPreflightFailure {
            multilingualE2ESmokeStatus = "Multilingual E2E preflight failed: \(preflight)"
            print("[MultilingualE2E] PRE_FLIGHT_FAIL reason=\(preflight.logReason)")
            finishManualE2ERun(source: source, result: "preflight_failed")
        } catch {
            multilingualE2ESmokeStatus = "Multilingual E2E smoke failed: \(error)"
            print("[MultilingualE2E] failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    /// Runs injected baseline and live enricher modes back-to-back with a comparison summary.
    func runMultilingualRetrievalE2ESmokePair(
        trigger: ExchangeE2ETrigger,
        executionMode: ExchangeE2EMode = .discoveryOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: executionMode) else { return }
        guard !isMultilingualE2ESmokeRunning else { return }

        isMultilingualE2ESmokeRunning = true
        multilingualE2ESmokeStatus = "Running multilingual retrieval E2E paired comparison…"
        defer { isMultilingualE2ESmokeRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(executionMode) {
                ExchangeBootstrap.logFederationBaseURLAtStartup()
                let baseURL = try ExchangeRetrievalE2EGate.validateForManualRun()
                try await MultilingualRetrievalE2EAuditSupport.preflightFederationForPairComparison(
                    baseURL: baseURL
                )

                print("[MultilingualE2E] START pair baseURL=\(baseURL.absoluteString)")
                let intelligenceProvider = exchangeDependencies.intelligenceProvider
                let liveEnricherDependencies = multilingualLiveEnricherDependencies()
                let fullFacadeDependencies = multilingualFullFacadeDependencies()
                let pair = try await MultilingualRetrievalE2EAuditSupport.runPair(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    executionMode: executionMode,
                    liveEnricherDependencies: { liveEnricherDependencies },
                    fullFacadeDependencies: { fullFacadeDependencies },
                    intelligenceProvider: { intelligenceProvider },
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                multilingualE2ESmokeLastReport = [
                    pair.baseline.aggregateReportText,
                    pair.live.aggregateReportText,
                    pair.comparison.summaryLines.joined(separator: "\n")
                ].joined(separator: "\n")
                if let path = pair.comparisonArtifactPath {
                    multilingualE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                } else if let path = pair.baseline.artifactPath {
                    multilingualE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                }

                let baselinePass = pair.baseline.runs.filter(\.passed).count
                let livePass = pair.live.runs.filter(\.passed).count
                multilingualE2ESmokeStatus =
                    "Done pair: baseline=\(baselinePass)/\(pair.baseline.runs.count) live=\(livePass)/\(pair.live.runs.count)"
                print("[MultilingualE2E] complete \(multilingualE2ESmokeStatus ?? "")")
                finishManualE2ERun(source: source, result: multilingualE2ESmokeStatus ?? "done")
            }
        } catch let preflight as RetrievalE2EPreflightFailure {
            multilingualE2ESmokeStatus = "Multilingual E2E preflight failed: \(preflight)"
            print("[MultilingualE2E] PRE_FLIGHT_FAIL reason=\(preflight.logReason)")
            finishManualE2ERun(source: source, result: "preflight_failed")
        } catch {
            multilingualE2ESmokeStatus = "Multilingual E2E pair failed: \(error)"
            print("[MultilingualE2E] pair failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    /// Runs injected baseline, live enricher, and full facade publish modes with a triple comparison summary.
    func runMultilingualRetrievalE2ESmokeTriple(
        trigger: ExchangeE2ETrigger,
        executionMode: ExchangeE2EMode = .discoveryOnly
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: executionMode) else { return }
        guard !isMultilingualE2ESmokeRunning else { return }

        isMultilingualE2ESmokeRunning = true
        multilingualE2ESmokeStatus = "Running multilingual retrieval E2E triple comparison…"
        defer { isMultilingualE2ESmokeRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(executionMode) {
                ExchangeBootstrap.logFederationBaseURLAtStartup()
                let baseURL = try ExchangeRetrievalE2EGate.validateForManualRun()
                try await MultilingualRetrievalE2EAuditSupport.preflightFederationForTripleComparison(
                    baseURL: baseURL
                )

                print("[MultilingualE2E] START triple baseURL=\(baseURL.absoluteString)")
                let intelligenceProvider = exchangeDependencies.intelligenceProvider
                let liveEnricherDependencies = multilingualLiveEnricherDependencies()
                let fullFacadeDependencies = multilingualFullFacadeDependencies()
                let triple = try await MultilingualRetrievalE2EAuditSupport.runTriple(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    executionMode: executionMode,
                    liveEnricherDependencies: { liveEnricherDependencies },
                    fullFacadeDependencies: { fullFacadeDependencies },
                    intelligenceProvider: { intelligenceProvider },
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                multilingualE2ESmokeLastReport = [
                    triple.baseline.aggregateReportText,
                    triple.live.aggregateReportText,
                    triple.fullFacade.aggregateReportText,
                    triple.comparison.summaryLines.joined(separator: "\n")
                ].joined(separator: "\n")
                if let path = triple.comparisonArtifactPath {
                    multilingualE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                } else if let path = triple.baseline.artifactPath {
                    multilingualE2ESmokeLastArtifactURL = URL(fileURLWithPath: path)
                }

                let baselinePass = triple.baseline.runs.filter(\.passed).count
                let livePass = triple.live.runs.filter(\.passed).count
                let fullFacadePass = triple.fullFacade.runs.filter(\.passed).count
                multilingualE2ESmokeStatus =
                    "Done triple: baseline=\(baselinePass)/\(triple.baseline.runs.count) live=\(livePass)/\(triple.live.runs.count) fullFacade=\(fullFacadePass)/\(triple.fullFacade.runs.count)"
                print("[MultilingualE2E] complete \(multilingualE2ESmokeStatus ?? "")")
                finishManualE2ERun(source: source, result: multilingualE2ESmokeStatus ?? "done")
            }
        } catch let preflight as RetrievalE2EPreflightFailure {
            multilingualE2ESmokeStatus = "Multilingual E2E preflight failed: \(preflight)"
            print("[MultilingualE2E] PRE_FLIGHT_FAIL reason=\(preflight.logReason)")
            finishManualE2ERun(source: source, result: "preflight_failed")
        } catch {
            multilingualE2ESmokeStatus = "Multilingual E2E triple failed: \(error)"
            print("[MultilingualE2E] triple failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    /// Runs 10 live multilingual subset scenarios (5 verticals × 2 language pairs) through ExchangeFacade.
    func runMultilingualLiveSubsetSmoke(
        trigger: ExchangeE2ETrigger,
        runMode: MultilingualRetrievalE2EMode = .livePublishEnricher,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        includeFullFacadeFirstScenario: Bool = false
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: executionMode) else { return }
        guard !isMultilingualLiveSubsetRunning else { return }

        isMultilingualLiveSubsetRunning = true
        multilingualLiveSubsetStatus = "Running multilingual live subset (\(MultilingualSecretaryLiveSubsetFixtures.all.count) scenarios)…"
        defer { isMultilingualLiveSubsetRunning = false }

        do {
            try await ExchangeE2EActiveRun.withMode(executionMode) {
                ExchangeBootstrap.logFederationBaseURLAtStartup()
                let baseURL = try ExchangeRetrievalE2EGate.validateForManualRun()
                var liveSubsetModes = [runMode]
                if includeFullFacadeFirstScenario {
                    liveSubsetModes.append(.fullFacadePublishPath)
                }
                try await MultilingualRetrievalE2EAuditSupport.preflightFederation(
                    baseURL: baseURL,
                    runModes: liveSubsetModes
                )

                print("[MultilingualLiveSubset] START mode=\(runMode.rawValue) executionMode=\(executionMode.rawValue) baseURL=\(baseURL.absoluteString)")
                let intelligenceProvider = exchangeDependencies.intelligenceProvider
                let liveEnricherDependencies = multilingualLiveEnricherDependencies()
                let fullFacadeDependencies = multilingualFullFacadeDependencies()
                let result = try await MultilingualSecretaryLiveSubsetRunner.run(
                    facade: exchangeFacade,
                    baseURL: baseURL,
                    runMode: runMode,
                    executionMode: executionMode,
                    includeFullFacadeFirstScenario: includeFullFacadeFirstScenario,
                    liveEnricherDependencies: { liveEnricherDependencies },
                    fullFacadeDependencies: { fullFacadeDependencies },
                    intelligenceProvider: { intelligenceProvider },
                    captureUIProjection: { detail in
                        AppSearchSmokeUIProjectionCapture.capture(from: detail)
                    }
                )

                multilingualLiveSubsetLastReport = result.aggregateReportText
                if let path = result.artifactPath {
                    multilingualLiveSubsetLastArtifactURL = URL(fileURLWithPath: path)
                }
                multilingualLiveSubsetStatus =
                    "Done live subset: pass=\(result.summary.passCount)/\(result.records.count) warnings=\(result.summary.warningCount)"
                print("[MultilingualLiveSubset] complete \(multilingualLiveSubsetStatus ?? "")")
                finishManualE2ERun(source: source, result: multilingualLiveSubsetStatus ?? "done")
            }
        } catch let preflight as RetrievalE2EPreflightFailure {
            multilingualLiveSubsetStatus = "Multilingual live subset preflight failed: \(preflight)"
            print("[MultilingualLiveSubset] PRE_FLIGHT_FAIL reason=\(preflight.logReason)")
            finishManualE2ERun(source: source, result: "preflight_failed")
        } catch {
            multilingualLiveSubsetStatus = "Multilingual live subset failed: \(error)"
            print("[MultilingualLiveSubset] failed error=\(error)")
            finishManualE2ERun(source: source, result: "error=\(error.localizedDescription)")
        }
    }

    private func multilingualLiveEnricherDependencies() -> MultilingualRetrievalE2EAuditSupport.LiveEnricherDependencies {
        MultilingualRetrievalE2EAuditSupport.LiveEnricherDependencies(
            indexedSurfaceEnricher: exchangeDependencies.indexedSurfaceEnricher,
            diagnosticsStore: requireExchangeGraph().providerSurfaceDiagnosticsStore
        )
    }

    private func multilingualFullFacadeDependencies() -> MultilingualRetrievalE2EFullFacadePublishSeeder.Dependencies? {
        guard let directoryClient = exchangeDependencies.directoryClient else { return nil }
        return MultilingualRetrievalE2EFullFacadePublishSeeder.Dependencies(
            directoryClient: directoryClient,
            diagnosticsStore: requireExchangeGraph().providerSurfaceDiagnosticsStore
        )
    }

    /// Runs fixed requester/profile gap fixtures through the live on-device `requesterMatchCompare` path.
    func runRequesterGapOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isRequesterGapSmokeAuditRunning else { return }
        guard let onDevice = exchangeDependencies.intelligenceProvider as? OnDeviceExchangeIntelligenceProvider else {
            requesterGapSmokeAuditStatus = "OnDeviceExchangeIntelligenceProvider is not wired."
            finishManualE2ERun(source: source, result: "provider_not_wired")
            return
        }

        isRequesterGapSmokeAuditRunning = true
        requesterGapSmokeAuditStatus =
            "Running \(RequesterGapOnDeviceSmokeAuditFixtures.all.count) on-device requester gap compare prompts…"
        defer { isRequesterGapSmokeAuditRunning = false }

        print("[RequesterGapSmokeAudit] begin fixtures=\(RequesterGapOnDeviceSmokeAuditFixtures.all.count)")
        let rows = await RequesterGapOnDeviceSmokeAuditSupport.run(intelligenceProvider: onDevice)
        let artifactURL = Self.requesterGapSmokeAuditArtifactURL

        do {
            try RequesterGapOnDeviceSmokeAuditSupport.writeJSONL(rows: rows, to: artifactURL)
            let succeeded = rows.filter(\.success).count
            requesterGapSmokeAuditLastArtifactURL = artifactURL
            requesterGapSmokeAuditStatus =
                "Done: \(succeeded)/\(rows.count) succeeded. JSONL: \(artifactURL.lastPathComponent)"
            print(
                "[RequesterGapSmokeAudit] complete succeeded=\(succeeded)/\(rows.count) " +
                "artifact=\(artifactURL.path)"
            )
            finishManualE2ERun(source: source, result: requesterGapSmokeAuditStatus ?? "done")
        } catch {
            requesterGapSmokeAuditStatus = "Smoke audit failed to write JSONL: \(error.localizedDescription)"
            print("[RequesterGapSmokeAudit] write failed error=\(error)")
            finishManualE2ERun(source: source, result: "write_failed")
        }
    }

    private static var requesterGapSmokeAuditArtifactURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("requester_gap_on_device_smoke_audit.jsonl", isDirectory: false)
    }

    /// Runs fixed requester autonomous compose fixtures through the live on-device `requesterDraft` path.
    func runRequesterComposeOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isRequesterComposeSmokeAuditRunning else { return }
        guard let onDevice = exchangeDependencies.intelligenceProvider as? OnDeviceExchangeIntelligenceProvider else {
            requesterComposeSmokeAuditStatus = "OnDeviceExchangeIntelligenceProvider is not wired."
            finishManualE2ERun(source: source, result: "provider_not_wired")
            return
        }

        isRequesterComposeSmokeAuditRunning = true
        requesterComposeSmokeAuditStatus =
            "Running \(RequesterComposeOnDeviceSmokeAuditFixtures.all.count) on-device requester compose prompts…"
        defer { isRequesterComposeSmokeAuditRunning = false }

        print("[RequesterComposeSmokeAudit] begin fixtures=\(RequesterComposeOnDeviceSmokeAuditFixtures.all.count)")
        let rows = await RequesterComposeOnDeviceSmokeAuditSupport.run(intelligenceProvider: onDevice)
        let artifactURL = Self.requesterComposeSmokeAuditArtifactURL

        do {
            try RequesterComposeOnDeviceSmokeAuditSupport.writeJSONL(rows: rows, to: artifactURL)
            let succeeded = rows.filter(\.success).count
            requesterComposeSmokeAuditLastArtifactURL = artifactURL
            requesterComposeSmokeAuditStatus =
                "Done: \(succeeded)/\(rows.count) audit-ok. JSONL: \(artifactURL.lastPathComponent)"
            print(
                "[RequesterComposeSmokeAudit] complete succeeded=\(succeeded)/\(rows.count) " +
                "artifact=\(artifactURL.path)"
            )
            finishManualE2ERun(source: source, result: requesterComposeSmokeAuditStatus ?? "done")
        } catch {
            requesterComposeSmokeAuditStatus = "Compose smoke audit failed to write JSONL: \(error.localizedDescription)"
            print("[RequesterComposeSmokeAudit] write failed error=\(error)")
            finishManualE2ERun(source: source, result: "write_failed")
        }
    }

    private static var requesterComposeSmokeAuditArtifactURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("requester_compose_on_device_smoke_audit.jsonl", isDirectory: false)
    }

    /// Runs all 20 provider inquiry compare fixtures through the live on-device `providerInquiryCompare` runner.
    func runProviderInquiryAnswerOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf
    ) async {
        await runProviderInquiryAnswerOnDeviceSmokeAudit(
            trigger: trigger,
            mode: mode,
            options: .all
        )
    }

    func runProviderInquiryAnswerOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf,
        range: ClosedRange<Int>
    ) async {
        await runProviderInquiryAnswerOnDeviceSmokeAudit(
            trigger: trigger,
            mode: mode,
            options: .oneBasedRange(range)
        )
    }

    func runProviderInquiryAnswerOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf,
        options: ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isProviderInquiryAnswerSmokeAuditRunning else { return }
        guard let onDevice = exchangeDependencies.intelligenceProvider as? OnDeviceExchangeIntelligenceProvider else {
            providerInquiryAnswerSmokeAuditStatus = "OnDeviceExchangeIntelligenceProvider is not wired."
            finishManualE2ERun(source: source, result: "provider_not_wired")
            return
        }

        let batch = ProviderInquiryAnswerOnDeviceSmokeAuditSupport.fixtures(for: options)
        guard !batch.isEmpty else {
            providerInquiryAnswerSmokeAuditStatus = "No fixtures matched run options."
            finishManualE2ERun(source: source, result: "no_fixtures")
            return
        }

        isProviderInquiryAnswerSmokeAuditRunning = true
        providerInquiryAnswerSmokeAuditStatus =
            "Running provider inquiry answer smoke \(options.runRangeLabel) (\(batch.count) fixtures)…"
        defer { isProviderInquiryAnswerSmokeAuditRunning = false }

        let rows = await ProviderInquiryAnswerOnDeviceSmokeAuditSupport.run(
            intelligenceProvider: onDevice,
            options: options
        )
        let artifactURL = ProviderInquiryAnswerOnDeviceSmokeAuditSupport.artifactURL(
            runRangeLabel: options.runRangeLabel
        )

        do {
            try ProviderInquiryAnswerOnDeviceSmokeAuditSupport.writeJSONL(rows: rows, to: artifactURL)
            let succeeded = rows.filter(\.success).count
            providerInquiryAnswerSmokeAuditLastArtifactURL = artifactURL
            providerInquiryAnswerSmokeAuditStatus =
                "Done \(options.runRangeLabel): \(succeeded)/\(rows.count) audit-ok. JSONL: \(artifactURL.lastPathComponent)"
            print(
                "[ProviderInquiryAnswerSmokeAudit] complete runRange=\(options.runRangeLabel) " +
                "succeeded=\(succeeded)/\(rows.count) artifact=\(artifactURL.path)"
            )
            finishManualE2ERun(source: source, result: providerInquiryAnswerSmokeAuditStatus ?? "done")
        } catch {
            providerInquiryAnswerSmokeAuditStatus =
                "Provider inquiry answer smoke audit failed to write JSONL: \(error.localizedDescription)"
            print("[ProviderInquiryAnswerSmokeAudit] write failed error=\(error)")
            finishManualE2ERun(source: source, result: "write_failed")
        }
    }

    /// Runs fixed direct-message reply suggestion fixtures through the live on-device `directChatReply` path.
    func runDirectChatReplyOnDeviceSmokeAudit(
        trigger: ExchangeE2ETrigger,
        mode: ExchangeE2EMode = .discoveryAndSecondHalf
    ) async {
        guard let source = beginManualE2ERun(trigger: trigger, mode: mode) else { return }
        guard !isDirectChatReplySmokeAuditRunning else { return }

        isDirectChatReplySmokeAuditRunning = true
        directChatReplySmokeAuditStatus =
            "Running \(DirectChatReplyOnDeviceSmokeAuditFixtures.all.count) on-device direct-reply prompts…"
        defer { isDirectChatReplySmokeAuditRunning = false }

        print(
            "[DirectChatReplySmokeAudit] begin fixtures=\(DirectChatReplyOnDeviceSmokeAuditFixtures.all.count)"
        )
        let rows = await DirectChatReplyOnDeviceSmokeAuditSupport.run(
            suggestionService: directChatReplySuggestionService
        )
        let artifactURL = Self.directChatReplySmokeAuditArtifactURL

        do {
            try DirectChatReplyOnDeviceSmokeAuditSupport.writeJSONL(rows: rows, to: artifactURL)
            let succeeded = rows.filter(\.success).count
            directChatReplySmokeAuditLastArtifactURL = artifactURL
            directChatReplySmokeAuditStatus =
                "Done: \(succeeded)/\(rows.count) audit-ok. JSONL: \(artifactURL.lastPathComponent)"
            print(
                "[DirectChatReplySmokeAudit] complete succeeded=\(succeeded)/\(rows.count) " +
                "artifact=\(artifactURL.path)"
            )
            finishManualE2ERun(source: source, result: directChatReplySmokeAuditStatus ?? "done")
        } catch {
            directChatReplySmokeAuditStatus =
                "Direct reply smoke audit failed to write JSONL: \(error.localizedDescription)"
            print("[DirectChatReplySmokeAudit] write failed error=\(error)")
            finishManualE2ERun(source: source, result: "write_failed")
        }
    }

    private static var directChatReplySmokeAuditArtifactURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("direct_chat_reply_on_device_smoke_audit.jsonl", isDirectory: false)
    }
    #endif

    func requireExchangeNodeID() async throws -> String {
        let identityService = BootstrappedIdentityService()
        let identity = try await identityService.localIdentity()
        let nodeID = identity.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !nodeID.isEmpty else {
            throw NSError(
                domain: "AppServices.ExchangeIdentity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Local exchange node ID is missing."]
            )
        }

        return nodeID
    }

    /// Uploads a public image (resized/compressed by the caller) and returns the public URL.
    ///
    /// Returns the public HTTPS URL on success.
    /// Throws a readable error when the directory client is missing or when upload fails.
    /// Callers should catch errors and surface them; do not let upload failures block
    /// the rest of the save/publish text flow.
    func uploadPublicMedia(
        data: Data,
        mimeType: String,
        role: String,
        publicProfileID: String?,
        offerID: String?
    ) async throws -> String {
        guard let directoryClient = exchangeDependencies.directoryClient else {
            throw NSError(
                domain: "AppServices.MediaUpload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Media upload is not available."]
            )
        }

        let nodeID = try await requireExchangeNodeID()

        return try await directoryClient.uploadPublicMedia(
            data: data,
            mimeType: mimeType,
            nodeID: nodeID,
            role: role,
            publicProfileID: publicProfileID,
            offerID: offerID
        )
    }

    /// Deletes one remote public media object. Does not throw for expected server outcomes.
    func deletePublicMedia(storageKey: String) async -> ExchangePublicMediaDeleteOutcome {
        guard let directoryClient = exchangeDependencies.directoryClient else {
            return .failed(reason: "Media delete is not available.")
        }
        let nodeID: String
        do {
            nodeID = try await requireExchangeNodeID()
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        return await directoryClient.deletePublicMedia(storageKey: storageKey, nodeID: nodeID)
    }

    /// Best-effort cleanup after a successful local save/publish/unpublish. Never throws.
    func deleteStaleRemotePublicMedia(storageKeys: Set<String>, context: String) async {
        guard !storageKeys.isEmpty else { return }

        var hadDeferredCleanup = false
        for key in storageKeys.sorted() {
            let outcome = await deletePublicMedia(storageKey: key)
            switch outcome {
            case .deleted, .notFound:
                break
            case .stillReferenced:
                #if DEBUG
                print("[AppServices] deleteStaleRemotePublicMedia stillReferenced context=\(context) key=\(key)")
                #endif
            case .ownershipMismatch:
                #if DEBUG
                print("[AppServices] deleteStaleRemotePublicMedia ownershipMismatch context=\(context) key=\(key)")
                #endif
            case .invalidStorageKey:
                break
            case .failed(let reason):
                hadDeferredCleanup = true
                #if DEBUG
                print("[AppServices] deleteStaleRemotePublicMedia failed context=\(context) key=\(key) reason=\(reason)")
                #endif
            }
        }

        if hadDeferredCleanup {
            print("[AppServices] Profile updated. Old media will be cleaned up later.")
        }
    }

    /// Removes remote keys present before save but absent from the updated local profile/offer URLs.
    func cleanupRemotePublicMediaAfterSellerSurfaceSave(
        previousStorageKeys: Set<String>,
        profileImageURL: String?,
        offerImageURL: String?,
        offerGalleryImageURLs: [String]
    ) async {
        let current = PublicMediaURLSupport.storageKeys(
            profileImageURL: profileImageURL,
            offerImageURL: offerImageURL,
            offerGalleryImageURLs: offerGalleryImageURLs
        )
        // Avoid bulk-deleting prior media when a save/publish wrote an empty URL set (e.g. editor
        // form not hydrated). Per-slot replace/remove paths call `deleteStaleRemotePublicMedia` directly.
        if current.isEmpty, !previousStorageKeys.isEmpty {
            #if DEBUG
            print(
                "[AppServices] cleanupRemotePublicMediaAfterSellerSurfaceSave skipped empty-current guard previousKeyCount=\(previousStorageKeys.count)"
            )
            #endif
            return
        }
        let stale = previousStorageKeys.subtracting(current)
        await deleteStaleRemotePublicMedia(storageKeys: stale, context: "seller-surface-save")
    }

    /// After a local profile/offer media URL change: republish when a federation surface was previously published,
    /// then delete stale media keys only after a successful republish (or immediately when unpublished).
    ///
    /// - Returns: User-facing error when republish was required but failed (stale keys are not deleted).
    @MainActor
    func afterSuccessfulSellerSurfaceMediaMutation(
        staleStorageKeys: Set<String>,
        context: String
    ) async -> String? {
        let keys = Set(
            staleStorageKeys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let needsRepublish = sellerSurfaceNeedsPublishedMediaSync(
            sellerWorkspace?.publicationState
        )

        if needsRepublish {
            guard let nodeID = await exchangeNodeID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !nodeID.isEmpty
            else {
                return nil
            }

            do {
                let displayName = await localExchangeDisplayName()
                let presentation = await MainActor.run {
                    guardianSupporterPresentationForPublish?()
                }
                _ = try await exchangeFacade.publishSellerSurface(
                    ownerNodeID: nodeID,
                    ownerDisplayName: displayName,
                    publicSupporterPresentation: presentation
                )
                await refreshSellerWorkspace(force: true)
                requestSecretaryRefresh(.sellerWorkspaceChanged)

                if !keys.isEmpty {
                    await deleteStaleRemotePublicMedia(
                        storageKeys: keys,
                        context: "\(context)-post-republish"
                    )
                }
                return nil
            } catch {
                #if DEBUG
                print(
                    "[AppServices] afterSuccessfulSellerSurfaceMediaMutation republishFailed " +
                    "context=\(context) error=\(error)"
                )
                #endif
                return "Saved on this device, but could not update your published profile: \(error.localizedDescription)"
            }
        }

        if !keys.isEmpty {
            await deleteStaleRemotePublicMedia(storageKeys: keys, context: context)
        }
        return nil
    }

    private func sellerSurfaceNeedsPublishedMediaSync(
        _ state: ExchangePublicationState?
    ) -> Bool {
        guard let state else { return false }
        switch state.status {
        case .published, .stale:
            return true
        case .failed, .pendingPublish:
            return state.lastSuccessAt != nil
        case .draft, .paused, .pendingUnpublish, .archived:
            return false
        }
    }

    func localExchangeDisplayName() async -> String? {
        do {
            let identityService = BootstrappedIdentityService()
            let identity = try await identityService.localIdentity()

            if let displayName = identity.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !displayName.isEmpty {
                return displayName
            }

            return nil
        } catch {
            print("[AppServices] localExchangeDisplayName lookup failed: \(error)")
            return nil
        }
    }

    // MARK: - Seller workspace

    @MainActor
    func setSecretaryProfileTabActive(_ active: Bool) {
        secretaryProfileTabIsActive = active
    }

    /// Single publish path for seller workspace snapshots (Profile tab observes ``sellerWorkspaceHydrationGeneration``).
    @MainActor
    private func assignSellerWorkspace(_ workspace: ExchangeModels.SellerWorkspaceSummary?) {
        sellerWorkspace = workspace
        sellerWorkspaceHydrationGeneration &+= 1
        objectWillChange.send()
        #if DEBUG
        let imageURL = workspace?.publicProfile?.profile.primaryImageURL ?? ""
        print(
            "[ProfileHydrationPublish] generation=\(sellerWorkspaceHydrationGeneration) " +
            "hasWorkspace=\(workspace != nil) hasPublicProfile=\(workspace?.publicProfile != nil) " +
            "hasImage=\(!imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
        )
        #endif
    }

    @MainActor
    func setSellerSurfaceEditorPresented(_ present: Bool) {
        sellerSurfaceEditorIsPresented = present
    }

    private func shouldRefreshSellerWorkspaceNow(force: Bool) -> Bool {
        if force { return true }
        return secretaryProfileTabIsActive || sellerSurfaceEditorIsPresented
    }

    @discardableResult
    func refreshSellerWorkspace(force: Bool = false) async -> Bool {
        await refreshSellerWorkspaceCoalesced(force: force)
    }

    /// Serial coalescing: concurrent callers await the same in-flight refresh instead of cancelling it mid-flight
    /// (cancellation could leave Profile on placeholder strings until a later refresh completed).
    @discardableResult
    private func refreshSellerWorkspaceCoalesced(force: Bool = false) async -> Bool {
        guard shouldRefreshSellerWorkspaceNow(force: force) else {
            #if DEBUG
            print(
                "[ProfileHydration] refreshSellerWorkspace skipped reason=profileOrEditorNotActive " +
                "profileTab=\(secretaryProfileTabIsActive) editor=\(sellerSurfaceEditorIsPresented)"
            )
            #endif
            return false
        }

        if let running = sellerWorkspaceRefreshTask {
            #if DEBUG
            print("[ProfileHydration] refreshSellerWorkspace coalesced await existing")
            #endif
            await running.value
            return sellerWorkspace != nil
        }

        isSellerWorkspaceRefreshInFlight = true
        #if DEBUG
        print("[ProfileHydration] refreshSellerWorkspace start")
        #endif

        let task = Task { [weak self] in
            guard let self else { return }
            var didAttemptWorkspaceFetch = false
            defer {
                // Do not treat "node ID not ready yet" as a completed hydration when we have no workspace —
                // otherwise Profile shows placeholder copy until a later refresh (e.g. post–800ms deferred boot).
                if didAttemptWorkspaceFetch || self.sellerWorkspace != nil {
                    self.hasCompletedSellerWorkspaceHydrationAtLeastOnce = true
                }
                #if DEBUG
                print(
                    "[ProfileHydration] refreshSellerWorkspace inner settled attemptedFetch=\(didAttemptWorkspaceFetch) hasWorkspace=\(self.sellerWorkspace != nil) hasPublicProfile=\(self.sellerWorkspace?.publicProfile != nil) markedHydrationComplete=\(self.hasCompletedSellerWorkspaceHydrationAtLeastOnce)"
                )
                #endif
            }

            let previousWorkspace = self.sellerWorkspace
            let previousIssues = self.sellerValidationIssues

            guard let nodeID = await self.exchangeNodeID, !nodeID.isEmpty else {
                // First paint / no identity: empty is fine. If we already hydrated, keep the last snapshot
                // so Profile does not regress to placeholder on transient node ID gaps.
                if previousWorkspace == nil {
                    self.assignSellerWorkspace(nil)
                    self.sellerValidationIssues = []
                }
                #if DEBUG
                print("[ProfileHydration] localNodeID available=false skippedFetch")
                #endif
                return
            }

            #if DEBUG
            print("[ProfileHydration] localNodeID available=true")
            #endif

            didAttemptWorkspaceFetch = true

            let displayName = await self.localExchangeDisplayName()

            #if DEBUG
            let fetchWall = CFAbsoluteTimeGetCurrent()
            #endif

            let workspace: ExchangeModels.SellerWorkspaceSummary
            do {
                workspace = try await self.exchangeFacade.getSellerWorkspace(
                    ownerNodeID: nodeID,
                    ownerDisplayName: displayName
                )
            } catch {
                guard !Task.isCancelled else { return }

                print("[AppServices] refreshSellerWorkspace getSellerWorkspace failed: \(error)")
                if previousWorkspace == nil {
                    self.assignSellerWorkspace(nil)
                    self.sellerValidationIssues = []
                } else {
                    self.assignSellerWorkspace(previousWorkspace)
                    self.sellerValidationIssues = previousIssues
                }
                await self.refreshExchangeIdentityDebugSummary()
                #if DEBUG
                print("[ProfileHydration] source=storeFetchFailed keptPrevious=\(previousWorkspace != nil)")
                #endif
                return
            }

            #if DEBUG
            let fetchMs = Int((CFAbsoluteTimeGetCurrent() - fetchWall) * 1000)
            print("[ProfileHydration] workspace fetched durationMs=\(fetchMs) assigning")
            print(
                "[ProfileHydration] source=store hasWorkspace=true hasPublicProfile=\(workspace.publicProfile != nil) hasProfileTitle=\(!(workspace.publicProfile?.displayName ?? "").isEmpty) hasProfileImageURL=\(!(workspace.publicProfile?.profile.primaryImageURL ?? "").isEmpty) offerCount=\(workspace.offers.count)"
            )
            #endif

            // Show local seller surface immediately; validation may finish afterward.
            self.assignSellerWorkspace(workspace)

            #if DEBUG
            let validateWall = CFAbsoluteTimeGetCurrent()
            #endif

            let issues: [ExchangeSellerValidationIssue]
            do {
                issues = try await self.exchangeFacade.validateSellerWorkspace(
                    ownerNodeID: nodeID
                )
            } catch {
                guard !Task.isCancelled else { return }

                print("[AppServices] refreshSellerWorkspace validateSellerWorkspace failed: \(error)")
                self.sellerValidationIssues = previousIssues
                await self.refreshExchangeIdentityDebugSummary()
                return
            }

            #if DEBUG
            let validateMs = Int((CFAbsoluteTimeGetCurrent() - validateWall) * 1000)
            print("[ProfileHydration] validation durationMs=\(validateMs)")
            #endif

            guard !Task.isCancelled else { return }

            self.sellerValidationIssues = issues
            await self.refreshExchangeIdentityDebugSummary()
            await self.recordPublicationAttentionIfNeeded(
                workspace: workspace,
                issues: issues,
                ownerNodeID: nodeID
            )
        }

        sellerWorkspaceRefreshTask = task
        await task.value
        sellerWorkspaceRefreshTask = nil
        isSellerWorkspaceRefreshInFlight = false
        #if DEBUG
        print("[ProfileHydration] refreshSellerWorkspace outer await finished")
        #endif
        return sellerWorkspace != nil
    }

    // MARK: - Federation registration / publication

    /// Node registration is presence registration only.
    /// It should not pretend to publish the real seller surface.
    private func registerLocalFederationNodePresence() async {
        if let skipReason = await launchFederationNetworkSideWorkSkipReason() {
            #if DEBUG
            print(
                "[FederationNetwork][skip] phase=registerLocalFederationNodePresence reason=\(skipReason)"
            )
            #endif
            return
        }

        do {
            let identity = try await exchangeDependencies.identityService.localIdentity()

            let federationBase = ExchangeBootstrap.resolvedFederationBaseURL()
            #if DEBUG
            print(
                "[AppServices] registerLocalFederationNodePresence directory baseURL=\(federationBase.absoluteString)"
            )
            #endif

            let client = ExchangeHTTPDirectoryClient(
                baseURL: federationBase
            )

            let localHasEncryptionKey =
                identity.encryptionKeyID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && identity.encryptionPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let localEncryptionKeyIDPrefix = identity.encryptionKeyID.map { String($0.prefix(8)) } ?? "nil"
            print(
                "[AppServices] registerLocalFederationNodePresence localEncryptionKey=\(localHasEncryptionKey) " +
                "encryptionKeyIDPrefix=\(localEncryptionKeyIDPrefix)"
            )

            try await client.registerNode(
                nodeID: identity.nodeID,
                displayName: identity.displayName ?? "Unify Node \(identity.nodeID.suffix(6))",
                publicKeyID: identity.publicKeyID,
                publicProfile: ExchangeHTTPDirectoryClient.RegisterPublicProfile(
                    id: "node-presence-\(identity.nodeID)",
                    visibility: .limited,
                    availability: .open,
                    openTo: ["coordination"],
                    offers: ["secretary-node"],
                    semantic: [
                        "tags": ["unify", "secretary", "node"]
                    ],
                    reachability: ExchangeHTTPDirectoryClient.RegisterPublicProfile.Reachability(
                        acceptingInbound: true,
                        accessMode: "direct"
                    )
                ),
                encryptionKeyID: identity.encryptionKeyID,
                encryptionPublicKey: identity.encryptionPublicKey
            )

            print(
                "[AppServices] Federation node presence registered: \(identity.nodeID) " +
                "encryptionPublished=\(localHasEncryptionKey)"
            )

            await flushPendingPushTokenRegistrationIfNeeded(reason: .presence)

            do {
                let publishedKeys = try await client.fetchNodePublicKeys(
                    nodeID: identity.nodeID,
                    forceRefresh: true
                )
                let remoteHasEncryptionKey =
                    publishedKeys.encryptionPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let remoteEncryptionKeyIDPrefix = publishedKeys.encryptionKeyID.map { String($0.prefix(8)) } ?? "nil"
                print(
                    "[AppServices] fetchNodePublicKeys nodeID=\(identity.nodeID) " +
                    "hasEncryptionKey=\(remoteHasEncryptionKey) encryptionKeyIDPrefix=\(remoteEncryptionKeyIDPrefix)"
                )
            } catch {
                print("[AppServices] fetchNodePublicKeys after register failed: \(error)")
            }
        } catch {
            print("[AppServices] Federation node presence registration failed: \(error)")
        }
    }

    func reconcileSellerSurfacePublicationIfPossible() async {
        guard let nodeID = await exchangeNodeID, !nodeID.isEmpty else { return }

        do {
            let displayName = await localExchangeDisplayName()

            _ = try await exchangeFacade.reconcileSellerSurfacePublication(
                ownerNodeID: nodeID,
                ownerDisplayName: displayName,
                now: Date()
            )
        } catch {
            print("[AppServices] reconcileSellerSurfacePublicationIfPossible failed: \(error)")
        }
    }

    /// Supplies Guardian crown presentation for seller-surface publish (set from profile shell).
    @MainActor var guardianSupporterPresentationForPublish: (() -> ExchangeSupporterPresentation?)?

    func updateOwnerGuardianSupporterPresentation(isActive: Bool) async {
        let hasProfile = sellerWorkspace?.publicProfile != nil
        let profileID = sellerWorkspace?.publicProfile?.profile.id
        let oldPresentation = sellerWorkspace?.publicProfile?.profile.publicSupporterPresentation
        #if DEBUG
        GuardianCrownDebugLog.log(
            "UpdateOwner",
            "start isActive=\(isActive) hasProfile=\(hasProfile) profileID=\(profileID ?? "nil") " +
            "old=\(GuardianCrownDebugLog.presentationLabel(oldPresentation))"
        )
        #endif

        guard var profile = sellerWorkspace?.publicProfile?.profile else {
            #if DEBUG
            GuardianCrownDebugLog.log("UpdateOwner", "skip hasProfile=false")
            #endif
            return
        }

        profile.publicSupporterPresentation = ExchangeSupporterPresentation.guardianCrownIfActive(isActive)
        #if DEBUG
        GuardianCrownDebugLog.log(
            "UpdateOwner",
            "mutate profileID=\(profile.id) new=\(GuardianCrownDebugLog.presentationLabel(profile.publicSupporterPresentation))"
        )
        #endif

        do {
            try await exchangeFacade.savePublicProfile(profile)
            await refreshSellerWorkspace(force: true)
            #if DEBUG
            let saved = sellerWorkspace?.publicProfile?.profile.publicSupporterPresentation
            GuardianCrownDebugLog.log(
                "UpdateOwner",
                "saved profileID=\(profile.id) presentation=\(GuardianCrownDebugLog.presentationLabel(saved))"
            )
            #endif
        } catch {
            #if DEBUG
            GuardianCrownDebugLog.log(
                "UpdateOwner",
                "saveFailed profileID=\(profile.id) error=\(error.localizedDescription)"
            )
            print("[AppServices] updateOwnerGuardianSupporterPresentation failed: \(error)")
            #endif
        }
    }
    
    func publishSellerSurfaceNow(
        publicSupporterPresentation: ExchangeSupporterPresentation? = nil
    ) async {
        guard let nodeID = await exchangeNodeID, !nodeID.isEmpty else { return }

        let presentation = await MainActor.run {
            publicSupporterPresentation ?? guardianSupporterPresentationForPublish?()
        }

        #if DEBUG
        GuardianCrownDebugLog.log(
            "PublishRequest",
            "nodeID=\(nodeID) profileID=\(sellerWorkspace?.publicProfile?.profile.id ?? "nil") " +
            "presentation=\(GuardianCrownDebugLog.presentationLabel(presentation))"
        )
        #endif

        do {
            let displayName = await localExchangeDisplayName()

            _ = try await exchangeFacade.publishSellerSurface(
                ownerNodeID: nodeID,
                ownerDisplayName: displayName,
                publicSupporterPresentation: presentation,
                now: Date()
            )

            await refreshSellerWorkspace(force: true)

            requestSecretaryRefresh(.sellerWorkspaceChanged)
            #if DEBUG
            GuardianCrownDebugLog.log("PublishResult", "nodeID=\(nodeID) success=true")
            #endif
        } catch {
            #if DEBUG
            GuardianCrownDebugLog.log(
                "PublishResult",
                "nodeID=\(nodeID) success=false error=\(error.localizedDescription)"
            )
            #endif
            print("[AppServices] publishSellerSurfaceNow failed: \(error)")
        }
    }

    /// Removes the seller surface from the federation directory (published profile, offers, retrieval docs).
    /// Local Secretary drafts on device are kept; publication state moves to paused after success.
    func unpublishRemotePublishedData() async throws {
        guard let nodeID = await exchangeNodeID, !nodeID.isEmpty else {
            throw UnpublishRemotePublishedDataError.missingFederationIdentity
        }

        let mediaKeysBeforeUnpublish = PublicMediaURLSupport.storageKeys(in: sellerWorkspace)

        _ = try await exchangeFacade.unpublishSellerSurface(
            ownerNodeID: nodeID,
            now: Date()
        )

        await refreshSellerWorkspace(force: true)

        await deleteStaleRemotePublicMedia(
            storageKeys: mediaKeysBeforeUnpublish,
            context: "unpublish-seller-surface"
        )

        requestSecretaryRefresh(.sellerWorkspaceChanged)
    }

    func unpublishSellerSurfaceNow() async {
        do {
            try await unpublishRemotePublishedData()
        } catch {
            print("[AppServices] unpublishSellerSurfaceNow failed: \(error)")
        }
    }

    // MARK: - Secretary attention (SQLite-backed Updates sheet)

    private func upsertSecretarySQLiteNotification(_ notification: SecretaryNotification) async {
        do {
            try await exchangeFacade.upsertSecretaryNotification(notification)
        } catch {
            #if DEBUG
            print("[AppServices] upsertSecretarySQLiteNotification failed | \(error)")
            #endif
        }
    }

    /// Count-based digests after federation / sync passes. First successful observation seeds baselines without notifying.
    private func observeMailboxSnapshotsAfterSyncPass(
        inboxBefore: Int?,
        inboxAfter: Int?,
        approvalsBefore: Int?,
        approvalsAfter: Int?,
        now: Date
    ) async {
        guard let inboxAfter, let approvalsAfter else { return }

        if !UserDefaults.standard.bool(forKey: Self.secretaryNotifyBaselineSeededKey) {
            UserDefaults.standard.set(true, forKey: Self.secretaryNotifyBaselineSeededKey)
            UserDefaults.standard.set(inboxAfter, forKey: Self.secretaryNotifyLastInboxCountKey)
            UserDefaults.standard.set(approvalsAfter, forKey: Self.secretaryNotifyLastApprovalsCountKey)
            return
        }

        if let ib = inboxBefore, inboxAfter > ib {
            #if DEBUG
            print(
                "[InboundDigestSuppressed] source=observeMailboxSnapshotsAfterSyncPass reason=duplicate_inbound_badge inboxBefore=\(ib) inboxAfter=\(inboxAfter)"
            )
            #endif
        }

        if let ab = approvalsBefore, approvalsAfter > ab {
            await upsertSecretarySQLiteNotification(
                SecretaryNotification(
                    createdAt: now,
                    updatedAt: now,
                    kind: .approvalDigest,
                    dedupeKey: SecretaryNotificationDedupeKey.approvalDigestSnapshot(count: approvalsAfter),
                    priority: .normal,
                    title: "Decision needed",
                    body: "Pending approvals rose (\(ab) → \(approvalsAfter)). Your secretary highlighted what to review.",
                    metadata: ["routeHint": "threads"]
                )
            )
        }

        UserDefaults.standard.set(inboxAfter, forKey: Self.secretaryNotifyLastInboxCountKey)
        UserDefaults.standard.set(approvalsAfter, forKey: Self.secretaryNotifyLastApprovalsCountKey)
    }

    private func recordDiscoveryAttentionIfNeeded() async {
        if secretaryDiscoveryMode != .discoverOnly || forYouItems.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.secretaryNotifyForYouLastNotifiedFingerprintKey)
            return
        }

        let fingerprint = forYouItems.map(\.id).sorted().joined(separator: "|")
        let prev = UserDefaults.standard.string(forKey: Self.secretaryNotifyForYouLastNotifiedFingerprintKey)
        guard fingerprint != prev else { return }

        let count = forYouItems.count
        guard count > 0 else { return }

        let shown = min(count, 5)
        await upsertSecretarySQLiteNotification(
            SecretaryNotification(
                createdAt: Date(),
                updatedAt: Date(),
                kind: .discoveryMatch,
                dedupeKey: SecretaryNotificationDedupeKey.discoveryMatchFingerprint(fingerprint),
                priority: .normal,
                title: "New discovery matches",
                body:
                    "I found \(shown) profile\(shown == 1 ? "" : "s") or offers that may be relevant.",
                metadata: ["routeHint": "dashboard"]
            )
        )

        UserDefaults.standard.set(fingerprint, forKey: Self.secretaryNotifyForYouLastNotifiedFingerprintKey)
    }

    private func markLegacyPublicationIssueNotificationsRead(stableDedupeKey: String) async {
        guard let rows = try? await exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: [.publicationIssue],
                limit: 200
            )
        ) else { return }

        let legacyIDs = rows.filter { $0.dedupeKey != stableDedupeKey }.map(\.id)
        guard !legacyIDs.isEmpty else { return }

        do {
            try await exchangeFacade.markSecretaryNotificationsRead(ids: Set(legacyIDs))
            #if DEBUG
            print("[PublicSurfaceNotificationLegacyRowsRead] count=\(legacyIDs.count)")
            #endif
        } catch {
            #if DEBUG
            print("[PublicSurfaceNotificationLegacyRowsRead] failed count=\(legacyIDs.count) error=\(error)")
            #endif
        }
    }

    private func recordPublicationAttentionIfNeeded(
        workspace: ExchangeModels.SellerWorkspaceSummary,
        issues: [ExchangeSellerValidationIssue],
        ownerNodeID: String
    ) async {
        let trimmedNode = ownerNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else { return }

        let status = workspace.publicationState?.status
        let failed = status == .failed
        let needs = workspace.needsPublicationAttention

        guard failed || needs || !issues.isEmpty else { return }

        let stableDedupe = SecretaryNotificationDedupeKey.publicationIssueSellerSurface(nodeID: trimmedNode)
        await markLegacyPublicationIssueNotificationsRead(stableDedupeKey: stableDedupe)

        let fingerprintSource = issues.map(\.summary).sorted().joined(separator: "|")
        let statusRaw = status?.rawValue ?? "nil"
        let fp = "\(statusRaw)|needs:\(needs)|\(fingerprintSource)"
        let issueHash = fp

        let publicationRows = try? await exchangeFacade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: false,
                kinds: [.publicationIssue],
                limit: 80
            )
        )
        let existingStable = publicationRows?.first { $0.dedupeKey == stableDedupe }

        if let existingStable, existingStable.metadata["issue_hash"] == issueHash {
            #if DEBUG
            print(
                "[PublicationNotificationUpsert] dedupeKey=\(stableDedupe) oldFingerprint=\(issueHash) newFingerprint=\(issueHash) fingerprintChanged=false preservedRead=\(existingStable.isRead) updatedAtBumped=false markUnread=false reason=same_issue_set_skip_upsert"
            )
            #endif
            return
        }

        let title: String =
            failed
                ? "Publishing failed"
                : "Public surface needs attention"

        let primaryIssue = issues.first?.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail =
            workspace.publicationDetailLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusLineTrimmed =
            workspace.statusLine.trimmingCharacters(in: .whitespacesAndNewlines)

        let body: String =
            (primaryIssue.flatMap { $0.isEmpty ? nil : $0 })
            ?? (detail.flatMap { $0.isEmpty ? nil : $0 })
            ?? (statusLineTrimmed.isEmpty ? nil : statusLineTrimmed)
            ?? "Review your outward surface before others discover it."

        let isNew = existingStable == nil
        let fingerprintChanged = existingStable.map { $0.metadata["issue_hash"] != issueHash } ?? false
        let oldFingerprint = existingStable?.metadata["issue_hash"] ?? "nil"
        #if DEBUG
        print(
            "[PublicationNotificationUpsert] dedupeKey=\(stableDedupe) oldFingerprint=\(oldFingerprint) newFingerprint=\(issueHash) fingerprintChanged=\(fingerprintChanged) existingWasRead=\(existingStable?.isRead ?? false) updatedAtBumped=true isNew=\(isNew) markUnread=false"
        )
        #endif

        let metadata: [String: String] = ["routeHint": "sellerSurface", "issue_hash": issueHash]
        await upsertSecretarySQLiteNotification(
            SecretaryNotification(
                createdAt: existingStable?.createdAt ?? Date(),
                updatedAt: Date(),
                kind: .publicationIssue,
                dedupeKey: stableDedupe,
                isRead: false,
                priority: .normal,
                title: title,
                body: body,
                metadata: metadata
            )
        )
    }

    // MARK: - Federation sync

    /// Federation pull + reconcile. When `requestDeskRefreshAfter` is false, skips the coalesced
    /// secretary desk replay (caller will load locally, e.g. pull-to-refresh on the dashboard).
    /// When `recordAttentionDigests` is false (e.g. dashboard pull-to-refresh), skips mailbox digest
    /// upserts so `secretaryNotificationsDidChange` does not enqueue a redundant `requestSecretaryRefresh`.
    @discardableResult
    func syncFederationInboxNow(
        requestDeskRefreshAfter: Bool = true,
        recordAttentionDigests: Bool = true,
        trigger: ExchangeSyncEngine.Trigger = .manualRefresh
    ) async -> Bool {
        if let skipReason = await automaticFederationSyncSkipReason(trigger: trigger) {
            print(
                "[SyncTrigger][skip] reason=\(skipReason.rawValue) trigger=\(trigger.rawValue) " +
                "path=syncFederationInboxNow"
            )
            return false
        }

        print("[SyncTrigger] trigger=\(trigger.rawValue) path=syncFederationInboxNow")
        #if DEBUG
        print("[AppServices] syncFederationInboxNow begin trigger=\(trigger.rawValue)")
        #endif

        let digestBefore = recordAttentionDigests ? await secretaryMailboxDigestCounts() : nil
        let inboxBefore = digestBefore?.inbox ?? -1
        let approvalsBefore = digestBefore?.pending ?? -1

        let completedBefore = await exchangeSyncEngine.currentStatus().lastCompletedAt
        let relayBefore = await exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence

        await exchangeSyncEngine.runPass(
            trigger: trigger,
            now: Date()
        )

        let completedAfter = await exchangeSyncEngine.currentStatus().lastCompletedAt
        let relayAfter = await exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence
        let syncActuallyRan =
            completedAfter != completedBefore || relayAfter > relayBefore

        #if DEBUG
        print(
            "[SecretaryRefreshAfterSync] trigger=\(trigger.rawValue) syncActuallyRan=\(syncActuallyRan) " +
            "lastCompletedChanged=\(completedAfter != completedBefore) relayAdvanced=\(relayAfter > relayBefore)"
        )
        #endif

        if syncActuallyRan {
            await reconcileSellerSurfacePublicationIfPossible()
            _ = await secretaryMailboxDigestCounts()
        }

        if recordAttentionDigests, syncActuallyRan {
            let digestAfter = await secretaryMailboxDigestCounts()

            await observeMailboxSnapshotsAfterSyncPass(
                inboxBefore: inboxBefore >= 0 ? inboxBefore : nil,
                inboxAfter: digestAfter.inbox,
                approvalsBefore: approvalsBefore >= 0 ? approvalsBefore : nil,
                approvalsAfter: digestAfter.pending,
                now: Date()
            )
        }

        if requestDeskRefreshAfter, syncActuallyRan {
            requestSecretaryRefresh(.federationSync)
        } else if requestDeskRefreshAfter {
            #if DEBUG
            print(
                "[SecretaryRefreshAfterSync] skipped federationSync deskRefresh reason=syncNoOp " +
                "trigger=\(trigger.rawValue)"
            )
            #endif
        }

        #if DEBUG
        print(
            "[AppServices] syncFederationInboxNow end trigger=\(trigger.rawValue) syncActuallyRan=\(syncActuallyRan)"
        )
        #endif
        return syncActuallyRan
    }

    /// When the sync engine policy-no-ops (`canStartRun` false), `syncFederationInboxNow` returns without fetching.
    /// Callers that need fresh relay data (e.g. live DM) can use this helper: if completion time did not advance,
    /// waits briefly and runs one `silentPush` pass (minimum interval 0) so a follow-up attempt can run after
    /// contention or short guards clear.
    func syncFederationInboxNowRetryingSilentPushIfEngineNoOp(
        requestDeskRefreshAfter: Bool = true,
        recordAttentionDigests: Bool = true,
        trigger: ExchangeSyncEngine.Trigger = .manualRefresh
    ) async {
        let beforeCompleted = await exchangeSyncEngine.currentStatus().lastCompletedAt
        let syncRan = await syncFederationInboxNow(
            requestDeskRefreshAfter: false,
            recordAttentionDigests: recordAttentionDigests,
            trigger: trigger
        )
        if syncRan {
            if requestDeskRefreshAfter {
                requestSecretaryRefresh(.federationSync)
            }
            return
        }
        let afterCompleted = await exchangeSyncEngine.currentStatus().lastCompletedAt
        guard afterCompleted == beforeCompleted else {
            if requestDeskRefreshAfter {
                requestSecretaryRefresh(.federationSync)
            }
            return
        }

        #if DEBUG
        print(
            "[AppServices] syncFederationInboxNowRetryingSilentPushIfEngineNoOp " +
                "phase=followUpSilentPush reason=lastCompletedAt_unchanged before=\(String(describing: beforeCompleted)) " +
                "after=\(String(describing: afterCompleted))"
        )
        #endif

        try? await Task.sleep(nanoseconds: 450_000_000)
        let relaySeqBeforeSilent = await exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence
        await exchangeSyncEngine.runPass(trigger: .silentPush, now: Date())
        let relaySeqAfterSilent = await exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence

        if requestDeskRefreshAfter, relaySeqAfterSilent > relaySeqBeforeSilent {
            requestSecretaryRefresh(.federationSync)
        }
    }

    func syncFederationOnAppActive() async {
        let nodeID = await exchangeNodeID
        #if DEBUG
        print("[AppServices] syncFederationOnAppActive outer await begin")
        print("[AppActiveFederationSync] phase=start exchangeNodeID=\(nodeID ?? "nil")")
        #endif

        foregroundFederationSyncTask?.cancel()

        foregroundFederationSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if await self.runAppActiveDeliveredSecretaryNotificationSyncIfNeeded(nodeID: nodeID) {
                return
            }

            if let skipReason = await self.automaticFederationSyncSkipReason(trigger: .appBecameActive) {
                print(
                    "[AppActiveFederationSync][skip] reason=\(skipReason.rawValue) " +
                    "exchangeNodeID=\(nodeID ?? "nil")"
                )
                return
            }

            #if DEBUG
            print("[AppServices] syncFederationOnAppActive inner task begin (after delay)")
            #endif

            let digestBefore = await self.secretaryMailboxDigestCounts()
            let inboxBefore = digestBefore.inbox
            let approvalsBefore = digestBefore.pending

            let completedBefore = await self.exchangeSyncEngine.currentStatus().lastCompletedAt
            let relayBefore = await self.exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence

            await self.exchangeSyncEngine.runPass(
                trigger: .appBecameActive,
                now: Date()
            )

            guard !Task.isCancelled else { return }

            let completedAfter = await self.exchangeSyncEngine.currentStatus().lastCompletedAt
            let relayAfter = await self.exchangeSyncEngine.lastSuccessfulRelayFetchSnapshot().sequence
            let syncActuallyRan =
                completedAfter != completedBefore || relayAfter > relayBefore

            if syncActuallyRan {
                await self.reconcileSellerSurfacePublicationIfPossible()
            }

            guard !Task.isCancelled else { return }

            await self.refreshForYouIfEligible()

            if syncActuallyRan {
                let digestAfter = await self.secretaryMailboxDigestCounts()

                await self.observeMailboxSnapshotsAfterSyncPass(
                    inboxBefore: inboxBefore,
                    inboxAfter: digestAfter.inbox,
                    approvalsBefore: approvalsBefore,
                    approvalsAfter: digestAfter.pending,
                    now: Date()
                )
            }

            if await self.pushTokenUploadNetworkSkipReason() == nil {
                let uploadReason: PushTokenUploadFlushReason =
                    UserDefaults.standard.bool(forKey: Self.pushTokenRegistrationFailedKey) ? .retry : .appActive
                await self.flushPendingPushTokenRegistrationIfNeeded(reason: uploadReason)
            }

            if syncActuallyRan {
                self.requestSecretaryRefresh(.appForeground)
            } else {
                #if DEBUG
                print(
                    "[SecretaryRefreshAfterSync] skipped appForeground deskRefresh reason=syncNoOp"
                )
                #endif
            }

            #if DEBUG
            print("[AppServices] syncFederationOnAppActive inner task end")
            print(
                "[AppActiveFederationSync] phase=end exchangeNodeID=\(nodeID ?? "nil") " +
                "runResult=completed requestSecretaryRefreshCalled=true"
            )
            #endif
        }

        await foregroundFederationSyncTask?.value
        foregroundFederationSyncTask = nil

        #if DEBUG
        print("[AppServices] syncFederationOnAppActive outer await end")
        #endif
    }

    // MARK: - Exchange bootstrap path

    private static func makeExchangeDatabaseURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Anum", isDirectory: true)

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("exchange.sqlite")
    }

    // MARK: - Data actions

    enum DataActionError: Error {
        case zipUnavailable
        case exportFailed(String)
    }

    func exportMyDataZip() async throws -> URL {
        let fm = FileManager.default
        let ts = Int(Date().timeIntervalSince1970)

        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("AnumExport_\(ts)", isDirectory: true)

        try? fm.removeItem(at: exportDir)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let transcriptCandidates = computeCandidateTranscriptURLs()
        var didCopyTranscript = false

        for url in transcriptCandidates {
            if fm.fileExists(atPath: url.path) {
                try copyIfExists(
                    src: url,
                    dstDir: exportDir,
                    dstName: "chat_transcript_v1.json"
                )
                didCopyTranscript = true
                break
            }
        }

        #if DEBUG
        if !didCopyTranscript {
            print("[AppServices] export: no transcript found in candidates (ok if first run)")
        }
        #endif

        let anumDir = try computeAnumSupportDirURL()
        let identityDst = exportDir.appendingPathComponent("identity", isDirectory: true)
        try? fm.createDirectory(at: identityDst, withIntermediateDirectories: true)

        try copyDirectoryContentsFiltering(
            srcDir: anumDir,
            dstDir: identityDst,
            shouldCopy: { name in
                !name.hasPrefix("memory.sqlite")
            }
        )

        let memoryDst = exportDir.appendingPathComponent("memory", isDirectory: true)
        try? fm.createDirectory(at: memoryDst, withIntermediateDirectories: true)

        _ = try await MemoryStore.shared.exportDatabaseSnapshot(
            to: memoryDst,
            filename: "memory.sqlite"
        )

        let exchangeDBURL = Self.makeExchangeDatabaseURL()
        let exchangeDst = exportDir.appendingPathComponent("exchange", isDirectory: true)
        try? fm.createDirectory(at: exchangeDst, withIntermediateDirectories: true)

        if fm.fileExists(atPath: exchangeDBURL.path) {
            try copyIfExists(
                src: exchangeDBURL,
                dstDir: exchangeDst,
                dstName: "exchange.sqlite"
            )

            let walURL = URL(fileURLWithPath: exchangeDBURL.path + "-wal")
            let shmURL = URL(fileURLWithPath: exchangeDBURL.path + "-shm")

            if fm.fileExists(atPath: walURL.path) {
                try? copyIfExists(
                    src: walURL,
                    dstDir: exchangeDst,
                    dstName: "exchange.sqlite-wal"
                )
            }

            if fm.fileExists(atPath: shmURL.path) {
                try? copyIfExists(
                    src: shmURL,
                    dstDir: exchangeDst,
                    dstName: "exchange.sqlite-shm"
                )
            }
        }

        let avatarsDir = try computeAvatarsDirURL()
        let avatarsDst = exportDir.appendingPathComponent("avatars", isDirectory: true)

        if fm.fileExists(atPath: avatarsDir.path) {
            try? fm.removeItem(at: avatarsDst)
            try fm.copyItem(at: avatarsDir, to: avatarsDst)
        }

        let manifestURL = exportDir.appendingPathComponent("manifest.json")
        let manifest = makeExportManifest(exportedAt: Date())

        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )

        try manifestData.write(to: manifestURL, options: [.atomic])

        return exportDir
    }

    /// Deletes Companion Mode local data only. Does not touch Secretary/Exchange or federation identity.
    @discardableResult
    func wipeCompanionDataOnly() async -> UnifyDataLifecycleReport {
        var report = UnifyDataLifecycleReport(domain: .companion)
        let logPrefix = "[AppServices][CompanionWipe]"

        chat.cancelGeneration()
        chat.clearRecentChat()
        chat.flushTranscriptToDisk()

        await MemoryStore.shared.closeForWipe()

        let fm = FileManager.default

        if let anumDir = try? computeAnumSupportDirURL() {
            let memoryURL = anumDir.appendingPathComponent("memory.sqlite")
            let memoryWALURL = URL(fileURLWithPath: memoryURL.path + "-wal")
            let memorySHMURL = URL(fileURLWithPath: memoryURL.path + "-shm")

            for url in [memoryURL, memoryWALURL, memorySHMURL] {
                _ = UnifyDataLifecycleFileRemoval.removeItemIfExists(
                    at: url,
                    fileManager: fm,
                    logPrefix: logPrefix,
                    report: &report
                )
            }

            for name in UnifyDataLifecycleFiles.symbioticCompanionRuntimeFilenames {
                let url = anumDir.appendingPathComponent(name)
                _ = UnifyDataLifecycleFileRemoval.removeItemIfExists(
                    at: url,
                    fileManager: fm,
                    logPrefix: logPrefix,
                    report: &report
                )
            }
        } else {
            report.recordFailure("could not resolve Application Support/Anum for memory DB")
        }

        for transcriptURL in computeCandidateTranscriptURLs() {
            _ = UnifyDataLifecycleFileRemoval.removeItemIfExists(
                at: transcriptURL,
                fileManager: fm,
                logPrefix: logPrefix,
                report: &report
            )
        }

        if let avatarsDir = try? computeAvatarsDirURL() {
            _ = UnifyDataLifecycleFileRemoval.removeItemIfExists(
                at: avatarsDir,
                fileManager: fm,
                logPrefix: logPrefix,
                report: &report
            )
        }

        for key in CompanionWipeUserDefaultsKeys.all {
            UserDefaults.standard.removeObject(forKey: key)
            report.recordRemoved(userDefaultsKey: key)
        }
        UserDefaults.standard.synchronize()

        try? await MemoryStore.shared.reopenAfterWipe()

        report.note("exchange.sqlite and federation identity were not modified")
        print("\(logPrefix) complete removedPaths=\(report.removedPaths.count) defaultsKeys=\(report.removedUserDefaultsKeys.count) failures=\(report.failures.count)")
        return report
    }

    /// Deletes Secretary Mode local data only. Does not touch Companion data or federation identity.
    @discardableResult
    func wipeSecretaryLocalDataOnly() async -> UnifyDataLifecycleReport {
        var report = UnifyDataLifecycleReport(domain: .secretary)
        let logPrefix = "[AppServices][SecretaryWipe]"

        suspendExchangeActivityForLocalWipe()
        resetSecretaryInMemoryStateAfterLocalWipe()

        exchangeGraph = nil

        let anumDir: URL
        do {
            anumDir = try computeAnumSupportDirURL()
        } catch {
            report.recordFailure("could not resolve Application Support/Anum: \(error)")
            anumDir = Self.makeExchangeDatabaseURL().deletingLastPathComponent()
        }

        let fm = FileManager.default
        for url in UnifyDataLifecycleFiles.exchangeDatabaseURLs(baseDirectory: anumDir) {
            _ = UnifyDataLifecycleFileRemoval.removeItemIfExists(
                at: url,
                fileManager: fm,
                logPrefix: logPrefix,
                report: &report
            )
        }

        let removedDefaults = SecretaryWipeUserDefaultsRemoval.removeKeys(report: &report)
        report.note("removed \(removedDefaults) Secretary UserDefaults keys")

        UnifyDataLifecycleFileRemoval.clearURLImageCaches(report: &report)
        UnifyDataLifecycleFileRemoval.removeSecretaryDebugArtifacts(
            fileManager: fm,
            logPrefix: logPrefix,
            report: &report
        )

        do {
            try await restartExchangeRuntimeAfterSecretaryLocalWipe()
            report.note("exchange runtime reinitialized with empty exchange.sqlite")
        } catch {
            report.recordFailure("exchange rebuild failed: \(error)")
        }

        report.note("companion memory, transcript, avatars, and federation identity were not modified")
        report.note("remote published media and relay copies were not deleted")
        print("\(logPrefix) complete removedPaths=\(report.removedPaths.count) defaultsKeys=\(report.removedUserDefaultsKeys.count) failures=\(report.failures.count)")
        return report
    }

    /// Deletes all local Companion + Secretary data on this device. Does not reset federation identity or remote data.
    @discardableResult
    func wipeAllLocalUnifyData() async -> UnifyDataLifecycleReport {
        var report = UnifyDataLifecycleReport(domain: .fullLocal)
        report.note("beginning companion wipe, then secretary wipe")

        let companionReport = await wipeCompanionDataOnly()
        report.removedPaths.append(contentsOf: companionReport.removedPaths)
        report.removedUserDefaultsKeys.append(contentsOf: companionReport.removedUserDefaultsKeys)
        report.failures.append(contentsOf: companionReport.failures)
        report.notes.append(contentsOf: companionReport.notes)

        let secretaryReport = await wipeSecretaryLocalDataOnly()
        report.removedPaths.append(contentsOf: secretaryReport.removedPaths)
        report.removedUserDefaultsKeys.append(contentsOf: secretaryReport.removedUserDefaultsKeys)
        report.failures.append(contentsOf: secretaryReport.failures)
        report.notes.append(contentsOf: secretaryReport.notes)

        report.note("federation identity was not reset; remote data was not deleted")
        print("[AppServices][FullLocalWipe] complete failures=\(report.failures.count)")
        return report
    }

    /// Destructive federation identity reset — separate from local data wipes. Requires explicit UI confirmation before calling.
    @discardableResult
    func resetFederationIdentity() throws -> UnifyDataLifecycleReport {
        var report = UnifyDataLifecycleReport(domain: .federationIdentity)
        do {
            try NodeIdentityVault.shared.resetFederationIdentity()
            report.note("NodeIdentityVault federation seed removed from Keychain")
            clearPushTokenRegistrationContext()
            invalidateExchangeNodeIDCache()
        } catch {
            report.recordFailure("NodeIdentityVault.resetFederationIdentity failed: \(error)")
        }
        report.note("local Companion and Secretary stores were not modified by this call")
        print("[AppServices][FederationIdentityReset] complete failures=\(report.failures.count)")
        return report
    }

    private func suspendExchangeActivityForLocalWipe() {
        exchangeBootTask?.cancel()
        exchangeBootTask = nil
        foregroundFederationSyncTask?.cancel()
        foregroundFederationSyncTask = nil
        sellerWorkspaceRefreshTask?.cancel()
        sellerWorkspaceRefreshTask = nil
        secretaryRefreshTask?.cancel()
        secretaryRefreshTask = nil
        didStartExchangeBoot = false
        discoveryHeroProgress = nil
        discoveryHeroProgressGeneration = 0
    }

    private func resetSecretaryInMemoryStateAfterLocalWipe() {
        secretaryDiscoveryMode = .off
        threadAutonomyMode = .manualOnly
        forYouItems = []
        forYouDiscoveryQuality = nil
        forYouLastPassFailure = nil
        lastForYouFailureAt = nil
        lastForYouPassAt = nil
        clearForYouPersistedLifecycleState()
        assignSellerWorkspace(nil)
        sellerValidationIssues = []
        exchangeIdentityDebugSummary = nil
        hasCompletedSellerWorkspaceHydrationAtLeastOnce = false
        sellerWorkspaceHydrationGeneration = 0
        isSellerWorkspaceRefreshInFlight = false
        secretaryConstitutionText = ""
        secretaryStyleText = ""
        contactContextStore = ExchangeUserDefaultsContactContextStore()
    }

    /// Rebuilds the Exchange graph after local Secretary wipe and restarts deferred boot/sync (idempotent via `didStartExchangeBoot`).
    private func restartExchangeRuntimeAfterSecretaryLocalWipe() async throws {
        try await rebuildExchangeGraphAfterSecretaryLocalWipe()
        await refreshSecretaryPushNotificationDeliveryState(logContext: "wipeRestart")
        await restorePushRegistrationAfterLocalWipeIfEligible()
        startDeferredExchangeBoot()
    }

    /// Re-requests APNs device token after local wipe cleared `secretary.apns.*` keys (bootstrap-owned, not discovery).
    private func restorePushRegistrationAfterLocalWipeIfEligible() async {
        if UserDefaults.standard.bool(forKey: Self.unifyPushDeliveryOptOutKey) {
            #if DEBUG
            print("[APNs][WipeRestart] skip reason=deliveryOptOut")
            #endif
            await refreshSecretaryPushNotificationDeliveryState(logContext: "wipeRestartApnsSkipOptOut")
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .denied, .notDetermined:
            authorized = false
        @unknown default:
            authorized = false
        }

        guard authorized else {
            #if DEBUG
            print(
                "[APNs][WipeRestart] skip reason=iosNotAuthorized status=\(settings.authorizationStatus.logToken)"
            )
            #endif
            await refreshSecretaryPushNotificationDeliveryState(logContext: "wipeRestartApnsSkipUnauthorized")
            return
        }

        #if DEBUG
        print("[APNs][WipeRestart] registerForRemoteNotifications")
        #endif

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        await refreshSecretaryPushNotificationDeliveryState(logContext: "wipeRestartApnsRegisterRequested")
    }

    private func rebuildExchangeGraphAfterSecretaryLocalWipe() async throws {
        let constitutionProvider: @Sendable () -> String? = {
            SecretaryConstitutionStorage.loadOptional()
        }
        let styleTextProvider: @Sendable () -> String? = {
            SecretaryStyleTextStorage.loadOptional()
        }

        let reporter = DiscoveryHeroProgressReporterBox()
        let graph = try Self.buildExchangeGraph(
            databaseURL: Self.makeExchangeDatabaseURL(),
            constitutionProvider: constitutionProvider,
            styleTextProvider: styleTextProvider,
            discoveryHeroProgressReporter: reporter,
            requesterLocationProvider: requesterLocationService
        )

        exchangeGraph = graph
        reporter.bind(self)

        chat.configureExchange(
            bridge: graph.chatBridge,
            facade: graph.facade
        )

        secretaryConstitutionText = SecretaryConstitutionStorage.load()
        secretaryStyleText = SecretaryStyleTextStorage.load()

        Self.bootstrapThreadAutonomyModeIfNeeded()
        let rawMode = UserDefaults.standard.string(forKey: Self.discoveryModeKey) ?? ""
        secretaryDiscoveryMode = ExchangeModels.SecretaryDiscoveryMode(rawValue: rawMode) ?? .off
        let rawThreadAutonomyMode = UserDefaults.standard.string(forKey: Self.threadAutonomyModeKey) ?? ""
        threadAutonomyMode = ExchangeModels.ExchangeThreadAutonomyMode(rawValue: rawThreadAutonomyMode) ?? .manualOnly

        requestSecretaryRefresh(.manual)
    }

    // MARK: - Paths & helpers

    private func computeTranscriptURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = base.appendingPathComponent("AnumAPP", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir.appendingPathComponent("chat_transcript_v1.json")
    }

    private func computeCandidateTranscriptURLs() -> [URL] {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        var dirNames: [String] = ["AnumAPP"]

        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            dirNames.append(name)
        }

        if let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !display.isEmpty {
            dirNames.append(display)
        }

        dirNames.append("Unify")

        var seen = Set<String>()
        dirNames = dirNames.filter { seen.insert($0).inserted }

        var urls: [URL] = []

        for dn in dirNames {
            let dir = base.appendingPathComponent(dn, isDirectory: true)
            urls.append(dir.appendingPathComponent("chat_transcript_v1.json"))
        }

        urls.append(base.appendingPathComponent("chat_transcript_v1.json"))
        urls.append(computeTranscriptURL())

        var seenURL = Set<String>()
        return urls.filter { seenURL.insert($0.path).inserted }
    }

    private func computeAnumSupportDirURL() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = base.appendingPathComponent("Anum", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir
    }

    private func computeAvatarsDirURL() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base.appendingPathComponent("Avatars", isDirectory: true)
    }

    private func copyIfExists(
        src: URL,
        dstDir: URL,
        dstName: String
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return }

        let dst = dstDir.appendingPathComponent(dstName)

        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }

        try fm.copyItem(at: src, to: dst)
    }

    private func copyDirectoryContentsFiltering(
        srcDir: URL,
        dstDir: URL,
        shouldCopy: (String) -> Bool
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: srcDir.path) else { return }

        let items = try fm.contentsOfDirectory(atPath: srcDir.path)

        for name in items {
            guard shouldCopy(name) else { continue }

            let src = srcDir.appendingPathComponent(name)
            let dst = dstDir.appendingPathComponent(name)

            if fm.fileExists(atPath: dst.path) {
                try? fm.removeItem(at: dst)
            }

            try fm.copyItem(at: src, to: dst)
        }
    }

    private func makeExportManifest(exportedAt: Date) -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""

        return [
            "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "appVersion": short,
            "build": build,
            "note": "All data exported locally from this device."
        ]
    }
}

// MARK: - Data lifecycle (local)

/// Structured outcome for local data lifecycle operations (logging + future Settings UI).
struct UnifyDataLifecycleReport: Sendable {
    enum Domain: String, Sendable {
        case companion
        case secretary
        case fullLocal
        case federationIdentity
    }

    let domain: Domain
    var removedPaths: [String] = []
    var removedUserDefaultsKeys: [String] = []
    var failures: [String] = []
    var notes: [String] = []

    mutating func recordRemoved(path: String) {
        removedPaths.append(path)
    }

    mutating func recordRemoved(userDefaultsKey: String) {
        removedUserDefaultsKeys.append(userDefaultsKey)
    }

    mutating func recordFailure(_ message: String) {
        failures.append(message)
    }

    mutating func note(_ message: String) {
        notes.append(message)
    }
}

enum SecretaryWipeUserDefaultsRemoval {
    static func collectKeys(in defaults: UserDefaults = .standard) -> [String] {
        let dictionary = defaults.dictionaryRepresentation()
        return dictionary.keys.filter { SecretaryWipeUserDefaultsCatalog.shouldRemoveKey($0) }.sorted()
    }

    @discardableResult
    static func removeKeys(
        in defaults: UserDefaults = .standard,
        report: inout UnifyDataLifecycleReport
    ) -> Int {
        let keys = collectKeys(in: defaults)
        for key in keys {
            defaults.removeObject(forKey: key)
            report.recordRemoved(userDefaultsKey: key)
        }
        defaults.synchronize()
        return keys.count
    }
}

enum UnifyDataLifecycleFileRemoval {
    @discardableResult
    static func removeItemIfExists(
        at url: URL,
        fileManager: FileManager = .default,
        logPrefix: String,
        report: inout UnifyDataLifecycleReport
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        do {
            try fileManager.removeItem(at: url)
            print("\(logPrefix) deleted \(url.lastPathComponent)")
            report.recordRemoved(path: url.path)
            return true
        } catch {
            let message = "failed deleting \(url.path): \(error)"
            print("\(logPrefix) \(message)")
            report.recordFailure(message)
            return false
        }
    }

    static func removeSecretaryDebugArtifacts(
        fileManager: FileManager = .default,
        logPrefix: String,
        report: inout UnifyDataLifecycleReport
    ) {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let artifactsDir = documents.appendingPathComponent("Artifacts", isDirectory: true)
        guard fileManager.fileExists(atPath: artifactsDir.path) else { return }

        guard let names = try? fileManager.contentsOfDirectory(atPath: artifactsDir.path) else {
            return
        }

        for name in names where name.hasSuffix(".jsonl") {
            let url = artifactsDir.appendingPathComponent(name)
            _ = removeItemIfExists(
                at: url,
                fileManager: fileManager,
                logPrefix: logPrefix,
                report: &report
            )
        }
    }

    static func clearURLImageCaches(report: inout UnifyDataLifecycleReport) {
        URLCache.shared.removeAllCachedResponses()
        report.note("URLCache.shared.removeAllCachedResponses()")
    }
}

/// Design hooks for server-side / federated deletion. No network calls in Phase 1.
enum UnifyRemotePublicationLifecycle {
    // TODO(Phase 2): DELETE published profile projection for node + publicProfileID.
    static func deletePublishedProfile(nodeID: String, publicProfileID: String) async throws {
        throw UnifyRemotePublicationLifecycleError.notImplemented("deletePublishedProfile")
    }

    // Implemented via `AppServices.deletePublicMedia` / `deleteStaleRemotePublicMedia`.
    static func deleteUploadedPublicMedia(storageKey: String, nodeID: String) async throws {
        _ = nodeID
        _ = storageKey
        throw UnifyRemotePublicationLifecycleError.notImplemented(
            "Use AppServices.deletePublicMedia from a live AppServices instance."
        )
    }

    // TODO(Phase 2): Remove remote retrieval_documents rows (may overlap with unpublish).
    static func deleteRemoteRetrievalDocuments(nodeID: String, publicProfileID: String) async throws {
        throw UnifyRemotePublicationLifecycleError.notImplemented("deleteRemoteRetrievalDocuments")
    }

    // TODO(Phase 2): Unpublish seller surface and delete orphaned media blobs for that profile.
    static func unpublishSellerSurfaceWithMediaCleanup(nodeID: String, publicProfileID: String) async throws {
        throw UnifyRemotePublicationLifecycleError.notImplemented("unpublishSellerSurfaceWithMediaCleanup")
    }
}

enum UnpublishRemotePublishedDataError: LocalizedError {
    case missingFederationIdentity

    var errorDescription: String? {
        switch self {
        case .missingFederationIdentity:
            return "No federation identity is available on this device."
        }
    }
}

enum UnifyRemotePublicationLifecycleError: Error, CustomStringConvertible {
    case notImplemented(String)

    var description: String {
        switch self {
        case .notImplemented(let operation):
            return "UnifyRemotePublicationLifecycle.\(operation) is not implemented yet."
        }
    }
}

// MARK: - Exchange runtime graph

@MainActor
private struct ExchangeGraph {
    let dependencies: ExchangeBootstrap.Dependencies
    let bundle: ExchangeBootstrap.Bundle
    let relayClient: ExchangeHTTPRelayClient?
    let store: any ExchangeStore
    let facade: ExchangeFacade
    let chatBridge: ExchangeChatBridge
    let syncEngine: ExchangeSyncEngine
    let secretaryStyleStore: any ExchangeSecretaryStyleStore
    let providerSurfaceDiagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore
}

private extension AppServices {
    static func buildExchangeGraph(
        databaseURL: URL,
        constitutionProvider: @escaping @Sendable () -> String?,
        styleTextProvider: @escaping @Sendable () -> String?,
        discoveryHeroProgressReporter: DiscoveryHeroProgressReporterBox,
        requesterLocationProvider: any ExchangeRequesterLocationProviding
    ) throws -> ExchangeGraph {
        let intelligenceProvider = OnDeviceExchangeIntelligenceProvider(
            runner: LlamaExchangeModelRunner(
                secretaryConstitutionProvider: constitutionProvider
            )
        )

        var liveDeps = ExchangeBootstrap.makeLiveDependencies()
        liveDeps.discoveryHeroProgressReporter = discoveryHeroProgressReporter
        let searchIntentDiagnostics = SearchIntentExtractionDiagnosticsStore()
        let onDeviceSearchIntentProvider = OnDeviceSearchIntentJSONProvider(
            runner: LlamaExchangeModelRunner(
                secretaryConstitutionProvider: constitutionProvider
            ),
            runtimeMonitor: liveDeps.runtimeMonitor
        )
        let asyncSearchIntentExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: onDeviceSearchIntentProvider,
            fallbackExtractor: CanonicalSearchIntentHeuristicExtractor(),
            diagnosticsStore: searchIntentDiagnostics
        )
        let providerSurfaceDiagnostics = ProviderSurfaceEnrichmentDiagnosticsStore()
        let providerSurfaceJSONProvider = OnDeviceProviderSurfaceEnrichmentJSONProvider(
            runner: LlamaExchangeModelRunner(
                secretaryConstitutionProvider: constitutionProvider
            ),
            runtimeMonitor: liveDeps.runtimeMonitor
        )
        let indexedSurfaceEnricher = LLMIndexedProviderSurfaceEnricher(
            provider: providerSurfaceJSONProvider,
            config: .init(timeoutSeconds: 2.0),
            diagnosticsStore: providerSurfaceDiagnostics
        )
        let llmProviderResponseAssessmentFlag = llmProviderResponseAssessmentFlagResolution
        let enableLLMProviderResponseAssessment = llmProviderResponseAssessmentFlag.enabled
        #if DEBUG
        print(
            "[AppServices] llmProviderResponseAssessment enabled=\(enableLLMProviderResponseAssessment) source=\(llmProviderResponseAssessmentFlag.source.rawValue)"
        )
        #endif
        if enableLLMProviderResponseAssessment {
            let responseAssessmentProvider = OnDeviceProviderResponseAssessmentJSONProvider(
                runner: LlamaExchangeModelRunner(
                    secretaryConstitutionProvider: constitutionProvider
                ),
                runtimeMonitor: liveDeps.runtimeMonitor
            )
            let responseAssessmentDiagnostics = ProviderResponseAssessmentDiagnosticsStore()
            let asyncAssessmentEngine = LLMExchangeProviderResponseAssessmentEngine(
                provider: responseAssessmentProvider,
                diagnosticsStore: responseAssessmentDiagnostics,
                config: .init(timeoutSeconds: 2.0)
            )
            liveDeps.asyncProviderResponseAssessmentEngine = asyncAssessmentEngine
            liveDeps.enableAsyncSecondHalfEvaluation = true
        }
        liveDeps.intelligenceProvider = intelligenceProvider
        liveDeps.asyncSearchIntentExtractor = asyncSearchIntentExtractor
        liveDeps.indexedSurfaceEnricher = indexedSurfaceEnricher
        liveDeps.secretaryConstitutionProvider = constitutionProvider
        liveDeps.secretaryStyleTextProvider = styleTextProvider
        liveDeps.secretaryStyleStore = ExchangeUserDefaultsSecretaryStyleStore()
        let forYouStandingInterestRunner = LlamaExchangeModelRunner(
            secretaryConstitutionProvider: constitutionProvider
        )
        liveDeps.forYouStandingInterestService = ForYouStandingInterestService(
            generator: ForYouStandingInterestLLMGenerator(
                runner: forYouStandingInterestRunner,
                fallback: ForYouStandingInterestHeuristicGenerator()
            )
        )
        liveDeps.requesterLocationProvider = requesterLocationProvider

        let bundle = try ExchangeBootstrap.makeBundle(
            databaseURL: databaseURL,
            dependencies: liveDeps
        )

        return ExchangeGraph(
            dependencies: liveDeps,
            bundle: bundle,
            relayClient: liveDeps.relayClient as? ExchangeHTTPRelayClient,
            store: bundle.store,
            facade: bundle.facade,
            chatBridge: bundle.chatBridge,
            syncEngine: bundle.syncEngine,
            secretaryStyleStore: liveDeps.secretaryStyleStore,
            providerSurfaceDiagnosticsStore: providerSurfaceDiagnostics
        )
    }

    static func tokenHashPrefix(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}

private extension UNAuthorizationStatus {
    var logToken: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}

struct ExchangeIdentityDebugSummary: Sendable, Hashable {
    let nodeID: String?
    let publicKeyID: String?
    let displayName: String?
    let sourceLabel: String
    let localProfileExists: Bool
    let localOfferCount: Int
    let localThreadCount: Int
    let localInboxCount: Int
    let sellerWorkspaceExists: Bool
    let databaseStatus: String
    let databasePath: String
    let restoredIdentityWithEmptyLocalStore: Bool
    let restoredMessage: String?
}
