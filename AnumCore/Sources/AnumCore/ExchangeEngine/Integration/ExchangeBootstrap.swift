import Foundation

public enum ExchangeBootstrap {
    public struct Dependencies: Sendable {
        public var directoryClient: (any ExchangeDirectoryClient)?
        public var dmAttachmentClient: ExchangeHTTPDMAttachmentClient?
        public var runtimeMonitor: any ExchangeRuntimeActivityMonitor
        public var identityService: any ExchangeIdentityService
        public var relayClient: any ExchangeRelayClient
        public var transportPolicy: ExchangeTransportPolicy
        public var syncPolicy: ExchangeSyncPolicy

        /// Optional provider for the local node id, used by discovery/trust-aware ranking.
        public var localNodeIDProvider: (@Sendable () async throws -> String?)?

        /// User-editable secretary **constitution** (role, boundaries). Injected in Exchange runner scaffold, not as style.
        public var secretaryConstitutionProvider: (@Sendable () -> String?)?

        /// User-editable **style & tone** freeform (voice only). Used for agency context and typed profile sync — not merged as global representation in the runner.
        public var secretaryStyleTextProvider: (@Sendable () -> String?)?
        public var secretaryStyleStore: any ExchangeSecretaryStyleStore

        public var intelligenceProvider: any ExchangeIntelligenceProvider
        public var asyncSearchIntentExtractor: (any AsyncOpenEndedSearchIntentExtractor)?
        public var indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher
        public var asyncProviderResponseAssessmentEngine: (any AsyncExchangeProviderResponseAssessmentEngine)?
        public var enableAsyncSecondHalfEvaluation: Bool
        /// When true, provider threads run `providerInquiryCompare` before coordinator and skip the separate inbound inquiry classifier.
        public var enableCompareFirstProviderInbound: Bool

        /// Optional standing-interest service for the For You directory rail. When `nil`, `makeBundle` uses a default heuristic-backed instance.
        public var forYouStandingInterestService: ForYouStandingInterestService?

        /// Optional live Discovery hero progress reporter (UI layer binds implementation).
        public var discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)?

        /// Optional one-shot device location for requester spatial anchors (app implements via CoreLocation).
        public var requesterLocationProvider: (any ExchangeRequesterLocationProviding)?

