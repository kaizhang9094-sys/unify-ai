import Foundation

/// P1 deterministic mock “composer” — produces secretary-style copy from the grounded pause frame (no LLM).
/// Tests can swap implementations or use `ExchangeRequesterClosureCopyValidator` with handcrafted strings.
public struct MockExchangeRequesterClosureComposer: ExchangeRequesterClosureComposing {
    public init() {}

    public func compose(_ input: ExchangeRequesterClosureComposerInput) async throws -> ExchangeRequesterClosureComposedCopy {
        let p = input.deterministicPause
        let warm = input.styleProfile.warmthDirectness == .warm || input.styleProfile.tone == .warm
        let direct = input.styleProfile.warmthDirectness == .direct || input.styleProfile.tone == .concise

        let title: String = {
            if direct {
                return "Provider reply"
            }
            if warm {
                return "Here’s what we know"
            }
            return "Where things stand"
        }()

        var summaryParts: [String] = []
        let summaryLead = p.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if warm {
            summaryParts.append("Quick picture: \(summaryLead)")
        } else if direct {
            summaryParts.append("Facts: \(summaryLead)")
        } else {
            summaryParts.append(summaryLead)
        }

        if let reply = input.latestProviderReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            let clipped = reply.count > 280 ? String(reply.prefix(277)) + "…" : reply
            if warm {
                summaryParts.append("They said: \(clipped)")
            } else if direct {
                summaryParts.append("Latest reply: \(clipped)")
            }
        }

        if !p.commitmentSignals.isEmpty {
            summaryParts.append("Review any contract or deposit terms carefully before you agree to anything.")
        }
        if !p.providerQuestions.isEmpty {
            summaryParts.append("They’re waiting on an answer from you.")
        }
        if !p.weakeningSignals.isEmpty {
            summaryParts.append("This may not match what you asked for — worth comparing before you commit.")
        }

        let summary = summaryParts.filter { !$0.isEmpty }.joined(separator: " ")

        let answered = p.answeredFacts.isEmpty
            ? ["They shared some details in their reply."]
            : p.answeredFacts

        let stillOpen = p.stillMissingFacts

        let reco = p.recommendationLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Review the reply and decide your next step."
            : p.recommendationLine

        let nextLabel = p.nextActionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Review"
            : p.nextActionLabel

        return ExchangeRequesterClosureComposedCopy(
            title: title,
            summary: summary,
            answeredBullets: answered,
            stillOpenBullets: stillOpen,
            recommendation: reco,
            nextActionLabel: nextLabel
        )
    }
}
