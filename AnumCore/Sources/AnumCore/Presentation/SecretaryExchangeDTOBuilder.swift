import Foundation

/// Pure mapping from durable exchange row / detail data into user-facing secretary exchange DTOs.
public enum SecretaryExchangeDTOBuilder {

    // MARK: - Public builders

    public static func buildItem(from source: SecretaryExchangeListRowSource, turns: [ExchangeTurn]) -> SecretaryExchangeItem {
        let headline = sanitize(source.titlePick.title)
        let sub = sanitizeOptional(source.subtitle.nilIfBlank)
        let phase = phaseLabel(display: source.display, inboxPhaseFallback: source.inboxPhaseTitle)
        let original = originalRequest(
            requestCaptured: source.requestCaptured,
            interpretationQuestion: source.interpretationUserQuestion,
            threadStoredTitle: source.threadStoredTitle,
            titlePickTitle: source.titlePick.title
        )
        let match = matchCard(from: source)
        let missing = missingLines(
            display: source.display,
            clarificationPrompt: source.clarificationPrompt
        )
        let outbound = outboundDraftCard(
            from: source.latestDraft,
            display: source.display,
            thread: source.thread
        )
        let inbound = latestInboundCard(fromTurns: turns)
        let next = nextAction(display: source.display, nextStepText: source.nextStepText)

        return SecretaryExchangeItem(
            id: source.id,
            updatedAt: source.updatedAt,
            headlineTitle: headline,
            subtitle: sub,
            phaseLabel: phase,
            originalRequest: original,
            matchCard: match,
            missingInformation: missing,
            outboundDraft: outbound,
            latestInbound: inbound,
            nextAction: next
        )
    }

