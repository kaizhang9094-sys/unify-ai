import XCTest
import AnumCore

/// `ExchangeDiscoveryEngine` + directory stub + hybrid retrieval: lane gates should prevent
/// wrong-surface candidates from appearing in final discovery output.
final class ExchangeDiscoveryEngineLaneIntegrationTests: XCTestCase {
    private let fixtureDate = SecretaryProjectionTestSupport.fixtureDate
    private let anchor = "discoverylaneseparationanchorfixturetoken"

    // MARK: - Lane separation (retrieval gate + projection)

    func test_discover_socialQuery_prefersAffinityProfile_notOfferOnlyPeer() async throws {
        let socialProfile = makeProfile(
            id: "pp-social-lane",
            nodeID: "node-social-lane",
            counterpartyID: "cp-social-lane",
            interests: [anchor, "hiking"],
            headline: "Community host"
        )
        let socialCP = makeCounterparty(
            id: "cp-social-lane",
            kind: .person,
            profile: socialProfile
        )
        let socialMatch = ExchangeDirectoryMatch.fromCounterparty(socialCP, offers: [])

        let offerOnly = makeOffer(
            id: "offer-lane-peer",
            nodeID: "node-offer-peer",
            publicProfileID: nil,
            title: "\(anchor) wholesale pallets",
            summary: "B2B pallets"
        )
        let offerCP = ExchangeCounterparty(
            id: "cp-offer-peer",
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            kind: .business,
            displayName: "Pallet vendor",
            source: .relayNetwork,
            identity: .init(nodeID: "node-offer-peer", verification: .unverified),
            publicProfile: nil
        )
        let offerMatch = ExchangeDirectoryMatch(
            counterparty: offerCP,
            publicProfile: nil,
            offers: [offerOnly],
            reachability: makeReachability()
        )

        let engine = makeDiscoveryEngine(matches: [socialMatch, offerMatch])
        let thread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "hiking", "community"]
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        let ids = result.candidates.map(\.counterparty.id)
        XCTAssertTrue(ids.contains("cp-social-lane"), "Expected social-profile counterparty in results")
        XCTAssertFalse(ids.contains("cp-offer-peer"), "Offer-only peer should not surface under social lane retrieval")
        if case .found(let found) = result {
            let top = found.candidates.first
            XCTAssertEqual(top?.counterparty.id, "cp-social-lane")
        } else {
            XCTFail("Expected .found for social + contactable profile, got \(result)")
        }
    }

    func test_discover_commercialQuery_prefersOffer_notPureAffinityPeer() async throws {
        // No shared anchor on the pure-social peer: its capability row still participates in the
        // commercial lane (offer + capability); lexical match must not piggyback on discoveryKeywords alone.
        let affinityProfile = makeProfile(
            id: "pp-affinity-peer",
            nodeID: "node-affinity-peer",
            counterpartyID: "cp-affinity-peer",
            interests: ["bookclub", "reading"],
            headline: "Social connector"
        )
        let affinityCP = makeCounterparty(
            id: "cp-affinity-peer",
            kind: .person,
            profile: affinityProfile
        )
        let affinityMatch = ExchangeDirectoryMatch.fromCounterparty(affinityCP, offers: [])

        let commercialProfile = makeProfile(
            id: "pp-commercial-lane",
            nodeID: "node-commercial-lane",
            counterpartyID: "cp-commercial-lane",
            interests: [],
            headline: "\(anchor) logistics partner",
            semanticDomains: ["freight forwarding"],
            offers: ["trucking"]
        )
        let commercialOffer = makeOffer(
            id: "offer-commercial-lane",
            nodeID: commercialProfile.nodeID,
            publicProfileID: commercialProfile.id,
            title: "\(anchor) freight quote",
            tags: ["logistics"]
        )
        let commercialCP = makeCounterparty(
            id: "cp-commercial-lane",
            kind: .business,
            profile: commercialProfile
        )
        let commercialMatch = ExchangeDirectoryMatch.fromCounterparty(
            commercialCP,
            offers: [commercialOffer]
        )

        let engine = makeDiscoveryEngine(matches: [affinityMatch, commercialMatch])
        let thread = makeThread(
            mode: .transactional,
            queryClass: .offerSearch,
            surface: .offer,
            anchor: anchor,
            providerFacetTerms: [anchor, "freight"],
            capabilityFacetTerms: ["logistics", "trucking"]
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        let ids = result.candidates.map(\.counterparty.id)
        XCTAssertTrue(ids.contains("cp-commercial-lane"))
        XCTAssertFalse(ids.contains("cp-affinity-peer"))
        if case .found(let found) = result {
            XCTAssertEqual(found.candidates.first?.counterparty.id, "cp-commercial-lane")
        } else {
            XCTFail("Expected .found, got \(result)")
        }
    }

    func test_discover_mixedSurfacePreference_allowsOfferAndProfileCandidates() async throws {
        // One rich node: emits both offer and affinity retrieval rows. `surfacePreference == .mixed`
        // must not hard-gate either family out at retrieval; post-rerank dominant surfaces should
        // still reflect both commercial and profile evidence (not collapse to a single bucket).
        let profile = makeProfile(
            id: "pp-mixed-rich",
            nodeID: "node-mixed-rich",
            counterpartyID: "cp-mixed-rich",
            interests: [anchor, "picnic"],
            headline: "\(anchor) studio host",
            semanticDomains: ["events"],
            offers: ["catering"]
        )
        let offer = makeOffer(
            id: "offer-mixed-rich",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "\(anchor) event package",
            tags: ["events"]
        )
        let cp = makeCounterparty(id: "cp-mixed-rich", kind: .business, profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [offer])

        let engine = makeDiscoveryEngine(matches: [match])
        let thread = makeThread(
            mode: .transactional,
            queryClass: .offerSearch,
            surface: .mixed,
            anchor: anchor,
            providerFacetTerms: [anchor, "events"],
            capabilityFacetTerms: ["catering"]
        )

        let retrievalQuery = ExchangeRetrievalQueryBuilder().build(from: thread)
        XCTAssertNil(
            retrievalQuery.resolvedLaneSurfaceAllowList,
            "Mixed surface preference must not install a hard lane allow-list at retrieval"
        )

        let result = try await engine.discover(thread: thread, limit: 24)
        XCTAssertFalse(result.candidates.isEmpty, "Mixed preference discovery should return at least one candidate")

        // Rerank recomputes coarse at counterparty scope, so a single contactable row may carry both
        // commercial (offers) and profile evidence; assert that combined signal is visible.
        let hasCombinedOfferAndProfileEvidence = result.candidates.contains { candidate in
            !candidate.matchedOffers.isEmpty &&
                (candidate.coarse.affinityOverlap > 0 || candidate.coarse.capabilityOverlap > 0)
        }
        XCTAssertTrue(
            hasCombinedOfferAndProfileEvidence,
            "Mixed routing should retain offer evidence alongside profile-surface overlap; candidates=\(result.candidates.map(\.counterparty.id))"
        )
    }

    func test_discover_generalDiscovery_remainsPermissiveAcrossSurfaces() async throws {
        let profile = makeProfile(
            id: "pp-general-rich",
            nodeID: "node-general-rich",
            counterpartyID: "cp-general-rich",
            interests: [anchor],
            headline: "General fixture",
            semanticDomains: ["consulting"],
            offers: ["audit"]
        )
        let offer = makeOffer(
            id: "offer-general-rich",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "\(anchor) audit sprint",
            tags: ["audit"]
        )
        let cp = makeCounterparty(id: "cp-general-rich", kind: .business, profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [offer])

        let engine = makeDiscoveryEngine(matches: [match])
        let thread = makeThread(
            mode: .transactional,
            queryClass: .generalDiscovery,
            surface: .offer,
            anchor: anchor,
            providerFacetTerms: [anchor]
        )

        let result = try await engine.discover(thread: thread, limit: 24)
        XCTAssertFalse(result.candidates.isEmpty, "General discovery should surface multiple surfaces when eligible")
        let surfaces = Set(result.candidates.map(\.dominantSurface))
        XCTAssertTrue(surfaces.count >= 2, "Expected permissive routing to retain more than one surface family, got \(surfaces)")
    }

    func test_discover_targetKindProvider_dropsPersonAffinityOnlyCandidate() async throws {
        // Omit shared anchor so the person row does not fuse above the vendor on generic keywords alone.
        let personAffinity = makeProfile(
            id: "pp-person-only",
            nodeID: "node-person-only",
            counterpartyID: "cp-person-only",
            interests: ["friends", "hobby"],
            headline: "Individual member"
        )
        let personCP = makeCounterparty(
            id: "cp-person-only",
            kind: .person,
            profile: personAffinity
        )
        let personMatch = ExchangeDirectoryMatch.fromCounterparty(personCP, offers: [])

        let vendorProfile = makeProfile(
            id: "pp-vendor",
            nodeID: "node-vendor",
            counterpartyID: "cp-vendor",
            interests: [],
            headline: "\(anchor) vendor studio",
            semanticDomains: ["facilities"],
            offers: ["maintenance contract"]
        )
        let vendorOffer = makeOffer(
            id: "offer-vendor",
            nodeID: vendorProfile.nodeID,
            publicProfileID: vendorProfile.id,
            title: "\(anchor) facilities retainer",
            tags: ["vendor"]
        )
        let vendorCP = makeCounterparty(id: "cp-vendor", kind: .business, profile: vendorProfile)
        let vendorMatch = ExchangeDirectoryMatch.fromCounterparty(vendorCP, offers: [vendorOffer])

        let engine = makeDiscoveryEngine(matches: [personMatch, vendorMatch])
        let thread = makeThread(
            mode: .transactional,
            queryClass: .providerSearch,
            surface: .capability,
            anchor: anchor,
            providerFacetTerms: [anchor, "vendor", "facilities"],
            capabilityFacetTerms: ["maintenance"],
            targetKind: .provider
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        XCTAssertTrue(result.candidates.contains { $0.counterparty.id == "cp-vendor" })
        XCTAssertFalse(result.candidates.contains { $0.counterparty.id == "cp-person-only" })
    }

    func test_discover_targetKindPerson_dropsBusinessOfferOnlyCandidate() async throws {
        let personProfile = makeProfile(
            id: "pp-person-social",
            nodeID: "node-person-social",
            counterpartyID: "cp-person-social",
            interests: [anchor, "circle"],
            headline: "Neighbor"
        )
        let personCP = makeCounterparty(
            id: "cp-person-social",
            kind: .person,
            profile: personProfile
        )
        let personMatch = ExchangeDirectoryMatch.fromCounterparty(personCP, offers: [])

        let bizProfile = makeProfile(
            id: "pp-biz-offer",
            nodeID: "node-biz-offer",
            counterpartyID: "cp-biz-offer",
            interests: [],
            headline: "B2B only",
            semanticDomains: ["steel"],
            offers: ["bulk"]
        )
        let bizOffer = makeOffer(
            id: "offer-biz-only",
            nodeID: bizProfile.nodeID,
            publicProfileID: bizProfile.id,
            title: "\(anchor) steel coils",
            tags: ["steel"]
        )
        let bizCP = makeCounterparty(id: "cp-biz-offer", kind: .business, profile: bizProfile)
        let bizMatch = ExchangeDirectoryMatch.fromCounterparty(bizCP, offers: [bizOffer])

        let engine = makeDiscoveryEngine(matches: [personMatch, bizMatch])
        let thread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "circle", "friends"],
            targetKind: .person
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        XCTAssertTrue(result.candidates.contains { $0.counterparty.id == "cp-person-social" })
        XCTAssertFalse(result.candidates.contains { $0.counterparty.id == "cp-biz-offer" })
    }

    func test_discover_dominantSurface_matchesRetrievalDocumentFamily() async throws {
        let rich = makeProfile(
            id: "pp-dominant-triple",
            nodeID: "node-dominant-triple",
            counterpartyID: "cp-dominant-triple",
            interests: [anchor],
            headline: "\(anchor) triple fixture",
            semanticDomains: ["design"],
            offers: ["workshop"]
        )
        let off = makeOffer(
            id: "offer-dominant-triple",
            nodeID: rich.nodeID,
            publicProfileID: rich.id,
            title: "\(anchor) workshop day rate",
            tags: ["design"]
        )
        let cp = makeCounterparty(id: "cp-dominant-triple", kind: .business, profile: rich)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [off])
        let engine = makeDiscoveryEngine(matches: [match])

        let commercialThread = makeThread(
            mode: .transactional,
            queryClass: .offerSearch,
            surface: .offer,
            anchor: anchor,
            providerFacetTerms: [anchor, "design"],
            capabilityFacetTerms: ["workshop"]
        )
        let commercial = try await engine.discover(thread: commercialThread, limit: 24)
        let offerDominant = commercial.candidates.filter { $0.dominantSurface == .offer }
        XCTAssertFalse(offerDominant.isEmpty, "Offer retrieval rows should map to offer-dominant candidates")

        let socialThread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "circle"]
        )
        let social = try await engine.discover(thread: socialThread, limit: 24)
        let affinityDominant = social.candidates.filter { $0.dominantSurface == .affinity }
        XCTAssertFalse(affinityDominant.isEmpty, "Affinity retrieval rows should map to affinity-dominant candidates")

        let capThread = makeThread(
            mode: .transactional,
            queryClass: .capabilitySearch,
            surface: .capability,
            anchor: anchor,
            capabilityFacetTerms: [anchor, "design", "workshop"]
        )
        let cap = try await engine.discover(thread: capThread, limit: 24)
        let capDominant = cap.candidates.filter { $0.dominantSurface == .capability }
        XCTAssertFalse(capDominant.isEmpty, "Capability retrieval rows should map to capability-dominant candidates")
    }

    func test_discover_coarseRationale_surfaceFamilyMatchesDominantLane() async throws {
        let profile = makeProfile(
            id: "pp-rationale",
            nodeID: "node-rationale",
            counterpartyID: "cp-rationale",
            interests: [anchor, "community"],
            headline: "Rationale fixture"
        )
        let cp = makeCounterparty(id: "cp-rationale", kind: .person, profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [])
        let engine = makeDiscoveryEngine(matches: [match])

        let thread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "community"]
        )
        let result = try await engine.discover(thread: thread, limit: 8)
        guard let top = result.candidates.first else {
            XCTFail("Expected at least one candidate")
            return
        }
        XCTAssertEqual(top.dominantSurface, .affinity)
        let rationale = top.coarse.rationale.lowercased()
        XCTAssertTrue(
            rationale.contains("affinity"),
            "Coarse rationale should name affinity surface family; got: \(top.coarse.rationale)"
        )
        XCTAssertFalse(rationale.contains("offer-led"), "Rationale should not claim offer-led dominance for affinity top hit")
    }

    func test_discover_onlyWrongLanePeers_returnsNone_notDirectoryFallbackRescue() async throws {
        let offerOnly = makeOffer(
            id: "offer-wrong-lane-only",
            nodeID: "node-wrong-lane",
            publicProfileID: nil,
            title: "\(anchor) commodity desk",
            tags: ["commodity"]
        )
        let cp = ExchangeCounterparty(
            id: "cp-wrong-lane-only",
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            kind: .business,
            displayName: "Desk only",
            source: .relayNetwork,
            identity: .init(nodeID: "node-wrong-lane", verification: .unverified),
            publicProfile: nil
        )
        let match = ExchangeDirectoryMatch(
            counterparty: cp,
            publicProfile: nil,
            offers: [offerOnly],
            reachability: makeReachability()
        )

        let engine = makeDiscoveryEngine(matches: [match])
        let thread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "friends"]
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        if case .none(let none) = result {
            XCTAssertTrue(result.candidates.isEmpty)
            XCTAssertFalse(
                none.summary.isEmpty,
                "Expected a legible empty-state summary when retrieval short-circuits wrong-lane docs"
            )
        } else {
            XCTFail("Expected .none when every ingested surface is lane-gated out and fallback lacks a profile, got \(result)")
        }
    }

    /// Posture may widen the rerank gate for **kind-compatible** rows that are otherwise
    /// `isRetrievable == false`, but must not admit **kind-incompatible** rows just because posture
    /// is contactable/intro-capable.
    func test_discover_postureRescue_weakKindCompatible_notWrongKind() async throws {
        // `ExchangeRetrievalQuery.keywords` always includes `surfacePreference.rawValue` ("capability"
        // here), but `SearchPlan`/`retrievalIntentTokens` does not — so headline "capability …"
        // yields a retrieval hit without coarse overlap against facet/provider/capability terms.
        let weakProfile = makeProfile(
            id: "pp-weak-posture-rescue",
            nodeID: "node-weak-posture-rescue",
            counterpartyID: "cp-weak-posture-rescue",
            interests: [],
            headline: "capability zzweakuniq",
            semanticDomains: [],
            offers: [],
            summary: "zzweak",
            reachability: .init(accessMode: .direct, acceptingInbound: true),
            displayName: "Auxprofilezq"
        )
        let weakCP = makeCounterparty(id: "cp-weak-posture-rescue", kind: .business, profile: weakProfile)
        let weakMatch = ExchangeDirectoryMatch.fromCounterparty(weakCP, offers: [])

        let strongProfile = makeProfile(
            id: "pp-strong-posture-rescue",
            nodeID: "node-strong-posture-rescue",
            counterpartyID: "cp-strong-posture-rescue",
            interests: [],
            headline: "strongvendorlane headline",
            semanticDomains: ["strongvendorlane"],
            offers: []
        )
        let strongOffer = makeOffer(
            id: "offer-strong-posture-rescue",
            nodeID: strongProfile.nodeID,
            publicProfileID: strongProfile.id,
            title: "strongcaplane offer title",
            tags: ["strongcaplane"]
        )
        let strongCP = makeCounterparty(id: "cp-strong-posture-rescue", kind: .business, profile: strongProfile)
        let strongMatch = ExchangeDirectoryMatch.fromCounterparty(strongCP, offers: [strongOffer])

        let engine = makeDiscoveryEngine(matches: [weakMatch, strongMatch])
        let providerThread = makeThread(
            mode: .transactional,
            queryClass: .providerSearch,
            surface: .capability,
            anchor: anchor,
            providerFacetTerms: ["strongvendorlane"],
            capabilityFacetTerms: ["strongcaplane"],
            targetKind: .provider,
            minimalRetrievalNoise: true
        )

        let providerResult = try await engine.discover(thread: providerThread, limit: 24)
        let weakCandidate = providerResult.candidates.first { $0.counterparty.id == "cp-weak-posture-rescue" }
        let debugIDs = providerResult.candidates.map(\.counterparty.id).joined(separator: ",")
        XCTAssertNotNil(
            weakCandidate,
            "Kind-compatible + contactable/intro posture should keep weak-but-compatible rows in the shortlist; got [\(debugIDs)]"
        )
        guard let weakCandidate else { return }
        XCTAssertTrue(
            weakCandidate.coarse.kindCompatible,
            "Weak fixture must remain target-kind compatible for a provider-scoped thread"
        )
        let overlapSum =
            weakCandidate.coarse.queryTokenOverlap +
            weakCandidate.coarse.explicitTokenOverlap +
            weakCandidate.coarse.regionOverlap +
            weakCandidate.coarse.offerOverlap +
            weakCandidate.coarse.capabilityOverlap +
            weakCandidate.coarse.affinityOverlap
        XCTAssertEqual(
            overlapSum,
            0,
            "Weak fixture must have zero SearchPlan-token overlap in rerank coarse (posture rescue only); " +
                "q=\(weakCandidate.coarse.queryTokenOverlap) e=\(weakCandidate.coarse.explicitTokenOverlap) " +
                "r=\(weakCandidate.coarse.regionOverlap) o=\(weakCandidate.coarse.offerOverlap) " +
                "c=\(weakCandidate.coarse.capabilityOverlap) a=\(weakCandidate.coarse.affinityOverlap)"
        )
        XCTAssertFalse(weakCandidate.coarse.isRetrievable)
        XCTAssertGreaterThanOrEqual(
            weakCandidate.posture.bucket.rawValue,
            3,
            "Posture rescue path requires introRequired-or-better bucket (rawValue ≥ 3)"
        )

        // Wrong kind: explicit person target must not surface a business counterparty even if contactable.
        let personProfile = makeProfile(
            id: "pp-person-posture-rescue",
            nodeID: "node-person-posture-rescue",
            counterpartyID: "cp-person-posture-rescue",
            interests: [anchor, "circle"],
            headline: "Neighbor"
        )
        let personCP = makeCounterparty(id: "cp-person-posture-rescue", kind: .person, profile: personProfile)
        let personMatch = ExchangeDirectoryMatch.fromCounterparty(personCP, offers: [])

        let wrongKindProfile = makeProfile(
            id: "pp-wrong-kind-posture-rescue",
            nodeID: "node-wrong-kind-posture-rescue",
            counterpartyID: "cp-wrong-kind-posture-rescue",
            interests: [],
            headline: "B2B vendor",
            semanticDomains: ["steel"],
            offers: ["bulk"],
            reachability: .init(accessMode: .direct, acceptingInbound: true)
        )
        let wrongKindOffer = makeOffer(
            id: "offer-wrong-kind-posture-rescue",
            nodeID: wrongKindProfile.nodeID,
            publicProfileID: wrongKindProfile.id,
            title: "\(anchor) steel offer",
            tags: ["steel"]
        )
        let wrongKindCP = makeCounterparty(
            id: "cp-wrong-kind-posture-rescue",
            kind: .business,
            profile: wrongKindProfile
        )
        let wrongKindMatch = ExchangeDirectoryMatch.fromCounterparty(wrongKindCP, offers: [wrongKindOffer])

        let socialEngine = makeDiscoveryEngine(matches: [personMatch, wrongKindMatch])
        let personThread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor, "circle"],
            targetKind: .person
        )
        let socialResult = try await socialEngine.discover(thread: personThread, limit: 12)
        XCTAssertTrue(socialResult.candidates.contains { $0.counterparty.id == "cp-person-posture-rescue" })
        XCTAssertFalse(
            socialResult.candidates.contains { $0.counterparty.id == "cp-wrong-kind-posture-rescue" },
            "Kind-incompatible business must not be rescued by contactable posture under explicit person target"
        )
    }

    func test_discover_deterministicAcrossIdenticalCalls() async throws {
        let profile = makeProfile(
            id: "pp-deterministic",
            nodeID: "node-deterministic",
            counterpartyID: "cp-deterministic",
            interests: [anchor],
            headline: "Deterministic fixture"
        )
        let cp = makeCounterparty(id: "cp-deterministic", kind: .person, profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [])
        let engine = makeDiscoveryEngine(matches: [match])
        let thread = makeThread(
            mode: .relational,
            queryClass: .socialAffinitySearch,
            surface: .affinity,
            anchor: anchor,
            affinityFacetTerms: [anchor]
        )

        let first = try await engine.discover(thread: thread, limit: 8)
        let second = try await engine.discover(thread: thread, limit: 8)

        XCTAssertEqual(firstSignature(first), firstSignature(second))
    }

    // MARK: - Remote-only directory recall (no fallback)

    func test_discover_remoteOnlyDirectoryMatchWithZeroLocalRetrieval_returnsNone() async throws {
        let hansenProfile = makeProfile(
            id: "pp-hansen",
            nodeID: "node-hansen",
            counterpartyID: "cp-hansen",
            interests: [],
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
        let thread = makeThread(
            mode: .transactional,
            queryClass: .providerSearch,
            surface: .offer,
            anchor: "piano teacher",
            providerFacetTerms: ["piano", "teacher"],
            targetKind: .provider
        )

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
            interests: [],
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
        let thread = makeThread(
            mode: .transactional,
            queryClass: .providerSearch,
            surface: .offer,
            anchor: "piano teacher",
            providerFacetTerms: ["piano", "teacher"],
            targetKind: .provider
        )

        let result = try await engine.discover(thread: thread, limit: 12)
        let ids = result.candidates.map(\.counterparty.id)
        XCTAssertTrue(ids.contains("cp-piano"), "Expected locally proven piano teacher candidate")
        if case .found(let found) = result {
            XCTAssertEqual(found.candidates.first?.counterparty.id, "cp-piano")
        } else {
            XCTFail("Expected .found when local retrieval proves piano teacher match, got \(result)")
        }
    }

    // MARK: - Harness

    private func makeDiscoveryEngine(matches: [ExchangeDirectoryMatch]) -> ExchangeDiscoveryEngine {
        let store = ExchangeRetrievalStore()
        // Lexical-only: vector fusion with `FixedEmbeddingProvider` can surface unrelated rows
        // that share weak semantic similarity, which obscures lane-gate assertions.
        let embedder = NilEmbeddingProviderForDiscoveryTests()
        let builder = ExchangeRetrievalDocumentBuilder()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let retrievalEngine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let client = StubExchangeDirectoryClientForDiscovery(matches: matches)
        return ExchangeDiscoveryEngine(
            directoryClient: client,
            localNodeIDProvider: { nil },
            embeddingProvider: embedder,
            retrievalStore: store,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: ingestor
        )
    }

    private func makeThread(
        mode: ExchangeMode,
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        anchor: String,
        providerFacetTerms: [String] = [],
        capabilityFacetTerms: [String] = [],
        affinityFacetTerms: [String] = [],
        targetKind: ExchangeIntentFacets.TargetKind = .unknown,
        minimalRetrievalNoise: Bool = false
    ) -> ExchangeThread {
        let facets = ExchangeIntentFacets(
            targetKind: targetKind,
            queryIntentClass: queryClass,
            surfacePreference: surface,
            providerTerms: providerFacetTerms,
            capabilityTerms: capabilityFacetTerms,
            affinityTerms: affinityFacetTerms
        )
        // Keep objective minimal so BM25/query tokens are not dominated by shared boilerplate that
        // weakly matches many ingested capability rows (hurts commercial vs social lane tests).
        let intentTitle = minimalRetrievalNoise ? "z" : "Lane integration"
        let intentObjective = minimalRetrievalNoise ? "z" : anchor
        let intent = ExchangeIntent(
            kind: .find,
            mode: mode,
            queryIntentClass: queryClass,
            surfacePreference: surface,
            title: intentTitle,
            objective: intentObjective
        )
        let interpretationDiscoveryKeywords = minimalRetrievalNoise ? [] : [anchor]
        let interpretation = ExchangeThread.InterpretationSnapshot(
            discoveryKeywords: interpretationDiscoveryKeywords
        )
        return ExchangeThread(
            mode: mode,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            interpretation: interpretation,
            state: .drafting
        )
    }

    private func makeProfile(
        id: String,
        nodeID: String,
        counterpartyID: String,
        interests: [String],
        headline: String,
        semanticDomains: [String] = [],
        offers: [String] = [],
        summary: String? = nil,
        reachability: ExchangePublicNodeProfile.ReachabilityPolicy? = nil,
        displayName: String? = nil
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            counterpartyID: counterpartyID,
            displayName: displayName ?? "Fixture \(id)",
            headline: headline,
            summary: summary ?? "Summary for \(id)",
            interests: interests,
            offers: offers,
            semantic: ExchangePublicNodeProfile.SemanticSurface(
                domains: semanticDomains,
                intentKinds: semanticDomains.isEmpty ? [] : ["professional"]
            ),
            reachability: reachability ?? .init(),
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

    private func makeReachability() -> ExchangeDirectoryMatch.ReachabilityPreview {
        ExchangeDirectoryMatch.ReachabilityPreview(
            isDiscoverable: true,
            isRouteableInPrinciple: true,
            allowsDirectContactInPrinciple: true,
            requiresIntroductionInPrinciple: false,
            hasRouteHint: true
        )
    }

    private func firstSignature(_ result: ExchangeDiscoveryEngine.DiscoveryResult) -> String {
        result.candidates
            .map { "\($0.counterparty.id)|\($0.dominantSurface.rawValue)|\($0.publicProfileID ?? "")|\($0.matchedOffers.map(\.id).joined(separator: ","))" }
            .joined(separator: ";")
    }
}

// MARK: - Stub embedding (BM25-only retrieval)

private struct NilEmbeddingProviderForDiscoveryTests: MemoryEmbeddingProvider, Sendable {
    func embed(_ text: String) -> [Float]? { nil }
}

// MARK: - Stub directory client

private final class StubExchangeDirectoryClientForDiscovery: ExchangeDirectoryClient, @unchecked Sendable {
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
