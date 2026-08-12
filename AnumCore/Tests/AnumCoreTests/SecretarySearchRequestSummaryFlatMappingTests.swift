import Foundation
import XCTest

@testable import AnumCore

final class SecretarySearchRequestSummaryFlatMappingTests: XCTestCase {

    func testRooferAuroraTomorrowMaps() throws {
        let json = """
        {"rawNeedText":"Find me a roofer in Aurora tomorrow at 2:30.","objectText":"roofer","needText":null,"categoryHint":"homeService","transactionIntentHint":"hire","surfacePreferenceHint":"offer","placeText":"Aurora","timeText":"tomorrow at 2:30","budgetText":null,"commercialText":null,"availabilityText":"tomorrow at 2:30","modifierTexts":[],"hardTexts":["Aurora","tomorrow at 2:30"],"softTexts":[],"semanticTexts":["roofer","roofing","contractor","home service"],"broadRecallTokens":["roofer","roofing","contractor","Aurora"],"clarificationGaps":[],"confidence":0.9}
        """
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let cleaned = mapper.cleanJSON(json)
        let dto = try XCTUnwrap(mapper.decodeFlatSummaryDTO(cleaned))
        let user = "Find me a roofer in Aurora tomorrow at 2:30."
        let validated = try XCTUnwrap(mapper.validateFlatSummary(dto, userText: user))
        let seed = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
        let canonical = try XCTUnwrap(
            mapper.mapFlatSummaryToCanonicalSearchIntent(validated, sourceText: user, intent: seed)
        )
        XCTAssertEqual(canonical.objectType?.lowercased(), "roofer")
        XCTAssertEqual(canonical.places.count, 1)
        XCTAssertEqual(canonical.places.first?.normalizedText, "aurora")
        XCTAssertEqual(canonical.places.first?.isHard, true)
        XCTAssertEqual(canonical.timeConstraints.count, 1)
        XCTAssertTrue(canonical.timeConstraints.first?.text.contains("tomorrow") == true)
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testHouseHelpLowObjectClarificationPath() throws {
        let json = """
        {"rawNeedText":"Can someone help with my house?","objectText":null,"needText":"help with my house","categoryHint":null,"transactionIntentHint":"find","surfacePreferenceHint":null,"placeText":null,"timeText":null,"budgetText":null,"commercialText":null,"availabilityText":null,"modifierTexts":[],"hardTexts":[],"softTexts":[],"semanticTexts":[],"broadRecallTokens":[],"clarificationGaps":["What kind of help?","Location"],"confidence":0.4}
        """
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let cleaned = mapper.cleanJSON(json)
        let dto = try XCTUnwrap(mapper.decodeFlatSummaryDTO(cleaned))
        let user = "Can someone help with my house?"
        let validated = try XCTUnwrap(mapper.validateFlatSummary(dto, userText: user))
        let seed = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
        let canonical = try XCTUnwrap(
            mapper.mapFlatSummaryToCanonicalSearchIntent(validated, sourceText: user, intent: seed)
        )
        XCTAssertNil(canonical.objectType)
        XCTAssertFalse(canonical.semanticConcepts.isEmpty)
        XCTAssertFalse(canonical.clarificationGaps.isEmpty)
        XCTAssertLessThanOrEqual(canonical.extractionConfidence ?? 1.0, 0.55)
    }

    func testPhotographerMarkhamWeekend() throws {
        let json = """
        {"rawNeedText":"Find a cheap experienced photographer near Markham this weekend.","objectText":"photographer","needText":null,"categoryHint":"professionalService","transactionIntentHint":"hire","surfacePreferenceHint":"offer","placeText":"Markham","timeText":"this weekend","budgetText":"cheap","commercialText":null,"availabilityText":"this weekend","modifierTexts":["cheap","experienced","near"],"hardTexts":["Markham","this weekend"],"softTexts":[],"semanticTexts":["photographer","photography"],"broadRecallTokens":["photographer","Markham"],"clarificationGaps":[],"confidence":0.85}
        """
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let cleaned = mapper.cleanJSON(json)
        let dto = try XCTUnwrap(mapper.decodeFlatSummaryDTO(cleaned))
        let user = "Find a cheap experienced photographer near Markham this weekend."
        let validated = try XCTUnwrap(mapper.validateFlatSummary(dto, userText: user))
        let seed = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
        let canonical = try XCTUnwrap(
            mapper.mapFlatSummaryToCanonicalSearchIntent(validated, sourceText: user, intent: seed)
        )
        XCTAssertEqual(canonical.objectType?.lowercased(), "photographer")
        XCTAssertEqual(canonical.places.first?.normalizedText, "markham")
        XCTAssertTrue(canonical.timeConstraints.contains { $0.text.contains("weekend") })
        XCTAssertTrue(canonical.preferences.contains { $0.key == "modifier" })
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    // MARK: - Compact flat-summary enrichment (social, budget, shipping)

    func testCompactPipelineEnglishTennisPartnerNullObjectSoftActivity() throws {
        let json = """
        {"raw":"Find people nearby who want a tennis partner for weekday evenings.","object":null,"need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["tennis partner"],"gaps":[],"confidence":0.84}
        """
        let user = "Find people nearby who want a tennis partner for weekday evenings."
        let seed = seedIntent(user)
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: mapper.cleanJSON(json),
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.objectType?.lowercased(), "tennis partner")
        XCTAssertEqual(canonical.places.first?.normalizedText, "nearby")
        XCTAssertTrue(canonical.timeConstraints.contains { $0.text.contains("weekday") })
        XCTAssertEqual(canonical.extractedSurfacePreference, .affinity)
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testCompactPipelineChineseTennisPartnerNullObjectSoftActivity() throws {
        let json = """
        {"raw":"想找附近晚上一起打网球的人。","object":null,"need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["一起打网球"],"gaps":[],"confidence":0.84}
        """
        let user = "想找附近晚上一起打网球的人。"
        let seed = seedIntent(user)
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: mapper.cleanJSON(json),
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.objectType, "一起打网球的人")
        XCTAssertEqual(canonical.places.first?.normalizedText, "附近")
        XCTAssertTrue(canonical.timeConstraints.contains { $0.text.contains("晚上") })
        XCTAssertEqual(canonical.extractedSurfacePreference, .affinity)
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testCompactPipelineChineseLawyerNumericBudget() throws {
        let json = """
        {"raw":"在迈阿密找一位双语家庭法律师，周五前要完成首次咨询，每小时费用不超过五百美元。","object":"lawyer","need":"首次咨询","place":"Miami","time":"Friday before today","budget":500,"commercial":null,"mods":["双语"],"hard":["Miami"],"soft":[],"gaps":[],"confidence":0.89}
        """
        let user = "在迈阿密找一位双语家庭法律师，周五前要完成首次咨询，每小时费用不超过五百美元。"
        let seed = seedIntent(user)
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: mapper.cleanJSON(json),
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.places.first?.normalizedText, "miami")
        XCTAssertTrue(
            canonical.commercialConstraints.contains { $0.kind == .budget && $0.value == "500" }
        )
        XCTAssertTrue(
            canonical.semanticConcepts.contains { $0.contains("首次咨询") }
        )
        XCTAssertTrue(
            canonical.broadRecallTokens.contains { $0.contains("首次咨询") }
        )
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testNeedTextWithObjectMapsToSemanticAndBroadRecall() throws {
        let json = """
        {"rawNeedText":"Find me a plumber in Austin for leak repair this Saturday afternoon.","objectText":"plumber","needText":"leak repair","categoryHint":"homeService","transactionIntentHint":"hire","surfacePreferenceHint":"offer","placeText":"Austin","timeText":"this Saturday afternoon","budgetText":null,"commercialText":null,"availabilityText":"this Saturday afternoon","modifierTexts":[],"hardTexts":["Austin"],"softTexts":[],"semanticTexts":["plumber"],"broadRecallTokens":["Austin"],"clarificationGaps":[],"confidence":0.88}
        """
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let cleaned = mapper.cleanJSON(json)
        let dto = try XCTUnwrap(mapper.decodeFlatSummaryDTO(cleaned))
        let user = "Find me a plumber in Austin for leak repair this Saturday afternoon."
        let validated = try XCTUnwrap(mapper.validateFlatSummary(dto, userText: user))
        let seed = seedIntent(user)
        let canonical = try XCTUnwrap(
            mapper.mapFlatSummaryToCanonicalSearchIntent(validated, sourceText: user, intent: seed)
        )
        XCTAssertEqual(canonical.objectType?.lowercased(), "plumber")
        XCTAssertTrue(
            canonical.semanticConcepts.contains { $0.lowercased().contains("leak") }
        )
        XCTAssertTrue(
            canonical.broadRecallTokens.contains { $0.lowercased().contains("leak") }
        )
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testCompactPipelineEnglishShippedToCanadaPreservesDestination() throws {
        let json = """
        {"raw":"Looking for a used MacBook Pro under 1200 dollars shipped to Canada.","object":"MacBook Pro","need":null,"place":null,"time":null,"budget":"1200 dollars","commercial":"shipped","mods":["used"],"hard":["Canada"],"soft":[],"gaps":[],"confidence":0.88}
        """
        let user = "Looking for a used MacBook Pro under 1200 dollars shipped to Canada."
        let seed = seedIntent(user)
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: mapper.cleanJSON(json),
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.places.first?.normalizedText, "canada")
        XCTAssertTrue(
            canonical.commercialConstraints.contains { $0.value.lowercased().contains("1200") }
        )
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    func testCompactPipelineChineseMacBookShipToShanghai() throws {
        let json = """
        {"raw":"二手 MacBook Pro 八千以内邮寄上海","object":"MacBook Pro","need":null,"place":null,"time":null,"budget":"8000 CNY","commercial":"邮寄","mods":["二手","邮寄"],"hard":["上海"],"soft":[],"gaps":[],"confidence":0.82}
        """
        let user = "二手 MacBook Pro 八千以内邮寄上海"
        let seed = seedIntent(user)
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: mapper.cleanJSON(json),
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.places.first?.normalizedText, "上海")
        XCTAssertTrue(mapper.isMateriallyActionable(canonical))
    }

    private func seedIntent(_ user: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
    }
}
