import Foundation

public struct OnDeviceExchangeIntelligenceProvider: ExchangeIntelligenceProvider, Sendable {
    private let runner: any ExchangeIntelligenceModelRunner
    private let fallback: ExchangeFallbackIntelligenceProvider

    public init(
        runner: any ExchangeIntelligenceModelRunner,
        fallback: ExchangeFallbackIntelligenceProvider = ExchangeFallbackIntelligenceProvider()
    ) {
        self.runner = runner
        self.fallback = fallback
    }

    /// Lightweight bridge for requester clarification rewrite.
    /// Keeps rewrite on the existing on-device model runner path.
    public func rewriteRequesterClarificationDraft(
        packet: RequesterClarificationDraftPacket,
        deterministicBaseDraft: String
    ) async -> ExchangeAgencyDraftRewriteResult {
        await ExchangeAgencyDraftRewriteEngine.rewriteRequesterClarification(
            packet: packet,
            deterministicBaseDraft: deterministicBaseDraft,
            runner: runner
        )
    }

    /// Lightweight bridge for provider response rewrite.
    /// Keeps rewrite on the existing on-device model runner path.
    public func rewriteProviderResponseDraft(
        packet: ProviderResponseDraftPacket,
        deterministicBaseDraft: String
    ) async -> ExchangeAgencyDraftRewriteResult {
        await ExchangeAgencyDraftRewriteEngine.rewriteProviderResponse(
            packet: packet,
            deterministicBaseDraft: deterministicBaseDraft,
            runner: runner
        )
    }

    /// Full LLM composition for requester autonomous outbound (Pass-2 packet).
    public func composeRequesterAutonomousOutbound(
        packet: RequesterClarificationDraftPacket
    ) async -> ExchangeAgencyDraftRewriteEngine.ExchangeAgencyAutonomousComposeResult {
        await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
            packet: packet,
            runner: runner
        )
    }

    /// Full LLM composition for provider autonomous outbound (Pass-2 packet).
    public func composeProviderAutonomousOutbound(
        packet: ProviderResponseDraftPacket
    ) async -> ExchangeAgencyDraftRewriteEngine.ExchangeAgencyAutonomousComposeResult {
        await ExchangeAgencyDraftRewriteEngine.composeProviderAutonomousOutbound(
            packet: packet,
            runner: runner
        )
    }

    /// LLM-first gap analysis: original request vs matched offer/profile surface.
    public func compareRequesterMatchToSurface(
        originalRequesterMessage: String,
        selectedOfferSummary: String?,
        selectedProfileSummary: String?,
        counterpartyDisplayName: String?,
        knownFacts: [String],
        styleProfile: ExchangeSecretaryStyleProfile,
        requesterRequirementsSummary: String? = nil
    ) async -> ExchangeRequesterMatchCompareResult {
        let prompt = ExchangeIntelligencePromptBuilder.requesterMatchComparePrompt(
            originalRequesterMessage: originalRequesterMessage,
            selectedOfferSummary: selectedOfferSummary,
            selectedProfileSummary: selectedProfileSummary,
            counterpartyDisplayName: counterpartyDisplayName,
            knownFacts: knownFacts,
            styleProfile: styleProfile,
            requesterRequirementsSummary: requesterRequirementsSummary
        )
        #if DEBUG
        await RequesterGapSmokeAuditDebugTrace.shared.recordPrompt(prompt)
        let styleSource = styleProfile.isNonDefaultProfile ? "userDefined" : "default"
        print(
            "[RequesterCompare] styleSource=\(styleSource) typedStyleInPrompt=true styleSupplementInRunner=false"
        )
        #endif
        do {
            let raw = try await runner.run(
                .init(
                    task: .requesterMatchCompare,
                    prompt: prompt,
                    maxTokens: 420,
                    representationSupplement: nil
                )
            )
            #if DEBUG
            await RequesterGapSmokeAuditDebugTrace.shared.recordRaw(raw)
            #endif
            let cleaned = Self.cleanJSON(raw)
            let dto = try JSONDecoder().decode(
                RequesterMatchCompareDTO.self,
                from: Data(cleaned.utf8)
            )
            let mapped = mapRequesterMatchCompareDTO(dto)
            #if DEBUG
            await RequesterGapSmokeAuditDebugTrace.shared.recordRawParsedProviderQuestions(
                mapped.providerQuestions
            )
            #endif
            let evidenceHaystack = Self.requesterMatchEvidenceHaystack(
                offerSummary: selectedOfferSummary,
                profileSummary: selectedProfileSummary,
                knownFacts: knownFacts
            )
            return ExchangeRequesterMatchCompareOutputGuard.sanitize(
                mapped,
                matchedEvidenceHaystack: evidenceHaystack,
                originalRequesterMessage: originalRequesterMessage,
                requesterRequirementsSummary: requesterRequirementsSummary
            )
        } catch {
            return ExchangeRequesterMatchCompareResult(
                missingFacts: [],
                providerQuestions: [],
                shouldAskProvider: false,
                reason: "requester_match_compare_failed: \(error.localizedDescription)"
            )
        }
    }

    /// Provider-native inbound intent extraction (replaces `classifyIntentFast` `.providerInboundAsk`).
    public func extractProviderInboundIntent(
        _ request: ProviderInboundIntentExtractionRequest
    ) async throws -> ProviderInboundIntentExtraction {
        let prompt = ProviderInboundIntentExtractionPromptBuilder.prompt(for: request)
        let raw = try await runner.run(
            .init(
                task: .providerInboundIntentExtraction,
                prompt: prompt,
                maxTokens: ExchangeIntelligenceTaskTokenBudget.providerInboundIntentExtractionMaxTokens
            )
        )
        let cleaned = Self.cleanJSON(raw)
        do {
            return try ProviderInboundIntentExtractor.decode(
                cleanedJSON: cleaned,
                rawRequesterAsk: request.rawRequesterAsk
            )
        } catch {
            throw ProviderInboundIntentExtractionFailure.decodeFailed(
                ProviderInboundIntentExtractionDecodeDetails(
                    underlyingDescription: String(describing: error),
                    rawCharacterCount: raw.count,
                    cleanedCharacterCount: cleaned.count
                )
            )
        }
    }

    /// LLM-first inquiry vs seller surface; used to tighten autonomous reply gating (no fabrication).
    public func compareProviderInquiryVsOffer(
        inboundInquiry: String,
        offerSummary: String?,
        profileSummary: String?,
        operatingMemorySummary: String,
        styleProfile: ExchangeSecretaryStyleProfile,
        consentAutomationSummary: String? = nil,
        sellerControlledFacts: String = "",
        queryIntentClass: String,
        surfacePreference: String,
        primaryOpportunitySurface: String,
        selectedProfileID: String?,
        selectedOfferID: String?,
        allowedFactBlocksMetadata: String? = nil,
        inboundIntentContext: ProviderInboundIntentExtraction? = nil
    ) async -> ExchangeProviderInquiryCompareResult {
        // TODO(TestFlight/public release): Full raw/clean providerInquiryCompare logs below are for private DEBUG testing only — remove or clip before shipping to external testers or production.
        #if DEBUG
        let freeformRaw = styleProfile.freeformInstructions ?? ""
        let freeformTrim = freeformRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ProviderInquiryCompare][styleInput]")
        print("typedStyleIsDefault=\(!styleProfile.isNonDefaultProfile)")
        print(
            "typedStyle=tone=\(styleProfile.tone.rawValue) warmthDirectness=\(styleProfile.warmthDirectness.rawValue) firmness=\(styleProfile.firmness.rawValue) disclosure=\(styleProfile.disclosureStyle.rawValue) initiative=\(styleProfile.initiativeLevel.rawValue) negotiation=\(styleProfile.negotiationStyle.rawValue) approvalSensitivity=\(styleProfile.approvalSensitivity.rawValue)"
        )
        print("freeformStyleIsEmpty=\(freeformTrim.isEmpty)")
        print("freeformStyle=\(freeformRaw)")
        #endif

        let prompt = ExchangeIntelligencePromptBuilder.providerInquiryComparePrompt(
            inboundInquiry: inboundInquiry,
            offerSummary: offerSummary,
            profileSummary: profileSummary,
            operatingMemorySummary: operatingMemorySummary,
            styleProfile: styleProfile,
            consentAutomationSummary: consentAutomationSummary,
            sellerControlledFacts: sellerControlledFacts,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            primaryOpportunitySurface: primaryOpportunitySurface,
            selectedProfileID: selectedProfileID,
            selectedOfferID: selectedOfferID,
            allowedFactBlocksMetadata: allowedFactBlocksMetadata,
            inboundIntentContext: inboundIntentContext
        )
        do {
            let raw = try await runner.run(
                .init(
                    task: .providerInquiryCompare,
                    prompt: prompt,
                    maxTokens: ExchangeIntelligenceTaskTokenBudget.providerInquiryCompareMaxTokens,
                    representationSupplement: nil
                )
            )
            #if DEBUG
            print("[ProviderInquiryCompare][rawOutput][begin]")
            print(raw)
            print("[ProviderInquiryCompare][rawOutput][end]")
            #endif

            switch ProviderInquiryCompareJSONCodec.decode(
                raw: raw,
                inboundIntent: inboundIntentContext,
                requesterAskFallback: inboundInquiry
            ) {
            case .failure(let reason):
                let stripped = ProviderInquiryCompareJSONCodec.stripJSONCodeFences(raw)
                let candidateCount = ProviderInquiryCompareJSONCodec.collectJSONObjectCandidates(from: stripped).count
                #if DEBUG
                print("[ProviderInquiryCompare][cleanJSON][begin]")
                print(stripped)
                print("[ProviderInquiryCompare][cleanJSON][end]")
                print("[ProviderInquiryCompare][decodeFallback]")
                print("reason=\(reason.logTag)")
                print("rawChars=\(raw.count)")
                print("cleanChars=\(stripped.count)")
                print("jsonObjectCandidates=\(candidateCount)")
                #endif
                return Self.providerInquiryCompareConservativeDecodeFallback(debugTag: reason.logTag)
            case .success(let mapped):
                #if DEBUG
                let rd = mapped.recommendedDisposition ?? "nil"
                let cs = mapped.canSendWithinConsent.map { String($0) } ?? "nil"
                let ra = mapped.requiresBoundaryApproval.map { String($0) } ?? "nil"
                let flags = mapped.riskFlags.joined(separator: "|")
                print("[ProviderInquiryCompare][decoded]")
                print("recommendedDisposition=\(rd)")
                print("answerableFromOffer=\(mapped.answerableFromOffer)")
                print("needsProviderInput=\(mapped.needsProviderInput)")
                print("canSendWithinConsent=\(cs)")
                print("requiresBoundaryApproval=\(ra)")
                print("knownFactsCount=\(mapped.knownFacts.count)")
                print("missingFactsCount=\(mapped.missingFacts.count)")
                print("draftChars=\(mapped.draftReply?.count ?? 0)")
                print("riskFlags=\(flags)")
                #endif
                return mapped
            }
        } catch {
            return ExchangeProviderInquiryCompareResult(
                answerableFromOffer: false,
                knownAnswers: [],
                knownFacts: [],
                missingFacts: [],
                needsProviderInput: true,
                draftReply: nil,
                reason: "provider_inquiry_compare_failed: \(error.localizedDescription)",
                recommendedDisposition: "askProviderInput",
                canSendWithinConsent: false,
                requiresBoundaryApproval: false
            )
        }
    }

    public func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.fastClassificationPrompt(for: request)
        let maxTokens = 32

        #if DEBUG
        print(
            "[ExchangeAI][Provider][fastClassify] start " +
            "userChars=\(request.userText.count) " +
            "promptChars=\(prompt.count) " +
            "hasThreadContext=\(request.threadContext != nil) " +
            "purpose=\(request.purpose.rawValue) maxTokens=\(maxTokens)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .fastClassification,
                    prompt: prompt,
                    maxTokens: maxTokens
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][fastClassify] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][fastClassify] rawFullBegin")
            print(raw)
            print("[ExchangeAI][Provider][fastClassify] rawFullEnd")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][fastClassify] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][fastClassify] cleanedFullBegin")
            print(cleaned)
            print("[ExchangeAI][Provider][fastClassify] cleanedFullEnd")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let decoded: ExchangeIntelligenceFastClassificationResponse
            do {
                let dto = try JSONDecoder().decode(
                    FastClassificationDTO.self,
                    from: Data(cleaned.utf8)
                )
                decoded = mapFastClassificationDTO(dto, request: request)
            } catch {
                throw error
            }
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][fastClassify] decode_ok " +
                "queryClass=\(decoded.queryIntentClass.rawValue) " +
                "surface=\(decoded.surfacePreference.rawValue) " +
                "kind=\(decoded.kind.rawValue) " +
                "mode=\(decoded.mode.rawValue) " +
                "readiness=\(decoded.readiness.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "needsFull=\(decoded.needsFullLLMInterpretation) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][fastClassify] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.classifyIntentFast(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][fastClassify] success " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][fastClassify] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.classifyIntentFast(request)
        }
    }

    public func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()

        let fast = try await classifyIntentFast(
            .init(
                userText: request.userText,
                threadContext: request.threadContext
            )
        )

        #if DEBUG
        print(
            "[ExchangeAI][Provider][interpret] preflight " +
            "queryClass=\(fast.queryIntentClass.rawValue) " +
            "surface=\(fast.surfacePreference.rawValue) " +
            "confidence=\(fast.confidence) " +
            "needsFull=\(fast.needsFullLLMInterpretation)"
        )
        #endif

        if !fast.needsFullLLMInterpretation {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][interpret] fast_only_return total=\(totalMs)ms")
            #endif
            return buildInterpretationFromFast(
                request: request,
                fast: fast
            )
        }

        let prompt = ExchangeIntelligencePromptBuilder.interpretationPrompt(
            for: request,
            fast: fast
        )

        #if DEBUG
        print(
            "[ExchangeAI][Provider][interpret] start " +
            "userChars=\(request.userText.count) " +
            "promptChars=\(prompt.count) " +
            "hasThreadContext=\(request.threadContext != nil)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await withTaskCancellationHandler {
                try await runner.run(
                    .init(
                        task: .interpretation,
                        prompt: prompt,
                        maxTokens: 420
                    )
                )
            } onCancel: {
                #if DEBUG
                print(
                    "[ExchangeAI][CancelSource] boundary=interpret " +
                    "task=interpretation " +
                    "reason=taskCancelled"
                )
                #endif
            }
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][interpret] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][interpret] rawFullBegin")
            print(raw)
            print("[ExchangeAI][Provider][interpret] rawFullEnd")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][interpret] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][interpret] cleanedFullBegin")
            print(cleaned)
            print("[ExchangeAI][Provider][interpret] cleanedFullEnd")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let dto = try JSONDecoder().decode(
                InterpretationDTO.self,
                from: Data(cleaned.utf8)
            )
            var decoded = mapInterpretationDTO(dto)
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            decoded = mergeInterpretationWithFast(decoded, fast: fast)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][interpret] decode_ok " +
                "mode=\(decoded.mode.rawValue) " +
                "kind=\(decoded.kind.rawValue) " +
                "readiness=\(decoded.readiness.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "semanticTags=\(decoded.semanticTags.joined(separator: ",")) " +
                "discoveryKeywords=\(decoded.discoveryKeywords.joined(separator: ",")) " +
                "targetTags=\(decoded.targetTags.joined(separator: ",")) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][interpret] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return buildInterpretationFromFast(
                    request: request,
                    fast: fast
                )
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][interpret] success " +
                "title=\(decoded.title) " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][interpret] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return buildInterpretationFromFast(
                request: request,
                fast: fast
            )
        }
    }

    public func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.posturePrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][posture] start " +
            "userChars=\(request.userText.count) " +
            "promptChars=\(prompt.count) " +
            "intentKind=\(request.intent.kind.rawValue)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .posture,
                    prompt: prompt,
                    maxTokens: 220
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][posture] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][posture] rawFullBegin")
            print(raw)
            print("[ExchangeAI][Provider][posture] rawFullEnd")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][posture] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][posture] cleanedFullBegin")
            print(cleaned)
            print("[ExchangeAI][Provider][posture] cleanedFullEnd")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let dto = try JSONDecoder().decode(
                PostureDTO.self,
                from: Data(cleaned.utf8)
            )
            let decoded = mapPostureDTO(dto)
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][posture] decode_ok " +
                "urgency=\(decoded.urgency.rawValue) " +
                "warmth=\(decoded.warmth.rawValue) " +
                "directness=\(decoded.directness.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][posture] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.modelPosture(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][posture] success " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][posture] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.modelPosture(request)
        }
    }

    public func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.draftPrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][draft] start " +
            "promptChars=\(prompt.count) " +
            "threadID=\(request.thread.id.uuidString) " +
            "counterpartyID=\(request.counterparty.id) " +
            "kind=\(request.kind.rawValue)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .requesterDraft,
                    prompt: prompt,
                    maxTokens: 420
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][draft] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][draft] rawFullBegin")
            print(raw)
            print("[ExchangeAI][Provider][draft] rawFullEnd")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][draft] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][draft] cleanedFullBegin")
            print(cleaned)
            print("[ExchangeAI][Provider][draft] cleanedFullEnd")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let dto = try JSONDecoder().decode(
                DraftDTO.self,
                from: Data(cleaned.utf8)
            )
            let decoded = mapDraftDTO(dto)
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][draft] decode_ok " +
                "subjectChars=\(decoded.subject?.count ?? 0) " +
                "bodyChars=\(decoded.body.count) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][draft] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.composeDraft(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][draft] success " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][draft] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.composeDraft(request)
        }
    }
    
    public func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.inboundInquiryPrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][inboundInquiry] start " +
            "askChars=\(request.requesterAsk.count) " +
            "promptChars=\(prompt.count)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .inboundInquiry,
                    prompt: prompt,
                    maxTokens: 260
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][inboundInquiry] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][inboundInquiry] rawFullBegin")
            print(raw)
            print("[ExchangeAI][Provider][inboundInquiry] rawFullEnd")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][inboundInquiry] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][inboundInquiry] cleanedFullBegin")
            print(cleaned)
            print("[ExchangeAI][Provider][inboundInquiry] cleanedFullEnd")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let dto = try JSONDecoder().decode(
                InboundInquiryDTO.self,
                from: Data(cleaned.utf8)
            )
            let decoded = mapInboundInquiryDTO(dto, request: request)
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][inboundInquiry] decode_ok " +
                "answerability=\(decoded.answerabilityStatus.rawValue) " +
                "classification=\(decoded.classification.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][inboundInquiry] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.classifyInboundInquiry(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][inboundInquiry] success " +
                "runner=\(runnerMs)ms clean=\(cleanMs)ms decode=\(decodeMs)ms total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][inboundInquiry] fallback error=\(error) total=\(totalMs)ms")
            #endif

            return try await fallback.classifyInboundInquiry(request)
        }
    }
}

