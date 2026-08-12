import Foundation

/// A stateful coordination object.
///
/// Threads are not generic chats. A thread exists to move a user's intent
/// through interpretation, discovery, approval, coordination, and outcome.
///
/// Failure is first-class. Approval is first-class. External action must be legible.
///
/// Important:
/// - A thread is not the transport record.
/// - A thread is not the full public profile.
/// - A thread is the durable coordination object that holds the user-facing,
///   secretary-facing basis for why work is progressing the way it is.
public struct ExchangeThread: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var createdAt: Date
    public var updatedAt: Date

    public var mode: ExchangeMode
    public var intent: ExchangeIntent
    public var posture: ExchangePosture

    /// Durable semantic extraction layer for search, fit scoring,
    /// and bounded continuation.
    ///
    /// This is useful, but should not become the canonical bridge
    /// for federation posture or match basis.
    public var facets: ExchangeIntentFacets?

    /// Durable model-owned interpretation handoff.
    ///
    /// This preserves the secretary's request-side understanding of the user's
    /// current thread. It is broader than pure retrieval, but remains a
    /// request/seeking-side snapshot and should not be treated as the canonical
    /// public-profile or federation-permission basis.
    public var interpretation: InterpretationSnapshot?

    /// User-visible translated work trace.
    ///
    /// This is not hidden chain-of-thought.
    /// It is a compact, legible stream of secretary work stages that the UI
    /// can render live in the workspace card.
    public var workTrace: WorkTraceSnapshot?
    
    /// Latest durable second-half projection snapshot.
    ///
    /// This is the compact, user-legible state produced by the second-half layer
    /// for the current thread. It lets lists, thread detail, approval, recovery,
    /// activity, and comparison surfaces stay coherent across reloads without
    /// recomputing second-half meaning from scratch on every UI read.
    ///
    /// This is not hidden reasoning and not the full long-term secretary memory.
    /// Deeper second-half history, prior evaluations, and accumulated learning
    /// should live in the local-only secretary state store.
    public var secondHalf: SecondHalfSnapshot?

    /// Durable thread-level goal contract.
    ///
    /// Intent says what the user wants.
    /// Posture says how the secretary should carry the user.
    /// Expectation says what counts as progress, success, and bounded continuation.
    public var expectation: ExchangeExpectation?

    /// Durable continuation usage state.
    /// Keeps track of whether the thread has already consumed its single
    /// autonomous clarification turn.
    public var autonomousClarificationCount: Int

    /// Canonical thread-visible state.
    public var state: ExchangeState

    /// The currently selected thread participant / external responder, if known.
    ///
    /// Important:
    /// this is not the seller surface itself.
    /// In seller-discovery flows, a thread may first select a public profile
    /// and optionally an offer before resolving the actual participating
    /// counterparty record for the coordination thread.
    public var selectedCounterpartyID: ExchangeCounterparty.ID?

    /// Lightweight pointer to the selected seller-facing public surface, if known.
    ///
    /// This is intentionally small and durable.
    /// Do not store a full public profile blob on the thread.
    ///
    /// Important:
    /// this is a discovered/public coordination surface, not the counterparty
    /// participant record itself.
    public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?

    /// Lightweight pointer to the selected offer basis, if known.
    ///
    /// This is intentionally small and durable.
    /// Do not store a full offer blob on the thread.
    public var selectedOfferID: ExchangeOffer.ID?

    /// Lightweight human-readable rationale for why a selected match / profile /
    /// path was chosen.
    ///
    /// This is not model chain-of-thought. It is a compact, legible basis
    /// that the UI and audits can surface.
    public var selectedMatchRationale: String?

    /// Lightweight posture / path basis for the currently selected external path.
    ///
    /// This is not canonical transport truth. It is a compact snapshot of:
    /// - how contact is allowed
    /// - whether introduction is required
    /// - what trust / disclosure constraints shaped the path
    public var selectedPath: FederationPathSnapshot?

    /// Candidate ids most relevant to the current thread state.
    /// Keep this lightweight and durable.
    public var candidateCounterpartyIDs: [ExchangeCounterparty.ID]

    /// Snapshot of the latest legible failure, if any.
    /// Clear this when the thread meaningfully recovers and progresses.
    public var latestFailure: ExchangeFailure?

    /// Approval bookkeeping kept lightweight at the thread layer.
    public var approval: ApprovalSnapshot?

    /// Lightweight thread/UI summary of outbound progress.
    ///
    /// Important:
    /// this is NOT canonical transport truth.
    /// Canonical transport execution lives in ExchangeDeliveryState on
    /// ExchangeOutboxItem / federation state.
    ///
    /// This snapshot only exists so thread views can show a simple,
    /// user-legible summary without loading transport records.
    public var delivery: DeliverySnapshot?

    /// Compact outcome summary once the thread resolves or meaningfully fails.
    public var outcome: OutcomeSnapshot?

    /// Last user-visible summary generated for the thread.
    public var visibleSummary: String?

    /// Small pointer to the last inbound federation envelope reconciled into
    /// this thread, if known.
    public var lastInboundEnvelopeID: String?

    /// Small pointer to the last outbound envelope queued/sent for this thread,
    /// if known.
    public var lastOutboundEnvelopeID: String?

    /// Freeform metadata for version-safe storage of small future details.
    /// Avoid putting large payloads here.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: ExchangeMode,
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets? = nil,
        interpretation: InterpretationSnapshot? = nil,
        workTrace: WorkTraceSnapshot? = nil,
        secondHalf: SecondHalfSnapshot? = nil,
        expectation: ExchangeExpectation? = nil,
        autonomousClarificationCount: Int = 0,
        state: ExchangeState,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        selectedMatchRationale: String? = nil,
        selectedPath: FederationPathSnapshot? = nil,
        candidateCounterpartyIDs: [ExchangeCounterparty.ID] = [],
        latestFailure: ExchangeFailure? = nil,
        approval: ApprovalSnapshot? = nil,
        delivery: DeliverySnapshot? = nil,
        outcome: OutcomeSnapshot? = nil,
        visibleSummary: String? = nil,
        lastInboundEnvelopeID: String? = nil,
        lastOutboundEnvelopeID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.intent = intent
        self.posture = posture
        self.facets = facets
        self.interpretation = interpretation
        self.workTrace = workTrace
        self.secondHalf = secondHalf
        self.expectation = expectation
        self.autonomousClarificationCount = max(0, autonomousClarificationCount)
        self.state = state
        self.selectedCounterpartyID = selectedCounterpartyID?.nilIfBlank
        self.selectedPublicProfileID = selectedPublicProfileID?.nilIfBlank
        self.selectedOfferID = selectedOfferID?.nilIfBlank
        self.selectedMatchRationale = selectedMatchRationale?.nilIfBlank
        self.selectedPath = selectedPath
        self.candidateCounterpartyIDs = Self.normalizedIDs(candidateCounterpartyIDs)
        self.latestFailure = latestFailure
        self.approval = approval
        self.delivery = delivery
        self.outcome = outcome
        self.visibleSummary = visibleSummary?.nilIfBlank
        self.lastInboundEnvelopeID = lastInboundEnvelopeID?.nilIfBlank
        self.lastOutboundEnvelopeID = lastOutboundEnvelopeID?.nilIfBlank
        self.metadata = metadata
    }
}

