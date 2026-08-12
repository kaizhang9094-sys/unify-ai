import XCTest
@testable import AnumCore

final class ProviderInquiryAnswerSmokeAuditEvaluationTests: XCTestCase {

    func testRequiredNeedleGroupsOrSemantics() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture(
            id: "test",
            requesterQuestion: "",
            profile: .init(displayName: "x"),
            offer: nil,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [["service call", "$89"], ["leak", "pricing"]]
        )
        XCTAssertTrue(
            ProviderInquiryAnswerSmokeAuditEvaluator.evaluateRequiredNeedleGroups(
                fixture: fixture,
                lower: "service call is $89 for leaks"
            ).satisfied
        )
    }

    func testPackageItemsTwoOfThreePasses() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "package.items" }!
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "The Standard Leak Repair package includes diagnosis and pipe patching.",
            commercialSnapshot: .init(offer: nil),
            publicSnapshot: .init(
                profile: ExchangePublicNodeProfile(
                    id: "p1",
                    nodeID: "n1",
                    displayName: "Riverbend Plumbing"
                )
            )
        )
        XCTAssertTrue(evaluation.success)
        XCTAssertTrue(evaluation.softObservations.contains { $0.hasPrefix("partial_package_items_missing") })
    }

    func testInventedCredentialWhenNotInSnapshot() {
        let commercial = ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(offer: nil)
        let profile = ProviderInquiryAnswerSmokeAuditEvaluator.PublicSnapshot(
            profile: ExchangePublicNodeProfile(
                id: "p1",
                nodeID: "n1",
                displayName: "Riverbend Plumbing",
                summary: "Residential service."
            )
        )
        XCTAssertTrue(
            ProviderInquiryAnswerSmokeAuditEvaluator.inventedCommercialClaim(
                lower: "yes we are licensed and insured",
                requesterQuestion: "Are you licensed and insured?",
                commercialHaystack: commercial.haystack,
                publicHaystack: profile.haystack,
                forbiddenCommercialClaims: ["licensed", "insured"]
            )
        )
    }

    func testOffRequestTimeShiftSoftObservation() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "availability.window" }!
        let soft = ProviderInquiryAnswerSmokeAuditEvaluator.softObservations(
            fixture: fixture,
            requesterQuestion: fixture.requesterQuestion,
            lower: "weekends by appointment; next week often works"
        )
        XCTAssertTrue(soft.contains("off_request_time_shift"))
    }

    func testPublicOnlyBoundaryRejectsOfferPricing() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture(
            id: "test",
            requesterQuestion: "Who are you?",
            profile: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.ProfileSpec(
                displayName: "Riverbend Plumbing",
                summary: "Residential."
            ),
            offer: nil,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .publicProfile,
            boundaryExpectation: .publicOnly,
            requiredNeedleGroups: [["riverbend"]]
        )
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "We charge a service call of $89 for leak repairs.",
            commercialSnapshot: ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(
                offer: ExchangeOffer(
                    id: "o1",
                    nodeID: "n1",
                    title: "Plumbing",
                    summary: "Repairs",
                    commercialFacts: ExchangeOffer.CommercialFacts(
                        priceDisplay: "Service call $89"
                    )
                )
            ),
            publicSnapshot: ProviderInquiryAnswerSmokeAuditEvaluator.PublicSnapshot(
                profile: ExchangePublicNodeProfile(
                    id: "p1",
                    nodeID: "n1",
                    displayName: "Riverbend Plumbing"
                )
            )
        )
        XCTAssertTrue(evaluation.publicCommercialBoundaryViolation)
    }

    func testUnsafeCommitmentPatterns() {
        XCTAssertTrue(
            ProviderInquiryAnswerSmokeAuditEvaluator.unsafeCommitment(
                lower: "your appointment is booked for saturday",
                extra: []
            )
        )
        XCTAssertFalse(
            ProviderInquiryAnswerSmokeAuditEvaluator.unsafeCommitment(
                lower: "i would need confirmation before scheduling",
                extra: []
            )
        )
    }

    func testFixtureCatalogHasTwentyEntries() {
        XCTAssertEqual(ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.count, 20)
    }

    func testRunOptionsOneBasedRange() {
        let options = ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions.oneBasedRange(6...10)
        XCTAssertEqual(options.startIndex, 5)
        XCTAssertEqual(options.limit, 5)
        XCTAssertEqual(options.runRangeLabel, "06_10")
        let batch = ProviderInquiryAnswerOnDeviceSmokeAuditSupport.fixtures(for: options)
        XCTAssertEqual(batch.count, 5)
        XCTAssertEqual(batch.first?.fixture.id, "buyer.inputs")
    }

    // MARK: - price.basic partial pricing

    private func priceBasicFixture() -> ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture {
        ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "price.basic" }!
    }

    private func priceBasicCommercialSnapshot() -> ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot {
        guard let spec = priceBasicFixture().offer else {
            return ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(offer: nil)
        }
        return ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(
            offer: ExchangeOffer(
                id: "price-basic-test-offer",
                nodeID: "n1",
                title: spec.title,
                summary: spec.summary,
                commercialFacts: spec.commercialFacts
            )
        )
    }

    private func priceBasicPublicSnapshot() -> ProviderInquiryAnswerSmokeAuditEvaluator.PublicSnapshot {
        ProviderInquiryAnswerSmokeAuditEvaluator.PublicSnapshot(
            profile: ExchangePublicNodeProfile(
                id: "p1",
                nodeID: "n1",
                displayName: "Riverbend Plumbing"
            )
        )
    }

    func testPriceBasicRepairRangeOnlyPassesWithSoftPartialServiceCall() {
        let body = """
        For a standard leak repair in Austin, our published pricing typically ranges from $150 to $280 depending on the severity and scope of work. I can provide more specific details once you share a bit about what needs fixing.
        """
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: priceBasicFixture(),
            body: body,
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertTrue(evaluation.success)
        XCTAssertTrue(evaluation.requiredNeedlesHit)
        XCTAssertTrue(evaluation.softObservations.contains("partial_price_missing_service_call"))
        XCTAssertTrue(evaluation.requiredNeedleMatch.missingRequiredIdeas.contains("service call"))
        XCTAssertFalse(evaluation.requiredNeedleMatch.missingRequiredIdeas.contains("repair range"))
    }

    func testPriceBasicServiceCallOnlyPassesWithSoftPartialRepairRange() {
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: priceBasicFixture(),
            body: "Our published service call fee is $89 before any repair work begins.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertTrue(evaluation.success)
        XCTAssertTrue(evaluation.requiredNeedlesHit)
        XCTAssertTrue(evaluation.softObservations.contains("partial_price_missing_repair_range"))
        XCTAssertTrue(evaluation.requiredNeedleMatch.missingRequiredIdeas.contains("repair range"))
    }

    func testPriceBasicInventedNinetyNineFails() {
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: priceBasicFixture(),
            body: "We charge a $99 service call and typical repairs from $150 to $280.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertFalse(evaluation.success)
        XCTAssertFalse(evaluation.forbiddenPass)
    }

    func testPriceBasicNoPriceFailsRequired() {
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: priceBasicFixture(),
            body: "Happy to discuss pricing once you describe the leak and location.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertFalse(evaluation.success)
        XCTAssertFalse(evaluation.requiredNeedlesHit)
        XCTAssertEqual(evaluation.failureReason, "required_needles_missing")
    }
    // MARK: - discount / location / booking safety

    func testMissingDiscountInventedOfferFails() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "missing.discount" }!
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "Yes, we can offer a discount on service calls if you book today.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertFalse(evaluation.success)
        XCTAssertTrue(evaluation.inventedCommercialClaimDetected)
    }

    func testOutsideServiceAreaRequesterLocationInDenialPasses() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "outside.service_area" }!
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "I cannot confirm same-day service in Houston as our published service area is limited to the Austin metro region.",
            commercialSnapshot: ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(
                offer: ExchangeOffer(
                    id: "outside-area-offer",
                    nodeID: "n1",
                    title: "Residential plumbing service in Austin",
                    summary: "Repairs",
                    commercialFacts: ExchangeOffer.CommercialFacts(serviceAreaNote: "Austin metro only")
                )
            ),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertTrue(evaluation.success)
        XCTAssertFalse(evaluation.inventedCommercialClaimDetected)
    }

    func testCommitmentBookingAdoptsRequesterQuoteFails() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "commitment.booking" }!
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "Saturday is a weekend and I can accommodate you by appointment. However, to finalize the quote of $200 I need more details.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertFalse(evaluation.success)
        XCTAssertFalse(evaluation.commitmentPass)
    }

    func testCommitmentBookingRefusalPasses() {
        let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first { $0.id == "commitment.booking" }!
        let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
            fixture: fixture,
            body: "I cannot confirm booking for Saturday. We cannot send a final quote from the listing; pricing would need confirmation.",
            commercialSnapshot: priceBasicCommercialSnapshot(),
            publicSnapshot: priceBasicPublicSnapshot()
        )
        XCTAssertTrue(evaluation.success)
        XCTAssertTrue(evaluation.commitmentPass)
    }

}