// MARK: - Runner boundary

public protocol ExchangeIntelligenceModelRunner: Sendable {
    func run(_ request: ExchangeIntelligenceModelRunRequest) async throws -> String
}

public struct ExchangeIntelligenceModelRunRequest: Sendable, Hashable {
    public enum Task: String, Sendable, Hashable {
        case fastClassification
        case interpretation
        /// Narrow on-device JSON extraction for open-ended search intent (minimal runner scaffold).
        case searchIntentExtraction
        case posture
        /// Legacy draft task; prefer `requesterDraft`, `providerDraft`, or `neutralRewrite` for scaffold routing.
        case draft
        case requesterDraft
        case providerDraft
        case neutralRewrite
        /// Direct-message reply suggestion; lightweight scaffold (no Exchange agency posture).
        case directChatReply
        case inboundInquiry
        /// Compare requester ask vs matched seller surface; emit missing facts and provider-bound questions.
        case requesterMatchCompare
        /// Compare inbound inquiry vs offer/OSM; gate autonomous answering vs provider input.
        case providerInquiryCompare
        /// Provider-side inbound ask interpretation (not requester search routing).
        case providerInboundIntentExtraction
    }

    public var task: Task
    public var prompt: String
    public var maxTokens: Int
    /// Merged into secretary representation in `LlamaExchangeModelRunner` (after global representation provider).
    public var representationSupplement: String?

    public init(
        task: Task,
        prompt: String,
        maxTokens: Int,
        representationSupplement: String? = nil
    ) {
        self.task = task
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.representationSupplement = representationSupplement
    }
}

/// Central on-device task output token budgets for Exchange intelligence runners.
public enum ExchangeIntelligenceTaskTokenBudget {
    /// `searchIntentExtraction` compact JSON schema; must stay in sync with runner task policy fallback.
    public static let searchIntentExtractionMaxTokens = 320
    /// `providerInboundIntentExtraction` compact JSON schema; must stay in sync with runner task policy fallback.
    public static let providerInboundIntentExtractionMaxTokens = 320
    /// Provider compare JSON can be ~1k chars; avoid truncation mid-object (decode fallback).
    public static let providerInquiryCompareMaxTokens = 560
}

// MARK: - Prompt builder