public extension ExchangeThread {
    /// Lightweight federation basis snapshot.
    ///
    /// This gives the thread a durable, user-legible record of why a path was
    /// or was not selected, without turning the thread into a transport object
    /// or embedding a full public profile.
    struct SecondHalfSnapshot: Codable, Sendable, Hashable {
        /// Snapshot format version.
        ///
        /// Keep this separate from the thread revision. This lets the second-half
        /// projection format evolve without forcing a full thread migration.
        public var schemaVersion: Int

        /// Optional producer/source label for debugging and migration.
        public var source: String?

        public var currentStateRaw: String
        public var roleRaw: String

        /// Compact stance / posture memory.
        public var postureSummary: String?
        public var readiness: String?
        public var urgency: String?
        public var trust: String?
        public var priceSensitivity: String?
        public var flexibility: String?

        /// Qualification memory.
        public var quality: String?
        public var strengthReasons: [String]
        public var weaknessReasons: [String]
        public var missingFacts: [String]
        /// Present from schema v2+; user-answerable gaps only (nil on legacy snapshots).
        public var userFacingMissingFacts: [String]?
        /// Present from schema v2+; provider / counterparty diagnostics (nil on legacy).
        public var diagnosticMissingFacts: [String]?
        public var clarifiedFacts: [String]
        public var unresolvedIssues: [String]

        /// Decision / recommendation memory.
        public var decisionSummary: String?
        public var recommendation: String?
        public var previousRecommendation: String?
        public var whatChanged: [String]
        public var tradeoffs: [String]

        /// Boundary / approval memory.
        public var escalationReason: String?
        public var boundaryKind: String?
        public var boundaryReason: String?
        public var externalEffectLine: String?
        public var requiresHumanApproval: Bool

        /// Next-move memory.
        public var nextMoveTitle: String?
        public var nextMoveRationale: String?
        public var nextMoveActionRaw: String?
        public var requiredInputs: [String]
        public var canRunAutonomously: Bool
        public var needsHumanAttention: Bool

        /// Provider/requester surface memory.
        public var providerReceptionSummary: String?
        public var providerLeadStrength: String?
        public var requesterReviewSummary: String?
        public var requesterReviewStrength: String?

        /// Draft/facts memory.
        public var draftSubject: String?
        public var draftPreview: String?
        public var draftFactsUsed: [String]

        /// Requester logical pause (additive JSON; optional for legacy snapshots).
        public var requesterPauseFrame: ExchangeRequesterPauseFrame?

        /// Validated secretary closure copy (optional; additive for legacy snapshots).
        public var requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy?

        /// Change tracking.
        public var revision: Int
        public var lastEvaluatedAt: Date
        public var updatedAt: Date

