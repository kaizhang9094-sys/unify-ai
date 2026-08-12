import Foundation

#if DEBUG
@inline(__always)
private func exDraftLog(_ message: @autoclosure () -> String) {
    print("[ExchangeDraftEngine] \(message())")
}
#else
@inline(__always)
private func exDraftLog(_ message: @autoclosure () -> String) { }
#endif

/// Creates outbound message drafts for Exchange.
///
/// This engine is intentionally conservative:
/// - no fake certainty
/// - no over-disclosure
/// - no over-commitment beyond the user's posture
public struct ExchangeDraftEngine: Sendable {
    public static let legacyTemplate = ExchangeDraftEngine(
        intelligenceProvider: nil,
        useLegacyTemplates: true
    )

    private let intelligenceProvider: (any ExchangeIntelligenceProvider)?
    private let useLegacyTemplates: Bool

    public init(
        intelligenceProvider: (any ExchangeIntelligenceProvider)? = nil,
        useLegacyTemplates: Bool = false
    ) {
        self.intelligenceProvider = intelligenceProvider
        self.useLegacyTemplates = useLegacyTemplates
    }

    public func createDraft(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind overrideKind: ExchangeMessageDraft.Kind? = nil,
        superseding supersedesDraftID: ExchangeMessageDraft.ID? = nil,
        now: Date = Date()
    ) async -> ExchangeMessageDraft {
        let resolvedKind = overrideKind ?? inferredDraftKind(for: thread.intent.kind)

        exDraftLog(
            "createDraft start " +
            "threadID=\(thread.id.uuidString) " +
            "state=\(thread.state.phaseTitle) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "resolvedKind=\(resolvedKind.rawValue) " +
            "counterpartyID=\(counterparty.id) " +
            "counterpartyKind=\(counterparty.kind.rawValue) " +
            "supersedesDraftID=\(supersedesDraftID?.uuidString ?? "nil") " +
            "useLegacyTemplates=\(useLegacyTemplates) " +
            "hasIntelligenceProvider=\(intelligenceProvider != nil)"
        )

        if useLegacyTemplates || intelligenceProvider == nil {
            exDraftLog(
                "createDraft using fallback path reason=" +
                (useLegacyTemplates ? "legacy_template_enabled" : "no_intelligence_provider")
            )

            let draft = fallbackDraft(
                thread: thread,
                counterparty: counterparty,
                kind: resolvedKind,
                supersedesDraftID: supersedesDraftID,
                now: now
            )

            exDraftLog(
                "createDraft fallback done " +
                "draftID=\(draft.id.uuidString) " +
                "status=\(draft.status.rawValue) " +
                "kind=\(draft.kind.rawValue) " +
                "subjectChars=\(draft.subject?.count ?? 0) " +
                "bodyChars=\(draft.body.count)"
            )

            return draft
        }

        let supersedingDraft = buildSupersedingDraftStub(
            thread: thread,
            counterparty: counterparty,
            kind: resolvedKind,
            supersedesDraftID: supersedesDraftID,
            now: now
        )

        exDraftLog(
            "createDraft supersedingStub " +
            "present=\(supersedingDraft != nil) " +
            "stubID=\(supersedingDraft?.id.uuidString ?? "nil")"
        )

        let response: ExchangeIntelligenceDraftResponse
        do {
            exDraftLog(
                "createDraft intelligence load start " +
                "threadID=\(thread.id.uuidString) " +
                "counterpartyID=\(counterparty.id) " +
                "kind=\(resolvedKind.rawValue)"
            )

            response = try await loadDraftResponse(
                ExchangeIntelligenceDraftRequest(
                    thread: thread,
                    counterparty: counterparty,
                    kind: resolvedKind,
                    supersedingDraft: supersedingDraft
                )
            )

            exDraftLog(
                "createDraft intelligence load done " +
                "subjectChars=\(response.subject?.count ?? 0) " +
                "bodyChars=\(response.body.count) " +
                "strategyChars=\(response.strategyNote?.count ?? 0) " +
                "confidence=\(String(format: "%.3f", response.confidence))"
            )
        } catch {
            exDraftLog(
                "createDraft intelligence load failed " +
                "error=\(String(describing: error))"
            )

            let draft = fallbackDraft(
                thread: thread,
                counterparty: counterparty,
                kind: resolvedKind,
                supersedesDraftID: supersedesDraftID,
                now: now
            )

            exDraftLog(
                "createDraft fallback after intelligence failure " +
                "draftID=\(draft.id.uuidString) " +
                "status=\(draft.status.rawValue) " +
                "kind=\(draft.kind.rawValue) " +
                "subjectChars=\(draft.subject?.count ?? 0) " +
                "bodyChars=\(draft.body.count)"
            )

            return draft
        }

        guard let sanitized = sanitizeDraftResponse(
            response,
            thread: thread,
            counterparty: counterparty,
            fallbackKind: resolvedKind
        ) else {
            exDraftLog("createDraft sanitize returned nil -> fallback")

            let draft = fallbackDraft(
                thread: thread,
                counterparty: counterparty,
                kind: resolvedKind,
                supersedesDraftID: supersedesDraftID,
                now: now
            )

            exDraftLog(
                "createDraft fallback after sanitize failure " +
                "draftID=\(draft.id.uuidString) " +
                "status=\(draft.status.rawValue) " +
                "kind=\(draft.kind.rawValue) " +
                "subjectChars=\(draft.subject?.count ?? 0) " +
                "bodyChars=\(draft.body.count)"
            )

            return draft
        }

        let finalDraft = ExchangeMessageDraft(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            kind: resolvedKind,
            audience: .externalCounterparty,
            subject: sanitized.subject,
            body: sanitized.body,
            strategyNote: sanitized.strategyNote,
            posture: thread.posture,
            targetCounterpartyID: counterparty.id,
            supersedesDraftID: supersedesDraftID
        )

        exDraftLog(
            "createDraft done " +
            "draftID=\(finalDraft.id.uuidString) " +
            "status=\(finalDraft.status.rawValue) " +
            "kind=\(finalDraft.kind.rawValue) " +
            "subjectChars=\(finalDraft.subject?.count ?? 0) " +
            "bodyChars=\(finalDraft.body.count) " +
            "strategyChars=\(finalDraft.strategyNote?.count ?? 0)"
        )

        return finalDraft
    }
}