enum ExchangeIntelligencePromptBuilder {
    private static func fastClassificationThreadContextJSON(
        for request: ExchangeIntelligenceFastClassificationRequest
    ) -> String {
        guard let ctx = request.threadContext else { return "null" }

        let threadID = ctx.threadID?.uuidString ?? "null"
        let modeHint = ctx.modeHint?.rawValue ?? "null"
        let priorIntentTitle = escaped(ctx.priorIntentTitle) ?? "null"
        let selectedCounterpartyID = escaped(ctx.selectedCounterpartyID) ?? "null"

        return """
        {"threadID":"\(threadID)","modeHint":"\(modeHint)","priorIntentTitle":\(priorIntentTitle),"selectedCounterpartyID":\(selectedCounterpartyID)}
        """
    }

    static func fastClassificationPrompt(
        for request: ExchangeIntelligenceFastClassificationRequest
    ) -> String {
        switch request.purpose {
        case .standardRequesterInterpretation, .providerInboundAsk:
            return fastClassificationPromptRequesterStandard(for: request)
        }
    }

    private static func fastClassificationPromptRequesterStandard(
        for request: ExchangeIntelligenceFastClassificationRequest
    ) -> String {
        let contextBlock = fastClassificationThreadContextJSON(for: request)

        return """
        You are a deterministic routing classifier for a private AI secretary system.

        Classify the user request into exactly one retrieval lane.

        Return exactly one compact JSON object.
        No markdown.
        No explanation.
        No trailing text.

        Required output:
        {"lane":"...","surface":"...","confidence":0.0,"needsFullLLMInterpretation":false}

        Allowed lane values:
        providerSearch
        offerSearch
        capabilitySearch
        collaborationSearch
        socialAffinitySearch
        relationshipSearch
        directOutreach
        followUp
        statusCheck
        generalDiscovery

        Allowed surface values:
        offer
        capability
        affinity
        mixed

        Routing hierarchy:
        1. If a selected counterparty exists and the user wants to continue, contact, send, reply, or advance the thread, use directOutreach.
        2. If the user asks to follow up, use followUp.
        3. If the user asks for status, progress, or an update, use statusCheck.
        4. If the user is looking for a paid, professional, local, commercial, or service-providing person/business, use providerSearch with surface offer.
        5. If the user is looking for an available listing, item, product, package, or explicitly described offer, use offerSearch with surface offer.
        6. If the user is looking for a person/entity by skill, knowledge, capability, expertise, or ability, but not clearly as a service provider, use capabilitySearch with surface capability.
        7. If the user wants to work together, partner, collaborate, or co-build, use collaborationSearch with surface capability.
        8. If the user wants friends, social activity, shared interests, or community, use socialAffinitySearch with surface affinity.
        9. If the user wants dating or relationship matching, use relationshipSearch with surface affinity.
        10. If none of the above is clear, use generalDiscovery with surface mixed and needsFullLLMInterpretation true.

        Tie-breakers:
        - Service/provider intent beats capability intent.
        - Direct outreach beats search only when the target is already known.
        - Discovery/search requests usually have needsFullLLMInterpretation false when the lane is clear.
        - Use needsFullLLMInterpretation true only when the request is ambiguous, multi-intent, or too underspecified.

        Thread context:
        \(contextBlock)

        User request:
        \(request.userText)

        JSON:
        """
    }