        public init(
            schemaVersion: Int = 1,
            source: String? = "second_half_facade",
            currentStateRaw: String,
            roleRaw: String,
            postureSummary: String? = nil,
            readiness: String? = nil,
            urgency: String? = nil,
            trust: String? = nil,
            priceSensitivity: String? = nil,
            flexibility: String? = nil,
            quality: String? = nil,
            strengthReasons: [String] = [],
            weaknessReasons: [String] = [],
            missingFacts: [String] = [],
            userFacingMissingFacts: [String]? = nil,
            diagnosticMissingFacts: [String]? = nil,
            clarifiedFacts: [String] = [],
            unresolvedIssues: [String] = [],
            decisionSummary: String? = nil,
            recommendation: String? = nil,
            previousRecommendation: String? = nil,
            whatChanged: [String] = [],
            tradeoffs: [String] = [],
            escalationReason: String? = nil,
            boundaryKind: String? = nil,
            boundaryReason: String? = nil,
            externalEffectLine: String? = nil,
            requiresHumanApproval: Bool = false,
            nextMoveTitle: String? = nil,
            nextMoveRationale: String? = nil,
            nextMoveActionRaw: String? = nil,
            requiredInputs: [String] = [],
            canRunAutonomously: Bool = false,
            needsHumanAttention: Bool = false,
            providerReceptionSummary: String? = nil,
            providerLeadStrength: String? = nil,
            requesterReviewSummary: String? = nil,
            requesterReviewStrength: String? = nil,
            draftSubject: String? = nil,
            draftPreview: String? = nil,
            draftFactsUsed: [String] = [],
            requesterPauseFrame: ExchangeRequesterPauseFrame? = nil,
            requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy? = nil,
            revision: Int = 1,
            lastEvaluatedAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.schemaVersion = max(1, schemaVersion)
            self.source = source?.nilIfBlank

            self.currentStateRaw = currentStateRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.roleRaw = roleRaw.trimmingCharacters(in: .whitespacesAndNewlines)

            self.postureSummary = postureSummary?.nilIfBlank
            self.readiness = readiness?.nilIfBlank
            self.urgency = urgency?.nilIfBlank
            self.trust = trust?.nilIfBlank
            self.priceSensitivity = priceSensitivity?.nilIfBlank
            self.flexibility = flexibility?.nilIfBlank

            self.quality = quality?.nilIfBlank
            self.strengthReasons = Self.normalizedLines(strengthReasons, maxCount: 8)
            self.weaknessReasons = Self.normalizedLines(weaknessReasons, maxCount: 8)
            self.missingFacts = Self.normalizedLines(missingFacts, maxCount: 8)
            if let userFacingMissingFacts {
                self.userFacingMissingFacts = Self.normalizedLines(userFacingMissingFacts, maxCount: 8)
            } else {
                self.userFacingMissingFacts = nil
            }
            if let diagnosticMissingFacts {
                self.diagnosticMissingFacts = Self.normalizedLines(diagnosticMissingFacts, maxCount: 10)
            } else {
                self.diagnosticMissingFacts = nil
            }
            self.clarifiedFacts = Self.normalizedLines(clarifiedFacts, maxCount: 10)
            self.unresolvedIssues = Self.normalizedLines(unresolvedIssues, maxCount: 10)

            self.decisionSummary = decisionSummary?.nilIfBlank
            self.recommendation = recommendation?.nilIfBlank
            self.previousRecommendation = previousRecommendation?.nilIfBlank
            self.whatChanged = Self.normalizedLines(whatChanged, maxCount: 10)
            self.tradeoffs = Self.normalizedLines(tradeoffs, maxCount: 8)

            self.escalationReason = escalationReason?.nilIfBlank
            self.boundaryKind = boundaryKind?.nilIfBlank
            self.boundaryReason = boundaryReason?.nilIfBlank
            self.externalEffectLine = externalEffectLine?.nilIfBlank
            self.requiresHumanApproval = requiresHumanApproval

            self.nextMoveTitle = nextMoveTitle?.nilIfBlank
            self.nextMoveRationale = nextMoveRationale?.nilIfBlank
            self.nextMoveActionRaw = nextMoveActionRaw?.nilIfBlank
            self.requiredInputs = Self.normalizedLines(requiredInputs, maxCount: 6)
            self.canRunAutonomously = canRunAutonomously
            self.needsHumanAttention = needsHumanAttention

            self.providerReceptionSummary = providerReceptionSummary?.nilIfBlank
            self.providerLeadStrength = providerLeadStrength?.nilIfBlank
            self.requesterReviewSummary = requesterReviewSummary?.nilIfBlank
            self.requesterReviewStrength = requesterReviewStrength?.nilIfBlank

            self.draftSubject = draftSubject?.nilIfBlank
            self.draftPreview = draftPreview?.nilIfBlank
            self.draftFactsUsed = Self.normalizedLines(draftFactsUsed, maxCount: 10)
            self.requesterPauseFrame = requesterPauseFrame
            self.requesterClosureComposedCopy = requesterClosureComposedCopy

            self.revision = max(1, revision)
            self.lastEvaluatedAt = lastEvaluatedAt
            self.updatedAt = updatedAt
        }

        public func bumpingRevision(at date: Date = Date()) -> SecondHalfSnapshot {
            var copy = self
            copy.revision += 1
            copy.lastEvaluatedAt = date
            copy.updatedAt = date
            return copy
        }

        private static func normalizedLines(_ values: [String], maxCount: Int) -> [String] {
            var seen = Set<String>()
            var output: [String] = []

            for value in values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let key = trimmed.lowercased()
                guard seen.insert(key).inserted else { continue }

                output.append(trimmed)

                if output.count >= maxCount {
                    break
                }
            }