private extension ExchangeDraftEngine {
    func loadDraftResponse(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        guard let intelligenceProvider else {
            exDraftLog("loadDraftResponse failed noIntelligenceProvider")
            throw ExchangeDraftEngineError.noIntelligenceProvider
        }

        exDraftLog(
            "loadDraftResponse call provider " +
            "threadID=\(request.thread.id.uuidString) " +
            "counterpartyID=\(request.counterparty.id) " +
            "kind=\(request.kind.rawValue)"
        )

        let response = try await intelligenceProvider.composeDraft(request)

        exDraftLog(
            "loadDraftResponse provider returned " +
            "subjectChars=\(response.subject?.count ?? 0) " +
            "bodyChars=\(response.body.count) " +
            "strategyChars=\(response.strategyNote?.count ?? 0) " +
            "confidence=\(String(format: "%.3f", response.confidence))"
        )

        return response
    }

    func sanitizeDraftResponse(
        _ response: ExchangeIntelligenceDraftResponse,
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        fallbackKind: ExchangeMessageDraft.Kind
    ) -> ExchangeIntelligenceDraftResponse? {
        let trimmedBody = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            exDraftLog("sanitizeDraftResponse reject reason=empty_body")
            return nil
        }

        let confidence = clampConfidence(response.confidence)
        guard confidence >= 0.20 else {
            exDraftLog(
                "sanitizeDraftResponse reject reason=low_confidence value=\(String(format: "%.3f", confidence))"
            )
            return nil
        }

        let trimmedSubject = response.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStrategy = response.strategyNote?.trimmingCharacters(in: .whitespacesAndNewlines)

        let expectationAlignedBody = alignBodyToExpectation(
            body: String(trimmedBody.prefix(2400)),
            thread: thread,
            counterparty: counterparty,
            kind: fallbackKind
        )