        public init(
            directoryClient: (any ExchangeDirectoryClient)? = nil,
            dmAttachmentClient: ExchangeHTTPDMAttachmentClient? = nil,
            runtimeMonitor: any ExchangeRuntimeActivityMonitor = ExchangeRuntimeActivityState(),
            identityService: any ExchangeIdentityService = BootstrappedIdentityService(),
            relayClient: any ExchangeRelayClient = BootstrappedRelayClient(),
            transportPolicy: ExchangeTransportPolicy = ExchangeTransportPolicy(),
            syncPolicy: ExchangeSyncPolicy = ExchangeSyncPolicy(),
            localNodeIDProvider: (@Sendable () async throws -> String?)? = nil,
            secretaryConstitutionProvider: (@Sendable () -> String?)? = nil,
            secretaryStyleTextProvider: (@Sendable () -> String?)? = nil,
            secretaryStyleStore: any ExchangeSecretaryStyleStore = ExchangeDefaultSecretaryStyleStore(),
            intelligenceProvider: any ExchangeIntelligenceProvider = ExchangeFallbackIntelligenceProvider(),
            asyncSearchIntentExtractor: (any AsyncOpenEndedSearchIntentExtractor)? = nil,
            indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher = NoopIndexedProviderSurfaceEnricher(),
            asyncProviderResponseAssessmentEngine: (any AsyncExchangeProviderResponseAssessmentEngine)? = nil,
            enableAsyncSecondHalfEvaluation: Bool = false,
            enableCompareFirstProviderInbound: Bool = true,
            forYouStandingInterestService: ForYouStandingInterestService? = nil,
            discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)? = nil,
            requesterLocationProvider: (any ExchangeRequesterLocationProviding)? = nil
        ) {
            self.directoryClient = directoryClient
            self.dmAttachmentClient = dmAttachmentClient
            self.runtimeMonitor = runtimeMonitor
            self.identityService = identityService
            self.relayClient = relayClient
            self.transportPolicy = transportPolicy
            self.syncPolicy = syncPolicy
            self.localNodeIDProvider = localNodeIDProvider
            self.secretaryConstitutionProvider = secretaryConstitutionProvider
            self.secretaryStyleTextProvider = secretaryStyleTextProvider
            self.secretaryStyleStore = secretaryStyleStore
            self.intelligenceProvider = intelligenceProvider
            self.asyncSearchIntentExtractor = asyncSearchIntentExtractor
            self.indexedSurfaceEnricher = indexedSurfaceEnricher
            self.asyncProviderResponseAssessmentEngine = asyncProviderResponseAssessmentEngine
            self.enableAsyncSecondHalfEvaluation = enableAsyncSecondHalfEvaluation
            self.enableCompareFirstProviderInbound = enableCompareFirstProviderInbound
            self.forYouStandingInterestService = forYouStandingInterestService
            self.discoveryHeroProgressReporter = discoveryHeroProgressReporter
            self.requesterLocationProvider = requesterLocationProvider
        }
    }

    public struct Bundle: Sendable {
        public var store: any ExchangeStore
        public var facade: ExchangeFacade
        public var chatBridge: ExchangeChatBridge
        public var syncEngine: ExchangeSyncEngine

        public init(
            store: any ExchangeStore,
            facade: ExchangeFacade,
            chatBridge: ExchangeChatBridge,
            syncEngine: ExchangeSyncEngine
        ) {
            self.store = store
            self.facade = facade
            self.chatBridge = chatBridge
            self.syncEngine = syncEngine
        }
    }

    public static let liveFederationBaseURL = URL(string: "https://unify-federation-server-production.up.railway.app")!

    /// DEBUG-only UserDefaults key for staging federation base URL override.
    public static let debugFederationBaseURLUserDefaultsKey = "unify.debug.federationBaseURL"

    /// DEBUG-only process environment key (Xcode scheme → Environment Variables).
    public static let debugFederationBaseURLEnvironmentKey = "UNIFY_DEBUG_FEDERATION_BASE_URL"

    /// DEBUG-only launch argument name (Xcode scheme → Arguments Passed On Launch).
    public static let debugFederationBaseURLLaunchArgumentKey = "-UNIFY_DEBUG_FEDERATION_BASE_URL"

    /// DEBUG fallback when no override is set (same origin as production).
    public static let debugFederationBaseURLProductionDefault = liveFederationBaseURL

    @available(*, deprecated, renamed: "debugFederationBaseURLProductionDefault")
    public static let debugFederationBaseURLLANDefault = liveFederationBaseURL

    public enum FederationBaseURLSource: String, Sendable {
        case production
        case productionDefault
        case debugLaunchArgument
        case debugEnvironment
        case debugUserDefaults
    }

    public struct ResolvedFederationBaseURL: Sendable {
        public var url: URL
        public var source: FederationBaseURLSource

        public init(url: URL, source: FederationBaseURLSource) {
            self.url = url
            self.source = source
        }
    }

    /// Federation HTTP base URL. **Release:** always production. **DEBUG:** launch arg → env → UserDefaults → production default.
    public static func resolvedFederationBaseURLConfiguration() -> ResolvedFederationBaseURL {
        #if DEBUG
        return resolveDebugFederationBaseURLConfiguration(
            environment: ProcessInfo.processInfo.environment,
            launchArguments: ProcessInfo.processInfo.arguments,
            userDefaultsString: sanitizedDebugUserDefaultsFederationBaseURL()
        )
        #else
        return ResolvedFederationBaseURL(url: liveFederationBaseURL, source: .production)
        #endif
    }

    public static func resolvedFederationBaseURL() -> URL {
        resolvedFederationBaseURLConfiguration().url
    }

    /// Logs resolved federation base URL at startup (no secrets).
    public static func logFederationBaseURLAtStartup() {
        #if DEBUG
        _ = clearTemporaryDebugFederationBaseURLOverrideFromUserDefaultsIfNeeded()
        #endif
        let resolved = resolvedFederationBaseURLConfiguration()
        Swift.print(
            "[ExchangeBootstrap] federationBaseURL=\(resolved.url.absoluteString) source=\(resolved.source.rawValue)"
        )
    }

    /// Skip directory registration / push upload on launch for ephemeral or invalid federation bases.
    public static func shouldSkipLaunchFederationNetworkRegistration(
        resolved: ResolvedFederationBaseURL? = nil
    ) -> Bool {
        let config = resolved ?? resolvedFederationBaseURLConfiguration()
        guard let host = config.url.host?.lowercased(), !host.isEmpty else { return true }
        if host.contains("trycloudflare.com") {
            return true
        }
        return false
    }

    #if DEBUG
    /// Persist a DEBUG staging override (UserDefaults). Pass `nil` or empty to clear.
    public static func setDebugFederationBaseURLOverride(_ urlString: String?) {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: debugFederationBaseURLUserDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: debugFederationBaseURLUserDefaultsKey)
        }
    }

    /// DEBUG-only env / launch flag to reset local Exchange identity before boot.
    public static let debugResetExchangeIdentityEnvironmentKey = "UNIFY_DEBUG_RESET_EXCHANGE_IDENTITY"

    /// DEBUG-only launch argument (e.g. `-UNIFY_DEBUG_RESET_EXCHANGE_IDENTITY=1`).
    public static let debugResetExchangeIdentityLaunchArgumentKey = "-UNIFY_DEBUG_RESET_EXCHANGE_IDENTITY"

    /// DEBUG-only: explicit opt-in for `ExchangeDebugSeeder.seedAll` (never on normal cold launch).
    public static let debugExchangeSeedAllEnvironmentKey = "UNIFY_DEBUG_EXCHANGE_SEED_ALL"
    public static let debugExchangeSeedAllLaunchArgumentKey = "-UNIFY_DEBUG_EXCHANGE_SEED_ALL"

    /// DEBUG-only: when true, deferred boot may run `ExchangeDebugSeeder.seedAll`.
    public static func isDebugExchangeSeedAllEnabled() -> Bool {
        if isTruthyDebugFlag(ProcessInfo.processInfo.environment[debugExchangeSeedAllEnvironmentKey]) {
            return true
        }
        for arg in ProcessInfo.processInfo.arguments {
            if arg == debugExchangeSeedAllLaunchArgumentKey {
                return true
            }
            let prefix = debugExchangeSeedAllLaunchArgumentKey + "="
            if arg.hasPrefix(prefix) {
                let value = String(arg.dropFirst(prefix.count))
                if isTruthyDebugFlag(value) {
                    return true
                }
            }
        }
        return false
    }

    private static func isDebugExchangeIdentityResetRequested() -> Bool {
        if isTruthyDebugFlag(ProcessInfo.processInfo.environment[debugResetExchangeIdentityEnvironmentKey]) {
            return true
        }

        for arg in ProcessInfo.processInfo.arguments {
            if arg == debugResetExchangeIdentityLaunchArgumentKey {
                return true
            }
            let prefix = debugResetExchangeIdentityLaunchArgumentKey + "="
            if arg.hasPrefix(prefix) {
                let value = String(arg.dropFirst(prefix.count))
                if isTruthyDebugFlag(value) {
                    return true
                }
            }
        }

        return false
    }

    private static func isTruthyDebugFlag(_ raw: String?) -> Bool {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else {
            return false
        }
        return value == "1" || value == "true" || value == "yes"
    }

    private static func clearExchangeIdentityUserDefaultsCache() {
        let keys = [
            "exchange.bootstrap.displayName",
            "secretary.apns.pendingTokenHex.v1",
            "secretary.apns.lastRegisteredTokenHex.v1",
            "secretary.apns.lastRegisteredContext.v1",
            "secretary.apns.registrationAttemptFailed.v1"
        ]
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
    #endif

    /// DEBUG-only no-op in Release. Clears Keychain federation identity when env/launch flag is set.
    public static func performDebugExchangeIdentityResetIfRequested() {
        #if DEBUG
        guard isDebugExchangeIdentityResetRequested() else { return }

        Swift.print("[ExchangeBootstrap] DEBUG reset exchange identity requested")

        do {
            try NodeIdentityVault.shared.resetIdentityForDebugOnly()
        } catch {
            Swift.print(
                "[ExchangeBootstrap] DEBUG reset exchange identity failed: \(error.localizedDescription)"
            )
            return
        }

        clearExchangeIdentityUserDefaultsCache()
        Swift.print("[ExchangeBootstrap] DEBUG reset exchange identity completed")
        #endif
    }

    private static func parseFederationHTTPBaseURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        if let direct = parseStrictFederationHTTPBaseURL(trimmed) {
            return direct
        }
        // Scheme env vars are sometimes polluted with pasted notes; accept the first URL token.
        if let extracted = extractFirstFederationHTTPBaseURLToken(from: trimmed) {
            return parseStrictFederationHTTPBaseURL(extracted)
        }
        return nil
    }

    private static func parseStrictFederationHTTPBaseURL(_ trimmed: String) -> URL? {
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }
        return parsed
    }

    private static func extractFirstFederationHTTPBaseURLToken(from raw: String) -> String? {
        let firstLine = raw
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        if firstLine.lowercased().hasPrefix("http://") || firstLine.lowercased().hasPrefix("https://") {
            let stopChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>"))
            let token = firstLine.unicodeScalars
                .prefix { !stopChars.contains($0) }
            let candidate = String(String.UnicodeScalarView(token))
            return candidate.isEmpty ? nil : candidate
        }

        guard let range = raw.range(
            of: #"https?://[^\s<>"']+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(raw[range])
    }

    #if DEBUG
    /// Testable DEBUG resolver (launch arg → env → UserDefaults → production default).
    internal static func resolveDebugFederationBaseURLConfiguration(
        environment: [String: String],
        launchArguments: [String],
        userDefaultsString: String?
    ) -> ResolvedFederationBaseURL {
        if let launchURL = federationBaseURLFromLaunchArguments(launchArguments) {
            return ResolvedFederationBaseURL(url: launchURL, source: .debugLaunchArgument)
        }
        if let envURL = parseFederationHTTPBaseURL(
            environment[debugFederationBaseURLEnvironmentKey]
        ) {
            return ResolvedFederationBaseURL(url: envURL, source: .debugEnvironment)
        }
        if let defaultsURL = parseFederationHTTPBaseURL(userDefaultsString) {
            return ResolvedFederationBaseURL(url: defaultsURL, source: .debugUserDefaults)
        }
        return ResolvedFederationBaseURL(
            url: debugFederationBaseURLProductionDefault,
            source: .productionDefault
        )
    }

    /// Clears persisted DEBUG overrides that point at local/LAN/tunnel hosts from prior smoke tests.
    @discardableResult
    private static func clearTemporaryDebugFederationBaseURLOverrideFromUserDefaultsIfNeeded() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: debugFederationBaseURLUserDefaultsKey),
              let url = parseFederationHTTPBaseURL(raw),
              let host = url.host?.lowercased(),
              isTemporaryDebugFederationHost(host)
        else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: debugFederationBaseURLUserDefaultsKey)
        Swift.print(
            "[ExchangeBootstrap] cleared temporary UserDefaults federation override host=\(host)"
        )
        return true
    }

    private static func sanitizedDebugUserDefaultsFederationBaseURL() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: debugFederationBaseURLUserDefaultsKey) else {
            return nil
        }
        guard let url = parseFederationHTTPBaseURL(raw),
              let host = url.host?.lowercased(),
              !isTemporaryDebugFederationHost(host)
        else {
            return nil
        }
        return raw
    }

    private static func isTemporaryDebugFederationHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.") {
            return true
        }
        if host.hasSuffix(".trycloudflare.com") || host.contains("trycloudflare.com") {
            return true
        }
        return false
    }
    #endif

    private static func federationBaseURLFromLaunchArguments(_ launchArguments: [String]? = nil) -> URL? {
        let args = launchArguments ?? ProcessInfo.processInfo.arguments
        let prefix = debugFederationBaseURLLaunchArgumentKey + "="
        for index in args.indices {
            let arg = args[index]
            if arg == debugFederationBaseURLLaunchArgumentKey {
                if index + 1 < args.count {
                    return parseFederationHTTPBaseURL(args[index + 1])
                }
                continue
            }
            if arg.hasPrefix(prefix) {
                return parseFederationHTTPBaseURL(String(arg.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    public static func makeLiveDependencies() -> Dependencies {
        let identityService = BootstrappedIdentityService()
        let runtimeMonitor = ExchangeRuntimeActivityState()

        let federationBase = resolvedFederationBaseURL()
        #if DEBUG
        Swift.print("[ExchangeBootstrap] makeLiveDependencies federationBaseURL=\(federationBase.absoluteString)")
        #endif

        let relayClient = ExchangeHTTPRelayClient(
            baseURL: federationBase,
            localNodeIDProvider: {
                let identity = try await identityService.localIdentity()
                return identity.nodeID
            }
        )

        let directoryClient = ExchangeHTTPDirectoryClient(
            baseURL: federationBase
        )

        let dmAttachmentClient = ExchangeHTTPDMAttachmentClient(baseURL: federationBase)

        return Dependencies(
            directoryClient: directoryClient,
            dmAttachmentClient: dmAttachmentClient,
            runtimeMonitor: runtimeMonitor,
            identityService: identityService,
            relayClient: relayClient,
            transportPolicy: ExchangeTransportPolicy(),
            // Allow relay fetch + inbox ingest while local generation is active once `runtimeMonitor` reflects it;
            // otherwise `runPass` no-ops and DMs only appear after a later cold sync.
            syncPolicy: ExchangeSyncPolicy(allowsSyncWhileGenerating: true),
            localNodeIDProvider: {
                let identity = try await identityService.localIdentity()
                return identity.nodeID
            },
            secretaryConstitutionProvider: nil,
            secretaryStyleTextProvider: nil,
            secretaryStyleStore: ExchangeDefaultSecretaryStyleStore(),
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            asyncSearchIntentExtractor: nil,
            indexedSurfaceEnricher: NoopIndexedProviderSurfaceEnricher(),
            asyncProviderResponseAssessmentEngine: nil,
            enableAsyncSecondHalfEvaluation: false,
            enableCompareFirstProviderInbound: true
        )
    }

    public static func makeFacade(
        databaseURL: URL,
        dependencies: Dependencies = .init()
    ) throws -> ExchangeFacade {
        try makeBundle(
            databaseURL: databaseURL,
            dependencies: dependencies
        ).facade
    }

    public static func makeChatBridge(
        databaseURL: URL,
        dependencies: Dependencies = .init()
    ) throws -> ExchangeChatBridge {
        try makeBundle(
            databaseURL: databaseURL,
            dependencies: dependencies
        ).chatBridge
    }

    public static func makeSyncEngine(
        databaseURL: URL,
        dependencies: Dependencies = .init()
    ) throws -> ExchangeSyncEngine {
        try makeBundle(
            databaseURL: databaseURL,
            dependencies: dependencies
        ).syncEngine
    }

    public static func makeBundle(
        databaseURL: URL,
        dependencies: Dependencies = .init()
    ) throws -> Bundle {
        let store = try ExchangeSQLiteStore(databaseURL: databaseURL)
        let federationBase = resolvedFederationBaseURL()

        let intelligenceProvider = dependencies.intelligenceProvider

        let postureModeler = ExchangePostureModeler(intelligenceProvider: intelligenceProvider)
        let summaryEngine = ExchangeSummaryEngine()
        let failureResolver = ExchangeFailureResolver()
        let fitEngine = ExchangeFitEngine()
        let draftEngine = ExchangeDraftEngine(intelligenceProvider: intelligenceProvider)
        let approvalEngine = ExchangeApprovalEngine()
        let policyEngine = ExchangePolicyEngine()
        let threadEngine = ExchangeThreadEngine()
        let publicationService = ExchangeDefaultPublicationService()

        let retrievalStore = ExchangeRetrievalStore()
        let sentenceEmbedder = ONNXSentenceEmbedder()
        let retrievalDocumentBuilder = ExchangeRetrievalDocumentBuilder()

        let sellerSurfaceService = ExchangeDefaultSellerSurfaceService(
            retrievalDocumentBuilder: retrievalDocumentBuilder
        )

        let interpreter = ExchangeInterpreter(
            intelligenceProvider: intelligenceProvider,
            asyncSearchIntentExtractor: dependencies.asyncSearchIntentExtractor
        )

        let retrievalEngine = ExchangeRetrievalEngine(
            store: retrievalStore,
            embeddingProvider: sentenceEmbedder
        )

        let retrievalIngestor = ExchangeRetrievalIngestor(
            store: retrievalStore,
            embeddingProvider: sentenceEmbedder
        )

        let discoveryEngine = ExchangeDiscoveryEngine(
            store: store,
            directoryClient: dependencies.directoryClient,
            localNodeIDProvider: dependencies.localNodeIDProvider,
            embeddingProvider: sentenceEmbedder,
            retrievalStore: retrievalStore,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: retrievalIngestor,
            discoveryHeroProgressReporter: dependencies.discoveryHeroProgressReporter
        )
        #if DEBUG
        Swift.print("[ExchangeBootstrap] ExchangeDiscoveryEngine directory queryEmbedding uses shared ONNXSentenceEmbedder")
        #endif

        let discoveryService = ExchangeDiscoveryService(
            discoveryEngine: discoveryEngine,
            fitEngine: fitEngine,
            discoveryHeroProgressReporter: dependencies.discoveryHeroProgressReporter
        )

        let messageComposer = ExchangeMessageComposer(
            draftEngine: draftEngine,
            policyEngine: policyEngine
        )

        let orchestrator = ExchangeOrchestrator(
            store: store,
            interpreter: interpreter,
            postureModeler: postureModeler,
            discoveryService: discoveryService,
            messageComposer: messageComposer,
            approvalEngine: approvalEngine,
            policyEngine: policyEngine,
            threadEngine: threadEngine,
            failureResolver: failureResolver,
            summaryEngine: summaryEngine,
            discoveryHeroProgressReporter: dependencies.discoveryHeroProgressReporter,
            requesterLocationProvider: dependencies.requesterLocationProvider
        )

        let envelopeService = ExchangeEnvelopeService(
            identityService: dependencies.identityService,
            federationBaseURL: federationBase
        )

        let continuationCoordinator = ExchangeThreadContinuationCoordinator()

        let federationService = ExchangeDefaultFederationService(
            store: store,
            policyEngine: policyEngine,
            envelopeService: envelopeService,
            identityService: dependencies.identityService,
            relayClient: dependencies.relayClient,
            runtimeMonitor: dependencies.runtimeMonitor,
            transportPolicy: dependencies.transportPolicy,
            continuationCoordinator: continuationCoordinator,
            threadEngine: threadEngine,
            federationBaseURL: federationBase
        )

        let publicationCoordinator: (any ExchangeSellerPublicationCoordinating)?
        if let directoryClient = dependencies.directoryClient {
            publicationCoordinator = ExchangeSellerPublicationCoordinator(
                store: store,
                directoryClient: directoryClient,
                sellerSurfaceService: sellerSurfaceService,
                publicationService: publicationService,
                embeddingProvider: sentenceEmbedder,
                indexedSurfaceBuilder: ExchangeIndexedProviderSurfaceBuilder(),
                retrievalDocumentBuilder: retrievalDocumentBuilder,
                indexedSurfaceEnricher: dependencies.indexedSurfaceEnricher
            )
        } else {
            publicationCoordinator = nil
        }

        #if DEBUG
        let closureComposer: (any ExchangeRequesterClosureComposing)? = MockExchangeRequesterClosureComposer()
        #else
        let closureComposer: (any ExchangeRequesterClosureComposing)? = nil
        #endif

        let requesterFlow = ExchangeSecondHalfRequesterFlow(
            asyncAssessmentEngine: dependencies.asyncProviderResponseAssessmentEngine
        )
        let secondHalfCoordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: requesterFlow
        )

        let secondHalfFacade = ExchangeSecondHalfFacade(
            coordinator: secondHalfCoordinator,
            styleStore: dependencies.secretaryStyleStore,
            localNodeIDProvider: dependencies.localNodeIDProvider,
            exchangeStore: store,
            closureComposer: closureComposer,
            preferAsyncCoordinatorEvaluation: dependencies.enableAsyncSecondHalfEvaluation
        )

        let forYouStandingInterestService =
            dependencies.forYouStandingInterestService
            ?? ForYouStandingInterestService()

        let facade = ExchangeFacade(
            orchestrator: orchestrator,
            federationService: federationService,
            store: store,
            summaryEngine: summaryEngine,
            sellerSurfaceService: sellerSurfaceService,
            publicationService: publicationService,
            publicationCoordinator: publicationCoordinator,
            secondHalfFacade: secondHalfFacade,
            intelligenceProvider: intelligenceProvider,
            secretaryConstitutionProvider: dependencies.secretaryConstitutionProvider,
            secretaryStyleTextProvider: dependencies.secretaryStyleTextProvider,
            directoryClient: dependencies.directoryClient,
            enableCompareFirstProviderInbound: dependencies.enableCompareFirstProviderInbound,
            forYouStandingInterestService: forYouStandingInterestService,
            forYouDirectoryEmbeddingProvider: sentenceEmbedder,
            contactSignalSendService: ContactSignalSendService(
                store: store,
                envelopeService: envelopeService,
                relayClient: dependencies.relayClient
            ),
            directMessageSendService: DirectMessageSendService(
                store: store,
                envelopeService: envelopeService,
                identityService: dependencies.identityService,
                relayClient: dependencies.relayClient,
                dmAttachmentClient: dependencies.dmAttachmentClient,
                federationBaseURL: federationBase
            ),
            dmAttachmentClient: dependencies.dmAttachmentClient
        )

        let syncEngine = ExchangeSyncEngine(
            store: store,
            syncStateStore: store,
            facade: facade,
            relayClient: dependencies.relayClient,
            runtimeMonitor: dependencies.runtimeMonitor,
            policy: dependencies.syncPolicy
        )

        let chatBridge = ExchangeChatBridge(
            facade: facade
        )

        Task {
            await facade.registerSecretarySQLiteHooksIfNeeded()
        }

        return Bundle(
            store: store,
            facade: facade,
            chatBridge: chatBridge,
            syncEngine: syncEngine
        )
    }
}

public actor BootstrappedIdentityService: ExchangeIdentityService {
    private let identity: ExchangeLocalIdentity

    public init() {
        let defaults = UserDefaults.standard

        let stableIdentity: NodeIdentity
        do {
            stableIdentity = try NodeIdentityVault.shared.loadOrCreateIdentity()
        } catch {
            fatalError("Failed to load or create stable node identity: \(error)")
        }

        let nodeID = stableIdentity.nodeID

        let storedDisplayName = defaults.string(forKey: "exchange.bootstrap.displayName")
        let displayName: String = {
            if let storedDisplayName,
               !storedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return storedDisplayName
            }

            let generated = "Unify Node " + String(nodeID.suffix(6))
            defaults.set(generated, forKey: "exchange.bootstrap.displayName")
            return generated
        }()

        let encryptionMaterial = try? NodeIdentityVault.shared.loadOrCreateEncryptionMaterial()

        self.identity = ExchangeLocalIdentity(
            nodeID: nodeID,
            displayName: displayName,
            publicKeyID: stableIdentity.publicKeyID,
            encryptionPublicKey: encryptionMaterial?.encryptionPublicKeyBase64,
            encryptionKeyID: encryptionMaterial?.encryptionKeyID,
            verification: .selfAsserted,
            supportedProtocolVersions: [ExchangeProtocolVersion.current],
            defaultRouteHint: .localLoopback(),
            metadata: [
                "bootstrap_mode": "true",
                "identity_source": "keychain_stable_seed",
                "federation_base_url": "https://unify-federation-server-production.up.railway.app"
            ]
        )

        #if DEBUG
        Swift.print(
            "[BootstrappedIdentityService] init supportedProtocolVersions=\(identity.supportedProtocolVersions.joined(separator: ","))"
        )
        #endif
    }

    public func localIdentity() async throws -> ExchangeLocalIdentity {
        #if DEBUG
        Swift.print(
            "[BootstrappedIdentityService] localIdentity supportedProtocolVersions=\(identity.supportedProtocolVersions.joined(separator: ","))"
        )
        #endif

        return identity
    }

    public func signEnvelope(_ envelope: ExchangeRelayEnvelope) async throws -> ExchangeRelayEnvelope.Signature {
        ExchangeRelayEnvelope.Signature(
            algorithm: .other,
            value: "signed:\(envelope.id.uuidString)",
            keyID: identity.publicKeyID,
            signatureVersion: "1"
        )
    }

    public func verifyEnvelopeSignature(
        _ envelope: ExchangeRelayEnvelope,
        expectedKeyID: String?
    ) async throws -> ExchangeEnvelopeVerificationResult {
        guard let signature = envelope.signature else {
            return .missingSignature
        }

        guard envelope.sender.publicKeyID != nil else {
            return .missingSenderKey
        }

        if let expectedKeyID,
           signature.keyID != expectedKeyID {
            return .keyMismatch(
                expected: expectedKeyID,
                actual: signature.keyID
            )
        }

        guard signature.algorithm == .other else {
            return .unsupportedSignatureVersion(signature.signatureVersion)
        }

        return .valid
    }
}

public actor BootstrappedRelayClient: ExchangeRelayClient {
    public init() {}

    public func send(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult {
        ExchangeRelaySendResult(
            status: .accepted,
            externalReference: envelope.ordering.idempotencyKey ?? envelope.id.uuidString,
            acceptedAt: Date(),
            routeSummary: route?.summaryLine ?? "bootstrap-relay",
            note: "Bootstrap relay accepted the envelope."
        )
    }

    public func fetchDeliveryStatus(reference: String) async throws -> ExchangeRelayDeliveryStatus? {
        ExchangeRelayDeliveryStatus(
            reference: reference,
            status: .accepted,
            checkedAt: Date(),
            note: "Bootstrap relay has no remote delivery tracking."
        )
    }

    public func syncInbox(
        request: ExchangeRelayInboxSyncRequest
    ) async throws -> ExchangeRelayInboxSyncResponse {
        ExchangeRelayInboxSyncResponse(
            receipts: [],
            nextCursor: request.cursor,
            hasMore: false,
            syncedAt: Date(),
            note: "Bootstrap relay has no remote inbox."
        )
    }

    public func acknowledgeInboxItems(
        _ acknowledgements: [ExchangeRelayInboxAcknowledgement]
    ) async throws -> ExchangeRelayInboxAcknowledgeResponse {
        ExchangeRelayInboxAcknowledgeResponse(
            acknowledgedReceiptIDs: acknowledgements.map(\.receiptID),
            rejectedReceiptIDs: [],
            updatedCount: acknowledgements.count,
            note: "Bootstrap relay acknowledged receipts locally."
        )
    }
}
