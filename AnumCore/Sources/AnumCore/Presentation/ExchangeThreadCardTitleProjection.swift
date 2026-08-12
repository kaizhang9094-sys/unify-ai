import Foundation

/// User-facing title / subtitle selection for Secretary / Discovery cards (read paths only).
///
/// Callers keep durable `ExchangeThread.title` unchanged; this layer picks what cards should show.
public enum ExchangeThreadCardTitleProjection: Sendable {

    // MARK: - Request capture (turn-backed)

    /// First `requestCaptured` turn text — same semantics as `ExchangeFacade.capturedRequestText(from:)`.
    public static func requestCapturedText(from turns: [ExchangeTurn]) -> String? {
        guard let turn = turns.first(where: { $0.kind == .requestCaptured }) else {
            return nil
        }

        let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }

        let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    /// Latest user `requestCaptured` turn — umbrella search list titles on reused workbenches.
    public static func latestRequestCapturedText(from turns: [ExchangeTurn]) -> String? {
        let userTurns = turns.filter { $0.kind == .requestCaptured && $0.actor == .user }
        let selectedTurn: ExchangeTurn? = {
            if let latestUser = userTurns.max(by: { $0.createdAt < $1.createdAt }) {
                return latestUser
            }
            return turns.filter { $0.kind == .requestCaptured }.max(by: { $0.createdAt < $1.createdAt })
        }()
        guard let turn = selectedTurn else { return nil }

        let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }

        let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    // MARK: - Title

    public struct TitlePick: Sendable {
        public var title: String
        public var titleSource: String
        public var rawRejected: String?

        public init(title: String, titleSource: String, rawRejected: String?) {
            self.title = title
            self.titleSource = titleSource
            self.rawRejected = rawRejected
        }
    }

    /// Primary card title for inbox / desk surfaces (never second-half machine titles).
    public static func inboxCardTitle(
        requestCapturedFromTurn: String?,
        interpretationUserQuestion: String?,
        threadStoredTitle: String,
        draftedSubject: String?,
        hydratedOpportunityTitle: String?,
        prioritizeHydratedOpportunityTitle: Bool,
        threadID: UUID?,
        surface: String,
        fallback: String = "New request"
    ) -> TitlePick {
        func pick(_ raw: String?, source: String) -> TitlePick? {
            guard let trimmed = Self.nonEmptyTrimmed(raw) else {
                return nil
            }
            if shouldRejectTitleCandidate(trimmed) {
                return nil
            }
            let cleaned = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                trimmed,
                field: .title,
                fallback: fallback
            )
            let clipped = clipTitle(cleaned)
            return TitlePick(title: clipped, titleSource: source, rawRejected: nil)
        }

        let result: TitlePick = {
            if prioritizeHydratedOpportunityTitle, let p = pick(hydratedOpportunityTitle, source: "hydratedOpportunity") {
                return p
            }

            if let p = pick(requestCapturedFromTurn, source: "capturedRequest") { return p }

            if let q = Self.nonEmptyTrimmed(interpretationUserQuestion),
               !q.lowercased().hasPrefix("i understood this as"),
               let p = pick(q, source: "interpretationQuestion") {
                return p
            }

            if let p = pick(draftedSubject, source: "draftSubject") { return p }

            if let p = pick(threadStoredTitle, source: "threadTitle") { return p }

            if !prioritizeHydratedOpportunityTitle, let p = pick(hydratedOpportunityTitle, source: "hydratedOpportunity") {
                return p
            }

            return TitlePick(title: fallback, titleSource: "fallback", rawRejected: nil)
        }()

