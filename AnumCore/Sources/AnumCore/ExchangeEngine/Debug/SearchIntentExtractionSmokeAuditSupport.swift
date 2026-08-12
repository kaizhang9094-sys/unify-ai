#if DEBUG
import Foundation

/// Fixed prompts for on-device `searchIntentExtraction` smoke audits (EN / ZH / mixed).
public enum SearchIntentExtractionSmokeAuditPrompts {
    public struct Prompt: Sendable, Hashable {
        public var id: String
        public var language: String
        public var inputTextExact: String

        public init(id: String, language: String, inputTextExact: String) {
            self.id = id
            self.language = language
            self.inputTextExact = inputTextExact
        }
    }

    public static let all: [Prompt] = [
        Prompt(id: "en.local_service.1", language: "en", inputTextExact: "Find me a plumber in Austin for a leak repair this Saturday afternoon."),
        Prompt(id: "en.time_sensitive.1", language: "en", inputTextExact: "Need an emergency locksmith in Seattle tonight before 10pm."),
        Prompt(id: "en.commercial_offer.1", language: "en", inputTextExact: "Looking for a used MacBook Pro under 1200 dollars shipped to Canada."),
        Prompt(id: "en.social_person.1", language: "en", inputTextExact: "Find people nearby who want a tennis partner for weekday evenings."),
        Prompt(id: "en.budget_price.1", language: "en", inputTextExact: "Wedding photographer under 3000 dollars near Chicago next spring."),
        Prompt(id: "en.remote_online.1", language: "en", inputTextExact: "Remote Spanish tutor for conversational practice on weekday mornings EST."),
        Prompt(id: "en.multi_constraint.1", language: "en", inputTextExact: "Find a bilingual family law lawyer in Miami for a first consultation before Friday with budget under 500 dollars per hour."),
        Prompt(id: "en.roofer_replay.1", language: "en", inputTextExact: "Find me a roofer in Aurora tomorrow at 2:30pm."),
        Prompt(id: "zh.local_service.1", language: "zh", inputTextExact: "我需要在周六下午在奥斯汀找一位水管工修理漏水。"),
        Prompt(id: "zh.time_sensitive.1", language: "zh", inputTextExact: "今晚十点前需要在西雅图市中心找紧急开锁师傅。"),
        Prompt(id: "zh.commercial_offer.1", language: "zh", inputTextExact: "我想买一台二手 MacBook Pro，预算八千人民币以内，可以邮寄到上海。"),
        Prompt(id: "zh.social_person.1", language: "zh", inputTextExact: "想找附近晚上一起打网球的人。"),
        Prompt(id: "zh.budget_price.1", language: "zh", inputTextExact: "明年春天在芝加哥附近找婚礼摄影师，预算不超过三千美元。"),
        Prompt(id: "zh.remote_online.1", language: "zh", inputTextExact: "需要远程的西班牙语口语陪练老师，工作日早上（美国东部时间）。"),
        Prompt(id: "zh.multi_constraint.1", language: "zh", inputTextExact: "在迈阿密找一位双语家庭法律师，周五前要完成首次咨询，每小时费用不超过五百美元。"),
        Prompt(id: "zh.macbook_replay.1", language: "zh", inputTextExact: "二手 MacBook Pro 八千以内邮寄上海"),
        Prompt(id: "mx.electrician.1", language: "mixed", inputTextExact: "上海 Pudong 周末 need a certified electrician 上门检查电路。"),
        Prompt(id: "mx.ui_designer.1", language: "mixed", inputTextExact: "Remote UI designer needed, 远程工作，预算 budget 5000 RMB 以内。"),
        Prompt(id: "mx.hiking_bilingual.1", language: "mixed", inputTextExact: "Help me 在湾区 find a beginner weekend hiking group 一起徒步。"),
        Prompt(id: "mx.contractor_beijing.1", language: "mixed", inputTextExact: "Need 装修 contractor in 北京 Chaoyang this 下周 for kitchen remodel.")
    ]
}

public struct SearchIntentExtractionSmokeAuditRow: Codable, Sendable, Hashable {
    public var promptId: String
    public var language: String
    public var inputTextExact: String
    public var promptSentToLLMExact: String?
    public var rawLLMOutputExact: String?
    public var parsedCanonicalSearchIntentFull: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    public var extractionSource: String?
    public var parseRepairStatus: String
    public var elapsedMs: Int?
    public var success: Bool
    public var failureReason: String?
    public var notes: String?

    public init(
        promptId: String,
        language: String,
        inputTextExact: String,
        promptSentToLLMExact: String?,
        rawLLMOutputExact: String?,
        parsedCanonicalSearchIntentFull: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        extractionSource: String?,
        parseRepairStatus: String,
        elapsedMs: Int?,
        success: Bool,
        failureReason: String?,
        notes: String? = nil
    ) {
        self.promptId = promptId
        self.language = language
        self.inputTextExact = inputTextExact
        self.promptSentToLLMExact = promptSentToLLMExact
        self.rawLLMOutputExact = rawLLMOutputExact
        self.parsedCanonicalSearchIntentFull = parsedCanonicalSearchIntentFull
        self.extractionSource = extractionSource
        self.parseRepairStatus = parseRepairStatus
        self.elapsedMs = elapsedMs
        self.success = success
        self.failureReason = failureReason
        self.notes = notes
    }
}

