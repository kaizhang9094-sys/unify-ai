import Foundation

#if DEBUG
@inline(__always)
private func exchangeBridgeLog(_ message: @autoclosure () -> String) {
    print("[ExchangeChatBridge] \(message())")
}
#else
@inline(__always)
private func exchangeBridgeLog(_ message: @autoclosure () -> String) { }
#endif

/// Bridges the primary conversation surface into Exchange.
///
/// Routing principle:
/// - active-thread commands still work explicitly
/// - obvious pure-chat stays in chat
/// - everything else defaults into Exchange for interpretation
///
/// The bridge should be permissive.
/// It is not the real meaning engine.
public struct ExchangeChatBridge: Sendable {
    private let facade: ExchangeFacade

    public init(facade: ExchangeFacade) {
        self.facade = facade
    }

    public func route(
        userText: String,
        currentThreadID: ExchangeThread.ID? = nil,
        progressContext: DiscoveryHeroProgressContext? = nil,
        now: Date = Date()
    ) async throws -> RouteResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        var last = t0

        @inline(__always)
        func mark(_ label: String) {
            #if DEBUG
            let now = CFAbsoluteTimeGetCurrent()
            let stepMs = Int((now - last) * 1000)
            let totalMs = Int((now - t0) * 1000)
            last = now
            exchangeBridgeLog("\(label) | step=\(stepMs)ms total=\(totalMs)ms")
            #endif
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        exchangeBridgeLog(
            "route begin | chars=\(trimmed.count) currentThread=\(currentThreadID?.uuidString ?? "nil")"
        )
        #endif

        guard !trimmed.isEmpty else {
            mark("route blocked empty_input")
            return .chatOnly(reason: "Empty input.")
        }

        let bridgeIntent = parseBridgeIntent(
            from: trimmed,
            currentThreadID: currentThreadID
        )

        mark("intent parsed")

        #if DEBUG
        exchangeBridgeLog(
            "intent selected | \(debugIntentSummary(bridgeIntent))"
        )
        #endif

        switch bridgeIntent {
        case .chatOnly(let reason):
            mark("route result chatOnly")
            #if DEBUG
            exchangeBridgeLog("chatOnly reason=\(reason)")
            #endif
            return .chatOnly(reason: reason)

        case .submitToExchange(let threadID, let reason):
            #if DEBUG
            exchangeBridgeLog(
                "submitToExchange begin | targetThread=\(threadID?.uuidString ?? "nil") reason=\(reason)"
            )
            #endif

            let response = try await facade.submit(
                trimmed,
                threadID: threadID,
                progressContext: progressContext,
                now: now
            )

            mark("facade.submit done")

            #if DEBUG
            exchangeBridgeLog(
                "submit response | thread=\(response.thread.id.uuidString) state=\(response.thread.state.phaseTitle) transientNonPersistent=\(response.isTransientNonPersistent) summary=\(response.summary)"
            )
            #endif

            let detail: ExchangeModels.ThreadDetail
            if response.isTransientNonPersistent {
                detail = ExchangeModels.ThreadDetail(
                    thread: response.thread,
                    turns: response.turns,
                    approvals: response.approvals,
                    drafts: response.drafts,
                    matches: response.matches,
                    counterparties: response.counterparties,
                    artifacts: response.artifacts,
                    summary: response.summary
                )
            } else {
                detail = try await facade.getThread(threadID: response.thread.id)
            }

            mark("facade.getThread done")

            #if DEBUG
            exchangeBridgeLog(
                "route return exchange | thread=\(detail.thread.id.uuidString) state=\(detail.thread.state.phaseTitle) turns=\(detail.turns.count) drafts=\(detail.drafts.count) approvals=\(detail.approvals.count)"
            )
            #endif

            return .exchange(
                response: response,
                detail: detail,
                reason: reason
            )

        case .approveCurrent(let reason):
            guard let threadID = currentThreadID else {
                mark("approveCurrent blocked no_thread")
                return .chatOnly(reason: "No active exchange thread to approve.")
            }

            #if DEBUG
            exchangeBridgeLog(
                "approveCurrent begin | thread=\(threadID.uuidString) reason=\(reason)"
            )
            #endif

            let pending = try await facade.listPendingApprovals()
            mark("facade.listPendingApprovals done")

            #if DEBUG
            exchangeBridgeLog("pending approvals fetched | count=\(pending.count)")
            #endif

            guard let item = pending.first(where: { $0.threadID == threadID }) else {
                mark("approveCurrent no_pending_for_thread")
                return .chatOnly(reason: "No pending approval exists for the current exchange thread.")
            }

            #if DEBUG
            exchangeBridgeLog(
                "approveCurrent target approval | approvalID=\(item.approval.id.uuidString)"
            )
            #endif

            let response = try await facade.approve(
                threadID: threadID,
                approvalID: item.approval.id,
                note: nil,
                now: now
            )

            mark("facade.approve done")

            #if DEBUG
            exchangeBridgeLog(
                "approve response | thread=\(response.thread.id.uuidString) state=\(response.thread.state.phaseTitle) summary=\(response.summary)"
            )
            #endif

            let detail = try await facade.getThread(threadID: response.thread.id)

            mark("facade.getThread done")

            #if DEBUG
            exchangeBridgeLog(
                "route return exchange(approve) | thread=\(detail.thread.id.uuidString) state=\(detail.thread.state.phaseTitle) turns=\(detail.turns.count) drafts=\(detail.drafts.count) approvals=\(detail.approvals.count)"
            )
            #endif

            return .exchange(
                response: response,
                detail: detail,
                reason: reason
            )

        case .rejectCurrent(let reason):
            guard let threadID = currentThreadID else {
                mark("rejectCurrent blocked no_thread")
                return .chatOnly(reason: "No active exchange thread to reject.")
            }

            #if DEBUG
            exchangeBridgeLog(
                "rejectCurrent begin | thread=\(threadID.uuidString) reason=\(reason)"
            )
            #endif

            let pending = try await facade.listPendingApprovals()
            mark("facade.listPendingApprovals done")

            #if DEBUG
            exchangeBridgeLog("pending approvals fetched | count=\(pending.count)")
            #endif

            guard let item = pending.first(where: { $0.threadID == threadID }) else {
                mark("rejectCurrent no_pending_for_thread")
                return .chatOnly(reason: "No pending approval exists for the current exchange thread.")
            }

            #if DEBUG
            exchangeBridgeLog(
                "rejectCurrent target approval | approvalID=\(item.approval.id.uuidString)"
            )
            #endif

            let response = try await facade.reject(
                threadID: threadID,
                approvalID: item.approval.id,
                note: nil,
                now: now
            )

            mark("facade.reject done")

            #if DEBUG
            exchangeBridgeLog(
                "reject response | thread=\(response.thread.id.uuidString) state=\(response.thread.state.phaseTitle) summary=\(response.summary)"
            )
            #endif

            let detail = try await facade.getThread(threadID: response.thread.id)

            mark("facade.getThread done")

            #if DEBUG
            exchangeBridgeLog(
                "route return exchange(reject) | thread=\(detail.thread.id.uuidString) state=\(detail.thread.state.phaseTitle) turns=\(detail.turns.count) drafts=\(detail.drafts.count) approvals=\(detail.approvals.count)"
            )
            #endif

            return .exchange(
                response: response,
                detail: detail,
                reason: reason
            )

        case .threadStatus(let reason):
            guard let threadID = currentThreadID else {
                mark("threadStatus blocked no_thread")
                return .chatOnly(reason: "No active exchange thread.")
            }

            #if DEBUG
            exchangeBridgeLog(
                "threadStatus begin | thread=\(threadID.uuidString) reason=\(reason)"
            )
            #endif

            let detail = try await facade.getThread(threadID: threadID)
            mark("facade.getThread done")

            #if DEBUG
            exchangeBridgeLog(
                "route return threadDetail | thread=\(detail.thread.id.uuidString) state=\(detail.thread.state.phaseTitle) turns=\(detail.turns.count) drafts=\(detail.drafts.count) approvals=\(detail.approvals.count)"
            )
            #endif

            return .threadDetail(
                detail: detail,
                reason: reason
            )
        }
    }
}

