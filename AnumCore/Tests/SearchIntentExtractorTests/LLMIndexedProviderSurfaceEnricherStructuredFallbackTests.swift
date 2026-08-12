import XCTest
@testable import AnumCore

final class LLMIndexedProviderSurfaceEnricherStructuredFallbackTests: XCTestCase {
    func testTimeoutAppliesDeterministicStructuredEnglishFallback() async {
        let surface = makeNonEnglishSurface()
        let diagnosticsStore = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: SlowProviderSurfaceEnrichmentJSONProvider(),
            config: .init(timeoutSeconds: 0.05),
            diagnosticsStore: diagnosticsStore
        )

        let enriched = await enricher.enrich(surface: surface)
        let diagnostics = await diagnosticsStore.last

        XCTAssertEqual(diagnostics?.source, .deterministicStructuredEnglish)
        XCTAssertEqual(diagnostics?.failureReason, .timeout)
        XCTAssertNotEqual(diagnostics?.source, .llmEnriched)
        XCTAssertNotNil(enriched.offers[0].canonicalEnglishRetrievalText)
        XCTAssertTrue(
            ExchangeStructuredEnglishRetrievalCarrierBuilder.hasAnyEnglishRetrievalCarrier(on: enriched)
        )
        let carrier = enriched.offers[0].canonicalEnglishRetrievalText ?? ""
        XCTAssertFalse(carrier.isEmpty)
        XCTAssertNotEqual(diagnostics?.source, .llmEnriched)
        XCTAssertNotEqual(diagnostics?.source, .fallbackOriginal)
    }

    private func makeNonEnglishSurface() -> ExchangeIndexedProviderSurface {
        let aurora = ExchangeDeclaredServiceArea.fromSellerChip("Aurora")!
        let offer = ExchangeIndexedOfferSurface(
            id: "offer-test",
            offerID: "offer-test",
            title: "屋顶维修",
            summary: "中文摘要",
            category: "roofing",
            objectIdentityTerms: ["roof repair"],
            capabilityTerms: ["roof repair"],
            commercialConstraints: [.init(text: "Free estimate", isHard: false)],
            fulfillment: .init(
                pricingMode: "quote",
                commitmentMode: "one_time",
                remoteFriendly: false,
                serviceAreaNote: "Aurora"
            ),
            sourceTextBlocks: ["屋顶维修"],
            serviceAreas: [aurora],
            visibility: "publicDiscoverable",
            status: "active"
        )
        return ExchangeIndexedProviderSurface(
            id: "profile-test",
            publicProfileID: "profile-test",
            nodeID: "node-test",
            displayName: "屋顶维修师傅",
            summary: "中文简介",
            visibility: "public",
            availability: "open",
            regions: .init(regionTags: ["aurora"]),
            capabilityTerms: ["roofing"],
            reachability: .init(
                accessMode: "direct",
                acceptingInbound: true,
                disclosureCeiling: "balanced",
                routeableOnly: false,
                intentCategoryPolicy: "open"
            ),
            offers: [offer],
            sourceTextBlocks: ["屋顶维修师傅"]
        )
    }
}

private struct SlowProviderSurfaceEnrichmentJSONProvider: AsyncProviderSurfaceEnrichmentJSONProvider {
    func isReadyForImmediateExtraction() async -> Bool { true }

    func enrichProviderSurfaceJSON(prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return "{}"
    }
}