            return output
        }
    }
    
    struct FederationPathSnapshot: Codable, Sendable, Hashable {
        public enum AccessMode: String, Codable, Sendable, CaseIterable, Hashable {
            case open
            case direct
            case introOnly
            case closed
            case unknown
        }

        public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
            case candidate
            case selected
            case blocked
            case unavailable
        }

        public var publicProfileID: ExchangePublicNodeProfile.ID?
        public var accessMode: AccessMode
        public var introductionRequired: Bool
        public var minimumTrustLabel: String?
        public var trustSatisfied: Bool?
        public var disclosureCeiling: ExchangeRelayEnvelope.Payload.DisclosureLevel?
        public var matchedRouteKind: String?
        public var status: Status
        public var rationale: String?
        public var recordedAt: Date

        public init(
            publicProfileID: ExchangePublicNodeProfile.ID? = nil,
            accessMode: AccessMode = .unknown,
            introductionRequired: Bool = false,
            minimumTrustLabel: String? = nil,
            trustSatisfied: Bool? = nil,
            disclosureCeiling: ExchangeRelayEnvelope.Payload.DisclosureLevel? = nil,
            matchedRouteKind: String? = nil,
            status: Status = .candidate,
            rationale: String? = nil,
            recordedAt: Date = Date()
        ) {
            self.publicProfileID = publicProfileID?.nilIfBlank
            self.accessMode = accessMode
            self.introductionRequired = introductionRequired
            self.minimumTrustLabel = minimumTrustLabel?.nilIfBlank
            self.trustSatisfied = trustSatisfied
            self.disclosureCeiling = disclosureCeiling
            self.matchedRouteKind = matchedRouteKind?.nilIfBlank
            self.status = status
            self.rationale = rationale?.nilIfBlank
            self.recordedAt = recordedAt
        }
    }

    struct InterpretationSnapshot: Codable, Sendable, Hashable {
        /// Broad semantic tags extracted from the request.
        public var semanticTags: [String]

        /// Discovery-oriented keywords extracted from the request.
        public var discoveryKeywords: [String]

        /// Broad target tags describing what the request is seeking.
        public var targetTags: [String]

        /// Compact secretary-owned understanding of the user's request.
        public var userSummary: String?
        public var userQuestion: String?
        public var userNextStep: String?

        /// Execution hints derived from the request interpretation.
        public var needsClarification: Bool
        public var shouldDiscover: Bool
        public var shouldDraft: Bool
        public var shouldFederate: Bool

        public init(
            semanticTags: [String] = [],
            discoveryKeywords: [String] = [],
            targetTags: [String] = [],
            userSummary: String? = nil,
            userQuestion: String? = nil,
            userNextStep: String? = nil,
            needsClarification: Bool = false,
            shouldDiscover: Bool = true,
            shouldDraft: Bool = false,
            shouldFederate: Bool = false
        ) {
            self.semanticTags = Self.normalizedTerms(semanticTags, maxCount: 12)
            self.discoveryKeywords = Self.normalizedTerms(discoveryKeywords, maxCount: 12)
            self.targetTags = Self.normalizedTerms(targetTags, maxCount: 10)
            self.userSummary = userSummary?.nilIfBlank
            self.userQuestion = userQuestion?.nilIfBlank
            self.userNextStep = userNextStep?.nilIfBlank
            self.needsClarification = needsClarification
            self.shouldDiscover = shouldDiscover
            self.shouldDraft = shouldDraft
            self.shouldFederate = shouldFederate
        }

        private enum CodingKeys: String, CodingKey {
            case semanticTags
            case discoveryKeywords
            case targetTags
            case userSummary
            case userQuestion
            case userNextStep
            case needsClarification
            case shouldDiscover
            case shouldDraft
            case shouldFederate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.init(
                semanticTags: try container.decodeIfPresent([String].self, forKey: .semanticTags) ?? [],
                discoveryKeywords: try container.decodeIfPresent([String].self, forKey: .discoveryKeywords) ?? [],
                targetTags: try container.decodeIfPresent([String].self, forKey: .targetTags) ?? [],
                userSummary: try container.decodeIfPresent(String.self, forKey: .userSummary),
                userQuestion: try container.decodeIfPresent(String.self, forKey: .userQuestion),
                userNextStep: try container.decodeIfPresent(String.self, forKey: .userNextStep),
                needsClarification: try container.decodeIfPresent(Bool.self, forKey: .needsClarification) ?? false,
                shouldDiscover: try container.decodeIfPresent(Bool.self, forKey: .shouldDiscover) ?? true,
                shouldDraft: try container.decodeIfPresent(Bool.self, forKey: .shouldDraft) ?? false,
                shouldFederate: try container.decodeIfPresent(Bool.self, forKey: .shouldFederate) ?? false
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(semanticTags, forKey: .semanticTags)
            try container.encode(discoveryKeywords, forKey: .discoveryKeywords)
            try container.encode(targetTags, forKey: .targetTags)
            try container.encodeIfPresent(userSummary, forKey: .userSummary)
            try container.encodeIfPresent(userQuestion, forKey: .userQuestion)
            try container.encodeIfPresent(userNextStep, forKey: .userNextStep)
            try container.encode(needsClarification, forKey: .needsClarification)
            try container.encode(shouldDiscover, forKey: .shouldDiscover)
            try container.encode(shouldDraft, forKey: .shouldDraft)
            try container.encode(shouldFederate, forKey: .shouldFederate)
        }

        public static func from(
            _ request: ExchangeInterpreter.InterpretedRequest
        ) -> InterpretationSnapshot {
            InterpretationSnapshot(
                semanticTags: request.semanticTags,
                discoveryKeywords: request.discoveryKeywords,
                targetTags: request.targetTags,
                userSummary: request.userSummary,
                userQuestion: request.userQuestion,
                userNextStep: request.userNextStep,
                needsClarification: false,
                shouldDiscover: request.shouldDiscover,
                shouldDraft: request.shouldDraft,
                shouldFederate: false
            )
        }

        private static func normalizedTerms(_ values: [String], maxCount: Int) -> [String] {
            var seen = Set<String>()
            var output: [String] = []

            for value in values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty else { continue }
                guard !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                output.append(trimmed)
                if output.count >= maxCount { break }
            }

            return output
        }
    }

    struct WorkTraceSnapshot: Codable, Sendable, Hashable {
        public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
            case idle
            case running
            case completed
            case blocked
        }

        public struct Step: Codable, Sendable, Hashable, Identifiable {
            public var id: UUID
            public var key: String
            public var title: String
            public var detail: String?
            public var isActive: Bool
            public var isComplete: Bool
            public var createdAt: Date
            public var updatedAt: Date

            public init(
                id: UUID = UUID(),
                key: String,
                title: String,
                detail: String? = nil,
                isActive: Bool = false,
                isComplete: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date()
            ) {
                self.id = id
                self.key = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                self.detail = detail?.nilIfBlank
                self.isActive = isActive
                self.isComplete = isComplete
                self.createdAt = createdAt
                self.updatedAt = updatedAt
            }
        }

        public var status: Status
        public var headline: String?
        public var steps: [Step]
        public var updatedAt: Date

        public init(
            status: Status = .idle,
            headline: String? = nil,
            steps: [Step] = [],
            updatedAt: Date = Date()
        ) {
            self.status = status
            self.headline = headline?.nilIfBlank
            self.steps = Self.normalizedSteps(steps)
            self.updatedAt = updatedAt
        }

        public var activeStep: Step? {
            steps.last(where: { $0.isActive })
        }

        public var completedStepCount: Int {
            steps.reduce(into: 0) { count, step in
                if step.isComplete { count += 1 }
            }
        }

        public func appendingStep(
            key: String,
            title: String,
            detail: String? = nil,
            activating: Bool = true,
            at date: Date = Date()
        ) -> WorkTraceSnapshot {
            var copy = self
            copy.steps = copy.steps.map {
                var step = $0
                step.isActive = false
                return step
            }

            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if let existingIndex = copy.steps.firstIndex(where: { $0.key == trimmedKey }) {
                var existing = copy.steps[existingIndex]
                existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.detail = detail?.nilIfBlank
                existing.isActive = activating
                existing.updatedAt = date
                copy.steps[existingIndex] = existing
            } else {
                copy.steps.append(
                    Step(
                        key: trimmedKey,
                        title: title,
                        detail: detail,
                        isActive: activating,
                        isComplete: false,
                        createdAt: date,
                        updatedAt: date
                    )
                )
            }

            copy.status = .running
            copy.updatedAt = date
            return copy
        }

        public func markingComplete(
            key: String? = nil,
            headline: String? = nil,
            at date: Date = Date()
        ) -> WorkTraceSnapshot {
            var copy = self

            if let key {
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                copy.steps = copy.steps.map { step in
                    var updated = step
                    if updated.key == trimmedKey {
                        updated.isActive = false
                        updated.isComplete = true
                        updated.updatedAt = date
                    } else if updated.isActive {
                        updated.isActive = false
                        updated.updatedAt = date
                    }
                    return updated
                }
            } else {
                copy.steps = copy.steps.map { step in
                    var updated = step
                    if updated.isActive {
                        updated.isActive = false
                        updated.isComplete = true
                        updated.updatedAt = date
                    }
                    return updated
                }
            }

            copy.status = .completed
            if let headline {
                copy.headline = headline.nilIfBlank
            }
            copy.updatedAt = date
            return copy
        }

        public func markingBlocked(
            headline: String,
            at date: Date = Date()
        ) -> WorkTraceSnapshot {
            var copy = self
            copy.steps = copy.steps.map { step in
                var updated = step
                if updated.isActive {
                    updated.updatedAt = date
                }
                updated.isActive = false
                return updated
            }
            copy.status = .blocked
            copy.headline = headline.nilIfBlank
            copy.updatedAt = date
            return copy
        }

        public static func starter(
            headline: String? = nil,
            at date: Date = Date()
        ) -> WorkTraceSnapshot {
            WorkTraceSnapshot(
                status: .running,
                headline: headline,
                steps: [],
                updatedAt: date
            )
        }

        private static func normalizedSteps(_ steps: [Step]) -> [Step] {
            var seen = Set<String>()
            var output: [Step] = []

            for step in steps {
                guard !step.key.isEmpty else { continue }
                guard !seen.contains(step.key) else { continue }
                seen.insert(step.key)
                output.append(step)
            }

            return output
        }
    }

    struct ApprovalSnapshot: Codable, Sendable, Hashable {
        public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
            case notRequired
            case pending
            case approved
            case rejected
            case expired
        }

        public var status: Status
        public var requestedAt: Date?
        public var decidedAt: Date?
        public var requestedDraftID: ExchangeMessageDraft.ID?
        public var note: String?

        public init(
            status: Status,
            requestedAt: Date? = nil,
            decidedAt: Date? = nil,
            requestedDraftID: ExchangeMessageDraft.ID? = nil,
            note: String? = nil
        ) {
            self.status = status
            self.requestedAt = requestedAt
            self.decidedAt = decidedAt
            self.requestedDraftID = requestedDraftID
            self.note = note?.nilIfBlank
        }
    }

    struct DeliverySnapshot: Codable, Sendable, Hashable {
        public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
            case notStarted
            case pendingApproval
            case readyToSend
            case sending
            case sent
            case failed
        }

        public var status: Status
        public var lastAttemptAt: Date?
        public var lastConfirmedSendAt: Date?
        public var externalReference: String?
        public var note: String?

        public init(
            status: Status,
            lastAttemptAt: Date? = nil,
            lastConfirmedSendAt: Date? = nil,
            externalReference: String? = nil,
            note: String? = nil
        ) {
            self.status = status
            self.lastAttemptAt = lastAttemptAt
            self.lastConfirmedSendAt = lastConfirmedSendAt
            self.externalReference = externalReference?.nilIfBlank
            self.note = note?.nilIfBlank
        }
    }

    struct OutcomeSnapshot: Codable, Sendable, Hashable {
        public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
            case noViableMatch
            case declined
            case stalled
            case resolved
            case failedLegibly
        }

        public var status: Status
        public var summary: String
        public var recordedAt: Date

        public init(
            status: Status,
            summary: String,
            recordedAt: Date = Date()
        ) {
            self.status = status
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.recordedAt = recordedAt
        }
    }
}

