import Foundation

/// Product-facing lines for the provider inbound "Inquiry summary" card (display-only).
public enum ExchangeProviderInboundAssessmentProjection: Sendable {

    public struct CleanResult: Sendable, Equatable {
        public var lines: [String]
        public var inputCount: Int
        public var outputCount: Int
        public var removedInternal: Int
        public var removedDuplicate: Int
        public var removedPerspectiveLeak: Int

        public init(
            lines: [String],
            inputCount: Int,
            outputCount: Int,
            removedInternal: Int,
            removedDuplicate: Int,
            removedPerspectiveLeak: Int
        ) {
            self.lines = lines
            self.inputCount = inputCount
            self.outputCount = outputCount
            self.removedInternal = removedInternal
            self.removedDuplicate = removedDuplicate
            self.removedPerspectiveLeak = removedPerspectiveLeak
        }
    }

    public static func safeAssessmentLines(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> CleanResult {
        let reception = display.providerReception
        let plain = display.plain

        var rawCandidates: [String] = []
        if let ask = reception?.requesterAsk?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty {
            rawCandidates.append(ask)
        }
        if let summary = reception?.inquirySummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            rawCandidates.append(summary)
        }
        if let missing = plain.missingInfoSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !missing.isEmpty {
            rawCandidates.append(missing)
        }
        if let next = providerCleanNextStep(from: display) {
            rawCandidates.append(next)
        }

        let inputCount = rawCandidates.count
        var removedInternal = 0
        var removedDuplicate = 0
        var removedPerspectiveLeak = 0
        var output: [String] = []

        for raw in rawCandidates {
            let normalized = normalizedProviderAssessmentLine(raw)
            guard !normalized.isEmpty else { continue }

            if isInternalProviderAssessmentLine(normalized) {
                removedInternal += 1
                continue
            }
            if isProviderPerspectiveLeakLine(normalized) {
                removedPerspectiveLeak += 1
                continue
            }

            if output.contains(where: { isRedundantProviderAssessmentLine(normalized, against: $0) }) {
                removedDuplicate += 1
                continue
            }

            output.append(normalized)
        }

        return CleanResult(
            lines: output,
            inputCount: inputCount,
            outputCount: output.count,
            removedInternal: removedInternal,
            removedDuplicate: removedDuplicate,
            removedPerspectiveLeak: removedPerspectiveLeak
        )
    }

    // MARK: - Line normalization and filters (testable)

    public static func normalizedProviderAssessmentLine(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }

        let prefixes = [
            "User inquiry:",
            "Grounding (published facts):",
            "Grounded reply (public facts):",
            "Draft grounded on published facts:",
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes {
                if line.lowercased().hasPrefix(prefix.lowercased()) {
                    line = String(line.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        return line
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isInternalProviderAssessmentLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let bannedFragments = [
            "grounded reply",
            "grounding (published facts)",
            "public facts",
            "structured facts",
            "pass 2",
            "answerable from known structured facts",
            "the inquiry is routine and answerable",
            "provider-side review in progress",
            "draft grounded on published facts",
        ]
        if bannedFragments.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.hasPrefix("grounded reply") || lower.hasPrefix("grounding (") {
            return true
        }
        return false
    }

    public static func isProviderPerspectiveLeakLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let leakPrefixes = [
            "we are open to purchasing",
            "we are looking to buy",
            "we want to buy",
            "we need to purchase",
            "we're open to purchasing",
            "we're looking to buy",
        ]
        return leakPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    public static func isRedundantProviderAssessmentLine(_ candidate: String, against existing: String) -> Bool {
        let a = normalizedProviderAssessmentLine(candidate).lowercased()
        let b = normalizedProviderAssessmentLine(existing).lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.count >= 12, b.count >= 12 {
            if a.contains(b) || b.contains(a) { return true }
        }
        return false
    }

    public static func providerCleanNextStep(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String? {
        guard display.providerReception != nil else { return nil }

        let anchor = display.providerReception?.matchedAnchor?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !anchor.isEmpty {
            return "Review the inquiry or reply using your published \(anchor) details."
        }
        return "Review the inquiry or reply using your published offer details."
    }
}