    static func interpretationPrompt(
        for request: ExchangeIntelligenceInterpretationRequest,
        fast: ExchangeIntelligenceFastClassificationResponse
    ) -> String {
        let contextBlock: String = {
            guard let ctx = request.threadContext else { return "null" }

            let threadID = ctx.threadID?.uuidString ?? "null"
            let modeHint = ctx.modeHint?.rawValue ?? "null"
            let priorIntentTitle = escaped(ctx.priorIntentTitle) ?? "null"
            let selectedCounterpartyID = escaped(ctx.selectedCounterpartyID) ?? "null"

            return """
            {
              "threadID": "\(threadID)",
              "modeHint": "\(modeHint)",
              "priorIntentTitle": \(priorIntentTitle),
              "selectedCounterpartyID": \(selectedCounterpartyID)
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to refine a user's natural-language coordination request into structured Exchange intent.

        A fast intent gate has already run. Use it as prior signal.

        Return JSON only.

        Rules:
        - Output exactly one JSON object.
        - No markdown fences.
        - No commentary.
        - Be conservative.
        - Keep title short.
        - Keep objective concrete.
        - Keep clarificationQuestion useful and specific when needed.
        - Confidence must be between 0 and 1.
        - desiredOutcomes should contain at most 2 items.
        - constraints should contain at most 4 items.
        - semanticTags should contain at most 12 short tags.
        - discoveryKeywords should contain at most 12 practical search phrases.
        - targetTags should contain at most 10 target/counterparty tags.
        - Prefer noun phrases and useful search phrases over prose.
        - Stay aligned with the fast gate unless the user text clearly requires correction.

        Allowed mode values:
        - transactional
        - cooperative
        - relational

        Allowed kind values:
        - requestQuote
        - introduce
        - negotiate
        - arrangeCall
        - arrangeMeeting
        - followUp
        - checkStatus
        - invite
        - source
        - find
        - message
        - coordinate
        - plan
        - other

        Allowed readiness values:
        - ready
        - needsClarification
        - underSpecified

        Allowed posture values:
        - urgency: low | normal | high | immediate
        - warmth: reserved | neutral | warm
        - directness: soft | balanced | firm
        - openness: selective | exploratory
        - commitment: exploring | serious | committed
        - privacy: guarded | balanced | disclosive
        - priceSensitivity: notSpecified | low | moderate | high
        - flexibility: rigid | moderate | flexible

        Output schema:
        {
          "mode": String,
          "kind": String,
          "title": String,
          "objective": String,
          "targetDescription": String?,
          "constraints": [
            {
              "key": String,
              "value": String,
              "isHardConstraint": Bool
            }
          ],
          "desiredOutcomes": [String],
          "readiness": String,
          "interpretationNotes": String?,
          "confidence": Double,
          "clarificationQuestion": String?,
          "userSummary": String?,
          "userQuestion": String?,
          "userNextStep": String?,
          "needsClarification": Bool?,
          "shouldDiscover": Bool?,
          "shouldDraft": Bool?,
          "semanticTags": [String]?,
          "discoveryKeywords": [String]?,
          "targetTags": [String]?,
          "inferredPosture": {
            "urgency": String,
            "warmth": String,
            "directness": String,
            "openness": String,
            "commitment": String,
            "privacy": String,
            "priceSensitivity": String,
            "flexibility": String,
            "notes": String?,
            "confidence": Double
          }?
        }

        Fast gate prior:
        {
          "queryIntentClass": "\(fast.queryIntentClass.rawValue)",
          "surfacePreference": "\(fast.surfacePreference.rawValue)",
          "mode": "\(fast.mode.rawValue)",
          "kind": "\(fast.kind.rawValue)",
          "readiness": "\(fast.readiness.rawValue)",
          "confidence": \(fast.confidence),
          "semanticTags": \(renderStringArray(fast.semanticTags)),
          "discoveryKeywords": \(renderStringArray(fast.discoveryKeywords)),
          "targetTags": \(renderStringArray(fast.targetTags)),
          "providerTerms": \(renderStringArray(fast.providerTerms)),
          "capabilityTerms": \(renderStringArray(fast.capabilityTerms)),
          "affinityTerms": \(renderStringArray(fast.affinityTerms)),
          "regionTerms": \(renderStringArray(fast.regionTerms)),
          "targetDescription": \(escaped(fast.targetDescription) ?? "null")
        }

        Thread context:
        \(contextBlock)

        User request:
        \(request.userText)
        """
    }

    static func posturePrompt(
        for request: ExchangeIntelligencePostureRequest
    ) -> String {
        let priorBlock: String = {
            guard let prior = request.priorPosture else { return "null" }

            return """
            {
              "urgency": "\(prior.urgency.rawValue)",
              "warmth": "\(prior.warmth.rawValue)",
              "directness": "\(prior.directness.rawValue)",
              "openness": "\(prior.openness.rawValue)",
              "commitment": "\(prior.commitment.rawValue)",
              "privacy": "\(prior.privacy.rawValue)",
              "priceSensitivity": "\(prior.priceSensitivity.rawValue)",
              "flexibility": "\(prior.flexibility.rawValue)",
              "notes": \(escaped(prior.notes) ?? "null")
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to model user posture for an Exchange thread.

        Return JSON only.

        Allowed urgency values:
        - low
        - normal
        - high
        - immediate

        Allowed warmth values:
        - reserved
        - neutral
        - warm

        Allowed directness values:
        - soft
        - balanced
        - firm

        Allowed openness values:
        - selective
        - exploratory

        Allowed commitment values:
        - exploring
        - serious
        - committed

        Allowed privacy values:
        - guarded
        - balanced
        - disclosive

        Allowed priceSensitivity values:
        - notSpecified
        - low
        - moderate
        - high

        Allowed flexibility values:
        - rigid
        - moderate
        - flexible

        Output schema:
        {
          "urgency": String,
          "warmth": String,
          "directness": String,
          "openness": String,
          "commitment": String,
          "privacy": String,
          "priceSensitivity": String,
          "flexibility": String,
          "notes": String?,
          "confidence": Double
        }

        Interpreted intent:
        {
          "mode": "\(request.intent.mode.rawValue)",
          "kind": "\(request.intent.kind.rawValue)",
          "title": "\(request.intent.title)",
          "objective": "\(request.intent.objective)",
          "targetDescription": \(escaped(request.intent.targetDescription) ?? "null"),
          "readiness": "\(request.intent.readiness.rawValue)"
        }

        Prior posture:
        \(priorBlock)

        User request:
        \(request.userText)
        """
    }

    static func draftPrompt(
        for request: ExchangeIntelligenceDraftRequest
    ) -> String {
        let supersedingBlock: String = {
            guard let draft = request.supersedingDraft else { return "null" }

            return """
            {
              "subject": \(escaped(draft.subject) ?? "null"),
              "body": \(escaped(draft.body) ?? "null"),
              "strategyNote": \(escaped(draft.strategyNote) ?? "null")
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to produce an outbound draft for a selected counterparty.

        Return JSON only.

        Output schema:
        {
          "subject": String?,
          "body": String,
          "strategyNote": String?,
          "confidence": Double
        }

        Thread:
        {
          "mode": "\(request.thread.mode.rawValue)",
          "intentKind": "\(request.thread.intent.kind.rawValue)",
          "intentTitle": "\(request.thread.intent.title)",
          "objective": "\(request.thread.intent.objective)",
          "targetDescription": \(escaped(request.thread.intent.targetDescription) ?? "null"),
          "constraints": \(renderConstraints(request.thread.intent.constraints)),
          "posture": {
            "urgency": "\(request.thread.posture.urgency.rawValue)",
            "warmth": "\(request.thread.posture.warmth.rawValue)",
            "directness": "\(request.thread.posture.directness.rawValue)",
            "openness": "\(request.thread.posture.openness.rawValue)",
            "commitment": "\(request.thread.posture.commitment.rawValue)",
            "privacy": "\(request.thread.posture.privacy.rawValue)",
            "priceSensitivity": "\(request.thread.posture.priceSensitivity.rawValue)",
            "flexibility": "\(request.thread.posture.flexibility.rawValue)"
          }
        }

        Counterparty:
        {
          "id": "\(request.counterparty.id)",
          "displayName": \(escaped(request.counterparty.displayName) ?? "null"),
          "bestDisplayLine": "\(request.counterparty.bestDisplayLine)",
          "kind": "\(request.counterparty.kind.rawValue)"
        }

        Draft kind:
        \(request.kind.rawValue)

        Superseded draft:
        \(supersedingBlock)
        """
    }
    
    static func inboundInquiryPrompt(
        for request: ExchangeIntelligenceInboundInquiryRequest
    ) -> String {
        return """
        You are the provider-side reception classifier for a private AI secretary system.

        Your job:
        Read an inbound requester message and decide how the provider-side secretary should treat it.

        Return JSON only.
        No markdown.
        No explanation outside JSON.

        Safety rules:
        - Do not invent facts.
        - If the response needs custom pricing, private/sensitive disclosure, scheduling commitment, legal/commercial commitment, payment, exception, or owner judgment, classify as requiresUserInput and exceptional.
        - If the inquiry is routine and answerable from known facts, classify as answerableFromKnownFacts and routine.
        - If facts are missing, classify as insufficientContext.
        - If clearly outside scope, classify as outOfScope.
        - Do not approve sending. Only classify.

        Allowed answerabilityStatus values:
        - answerableFromKnownFacts
        - requiresUserInput
        - insufficientContext
        - outOfScope

        Allowed classification values:
        - routine
        - exceptional

        Output schema:
        {
          "inquirySummary": String,
          "requesterAsk": String,
          "matchedOfferOrProfileAnchor": String?,
          "answerabilityStatus": String,
          "classification": String,
          "rationale": String?,
          "confidence": Double
        }

        Provider secretary style:
        \(escaped(request.secretaryRepresentation) ?? "null")

        Thread:
        {
          "title": \(escaped(request.threadTitle) ?? "null"),
          "visibleSummary": \(escaped(request.visibleSummary) ?? "null"),
          "selectedCounterpartyName": \(escaped(request.selectedCounterpartyName) ?? "null"),
          "matchedOfferOrProfileAnchor": \(escaped(request.matchedOfferOrProfileAnchor) ?? "null")
        }

        Known facts:
        \(renderStringArray(request.knownFacts))

        Unresolved issues:
        \(renderStringArray(request.unresolvedIssues))

        Inbound requester ask:
        \(request.requesterAsk)

        JSON:
        """
    }

    static func requesterRequirementsGroundingPromptBlock(_ summary: String?) -> String {
        let body = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else {
            return """
            REQUESTER INTENT GROUNDING (canonical summary not provided):
            - Use the original requester message below as the only explicit requirement source.
            - Do not invent ideal slots or assume unstated requirements.
            """
        }
        return """
        REQUESTER INTENT GROUNDING (explicit requirements only; do not invent unstated needs):
        \(body)

        Grounding rules:
        - Treat this block as the structured requester intent summary.
        - Do not create providerQuestions for facts outside this block and the original message.
        - The original message below is context only when this block is present.
        """
    }

    static func requesterMatchComparePrompt(
        originalRequesterMessage: String,
        selectedOfferSummary: String?,
        selectedProfileSummary: String?,
        counterpartyDisplayName: String?,
        knownFacts: [String],
        styleProfile: ExchangeSecretaryStyleProfile,
        requesterRequirementsSummary: String? = nil
    ) -> String {
        let offer = escaped(selectedOfferSummary) ?? "null"
        let profile = escaped(selectedProfileSummary) ?? "null"
        let counterparty = escaped(counterpartyDisplayName) ?? "null"
        let typedStyleLine = """
        tone=\(styleProfile.tone.rawValue), warmthDirectness=\(styleProfile.warmthDirectness.rawValue), firmness=\(styleProfile.firmness.rawValue), disclosureStyle=\(styleProfile.disclosureStyle.rawValue), initiative=\(styleProfile.initiativeLevel.rawValue), negotiation=\(styleProfile.negotiationStyle.rawValue), approvalSensitivity=\(styleProfile.approvalSensitivity.rawValue)
        """
        let styleGuideSection = ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideBlock(
            styleFreeform: styleProfile.freeformInstructions
        )
        let styleGuideAppend = styleGuideSection.isEmpty ? "" : "\n\n\(styleGuideSection)"
        let groundingBlock = requesterRequirementsGroundingPromptBlock(requesterRequirementsSummary)

        return """
        You are the requester's private secretary. Act as a grounded DELTA detector between REQUESTER INTENT and MATCHED SURFACE EVIDENCE.

        Return exactly one JSON object. No markdown. No commentary.

        \(groundingBlock)

        Core delta rule — flag a gap ONLY when BOTH are true:
        1) an explicit requirement appears in REQUESTER INTENT GROUNDING (or original message when grounding is absent), and
        2) MATCHED SURFACE EVIDENCE does not resolve it with direct wording or a close synonym.

        You are NOT filling ideal slots. You are building common ground between requester intent and what the matched offer/profile actually shows.

        Do NOT ask nice-to-have diligence questions unless explicitly required in grounding.

        If the surface already answers a requirement, do not ask it again.

        providerQuestions rules:
        - Address the matched counterparty using you/your.
        - Ask at most ONE natural clarification question total.
        - If no clarification is needed, set shouldAskProvider=false and providerQuestions=[].
        - Never use robotic phrases: "for this request", "for this job", "services matching", "intent gap", "canonicalIntent", "underspecified publicly".
        - Do not ask requester-diagnostic questions (symptoms, materials, scope breakdown).
        - Do not ask about credentials, certification, standards, price, or provider-type preferences unless the requester explicitly required them in grounding.
        - providerQuestions must be to the matched provider about their capability/fit/availability — never ask the provider what the requester prefers or which contractor type the requester wants.
        - Never use internal analysis phrasing such as "hardened timeline" or "high-level cues".

        Adapt tone by routingSurface in grounding (default provider/offer):
        - provider/offer: practical service, availability, or fit question
        - capability/collaboration: project/capability fit or openness to collaborate
        - social/affinity: soft interest or weekend/availability openness (not vendor/service wording)
        - relationship: cautious, consent-aware, low-autonomy question
        - mixed: neutral clarification only

        missingFacts / reason:
        - List only explicit unresolved deltas, briefly.
        - Optional secondary uncertainty may appear in reason only; do not convert to providerQuestions.

        Output schema:
        {
          "missingFacts": [String],
          "providerQuestions": [String],
          "shouldAskProvider": Bool,
          "reason": String
        }

        Secretary style profile:
        \(typedStyleLine)\(styleGuideAppend)

        Original requester message (context; do not add requirements beyond grounding when provided):
        \(originalRequesterMessage)

        MATCHED SURFACE EVIDENCE (offer/profile/known facts only — do not invent beyond this):

        Matched offer summary:
        \(offer)

        Matched public profile summary:
        \(profile)

        Counterparty display:
        \(counterparty)

        Known facts:
        \(renderStringArray(knownFacts))

        JSON:
        """
    }
    
    static func providerInquiryComparePrompt(
        inboundInquiry: String,
        offerSummary: String?,
        profileSummary: String?,
        operatingMemorySummary: String,
        styleProfile: ExchangeSecretaryStyleProfile,
        consentAutomationSummary: String?,
        sellerControlledFacts: String,
        queryIntentClass: String,
        surfacePreference: String,
        primaryOpportunitySurface: String,
        selectedProfileID: String?,
        selectedOfferID: String?,
        allowedFactBlocksMetadata: String? = nil,
        inboundIntentContext: ProviderInboundIntentExtraction? = nil
    ) -> String {
        let consent = escaped(consentAutomationSummary) ?? "null"
        let factsBodyEarly = sellerControlledFacts.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasStructuredOfferFacts = factsBodyEarly.contains("=== OFFER_FACTS ===")
        let hasStructuredProfileFacts = factsBodyEarly.contains("=== PROFILE_FACTS ===")
        let hasStructuredOSMExcerpt = factsBodyEarly.contains("=== OPERATING_MEMORY_EXCERPT ===")
        let osmTrimmed = String(operatingMemorySummary.prefix(2800)).trimmingCharacters(in: .whitespacesAndNewlines)

        let offer: String = {
            if hasStructuredOfferFacts, offerSummary != nil {
                return escaped("(see OFFER_FACTS)") ?? "\"(see OFFER_FACTS)\""
            }
            return escaped(offerSummary) ?? "null"
        }()

        let profile: String = {
            if hasStructuredProfileFacts, profileSummary != nil {
                return escaped("(see PROFILE_FACTS)") ?? "\"(see PROFILE_FACTS)\""
            }
            return escaped(profileSummary) ?? "null"
        }()

        let osm: String = {
            if hasStructuredOSMExcerpt, !osmTrimmed.isEmpty {
                return escaped("(see OPERATING_MEMORY_EXCERPT)") ?? "\"(see OPERATING_MEMORY_EXCERPT)\""
            }
            return escaped(osmTrimmed.isEmpty ? nil : osmTrimmed) ?? "null"
        }()

        let esc = { (value: String) -> String in escaped(value) ?? "null" }
        let pid = selectedProfileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let oid = selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines)

        let typedStyleLine = """
        tone=\(styleProfile.tone.rawValue), warmthDirectness=\(styleProfile.warmthDirectness.rawValue), firmness=\(styleProfile.firmness.rawValue), disclosureStyle=\(styleProfile.disclosureStyle.rawValue), initiative=\(styleProfile.initiativeLevel.rawValue), negotiation=\(styleProfile.negotiationStyle.rawValue), approvalSensitivity=\(styleProfile.approvalSensitivity.rawValue)
        """

        let secretaryStyleGuideSection = ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideBlock(
            styleFreeform: styleProfile.freeformInstructions
        )

        let inboundIntentBlock: String = {
            guard let ctx = inboundIntentContext else { return "" }
            return "\n\n\(ctx.providerInquiryCompareIntentContextBlock())\n"
        }()

        let surfaceRoutingBlock = """
        THREAD_SURFACE_ROUTING (provider inbound; advisory — compare/governor decide disposition):
        INBOUND_INQUIRY_KIND: \(esc(queryIntentClass))
        REQUESTED_FACT_SURFACES: \(esc(surfacePreference))
        PRIMARY_OPPORTUNITY_SURFACE: \(esc(primaryOpportunitySurface))
        SELECTED_PROFILE_ID: \(escaped(pid ?? "nil") ?? "null")
        SELECTED_OFFER_ID: \(escaped(oid ?? "nil") ?? "null")
        \(inboundIntentBlock)
        """

        let allowedBlocksSection: String = {
            guard let meta = allowedFactBlocksMetadata?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !meta.isEmpty else { return "" }
            return """

            ALLOWED_FACT_BLOCKS (code-enforced; do not infer facts from omitted sections):
            \(meta)

            When present: use only flagged sections; narrow answer to the ask; needsProviderInput if required facts absent; ALLOWED_FACT_BLOCKS wins over summaries.
            """
        }()

        let sellerControlledBlock: String = {
            guard !factsBodyEarly.isEmpty else {
                return """
                SELLER_CONTROLLED_FACTS:
                (no hydrated sections assembled — rely on summaries and operating memory excerpt above.)
                """
            }
            return """
            STRUCTURED_SELLER_SURFACES (authoritative seller-entered text; treat as factual unless explicitly marked private):
            \(factsBodyEarly)

            Section roles: PROFILE_FACTS = identity/reachability (not transaction policy). OFFER_FACTS = commercial listing facts. OPERATING_MEMORY_EXCERPT = secretary memory when relevant and non-contradictory.
            """
        }()

        let voiceAndGroundingBlock = """
        Voice and grounding rules:
        - Speak as "we" for the seller side; address the requester as "you".
        - draftReply must not contain: "provider", "listing", "offer facts", "permitted facts", "published offer", "fact blocks", or any internal structural term.
        - For missing or unconfirmed seller-side facts: write "we'd need to confirm that", "we don't have that confirmed yet", or "I don't want to give you the wrong answer on that" — never ask the requester to confirm seller-side facts.
        - Requester words are not seller facts. Never adopt requester assertions as confirmed answers.
        - Never infer credentials, discounts, guarantees, warranties, or outside-area exceptions from profession, title, tags, category, or headline.
        - Caveat lane only covers published general facts (availability_note, lead_time_note, price range, policy/FAQ).

        draftReply voice examples:
        ✗ "I need to verify your credentials and availability with you."
        ✓ "We'd need to confirm credentials and availability before locking that in."

        ✗ "Confirm that you received approval for this discount."
        ✓ "We don't have a discount confirmed for this — any custom pricing would need to be checked first."

        ✗ "I would need to confirm license and insurance with you."
        ✓ "I don't want to give you the wrong answer on license or insurance — we'd need to confirm those first."
        """

        let commercialAnswerLanesBlock = """
        Commercial answer lanes (choose one):
        1. Full answer — permitted facts fully answer the ask. answerableFromOffer=true, needsProviderInput=false, draftReply required, recommendedDisposition=sendWithinConsent when consent allows.
        2. Caveat answer — a published general fact exists but finer precision is missing. answerableFromOffer=true, needsProviderInput=false. draftReply states the published general fact then notes what we'd still need to confirm. Do not confirm exact slot, booking, final quote, guarantee, discount, credential, or outside-area service.
        3. Unsupported high-risk — discount, license, insurance, certification, bonding, warranty, guarantee, final quote, exact booking, requester-proposed price, or outside-area exception not explicit in permitted facts: do not answer yes. draftReply uses "we" voice to acknowledge the gap; never ask the requester to confirm seller-side facts. needsProviderInput=true, canSendWithinConsent=false, recommendedDisposition=askProviderInput.
        4. Refusal / no-answer — social or off-surface ask, or unsupported commitment.

        Outside-area: name requester's area only in a denial; state known service area; never claim service outside it.
        """

        let answerDisciplineBlock = """
        Answer discipline:
        - Answer the requested fact(s) directly before any light tone.
        - Secretary style may adjust wording but must not widen scope, add persuasion, or substitute for missing facts.
        - No sales language, flattery, cheerleading, or filler.
        - Do not volunteer extra benefits or superlatives unless the ask is clearly broad.
        - For geography asks: answer only with known location or service-area facts.
        """

        let exampleFullAnswer = """
        {"answerableFromOffer":true,"knownAnswers":["Service call $89; typical leak repair $150–$280"],"knownFacts":[],"missingFacts":[],"needsProviderInput":false,"draftReply":"Our service call is $89 and typical leak repairs run $150–$280.","replyToSend":null,"reason":"Price on listing.","intentCategory":"pricing","riskFlags":[],"recommendedDisposition":"sendWithinConsent","canSendWithinConsent":true,"requiresBoundaryApproval":false}
        """

        let exampleCaveat = """
        {"answerableFromOffer":true,"knownAnswers":["Usually 24–48 hours; weekends by appointment"],"knownFacts":[],"missingFacts":["Exact start time"],"needsProviderInput":false,"draftReply":"We're usually available within 24–48 hours and weekends are by appointment — we'd need to confirm the exact time before locking that in.","replyToSend":null,"reason":"General published timing only.","intentCategory":"lead_time","riskFlags":["precision_gap"],"recommendedDisposition":"sendWithinConsent","canSendWithinConsent":true,"requiresBoundaryApproval":false}
        """

        let exampleUnsupportedCredential = """
        {"answerableFromOffer":false,"knownAnswers":[],"knownFacts":[],"missingFacts":["License and insurance not confirmed"],"needsProviderInput":true,"draftReply":"I don't want to give you the wrong answer on license or insurance — we'd need to confirm those first.","replyToSend":null,"reason":"Credential details are not available in permitted facts.","intentCategory":"credentials","riskFlags":["unsupported_claim"],"recommendedDisposition":"askProviderInput","canSendWithinConsent":false,"requiresBoundaryApproval":false}
        """

        let exampleOpennessOnly = """
        {"answerableFromOffer":true,"knownAnswers":["Open to hearing from early-stage founders, including AI and pharmaceutical startups."],"knownFacts":[],"missingFacts":[],"needsProviderInput":false,"draftReply":"Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups.","replyToSend":null,"reason":"Profile open_to answers the outreach question.","intentCategory":"openness","riskFlags":[],"recommendedDisposition":"sendWithinConsent","canSendWithinConsent":true,"requiresBoundaryApproval":false}
        """

        let opennessDisciplineBlock: String = {
            guard inboundIntentContext?.inquiryKind == .availabilityOrOpenness else { return "" }
            return """

            OPENNESS_INQUIRY (PROVIDER_INBOUND_INTENT inquiryKind=availabilityOrOpenness):
            - Answer only whether the provider is open to the outreach type asked (founders, category, geography, etc.).
            - Use PROFILE_FACTS open_to / availability and OFFER_FACTS scope when present.
            - Do not list pricing, exact scheduling, or unrelated service scope in missingFacts unless the requester asked for those.
            - missingFacts must be [] when permitted facts answer the openness ask.
            - Do not add "we need to confirm availability/pricing/details before proceeding" hedges when openness is already on-surface.
            """
        }()

        return """
        You are the seller's private secretary. Compare the inbound inquiry to the seller surface below and return exactly one JSON object (no markdown, no array, no trailing text).

        \(voiceAndGroundingBlock)

        \(answerDisciplineBlock)

        \(surfaceRoutingBlock)\(allowedBlocksSection)

        Primary grounding: obey PRIMARY_OPPORTUNITY_SURFACE. Profile asks use PROFILE_FACTS; commercial asks use OFFER_FACTS. If the targeted section lacks the fact, use unsupported high-risk or askProviderInput — do not guess.

        \(commercialAnswerLanesBlock)\(opennessDisciplineBlock)

        JSON rules:
        - Emit exactly one syntactically valid JSON object. No markdown fences. No trailing commentary. No schema template echo.
        - Use lowercase JSON literals only: null, true, false. Never use None, True, or False.
        - If there is no boundary-crossing reason, output "boundaryCrossingReason": null (not None).
        - Do not output TypeScript-style types (e.g. Bool, String?) — use JSON literals only.
        - knownAnswers/knownFacts only from permitted text; draftReply required for full/caveat lanes.
        - disposition: sendWithinConsent | askProviderInput | holdForBoundaryApproval | blocked | wait
        - riskFlags e.g. precision_gap, unsupported_claim

        Seller automation consent (JSON string):
        \(consent)

        Secretary style:
        \(typedStyleLine)
        \(secretaryStyleGuideSection)

        Offer summary:
        \(offer)

        Profile summary:
        \(profile)

        Operating memory (excerpt):
        \(osm)

        \(sellerControlledBlock)

        Example — full answer:
        \(exampleFullAnswer)

        Example — caveat (timing):
        \(exampleCaveat)

        Example — unsupported credential:
        \(exampleUnsupportedCredential)

        Example — openness / open_to (when inquiryKind is availabilityOrOpenness):
        \(exampleOpennessOnly)

        Current inbound inquiry:
        \(inboundInquiry)

        Required JSON keys (one object; use null for absent optional strings):
        answerableFromOffer, knownAnswers, knownFacts, missingFacts, needsProviderInput, draftReply, replyToSend, reason, intentCategory, inquirySummary, requesterAsk, riskFlags, recommendedDisposition, canSendWithinConsent, requiresBoundaryApproval, consentBasis, boundaryCrossingReason
        """
    }


    private static func escaped(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }

    private static func renderConstraints(
        _ constraints: [ExchangeIntent.Constraint]
    ) -> String {
        guard !constraints.isEmpty else { return "[]" }

        let items = constraints.map { constraint in
            """
            {"key":"\(constraint.key)","value":"\(constraint.value)","isHardConstraint":\(constraint.isHardConstraint ? "true" : "false")}
            """
        }

        return "[\(items.joined(separator: ","))]"
    }

    private static func renderStringArray(_ values: [String]) -> String {
        guard !values.isEmpty else { return "[]" }
        let encoded = values.compactMap { escaped($0) }
        return "[\(encoded.joined(separator: ","))]"
    }
}

// MARK: - DTOs

private extension OnDeviceExchangeIntelligenceProvider {
    struct FastClassificationDTO: Decodable {
        let lane: String
        let surface: String?
        let confidence: Double?
        let needsFullLLMInterpretation: Bool?
    }

    struct InterpretationDTO: Decodable {
        struct ConstraintDTO: Decodable {
            let key: String
            let value: String
            let isHardConstraint: Bool?
        }

        let mode: String
        let kind: String
        let title: String
        let objective: String
        let targetDescription: String?
        let constraints: [ConstraintDTO]?
        let desiredOutcomes: [String]?
        let readiness: String
        let interpretationNotes: String?
        let confidence: Double
        let clarificationQuestion: String?
        let userSummary: String?
        let userQuestion: String?
        let userNextStep: String?
        let inferredPosture: PostureDTO?
        let needsClarification: Bool?
        let shouldDiscover: Bool?
        let shouldDraft: Bool?
        let semanticTags: [String]?
        let discoveryKeywords: [String]?
        let targetTags: [String]?
    }

    struct PostureDTO: Decodable {
        let urgency: String
        let warmth: String
        let directness: String
        let openness: String
        let commitment: String
        let privacy: String
        let priceSensitivity: String
        let flexibility: String
        let notes: String?
        let confidence: Double?
    }

    struct DraftDTO: Decodable {
        let subject: String?
        let body: String
        let strategyNote: String?
        let confidence: Double
    }
    struct InboundInquiryDTO: Decodable {
        let inquirySummary: String
        let requesterAsk: String
        let matchedOfferOrProfileAnchor: String?
        let answerabilityStatus: String
        let classification: String
        let rationale: String?
        let confidence: Double?
    }

    struct RequesterMatchCompareDTO: Decodable {
        let missingFacts: [String]?
        let providerQuestions: [String]?
        let shouldAskProvider: Bool?
        let reason: String?
    }

    struct ProviderInquiryCompareDTO: Decodable {
        struct KnownFactDTO: Decodable {
            let fact: String?
            let source: String?
            let confidence: Double?
        }

        let answerableFromOffer: Bool?
        let knownAnswers: [String]?
        let knownFacts: [KnownFactDTO]?
        let missingFacts: [String]?
        let needsProviderInput: Bool?
        let draftReply: String?
        let replyToSend: String?
        let reason: String?
        let intentCategory: String?
        let inquirySummary: String?
        let requesterAsk: String?
        let riskFlags: [String]?
        let recommendedDisposition: String?
        let recommendedAction: String?
        let consentBasis: String?
        let boundaryCrossingReason: String?
        let canSendWithinConsent: Bool?
        let requiresBoundaryApproval: Bool?
    }
}

// MARK: - Mapping

private extension OnDeviceExchangeIntelligenceProvider {
    func buildInterpretationFromFast(
        request: ExchangeIntelligenceInterpretationRequest,
        fast: ExchangeIntelligenceFastClassificationResponse
    ) -> ExchangeIntelligenceInterpretationResponse {
        ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: fast.queryIntentClass,
            surfacePreference: fast.surfacePreference,
            mode: fast.mode,
            kind: fast.kind,
            title: fallbackTitle(
                for: fast.kind,
                text: request.userText,
                threadContext: request.threadContext
            ),
            objective: normalizeInput(request.userText),
            targetDescription: fast.targetDescription,
            constraints: fast.explicitHardConstraints,
            desiredOutcomes: fallbackDesiredOutcomes(for: fast.kind),
            readiness: fast.readiness,
            interpretationNotes: "on-device fast-classification path",
            confidence: fast.confidence,
            clarificationQuestion: fast.readiness == .ready
                ? nil
                : fallbackClarificationQuestion(for: fast.kind),
            userSummary: fast.userSummary,
            userQuestion: fast.readiness == .ready
                ? nil
                : fallbackClarificationQuestion(for: fast.kind),
            userNextStep: fast.userNextStep,
            inferredPosture: nil,
            needsClarification: fast.readiness != .ready,
            shouldDiscover: defaultShouldDiscover(for: fast.kind) && request.threadContext?.selectedCounterpartyID == nil,
            shouldDraft: defaultShouldDraft(for: fast.kind) && request.threadContext?.selectedCounterpartyID != nil,
            semanticTags: fast.semanticTags,
            discoveryKeywords: fast.discoveryKeywords,
            targetTags: fast.targetTags
        )
    }

    func mergeInterpretationWithFast(
        _ interpreted: ExchangeIntelligenceInterpretationResponse,
        fast: ExchangeIntelligenceFastClassificationResponse
    ) -> ExchangeIntelligenceInterpretationResponse {
        ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: interpreted.queryIntentClass ?? fast.queryIntentClass,
            surfacePreference: interpreted.surfacePreference ?? fast.surfacePreference,
            mode: interpreted.mode,
            kind: interpreted.kind,
            title: interpreted.title,
            objective: interpreted.objective,
            targetDescription: interpreted.targetDescription ?? fast.targetDescription,
            constraints: interpreted.constraints.isEmpty ? fast.explicitHardConstraints : interpreted.constraints,
            desiredOutcomes: interpreted.desiredOutcomes,
            readiness: interpreted.readiness,
            interpretationNotes: interpreted.interpretationNotes,
            confidence: max(interpreted.confidence, fast.confidence * 0.85),
            clarificationQuestion: interpreted.clarificationQuestion,
            userSummary: interpreted.userSummary ?? fast.userSummary,
            userQuestion: interpreted.userQuestion,
            userNextStep: interpreted.userNextStep ?? fast.userNextStep,
            inferredPosture: interpreted.inferredPosture,
            needsClarification: interpreted.needsClarification,
            shouldDiscover: interpreted.shouldDiscover,
            shouldDraft: interpreted.shouldDraft,
            semanticTags: normalizeTagList(
                interpreted.semanticTags + fast.semanticTags,
                maxCount: 12
            ),
            discoveryKeywords: normalizeKeywordList(
                interpreted.discoveryKeywords + fast.discoveryKeywords,
                maxCount: 12
            ),
            targetTags: normalizeTagList(
                interpreted.targetTags + fast.targetTags,
                maxCount: 10
            )
        )
    }