public extension ExchangeThread {
    var title: String {
        intent.title.isEmpty ? intent.summaryLine : intent.title
    }

    var hasFailure: Bool {
        latestFailure != nil || state.isFailureState
    }

    var requiresHumanDecision: Bool {
        if let expectation, !expectation.requiresUserDecisionOn.isEmpty {
            switch state {
            case .needsClarification,
                 .matchFound,
                 .matchCandidatesWeak,
                 .noViableMatch,
                 .awaitingApproval,
                 .blockedByDeliveryFailure,
                 .declined,
                 .stalled,
                 .blockedBySystemFailure:
                return true

            case .draftReady,
                 .drafting,
                 .searching,
                 .sending,
                 .awaitingResponse,
                 .resolved:
                break
            }
        }

        switch state {
        case .needsClarification,
             .matchFound,
             .matchCandidatesWeak,
             .noViableMatch,
             .awaitingApproval,
             .blockedByDeliveryFailure,
             .declined,
             .stalled,
             .blockedBySystemFailure:
            return true
            
        case .draftReady,
             .drafting,
             .searching,
             .sending,
             .awaitingResponse,
             .resolved:
            return false
        }
    }

    var canAttemptExternalAction: Bool {
        if intent.requiresClarificationBeforeAction {
            return false
        }

        if let expectation, expectation.stopConditions.contains(.approvalRequired) {
            if approval?.status != .approved && approval?.status != .notRequired && approval != nil {
                return false
            }
        }

        if let approval {
            switch approval.status {
            case .pending, .rejected, .expired:
                return false
            case .approved, .notRequired:
                break
            }
        }

        if let delivery {
            switch delivery.status {
            case .pendingApproval, .sent:
                return false
            case .readyToSend, .sending, .failed, .notStarted:
                break
            }
        }

        switch state {
        case .awaitingApproval:
            return approval?.status == .approved || approval == nil

        case .sending:
            return approval?.status == .approved || approval?.status == .notRequired || approval == nil

        case .awaitingResponse,
             .declined,
             .stalled,
             .resolved,
             .blockedBySystemFailure:
            return false

        case .drafting,
             .draftReady,
             .needsClarification,
             .searching,
             .matchFound,
             .matchCandidatesWeak,
             .noViableMatch,
             .blockedByDeliveryFailure:
            return false
        }
    }

