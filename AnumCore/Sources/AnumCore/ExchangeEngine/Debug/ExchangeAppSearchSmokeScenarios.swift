import Foundation

#if DEBUG

public struct ExchangeAppSearchSmokeScenario: Sendable {
    public var queryText: String
    public var expectation: ExchangeRetrievalAccuracyScenarioExpectation

    public init(queryText: String, expectation: ExchangeRetrievalAccuracyScenarioExpectation) {
        self.queryText = queryText
        self.expectation = expectation
    }
}

public enum ExchangeAppSearchSmokeScenarios {
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID
    private typealias O = ExchangeRetrievalAccuracyFixtureBuilder.OfferID

    public static let mandatory: [ExchangeAppSearchSmokeScenario] = [
        .init(
            queryText: "computer",
            expectation: .init(
                id: "object-lane.computer",
                queryLabel: "computer",
                expectedSummary: "object lane proves computer; car forbidden",
                objectLaneActive: true,
                requiredInTopK: [N.computerSeller, N.multiSeller],
                forbiddenAttachments: [(N.carSeller, O.toyotaCamry), (N.multiSeller, O.multiCar)],
                selectedOfferID: O.dellLaptop,
                maxRankByNode: [N.computerSeller: 3, N.multiSeller: 3],
                requiresAdvanceable: true,
                category: .objectLane,
                primaryExpectedNodeID: N.computerSeller,
                acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
                equivalentResultGroupName: "valid computer providers"
            )
        ),
        .init(
            queryText: "car",
            expectation: .init(
                id: "object-lane.car",
                queryLabel: "car",
                expectedSummary: "car seller top; Toyota proven",
                objectLaneActive: true,
                requiredInTopK: [N.carSeller],
                forbiddenAttachments: [(N.computerSeller, O.dellLaptop), (N.multiSeller, O.multiComputer)],
                selectedOfferID: O.toyotaCamry,
                maxRankByNode: [N.carSeller: 3],
                requiresAdvanceable: true,
                category: .objectLane
            )
        ),
        .init(
            queryText: "computer",
            expectation: .init(
                id: "object-lane.multi-seller-computer",
                queryLabel: "computer (multi-seller)",
                expectedSummary: "only multi-computer on multi-seller",
                objectLaneActive: true,
                requiredInTopK: [N.multiSeller],
                requiredMatchedOffers: [N.multiSeller: [O.multiComputer]],
                forbiddenAttachments: [(N.multiSeller, O.multiCar)],
                category: .objectLane,
                primaryExpectedNodeID: N.multiSeller,
                acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
                equivalentResultGroupName: "valid computer providers"
            )
        ),
        .init(
            queryText: "laptop",
            expectation: .init(
                id: "object-lane.laptop",
                queryLabel: "laptop",
                expectedSummary: "computer above car",
                objectLaneActive: true,
                requiredInTopK: [N.computerSeller],
                forbiddenAttachments: [(N.carSeller, O.toyotaCamry)],
                maxRankByNode: [N.computerSeller: 3],
                category: .objectLane,
                primaryExpectedNodeID: N.computerSeller,
                acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
                equivalentResultGroupName: "valid computer providers"
            )
        ),
        .init(
            queryText: "computer under 500 tomorrow",
            expectation: .init(
                id: "object-lane.computer-budget-time",
                queryLabel: "computer under 500 tomorrow",
                expectedSummary: "computer proven; car forbidden",
                objectLaneActive: true,
                requiredInTopK: [N.computerSeller],
                forbiddenAttachments: [(N.carSeller, O.toyotaCamry), (N.multiSeller, O.multiCar)],
                category: .objectLane
            )
        ),
        .init(
            queryText: "wedding photo package",
            expectation: .init(
                id: "package.wedding-photo",
                queryLabel: "wedding photo package",
                expectedSummary: "photographer top; detail/package docKinds",
                objectLaneActive: false,
                requiredInTopK: [N.photographer],
                requiredDocKindsInTopTrace: [.offerDetail],
                forbiddenDocKindsFirstRank: [.offerFAQ],
                maxRankByNode: [N.photographer: 3],
                category: .packageFAQ
            )
        ),
        .init(
            queryText: "how long does photo delivery take?",
            expectation: .init(
                id: "faq.photo-delivery",
                queryLabel: "how long does photo delivery take?",
                expectedSummary: "photographer FAQ top; object lane inactive",
                objectLaneActive: false,
                requiredInTopK: [N.photographer],
                requiredDocKindsInTopTrace: [.offerFAQ],
                category: .packageFAQ
            )
        ),
        .init(
            queryText: "find me a coder",
            expectation: .init(
                id: "capability.find-coder",
                queryLabel: "find me a coder",
                expectedSummary: "node-coder top 3",
                objectLaneActive: false,
                requiredInTopK: [N.coder],
                maxRankByNode: [N.coder: 3],
                category: .providerCapability
            )
        ),
        .init(
            queryText: "find someone interested in robotics",
            expectation: .init(
                id: "affinity.robotics",
                queryLabel: "interested in robotics",
                expectedSummary: "robotics-founder top",
                objectLaneActive: false,
                requiredInTopK: [N.roboticsFounder],
                requiredDocKindsInTopTrace: [.profileAffinity],
                category: .seekingAffinity
            )
        ),
        .init(
            queryText: "find someone open to startup collaboration",
            expectation: .init(
                id: "seeking.startup-collaboration",
                queryLabel: "startup collaboration",
                expectedSummary: "coder or robotics-founder top 3",
                objectLaneActive: false,
                maxRankByNode: [N.coder: 3, N.roboticsFounder: 3],
                category: .seekingAffinity
            )
        ),
    ]
}

#endif
