import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeUmbrellaDiscoveryGradeProjection")
struct ExchangeUmbrellaDiscoveryGradeProjectionTests {

    @Test("found strong metadata projects strong while internal state remains weak")
    func foundStrongMetadataProjectsStrongWhileInternalWeak() {
        var thread = makeUmbrellaThread(state: .matchCandidatesWeak(
            .init(
                candidateCount: 3,
                explanation: "Found paths",
                suggestedRefinement: "Review"
            )
        ))
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
            thread: thread,
            context: .init(activatedChildCount: 2, strongestChildSourceRank: 1, strongestChildProofValid: true)
        )

        #expect(resolution.projectedGrade == .strong)
        #expect(resolution.internalStateKey == "matchCandidatesWeak")
        #expect(resolution.gradeReason == "strong_classify_preserved")
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) == "Found strong matches")
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.visibleStatusLabel(for: resolution) == "Matches found")
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.executionBadgeTitle(for: resolution) == "Matches Found")
        let label = ExchangeUmbrellaDiscoveryGradeProjection.visibleStatusLabel(for: resolution) ?? ""
        #expect(!label.localizedCaseInsensitiveContains("Weak Matches"))
        #expect(!label.localizedCaseInsensitiveContains("Weak Paths"))
    }

    @Test("found moderate metadata projects moderate review copy")
    func foundModerateMetadataProjectsModerateReviewCopy() {
        var thread = makeUmbrellaThread(state: .matchCandidatesWeak(
            .init(
                candidateCount: 2,
                explanation: "Found paths",
                suggestedRefinement: "Review"
            )
        ))
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .moderateReviewNeeded,
            activatedChildCount: 1,
            to: &thread.metadata
        )

        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
            thread: thread,
            context: .init(activatedChildCount: 1, strongestChildSourceRank: 1, strongestChildProofValid: true)
        )

        #expect(resolution.projectedGrade == .moderate)
        #expect(resolution.gradeReason == "moderate_review_needed_preserved")
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) == "Review matches")
        let title = ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) ?? ""
        #expect(!title.localizedCaseInsensitiveContains("No match"))
        #expect(!title.localizedCaseInsensitiveContains("Weak"))
    }

    @Test("weak metadata keeps weak projection")
    func weakMetadataKeepsWeakProjection() {
        var thread = makeUmbrellaThread(state: .matchCandidatesWeak(
            .init(
                candidateCount: 2,
                explanation: "Weak paths",
                suggestedRefinement: "Refine"
            )
        ))
        ExchangeThreadDiscoveryGradeMetadata.applyWeakGrade(to: &thread.metadata)

        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(thread: thread)

        #expect(resolution.projectedGrade == .weak)
        #expect(resolution.gradeReason == "weak_classify")
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) == nil)
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.shouldUseWeakPresentation(thread: thread))
    }

    @Test("missing grade metadata falls back to internal weak state")
    func missingGradeMetadataFallsBackToInternalWeakState() {
        let thread = makeUmbrellaThread(state: .matchCandidatesWeak(
            .init(
                candidateCount: 1,
                explanation: "Weak paths",
                suggestedRefinement: nil
            )
        ))

        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(thread: thread)

        #expect(resolution.projectedGrade == .weak)
        #expect(resolution.usesMetadata == false)
        #expect(resolution.gradeReason == "internal_state_weak_fallback")
    }

    @Test("should not use weak presentation when projected grade is strong")
    func shouldNotUseWeakPresentationWhenProjectedStrong() {
        var thread = makeUmbrellaThread(state: .matchCandidatesWeak(
            .init(
                candidateCount: 2,
                explanation: "Found paths",
                suggestedRefinement: "Review"
            )
        ))
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        #expect(!ExchangeUmbrellaDiscoveryGradeProjection.shouldUseWeakPresentation(thread: thread))
    }
}

private func makeUmbrellaThread(state: ExchangeState) -> ExchangeThread {
    var thread = ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "find laptop",
            objective: "repair laptop"
        ),
        posture: ExchangePosture(),
        facets: ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            capabilityTerms: ["laptop"]
        ),
        state: state
    )
    ExchangeThreadRoleResolver.applyUmbrellaSearchRole(rootThreadID: thread.id, to: &thread.metadata)
    return thread
}
