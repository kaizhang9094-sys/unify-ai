import Foundation
import Testing
@testable import AnumCore

#if DEBUG

@Suite("ExchangeAppSearchSmokeGate")
struct ExchangeAppSearchSmokeGateTests {
    @Test("gate accepts localhost 8787")
    func acceptsLocalhost() throws {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "http://127.0.0.1:8787")!,
            source: .debugEnvironment
        )
        let url = try ExchangeAppSearchSmokeGate.validateResolvedBaseURL(resolved)
        #expect(url.host == "127.0.0.1")
        #expect(url.port == 8787)
    }

    @Test("4H-1 simulator gate rejects Cloudflare tunnel")
    func rejectsCloudflareTunnelForSimulatorSmoke() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "https://mile-leslie-burke-conflicts.trycloudflare.com")!,
            source: .debugEnvironment
        )
        #expect(throws: (any Error).self) {
            try ExchangeAppSearchSmokeGate.validateResolvedBaseURL(resolved)
        }
    }

    @Test("4H-1 simulator gate rejects LAN IP")
    func rejectsLANIPForSimulatorSmoke() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "http://192.168.2.19:8787")!,
            source: .debugEnvironment
        )
        #expect(throws: (any Error).self) {
            try ExchangeAppSearchSmokeGate.validateResolvedBaseURL(resolved)
        }
    }

    @Test("gate rejects production URL")
    func rejectsProduction() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: ExchangeBootstrap.liveFederationBaseURL,
            source: .productionDefault
        )
        #expect(throws: (any Error).self) {
            try ExchangeAppSearchSmokeGate.validateResolvedBaseURL(resolved)
        }
    }

    @Test("snapshot diff detects engine thread selectedOfferID mismatch")
    func engineThreadMismatch() {
        let engine = AppSearchSmokeEngineSnapshot(
            query: "computer",
            scenarioID: "object-lane.computer",
            intentClass: "offerSearch",
            facetsQueryIntentClass: "offerSearch",
            objectType: "computer",
            domainCategory: "product",
            transactionIntent: "buy",
            objectLaneActive: true,
            discoveryCalled: true,
            responseMode: "clientRerank",
            topNodes: ["node-computer-seller"],
            selectedOfferID: "offer-dell-laptop",
            matchedOffersByNode: ["node-computer-seller": ["offer-dell-laptop"]],
            provenObjectOfferIDs: ["offer-dell-laptop"],
            objectEvidenceScoreByOfferID: [:],
            topDocKinds: [],
            forbiddenAttachmentViolations: 0,
            objectLaneFP: 0,
            objectLaneFN: 0,
            strictFailures: [],
            serverRoundTripIssues: []
        )
        let thread = AppSearchSmokeThreadSnapshot(
            threadID: UUID().uuidString,
            selectedOfferID: "offer-multi-computer",
            selectedPublicProfileID: nil,
            selectedCounterpartyID: "node-computer-seller",
            matchedOffersByNode: ["node-computer-seller": ["offer-multi-computer"]],
            provenObjectOfferIDs: [],
            topNodes: ["node-computer-seller"]
        )
        let ui = AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: "offer-dell-laptop",
            matchedOffersByNode: [:],
            preferredMatchCounterpartyID: nil,
            preferredMatchOfferID: "offer-dell-laptop",
            cardOfferID: "offer-dell-laptop",
            visiblePublicProfileID: nil,
            surfaceLead: "offerLed"
        )
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "object-lane.computer",
            queryLabel: "computer",
            expectedSummary: "test",
            objectLaneActive: true,
            selectedOfferID: "offer-dell-laptop",
            category: .objectLane
        )
        let wiring = ExchangeAppSearchSmokeAuditSupport.evaluateWiringForTests(
            expectation: expectation,
            engine: engine,
            thread: thread,
            ui: ui
        )
        #expect(!wiring.engineVsThreadMismatch.isEmpty)
        #expect(!wiring.threadVsUIMismatch.isEmpty)
        #expect(wiring.wrongFallbackOfferSelections == 1)
    }

    @Test("strict safety fails on forbidden attachment in engine snapshot")
    func forbiddenAttachmentStrictFailure() {
        let result = ExchangeRetrievalAccuracyScenarioResult(
            scenarioID: "test",
            queryLabel: "test",
            passed: false,
            expectedSummary: "test",
            failureReason: nil,
            actualTopSummaries: [],
            selectedOfferID: nil,
            matchedOffersByNode: ["node-car-seller": ["offer-toyota-camry"]],
            objectLaneActive: true,
            provenObjectOfferIDs: [],
            topDocKinds: [],
            topObjectEvidenceScores: [:],
            queryContext: nil,
            directoryRecall: nil
        )
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "test",
            queryLabel: "test",
            expectedSummary: "test",
            objectLaneActive: true,
            forbiddenAttachments: [("node-car-seller", "offer-toyota-camry")],
            category: .objectLane
        )
        let failures = ExchangeRetrievalAccuracyReport.strictInvariantFailures(
            expectation: expectation,
            result: result
        )
        #expect(!failures.isEmpty)
        #expect(failures.contains { $0.contains("forbidden attachment") })
    }
}

#endif

#if DEBUG
@Suite("ExchangeRetrievalE2EGate")
struct ExchangeRetrievalE2EGateTests {
    @Test("mandatory retrieval E2E scenarios count is five")
    func scenarioCount() {
        #expect(ExchangeRetrievalE2EScenarios.mandatory.count == 5)
    }

    @Test("retrieval E2E object-lane cases expect active lane")
    func objectLaneCases() {
        let active = ExchangeRetrievalE2EScenarios.mandatory.filter { $0.structural.expectedObjectLaneActive }
        #expect(active.count == 2)
    }


