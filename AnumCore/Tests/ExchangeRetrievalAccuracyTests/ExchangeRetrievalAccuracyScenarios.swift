import Foundation
@testable import AnumCore

enum ExchangeRetrievalAccuracyScenarios {
    typealias Scenario = (ExchangeThread, ExchangeRetrievalAccuracyScenarioExpectation)
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID
    private typealias O = ExchangeRetrievalAccuracyFixtureBuilder.OfferID
    private typealias F = ExchangeRetrievalAccuracyThreadFactory

    static let all: [Scenario] = [
        s1(), s2(), s3(), s4(), s5(), s6(), s7(), s8(), s9(), s10(),
        s11(), s12(), s13(), s14(), s15(), s16(), s17(), s18(), s19(), s20()
    ]

    private static func s1() -> Scenario {
        (F.makeThread(rawUserText: "computer", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "computer", transactionIntent: .buy, semanticConcepts: ["computer"], broadRecallTokens: ["computer"]),
         .init(id: "object-lane.computer", queryLabel: "computer", expectedSummary: "object lane proves computer; car forbidden", objectLaneActive: true,
               requiredInTopK: [N.computerSeller, N.multiSeller],
               forbiddenAttachments: [(N.carSeller, O.toyotaCamry), (N.multiSeller, O.multiCar)],
               selectedOfferID: O.dellLaptop,
               maxRankByNode: [N.computerSeller: 3, N.multiSeller: 3],
               requiresAdvanceable: true,
               category: .objectLane,
               primaryExpectedNodeID: N.computerSeller,
               acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
               equivalentResultGroupName: "valid computer providers"))
    }

    private static func s2() -> Scenario {
        (F.makeThread(rawUserText: "car", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "car", transactionIntent: .buy, semanticConcepts: ["car"], broadRecallTokens: ["car"]),
         .init(id: "object-lane.car", queryLabel: "car", expectedSummary: "car seller top; Toyota proven", objectLaneActive: true,
               requiredInTopK: [N.carSeller],
               forbiddenAttachments: [(N.computerSeller, O.dellLaptop), (N.multiSeller, O.multiComputer)],
               selectedOfferID: O.toyotaCamry,
               maxRankByNode: [N.carSeller: 3],
               requiresAdvanceable: true,
               category: .objectLane))
    }

    private static func s3() -> Scenario {
        (F.makeThread(rawUserText: "computer", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "computer", transactionIntent: .buy, semanticConcepts: ["computer"], broadRecallTokens: ["computer"]),
         .init(id: "object-lane.multi-seller-computer", queryLabel: "computer (multi-seller)", expectedSummary: "only multi-computer on multi-seller", objectLaneActive: true,
               requiredInTopK: [N.multiSeller],
               requiredMatchedOffers: [N.multiSeller: [O.multiComputer]],
               forbiddenAttachments: [(N.multiSeller, O.multiCar)],
               category: .objectLane,
               primaryExpectedNodeID: N.multiSeller,
               acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
               equivalentResultGroupName: "valid computer providers"))
    }

    private static func s4() -> Scenario {
        (F.makeThread(rawUserText: "laptop", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "laptop", transactionIntent: .buy, semanticConcepts: ["laptop"], broadRecallTokens: ["laptop"]),
         .init(id: "object-lane.laptop", queryLabel: "laptop", expectedSummary: "computer above car", objectLaneActive: true,
               requiredInTopK: [N.computerSeller],
               forbiddenAttachments: [(N.carSeller, O.toyotaCamry)],
               maxRankByNode: [N.computerSeller: 3],
               category: .objectLane,
               primaryExpectedNodeID: N.computerSeller,
               acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
               equivalentResultGroupName: "valid computer providers"))
    }

    private static func s5() -> Scenario {
        (F.makeThread(rawUserText: "wedding photo package", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .professionalService, semanticConcepts: ["wedding", "photography"], broadRecallTokens: ["wedding", "photo", "package"], providerTerms: ["photographer"]),
         .init(id: "package.wedding-photo", queryLabel: "wedding photo package", expectedSummary: "photographer top; detail/package docKinds", objectLaneActive: false,
               requiredInTopK: [N.photographer],
               requiredDocKindsInTopTrace: [.offerDetail],
               forbiddenDocKindsFirstRank: [.offerFAQ],
               maxRankByNode: [N.photographer: 3],
               category: .packageFAQ))
    }

    private static func s6() -> Scenario {
        (F.makeThread(rawUserText: "how long does photo delivery take?", queryIntentClass: .followUp, surfacePreference: .offer, semanticConcepts: ["delivery"], broadRecallTokens: ["delivery", "photo"]),
         .init(id: "faq.photo-delivery", queryLabel: "how long does photo delivery take?", expectedSummary: "photographer FAQ top; object lane inactive", objectLaneActive: false,
               requiredInTopK: [N.photographer],
               requiredDocKindsInTopTrace: [.offerFAQ],
               category: .packageFAQ))
    }