        logProjection(
            surface: surface,
            threadID: threadID,
            titleSource: result.titleSource,
            rawRejected: nil,
            finalTitle: result.title,
            subtitle: "(title)"
        )
        return result
    }

    /// Latest counterparty inbound ask from `replyReceived` turns (provider card / header titles).
    public static func latestInboundRequesterAsk(from turns: [ExchangeTurn]) -> String? {
        let replies = turns.filter { $0.kind == .replyReceived }
        guard let last = replies.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        if let detailRaw = last.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detailRaw.isEmpty {
            return String(detailRaw.prefix(220))
        }
        let summary = last.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return String(summary.prefix(220))
    }

    /// Provider-side inbound federation desk (`metadata.inbound_thread == true`).
    public static func isProviderInboundThread(metadata: [String: String]) -> Bool {
        metadata["inbound_thread"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "true"
    }

    /// Humanized title for inbound federation provider threads — inquiry subject, not lifecycle/status copy.
    public static func inboundProviderInquiryTitlePick(
        inboundRequesterAsk: String? = nil,
        inquirySummary: String? = nil,
        hydratedOpportunityTitle: String?,
        inboundSenderDisplay: String?,
        threadStoredTitle: String,
        threadID: UUID?,
        surface: String
    ) -> TitlePick {
        let fallback = "New inquiry"

        func rejectSender(_ raw: String) -> Bool {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            if shouldRejectTitleCandidate(trimmed) { return true }
            return looksLikeRawNodeTitle(trimmed.lowercased())
        }

        func pick(_ raw: String?, source: String) -> TitlePick? {
            guard let trimmed = Self.nonEmptyTrimmed(raw) else { return nil }
            if shouldRejectTitleCandidate(trimmed) { return nil }
            if isProviderInboundTemplateCopy(trimmed) { return nil }
            let cleaned = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                trimmed,
                field: .title,
                fallback: fallback
            )
            let clipped = clipTitle(cleaned)
            guard !clipped.isEmpty else { return nil }
            return TitlePick(title: clipped, titleSource: source, rawRejected: nil)
        }

        let result: TitlePick = {
            if let p = pick(inboundRequesterAsk, source: "inboundRequesterAsk") { return p }
            if let p = pick(inquirySummary, source: "inquirySummary") { return p }
            if let p = pick(hydratedOpportunityTitle, source: "inboundInquiryHydrated") { return p }
            if let sender = Self.nonEmptyTrimmed(inboundSenderDisplay), !rejectSender(sender) {
                if let p = pick("Inquiry from \(sender)", source: "inboundSenderDisplay") { return p }
            }
            return TitlePick(title: fallback, titleSource: "fallback", rawRejected: threadStoredTitle)
        }()

        logProjection(
            surface: surface,
            threadID: threadID,
            titleSource: result.titleSource,
            rawRejected: result.rawRejected,
            finalTitle: result.title,
            subtitle: "(title)"
        )
        return result
    }

    /// Title for an inbox row after `ExchangeFacade.listThreads` has populated `title` / `capturedRequestText`.
    public static func displayTitleForInboxItem(
        _ item: ExchangeModels.InboxItem,
        surface: String = "threads"
    ) -> TitlePick {
        if item.isInboundProviderDesk || item.prefersInboundProviderCardTitleRewrite {
            let inquirySummary = item.secondHalfDisplay?.providerReception?.inquirySummary
                ?? item.secondHalfDisplay?.providerReception?.requesterAsk
            return inboundProviderInquiryTitlePick(
                inboundRequesterAsk: item.cardInboundRequesterPreview,
                inquirySummary: inquirySummary,
                hydratedOpportunityTitle: item.selectedCounterpartyName,
                inboundSenderDisplay: item.cardInboundSenderLabel,
                threadStoredTitle: item.title,
                threadID: item.threadID,
                surface: surface
            )
        }

        /// `listThreads` mirrors hydrated offer/profile headline into `selectedCounterpartyName` when helpful.
        let headlineTrimmed = item.selectedCounterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hydratedHeadline: String? = headlineTrimmed.isEmpty ? nil : headlineTrimmed
        let shouldPrioritizeHydratedOpportunityTitle: Bool = {
            switch item.state {
            case .matchFound:
                return item.selectedOfferID != nil || item.selectedPublicProfileID != nil || item.selectedCounterpartyID != nil
            default:
                return false
            }
        }()

        return inboxCardTitle(
            requestCapturedFromTurn: item.capturedRequestText,
            interpretationUserQuestion: item.interpretationQuestion,
            threadStoredTitle: item.title,
            draftedSubject: item.draftedSubject,
            hydratedOpportunityTitle: hydratedHeadline,
            prioritizeHydratedOpportunityTitle: shouldPrioritizeHydratedOpportunityTitle,
            threadID: item.threadID,
            surface: surface
        )
    }

    #if DEBUG
    /// Inbox federation rows use a separate title pick path; share the same DEBUG dedupe gate as card titles.
    public static func logInboundInboxTitleIfChanged(
        threadID: UUID?,
        titleSource: String,
        finalTitle: String
    ) {
        logProjection(
            surface: "inbound",
            threadID: threadID,
            titleSource: titleSource,
            rawRejected: nil,
            finalTitle: finalTitle,
            subtitle: "n/a"
        )
    }
    #endif

    /// Thread header / detail hero title from durable thread + turns + draft.
    public static func threadHeaderTitle(
        requestCapturedFromTurn: String?,
        interpretationUserQuestion: String?,
        threadStoredTitle: String,
        draftedSubject: String?,
        hydratedOpportunityTitle: String?,
        threadID: UUID?,
        surface: String = "detail",
        fallback: String = "New request",
        isProviderInbound: Bool = false,
        inboundRequesterAsk: String? = nil,
        inquirySummary: String? = nil,
        inboundSenderDisplay: String? = nil
    ) -> TitlePick {
        if isProviderInbound {
            return inboundProviderInquiryTitlePick(
                inboundRequesterAsk: inboundRequesterAsk,
                inquirySummary: inquirySummary,
                hydratedOpportunityTitle: hydratedOpportunityTitle,
                inboundSenderDisplay: inboundSenderDisplay,
                threadStoredTitle: threadStoredTitle,
                threadID: threadID,
                surface: surface
            )
        }
        return inboxCardTitle(
            requestCapturedFromTurn: requestCapturedFromTurn,
            interpretationUserQuestion: interpretationUserQuestion,
            threadStoredTitle: threadStoredTitle,
            draftedSubject: draftedSubject,
            hydratedOpportunityTitle: hydratedOpportunityTitle,
            prioritizeHydratedOpportunityTitle: false,
            threadID: threadID,
            surface: surface,
            fallback: fallback
        )
    }

    // MARK: - Subtitle

    /// `primaryStatusLine` must be the façade’s canonical status headline (e.g. `InboxItem.stateTitle` / `inboxStateTitle`), not a second projection pass.
    public static func inboxCardSubtitle(
        primaryTitle: String,
        primaryStatusLine: String,
        deliveryStatusText: String?,
        outcomeStatusText: String?,
        opportunityShortLine: String?,
        requesterMessagePreview: String? = nil,
        threadID: UUID?,
        surface: String
    ) -> String {
        var pieces: [String] = [primaryStatusLine]

        if let r = Self.nonEmptyTrimmed(requesterMessagePreview),
           !shouldRejectSubtitleCandidate(r),
           !primaryTitle.localizedCaseInsensitiveContains(r),
           !primaryStatusLine.localizedCaseInsensitiveContains(r) {
            pieces.append(r)
        }

        if let d = Self.nonEmptyTrimmed(deliveryStatusText),
           !shouldRejectSubtitleCandidate(d),
           !primaryTitle.localizedCaseInsensitiveContains(d) {
            pieces.append(d)
        }

        if let o = Self.nonEmptyTrimmed(outcomeStatusText),
           !shouldRejectSubtitleCandidate(o),
           !primaryTitle.localizedCaseInsensitiveContains(o) {
            pieces.append(o)
        }

        if let opp = Self.nonEmptyTrimmed(opportunityShortLine),
           !shouldRejectSubtitleCandidate(opp),
           !primaryTitle.localizedCaseInsensitiveContains(opp) {
            pieces.append(ExchangeUserFacingCopySanitizer.sanitizeOrFallback(opp, field: .subtitle, fallback: ""))
        }

        let joined = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        let final = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            joined,
            field: .subtitle,
            fallback: primaryStatusLine
        )

        #if DEBUG
        logProjection(
            surface: surface,
            threadID: threadID,
            titleSource: "subtitle",
            rawRejected: nil,
            finalTitle: primaryTitle,
            subtitle: final
        )
        #endif
        return final
    }

    public static func inboxCardSubtitle(
        for item: ExchangeModels.InboxItem,
        primaryTitle: String,
        surface: String = "threads"
    ) -> String {
        let opp = Self.nonEmptyTrimmed(item.visibleSummary)
        let stateLine = item.stateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return inboxCardSubtitle(
            primaryTitle: primaryTitle,
            primaryStatusLine: stateLine.isEmpty ? primaryTitle : stateLine,
            deliveryStatusText: item.deliveryStatusText,
            outcomeStatusText: item.outcomeStatusText,
            opportunityShortLine: opp,
            requesterMessagePreview: item.cardInboundRequesterPreview,
            threadID: item.threadID,
            surface: surface
        )
    }

    // MARK: - Internals

    private static func nonEmptyTrimmed(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clipTitle(_ line: String) -> String {
        let maxLen = 120
        guard line.count > maxLen else { return line }
        let idx = line.index(line.startIndex, offsetBy: maxLen - 1)
        return String(line[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Route/classifier titles from `ExchangeInterpreter.buildTitle` — not user-facing request wording.
    private static let interpreterRouteClassifierTitles: Set<String> = [
        "find provider",
        "find offer",
        "find capability match",
        "find collaboration match",
        "find shared-interest match",
        "find shared interest match",
        "find relationship match",
        "send message",
        "follow up",
        "check status",
        "continue message",
        "find match",
        "search",
        "find",
        "request"
    ]

    /// Title/projection-only: lifecycle and status headlines must not become primary card titles.
    public static func isExchangeLifecycleStatusTitle(_ raw: String) -> Bool {
        let normalized = normalizedLifecycleTitleKey(raw)
        guard !normalized.isEmpty else { return false }

        let exactMatches: Set<String> = [
            "response received",
            "counterparty is asking for additional information",
            "message sent waiting for a response",
            "approval granted preparing to send",
            "approval granted ready to send",
            "sending ready to send",
            "waiting for reply",
            "outbound coordination confirmed"
        ]
        if exactMatches.contains(normalized) { return true }

        if normalized.hasPrefix("approval granted") { return true }
        if normalized.hasPrefix("message sent") && normalized.contains("waiting") { return true }
        if normalized.hasPrefix("sending") && normalized.contains("ready to send") { return true }

        return false
    }

    public static func shouldRejectTitleCandidate(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }

        if isExchangeLifecycleStatusTitle(raw) {
            return true
        }

        if ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(raw) {
            return true
        }

        if interpreterRouteClassifierTitles.contains(lower) {
            return true
        }

        let needles = [
            "i understood this as",
            "provider-facing search",
            "requester-facing search",
            "understanding request",
            "reviewable path",
            "path surfaced",
            "no path",
            "waiting for reply",
            "decision frame",
            "provider reception",
            "inbound message",
            "inbound message from",
            "selected counterparty",
            "filed",
            "linked thread",
            "matchfound",
            "providerreception",
            "framedecision",
            "found path",
            "path found",
            "weak paths",
            "draft grounded on published facts:",
            "response-response-inbound",
            "response — inbound message from node",
            "response - inbound message from node",
            "inbound message from node-",
            "hi node-"
        ]

        for n in needles where lower.contains(n) {
            return true
        }

        if looksLikeRawNodeTitle(lower) { return true }

        return false
    }

    private static func shouldRejectSubtitleCandidate(_ raw: String) -> Bool {
        shouldRejectTitleCandidate(raw)
    }

    private static func looksLikeRawNodeTitle(_ lower: String) -> Bool {
        if lower.hasPrefix("node-") && lower.count <= 48 { return true }
        if lower.range(of: #"^node-[a-z0-9-]{8,}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func normalizedLifecycleTitleKey(_ title: String) -> String {
        let collapsed = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .lowercased()
        let alnumAndSpace = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = collapsed.unicodeScalars
            .filter { alnumAndSpace.contains($0) }
            .map { Character($0) }
        return String(stripped)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inbound-create template objective — not an inquiry subject line.
    private static func isProviderInboundTemplateCopy(_ raw: String) -> Bool {
        let normalized = normalizedLifecycleTitleKey(raw)
        if normalized.hasPrefix("review and respond to the inbound") { return true }
        if normalized == "review and respond to the inbound message" { return true }
        return false
    }

    #if DEBUG
    private enum TitleProjectionLogGate {
        static let lock = NSLock()
        nonisolated(unsafe) static var lastSignatureByKey: [String: String] = [:]
    }

    private static func logProjection(
        surface: String,
        threadID: UUID?,
        titleSource: String,
        rawRejected: String?,
        finalTitle: String,
        subtitle: String
    ) {
        let tid = threadID.map { $0.uuidString } ?? "nil"
        let rej = rawRejected.map { $0.replacingOccurrences(of: "\n", with: " ") } ?? "nil"
        let oneLineTitle = finalTitle.replacingOccurrences(of: "\n", with: " ")
        let oneLineSubtitle = subtitle.replacingOccurrences(of: "\n", with: " ")
        let key = "\(tid)|\(surface)|\(titleSource)"
        let signature = "\(rej)|\(oneLineTitle)|\(oneLineSubtitle)"

        TitleProjectionLogGate.lock.lock()
        if TitleProjectionLogGate.lastSignatureByKey[key] == signature {
            TitleProjectionLogGate.lock.unlock()
            return
        }
        TitleProjectionLogGate.lastSignatureByKey[key] = signature
        if TitleProjectionLogGate.lastSignatureByKey.count > 400 {
            TitleProjectionLogGate.lastSignatureByKey.removeAll(keepingCapacity: true)
        }
        TitleProjectionLogGate.lock.unlock()

        Swift.print(
            "[SecretaryTitleProjection] changed=true thread=\(tid) surface=\(surface) titleSource=\(titleSource) rawRejected=\(rej) finalTitle=\(oneLineTitle) subtitle=\(oneLineSubtitle)"
        )
        let loweredRaw = rej.lowercased()
        let loweredFinal = oneLineTitle.lowercased() + " " + oneLineSubtitle.lowercased()
        let removedInternalScaffold = loweredRaw.contains("draft grounded on published facts")
            || loweredRaw.contains("inbound message from node")
            || loweredRaw.contains("response-response-inbound")
            || loweredFinal != loweredRaw
        Swift.print(
            "[TitleProjectionClean] surface=\(surface) thread=\(tid) removedInternalScaffold=\(removedInternalScaffold) rawPrefix=\(String(rej.prefix(120))) finalPrefix=\(String(oneLineTitle.prefix(120)))"
        )
    }
    #else
    private static func logProjection(
        surface: String,
        threadID: UUID?,
        titleSource: String,
        rawRejected: String?,
        finalTitle: String,
        subtitle: String
    ) {}
    #endif
}

private extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