    public static func buildDetail(from detail: ExchangeModels.ThreadDetail) -> SecretaryExchangeDetail {
        let display = detail.secondHalfDisplay
        let thread = detail.thread
        let turns = detail.turns
        let latestDraft = detail.drafts.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first

        let requestCaptured: String? = {
            if ExchangeThreadCardTitleProjection.isProviderInboundThread(metadata: thread.metadata) {
                return nil
            }
            if thread.threadRole == .candidateCoordination {
                return ExchangeThreadSearchQueryDisplay.displaySearchQuery(
                    for: thread,
                    turns: turns
                )?.text ?? ExchangeThreadCardTitleProjection.requestCapturedText(from: turns)
            }
            return ExchangeThreadCardTitleProjection.requestCapturedText(from: turns)
        }()
        let interpretation = thread.interpretation
        let isProviderInbound = ExchangeThreadCardTitleProjection.isProviderInboundThread(metadata: thread.metadata)

        let draftSubjectForHeader: String? = {
            guard let draft = latestDraft else { return nil }
            guard draft.audience == .externalCounterparty else {
                return draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            }
            guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else { return nil }
            return draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }()

        let inboundRequesterAsk: String? = {
            guard isProviderInbound else { return nil }
            return ExchangeThreadCardTitleProjection.latestInboundRequesterAsk(from: turns)
        }()

        let inquirySummary: String? = {
            guard isProviderInbound else { return nil }
            if let summary = display?.providerReception?.inquirySummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return summary
            }
            if let ask = display?.providerReception?.requesterAsk?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return ask
            }
            let objective = thread.intent.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !objective.isEmpty else { return nil }
            if ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(objective) { return nil }
            if objective.lowercased().hasPrefix("review and respond to the inbound") { return nil }
            return objective
        }()

        let titlePick = ExchangeThreadCardTitleProjection.threadHeaderTitle(
            requestCapturedFromTurn: requestCaptured,
            interpretationUserQuestion: isProviderInbound ? nil : interpretation?.userQuestion,
            threadStoredTitle: thread.title,
            draftedSubject: draftSubjectForHeader,
            hydratedOpportunityTitle: detail.selectedCounterparty?.bestDisplayLine,
            threadID: thread.id,
            surface: "detail",
            fallback: isProviderInbound ? "New inquiry" : "New request",
            isProviderInbound: isProviderInbound,
            inboundRequesterAsk: inboundRequesterAsk,
            inquirySummary: inquirySummary,
            inboundSenderDisplay: detail.selectedCounterparty?.bestDisplayLine
        )

        let subtitleRaw = detail.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = subtitleRaw.isEmpty ? nil : sanitize(subtitleRaw)

        let phase = phaseLabel(display: display, inboxPhaseFallback: "")

        let original = originalRequest(
            requestCaptured: requestCaptured,
            interpretationQuestion: interpretation?.userQuestion,
            threadStoredTitle: thread.title,
            titlePickTitle: titlePick.title
        )

        let match = matchCardForDetail(detail: detail)
        let missing = missingLines(
            display: display,
            clarificationPrompt: clarificationPromptFromTurns(turns, thread: thread)
        )
        let outbound = outboundDraftCard(from: latestDraft, display: display, thread: thread)
        let inbound = latestInboundCard(fromTurns: turns)
        let nextStepFallback = detail.interpretationNextStep ?? interpretation?.userNextStep
        let next = nextAction(display: display, nextStepText: nextStepFallback)
        let steps = workSteps(from: display, turns: turns)

        return SecretaryExchangeDetail(
            id: thread.id,
            updatedAt: thread.updatedAt,
            headlineTitle: sanitize(titlePick.title),
            subtitle: subtitle,
            phaseLabel: phase,
            originalRequest: original,
            matchCard: match,
            missingInformation: missing,
            outboundDraft: outbound,
            latestInbound: inbound,
            nextAction: next,
            workSteps: steps
        )
    }

    // MARK: - Internals

    private static func clarificationPromptFromTurns(_ turns: [ExchangeTurn], thread: ExchangeThread) -> String? {
        if let q = turns.reversed().first(where: { $0.kind == .clarificationAsked })?.summary.nilIfBlank {
            return q
        }
        return thread.interpretation?.userQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private static func phaseLabel(display: ExchangeSecondHalfUIAdapter.DisplayModel?, inboxPhaseFallback: String) -> String {
        if let d = display {
            let candidateParts: [String?] = [
                d.stateLabel,
                d.hero.statusLine,
                d.agencyPhaseTitle,
                d.summary,
                d.subtitle,
                d.title
            ]
            let candidates = candidateParts
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for c in candidates {
                let s = sanitize(c)
                if !s.isEmpty { return s }
            }
        }
        let fb = sanitize(inboxPhaseFallback)
        return fb.isEmpty ? "Active" : fb
    }

    private static func originalRequest(
        requestCaptured: String?,
        interpretationQuestion: String?,
        threadStoredTitle: String,
        titlePickTitle: String
    ) -> String? {
        if let r = trimmedNonEmpty(requestCaptured) {
            return sanitize(r)
        }
        if let q = trimmedNonEmpty(interpretationQuestion) {
            return sanitize(q)
        }
        let t = threadStoredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return sanitize(t) }
        return sanitizeOptional(titlePickTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank)
    }

    private static func matchCard(from source: SecretaryExchangeListRowSource) -> SecretaryExchangeMatchCard? {
        let headline = source.hydrationResolvedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? source.titlePick.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty else { return nil }
        let summary = sanitizeOptional(
            source.hydrationMatchSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? source.hydrationVisibleLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
        let why = sanitizeOptional(source.matchWhy?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank)
        return SecretaryExchangeMatchCard(
            headline: sanitize(headline),
            summary: summary,
            whyItFits: why
        )
    }

    private static func matchCardForDetail(detail: ExchangeModels.ThreadDetail) -> SecretaryExchangeMatchCard? {
        let cp = detail.selectedCounterparty?.bestDisplayLine.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if let m = detail.selectedMatch {
            let reasons = m.reasons.map(\.summary).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let headline = cp ?? reasons.first.map { sanitize($0) } ?? "Match"
            let summaryParts = reasons.dropFirst().prefix(4).map { sanitize($0) }
            let summary = summaryParts.isEmpty ? nil : summaryParts.joined(separator: " · ")
            let cautionSummaries = m.cautions.map(\.summary).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let whyFromCautions = cautionSummaries.prefix(3).map { sanitize($0) }.joined(separator: " · ")
            let whyFromRecommendation = m.recommendation.map { sanitize($0) }
            let whyItFits: String?
            if !whyFromCautions.isEmpty {
                whyItFits = whyFromCautions
            } else {
                whyItFits = whyFromRecommendation
            }
            return SecretaryExchangeMatchCard(
                headline: sanitize(headline),
                summary: summary,
                whyItFits: whyItFits
            )
        }
        if let h = cp {
            return SecretaryExchangeMatchCard(headline: sanitize(h), summary: nil, whyItFits: nil)
        }
        return nil
    }

    private static func missingLines(
        display: ExchangeSecondHalfUIAdapter.DisplayModel?,
        clarificationPrompt: String?
    ) -> [String] {
        var lines: [String] = []
        if let c = trimmedNonEmpty(clarificationPrompt) {
            lines.append(sanitize(c))
        }
        guard let d = display else { return dedupeTrim(lines) }
        if let decision = d.decision {
            lines.append(contentsOf: decision.unresolvedIssues.map { sanitize($0) })
            lines.append(contentsOf: decision.tradeoffs.map { sanitize($0) })
        }
        if let nm = d.nextMove {
            lines.append(contentsOf: nm.requiredInputs.map { sanitize($0) })
        }
        if let esc = trimmedNonEmpty(d.escalationReason) {
            lines.append(sanitize(esc))
        }
        lines.append(contentsOf: d.operatingContext.userFacingMissingFacts.map { sanitize($0) })
        if let missing = d.requesterReview?.missingFacts {
            lines.append(contentsOf: missing.map { sanitize($0) })
        }
        return dedupeTrim(lines)
    }

    private static func outboundDraftCard(
        from draft: ExchangeMessageDraft?,
        display: ExchangeSecondHalfUIAdapter.DisplayModel?,
        thread: ExchangeThread
    ) -> SecretaryExchangeMessageCard? {
        guard let draft else { return nil }
        if draft.audience == .externalCounterparty {
            guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else { return nil }
        }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        var footnote: String?
        if display?.boundary.requiresHumanApproval == true || display?.nextMove?.needsApproval == true {
            footnote = "Approval required before sending"
        }
        return SecretaryExchangeMessageCard(
            roleLabel: "Draft",
            timestamp: draft.updatedAt,
            subject: draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            body: sanitize(body),
            footnote: footnote.map { sanitize($0) }
        )
    }

    private static func latestInboundCard(fromTurns turns: [ExchangeTurn]) -> SecretaryExchangeMessageCard? {
        let sorted = turns.sorted { $0.createdAt > $1.createdAt }

        func body(for turn: ExchangeTurn) -> String? {
            let d = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let s = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { return d }
            if !s.isEmpty { return s }
            return nil
        }

        for t in sorted where t.kind == .replyReceived {
            guard let raw = body(for: t).flatMap({ trimmedNonEmpty($0) }) else { continue }
            return SecretaryExchangeMessageCard(
                roleLabel: "Reply",
                timestamp: t.createdAt,
                subject: nil,
                body: sanitize(raw),
                footnote: nil
            )
        }

        for t in sorted where t.actor == .counterparty {
            guard let raw = body(for: t).flatMap({ trimmedNonEmpty($0) }) else { continue }
            return SecretaryExchangeMessageCard(
                roleLabel: "Reply",
                timestamp: t.createdAt,
                subject: nil,
                body: sanitize(raw),
                footnote: nil
            )
        }

        for t in sorted where t.actor == .relay {
            guard let raw = body(for: t).flatMap({ trimmedNonEmpty($0) }) else { continue }
            return SecretaryExchangeMessageCard(
                roleLabel: "Reply",
                timestamp: t.createdAt,
                subject: nil,
                body: sanitize(raw),
                footnote: nil
            )
        }

        return nil
    }

    private static func nextAction(
        display: ExchangeSecondHalfUIAdapter.DisplayModel?,
        nextStepText: String?
    ) -> SecretaryExchangeNextAction? {
        if let nm = display?.nextMove {
            let t = nm.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let a = nm.action.trimmingCharacters(in: .whitespacesAndNewlines)
            let primary = (!t.isEmpty ? t : a)
            guard !primary.isEmpty else { return nil }
            let rat = nm.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = rat.isEmpty ? nil : sanitize(rat)
            let requires = nm.needsApproval || nm.needsUserInput || nm.isBlockingOnHuman || (display?.needsHumanAttention ?? false)
            return SecretaryExchangeNextAction(
                primaryLine: sanitize(primary),
                detail: detail,
                requiresUser: requires
            )
        }
        if let n = trimmedNonEmpty(nextStepText) {
            return SecretaryExchangeNextAction(
                primaryLine: sanitize(n),
                detail: nil,
                requiresUser: display?.needsHumanAttention ?? false
            )
        }
        return nil
    }

    private static func workSteps(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel?,
        turns: [ExchangeTurn]
    ) -> [SecretaryExchangeWorkStep] {
        var steps: [SecretaryExchangeWorkStep] = []
        if let d = display {
            for s in d.activitySteps {
                let done = s.status == .completed
                steps.append(
                    SecretaryExchangeWorkStep(
                        title: sanitize(s.title),
                        detail: s.detail.map { sanitize($0) },
                        completed: done
                    )
                )
            }
            if steps.isEmpty {
                for item in d.timelineItems {
                    let sum = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    steps.append(
                        SecretaryExchangeWorkStep(
                            title: sanitize(item.title),
                            detail: sum.isEmpty ? nil : sanitize(sum),
                            completed: item.tone == .success
                        )
                    )
                }
            }
        }
        if steps.isEmpty {
            let sorted = turns.sorted { $0.createdAt < $1.createdAt }
            for t in sorted.prefix(12) where t.visibility.isVisibleToUserByDefault {
                let title = sanitize(t.summary)
                guard !title.isEmpty else { continue }
                let detail = t.detail.map { sanitize($0) }
                steps.append(
                    SecretaryExchangeWorkStep(
                        title: title,
                        detail: detail,
                        completed: false
                    )
                )
            }
        }
        return dedupeWorkSteps(steps)
    }

    private static func dedupeWorkSteps(_ steps: [SecretaryExchangeWorkStep]) -> [SecretaryExchangeWorkStep] {
        var seen = Set<String>()
        var out: [SecretaryExchangeWorkStep] = []
        for s in steps {
            let key = s.title.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(s)
        }
        return out
    }

    private static func dedupeTrim(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in lines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(t)
        }
        return out
    }

    private static func sanitize(_ value: String) -> String {
        stripForbiddenTokens(from: value)
    }

    private static func sanitizeOptional(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { return nil }
        let s = stripForbiddenTokens(from: v)
        return s.isEmpty ? nil : s
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    /// Strips explicit internal / log tokens only. Does not remove common English ("thread", "fallback",
    /// "second half of …", "retrieval …") unless they appear as identifier-style fragments.
    private static let forbiddenRegex: [NSRegularExpression] = {
        let idTail = "[A-Za-z0-9_.-]+"
        let patterns = [
            // secondHalf (camel / snake / hyphen token — not prose "second half of the day")
            "(?i)(?<![A-Za-z0-9])secondHalf(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])second_half(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])second-half(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])secondhalf(?![A-Za-z0-9])",

            // pass2 (token; avoid "pass 200" via trailing digit check on spaced form)
            "(?i)(?<![A-Za-z0-9])pass2(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])pass_2(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])pass-2(?![A-Za-z0-9])",

            // agencyPhase
            "(?i)(?<![A-Za-z0-9])agencyPhase(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])agency_phase(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])agency-phase(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])agencyphase(?![A-Za-z0-9])",

            // Thread id labels (not the dictionary word "thread")
            "(?i)\\bthreadID\\b",
            "(?i)\\bthreadId\\b",
            "(?i)\\bthread_id\\b",
            "(?i)thread\\s*id\\s*[:=]",
            "(?i)thread\\s*=\\s*[0-9A-Fa-f-]{8,}",

            // Fallback as log / policy key (not "a fallback option" in plain English)
            "(?i)\\bfallback(?:Mode|Policy|Path|Strategy|Reason|State|Line|Label|Plan|Key)\\b",
            "(?i)\\bfallback\\s*[:=]",

            "(?i)\\bllm\\s+accepted\\b",

            // Body hash labels (identifier-style — not prose "body hash …")
            "(?i)\\bbodyhash\\b",
            "(?i)\\bbody_hash\\b",
            "(?i)\\bbody-hash\\b",
            "(?i)(?<![A-Za-z0-9])bodyHash(?![A-Za-z0-9])",

            // Runtime mode labels
            "(?i)(?<![A-Za-z0-9])runtimeMode(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])runtime_mode(?![A-Za-z0-9])",
            "(?i)\\bruntime\\s+mode\\s*[:=]",

            // Retrieval score labels (camel / snake only — not the phrase "retrieval score" in prose)
            "(?i)(?<![A-Za-z0-9])retrievalScore(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])retrieval_score(?![A-Za-z0-9])",

            // Raw ExchangeState–style identifiers
            "(?i)(?<![A-Za-z0-9])exchangeState(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])exchange_state(?![A-Za-z0-9])",
            "(?i)(?<![A-Za-z0-9])exchangestate(?![A-Za-z0-9])",

            // Node / profile / offer id log fragments
            "(?i)\\b(?:node|profile|offer)\\s*id\\s*[:=]\\s*\(idTail)",
            "(?i)(?<![A-Za-z0-9])(?:offer|profile|node|publicProfile)(?:ID|Id)\\s*[:=]\\s*\(idTail)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    private static func stripForbiddenTokens(from value: String) -> String {
        var s = value
        for regex in forbiddenRegex {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        }
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