    var autoReplyBudgetRemaining: Int? {
        expectation?.autoReplyBudgetRemaining
    }

    var canAutoContinue: Bool {
        expectation?.canAutoReply ?? false
    }

    var canUseAutonomousClarification: Bool {
        guard let facets, facets.allowsAutonomousClarification else { return false }
        return autonomousClarificationCount < 1
    }

    /// Internal retrieval / ranking query (keyword rails, facet searchable text). Not for user-facing copy.
    var primarySearchText: String {
        if let interpretation,
           !interpretation.discoveryKeywords.isEmpty {
            return interpretation.discoveryKeywords.joined(separator: " ")
        }

        if let facets, !facets.searchableText.isEmpty {
            return facets.searchableText
        }

        return [
            intent.title,
            intent.targetDescription,
            intent.objective
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    /// Durable metadata key for the original requester sentence (set at `beginThread`).
    static let originalRequesterTextMetadataKey = "original_requester_text"

    /// User-facing request wording for conversation, prompts, and titles — never keyword rails.
    var humanRequesterText: String {
        if let stored = metadata[Self.originalRequesterTextMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty,
           !looksLikeInternalSearchQuery(stored) {
            return stored
        }

        let objective = intent.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        if !objective.isEmpty, !looksLikeInternalSearchQuery(objective) {
            return objective
        }

        let title = intent.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty,
           !looksLikeInternalSearchQuery(title),
           !title.lowercased().hasPrefix("find ") {
            return title
        }

        return objective.isEmpty ? "New request" : objective
    }

    /// True when `text` is internal search/retrieval query material, not a human request sentence.
    func looksLikeInternalSearchQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        let primary = primarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !primary.isEmpty, normalized == primary { return true }

        if let facets {
            let searchable = facets.searchableText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !searchable.isEmpty, normalized == searchable { return true }
        }

        if let interpretation, !interpretation.discoveryKeywords.isEmpty {
            let joined = interpretation.discoveryKeywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !joined.isEmpty {
                if normalized == joined { return true }
                let textTokens = Set(
                    normalized.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
                )
                let keywordTokens = Set(
                    joined.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
                )
                if textTokens.count >= 3,
                   textTokens == keywordTokens || (!trimmed.contains(where: { ".!?,".contains($0) }) && textTokens.isSubset(of: keywordTokens)) {
                    return true
                }
            }
        }

        return false
    }

    func withUpdatedState(
        _ newState: ExchangeState,
        at date: Date = Date(),
        failure: ExchangeFailure? = nil,
        visibleSummary: String? = nil
    ) -> ExchangeThread {
        var copy = self
        copy.state = newState
        copy.updatedAt = date

        if let failure {
            copy.latestFailure = failure
        }

        if let visibleSummary {
            copy.visibleSummary = visibleSummary.nilIfBlank
        }

        return copy
    }

    func withFailure(
        _ failure: ExchangeFailure,
        mappedState: ExchangeState,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.latestFailure = failure
        copy.state = mappedState
        copy.updatedAt = date
        copy.visibleSummary = failure.summary

        if let mappedOutcomeStatus = mappedOutcomeStatus(for: mappedState) {
            copy.outcome = OutcomeSnapshot(
                status: mappedOutcomeStatus,
                summary: failure.summary,
                recordedAt: date
            )
        }

        return copy
    }

    func clearingFailure(
        at date: Date = Date(),
        keepOutcome: Bool = false
    ) -> ExchangeThread {
        var copy = self
        copy.latestFailure = nil
        copy.updatedAt = date

        if !keepOutcome {
            copy.outcome = nil
        }

        return copy
    }

    func selectingCounterparty(
        id counterpartyID: ExchangeCounterparty.ID,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        let trimmed = counterpartyID.trimmingCharacters(in: .whitespacesAndNewlines)

        copy.selectedCounterpartyID = trimmed.isEmpty ? nil : trimmed

        if !trimmed.isEmpty, !copy.candidateCounterpartyIDs.contains(trimmed) {
            copy.candidateCounterpartyIDs.append(trimmed)
            copy.candidateCounterpartyIDs = Self.normalizedIDs(copy.candidateCounterpartyIDs)
        }

        copy.updatedAt = date
        return copy
    }

    func selectingMatch(
        counterpartyID: ExchangeCounterparty.ID?,
        publicProfileID: ExchangePublicNodeProfile.ID?,
        offerID: ExchangeOffer.ID?,
        rationale: String? = nil,
        path: FederationPathSnapshot? = nil,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self

        copy.selectedCounterpartyID = counterpartyID?.nilIfBlank
        copy.selectedPublicProfileID = publicProfileID?.nilIfBlank
        copy.selectedOfferID = offerID?.nilIfBlank
        copy.selectedMatchRationale = rationale?.nilIfBlank
        copy.selectedPath = path

        if let counterpartyID = counterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !counterpartyID.isEmpty,
           !copy.candidateCounterpartyIDs.contains(counterpartyID) {
            copy.candidateCounterpartyIDs.append(counterpartyID)
            copy.candidateCounterpartyIDs = Self.normalizedIDs(copy.candidateCounterpartyIDs)
        }

        copy.updatedAt = date
        return copy
    }

    func clearingSelection(
        at date: Date = Date(),
        clearCandidates: Bool = true,
        clearSecondHalf: Bool = true
    ) -> ExchangeThread {
        var copy = self

        copy.selectedCounterpartyID = nil
        copy.selectedPublicProfileID = nil
        copy.selectedOfferID = nil
        copy.selectedMatchRationale = nil
        copy.selectedPath = nil

        if clearCandidates {
            copy.candidateCounterpartyIDs = []
        }

        if clearSecondHalf {
            copy.secondHalf = nil
        }

        copy.updatedAt = date
        return copy
    }

    func updatingCandidates(
        _ ids: [ExchangeCounterparty.ID],
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.candidateCounterpartyIDs = Self.normalizedIDs(ids)
        copy.updatedAt = date
        return copy
    }

    func settingSelectedPath(
        _ selectedPath: FederationPathSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.selectedPath = selectedPath
        copy.updatedAt = date
        return copy
    }

    func settingSelectedPublicProfileID(
        _ profileID: ExchangePublicNodeProfile.ID?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.selectedPublicProfileID = profileID?.nilIfBlank
        copy.updatedAt = date
        return copy
    }

    func settingSelectedOfferID(
        _ offerID: ExchangeOffer.ID?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.selectedOfferID = offerID?.nilIfBlank
        copy.updatedAt = date
        return copy
    }

    func settingSelectedMatchRationale(
        _ rationale: String?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.selectedMatchRationale = rationale?.nilIfBlank
        copy.updatedAt = date
        return copy
    }

    func settingApproval(
        _ approval: ApprovalSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.approval = approval
        copy.updatedAt = date
        return copy
    }

    func settingDelivery(
        _ delivery: DeliverySnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.delivery = delivery
        copy.updatedAt = date
        return copy
    }

    func settingOutcome(
        _ outcome: OutcomeSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.outcome = outcome
        copy.updatedAt = date
        return copy
    }

    func settingExpectation(
        _ expectation: ExchangeExpectation?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.expectation = expectation
        copy.updatedAt = date
        return copy
    }

    func settingFacets(
        _ facets: ExchangeIntentFacets?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.facets = facets
        copy.updatedAt = date
        return copy
    }

    func settingInterpretation(
        _ interpretation: InterpretationSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.interpretation = interpretation
        copy.updatedAt = date
        return copy
    }

    func settingWorkTrace(
        _ workTrace: WorkTraceSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.workTrace = workTrace
        copy.updatedAt = date
        return copy
    }
    
    func settingSecondHalf(
        _ secondHalf: SecondHalfSnapshot?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.secondHalf = secondHalf
        copy.updatedAt = date
        return copy
    }

    func incrementingAutoReplyBudget(
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        if let expectation = copy.expectation {
            copy.expectation = expectation.incrementingAutoReplyCount()
        }
        copy.updatedAt = date
        return copy
    }

    func resettingAutoReplyBudget(
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        if let expectation = copy.expectation {
            copy.expectation = expectation.resettingAutoReplyCount()
        }
        copy.updatedAt = date
        return copy
    }

    func incrementingAutonomousClarificationCount(
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.autonomousClarificationCount += 1
        copy.updatedAt = date
        return copy
    }

    func resettingAutonomousClarificationCount(
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.autonomousClarificationCount = 0
        copy.updatedAt = date
        return copy
    }

    func markingLastInboundEnvelope(
        _ envelopeID: String?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.lastInboundEnvelopeID = envelopeID?.nilIfBlank
        copy.updatedAt = date
        return copy
    }

    func markingLastOutboundEnvelope(
        _ envelopeID: String?,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.lastOutboundEnvelopeID = envelopeID?.nilIfBlank
        copy.updatedAt = date
        return copy
    }

    func updatingIntent(
        _ intent: ExchangeIntent,
        posture: ExchangePosture? = nil,
        facets: ExchangeIntentFacets? = nil,
        interpretation: InterpretationSnapshot? = nil,
        workTrace: WorkTraceSnapshot? = nil,
        secondHalf: SecondHalfSnapshot? = nil,
        expectation: ExchangeExpectation? = nil,
        mode: ExchangeMode? = nil,
        at date: Date = Date(),
        clearVisibleSummary: Bool = false,
        preserveExistingFacets: Bool = false,
        preserveExistingInterpretation: Bool = false,
        preserveExistingWorkTrace: Bool = false,
        preserveExistingSecondHalf: Bool = false,
        preserveExistingExpectation: Bool = false
        
    ) -> ExchangeThread {
        var copy = self
        copy.intent = intent
        copy.mode = mode ?? intent.mode
        copy.posture = posture ?? self.posture
        copy.facets = preserveExistingFacets ? self.facets : facets
        copy.interpretation = preserveExistingInterpretation ? self.interpretation : interpretation
        copy.workTrace = preserveExistingWorkTrace ? self.workTrace : workTrace
        copy.secondHalf = preserveExistingSecondHalf ? self.secondHalf : secondHalf
        copy.expectation = preserveExistingExpectation ? self.expectation : expectation
        copy.autonomousClarificationCount = self.autonomousClarificationCount

        copy.selectedCounterpartyID = nil
        copy.selectedPublicProfileID = nil
        copy.selectedOfferID = nil
        copy.selectedMatchRationale = nil
        copy.selectedPath = nil
        copy.candidateCounterpartyIDs = []

        copy.updatedAt = date

        if clearVisibleSummary {
            copy.visibleSummary = nil
        }

        return copy
    }

    func updatingPosture(
        _ posture: ExchangePosture,
        at date: Date = Date()
    ) -> ExchangeThread {
        var copy = self
        copy.posture = posture
        copy.updatedAt = date
        return copy
    }

    /// Reuse the current thread while refreshing the user's understood intent,
    /// semantic facets, posture, raw interpretation snapshot, and visible work trace.
    /// This preserves current thread state and coordination history, but clears
    /// stale selection and visible summary so a new one can be generated.
    func refreshingForReuse(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets? = nil,
        interpretation: InterpretationSnapshot? = nil,
        workTrace: WorkTraceSnapshot? = nil,
        secondHalf: SecondHalfSnapshot? = nil,
        expectation: ExchangeExpectation? = nil,
        at date: Date = Date(),
        preserveExistingFacets: Bool = false,
        preserveExistingInterpretation: Bool = false,
        preserveExistingWorkTrace: Bool = false,
        preserveExistingSecondHalf: Bool = false,
        preserveExistingExpectation: Bool = false
    ) -> ExchangeThread {
        var copy = self
        copy.intent = intent
        copy.mode = intent.mode
        copy.posture = posture
        copy.facets = preserveExistingFacets ? self.facets : facets
        copy.interpretation = preserveExistingInterpretation ? self.interpretation : interpretation
        copy.workTrace = preserveExistingWorkTrace ? self.workTrace : workTrace
        copy.secondHalf = preserveExistingSecondHalf ? self.secondHalf : secondHalf
        copy.expectation = preserveExistingExpectation ? self.expectation : expectation
        copy.autonomousClarificationCount = self.autonomousClarificationCount

        copy.selectedCounterpartyID = nil
        copy.selectedPublicProfileID = nil
        copy.selectedOfferID = nil
        copy.selectedMatchRationale = nil
        copy.selectedPath = nil
        copy.candidateCounterpartyIDs = []

        copy.latestFailure = nil
        copy.approval = nil
        copy.delivery = nil
        copy.outcome = nil
        copy.visibleSummary = nil
        copy.lastInboundEnvelopeID = nil
        copy.lastOutboundEnvelopeID = nil
        copy.updatedAt = date
        return copy
    }
}

private extension ExchangeThread {
    static func normalizedIDs(_ ids: [ExchangeCounterparty.ID]) -> [ExchangeCounterparty.ID] {
        var seen = Set<String>()
        var output: [ExchangeCounterparty.ID] = []

        for rawID in ids {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }

        return output
    }

    func mappedOutcomeStatus(for state: ExchangeState) -> OutcomeSnapshot.Status? {
        switch state {
        case .matchFound:
            return nil

        case .matchCandidatesWeak, .noViableMatch:
            return .noViableMatch

        case .declined:
            return .declined

        case .stalled:
            return .stalled

        case .resolved:
            return .resolved

        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            return .failedLegibly

        case .drafting,
             .draftReady,
             .needsClarification,
             .searching,
             .awaitingApproval,
             .sending,
             .awaitingResponse:
            return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