    private static func s7() -> Scenario {
        (F.makeThread(rawUserText: "move out cleaning package", queryIntentClass: .offerSearch, surfacePreference: .offer, semanticConcepts: ["cleaning"], broadRecallTokens: ["move", "out", "cleaning", "package"]),
         .init(id: "package.move-out-cleaning", queryLabel: "move out cleaning package", expectedSummary: "cleaner above unrelated", objectLaneActive: false,
               requiredInTopK: [N.cleaner],
               maxRankByNode: [N.cleaner: 3, N.photographer: 10],
               category: .packageFAQ))
    }

    private static func s8() -> Scenario {
        (F.makeThread(rawUserText: "find me a coder", queryIntentClass: .capabilitySearch, surfacePreference: .capability, semanticConcepts: ["coder"], broadRecallTokens: ["coder"], capabilityTerms: ["coder", "software"]),
         .init(id: "capability.find-coder", queryLabel: "find me a coder", expectedSummary: "node-coder top 3", objectLaneActive: false,
               requiredInTopK: [N.coder],
               maxRankByNode: [N.coder: 3],
               category: .providerCapability))
    }

    private static func s9() -> Scenario {
        (F.makeThread(rawUserText: "find a plumber for an appraisal", queryIntentClass: .providerSearch, surfacePreference: .capability, domainCategory: .homeService, semanticConcepts: ["plumber"], broadRecallTokens: ["plumber", "appraisal"], providerTerms: ["plumber"], capabilityTerms: ["appraisal"]),
         .init(id: "provider.plumber-appraisal", queryLabel: "find a plumber for an appraisal", expectedSummary: "plumber top 3", objectLaneActive: false,
               requiredInTopK: [N.plumber],
               maxRankByNode: [N.plumber: 3],
               category: .providerCapability))
    }

    private static func s10() -> Scenario {
        (F.makeThread(rawUserText: "find someone who can build an iOS app", queryIntentClass: .capabilitySearch, surfacePreference: .capability, semanticConcepts: ["iOS", "app"], broadRecallTokens: ["ios", "app"], capabilityTerms: ["ios", "app"]),
         .init(id: "capability.build-ios-app", queryLabel: "build an iOS app", expectedSummary: "coder top 3", objectLaneActive: false,
               requiredInTopK: [N.coder],
               maxRankByNode: [N.coder: 3],
               category: .providerCapability))
    }

    private static func s11() -> Scenario {
        (F.makeThread(rawUserText: "find someone interested in robotics", queryIntentClass: .socialAffinitySearch, surfacePreference: .affinity, semanticConcepts: ["robotics"], broadRecallTokens: ["robotics"], affinityTerms: ["robotics"]),
         .init(id: "affinity.robotics", queryLabel: "interested in robotics", expectedSummary: "robotics-founder top", objectLaneActive: false,
               requiredInTopK: [N.roboticsFounder],
               requiredDocKindsInTopTrace: [.profileAffinity],
               category: .seekingAffinity))
    }

    private static func s12() -> Scenario {
        (F.makeThread(rawUserText: "find someone open to startup collaboration", queryIntentClass: .collaborationSearch, surfacePreference: .capability, semanticConcepts: ["startup"], broadRecallTokens: ["startup", "collaboration"], capabilityTerms: ["collaboration"]),
         .init(id: "seeking.startup-collaboration", queryLabel: "startup collaboration", expectedSummary: "coder or robotics-founder top 3", objectLaneActive: false,
               maxRankByNode: [N.coder: 3, N.roboticsFounder: 3],
               category: .seekingAffinity))
    }

    private static func s13() -> Scenario {
        (F.makeThread(rawUserText: "local founders interested in AI robotics", queryIntentClass: .socialAffinitySearch, surfacePreference: .affinity, semanticConcepts: ["AI", "robotics"], broadRecallTokens: ["founders", "ai", "robotics"], affinityTerms: ["ai", "robotics", "founders"]),
         .init(id: "affinity.local-founders-ai", queryLabel: "local founders AI robotics", expectedSummary: "founder nodes above sellers", objectLaneActive: false,
               requiredInTopK: [N.roboticsFounder, N.coder],
               maxRankByNode: [N.carSeller: 8, N.computerSeller: 8],
               category: .seekingAffinity,
               primaryExpectedNodeID: N.roboticsFounder,
               acceptableTop1NodeIDs: [N.roboticsFounder, N.coder],
               equivalentResultGroupName: "valid AI/robotics/founder profiles"))
    }

    private static func s14() -> Scenario {
        (F.makeThread(rawUserText: "find a photographer open to startup collaboration", queryIntentClass: .collaborationSearch, surfacePreference: .mixed, semanticConcepts: ["photographer", "collaboration"], broadRecallTokens: ["photographer", "startup", "collaboration"]),
         .init(id: "mixed.photographer-collaboration", queryLabel: "photographer startup collaboration", expectedSummary: "mixed docKinds; safe attachments", objectLaneActive: false,
               category: .mixedNoisy))
    }