public extension ExchangeChatBridge {
    enum RouteResult: Sendable {
        case chatOnly(reason: String)
        case exchange(
            response: ExchangeOrchestrator.Response,
            detail: ExchangeModels.ThreadDetail,
            reason: String
        )
        case threadDetail(detail: ExchangeModels.ThreadDetail, reason: String)
    }
}

private extension ExchangeChatBridge {
    enum BridgeIntent: Sendable {
        case chatOnly(reason: String)
        case submitToExchange(threadID: ExchangeThread.ID?, reason: String)
        case approveCurrent(reason: String)
        case rejectCurrent(reason: String)
        case threadStatus(reason: String)
    }

    func debugIntentSummary(_ intent: BridgeIntent) -> String {
        switch intent {
        case .chatOnly(let reason):
            return "chatOnly reason=\(reason)"
        case .submitToExchange(let threadID, let reason):
            return "submitToExchange threadID=\(threadID?.uuidString ?? "nil") reason=\(reason)"
        case .approveCurrent(let reason):
            return "approveCurrent reason=\(reason)"
        case .rejectCurrent(let reason):
            return "rejectCurrent reason=\(reason)"
        case .threadStatus(let reason):
            return "threadStatus reason=\(reason)"
        }
    }

    func shouldStartFreshExchangeThread(_ lower: String) -> Bool {
        let strongNewRequestSignals = [
            "find me",
            "look for",
            "search for",
            "source",
            "help me find",
            "help me contact",
            "can you find",
            "can you contact",
            "introduce me",
            "set up a call",
            "set up a meeting",
            "arrange",
            "draft me",
            "draft an outreach",
            "draft a message",
            "write a message",
            "write an email",
            "request a quote",
            "want to buy",
            "looking to buy",
            "need a ",
            "need an ",
            "get a ",
            "get an "
        ]

        if strongNewRequestSignals.contains(where: { lower.contains($0) }) {
            return true
        }

        let continuationSignals = [
            "send it",
            "approve",
            "reject",
            "revise",
            "rewrite",
            "shorten",
            "make it",
            "change it",
            "follow up",
            "check status",
            "use the second one",
            "message the first one",
            "try again"
        ]

        if continuationSignals.contains(where: { lower.contains($0) }) {
            return false
        }

        return false
    }
    
