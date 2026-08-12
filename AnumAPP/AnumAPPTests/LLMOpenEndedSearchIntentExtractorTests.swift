import XCTest
@testable import AnumCore

final class LLMOpenEndedSearchIntentExtractorTests: XCTestCase {
    func test_vtbExtraction_preservesCommercialPhrase_andSoftByDefault() throws {
        let raw = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "home",
            domainHint: "real estate",
            transactionIntentHint: "for sale",
            places: [.init(text: "GTA", aliases: ["Greater Toronto Area"], confidence: 0.93, isHard: false)],
            attributes: [.init(key: "bedrooms", value: "3 bedroom", numericValue: 3)],
            commercialConstraints: [
                .init(kind: "financing", key: "sellerFinancing", value: "vendor take-back mortgage", isHard: false)
            ],
            semanticConcepts: ["seller financing", "vendor take-back mortgage"],
            broadRecallTokens: ["home", "gta"],
            confidence: 0.92
        )
        let extracted = try XCTUnwrap(extract(with: dto, raw: raw))

        XCTAssertEqual(extracted.objectType, "home")
        XCTAssertEqual(extracted.domainCategory, .realEstate)
        XCTAssertEqual(extracted.transactionIntent, .forSale)
        XCTAssertTrue(extracted.places.contains { $0.normalizedText == "gta" })
        XCTAssertTrue(extracted.attributes.contains { $0.key == "bedrooms" && $0.numericValue == 3 })
        let fin = try XCTUnwrap(extracted.commercialConstraints.first)
        XCTAssertTrue(fin.value.lowercased().contains("vendor take-back"))
        XCTAssertFalse(fin.isHard)
        XCTAssertTrue(isMateriallyActionable(extracted))
        XCTAssertFalse(hasFusedAtomicLeak(extracted, raw: raw))
    }

    func test_unknownOpenEndedCondition_preservesUnusualPhrases() throws {
        let raw = "Find a contractor who works with first-time developers and accepts small renovation budgets."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "contractor",
            softPreferences: ["accepts small renovation budgets"],
            semanticConcepts: ["works with first-time developers"],
            broadRecallTokens: ["contractor"],
            confidence: 0.88
        )
        let extracted = try XCTUnwrap(extract(with: dto, raw: raw))

        XCTAssertTrue(extracted.semanticConcepts.contains { $0.lowercased().contains("first-time developers") })
        XCTAssertTrue(extracted.softPreferences.contains { $0.value.lowercased().contains("small renovation budgets") })
    }

    func test_datingDogs_preservesSocialConditions_withoutBusinessForceFit() throws {
        let raw = "Find me a single woman looking to date who likes dogs."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "single woman",
            domainHint: "relationship",
            semanticConcepts: ["dating", "likes dogs"],
            broadRecallTokens: ["single woman", "dating"],
            confidence: 0.74
        )
        let extracted = try XCTUnwrap(extract(with: dto, raw: raw))

        XCTAssertEqual(extracted.domainCategory, .general)
        XCTAssertTrue(extracted.semanticConcepts.contains { $0.lowercased().contains("likes dogs") })
        XCTAssertTrue(extracted.semanticConcepts.contains { $0.lowercased().contains("dating") })
    }

    func test_skiBuddy_preservesPurposeDestinationAndTime() throws {
        let raw = "Find me a ski buddy who has time next Saturday to Mount St. Louis."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "ski buddy",
            places: [.init(text: "Mount St. Louis", aliases: nil, confidence: 0.85, isHard: false)],
            timeConstraints: [.init(kind: "day", text: "next Saturday", isHard: false)],
            semanticConcepts: ["ski buddy"],
            broadRecallTokens: ["ski", "buddy", "mount st. louis"],
            confidence: 0.80
        )
        let extracted = try XCTUnwrap(extract(with: dto, raw: raw))

        XCTAssertTrue(extracted.semanticConcepts.contains { $0.lowercased().contains("ski buddy") })
        XCTAssertTrue(extracted.places.contains { $0.normalizedText.contains("mount st") })
        XCTAssertTrue(extracted.timeConstraints.contains { $0.text.contains("next saturday") })
    }

    func test_invalidJSON_fallsBackToHeuristic() throws {
        let raw = "Looking for a house in GTA with seller financing."
        let extracted = try XCTUnwrap(
            LLMOpenEndedSearchIntentExtractor(
                jsonProvider: FakeJSONProvider(rawJSON: "not-json")
            ).extract(sourceText: raw, intent: fixtureIntent(raw))
        )

        XCTAssertEqual(extracted.objectType, "house")
        XCTAssertTrue(extracted.places.contains { $0.normalizedText == "gta" })
    }

    func test_busyError_fallsBackToHeuristic_withoutHang() throws {
        let raw = "Looking for a house in GTA with seller financing."
        let extracted = try XCTUnwrap(
            LLMOpenEndedSearchIntentExtractor(
                jsonProvider: ThrowingJSONProvider()
            ).extract(sourceText: raw, intent: fixtureIntent(raw))
        )

        XCTAssertEqual(extracted.objectType, "house")
        XCTAssertTrue(extracted.commercialConstraints.contains { $0.kind == .financing })
    }

    func test_emptyUnclearQuery_notMateriallyActionable() {
        let raw = "help me find something"
        let dto = LLMSearchIntentExtractionDTO(confidence: 0.45)
        let extracted = extract(with: dto, raw: raw)
        XCTAssertTrue(
            extracted == nil || !isMateriallyActionable(extracted!),
            "Unclear query should remain nil or non-actionable"
        )
    }

    func test_hardVsSoftFinancingMapping() throws {
        let hardRaw = "must have seller financing"
        let hardDTO = LLMSearchIntentExtractionDTO(
            objectType: "house",
            commercialConstraints: [.init(kind: "financing", key: "sellerFinancing", value: "seller financing", isHard: nil)],
            semanticConcepts: ["seller financing"],
            broadRecallTokens: ["house"],
            confidence: 0.90
        )
        let hard = try XCTUnwrap(extract(with: hardDTO, raw: hardRaw))
        XCTAssertTrue(hard.commercialConstraints.contains { $0.kind == .financing && $0.isHard })

        let softRaw = "with seller financing"
        let softDTO = LLMSearchIntentExtractionDTO(
            objectType: "house",
            commercialConstraints: [.init(kind: "financing", key: "sellerFinancing", value: "seller financing", isHard: nil)],
            semanticConcepts: ["seller financing"],
            broadRecallTokens: ["house"],
            confidence: 0.90
        )
        let soft = try XCTUnwrap(extract(with: softDTO, raw: softRaw))
        XCTAssertTrue(soft.commercialConstraints.contains { $0.kind == .financing && !$0.isHard })
    }

    func test_conservativeMapping_keepsGeneral_whenLowConfidenceHint() throws {
        let raw = "Find me a ski buddy"
        let lowDTO = LLMSearchIntentExtractionDTO(
            domainHint: "activity partner",
            semanticConcepts: ["ski buddy", "activity partner"],
            broadRecallTokens: ["ski buddy"],
            confidence: 0.60
        )
        let low = try XCTUnwrap(extract(with: lowDTO, raw: raw))
        XCTAssertEqual(low.domainCategory, .general)
        XCTAssertTrue(low.semanticConcepts.contains { $0.lowercased().contains("ski buddy") })

        let highDTO = LLMSearchIntentExtractionDTO(
            objectType: "house",
            domainHint: "real estate",
            transactionIntentHint: "for sale",
            semanticConcepts: ["home search"],
            broadRecallTokens: ["house"],
            confidence: 0.90
        )
        let high = try XCTUnwrap(extract(with: highDTO, raw: "house for sale"))
        XCTAssertEqual(high.domainCategory, ExchangeIntentFacets.DomainCategory.realEstate)
        XCTAssertEqual(high.transactionIntent, ExchangeIntentFacets.TransactionIntent.forSale)
    }
}

