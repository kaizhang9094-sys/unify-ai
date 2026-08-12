import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeActorNounNormalization")
struct ExchangeActorNounNormalizationTests {

    @Test("laptop repair actor noun never becomes retrieval object text")
    func laptopRepairNeverUsesActorAsRetrievalObject() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["repair laptop"],
            rawUserText: "find me someone who repairs laptops"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.rawObject == "person")
        #expect(result.searchIntent.objectType == nil)
        #expect(result.retrievalObjectText == "repair laptop")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "repair laptop")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) != "person")
    }

    @Test("car seller actor noun uses need phrase for retrieval object text")
    func carSellerUsesNeedPhraseForRetrievalObjectText() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "someone",
            transactionIntent: .buy,
            semanticConcepts: ["sell car"],
            rawUserText: "find me someone selling a car"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.searchIntent.objectType == nil)
        #expect(result.retrievalObjectText == "sell car")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "sell car")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) != "someone")
    }

    @Test("cleaner role noun is not treated as generic actor")
    func cleanerRoleDoesNotNormalize() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "cleaner",
            transactionIntent: .hire,
            semanticConcepts: ["cleaning"],
            rawUserText: "find me a cleaner"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(!result.applied)
        #expect(result.searchIntent.objectType == "cleaner")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "cleaner")
    }

    @Test("house cleaning keeps need phrase without splitting")
    func houseCleaningKeepsNeedPhraseWithoutSplitting() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["house cleaning"],
            rawUserText: "find me someone for house cleaning"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.searchIntent.objectType == nil)
        #expect(result.retrievalObjectText == "house cleaning")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "house cleaning")
    }

    @Test("plain person search clears actor object and avoids object lane carrier")
    func plainPersonSearchClearsActorObject() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "person",
            transactionIntent: nil,
            semanticConcepts: [],
            rawUserText: "find me a person"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.searchIntent.objectType == nil)
        #expect(result.retrievalObjectText == nil)
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == nil)

        let thread = makeThread(
            queryIntentClass: .providerSearch,
            domainCategory: .general,
            transactionIntent: nil,
            objectType: result.searchIntent.objectType,
            semanticConcepts: result.searchIntent.semanticConcepts
        )
        #expect(!ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    @Test("semantic concepts drop actor noun after guard")
    func semanticConceptsDropActorNounAfterGuard() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["person", "repair laptop"],
            rawUserText: "find me someone who repairs laptops"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(!result.searchIntent.semanticConcepts.contains(where: { $0.lowercased() == "person" }))
        #expect(result.searchIntent.semanticConcepts == ["repair laptop"])
    }

    @Test("retrieval resolver prefers multi-token need over generic concepts")
    func retrievalResolverPrefersMultiTokenNeed() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["provider", "laptop", "repair laptop"],
            rawUserText: "find me someone to repair my laptop"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.retrievalObjectText == "repair laptop")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "repair laptop")
    }

    @Test("punctuation is stripped from retrieval object text")
    func punctuationIsStrippedFromRetrievalObjectText() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["repair laptops?"],
            rawUserText: "find me someone who repairs laptops?"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.retrievalObjectText == "repair laptops")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "repair laptops")
    }

    @Test("already extracted single object token may promote objectType when no need phrase")
    func alreadyExtractedSingleObjectMayPromoteObjectType() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "person",
            transactionIntent: .buy,
            semanticConcepts: ["laptop"],
            rawUserText: "find me someone with a laptop for sale"
        )

        let result = ExchangeActorNounNormalization.normalize(canonical, source: "unitTest")

        #expect(result.applied)
        #expect(result.searchIntent.objectType == "laptop")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: result.searchIntent) == "laptop")
    }

    @Test("live interpretation wrapper applies actor guard before product lane")
    func liveInterpretationWrapperAppliesActorGuard() {
        var canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["repair laptop"],
            rawUserText: "find me someone who repairs laptops"
        )

        canonical = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
            canonical,
            source: "unitTest"
        )

        #expect(canonical.objectType == nil)
        #expect(ExchangeOfferObjectLane.queryObjectText(from: canonical) == "repair laptop")
    }

    @Test("read path blocks actor noun even before normalize")
    func readPathBlocksActorNounBeforeNormalize() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "person",
            transactionIntent: .hire,
            semanticConcepts: ["repair laptop"],
            rawUserText: "find me someone who repairs laptops"
        )

        #expect(ExchangeOfferObjectLane.queryObjectText(from: canonical) == "repair laptop")
        #expect(ExchangeOfferObjectLane.queryObjectText(from: canonical) != "person")
    }

    @Test("english and raw fallback reject pure search boilerplate")
    func englishAndRawFallbackRejectPureSearchBoilerplate() {
        let boilerplateOnly = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "person",
            semanticConcepts: [],
            rawUserText: "find me someone",
            canonicalEnglishSearchText: "find me someone"
        )

        #expect(ExchangeActorNounNormalization.resolvedRetrievalObjectText(from: boilerplateOnly) == nil)

        let withMeaningfulRaw = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "someone",
            semanticConcepts: [],
            rawUserText: "find me someone who repairs laptops",
            canonicalEnglishSearchText: "find me someone who repairs laptops"
        )

        #expect(
            ExchangeActorNounNormalization.resolvedRetrievalObjectText(from: withMeaningfulRaw) == "repairs laptops"
        )
    }

}

private func makeThread(
    queryIntentClass: ExchangeIntent.QueryIntentClass,
    domainCategory: ExchangeIntentFacets.DomainCategory,
    transactionIntent: ExchangeIntentFacets.TransactionIntent?,
    objectType: String?,
    semanticConcepts: [String] = [],
    rawUserText: String = "test"
) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: domainCategory,
        objectType: objectType,
        transactionIntent: transactionIntent,
        semanticConcepts: semanticConcepts,
        rawUserText: rawUserText
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: queryIntentClass,
        surfacePreference: queryIntentClass == .offerSearch ? .offer : .mixed
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: queryIntentClass,
            title: "test",
            objective: "test"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}