    func parseBridgeIntent(
        from text: String,
        currentThreadID: ExchangeThread.ID?
    ) -> BridgeIntent {
        let lower = text.lowercased()
        let normalized = normalizeCommandText(lower)

        if let currentThreadID {
            if isApprovalCommand(normalized) {
                return .approveCurrent(reason: "Explicit approval command inside current exchange thread.")
            }

            if isRejectionCommand(normalized) {
                return .rejectCurrent(reason: "Explicit rejection command inside current exchange thread.")
            }

            if isStatusCommand(normalized) {
                return .threadStatus(reason: "Explicit status request for current exchange thread.")
            }

            if shouldStayChatOnlyInsideActiveThread(normalized) {
                return .chatOnly(reason: "Message appears conversational rather than exchange-related.")
            }

            if shouldStartFreshExchangeThread(normalized) {
                return .submitToExchange(
                    threadID: nil,
                    reason: "Message appears to be a new exchange request, not a continuation of the active thread."
                )
            }

            return .submitToExchange(
                threadID: currentThreadID,
                reason: "Message appears to continue the active exchange thread."
            )
        }

        if isDefinitelyChatOnlyOutsideThread(normalized) {
            return .chatOnly(reason: "Message appears conversational rather than coordination-related.")
        }

        return .submitToExchange(
            threadID: nil,
            reason: explicitExchangeSignalReason(for: normalized)
        )
    }