    @Test("object-lane E2E scenarios declare requiredObjectType")
    func objectLaneScenariosDeclareObjectType() {
        let objectCases = ExchangeRetrievalE2EScenarios.mandatory.filter { $0.structural.expectedObjectLaneActive }
        #expect(objectCases.count == 2)
        for scenario in objectCases {
            #expect(scenario.structural.requiredObjectType != nil)
        }
    }

    @Test("retrieval E2E service cases forbid incorrect product buy lane")
    func serviceCasesForbidProductBuyLane() {
        let serviceCases = ExchangeRetrievalE2EScenarios.mandatory.filter(\.structural.forbidIncorrectProductBuyLane)
        #expect(serviceCases.count == 3)
        for scenario in serviceCases {
            #expect(scenario.structural.expectedObjectLaneActive == false)
        }
    }

    @Test("RetrievalE2E gate allows localhost")
    func allowsLocalhost() throws {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "http://127.0.0.1:8787")!,
            source: .debugEnvironment
        )
        let url = try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        #expect(url.host == "127.0.0.1")
    }

    @Test("RetrievalE2E gate allows 192.168.2.19:8787 in DEBUG")
    func allowsLANIP() throws {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "http://192.168.2.19:8787")!,
            source: .debugEnvironment
        )
        #expect(ExchangeRetrievalE2EGate.isAllowedRealDeviceDevelopmentHost("192.168.2.19"))
        let url = try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        #expect(url.host == "192.168.2.19")
    }

    @Test("RetrievalE2E gate allows Cloudflare tunnel URL")
    func allowsCloudflareTunnelURL() throws {
        let tunnelURL = URL(string: "https://mile-leslie-burke-conflicts.trycloudflare.com")!
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: tunnelURL,
            source: .debugEnvironment
        )
        #expect(ExchangeRetrievalE2EGate.isCloudflareTunnelHost("mile-leslie-burke-conflicts.trycloudflare.com"))
        let url = try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        #expect(url.absoluteString == tunnelURL.absoluteString)
        #expect(url.appendingPathComponent("health").absoluteString == "https://mile-leslie-burke-conflicts.trycloudflare.com/health")
    }

    @Test("RetrievalE2E gate rejects production cloud URL")
    func rejectsProductionCloudURL() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: ExchangeBootstrap.liveFederationBaseURL,
            source: .productionDefault
        )
        #expect(throws: (any Error).self) {
            try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        }
    }

    @Test("RetrievalE2E gate rejects railway staging URL")
    func rejectsRailwayStagingURL() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "https://example.up.railway.app")!,
            source: .debugEnvironment
        )
        #expect(throws: (any Error).self) {
            try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        }
    }

    @Test("RetrievalE2E gate rejects empty URL")
    func rejectsEmptyURL() {
        let resolved = ExchangeBootstrap.ResolvedFederationBaseURL(
            url: URL(string: "http:///health")!,
            source: .debugEnvironment
        )
        #expect(throws: (any Error).self) {
            try ExchangeRetrievalE2EGate.validateResolvedBaseURL(resolved)
        }
    }
}
#endif

#if DEBUG
@Suite("ExchangeRetrievalSmokeManifestLoader")
struct ExchangeRetrievalSmokeManifestLoaderTests {
    @Test("tunnel mode uses remote manifest loading")
    func tunnelUsesRemoteMode() {
        let baseURL = URL(string: "https://mile-leslie-burke-conflicts.trycloudflare.com")!
        #expect(ExchangeRetrievalSmokeManifestLoader.manifestLoadMode(for: baseURL) == .remoteHTTP)
        #expect(
            ExchangeRetrievalSmokeManifestLoader.remoteManifestURL(baseURL: baseURL).absoluteString
                == "https://mile-leslie-burke-conflicts.trycloudflare.com/debug/retrieval-smoke/manifest"
        )
    }

    @Test("LAN mode uses remote manifest loading")
    func lanUsesRemoteMode() {
        let baseURL = URL(string: "http://192.168.2.19:8787")!
        #expect(ExchangeRetrievalSmokeManifestLoader.manifestLoadMode(for: baseURL) == .remoteHTTP)
    }

    @Test("localhost mode uses local /tmp manifest loading")
    func localhostUsesLocalMode() {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        #expect(ExchangeRetrievalSmokeManifestLoader.manifestLoadMode(for: baseURL) == .localFile)
    }

    @Test("remote manifest payload parses and validates")
    func remoteManifestPayloadParses() throws {
        let json = """
        {
          "ok": true,
          "publishGenerationID": "233ab264-fcf7-4e1e-9453-0cc9b01d22ef",
          "seededAt": "2026-05-24T00:00:00.000Z",
          "expectedNodeIDs": ["node-car-seller"],
          "expectedDocIDs": ["doc-car-intro"],
          "docCountsByKind": {"profile_intro": 1},
          "retrievalDocCount": 62,
          "embeddedCount": 62
        }
        """
        let manifest = try ExchangeRetrievalSmokeManifestLoader.parseRemoteManifestPayload(Data(json.utf8))
        #expect(manifest.publishGenerationID == "233ab264-fcf7-4e1e-9453-0cc9b01d22ef")
        #expect(manifest.expectedNodeIDs == ["node-car-seller"])
    }

    @Test("remote manifest missing fails as PRE_FLIGHT remoteManifestMissing")
    func remoteManifestMissingFailsPreflight() {
        let json = """
        {"ok": false, "reason": "manifest_file_missing"}
        """
        #expect(throws: RetrievalE2EPreflightFailure.self) {
            _ = try ExchangeRetrievalSmokeManifestLoader.parseRemoteManifestPayload(Data(json.utf8))
        }
    }
}
#endif