public enum SearchIntentExtractionSmokeAuditSupport {
    public static func run(
        extractor: any AsyncOpenEndedSearchIntentExtractor,
        pauseBetweenPromptsNanoseconds: UInt64 = 600_000_000
    ) async -> [SearchIntentExtractionSmokeAuditRow] {
        var rows: [SearchIntentExtractionSmokeAuditRow] = []
        rows.reserveCapacity(SearchIntentExtractionSmokeAuditPrompts.all.count)

        for (index, prompt) in SearchIntentExtractionSmokeAuditPrompts.all.enumerated() {
            await SearchIntentExtractionDebugTrace.shared.reset()

            let seed = seedIntent(for: prompt.inputTextExact)
            let builtPrompt = ExchangeOpenEndedSearchIntentPromptBuilder.buildPrompt(
                sourceText: prompt.inputTextExact,
                intent: seed
            )
            await SearchIntentExtractionDebugTrace.shared.recordPrompt(builtPrompt)

            let wall = CFAbsoluteTimeGetCurrent()
            let canonical = await extractor.extract(
                sourceText: prompt.inputTextExact,
                intent: seed
            )
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)
            let diagnostics = await extractor.lastExtractionDiagnostics()
            let trace = await SearchIntentExtractionDebugTrace.shared.currentSnapshot()

            let extractionSource = canonical?.extractionSource?.rawValue
                ?? diagnostics?.source.rawValue
            let parseRepairStatus = parseRepairStatusLabel(
                diagnostics: diagnostics,
                extractionSource: extractionSource
            )
            let llmSources: Set<String> = [
                SearchIntentExtractionSource.llmFlatSummary.rawValue,
                SearchIntentExtractionSource.llm.rawValue,
                SearchIntentExtractionSource.llmRepairedJSON.rawValue
            ]
            let success = canonical != nil
                && extractionSource.map { llmSources.contains($0) } == true
            let failureReason: String?
            if success {
                failureReason = nil
            } else if let reason = diagnostics?.fallbackReason?.rawValue {
                failureReason = reason
            } else if canonical == nil {
                failureReason = "nilCanonical"
            } else {
                failureReason = "nonLLMSource:\(extractionSource ?? "nil")"
            }

            let row = SearchIntentExtractionSmokeAuditRow(
                promptId: prompt.id,
                language: prompt.language,
                inputTextExact: prompt.inputTextExact,
                promptSentToLLMExact: trace.promptSentToLLMExact ?? builtPrompt,
                rawLLMOutputExact: trace.rawLLMOutputExact,
                parsedCanonicalSearchIntentFull: canonical,
                extractionSource: extractionSource,
                parseRepairStatus: parseRepairStatus,
                elapsedMs: diagnostics?.elapsedMs ?? elapsedMs,
                success: success,
                failureReason: failureReason,
                notes: diagnostics?.decodeErrorSummary
            )
            rows.append(row)

            printSmokeAuditRow(row, index: index + 1, total: SearchIntentExtractionSmokeAuditPrompts.all.count)

            if index < SearchIntentExtractionSmokeAuditPrompts.all.count - 1,
               pauseBetweenPromptsNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pauseBetweenPromptsNanoseconds)
            }
        }

        return rows
    }

    public static func writeJSONL(rows: [SearchIntentExtractionSmokeAuditRow], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for (idx, row) in rows.enumerated() {
            data.append(try encoder.encode(row))
            if idx < rows.count - 1 { data.append(Data("\n".utf8)) }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    private static func seedIntent(for text: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "smoke-audit-seed",
            objective: text
        )
    }

    private static func parseRepairStatusLabel(
        diagnostics: SearchIntentExtractionDiagnostics?,
        extractionSource: String?
    ) -> String {
        var parts: [String] = []
        if let extractionSource { parts.append("source=\(extractionSource)") }
        if let diagnostics {
            parts.append("attemptedLLM=\(diagnostics.attemptedLLM)")
            if diagnostics.repairAttempted { parts.append("repairAttempted=true") }
            if let summary = diagnostics.compactCanonicalSummary, !summary.isEmpty {
                parts.append("compact=\(summary)")
            }
            if let decode = diagnostics.decodeErrorSummary, !decode.isEmpty {
                parts.append("decode=\(decode)")
            }
            if let reason = diagnostics.fallbackReason?.rawValue {
                parts.append("fallback=\(reason)")
            }
        }
        return parts.isEmpty ? "unknown" : parts.joined(separator: " | ")
    }

    private static func printSmokeAuditRow(
        _ row: SearchIntentExtractionSmokeAuditRow,
        index: Int,
        total: Int
    ) {
        let rawPreview = row.rawLLMOutputExact.map { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count <= 160 ? trimmed : String(trimmed.prefix(160)) + "…"
        } ?? "null"
        let object = row.parsedCanonicalSearchIntentFull?.objectType ?? "nil"
        print(
            "[SearchIntentSmokeAudit] \(index)/\(total) id=\(row.promptId) lang=\(row.language) " +
            "success=\(row.success) source=\(row.extractionSource ?? "nil") elapsedMs=\(row.elapsedMs ?? -1) " +
            "parseRepair=\(row.parseRepairStatus) failure=\(row.failureReason ?? "nil") object=\(object)"
        )
        print("[SearchIntentSmokeAudit] input=\(row.inputTextExact)")
        print("[SearchIntentSmokeAudit] raw=\(rawPreview)")
    }
}
#endif
