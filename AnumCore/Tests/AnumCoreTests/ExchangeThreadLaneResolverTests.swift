import Foundation
import XCTest
@testable import AnumCore

final class ExchangeThreadLaneResolverTests: XCTestCase {

    private func intent(
        _ queryIntentClass: ExchangeIntent.QueryIntentClass,
        mode: ExchangeMode = .transactional
    ) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: mode,
            queryIntentClass: queryIntentClass,
            title: "Test",
            objective: "Test objective",
            readiness: .ready
        )
    }

    private func thread(
        intent: ExchangeIntent,
        metadata: [String: String] = [:],
        lastInboundEnvelopeID: String? = nil
    ) -> ExchangeThread {
        ExchangeThread(
            mode: intent.mode,
            intent: intent,
            posture: .default,
            state: .drafting,
            lastInboundEnvelopeID: lastInboundEnvelopeID,
            metadata: metadata
        )
    }

    func testSocialAffinityIntentResolvesSocialConnectionLane() {
        let lane = ExchangeThreadLaneResolver.lane(for: intent(.socialAffinitySearch, mode: .relational))
        XCTAssertEqual(lane, .socialConnection)
    }

    func testRelationshipIntentResolvesSocialConnectionLane() {
        let lane = ExchangeThreadLaneResolver.lane(for: intent(.relationshipSearch, mode: .relational))
        XCTAssertEqual(lane, .socialConnection)
    }

    func testProviderSearchResolvesCommercialInquiryLane() {
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: intent(.providerSearch)), .commercialInquiry)
    }

    func testOfferSearchResolvesCommercialInquiryLane() {
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: intent(.offerSearch)), .commercialInquiry)
    }

    func testDirectMessageMetadataOverridesIntentLane() {
        let lane = ExchangeThreadLaneResolver.lane(
            for: intent(.providerSearch),
            metadata: ["direct_message_thread": "true"]
        )
        XCTAssertEqual(lane, .directMessage)
    }

    func testContactSignalMetadataOverridesIntentLane() {
        let lane = ExchangeThreadLaneResolver.lane(
            for: intent(.socialAffinitySearch),
            metadata: ["contact_request_thread": "true"]
        )
        XCTAssertEqual(lane, .contactSignal)
    }

    func testBeginThreadAppliesLaneMetadata() {
        let engine = ExchangeThreadEngine()
        let socialIntent = intent(.socialAffinitySearch, mode: .relational)
        let mutation = engine.beginThread(
            userText: "Find hiking friends",
            mode: .relational,
            intent: socialIntent,
            posture: .default
        )
        XCTAssertEqual(
            mutation.thread.metadata[ExchangeThreadLaneResolver.metadataKey],
            ExchangeThreadLane.socialConnection.rawValue
        )
        XCTAssertEqual(
            mutation.thread.metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey],
            ExchangeThreadLaneResolver.conversationSurfaceSocialConnection
        )
    }

    func testRecordSelectedMatchClearsOfferForSocialLane() throws {
        let engine = ExchangeThreadEngine()
        let base = thread(
            intent: intent(.socialAffinitySearch, mode: .relational),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue,
                ExchangeThreadLaneResolver.conversationSurfaceMetadataKey:
                    ExchangeThreadLaneResolver.conversationSurfaceSocialConnection
            ]
        )
        let mutation = try engine.recordSelectedMatch(
            thread: base,
            selectedCounterpartyID: "node-abc",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: "offer-should-drop",
            candidateIDs: ["node-abc"],
            summary: "Found profile path"
        )
        XCTAssertNil(mutation.thread.selectedOfferID)
        XCTAssertEqual(mutation.thread.selectedPublicProfileID, "profile-1")
    }

    func testRecordSelectedMatchKeepsOfferForCommercialLane() throws {
        let engine = ExchangeThreadEngine()
        let base = thread(
            intent: intent(.offerSearch),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.commercialInquiry.rawValue
            ]
        )
        let mutation = try engine.recordSelectedMatch(
            thread: base,
            selectedCounterpartyID: "node-abc",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: "offer-keep",
            candidateIDs: ["node-abc"],
            summary: "Found offer path"
        )
        XCTAssertEqual(mutation.thread.selectedOfferID, "offer-keep")
    }

    func testOutboundEnvelopeMetadataForSocialConnection() {
        let svc = ExchangeEnvelopeService(identityService: FixedLaneTestIdentityService())
        let thread = thread(
            intent: intent(.socialAffinitySearch, mode: .relational),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue,
                ExchangeThreadLaneResolver.conversationSurfaceMetadataKey:
                    ExchangeThreadLaneResolver.conversationSurfaceSocialConnection
            ]
        )
        let md = svc.contactRequestContract_buildMetadata(
            thread: thread,
            counterparty: laneTestCounterparty(),
            publicProfile: laneTestProfile(),
            draft: laneTestDraft(threadID: thread.id),
            requestedDisclosureLevel: .balanced,
            effectiveDisclosureLevel: .balanced,
            resolvedRoute: ExchangeRelayRoute(routeKey: "node:remote-node", kind: .node, destination: "remote-node"),
            resolvedTargetNodeID: "remote-node"
        )
        XCTAssertEqual(md[ExchangeThreadLaneResolver.metadataKey], ExchangeThreadLane.socialConnection.rawValue)
        XCTAssertEqual(
            md[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey],
            ExchangeThreadLaneResolver.conversationSurfaceSocialConnection
        )
    }

    func testInboundEnvelopeMetadataPreservesSocialConnectionLane() {
        let lane = ExchangeThreadLaneResolver.laneFromInboundEnvelopeMetadata([
            ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue,
            ExchangeThreadLaneResolver.conversationSurfaceMetadataKey:
                ExchangeThreadLaneResolver.conversationSurfaceSocialConnection,
            "selected_offer_id": "offer-should-not-anchor"
        ])
        XCTAssertEqual(lane, .socialConnection)
        XCTAssertTrue(ExchangeThreadLaneResolver.clearsCommercialOfferAnchor(for: lane))
    }

    func testInferSecondHalfRoleSkipsProviderForSocialConnectionInbound() {
        let socialInbound = thread(
            intent: intent(.socialAffinitySearch, mode: .relational),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue,
                "inbound_thread": "true"
            ],
            lastInboundEnvelopeID: "env-1"
        )
        XCTAssertEqual(ExchangeThreadLaneResolver.inferSecondHalfRole(for: socialInbound), .requester)
    }

    func testInferSecondHalfRoleKeepsProviderForCommercialInbound() {
        let commercialInbound = thread(
            intent: intent(.offerSearch),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.commercialInquiry.rawValue,
                "inbound_thread": "true"
            ],
            lastInboundEnvelopeID: "env-2"
        )
        XCTAssertEqual(ExchangeThreadLaneResolver.inferSecondHalfRole(for: commercialInbound), .provider)
    }

    func testInferSecondHalfRoleUnchangedForDirectMessage() {
        let dm = thread(
            intent: intent(.directOutreach),
            metadata: ["direct_message_thread": "true"],
            lastInboundEnvelopeID: "env-dm"
        )
        XCTAssertEqual(ExchangeThreadLaneResolver.inferSecondHalfRole(for: dm), .requester)
    }

    func testSecondHalfMutationSkippedForSocialConnection() {
        let social = thread(
            intent: intent(.socialAffinitySearch, mode: .relational),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue
            ]
        )
        XCTAssertTrue(ExchangeThreadLaneResolver.isSecondHalfMutationSkipped(for: social))
    }

    func testSecondHalfMutationNotSkippedForCommercialInquiry() {
        let commercial = thread(
            intent: intent(.offerSearch),
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.commercialInquiry.rawValue
            ]
        )
        XCTAssertFalse(ExchangeThreadLaneResolver.isSecondHalfMutationSkipped(for: commercial))
    }
}

