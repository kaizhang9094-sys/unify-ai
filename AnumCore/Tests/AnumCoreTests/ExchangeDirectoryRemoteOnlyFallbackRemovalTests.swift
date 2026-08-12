import Foundation
import XCTest

@testable import AnumCore

/// Remote directory recall must not surface user-visible candidates when local hybrid retrieval finds zero proof.
final class ExchangeDirectoryRemoteOnlyFallbackRemovalTests: XCTestCase {
    private let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)

    func test_discover_remoteOnlyDirectoryMatchWithZeroLocalRetrieval_returnsNone() async throws {
        let hansenProfile = makeProfile(
            id: "pp-hansen",
            nodeID: "node-hansen",
            counterpartyID: "cp-hansen",
            headline: "Hansen",
            displayName: "Hansen"
        )
        let vcOffer = makeOffer(
            id: "offer-vc",
            nodeID: hansenProfile.nodeID,
            publicProfileID: hansenProfile.id,
            title: "Vc",
            summary: "Vc"
        )
        let hansenCP = makeCounterparty(id: "cp-hansen", kind: .provider, profile: hansenProfile)
        let hansenMatch = ExchangeDirectoryMatch.fromCounterparty(hansenCP, offers: [vcOffer])

        let engine = makeDiscoveryEngine(matches: [hansenMatch])
        let thread = makePianoTeacherThread()

        let result = try await engine.discover(thread: thread, limit: 12)

        guard case .none = result else {
            return XCTFail(
                "Expected .none when remote directory returns unrelated match but local retrieval is empty, got \(result)"
            )
        }
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func test_discover_localRetrievalProofStillSurfacesCandidate() async throws {
        let profile = makeProfile(
            id: "pp-piano",
            nodeID: "node-piano",
            counterpartyID: "cp-piano",
            headline: "Piano teacher",
            semanticDomains: ["music education"],
            offers: ["piano lessons"]
        )
        let offer = makeOffer(
            id: "offer-piano",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "Piano teacher lessons",
            tags: ["piano", "teacher", "music"]
        )
        let cp = makeCounterparty(id: "cp-piano", kind: .provider, profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [offer])

        let engine = makeDiscoveryEngine(matches: [match])
        let thread = makePianoTeacherThread()

        let result = try await engine.discover(thread: thread, limit: 12)
        let ids = result.candidates.map(\.counterparty.id)
        XCTAssertTrue(ids.contains("cp-piano"), "Expected locally proven piano teacher candidate")
        if case .found(let found) = result {
            XCTAssertEqual(found.candidates.first?.counterparty.id, "cp-piano")
        } else {
            XCTFail("Expected .found when local retrieval proves piano teacher match, got \(result)")
        }
    }

    func test_discoverAndRank_remoteOnlyDirectoryMatchWithZeroLocalRetrieval_returnsNone() async throws {
        let hansenProfile = makeProfile(
            id: "pp-hansen-rank",
            nodeID: "node-hansen-rank",
            counterpartyID: "cp-hansen-rank",
            headline: "Hansen",
            displayName: "Hansen"
        )
        let vcOffer = makeOffer(
            id: "offer-vc-rank",
            nodeID: hansenProfile.nodeID,
            publicProfileID: hansenProfile.id,
            title: "Vc",
            summary: "Vc"
        )
        let hansenCP = makeCounterparty(id: "cp-hansen-rank", kind: .provider, profile: hansenProfile)
        let hansenMatch = ExchangeDirectoryMatch.fromCounterparty(hansenCP, offers: [vcOffer])

        let discoveryEngine = makeDiscoveryEngine(matches: [hansenMatch])
        let service = ExchangeDiscoveryService(
            discoveryEngine: discoveryEngine,
            fitEngine: ExchangeFitEngine()
        )
        let thread = makePianoTeacherThread()

        let result = try await service.discoverAndRank(thread: thread, limit: 12)

        guard case .none = result else {
            return XCTFail("Expected discoverAndRank .none for remote-only unrelated recall, got \(result)")
        }
    }

    // MARK: - Harness

    private func makeDiscoveryEngine(matches: [ExchangeDirectoryMatch]) -> ExchangeDiscoveryEngine {
        let store = ExchangeRetrievalStore()
        let embedder = NilEmbeddingProviderForRemoteOnlyFallbackTests()
        let builder = ExchangeRetrievalDocumentBuilder()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let retrievalEngine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let client = StubExchangeDirectoryClientForRemoteOnlyFallbackTests(matches: matches)
        return ExchangeDiscoveryEngine(
            directoryClient: client,
            localNodeIDProvider: { nil },
            embeddingProvider: embedder,
            retrievalStore: store,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: ingestor
        )
    }

    private func makePianoTeacherThread() -> ExchangeThread {
        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["piano", "teacher"]
        )
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "Find piano teacher",
            objective: "Find me a piano teacher.",
            targetDescription: "piano teacher"
        )
        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            interpretation: ExchangeThread.InterpretationSnapshot(
                discoveryKeywords: ["piano", "teacher"]
            ),
            state: .drafting
        )
    }

    private func makeProfile(
        id: String,
        nodeID: String,
        counterpartyID: String,
        headline: String,
        semanticDomains: [String] = [],
        offers: [String] = [],
        displayName: String? = nil
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            counterpartyID: counterpartyID,
            displayName: displayName ?? "Fixture \(id)",
            headline: headline,
            summary: "Summary for \(id)",
            interests: [],
            offers: offers,
            semantic: ExchangePublicNodeProfile.SemanticSurface(
                domains: semanticDomains,
                intentKinds: semanticDomains.isEmpty ? [] : ["professional"]
            ),
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            ),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
    }

    private func makeOffer(
        id: String,
        nodeID: String,
        publicProfileID: String?,
        title: String,
        summary: String? = nil,
        tags: [String] = []
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            title: title,
            summary: summary,
            tags: tags,
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
    }

    private func makeCounterparty(
        id: String,
        kind: ExchangeCounterparty.Kind,
        profile: ExchangePublicNodeProfile
    ) -> ExchangeCounterparty {
        ExchangeCounterparty(
            id: id,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            kind: kind,
            displayName: profile.displayName ?? id,
            source: .relayNetwork,
            identity: .init(nodeID: profile.nodeID, verification: .unverified),
            publicProfile: profile
        )
    }
}

private struct NilEmbeddingProviderForRemoteOnlyFallbackTests: MemoryEmbeddingProvider, Sendable {
    func embed(_ text: String) -> [Float]? { nil }
}

private final class StubExchangeDirectoryClientForRemoteOnlyFallbackTests: ExchangeDirectoryClient, @unchecked Sendable {
    private let matches: [ExchangeDirectoryMatch]

    init(matches: [ExchangeDirectoryMatch]) {
        self.matches = matches
    }

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        ExchangeDirectorySearchResponse(matches: matches, source: .local, summary: "stub-directory")
    }

    func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }
}
