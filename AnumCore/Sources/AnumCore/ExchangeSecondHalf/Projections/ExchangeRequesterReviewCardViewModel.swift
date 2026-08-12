import Foundation

/// Requester-side review card projection.
///
/// This is the cleaner requester-facing framing of an opportunity after
/// qualification and/or clarification.
public struct ExchangeRequesterReviewCardViewModel: Codable, Hashable, Sendable {
    public enum ReviewStrength: String, Codable, CaseIterable, Hashable, Sendable {
        case weak
        case promising
        case strong
        case decisionReady
    }

    public var title: String
    public var subtitle: String
    public var reviewStrength: ReviewStrength
    public var strengthReasons: [String]
    public var weaknessReasons: [String]
    public var missingFacts: [String]
    public var recommendation: String?
    public var nextMove: ExchangeNextMoveViewModel?
    public var pauseFrame: ExchangeRequesterPauseFrame?

    public init(
        title: String,
        subtitle: String,
        reviewStrength: ReviewStrength,
        strengthReasons: [String] = [],
        weaknessReasons: [String] = [],
        missingFacts: [String] = [],
        recommendation: String? = nil,
        nextMove: ExchangeNextMoveViewModel? = nil,
        pauseFrame: ExchangeRequesterPauseFrame? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.reviewStrength = reviewStrength
        self.strengthReasons = strengthReasons
        self.weaknessReasons = weaknessReasons
        self.missingFacts = missingFacts
        self.recommendation = recommendation
        self.nextMove = nextMove
        self.pauseFrame = pauseFrame
    }
}

public extension ExchangeRequesterReviewCardViewModel {
    init(
        qualification: ExchangeOpportunityQualification,
        frame: ExchangeDecisionFrame?,
        plan: ExchangeSecondHalfPlan
    ) {
        self.init(
            qualification: qualification,
            frame: frame,
            plan: plan,
            decisionNeeds: nil,
            nextMove: nil
        )
    }

    /// Pass 2 augmentation: merges buyer-facing decision readiness without replacing the qualifier/reviewer.
    init(
        qualification: ExchangeOpportunityQualification,
        frame: ExchangeDecisionFrame?,
        plan: ExchangeSecondHalfPlan,
        decisionNeeds: ExchangeRequesterDecisionNeeds?,
        nextMove: ExchangeNextMoveViewModel?,
        surfaceContext: ExchangeRequesterReviewSurfaceContext? = nil,
        pauseFrame: ExchangeRequesterPauseFrame? = nil,
        facets: ExchangeIntentFacets? = nil
    ) {
        let locationFact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        let reviewStrength: ReviewStrength
        switch qualification.qualityTier {
        case .weak:
            reviewStrength = .weak
        case .promising:
            reviewStrength = .promising
        case .strong:
            reviewStrength = .strong
        case .decisionReady:
            reviewStrength = .decisionReady
        }

        let mergedMissing = ExchangeSecondHalfLocationResolver.filterPoisonedMissingFacts(
            Self.mergedUnique(
                primary: qualification.missingFacts,
                secondary: decisionNeeds?.missingDecisionFacts,
                cap: 12
            )
        )

        let mergedStrengthLinesRaw =
            Self.mergedUnique(
                primary: qualification.strengthReasons,
                secondary: decisionNeeds?.knownDecisionFacts,
                cap: 12
            )

        var strengthInput = mergedStrengthLinesRaw.isEmpty ? qualification.strengthReasons : mergedStrengthLinesRaw
        if let uiPhrase = ExchangeSecondHalfLocationResolver.uiDisplayPhrase(for: locationFact) {
            strengthInput.insert(uiPhrase, at: 0)
        }
        let sanitizedStrengths = ExchangeRequesterReviewPresentation.sanitizedStrengthReasons(strengthInput)

        let subtitle = ExchangeRequesterReviewPresentation.reviewCardSubtitle(
            qualification: qualification,
            decisionNeeds: decisionNeeds,
            fallbackStrengthFirstLine: sanitizedStrengths.first ?? qualification.strengthReasons.first
        )

        let title = ExchangeRequesterReviewPresentation.reviewCardTitle(
            qualification: qualification,
            frame: frame,
            surface: surfaceContext
        )

        var recoParts: [String] = []

        if qualification.qualityTier == .weak {
            recoParts.append("Weak match — not enough evidence yet. Clarify or keep searching.")
        } else if !mergedMissing.isEmpty {
            recoParts.append("Possible fit, but missing details before you decide.")
        }

        if let frame {
            let trimmed = frame.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let sanitizedReco = ExchangeRequesterReviewPresentation.sanitizedRecommendationBlock(trimmed) {
                recoParts.append(sanitizedReco)
            }

            let fitFacts = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.clarifiedFacts).prefix(4)
            if !fitFacts.isEmpty {
                recoParts.append("Why this looks like a fit:\n" + fitFacts.joined(separator: "\n"))
            }

            if !frame.unresolvedIssues.isEmpty {
                let open = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.unresolvedIssues)
                    .prefix(4)
                    .joined(separator: "; ")
                if !open.isEmpty {
                    recoParts.append("Still open: \(open)")
                }
            }
        }

        if let r = decisionNeeds?.rationale,
           let sanitizedRationale = ExchangeRequesterReviewPresentation.sanitizedRecommendationBlock(r) {
            recoParts.append(sanitizedRationale)
        }

        if !mergedMissing.isEmpty {
            let miss = mergedMissing.prefix(5).joined(separator: "; ")
            recoParts.append("Missing or unclear: \(miss)")
        }

        let nmTitle = nextMove?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nmTitle.isEmpty {
            recoParts.append("Next: \(nmTitle)")
        }

        let recoJoined = recoParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let reco: String? = recoJoined.isEmpty ? nil : Self.clipped(recoJoined, maxCharacters: 900)

        let move = nextMove ?? ExchangeNextMoveViewModel(plan: plan)

        self.init(
            title: title,
            subtitle: subtitle,
            reviewStrength: reviewStrength,
            strengthReasons: sanitizedStrengths,
            weaknessReasons: ExchangeRequesterReviewPresentation.sanitizedWeaknessReasons(
                qualification.weaknessReasons
            ),
            missingFacts: mergedMissing.isEmpty ? qualification.missingFacts : mergedMissing,
            recommendation: reco,
            nextMove: move,
            pauseFrame: pauseFrame
        )
    }

    private static func mergedUnique(primary: [String], secondary: [String]?, cap: Int) -> [String] {
        guard let secondary else { return primary }

        var seen = Set<String>()
        var out: [String] = []

        for bucket in [primary, secondary] {
            for raw in bucket {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let key = trimmed.lowercased()
                guard seen.insert(key).inserted else { continue }

                out.append(trimmed)
                if out.count >= cap {
                    return out
                }
            }
        }

        return out
    }

    private static func clipped(_ value: String, maxCharacters: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }

        let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)

        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var isDecisionReady: Bool {
        reviewStrength == .decisionReady
    }

    var needsMoreQualification: Bool {
        !missingFacts.isEmpty
    }
}
