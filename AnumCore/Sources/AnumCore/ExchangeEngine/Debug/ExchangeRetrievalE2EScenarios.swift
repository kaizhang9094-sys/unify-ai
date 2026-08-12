import Foundation

#if DEBUG

public struct ExchangeRetrievalE2EStructuralExpectation: Sendable {
    public var expectedObjectLaneActive: Bool
    public var requiredObjectType: String?
    public var requiredRouteClass: String?
    public var allowedRouteClasses: [String]?
    public var requiredSurfacePreference: String?
    public var requiredDomainCategory: String?
    public var forbiddenDomainCategory: String?
    public var requiredTransactionIntent: String?
    public var forbiddenTransactionIntents: [String]
    /// When true, fail if canonical fields incorrectly activate product+buy object lane on a service query.
    public var forbidIncorrectProductBuyLane: Bool
    public var requireTimeConstraint: Bool
    public var requireBudgetConstraint: Bool
    /// FAQ/detail docs may rank, but must not prove offer-object identity by themselves.
    public var requireFAQDocsDoNotProveObject: Bool

    public init(
        expectedObjectLaneActive: Bool,
        requiredObjectType: String? = nil,
        requiredRouteClass: String? = nil,
        allowedRouteClasses: [String]? = nil,
        requiredSurfacePreference: String? = nil,
        requiredDomainCategory: String? = nil,
        forbiddenDomainCategory: String? = nil,
        requiredTransactionIntent: String? = nil,
        forbiddenTransactionIntents: [String] = [],
        forbidIncorrectProductBuyLane: Bool = false,
        requireTimeConstraint: Bool = false,
        requireBudgetConstraint: Bool = false,
        requireFAQDocsDoNotProveObject: Bool = false
    ) {
        self.expectedObjectLaneActive = expectedObjectLaneActive
        self.requiredObjectType = requiredObjectType
        self.requiredRouteClass = requiredRouteClass
        self.allowedRouteClasses = allowedRouteClasses
        self.requiredSurfacePreference = requiredSurfacePreference
        self.requiredDomainCategory = requiredDomainCategory
        self.forbiddenDomainCategory = forbiddenDomainCategory
        self.requiredTransactionIntent = requiredTransactionIntent
        self.forbiddenTransactionIntents = forbiddenTransactionIntents
        self.forbidIncorrectProductBuyLane = forbidIncorrectProductBuyLane
        self.requireTimeConstraint = requireTimeConstraint
        self.requireBudgetConstraint = requireBudgetConstraint
        self.requireFAQDocsDoNotProveObject = requireFAQDocsDoNotProveObject
    }
}

public struct ExchangeRetrievalE2EScenario: Sendable {
    public var queryText: String
    public var structural: ExchangeRetrievalE2EStructuralExpectation
    public var retrieval: ExchangeRetrievalAccuracyScenarioExpectation?

    public init(
        queryText: String,
        structural: ExchangeRetrievalE2EStructuralExpectation,
        retrieval: ExchangeRetrievalAccuracyScenarioExpectation? = nil
    ) {
        self.queryText = queryText
        self.structural = structural
        self.retrieval = retrieval
    }
}

public enum ExchangeRetrievalE2EScenarios {
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID
    private typealias O = ExchangeRetrievalAccuracyFixtureBuilder.OfferID

    /// Real-device DEBUG smoke cases exercising the full ExchangeFacade submit path.
    public static let mandatory: [ExchangeRetrievalE2EScenario] = [
        .init(
            queryText: "find me a computer under 500 tomorrow",
            structural: .init(
                expectedObjectLaneActive: true,
                requiredObjectType: "computer",
                requiredRouteClass: "offerSearch",
                requiredSurfacePreference: "offer",
                requiredDomainCategory: "product",
                requiredTransactionIntent: "buy",
                requireTimeConstraint: true,
                requireBudgetConstraint: true
            ),
            retrieval: .init(
                id: "e2e.computer-budget-time",
                queryLabel: "find me a computer under 500 tomorrow",
                expectedSummary: "object lane proves computer; sibling car forbidden",
                objectLaneActive: true,
                requiredInTopK: [N.computerSeller],
                forbiddenAttachments: [(N.carSeller, O.toyotaCamry), (N.multiSeller, O.multiCar)],
                category: .objectLane
            )
        ),
        .init(
            queryText: "find me a car",
            structural: .init(
                expectedObjectLaneActive: true,
                requiredObjectType: "car",
                requiredRouteClass: "offerSearch",
                requiredSurfacePreference: "offer",
                requiredDomainCategory: "product",
                requiredTransactionIntent: "buy"
            ),
            retrieval: .init(
                id: "e2e.car",
                queryLabel: "find me a car",
                expectedSummary: "car seller top; computer forbidden",
                objectLaneActive: true,
                requiredInTopK: [N.carSeller],
                forbiddenAttachments: [(N.computerSeller, O.dellLaptop), (N.multiSeller, O.multiComputer)],
                selectedOfferID: O.toyotaCamry,
                category: .objectLane
            )
        ),
        .init(
            queryText: "find me a cleaner tomorrow at 2 under 200",
            structural: .init(
                expectedObjectLaneActive: false,
                allowedRouteClasses: ["providerSearch", "offerSearch"],
                requiredSurfacePreference: "offer",
                forbiddenDomainCategory: "product",
                forbiddenTransactionIntents: ["buy", "forSale"],
                forbidIncorrectProductBuyLane: true,
                requireTimeConstraint: true,
                requireBudgetConstraint: true
            ),
            retrieval: .init(
                id: "e2e.cleaner-budget-time",
                queryLabel: "find me a cleaner tomorrow at 2 under 200",
                expectedSummary: "cleaner service path; product buy lane must stay inactive",
                objectLaneActive: false,
                requiredInTopK: [N.cleaner],
                maxRankByNode: [N.cleaner: 5],
                category: .providerCapability
            )
        ),
        .init(
            queryText: "who can deliver this?",
            structural: .init(
                expectedObjectLaneActive: false,
                forbidIncorrectProductBuyLane: true,
                requireFAQDocsDoNotProveObject: true
            ),
            retrieval: .init(
                id: "e2e.delivery-faq",
                queryLabel: "who can deliver this?",
                expectedSummary: "FAQ/detail may surface; object lane inactive",
                objectLaneActive: false,
                requiredInTopK: [N.photographer],
                requiredDocKindsInTopTrace: [.offerFAQ],
                category: .packageFAQ
            )
        ),
        .init(
            queryText: "find me someone who repairs laptops",
            structural: .init(
                expectedObjectLaneActive: false,
                requiredRouteClass: "providerSearch",
                requiredSurfacePreference: "offer",
                forbiddenDomainCategory: "product",
                forbiddenTransactionIntents: ["buy", "forSale"],
                forbidIncorrectProductBuyLane: true
            ),
            retrieval: .init(
                id: "e2e.laptop-repair-service",
                queryLabel: "find me someone who repairs laptops",
                expectedSummary: "repair/service provider path; not product buy lane",
                objectLaneActive: false,
                requiredInTopK: [N.plumber],
                maxRankByNode: [N.plumber: 5],
                category: .providerCapability
            )
        ),
    ]
}

#endif