    func mapFastClassificationDTO(
        _ dto: FastClassificationDTO,
        request: ExchangeIntelligenceFastClassificationRequest
    ) -> ExchangeIntelligenceFastClassificationResponse {
        let queryIntentClass = mapQueryIntentClass(dto.lane)
        let surfacePreference: ExchangeIntent.SurfacePreference = {
            if let raw = dto.surface?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return mapSurfacePreference(raw)
            }

            switch queryIntentClass {
            case .providerSearch, .offerSearch:
                return .offer
            case .capabilitySearch, .collaborationSearch:
                return .capability
            case .socialAffinitySearch, .relationshipSearch:
                return .affinity
            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                return .mixed
            }
        }()

        let mode: ExchangeMode = {
            switch queryIntentClass {
            case .socialAffinitySearch, .relationshipSearch:
                return .relational
            case .collaborationSearch:
                return .cooperative
            default:
                return .transactional
            }
        }()

        let kind: ExchangeIntent.Kind = {
            switch queryIntentClass {
            case .providerSearch, .offerSearch, .capabilitySearch, .collaborationSearch,
                 .socialAffinitySearch, .relationshipSearch, .generalDiscovery:
                return .find
            case .directOutreach:
                return .message
            case .followUp:
                return .followUp
            case .statusCheck:
                return .checkStatus
            }
        }()