    func explicitExchangeSignalReason(for lower: String) -> String {
        if shouldStartExchange(for: lower) {
            return "Message explicitly suggests coordination intent."
        }
        return "Secretary mode defaults non-chat requests into Exchange for interpretation."
    }

    func shouldStartExchange(for lower: String) -> Bool {
        let strongSignals = [
            "find me",
            "look for",
            "source",
            "get me",
            "request a quote",
            "quote",
            "reach out",
            "contact",
            "message them",
            "send this",
            "introduce me",
            "set up a call",
            "set up a meeting",
            "follow up",
            "check status",
            "invite",
            "coordinate",
            "arrange",
            "help me find",
            "help me contact",
            "help me reach out",
            "can you find",
            "can you contact",
            "can you arrange"
        ]

        if strongSignals.contains(where: { lower.contains($0) }) {
            return true
        }

        let weakerActionSignals = [
            "contractor",
            "supplier",
            "vendor",
            "manufacturer",
            "meeting",
            "call",
            "intro",
            "introduction",
            "service provider",
            "quote",
            "pricing",
            "roofer",
            "plumber",
            "electrician",
            "lawyer",
            "accountant",
            "builder",
            "designer",
            "installer",
            "repair",
            "hire"
        ]

        let weakCount = weakerActionSignals.reduce(into: 0) { partial, token in
            if lower.contains(token) {
                partial += 1
            }
        }

        return weakCount >= 2
    }

    func shouldStayChatOnlyInsideActiveThread(_ lower: String) -> Bool {
        let exactChatSignals = Set([
            "hi",
            "hey",
            "hello",
            "good morning",
            "good afternoon",
            "good evening",
            "good night",
            "how are you",
            "who are you",
            "tell me a joke",
            "thanks",
            "thank you",
            "no worries",
            "ok",
            "okay",
            "cool"
        ])

        if exactChatSignals.contains(lower) {
            return true
        }

        let clearChatPrefixes = [
            "tell me about",
            "what do you think",
            "do you like",
            "can i ask you something unrelated"
        ]

        return clearChatPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    func isDefinitelyChatOnlyOutsideThread(_ lower: String) -> Bool {
        let exactChatSignals = Set([
            "hi",
            "hey",
            "hello",
            "good morning",
            "good afternoon",
            "good evening",
            "good night",
            "how are you",
            "who are you",
            "tell me a joke",
            "thanks",
            "thank you",
            "no worries",
            "ok",
            "okay",
            "cool",
            "nice",
            "sounds good"
        ])

        if exactChatSignals.contains(lower) {
            return true
        }

        let clearChatPrefixes = [
            "tell me about",
            "what do you think about",
            "what do you think of",
            "do you like",
            "can i ask you something unrelated",
            "what is",
            "who is",
            "explain",
            "summarize",
            "recommend me a movie",
            "recommend a movie",
            "write me a poem",
            "tell me a story"
        ]

        return clearChatPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    func isApprovalCommand(_ lower: String) -> Bool {
        let commands = Set([
            "approve",
            "approved",
            "approve this",
            "yes send it",
            "send it",
            "looks good",
            "go ahead"
        ])
        return commands.contains(lower)
    }

    func isRejectionCommand(_ lower: String) -> Bool {
        let commands = Set([
            "reject",
            "reject this",
            "decline",
            "don't send",
            "do not send",
            "cancel this"
        ])
        return commands.contains(lower)
    }

    func isStatusCommand(_ lower: String) -> Bool {
        let commands = Set([
            "status",
            "show status",
            "thread status",
            "show thread",
            "show exchange",
            "what's the status",
            "what is the status",
            "where is this at"
        ])
        return commands.contains(lower)
    }

    func normalizeCommandText(_ lower: String) -> String {
        lower
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\.\,\!\?\:\;]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
