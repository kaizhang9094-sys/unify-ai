import XCTest
import AnumCore

/// End-to-end checks that `ExchangeIntent` / `ExchangeIntentFacets` on an `ExchangeThread`
/// flow through `ExchangeRetrievalQueryBuilder` into `ExchangeRetrievalQuery` routing fields
/// (including `allowedSurfaceTypes`) before retrieval runs.
final class ExchangeRetrievalQueryBuilderPipelineTests: XCTestCase {
    private let builder = ExchangeRetrievalQueryBuilder()

    // MARK: - Lane surfaces (via facets → builder → query)

    func test_pipeline_socialAffinitySearch_affinityPreference_laneSurfacesExcludeOffer() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            affinityTerms: ["friends", "hiking circle"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(query.surfacePreference, .affinity)
        let lane = Set(query.allowedSurfaceTypes ?? [])
        XCTAssertEqual(lane, [.publicProfileAffinity, .publicProfileCapability])
        XCTAssertFalse(lane.contains(.offer))
        XCTAssertEqual(Set(query.affinityTerms), Set(["friends", "hiking circle"]))
    }

    func test_pipeline_relationshipSearch_affinityPreference_laneSurfacesExcludeOffer() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .relationshipSearch,
            surfacePreference: .affinity,
            affinityTerms: ["community", "picnic"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .relationshipSearch)
        XCTAssertEqual(query.surfacePreference, .affinity)
        let lane = Set(query.allowedSurfaceTypes ?? [])
        XCTAssertEqual(lane, [.publicProfileAffinity, .publicProfileCapability])
        XCTAssertFalse(lane.contains(.offer))
        XCTAssertEqual(Set(query.affinityTerms), Set(["community", "picnic"]))
    }

    func test_pipeline_offerSearch_offerPreference_laneSurfacesExcludeAffinity() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["vendor", "procurement"],
            capabilityTerms: ["widget", "consulting"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .offerSearch)
        XCTAssertEqual(query.surfacePreference, .offer)
        let lane = Set(query.allowedSurfaceTypes ?? [])
        XCTAssertEqual(lane, [.offer, .publicProfileCapability])
        XCTAssertFalse(lane.contains(.publicProfileAffinity))
        XCTAssertEqual(Set(query.providerTerms), Set(["procurement", "vendor"]))
        XCTAssertEqual(Set(query.capabilityTerms), Set(["consulting", "widget"]))
    }

    func test_pipeline_providerSearch_capabilityPreference_laneSurfacesExcludeAffinity() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .capability,
            providerTerms: ["enterprise"],
            capabilityTerms: ["integration", "platform"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .providerSearch)
        XCTAssertEqual(query.surfacePreference, .capability)
        let lane = Set(query.allowedSurfaceTypes ?? [])
        XCTAssertEqual(lane, [.offer, .publicProfileCapability])
        XCTAssertFalse(lane.contains(.publicProfileAffinity))
        XCTAssertEqual(Set(query.providerTerms), Set(["enterprise"]))
        XCTAssertEqual(Set(query.capabilityTerms), Set(["integration", "platform"]))
    }

    func test_pipeline_mixedSurfacePreference_laneSurfacesNil() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .mixed,
            providerTerms: ["acme"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.surfacePreference, .mixed)
        XCTAssertNil(query.allowedSurfaceTypes)
        XCTAssertNil(query.resolvedLaneSurfaceAllowList)
    }

    func test_pipeline_generalDiscovery_laneSurfacesNil() {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .offer,
            title: "Discovery fixture",
            objective: "open ended browse for anything interesting"
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: nil,
            state: .drafting
        )
        let query = builder.build(from: thread)

        XCTAssertEqual(query.queryIntentClass, .generalDiscovery)
        XCTAssertEqual(query.surfacePreference, .offer)
        XCTAssertNil(query.allowedSurfaceTypes)
        XCTAssertNil(query.resolvedLaneSurfaceAllowList)
    }

    func test_pipeline_directOutreach_followUp_statusCheck_laneSurfacesNilEvenWithOfferPreference() {
        let routedIntents: [ExchangeIntent.QueryIntentClass] = [
            .directOutreach,
            .followUp,
            .statusCheck
        ]

        for routed in routedIntents {
            let facets = ExchangeIntentFacets(
                queryIntentClass: routed,
                surfacePreference: .offer,
                providerTerms: ["contoso"]
            )
            let query = builder.build(from: makeThread(facets: facets))

            XCTAssertEqual(query.queryIntentClass, routed)
            XCTAssertEqual(query.surfacePreference, .offer)
            XCTAssertNil(
                query.allowedSurfaceTypes,
                "\(routed.rawValue) should not apply commercial lane hard surfaces."
            )
            XCTAssertNil(query.resolvedLaneSurfaceAllowList)
        }
    }

    func test_pipeline_commercial_offerSearch_affinityPreference_staysPermissiveForLaneSurfaces() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .affinity,
            providerTerms: ["invoice"],
            affinityTerms: ["culture fit"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .offerSearch)
        XCTAssertEqual(query.surfacePreference, .affinity)
        XCTAssertNil(query.allowedSurfaceTypes)
        XCTAssertNil(query.resolvedLaneSurfaceAllowList)
        XCTAssertEqual(Set(query.providerTerms), Set(["invoice"]))
        XCTAssertEqual(Set(query.affinityTerms), Set(["culture fit"]))
    }

    func test_pipeline_commercial_providerSearch_affinityPreference_staysPermissiveForLaneSurfaces() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .affinity,
            providerTerms: ["studio"],
            affinityTerms: ["mentorship"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.queryIntentClass, .providerSearch)
        XCTAssertEqual(query.surfacePreference, .affinity)
        XCTAssertNil(query.allowedSurfaceTypes)
        XCTAssertNil(query.resolvedLaneSurfaceAllowList)
    }

    func test_pipeline_capabilitySearch_and_collaboration_capabilityPreference_laneSurfacesAllowOfferAndCapabilityProfile() {
        let expectedLane: Set<ExchangeRetrievalDocument.SurfaceType> = [.offer, .publicProfileCapability]

        for intentClass in [ExchangeIntent.QueryIntentClass.capabilitySearch, .collaborationSearch] {
            let facets = ExchangeIntentFacets(
                queryIntentClass: intentClass,
                surfacePreference: .capability,
                capabilityTerms: ["design review", "workshop"]
            )
            let query = builder.build(from: makeThread(facets: facets))

            XCTAssertEqual(query.queryIntentClass, intentClass)
            XCTAssertEqual(query.surfacePreference, .capability)
            XCTAssertEqual(Set(query.allowedSurfaceTypes ?? []), expectedLane)
            XCTAssertEqual(Set(query.capabilityTerms), Set(["design review", "workshop"]))
        }
    }

    func test_pipeline_targetKind_survivesFromFacets() {
        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            queryIntentClass: .providerSearch,
            surfacePreference: .capability,
            providerTerms: ["studio"],
            capabilityTerms: ["branding"]
        )
        let query = builder.build(from: makeThread(facets: facets))

        XCTAssertEqual(query.targetKind, "provider")
    }

    func test_pipeline_facetsTakePrecedenceOverIntent_forRoutingFields() {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "Intent title",
            objective: "intent objective body"
        )
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["facetvendor"]
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
        let query = builder.build(from: thread)

        XCTAssertEqual(query.queryIntentClass, .offerSearch)
        XCTAssertEqual(query.surfacePreference, .offer)
        XCTAssertEqual(Set(query.providerTerms), Set(["facetvendor"]))
    }

    // MARK: - Helpers

    private func makeThread(facets: ExchangeIntentFacets?) -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "Pipeline fixture",
            objective: "fixture objective for retrieval query builder pipeline tests"
        )
        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }
}