        let finalStrategy: String? = {
            if let trimmedStrategy, !trimmedStrategy.isEmpty {
                let enriched = enrichStrategyNote(
                    base: String(trimmedStrategy.prefix(300)),
                    expectation: thread.expectation,
                    kind: fallbackKind
                )
                exDraftLog(
                    "sanitizeDraftResponse strategy source=model_enriched chars=\(enriched.count)"
                )
                return enriched
            }

            let built = buildStrategyNote(
                thread: thread,
                counterparty: counterparty,
                kind: fallbackKind
            )
            exDraftLog(
                "sanitizeDraftResponse strategy source=fallback_builder chars=\(built.count)"
            )
            return built
        }()

        let sanitized = ExchangeIntelligenceDraftResponse(
            subject: trimmedSubject.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) },
            body: expectationAlignedBody,
            strategyNote: finalStrategy,
            confidence: confidence
        )

        exDraftLog(
            "sanitizeDraftResponse success " +
            "subjectChars=\(sanitized.subject?.count ?? 0) " +
            "bodyChars=\(sanitized.body.count) " +
            "strategyChars=\(sanitized.strategyNote?.count ?? 0) " +
            "confidence=\(String(format: "%.3f", sanitized.confidence))"
        )

        return sanitized
    }

    func buildSupersedingDraftStub(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind,
        supersedesDraftID: ExchangeMessageDraft.ID?,
        now: Date
    ) -> ExchangeMessageDraft? {
        guard let supersedesDraftID else {
            exDraftLog("buildSupersedingDraftStub none")
            return nil
        }

        let stub = ExchangeMessageDraft(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            kind: kind,
            audience: .externalCounterparty,
            subject: nil,
            body: "",
            strategyNote: nil,
            posture: thread.posture,
            targetCounterpartyID: counterparty.id,
            supersedesDraftID: supersedesDraftID
        )

        exDraftLog(
            "buildSupersedingDraftStub built " +
            "draftID=\(stub.id.uuidString) " +
            "supersedesDraftID=\(supersedesDraftID.uuidString) " +
            "kind=\(kind.rawValue)"
        )

        return stub
    }

    func fallbackDraft(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind,
        supersedesDraftID: ExchangeMessageDraft.ID?,
        now: Date
    ) -> ExchangeMessageDraft {
        exDraftLog(
            "fallbackDraft start " +
            "threadID=\(thread.id.uuidString) " +
            "counterpartyID=\(counterparty.id) " +
            "kind=\(kind.rawValue)"
        )

        let subject = buildSubject(thread: thread, counterparty: counterparty, kind: kind)
        let body = buildBody(thread: thread, counterparty: counterparty, kind: kind)
        let strategy = buildStrategyNote(thread: thread, counterparty: counterparty, kind: kind)

        let draft = ExchangeMessageDraft(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            kind: kind,
            audience: .externalCounterparty,
            subject: subject,
            body: body,
            strategyNote: strategy,
            posture: thread.posture,
            targetCounterpartyID: counterparty.id,
            supersedesDraftID: supersedesDraftID
        )

        exDraftLog(
            "fallbackDraft done " +
            "draftID=\(draft.id.uuidString) " +
            "subjectChars=\(draft.subject?.count ?? 0) " +
            "bodyChars=\(draft.body.count) " +
            "strategyChars=\(draft.strategyNote?.count ?? 0)"
        )

        return draft
    }

    func clampConfidence(_ value: Double) -> Double {
        let clamped = min(max(value, 0.0), 1.0)
        exDraftLog(
            "clampConfidence input=\(String(format: "%.3f", value)) output=\(String(format: "%.3f", clamped))"
        )
        return clamped
    }

    func inferredDraftKind(for kind: ExchangeIntent.Kind) -> ExchangeMessageDraft.Kind {
        let resolved: ExchangeMessageDraft.Kind
        switch kind {
        case .introduce:
            resolved = .introduction
        case .requestQuote:
            resolved = .quoteRequest
        case .followUp, .checkStatus:
            resolved = .followUp
        case .negotiate:
            resolved = .negotiation
        case .arrangeCall, .arrangeMeeting, .invite:
            resolved = .scheduling
        case .message, .find, .source, .coordinate, .plan, .other:
            resolved = .inquiry
        }

        exDraftLog(
            "inferredDraftKind intent=\(kind.rawValue) resolved=\(resolved.rawValue)"
        )

        return resolved
    }

    func buildSubject(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind
    ) -> String? {
        let subject: String?

        if let expectation = thread.expectation {
            switch expectation.primaryGoal {
            case .obtainQuote:
                if let target = thread.intent.targetDescription, !target.isEmpty {
                    subject = "Quote request: \(target)"
                } else {
                    subject = "Quote request"
                }

            case .secureIntroduction:
                subject = "Introduction request"

            case .arrangeCall:
                subject = "Call coordination"

            case .arrangeMeeting:
                subject = "Meeting coordination"

            case .confirmAvailability:
                subject = "Availability check"

            case .confirmFit:
                if let target = thread.intent.targetDescription, !target.isEmpty {
                    subject = "Fit check: \(target)"
                } else {
                    subject = "Fit check"
                }

            case .advanceNegotiation:
                subject = "Next step on terms"

            case .establishContact, .gatherInformation, .resolveThread, .other:
                subject = nil
            }
        } else {
            switch kind {
            case .quoteRequest:
                if let target = thread.intent.targetDescription, !target.isEmpty {
                    subject = "Quote request: \(target)"
                } else {
                    subject = "Quote request"
                }

            case .introduction:
                subject = "Introduction request"

            case .followUp:
                subject = "Follow-up"

            case .negotiation:
                subject = "Next step on terms"

            case .scheduling:
                if thread.intent.kind == .arrangeCall {
                    subject = "Call coordination"
                } else if thread.intent.kind == .arrangeMeeting {
                    subject = "Meeting coordination"
                } else {
                    subject = "Scheduling"
                }

            case .inquiry:
                if let target = thread.intent.targetDescription, !target.isEmpty {
                    subject = "Inquiry: \(target)"
                } else {
                    subject = "Inquiry"
                }

            case .closure, .other:
                subject = nil
            }
        }

        exDraftLog(
            "buildSubject kind=\(kind.rawValue) subject=\(subject ?? "nil")"
        )

        return subject
    }

    func buildBody(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        let opening = openingLine(for: counterparty, posture: thread.posture)
        let objective = objectiveLine(for: thread, kind: kind)
        let expectation = expectationLine(for: thread, kind: kind)
        let market = marketContextLine(for: thread)
        let constraintLine = constraintsLine(for: thread)
        let privacyGuard = privacyLine(for: thread.posture, expectation: thread.expectation)
        let commitmentGuard = commitmentLine(for: thread.posture, expectation: thread.expectation)
        let urgencyLine = urgencyLine(for: thread.posture)
        let callToAction = ctaLine(for: thread, kind: kind)

        let body = [
            opening,
            objective,
            expectation,
            market,
            constraintLine,
            privacyGuard,
            commitmentGuard,
            urgencyLine,
            callToAction
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        exDraftLog(
            "buildBody kind=\(kind.rawValue) bodyChars=\(body.count)"
        )

        return body
    }

    func openingLine(
        for counterparty: ExchangeCounterparty,
        posture: ExchangePosture
    ) -> String {
        let name = counterparty.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let line: String
        switch posture.warmth {
        case .warm:
            line = name.isEmpty ? "Hi there," : "Hi \(name),"
        case .neutral, .reserved:
            line = name.isEmpty ? "Hello," : "Hello \(name),"
        }

        exDraftLog(
            "openingLine warmth=\(posture.warmth.rawValue) line=\(line)"
        )

        return line
    }

    func objectiveLine(
        for thread: ExchangeThread,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        let target = thread.intent.targetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)

        let line: String
        switch kind {
        case .quoteRequest:
            if let target, !target.isEmpty {
                line = "I’m reaching out to request a quote for \(target)."
            } else {
                line = "I’m reaching out to request a quote."
            }

        case .introduction:
            if let target, !target.isEmpty {
                line = "I’m reaching out because I’m hoping to explore a possible introduction related to \(target)."
            } else {
                line = "I’m reaching out to explore a possible introduction."
            }

        case .followUp:
            line = "I wanted to follow up on this and see whether it is still worth progressing."

        case .negotiation:
            line = "I’m reaching out to see whether there is still room to move toward alignment on the current terms."

        case .scheduling:
            if thread.intent.kind == .arrangeCall {
                line = "I’m reaching out to see whether a call makes sense for this."
            } else if thread.intent.kind == .arrangeMeeting {
                line = "I’m reaching out to see whether a meeting would make sense for this."
            } else {
                line = "I’m reaching out to coordinate the next step."
            }

        case .inquiry:
            if let target, !target.isEmpty {
                line = "I’m reaching out regarding \(target)."
            } else {
                line = "I’m reaching out regarding a potential fit."
            }

        case .closure:
            line = "I’m writing to close the loop on this thread."

        case .other:
            line = thread.intent.objective
        }

        exDraftLog(
            "objectiveLine kind=\(kind.rawValue) lineChars=\(line.count)"
        )

        return line
    }

    func expectationLine(
        for thread: ExchangeThread,
        kind: ExchangeMessageDraft.Kind
    ) -> String? {
        guard let expectation = thread.expectation else {
            exDraftLog("expectationLine none")
            return nil
        }

        let line: String?
        switch expectation.primaryGoal {
        case .obtainQuote:
            line = "The goal here is to determine whether there is a real quoting path, not to over-negotiate too early."
        case .secureIntroduction:
            line = "The goal here is a clean introduction path without overcommitting too early."
        case .arrangeCall:
            line = "The goal here is to see whether a call makes sense and to keep the next step bounded."
        case .arrangeMeeting:
            line = "The goal here is to see whether a meeting makes sense and to keep the next step bounded."
        case .confirmAvailability:
            line = "The goal here is to get a clear availability or status signal."
        case .confirmFit:
            line = "The goal here is to confirm fit or cleanly rule it out."
        case .advanceNegotiation:
            line = "The goal here is to test whether there is a workable path forward without overcommitting."
        case .establishContact:
            line = "The goal here is to establish contact and see whether there is a real basis to continue."
        case .gatherInformation:
            line = "The goal here is to gather enough information to determine the next step."
        case .resolveThread:
            line = "The goal here is to move this thread to a clear resolution."
        case .other:
            line = nil
        }

        exDraftLog(
            "expectationLine primaryGoal=\(expectation.primaryGoal) present=\(line != nil)"
        )

        return line
    }

    func marketContextLine(for thread: ExchangeThread) -> String? {
        guard let expectation = thread.expectation else {
            exDraftLog("marketContextLine none")
            return nil
        }

        let line: String?
        switch expectation.marketType {
        case .localService:
            line = expectation.prefersLocalFirst ? "A local option is preferred here." : nil
        case .physicalGoods:
            line = expectation.allowsRemoteOrShipped ? "Shipped fulfillment is acceptable if the fit is right." : nil
        case .digitalService:
            line = "Remote or digital fulfillment is acceptable here."
        case .relationshipLed:
            line = "Keep the exchange low-pressure and respectful."
        case .informationRequest, .unknown:
            line = nil
        }

        exDraftLog(
            "marketContextLine marketType=\(expectation.marketType) present=\(line != nil)"
        )

        return line
    }

    func constraintsLine(for thread: ExchangeThread) -> String? {
        var renderedConstraints: [String] = thread.intent.constraints.map { constraint in
            constraint.isHardConstraint
                ? "\(constraint.key): \(constraint.value)"
                : "\(constraint.key): \(constraint.value) (preferred)"
        }

        if let expectation = thread.expectation {
            if expectation.prefersLocalFirst {
                renderedConstraints.append("location: local preferred")
            }

            switch expectation.fulfillmentMode {
            case .localOnly:
                renderedConstraints.append("fulfillment: local only")
            case .localPreferred:
                renderedConstraints.append("fulfillment: local preferred")
            case .shippable:
                renderedConstraints.append("fulfillment: shipped delivery is acceptable")
            case .remoteFriendly:
                renderedConstraints.append("fulfillment: remote coordination is acceptable")
            case .digitalDelivery:
                renderedConstraints.append("fulfillment: digital delivery is acceptable")
            case .unknown:
                break
            }
        }

        guard !renderedConstraints.isEmpty else {
            exDraftLog("constraintsLine none")
            return nil
        }

        let rendered = renderedConstraints.joined(separator: "; ")

        let line: String
        switch thread.posture.directness {
        case .firm:
            line = "Key constraints: \(rendered)."
        case .balanced:
            line = "A few constraints matter on my side: \(rendered)."
        case .soft:
            line = "A few preferences may be relevant here: \(rendered)."
        }

        exDraftLog(
            "constraintsLine directness=\(thread.posture.directness.rawValue) count=\(renderedConstraints.count)"
        )

        return line
    }

    func privacyLine(
        for posture: ExchangePosture,
        expectation: ExchangeExpectation?
    ) -> String? {
        if let expectation,
           expectation.stopConditions.contains(.counterpartyRequestsSensitiveInfo) ||
           expectation.stopConditions.contains(.disclosureBoundaryReached) {
            exDraftLog("privacyLine via expectation boundary")
            return "I’m keeping the initial context limited for now and can share more only if needed."
        }

        let line: String?
        switch posture.privacy {
        case .guarded:
            line = "I’m keeping the initial context brief for now, but I can share more if useful."
        case .balanced, .disclosive:
            line = nil
        }

        exDraftLog(
            "privacyLine posture=\(posture.privacy.rawValue) present=\(line != nil)"
        )

        return line
    }

    func commitmentLine(
        for posture: ExchangePosture,
        expectation: ExchangeExpectation?
    ) -> String? {
        if let expectation,
           expectation.stopConditions.contains(.counterpartyRequestsCommitment) {
            exDraftLog("commitmentLine via expectation boundary")
            return "I’m keeping this exploratory for now and not committing beyond an initial fit check."
        }

        let line: String?
        switch posture.commitment {
        case .exploring:
            line = "I’m keeping this exploratory at the moment."
        case .serious, .committed:
            line = nil
        }

        exDraftLog(
            "commitmentLine posture=\(posture.commitment.rawValue) present=\(line != nil)"
        )

        return line
    }

    func urgencyLine(for posture: ExchangePosture) -> String? {
        let line: String?
        switch posture.urgency {
        case .immediate:
            line = "Timing matters on this side, so a prompt response would be appreciated."
        case .high:
            line = "I’m hoping to move on this fairly soon."
        case .normal, .low:
            line = nil
        }

        exDraftLog(
            "urgencyLine urgency=\(posture.urgency.rawValue) present=\(line != nil)"
        )

        return line
    }

    func ctaLine(
        for thread: ExchangeThread,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        if let expectation = thread.expectation {
            switch expectation.primaryGoal {
            case .obtainQuote:
                let line = statementCTA(
                    thread: thread,
                    direct: "If this is something you handle, please let me know what information you would need in order to quote it.",
                    softer: "If this is something you handle, I’d be glad to share whatever you would need for a quote."
                )
                exDraftLog("ctaLine via expectation primaryGoal=obtainQuote")
                return line
            case .secureIntroduction:
                let line = statementCTA(
                    thread: thread,
                    direct: "If this feels like a fit, please let me know the best next step for an introduction.",
                    softer: "If this sounds relevant, I’d be happy to continue the conversation and see whether an introduction makes sense."
                )
                exDraftLog("ctaLine via expectation primaryGoal=secureIntroduction")
                return line
            case .arrangeCall, .arrangeMeeting:
                let line = statementCTA(
                    thread: thread,
                    direct: "Let me know what timing would work best.",
                    softer: "I’d be glad to work around a time that suits you."
                )
                exDraftLog("ctaLine via expectation primaryGoal=arrangeCall/arrangeMeeting")
                return line
            case .confirmAvailability:
                let line = statementCTA(
                    thread: thread,
                    direct: "Let me know whether this is still available or worth progressing.",
                    softer: "I’d be glad to continue if this still makes sense on your side."
                )
                exDraftLog("ctaLine via expectation primaryGoal=confirmAvailability")
                return line
            case .confirmFit:
                let line = statementCTA(
                    thread: thread,
                    direct: "Let me know whether this is within your scope.",
                    softer: "I’d be glad to hear whether this could be a fit."
                )
                exDraftLog("ctaLine via expectation primaryGoal=confirmFit")
                return line
            case .advanceNegotiation:
                let line = statementCTA(
                    thread: thread,
                    direct: "Let me know whether there is a workable path forward.",
                    softer: "I’d be open to seeing whether there is still a workable path here."
                )
                exDraftLog("ctaLine via expectation primaryGoal=advanceNegotiation")
                return line
            case .establishContact, .gatherInformation, .resolveThread, .other:
                break
            }
        }

        let line: String
        switch kind {
        case .quoteRequest:
            switch thread.posture.directness {
            case .firm:
                line = "If this is something you handle, please let me know what information you would need to quote it."
            case .balanced, .soft:
                line = "If this is something you handle, I’d be glad to share whatever you need for a quote."
            }

        case .introduction:
            line = statementCTA(
                thread: thread,
                direct: "If this feels like a fit, I’d be open to taking the next step.",
                softer: "If this sounds relevant, I’d be happy to continue the conversation."
            )

        case .followUp:
            line = statementCTA(
                thread: thread,
                direct: "Let me know whether this is still worth progressing.",
                softer: "I’d be glad to continue if this still makes sense on your side."
            )

        case .negotiation:
            line = statementCTA(
                thread: thread,
                direct: "Let me know whether there is a workable path forward.",
                softer: "I’d be open to seeing whether there is still a workable path here."
            )

        case .scheduling:
            line = statementCTA(
                thread: thread,
                direct: "Let me know what timing would work best.",
                softer: "I’d be glad to work around a time that suits you."
            )

        case .inquiry:
            line = statementCTA(
                thread: thread,
                direct: "Let me know whether this is within your scope.",
                softer: "I’d be glad to hear whether this could be a fit."
            )

        case .closure:
            line = "No action is needed unless you think this should be revisited."

        case .other:
            line = statementCTA(
                thread: thread,
                direct: "Let me know the best next step.",
                softer: "I’d be glad to continue if this makes sense."
            )
        }

        exDraftLog(
            "ctaLine via kind kind=\(kind.rawValue) lineChars=\(line.count)"
        )

        return line
    }

    func statementCTA(
        thread: ExchangeThread,
        direct: String,
        softer: String
    ) -> String {
        let line: String
        switch thread.posture.directness {
        case .firm:
            line = direct
        case .balanced, .soft:
            line = softer
        }

        exDraftLog(
            "statementCTA directness=\(thread.posture.directness.rawValue) lineChars=\(line.count)"
        )

        return line
    }

    func buildStrategyNote(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        var parts: [String] = []

        switch kind {
        case .quoteRequest:
            parts.append("Quote-seeking outreach.")
        case .introduction:
            parts.append("Low-pressure introduction framing.")
        case .followUp:
            parts.append("Gentle thread reactivation.")
        case .negotiation:
            parts.append("Alignment check without overstating leverage.")
        case .scheduling:
            parts.append("Next-step coordination.")
        case .inquiry:
            parts.append("Fit-testing first-touch outreach.")
        case .closure:
            parts.append("Thread closure.")
        case .other:
            parts.append("General coordination draft.")
        }

        if let expectation = thread.expectation {
            parts.append("Primary goal: \(primaryGoalStrategyLabel(expectation.primaryGoal)).")
            parts.append("Market type: \(marketTypeStrategyLabel(expectation.marketType)).")
            parts.append("Fulfillment mode: \(fulfillmentModeStrategyLabel(expectation.fulfillmentMode)).")
            parts.append("Risk level: \(riskLevelStrategyLabel(expectation.riskLevel)).")

            if expectation.prefersLocalFirst {
                parts.append("Bias toward local-first framing.")
            }
            if expectation.allowsRemoteOrShipped {
                parts.append("Remote or shipped fulfillment can be treated as acceptable.")
            }
            if expectation.allowsAutonomousClarification {
                parts.append("A small amount of bounded clarification is acceptable.")
            } else {
                parts.append("Avoid open-ended clarification loops.")
            }
            if expectation.maxAutoReplies > 0 {
                parts.append("Respect bounded autonomy budget.")
            }
        }

        if thread.posture.privacy == .guarded {
            parts.append("Disclosure kept intentionally minimal.")
        }
        if thread.posture.commitment == .exploring {
            parts.append("Avoids overstating commitment.")
        }
        if thread.posture.directness == .firm {
            parts.append("Uses clear, efficient phrasing.")
        }
        if thread.posture.urgency == .immediate || thread.posture.urgency == .high {
            parts.append("Signals timing importance without claiming urgency on the recipient.")
        }
        if counterparty.kind == .secretaryNode {
            parts.append("Suitable for node-to-node coordination.")
        }

        let note = parts.joined(separator: " ")

        exDraftLog(
            "buildStrategyNote kind=\(kind.rawValue) chars=\(note.count)"
        )

        return note
    }

    func alignBodyToExpectation(
        body: String,
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            exDraftLog("alignBodyToExpectation empty body -> rebuilding fallback body")
            return buildBody(thread: thread, counterparty: counterparty, kind: kind)
        }

        if let expectation = thread.expectation,
           expectation.allowsAutonomousClarification == false,
           trimmed.contains("?") {
            exDraftLog("alignBodyToExpectation softening questions due to expectation boundary")
            return softenQuestionsInBody(trimmed)
        }

        exDraftLog("alignBodyToExpectation unchanged bodyChars=\(trimmed.count)")
        return trimmed
    }

    func softenQuestionsInBody(_ body: String) -> String {
        var lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if let lastIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lines[lastIndex] = lines[lastIndex].replacingOccurrences(of: "?", with: ".")
        }

        let softened = lines.joined(separator: "\n")

        exDraftLog(
            "softenQuestionsInBody beforeChars=\(body.count) afterChars=\(softened.count)"
        )

        return softened
    }

    func enrichStrategyNote(
        base: String,
        expectation: ExchangeExpectation?,
        kind: ExchangeMessageDraft.Kind
    ) -> String {
        guard let expectation else {
            exDraftLog("enrichStrategyNote no expectation")
            return base
        }

        var extras: [String] = [base]
        extras.append("Primary goal: \(primaryGoalStrategyLabel(expectation.primaryGoal)).")
        extras.append("Risk level: \(riskLevelStrategyLabel(expectation.riskLevel)).")

        if expectation.prefersLocalFirst {
            extras.append("Favor local-first fit.")
        }
        if expectation.allowsRemoteOrShipped {
            extras.append("Remote or shipped options are acceptable.")
        }
        if expectation.allowsAutonomousClarification == false {
            extras.append("Avoid open-ended clarification.")
        }

        let enriched = extras.joined(separator: " ")

        exDraftLog(
            "enrichStrategyNote kind=\(kind.rawValue) baseChars=\(base.count) enrichedChars=\(enriched.count)"
        )

        return enriched
    }

    func primaryGoalStrategyLabel(_ value: ExchangeExpectation.PrimaryGoal) -> String {
        switch value {
        case .obtainQuote: return "obtain a quote"
        case .establishContact: return "establish contact"
        case .secureIntroduction: return "secure an introduction"
        case .arrangeCall: return "arrange a call"
        case .arrangeMeeting: return "arrange a meeting"
        case .gatherInformation: return "gather information"
        case .confirmAvailability: return "confirm availability"
        case .confirmFit: return "confirm fit"
        case .advanceNegotiation: return "advance negotiation"
        case .resolveThread: return "resolve the thread"
        case .other: return "move the request forward"
        }
    }

    func marketTypeStrategyLabel(_ value: ExchangeExpectation.MarketType) -> String {
        switch value {
        case .localService: return "local service"
        case .physicalGoods: return "physical goods"
        case .digitalService: return "digital service"
        case .informationRequest: return "information request"
        case .relationshipLed: return "relationship-led"
        case .unknown: return "unknown"
        }
    }

    func fulfillmentModeStrategyLabel(_ value: ExchangeExpectation.FulfillmentMode) -> String {
        switch value {
        case .localOnly: return "local only"
        case .localPreferred: return "local preferred"
        case .shippable: return "shippable"
        case .remoteFriendly: return "remote-friendly"
        case .digitalDelivery: return "digital delivery"
        case .unknown: return "unknown"
        }
    }

    func riskLevelStrategyLabel(_ value: ExchangeExpectation.RiskLevel) -> String {
        switch value {
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        }
    }
}

private enum ExchangeDraftEngineError: Error {
    case noIntelligenceProvider
}
