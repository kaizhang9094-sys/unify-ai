import Foundation

/// Deterministic Pass 2 draft overlay (no LLM). Augments coordinator drafts only.
public enum ExchangeSecondHalfPass2DraftAugment: Sendable {

    public static func merge(
        base: ExchangeDraftComposer.Draft?,
        assessment: ExchangeAgencyAssessment?,
        role: ExchangeSecondHalfRole
    ) -> ExchangeDraftComposer.Draft? {
        guard let assessment else { return base }

        switch role {
        case .requester:
            // Review/agency diagnostic questions stay in `requesterDecisionNeeds` for UI.
            // They must not be appended to federation-bound draft bodies.
            guard let requests = assessment.requesterDecisionNeeds,
                  !requests.recommendedQuestions.isEmpty else { return base }

            let reviewCount = min(requests.recommendedQuestions.count, 3)
            if var merged = base {
                merged.notes.append(
                    "Pass 2 agency: retained \(reviewCount) review question(s) in agency assessment (not appended to sendable body)."
                )
                return merged
            }
            return base

        case .provider:
            if let b = base {
                var merged = augmentProviderFacts(on: b, assessment: assessment)

                if let ans = assessment.providerAnswerability {
                    if let pa = ans.proposedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pa.isEmpty {
                        if ans.usesCompareFirstGroundedFinalBody {
                            merged.body = pa
                        } else if !merged.body.isEmpty {
                            merged.body =
                                """
                                Draft grounded on published facts:\n\(pa)



                                ---
                                \(merged.body)
                                """
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            merged.body =
                                pa.trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        let factLines = providerGroundedFactLines(ans)
                        merged.usedStructuredFacts = dedupeFacts(merged.usedStructuredFacts + factLines)

                        merged.notes.append(
                            ans.answerability == .requiresProviderApproval
                                ? """
                                Pass 2 agency: prefixed proposed public-fact wording; seller review required before sending.
                                """
                                : """
                                Pass 2 agency: prefixed deterministic public-fact wording.
                                """
                        )
                    } else if !providerGroundedFactLines(ans).isEmpty {
                        merged.notes.append("Pass 2 agency: surfaced facts-used overlay.")
                    }
                }

                merged = augmentProviderFacts(on: merged, assessment: assessment)
                if assessment.providerAnswerability?.usesCompareFirstGroundedFinalBody == true {
                    merged.agencyComposePolicy = .skipFullComposeCompareFirstGrounded
                }
                return merged
            }

            if let ans = assessment.providerAnswerability {
                let pa = ans.proposedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !pa.isEmpty {
                    return ExchangeDraftComposer.Draft(
                        body: pa,
                        usedStructuredFacts: providerGroundedFactLines(ans),
                        notes: [
                            "Pass 2 agency: display-only draft from public facts overlay (deterministic)."
                        ],
                        agencyComposePolicy: ans.usesCompareFirstGroundedFinalBody
                            ? .skipFullComposeCompareFirstGrounded
                            : nil
                    )
                }
            }

            return base
        }
    }

    private static func augmentProviderFacts(
        on draft: ExchangeDraftComposer.Draft,
        assessment: ExchangeAgencyAssessment
    ) -> ExchangeDraftComposer.Draft {
        let lines = normalizeFactLines(assessment.groundedFactLines)

        guard !lines.isEmpty else { return draft }

        var merged = draft
        merged.usedStructuredFacts = dedupeFacts(merged.usedStructuredFacts + lines)
        merged.notes.append("Pass 2 agency: merged grounded fact lines (\(lines.count)).")
        return merged
    }

    private static func normalizeFactLines(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func dedupeFacts(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            out.append(trimmed)

            if out.count >= 12 {
                break
            }
        }

        return out
    }

    private static func providerGroundedFactLines(
        _ answerability: ExchangeProviderAnswerability
    ) -> [String] {
        let grounded = normalizeFactLines(answerability.groundedFacts.map(\.text))
        if !grounded.isEmpty {
            return grounded
        }
        // Backward compatibility for older snapshots without grounded provenance.
        return normalizeFactLines(answerability.knownFactsUsed)
    }
}