        let readiness: ExchangeIntent.Readiness = {
            let normalized = normalizeInput(request.userText)
            if normalized.count < 3 { return .underSpecified }
            if request.threadContext?.selectedCounterpartyID != nil { return .ready }
            return .ready
        }()

        let confidence = clampConfidence(dto.confidence ?? 0.92)

        return ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            mode: mode,
            kind: kind,
            readiness: readiness,
            confidence: confidence,
            needsFullLLMInterpretation: dto.needsFullLLMInterpretation ?? false,
            semanticTags: [],
            discoveryKeywords: [],
            targetTags: [],
            providerTerms: [],
            capabilityTerms: [],
            affinityTerms: [],
            regionTerms: [],
            explicitHardConstraints: [],
            targetDescription: nil,
            userSummary: nil,
            userNextStep: nil
        )
    }

    func mapInterpretationDTO(
        _ dto: InterpretationDTO
    ) -> ExchangeIntelligenceInterpretationResponse {
        let mode = mapMode(dto.mode)
        let kind = mapKind(dto.kind)
        let readiness = mapReadiness(dto.readiness)

        let constraints: [ExchangeIntent.Constraint] = (dto.constraints ?? []).compactMap { item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return ExchangeIntent.Constraint(
                key: String(key.prefix(40)),
                value: String(value.prefix(120)),
                isHardConstraint: item.isHardConstraint ?? false
            )
        }

        let desiredOutcomes = mapDesiredOutcomes(dto.desiredOutcomes ?? [])
        let inferredPosture = dto.inferredPosture.map { mapPostureDTO($0) }

        let semanticTags = normalizeTagList(dto.semanticTags ?? [], maxCount: 12)
        let targetTags = normalizeTagList(dto.targetTags ?? [], maxCount: 10)

        let discoveryKeywords = normalizeKeywordList(
            (dto.discoveryKeywords?.isEmpty == false)
                ? (dto.discoveryKeywords ?? [])
                : (targetTags + semanticTags),
            maxCount: 12
        )

        let clampedConfidence = clampConfidence(dto.confidence)
        let title = String(dto.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let objective = String(dto.objective.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))

        let finalNeedsClarification = dto.needsClarification ?? (readiness != .ready)
        let finalShouldDiscover = dto.shouldDiscover ?? defaultShouldDiscover(for: kind)
        let finalShouldDraft = dto.shouldDraft ?? defaultShouldDraft(for: kind)

        return ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: nil,
            surfacePreference: nil,
            mode: mode,
            kind: kind,
            title: title,
            objective: objective,
            targetDescription: trimmed(dto.targetDescription, limit: 120),
            constraints: constraints,
            desiredOutcomes: desiredOutcomes,
            readiness: readiness,
            interpretationNotes: trimmed(dto.interpretationNotes, limit: 240),
            confidence: clampedConfidence,
            clarificationQuestion: trimmed(dto.clarificationQuestion, limit: 180),
            userSummary: trimmed(dto.userSummary, limit: 220),
            userQuestion: trimmed(dto.userQuestion, limit: 180),
            userNextStep: trimmed(dto.userNextStep, limit: 220),
            inferredPosture: inferredPosture,
            needsClarification: finalNeedsClarification,
            shouldDiscover: finalShouldDiscover,
            shouldDraft: finalShouldDraft,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )
    }

    func mapPostureDTO(
        _ dto: PostureDTO
    ) -> ExchangeIntelligencePostureResponse {
        ExchangeIntelligencePostureResponse(
            urgency: mapUrgency(dto.urgency),
            warmth: mapWarmth(dto.warmth),
            directness: mapDirectness(dto.directness),
            openness: mapOpenness(dto.openness),
            commitment: mapCommitment(dto.commitment),
            privacy: mapPrivacy(dto.privacy),
            priceSensitivity: mapPriceSensitivity(dto.priceSensitivity),
            flexibility: mapFlexibility(dto.flexibility),
            notes: trimmed(dto.notes, limit: 240),
            confidence: clampConfidence(dto.confidence ?? 0.7)
        )
    }

    func mapDraftDTO(
        _ dto: DraftDTO
    ) -> ExchangeIntelligenceDraftResponse {
        ExchangeIntelligenceDraftResponse(
            subject: trimmed(dto.subject, limit: 140),
            body: dto.body.trimmingCharacters(in: .whitespacesAndNewlines),
            strategyNote: trimmed(dto.strategyNote, limit: 240),
            confidence: clampConfidence(dto.confidence)
        )
    }
    
    func mapInboundInquiryDTO(
        _ dto: InboundInquiryDTO,
        request: ExchangeIntelligenceInboundInquiryRequest
    ) -> ExchangeIntelligenceInboundInquiryResponse {
        ExchangeIntelligenceInboundInquiryResponse(
            inquirySummary: trimmed(dto.inquirySummary, limit: 220)
                ?? request.visibleSummary
                ?? String(request.requesterAsk.prefix(220)),
            requesterAsk: trimmed(dto.requesterAsk, limit: 500)
                ?? request.requesterAsk,
            matchedOfferOrProfileAnchor: trimmed(
                dto.matchedOfferOrProfileAnchor,
                limit: 160
            ) ?? request.matchedOfferOrProfileAnchor,
            answerabilityStatus: mapInboundAnswerability(dto.answerabilityStatus),
            classification: mapInboundClassification(dto.classification),
            rationale: trimmed(dto.rationale, limit: 240),
            confidence: clampConfidence(dto.confidence ?? 0.65)
        )
    }

    func mapRequesterMatchCompareDTO(_ dto: RequesterMatchCompareDTO) -> ExchangeRequesterMatchCompareResult {
        let missing = normalizedCompareLines(dto.missingFacts, cap: 16, maxLen: 220)
        let questions = normalizedCompareLines(dto.providerQuestions, cap: 8, maxLen: 360)
        let should = dto.shouldAskProvider ?? !questions.isEmpty
        return ExchangeRequesterMatchCompareResult(
            missingFacts: missing,
            providerQuestions: questions,
            shouldAskProvider: should,
            reason: trimmed(dto.reason, limit: 400) ?? ""
        )
    }

    static func requesterMatchEvidenceHaystack(
        offerSummary: String?,
        profileSummary: String?,
        knownFacts: [String]
    ) -> String {
        {
            var parts: [String] = []
            if let offerSummary { parts.append(offerSummary) }
            if let profileSummary { parts.append(profileSummary) }
            if !knownFacts.isEmpty { parts.append(knownFacts.joined(separator: " ")) }
            return parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
                .lowercased()
        }()
    }

    func mapProviderInquiryCompareDTO(_ dto: ProviderInquiryCompareDTO) -> ExchangeProviderInquiryCompareResult {
        let known = normalizedCompareLines(dto.knownAnswers, cap: 12, maxLen: 280)
        let missing = normalizedCompareLines(dto.missingFacts, cap: 12, maxLen: 220)
        let answerable = dto.answerableFromOffer ?? false
        let needsInput = dto.needsProviderInput ?? !answerable
        let draftFromDTO = trimmed(dto.draftReply, limit: 1200)
            ?? trimmed(dto.replyToSend, limit: 1200)

        let mappedFacts: [ExchangeProviderInquiryCompareKnownFact] = (dto.knownFacts ?? []).compactMap { row in
            guard let f = row.fact?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty else {
                return nil
            }
            return ExchangeProviderInquiryCompareKnownFact(
                fact: String(f.prefix(360)),
                source: trimmed(row.source, limit: 120),
                confidence: row.confidence
            )
        }

        var mergedKnownAnswers = known
        if mergedKnownAnswers.isEmpty {
            mergedKnownAnswers = mappedFacts.map(\.fact)
        }

        let risk = normalizedCompareLines(dto.riskFlags, cap: 12, maxLen: 120)

        let disposition =
            trimmed(dto.recommendedDisposition, limit: 80)
            ?? trimmed(dto.recommendedAction, limit: 80)

        return ExchangeProviderInquiryCompareResult(
            answerableFromOffer: answerable,
            knownAnswers: mergedKnownAnswers,
            knownFacts: mappedFacts,
            missingFacts: missing,
            needsProviderInput: needsInput,
            draftReply: draftFromDTO,
            reason: trimmed(dto.reason, limit: 400) ?? "",
            intentCategory: trimmed(dto.intentCategory, limit: 80),
            inquirySummary: trimmed(dto.inquirySummary, limit: 240),
            requesterAsk: trimmed(dto.requesterAsk, limit: 500),
            riskFlags: risk,
            recommendedDisposition: disposition,
            canSendWithinConsent: dto.canSendWithinConsent,
            requiresBoundaryApproval: dto.requiresBoundaryApproval,
            consentBasis: trimmed(dto.consentBasis, limit: 300),
            boundaryCrossingReason: trimmed(dto.boundaryCrossingReason, limit: 300)
        )
    }

    func normalizedCompareLines(_ raw: [String]?, cap: Int, maxLen: Int) -> [String] {
        var out: [String] = []
        for s in raw ?? [] {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let clipped = String(t.prefix(maxLen))
            out.append(clipped)
            if out.count >= cap { break }
        }
        return out
    }

    func mapInboundAnswerability(
        _ raw: String
    ) -> ExchangeInboundInquiryAnswerability {
        switch normalizedLooseEnum(raw) {
        case "answerablefromknownfacts", "answerable", "knownfacts":
            return .answerableFromKnownFacts
        case "requiresuserinput", "userinput", "needsuserinput":
            return .requiresUserInput
        case "outofscope", "outsidescope":
            return .outOfScope
        default:
            return .insufficientContext
        }
    }

    func mapInboundClassification(
        _ raw: String
    ) -> ExchangeInboundInquiryClassification {
        switch normalizedLooseEnum(raw) {
        case "exceptional", "custom", "highjudgment", "sensitive":
            return .exceptional
        default:
            return .routine
        }
    }

    func defaultShouldDiscover(for kind: ExchangeIntent.Kind) -> Bool {
        switch kind {
        case .find, .source, .introduce, .requestQuote:
            return true
        case .message, .followUp, .checkStatus, .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan, .negotiate, .other:
            return false
        }
    }

    func defaultShouldDraft(for kind: ExchangeIntent.Kind) -> Bool {
        switch kind {
        case .message, .followUp, .checkStatus, .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan, .negotiate:
            return true
        case .find, .source, .introduce, .requestQuote, .other:
            return false
        }
    }

    func mapDesiredOutcomes(_ rawValues: [String]) -> [ExchangeIntent.DesiredOutcome] {
        var output: [ExchangeIntent.DesiredOutcome] = []
        var seen = Set<ExchangeIntent.DesiredOutcome>()

        for raw in rawValues {
            guard let mapped = mapDesiredOutcome(raw), !seen.contains(mapped) else { continue }
            seen.insert(mapped)
            output.append(mapped)
        }

        return output
    }

    func mapQueryIntentClass(_ raw: String) -> ExchangeIntent.QueryIntentClass {
        switch normalizedLooseEnum(raw) {
        case "providersearch":
            return .providerSearch
        case "offersearch":
            return .offerSearch
        case "capabilitysearch":
            return .capabilitySearch
        case "collaborationsearch":
            return .collaborationSearch
        case "socialaffinitysearch":
            return .socialAffinitySearch
        case "relationshipsearch":
            return .relationshipSearch
        case "directoutreach":
            return .directOutreach
        case "followup":
            return .followUp
        case "statuscheck":
            return .statusCheck
        default:
            return .generalDiscovery
        }
    }

    func mapSurfacePreference(_ raw: String) -> ExchangeIntent.SurfacePreference {
        switch normalizedLooseEnum(raw) {
        case "offer":
            return .offer
        case "capability":
            return .capability
        case "affinity":
            return .affinity
        default:
            return .mixed
        }
    }

    func mapMode(_ raw: String) -> ExchangeMode {
        switch normalizedLooseEnum(raw) {
        case "transactional":
            return .transactional
        case "cooperative":
            return .cooperative
        case "relational":
            return .relational
        default:
            return .transactional
        }
    }

    func mapKind(_ raw: String) -> ExchangeIntent.Kind {
        switch normalizedLooseEnum(raw) {
        case "requestquote", "quote", "request_quote":
            return .requestQuote
        case "introduce", "intro", "introduction":
            return .introduce
        case "negotiate", "negotiation":
            return .negotiate
        case "arrangecall", "call", "schedulecall":
            return .arrangeCall
        case "arrangemeeting", "meeting", "schedulemeeting":
            return .arrangeMeeting
        case "followup", "follow_up":
            return .followUp
        case "checkstatus", "status":
            return .checkStatus
        case "invite", "invitation":
            return .invite
        case "source", "sourcing":
            return .source
        case "find", "search", "lookup":
            return .find
        case "message", "contact", "reachout", "outreach":
            return .message
        case "coordinate", "coordination":
            return .coordinate
        case "plan", "planning":
            return .plan
        default:
            return .other
        }
    }

    func mapReadiness(_ raw: String) -> ExchangeIntent.Readiness {
        switch normalizedLooseEnum(raw) {
        case "ready":
            return .ready
        case "needsclarification", "clarificationneeded", "needclarification":
            return .needsClarification
        default:
            return .underSpecified
        }
    }

    func mapDesiredOutcome(_ raw: String) -> ExchangeIntent.DesiredOutcome? {
        let value = normalizedLoosePhrase(raw)

        if value.contains("shortlist") || value.contains("list") || value.contains("candidates") || value.contains("matches") {
            return .shortlist
        }
        if value.contains("intro") || value.contains("introduc") {
            return .intro
        }
        if value.contains("quote") || value.contains("estimate") || value.contains("pricing") {
            return .quote
        }
        if value.contains("meeting") || value.contains("call") || value.contains("schedule") {
            return .meeting
        }
        if value.contains("response") || value.contains("reply") || value.contains("message") || value.contains("outreach") || value.contains("draft") {
            return .response
        }
        if value.contains("align") || value.contains("agreement") || value.contains("coordinate") {
            return .aligned
        }
        if value.contains("resolve") || value.contains("resolved") || value.contains("complete") {
            return .resolved
        }

        return nil
    }

    func mapUrgency(_ raw: String) -> ExchangePosture.Urgency {
        switch normalizedLooseEnum(raw) {
        case "low":
            return .low
        case "normal", "medium", "moderate", "standard":
            return .normal
        case "high", "urgent", "soon":
            return .high
        case "immediate", "asap":
            return .immediate
        default:
            return .normal
        }
    }

    func mapWarmth(_ raw: String) -> ExchangePosture.Warmth {
        switch normalizedLooseEnum(raw) {
        case "reserved", "formal":
            return .reserved
        case "warm", "friendly":
            return .warm
        default:
            return .neutral
        }
    }

    func mapDirectness(_ raw: String) -> ExchangePosture.Directness {
        switch normalizedLooseEnum(raw) {
        case "soft", "gentle":
            return .soft
        case "firm", "direct":
            return .firm
        default:
            return .balanced
        }
    }

    func mapOpenness(_ raw: String) -> ExchangePosture.Openness {
        switch normalizedLooseEnum(raw) {
        case "exploratory", "open", "broad":
            return .exploratory
        default:
            return .selective
        }
    }

    func mapCommitment(_ raw: String) -> ExchangePosture.Commitment {
        switch normalizedLooseEnum(raw) {
        case "serious", "active":
            return .serious
        case "committed", "decided":
            return .committed
        default:
            return .exploring
        }
    }

    func mapPrivacy(_ raw: String) -> ExchangePosture.Privacy {
        switch normalizedLooseEnum(raw) {
        case "guarded", "private":
            return .guarded
        case "disclosive", "open", "transparent":
            return .disclosive
        default:
            return .balanced
        }
    }

    func mapPriceSensitivity(_ raw: String) -> ExchangePosture.PriceSensitivity {
        switch normalizedLooseEnum(raw) {
        case "low":
            return .low
        case "moderate", "medium", "normal":
            return .moderate
        case "high", "budgetsensitive", "budget":
            return .high
        default:
            return .notSpecified
        }
    }

    func mapFlexibility(_ raw: String) -> ExchangePosture.Flexibility {
        switch normalizedLooseEnum(raw) {
        case "rigid", "strict":
            return .rigid
        case "flexible", "open":
            return .flexible
        default:
            return .moderate
        }
    }

    func normalizedLooseEnum(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    func normalizedLoosePhrase(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func clampConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    func normalizeTagList(_ raw: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for item in raw {
            let normalized = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !normalized.isEmpty else { continue }
            guard normalized.count <= 48 else { continue }
            guard !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            output.append(normalized)

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    func normalizeKeywordList(_ raw: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for item in raw {
            let normalized = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !normalized.isEmpty else { continue }
            guard normalized.count <= 64 else { continue }
            guard !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            output.append(normalized)

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    func normalizeInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func trimmed(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(limit))
    }
}

// MARK: - Fallback helpers reused here

private extension OnDeviceExchangeIntelligenceProvider {
    func fallbackTitle(
        for kind: ExchangeIntent.Kind,
        text: String,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> String {
        let clipped = String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .requestQuote: return "Request Quote"
        case .introduce: return "Request Introduction"
        case .message: return threadContext?.selectedCounterpartyID != nil ? "Continue Message" : "Send Message"
        case .find: return "Find Match"
        case .source: return "Source Match"
        case .arrangeCall: return "Arrange Call"
        case .arrangeMeeting: return "Arrange Meeting"
        case .followUp: return "Follow Up"
        case .checkStatus: return "Check Status"
        case .invite: return "Invite"
        case .coordinate: return "Coordinate"
        case .plan: return "Plan"
        case .negotiate: return "Negotiate"
        case .other:
            return clipped.isEmpty ? (threadContext?.priorIntentTitle ?? "Exchange Request") : clipped
        }
    }

    func fallbackDesiredOutcomes(for kind: ExchangeIntent.Kind) -> [ExchangeIntent.DesiredOutcome] {
        switch kind {
        case .find, .source:
            return [.shortlist]
        case .introduce:
            return [.intro]
        case .requestQuote:
            return [.quote]
        case .arrangeCall, .arrangeMeeting:
            return [.meeting]
        case .message, .followUp, .checkStatus:
            return [.response]
        case .negotiate, .invite, .coordinate, .plan:
            return [.aligned]
        case .other:
            return [.resolved]
        }
    }

    func fallbackClarificationQuestion(for kind: ExchangeIntent.Kind) -> String {
        switch kind {
        case .requestQuote:
            return "What exactly do you want quoted, and what location or scope should I use?"
        case .introduce:
            return "Who do you want to be introduced to, or what kind of person should I look for?"
        case .message:
            return "Who should I contact, and what outcome do you want from the message?"
        case .arrangeCall, .arrangeMeeting:
            return "Who should I coordinate with, and what timing or purpose should I use?"
        case .find, .source:
            return "What kind of person or provider are you looking for, and what matters most in the match?"
        case .negotiate:
            return "What terms are you trying to move, and what outcome would count as acceptable?"
        case .followUp, .checkStatus:
            return "Which thread or contact should I follow up on?"
        case .invite:
            return "Who should be invited, and to what?"
        case .coordinate, .plan, .other:
            return "What is the specific coordination outcome you want me to help move forward?"
        }
    }
}

// MARK: - Validation / cleanup

private extension OnDeviceExchangeIntelligenceProvider {
    enum ProviderInquiryCompareJSONRejectionReason: Error {
        /// Top-level JSON array `[` — invalid for this task (do not unwrap nested objects).
        case topLevelArray
        /// Output empty after fence strip.
        case emptyOutput
        /// No valid top-level JSON object (extraction or `NSDictionary` parse failed).
        case missingRequiredObject

        /// Stable token for logs / fallback tagging (`empty_output`, `missing_required_object`, …).
        var logTag: String {
            switch self {
            case .topLevelArray:
                return "top_level_array"
            case .emptyOutput:
                return "empty_output"
            case .missingRequiredObject:
                return "missing_required_object"
            }
        }
    }

    /// Strips optional markdown fences only — does not extract inner `{...}` from arrays (used by provider inquiry compare diagnostics + decode).
    static func stripJSONCodeFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let closing = text.range(of: "```", options: .backwards) {
                text.removeSubrange(closing)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.lowercased().hasPrefix("json\n") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    /// First `[` or `{` outside JSON strings — used to reject top-level arrays for provider inquiry compare.
    static func firstJSONStructuralDelimiter(_ text: String) -> Character? {
        var inString = false
        var escaped = false
        for ch in text {
            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    continue
                }
                if ch == "\"" {
                    inString = false
                }
                continue
            }
            if ch == "\"" {
                inString = true
                continue
            }
            if ch == "[" || ch == "{" {
                return ch
            }
        }
        return nil
    }

    /// Requires a single top-level JSON **object**; rejects arrays (does not unwrap the first element from `[{...}]`).
    static func cleanedJSONObjectStringForProviderInquiryCompare(_ raw: String) -> Result<String, ProviderInquiryCompareJSONRejectionReason> {
        let text = stripJSONCodeFences(raw)
        if text.isEmpty {
            return .failure(.emptyOutput)
        }

        // Reject top-level JSON array (including `[{...}]`) — do not extract the first nested object.
        let trimmedForBracketCheck = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedForBracketCheck.hasPrefix("[") {
            return .failure(.topLevelArray)
        }

        if let delim = firstJSONStructuralDelimiter(text) {
            if delim == "[" {
                return .failure(.topLevelArray)
            }
        } else {
            return .failure(.missingRequiredObject)
        }

        guard let extracted = extractFirstBalancedJSONObject(from: text) else {
            return .failure(.missingRequiredObject)
        }

        guard let data = extracted.data(using: String.Encoding.utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              obj is NSDictionary
        else {
            return .failure(.missingRequiredObject)
        }

        return .success(extracted)
    }

    static func providerInquiryCompareConservativeDecodeFallback(debugTag: String) -> ExchangeProviderInquiryCompareResult {
        ExchangeProviderInquiryCompareResult(
            answerableFromOffer: false,
            knownAnswers: [],
            knownFacts: [],
            missingFacts: [],
            needsProviderInput: true,
            draftReply: nil,
            reason: "provider_inquiry_compare_decode_fallback: \(debugTag)",
            recommendedDisposition: "askProviderInput",
            canSendWithinConsent: false,
            requiresBoundaryApproval: false
        )
    }

    static func cleanJSON(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let closing = text.range(of: "```", options: .backwards) {
                text.removeSubrange(closing)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.lowercased().hasPrefix("json\n") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let extracted = extractFirstBalancedJSONObject(from: text) {
            #if DEBUG
            print("[ExchangeAI][Provider] cleanJSON extractedBalancedObject inChars=\(raw.count) outChars=\(extracted.count)")
            #endif
            return extracted
        }

        #if DEBUG
        print("[ExchangeAI][Provider] cleanJSON inChars=\(raw.count) outChars=\(text.count)")
        #endif

        return text
    }

    static func extractFirstBalancedJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var endIndex: String.Index?

        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = idx
                        break
                    }
                }
            }

            idx = text.index(after: idx)
        }

        guard let endIndex, depth == 0 else { return nil }
        return String(text[start...endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isUsable(_ response: ExchangeIntelligenceFastClassificationResponse) -> Bool {
        let ok = response.confidence >= 0.20

        #if DEBUG
        print(
            "[ExchangeAI][Provider][fastClassify] usability " +
            "ok=\(ok) " +
            "confidence=\(response.confidence) " +
            "queryClass=\(response.queryIntentClass.rawValue) " +
            "surface=\(response.surfacePreference.rawValue)"
        )
        #endif

        return ok
    }
    
    func isUsable(
        _ response: ExchangeIntelligenceInboundInquiryResponse
    ) -> Bool {
        let summary = response.inquirySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = response.requesterAsk.trimmingCharacters(in: .whitespacesAndNewlines)

        return !summary.isEmpty &&
            !ask.isEmpty &&
            response.confidence >= 0.20
    }

    func isUsable(_ response: ExchangeIntelligenceInterpretationResponse) -> Bool {
        let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = response.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = !title.isEmpty && !objective.isEmpty

        #if DEBUG
        print(
            "[ExchangeAI][Provider][interpret] usability " +
            "ok=\(ok) " +
            "titleEmpty=\(title.isEmpty) " +
            "objectiveEmpty=\(objective.isEmpty)"
        )
        #endif

        return ok
    }

    func isUsable(_ response: ExchangeIntelligencePostureResponse) -> Bool {
        let ok = response.confidence >= 0.20

        #if DEBUG
        print("[ExchangeAI][Provider][posture] usability ok=\(ok) confidence=\(response.confidence)")
        #endif

        return ok
    }

    func isUsable(_ response: ExchangeIntelligenceDraftResponse) -> Bool {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = !body.isEmpty

        #if DEBUG
        print("[ExchangeAI][Provider][draft] usability ok=\(ok) bodyChars=\(body.count)")
        #endif

        return ok
    }
}