private extension LLMOpenEndedSearchIntentExtractorTests {
    struct FakeJSONProvider: LLMOpenEndedSearchIntentExtractor.JSONProvider {
        let rawJSON: String
        func extractSearchIntentJSON(
            prompt: String,
            sourceText: String,
            intent: ExchangeIntent
        ) throws -> String {
            rawJSON
        }
    }

    struct ThrowingJSONProvider: LLMOpenEndedSearchIntentExtractor.JSONProvider {
        enum BusyError: Error { case busy }
        func extractSearchIntentJSON(
            prompt: String,
            sourceText: String,
            intent: ExchangeIntent
        ) throws -> String {
            throw BusyError.busy
        }
    }

    func extract(with dto: LLMSearchIntentExtractionDTO, raw: String) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(dto),
              let rawJSON = String(data: data, encoding: .utf8)
        else { return nil }
        return LLMOpenEndedSearchIntentExtractor(
            jsonProvider: FakeJSONProvider(rawJSON: rawJSON)
        ).extract(sourceText: raw, intent: fixtureIntent(raw))
    }

    func fixtureIntent(_ raw: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "fixture",
            objective: raw
        )
    }

    func hasFusedAtomicLeak(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        raw: String
    ) -> Bool {
        let fields = (
            si.semanticConcepts +
            si.broadRecallTokens +
            si.commercialConstraints.map(\.value) +
            si.attributes.map(\.value)
        ).map { $0.lowercased() }
        let rawLower = raw.lowercased()
        return fields.contains { $0 == rawLower || $0.contains(", and ") }
    }

    func isMateriallyActionable(_ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> Bool {
        let hasTarget =
            !(si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            si.domainCategory != .general ||
            !si.semanticConcepts.isEmpty
        let hasAnchor =
            !si.places.isEmpty ||
            !si.commercialConstraints.isEmpty ||
            !si.attributes.isEmpty ||
            !si.preferences.isEmpty ||
            !si.timeConstraints.isEmpty ||
            !si.broadRecallTokens.isEmpty ||
            !si.softPreferences.isEmpty
        return hasTarget && hasAnchor
    }
}