    private static func s15() -> Scenario {
        (F.makeThread(rawUserText: "computer under 500 tomorrow", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "computer", transactionIntent: .buy, semanticConcepts: ["computer"], broadRecallTokens: ["computer"], timeText: "tomorrow"),
         .init(id: "object-lane.computer-budget-time", queryLabel: "computer under 500 tomorrow", expectedSummary: "computer proven; car forbidden", objectLaneActive: true,
               requiredInTopK: [N.computerSeller],
               forbiddenAttachments: [(N.carSeller, O.toyotaCamry), (N.multiSeller, O.multiCar)],
               category: .objectLane))
    }

    private static func s16() -> Scenario {
        (F.makeThread(rawUserText: "available tomorrow", queryIntentClass: .generalDiscovery, surfacePreference: .mixed, broadRecallTokens: ["available", "tomorrow"], timeText: "tomorrow"),
         .init(id: "mixed.available-tomorrow", queryLabel: "available tomorrow", expectedSummary: "weak/non-advanceable", objectLaneActive: false,
               selectedOfferIDMustBeNil: true,
               requiresAdvanceable: false,
               allowsWeakOrNone: true,
               category: .mixedNoisy))
    }

    private static func s17() -> Scenario {
        (F.makeThread(rawUserText: "do they offer delivery?", queryIntentClass: .followUp, surfacePreference: .offer, broadRecallTokens: ["delivery"]),
         .init(id: "faq.delivery", queryLabel: "do they offer delivery?", expectedSummary: "FAQ ranks; no object proof", objectLaneActive: false,
               requiredDocKindsInTopTrace: [.offerFAQ],
               category: .packageFAQ))
    }

    private static func s18() -> Scenario {
        (F.makeThread(rawUserText: "Toyota", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "car", transactionIntent: .buy, semanticConcepts: ["Toyota"], broadRecallTokens: ["toyota", "car"]),
         .init(id: "object-lane.toyota", queryLabel: "Toyota", expectedSummary: "car seller top", objectLaneActive: true,
               requiredInTopK: [N.carSeller],
               requiredMatchedOffers: [N.carSeller: [O.toyotaCamry]],
               maxRankByNode: [N.carSeller: 3],
               category: .objectLane))
    }

    private static func s19() -> Scenario {
        (F.makeThread(rawUserText: "MacBook", queryIntentClass: .offerSearch, surfacePreference: .offer, domainCategory: .product, objectType: "computer", transactionIntent: .buy, semanticConcepts: ["MacBook"], broadRecallTokens: ["macbook", "computer"]),
         .init(id: "object-lane.macbook", queryLabel: "MacBook", expectedSummary: "computer seller top", objectLaneActive: true,
               requiredInTopK: [N.computerSeller],
               maxRankByNode: [N.computerSeller: 3],
               category: .objectLane,
               primaryExpectedNodeID: N.computerSeller,
               acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
               equivalentResultGroupName: "valid computer providers"))
    }

    private static func s20() -> Scenario {
        (F.makeThread(rawUserText: "founder with hardware automation interests", queryIntentClass: .socialAffinitySearch, surfacePreference: .affinity, semanticConcepts: ["founder", "hardware"], broadRecallTokens: ["founder", "hardware", "automation"], affinityTerms: ["robotics", "automation", "hardware"]),
         .init(id: "affinity.founder-hardware", queryLabel: "founder hardware automation", expectedSummary: "robotics/coder rank; no commercial attachment", objectLaneActive: false,
               requiredInTopK: [N.roboticsFounder, N.coder],
               category: .seekingAffinity))
    }


    static let mandatoryOnnxSmokeIDs: Set<String> = [
        "object-lane.computer",
        "object-lane.car",
        "object-lane.multi-seller-computer",
        "object-lane.laptop",
        "package.wedding-photo",
        "faq.photo-delivery",
        "capability.find-coder",
        "affinity.robotics",
        "seeking.startup-collaboration",
        "object-lane.computer-budget-time"
    ]

    static let extendedOnnxSmokeIDs: Set<String> = mandatoryOnnxSmokeIDs.union([
        "capability.build-ios-app",
        "mixed.photographer-collaboration",
        "object-lane.toyota",
        "faq.delivery"
    ])

    static func scenarios(forIDs ids: Set<String>) -> [Scenario] {
        all.filter { ids.contains($0.1.id) }
    }

    static func scenario(forID id: String) -> Scenario? {
        all.first { $0.1.id == id }
    }

    static func onnxSmokeScenarioIDs() -> Set<String> {
        if ExchangeRetrievalOnnxSmokeGate.isExtendedEnabled {
            return extendedOnnxSmokeIDs
        }
        return mandatoryOnnxSmokeIDs
    }
}