private actor FixedLaneTestIdentityService: ExchangeIdentityService {
    func localIdentity() async throws -> ExchangeLocalIdentity {
        ExchangeLocalIdentity(
            nodeID: "local-lane-test",
            displayName: "Lane Test",
            publicKeyID: "key",
            verification: .selfAsserted,
            supportedProtocolVersions: [ExchangeProtocolVersion.current],
            defaultRouteHint: nil,
            metadata: [:]
        )
    }

    func signEnvelope(_ envelope: ExchangeRelayEnvelope) async throws -> ExchangeRelayEnvelope.Signature {
        ExchangeRelayEnvelope.Signature(
            algorithm: .other,
            value: "sig",
            keyID: "key",
            signatureVersion: "1"
        )
    }

    func verifyEnvelopeSignature(
        _ envelope: ExchangeRelayEnvelope,
        expectedKeyID: String?
    ) async throws -> ExchangeEnvelopeVerificationResult {
        .valid
    }
}

private func laneTestCounterparty() -> ExchangeCounterparty {
    ExchangeCounterparty(
        id: "remote-node",
        kind: .person,
        displayName: "Remote",
        source: .manualEntry,
        identity: .init(nodeID: "remote-node", publicKeyID: nil, verification: .unverified)
    )
}

private func laneTestProfile() -> ExchangePublicNodeProfile {
    ExchangePublicNodeProfile(
        id: "profile-1",
        nodeID: "remote-node",
        counterpartyID: "remote-node",
        displayName: "Remote",
        reachability: .init(
            accessMode: .direct,
            acceptingInbound: true,
            intentCategoryPolicy: .permissive,
            disclosureCeiling: .balanced
        )
    )
}

private func laneTestDraft(threadID: ExchangeThread.ID) -> ExchangeMessageDraft {
    ExchangeMessageDraft(
        threadID: threadID,
        kind: .inquiry,
        audience: .externalCounterparty,
        subject: "Hello",
        body: "Interested in connecting.",
        posture: .default
    )
}
