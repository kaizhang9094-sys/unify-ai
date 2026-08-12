import Foundation

/// App-facing Exchange DTOs.
///
/// These types sit between raw domain objects and UI-specific view models.
/// They should project durable Exchange state into stable, UI-friendly shapes,
/// without re-deciding policy or discovery semantics in the view layer.
///
/// Core alignment:
/// - interpretation = request-side understanding
/// - counterparty = durable external identity/entity
/// - public profile = exposed public coordination surface
public enum ExchangeModels {
    public enum ContactRelationshipType: String, Codable, Sendable, CaseIterable, Hashable {
        case friend
        case client
        case colleague
        case supplier
        case family
        case investor
        case broker
        case contractor
        case lead
        case professionalContact
        case custom
    }

    public enum ContactAIAssistLevel: String, Codable, Sendable, CaseIterable, Hashable {
        case suggestOnly
        case draftBeforeSend
        case autoReplyDisabled
    }

    public enum RelationshipGoal: String, Codable, Sendable, CaseIterable, Hashable {
        case maintainFriendship
        case becomeCloserFriends
        case warmProfessionalContact
        case developClientRelationship
        case winFutureContract
        case explorePartnership
        case buildInvestorRelationship
        case maintainSupplierRelationship
        case referralContact
        case reconnectCasually
        case personalRelationship
        case custom
    }

    public struct ContactContext: Codable, Sendable, Hashable {
        public var remoteNodeID: String
        public var displayNameOverride: String?
        public var relationshipType: ContactRelationshipType
        public var customRelationshipLabel: String?
        public var relationshipGoal: RelationshipGoal
        public var customRelationshipGoal: String?
        public var goalNotes: String?
        public var notes: String
        public var toneOverride: String?
        public var aiAssistLevel: ContactAIAssistLevel
        public var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case remoteNodeID
            case displayNameOverride
            case relationshipType
            case customRelationshipLabel
            case relationshipGoal
            case customRelationshipGoal
            case goalNotes
            case notes
            case toneOverride
            case aiAssistLevel
            case updatedAt
        }

        public init(
            remoteNodeID: String,
            displayNameOverride: String? = nil,
            relationshipType: ContactRelationshipType = .professionalContact,
            customRelationshipLabel: String? = nil,
            relationshipGoal: RelationshipGoal? = nil,
            customRelationshipGoal: String? = nil,
            goalNotes: String? = nil,
            notes: String = "",
            toneOverride: String? = nil,
            aiAssistLevel: ContactAIAssistLevel = .suggestOnly,
            updatedAt: Date = Date()
        ) {
            self.remoteNodeID = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayNameOverride = displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.relationshipType = relationshipType
            self.customRelationshipLabel = customRelationshipLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.relationshipGoal = relationshipGoal ?? Self.defaultGoal(for: relationshipType)
            self.customRelationshipGoal = customRelationshipGoal?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.goalNotes = goalNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            self.toneOverride = toneOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.aiAssistLevel = aiAssistLevel
            self.updatedAt = updatedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let remoteNodeID = try container.decode(String.self, forKey: .remoteNodeID)
            let displayNameOverride = try container.decodeIfPresent(String.self, forKey: .displayNameOverride)
            let relationshipType = try container.decodeIfPresent(ContactRelationshipType.self, forKey: .relationshipType) ?? .professionalContact
            let customRelationshipLabel = try container.decodeIfPresent(String.self, forKey: .customRelationshipLabel)
            let relationshipGoal = try container.decodeIfPresent(RelationshipGoal.self, forKey: .relationshipGoal)
            let customRelationshipGoal = try container.decodeIfPresent(String.self, forKey: .customRelationshipGoal)
            let goalNotes = try container.decodeIfPresent(String.self, forKey: .goalNotes)
            let notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
            let toneOverride = try container.decodeIfPresent(String.self, forKey: .toneOverride)
            let aiAssistLevel = try container.decodeIfPresent(ContactAIAssistLevel.self, forKey: .aiAssistLevel) ?? .suggestOnly
            let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

            self.init(
                remoteNodeID: remoteNodeID,
                displayNameOverride: displayNameOverride,
                relationshipType: relationshipType,
                customRelationshipLabel: customRelationshipLabel,
                relationshipGoal: relationshipGoal ?? Self.defaultGoal(for: relationshipType),
                customRelationshipGoal: customRelationshipGoal,
                goalNotes: goalNotes,
                notes: notes,
                toneOverride: toneOverride,
                aiAssistLevel: aiAssistLevel,
                updatedAt: updatedAt
            )
        }

        public static func defaultFor(remoteNodeID: String) -> ContactContext {
            ContactContext(
                remoteNodeID: remoteNodeID,
                relationshipType: .professionalContact,
                relationshipGoal: .warmProfessionalContact,
                aiAssistLevel: .suggestOnly
            )
        }

        public static func defaultGoal(for relationshipType: ContactRelationshipType) -> RelationshipGoal {
            switch relationshipType {
            case .friend, .family:
                return .maintainFriendship
            case .client, .lead:
                return .developClientRelationship
            case .supplier, .contractor:
                return .maintainSupplierRelationship
            case .investor, .broker:
                return .buildInvestorRelationship
            case .colleague, .professionalContact, .custom:
                return .warmProfessionalContact
            }
        }
    }

    public struct ContactReplySuggestion: Codable, Sendable, Hashable {
        public var reply: String
        public var reason: String?
        public var safety: String?
        public var requiresApproval: Bool

        public init(
            reply: String,
            reason: String? = nil,
            safety: String? = nil,
            requiresApproval: Bool = true
        ) {
            self.reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.safety = safety?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.requiresApproval = requiresApproval
        }
    }

    public enum DirectReplyTranscriptRole: String, Codable, Sendable, Hashable {
        case localUser
        case remoteContact
    }

    public struct DirectReplyTranscriptMessage: Codable, Sendable, Hashable {
        public var role: DirectReplyTranscriptRole
        public var text: String
        public var timestamp: Date?
        public var source: String?

        public init(
            role: DirectReplyTranscriptRole,
            text: String,
            timestamp: Date? = nil,
            source: String? = nil
        ) {
            self.role = role
            self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.timestamp = timestamp
            self.source = source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    public struct DirectReplySuggestionInput: Codable, Sendable, Hashable {
        public var remoteNodeID: String
        /// Local user's display name for voice anchoring (e.g. onboarding name, Exchange identity, or "Me").
        public var localUserDisplayName: String?
        public var contactDisplayName: String?
        public var latestIncomingMessage: String?
        public var recentTranscript: [DirectReplyTranscriptMessage]
        public var contactContext: ContactContext
        public var relationshipType: ContactRelationshipType
        public var relationshipGoal: RelationshipGoal
        public var relationshipNotes: String
        public var toneOverride: String?
        public var userSecretaryStyle: String?
        public var userSecretaryConstitution: String?
        public var contactPublicProfileSummary: String?
        public var contactCommercialProfileSummary: String?
        public var safetyRules: [String]

        public init(
            remoteNodeID: String,
            localUserDisplayName: String? = nil,
            contactDisplayName: String? = nil,
            latestIncomingMessage: String? = nil,
            recentTranscript: [DirectReplyTranscriptMessage],
            contactContext: ContactContext,
            relationshipType: ContactRelationshipType,
            relationshipGoal: RelationshipGoal,
            relationshipNotes: String,
            toneOverride: String? = nil,
            userSecretaryStyle: String? = nil,
            userSecretaryConstitution: String? = nil,
            contactPublicProfileSummary: String? = nil,
            contactCommercialProfileSummary: String? = nil,
            safetyRules: [String]
        ) {
            self.remoteNodeID = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.localUserDisplayName = localUserDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.contactDisplayName = contactDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.latestIncomingMessage = latestIncomingMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.recentTranscript = recentTranscript
            self.contactContext = contactContext
            self.relationshipType = relationshipType
            self.relationshipGoal = relationshipGoal
            self.relationshipNotes = relationshipNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            self.toneOverride = toneOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.userSecretaryStyle = userSecretaryStyle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.userSecretaryConstitution = userSecretaryConstitution?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.contactPublicProfileSummary = contactPublicProfileSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.contactCommercialProfileSummary = contactCommercialProfileSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.safetyRules = safetyRules
        }
    }

    public struct DirectReplySuggestionOutput: Codable, Sendable, Hashable {
        public var reply: String
        public var reason: String?
        public var safety: String?
        public var requiresApproval: Bool
        /// Set when the service substitutes policy fallback (`parse_failed`, `duplicate`, `runner_failed`).
        public var fallbackReason: String?
        /// `none`, `success`, or `failed` for duplicate anti-echo retry.
        public var duplicateRetry: String?

        public init(
            reply: String,
            reason: String? = nil,
            safety: String? = nil,
            requiresApproval: Bool = true,
            fallbackReason: String? = nil,
            duplicateRetry: String? = nil
        ) {
            self.reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.safety = safety?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.requiresApproval = true
            self.fallbackReason = fallbackReason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.duplicateRetry = duplicateRetry?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        }
    }

    public struct ContactRequestSendResult: Sendable, Hashable {
        public var targetNodeID: String
        public var threadID: ExchangeThread.ID?
        public var outboxItemID: ExchangeOutboxItem.ID?
        public var envelopeID: String?
        public var outgoingContactRequestID: OutgoingContactRequest.ID?
        public var hydratedFromDirectory: Bool

        public init(
            targetNodeID: String,
            threadID: ExchangeThread.ID?,
            outboxItemID: ExchangeOutboxItem.ID?,
            envelopeID: String?,
            outgoingContactRequestID: OutgoingContactRequest.ID? = nil,
            hydratedFromDirectory: Bool
        ) {
            self.targetNodeID = targetNodeID
            self.threadID = threadID
            self.outboxItemID = outboxItemID
            self.envelopeID = envelopeID
            self.outgoingContactRequestID = outgoingContactRequestID
            self.hydratedFromDirectory = hydratedFromDirectory
        }
    }

    public struct ContactRequestItem: Sendable, Hashable, Identifiable {
        public var id: String
        public var requesterNodeID: String?
        public var displayName: String
        public var note: String?
        public var receivedAt: Date
        public var sourceInboxItemIDs: [ExchangeInboxItem.ID]
        public var sourceEnvelopeIDs: [String]
        public var pendingCount: Int
        public var avatarImageURL: String?

        public init(
            id: String,
            requesterNodeID: String?,
            displayName: String,
            note: String?,
            receivedAt: Date,
            sourceInboxItemIDs: [ExchangeInboxItem.ID],
            sourceEnvelopeIDs: [String],
            pendingCount: Int,
            avatarImageURL: String? = nil
        ) {
            self.id = id
            self.requesterNodeID = requesterNodeID
            self.displayName = displayName
            self.note = note
            self.receivedAt = receivedAt
            self.sourceInboxItemIDs = sourceInboxItemIDs
            self.sourceEnvelopeIDs = sourceEnvelopeIDs
            self.pendingCount = max(1, pendingCount)
            self.avatarImageURL = avatarImageURL
        }
    }

    /// Summary of an activated child coordination thread under an umbrella search workbench.
    public struct CoordinationChildThreadSummary: Sendable, Hashable, Identifiable {
        public var id: ExchangeThread.ID { childThreadID }

        public var childThreadID: ExchangeThread.ID
        public var parentThreadID: ExchangeThread.ID
        public var rootThreadID: ExchangeThread.ID
        public var sourceMatchID: ExchangeMatch.ID?
        public var sourceRank: Int?
        public var counterpartyID: ExchangeCounterparty.ID
        public var publicProfileID: ExchangePublicNodeProfile.ID?
        public var offerID: ExchangeOffer.ID?
        public var displayName: String?
        public var headline: String?
        public var matchSummary: String?
        public var primaryImageURL: String?

        /// Desk/list structural fields (no offer/profile hydration).
        public var childState: ExchangeState?
        public var stateTitle: String?
        public var updatedAt: Date?
        public var requiresHumanDecision: Bool
        public var hasPendingApproval: Bool
        public var hasFailure: Bool
        public var awaitingReply: Bool

        public init(
            childThreadID: ExchangeThread.ID,
            parentThreadID: ExchangeThread.ID,
            rootThreadID: ExchangeThread.ID,
            sourceMatchID: ExchangeMatch.ID? = nil,
            sourceRank: Int? = nil,
            counterpartyID: ExchangeCounterparty.ID,
            publicProfileID: ExchangePublicNodeProfile.ID? = nil,
            offerID: ExchangeOffer.ID? = nil,
            displayName: String? = nil,
            headline: String? = nil,
            matchSummary: String? = nil,
            primaryImageURL: String? = nil,
            childState: ExchangeState? = nil,
            stateTitle: String? = nil,
            updatedAt: Date? = nil,
            requiresHumanDecision: Bool = false,
            hasPendingApproval: Bool = false,
            hasFailure: Bool = false,
            awaitingReply: Bool = false
        ) {
            self.childThreadID = childThreadID
            self.parentThreadID = parentThreadID
            self.rootThreadID = rootThreadID
            self.sourceMatchID = sourceMatchID
            self.sourceRank = sourceRank
            self.counterpartyID = counterpartyID
            self.publicProfileID = publicProfileID?.nilIfBlank
            self.offerID = offerID?.nilIfBlank
            self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.headline = headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.matchSummary = matchSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.primaryImageURL = primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.childState = childState
            self.stateTitle = stateTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.updatedAt = updatedAt
            self.requiresHumanDecision = requiresHumanDecision
            self.hasPendingApproval = hasPendingApproval
            self.hasFailure = hasFailure
            self.awaitingReply = awaitingReply
        }
    }

    public struct ThreadDetail: Sendable, Hashable {
        public var thread: ExchangeThread
        public var turns: [ExchangeTurn]
        public var approvals: [ExchangeApproval]
        public var drafts: [ExchangeMessageDraft]
        public var matches: [ExchangeMatch]
        public var counterparties: [ExchangeCounterparty]
        public var artifacts: [ExchangeArtifact]

        /// Federation-adjacent state for thread detail screens.
        public var outboxItems: [ExchangeOutboxItem]
        public var inboxItems: [ExchangeInboxItem]
        public var auditRecords: [ExchangeAuditRecord]

        /// Pre-shaped, app-facing timeline items.
        public var timelineItems: [ThreadTimelineItem]

        public var summary: String

        /// App-facing convenience mirrors of the durable request-side interpretation layer.
        public var interpretationSummary: String?
        public var interpretationQuestion: String?
        public var interpretationNextStep: String?
        public var semanticTags: [String]
        public var discoveryKeywords: [String]
        public var targetTags: [String]
        public var shouldFederate: Bool

        /// App-facing selected match / seller-surface projection.
        public var selectedCounterparty: ExchangeCounterparty?
        public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
        public var selectedOfferID: ExchangeOffer.ID?
        /// Discovery `selectBestMatch` anchor persisted on umbrella threads (metadata-backed).
        public var canonicalDiscoverySelectedOfferID: ExchangeOffer.ID?
        /// Primary activated coordination child offer when umbrella search defers thread selection.
        public var primaryCoordinationChildOfferID: ExchangeOffer.ID?
        public var selectedMatch: ExchangeMatch?

        /// App-facing translated work trace.
        public var workTrace: WorkTraceCard?

        /// App-facing second-half projection.
        ///
        /// This is the clean bridge from the new ExchangeSecondHalf module into
        /// existing UI surfaces. Views should prefer this when present, without
        /// directly calling second-half engines.
        public var secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel?

        /// Structural role for umbrella vs child coordination threads.
        public var threadRole: ExchangeThreadRole
        public var parentThreadID: ExchangeThread.ID?
        public var rootThreadID: ExchangeThread.ID?
        public var sourceMatchID: ExchangeMatch.ID?
        public var sourceRank: Int?
        /// Activated child coordination threads when this detail is an umbrella workbench.
        public var coordinationChildren: [CoordinationChildThreadSummary]

        /// Thread that owns compare / full match workbench (umbrella for child threads).
        public var compareWorkbenchThreadID: ExchangeThread.ID {
            if threadRole == .candidateCoordination, let parentThreadID {
                return parentThreadID
            }
            return thread.id
        }

        public init(
            thread: ExchangeThread,
            turns: [ExchangeTurn],
            approvals: [ExchangeApproval],
            drafts: [ExchangeMessageDraft],
            matches: [ExchangeMatch],
            counterparties: [ExchangeCounterparty],
            artifacts: [ExchangeArtifact],
            outboxItems: [ExchangeOutboxItem] = [],
            inboxItems: [ExchangeInboxItem] = [],
            auditRecords: [ExchangeAuditRecord] = [],
            timelineItems: [ThreadTimelineItem] = [],
            summary: String,
            interpretationSummary: String? = nil,
            interpretationQuestion: String? = nil,
            interpretationNextStep: String? = nil,
            semanticTags: [String] = [],
            discoveryKeywords: [String] = [],
            targetTags: [String] = [],
            shouldFederate: Bool? = nil,
            selectedCounterparty: ExchangeCounterparty? = nil,
            selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
            selectedOfferID: ExchangeOffer.ID? = nil,
            canonicalDiscoverySelectedOfferID: ExchangeOffer.ID? = nil,
            primaryCoordinationChildOfferID: ExchangeOffer.ID? = nil,
            selectedMatch: ExchangeMatch? = nil,
            workTrace: WorkTraceCard? = nil,
            secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel? = nil,
            threadRole: ExchangeThreadRole? = nil,
            parentThreadID: ExchangeThread.ID? = nil,
            rootThreadID: ExchangeThread.ID? = nil,
            sourceMatchID: ExchangeMatch.ID? = nil,
            sourceRank: Int? = nil,
            coordinationChildren: [CoordinationChildThreadSummary] = []
        ) {
            self.thread = thread
            self.turns = turns
            self.approvals = approvals
            self.drafts = drafts
            self.matches = matches
            self.counterparties = counterparties
            self.artifacts = artifacts
            self.outboxItems = outboxItems
            self.inboxItems = inboxItems
            self.auditRecords = auditRecords
            self.timelineItems = timelineItems
            self.summary = summary

            let interpretation = thread.interpretation

            self.interpretationSummary =
                interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? interpretation?.userSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.interpretationQuestion =
                interpretationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? interpretation?.userQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.interpretationNextStep =
                interpretationNextStep?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? interpretation?.userNextStep?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.semanticTags = semanticTags.isEmpty ? (interpretation?.semanticTags ?? []) : semanticTags
            self.discoveryKeywords = discoveryKeywords.isEmpty ? (interpretation?.discoveryKeywords ?? []) : discoveryKeywords
            self.targetTags = targetTags.isEmpty ? (interpretation?.targetTags ?? []) : targetTags
            self.shouldFederate = shouldFederate ?? interpretation?.shouldFederate ?? false

            self.selectedCounterparty =
                selectedCounterparty
                ?? counterparties.first(where: { $0.id == thread.selectedCounterpartyID })

            self.selectedPublicProfileID = selectedPublicProfileID ?? thread.selectedPublicProfileID
            self.canonicalDiscoverySelectedOfferID =
                canonicalDiscoverySelectedOfferID
                ?? ExchangeThreadCanonicalDiscoverySelectionMetadata.selectedOfferID(from: thread.metadata)
            self.primaryCoordinationChildOfferID =
                primaryCoordinationChildOfferID
                ?? ExchangeThreadCanonicalDiscoverySelectionMetadata.primaryCoordinationChildOfferID(from: thread.metadata)
            self.selectedOfferID =
                selectedOfferID
                ?? thread.selectedOfferID
                ?? self.canonicalDiscoverySelectedOfferID

            let anchorOfferID = self.selectedOfferID
                ?? self.primaryCoordinationChildOfferID

            self.selectedMatch =
                selectedMatch
                ?? matches.first(where: { match in
                    if let rawOffer = anchorOfferID?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !rawOffer.isEmpty {
                        if match.offerID == rawOffer { return true }
                        if match.matchedOfferIDs.contains(rawOffer) { return true }
                    }
                    if let selectedPublicProfileID = thread.selectedPublicProfileID,
                       match.publicProfileID == selectedPublicProfileID {
                        return true
                    }
                    if let selectedCounterpartyID = thread.selectedCounterpartyID,
                       match.counterpartyID == selectedCounterpartyID {
                        return true
                    }
                    return false
                })

            self.workTrace = workTrace ?? WorkTraceCard(thread.workTrace)
            self.secondHalfDisplay = secondHalfDisplay

            self.threadRole = threadRole ?? thread.threadRole
            self.parentThreadID = parentThreadID ?? thread.parentThreadID
            self.rootThreadID = rootThreadID ?? thread.rootThreadID
            self.sourceMatchID = sourceMatchID ?? thread.sourceMatchID
            self.sourceRank = sourceRank ?? thread.sourceRank
            self.coordinationChildren = coordinationChildren
        }
    }

    public struct InboxItem: Sendable, Hashable, Identifiable {
        public var id: ExchangeThread.ID { threadID }

        public var threadID: ExchangeThread.ID
        public var title: String
        public var capturedRequestText: String?
        public var subtitle: String
        public var state: ExchangeState
        public var stateTitle: String
        public var updatedAt: Date

        public var requiresHumanDecision: Bool
        public var hasFailure: Bool

        public var visibleSummary: String?
        public var selectedCounterpartyID: ExchangeCounterparty.ID?
        public var selectedCounterpartyName: String?

        public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
        public var selectedOfferID: ExchangeOffer.ID?
        public var latestMatchID: ExchangeMatch.ID?
        public var latestMatch: ExchangeMatch?

        public var candidateCount: Int
        /// Ranked alternate provider/profile/offer headlines (excludes selected path) for discovery review copy.
        public var alternateCandidateHeadlines: [String]
        public var hasPendingApproval: Bool
        /// True when any persisted draft row exists for the thread (not necessarily user-reviewable external outbound).
        /// Prefer ``hasActionableExternalOutboundDraft`` for “draft ready” / review surfaces.
        public var hasDraft: Bool
        /// True when persisted drafts include an **user-facing renderable** external outbound draft (`ExchangeMessageDraft/hasUserFacingRenderableExternalOutboundDraft(in:thread:)`).
        public var hasActionableExternalOutboundDraft: Bool
        public var awaitingReply: Bool

        public var latestFailureSummary: String?
        public var deliveryStatusText: String?
        public var outcomeStatusText: String?
        public var trustPathSummary: String?
        public var requiresAttentionReason: String?
        public var nextStepText: String?

        // Card-facing fields
        public var selectedMatchSummary: String?
        public var selectedMatchWhy: String?
        public var draftedSubject: String?
        public var draftedBodyPreview: String?
        public var clarificationPrompt: String?
        public var failureWhatHappened: String?
        public var failureWhatDidNotHappen: String?
        public var failureNextMove: String?

        /// App-facing request-side interpretation layer.
        public var interpretationSummary: String?
        public var interpretationQuestion: String?
        public var interpretationNextStep: String?
        public var needsClarification: Bool
        public var shouldDiscover: Bool
        public var shouldDraft: Bool
        public var shouldFederate: Bool
        public var semanticTags: [String]
        public var discoveryKeywords: [String]
        public var targetTags: [String]

        /// Compact app-facing translated work trace for cards/lists.
        ///
        /// This should be projected by the facade/app layer rather than inferred
        /// by the view from raw thread state.
        public var workTrace: WorkTraceCard?

        /// App-facing second-half projection.
        ///
        /// This lets the existing dashboard/thread UI render post-match meaning
        /// without becoming dependent on second-half orchestration internals.
        public var secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel?

        /// Display-only ordered image URL candidates for thread list / pinned slots (hydrated like thread-detail hero).
        public var surfaceListImageURLCandidates: [String]

        /// Inbound federation provider-side threads without a captured user request: use humanized card titles.
        public var prefersInboundProviderCardTitleRewrite: Bool
        /// Sender display for “New message from …” when inbound rewrite applies (avoid raw node ids).
        public var cardInboundSenderLabel: String?
        /// Latest counterparty / inbox preview line for card subtitles.
        public var cardInboundRequesterPreview: String?
        /// Provider-side inbound federation desk (`metadata.inbound_thread`).
        public var isInboundProviderDesk: Bool
        /// Durable inbound envelope receipt on the provider desk thread.
        public var hasFederatedInboundEnvelope: Bool
        /// True when `queuePreparedSecondHalfOutboundSend` is the right primary path (no pending approval row, routine draft).
        public var prefersPreparedUserDirectedOutboundSend: Bool

        public var threadRole: ExchangeThreadRole
        public var parentThreadID: ExchangeThread.ID?
        public var rootThreadID: ExchangeThread.ID?
        public var sourceMatchID: ExchangeMatch.ID?
        public var sourceRank: Int?
        /// Child coordination thread ids when this inbox row is an umbrella search workbench.
        public var coordinationChildThreadIDs: [ExchangeThread.ID]
        /// Structural child path rows for History grouping (desk snapshot; no per-child getThread).
        public var coordinationChildSummaries: [CoordinationChildThreadSummary]
        /// User-facing discovery grade when internal workflow state is weak but classifyShortlist was found.
        public var discoveryProjectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade?

        public init(
            threadID: ExchangeThread.ID,
            title: String,
            capturedRequestText: String? = nil,
            subtitle: String,
            state: ExchangeState,
            stateTitle: String,
            updatedAt: Date,
            requiresHumanDecision: Bool,
            hasFailure: Bool,
            visibleSummary: String? = nil,
            selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
            selectedCounterpartyName: String? = nil,
            selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
            selectedOfferID: ExchangeOffer.ID? = nil,
            latestMatchID: ExchangeMatch.ID? = nil,
            latestMatch: ExchangeMatch? = nil,
            candidateCount: Int = 0,
            alternateCandidateHeadlines: [String] = [],
            hasPendingApproval: Bool = false,
            hasDraft: Bool = false,
            hasActionableExternalOutboundDraft: Bool = false,
            awaitingReply: Bool = false,
            latestFailureSummary: String? = nil,
            deliveryStatusText: String? = nil,
            outcomeStatusText: String? = nil,
            trustPathSummary: String? = nil,
            requiresAttentionReason: String? = nil,
            nextStepText: String? = nil,
            selectedMatchSummary: String? = nil,
            selectedMatchWhy: String? = nil,
            draftedSubject: String? = nil,
            draftedBodyPreview: String? = nil,
            clarificationPrompt: String? = nil,
            failureWhatHappened: String? = nil,
            failureWhatDidNotHappen: String? = nil,
            failureNextMove: String? = nil,
            interpretationSummary: String? = nil,
            interpretationQuestion: String? = nil,
            interpretationNextStep: String? = nil,
            needsClarification: Bool = false,
            shouldDiscover: Bool = false,
            shouldDraft: Bool = false,
            shouldFederate: Bool = false,
            semanticTags: [String] = [],
            discoveryKeywords: [String] = [],
            targetTags: [String] = [],
            workTrace: WorkTraceCard? = nil,
            secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel? = nil,
            surfaceListImageURLCandidates: [String] = [],
            prefersInboundProviderCardTitleRewrite: Bool = false,
            cardInboundSenderLabel: String? = nil,
            cardInboundRequesterPreview: String? = nil,
            isInboundProviderDesk: Bool = false,
            hasFederatedInboundEnvelope: Bool = false,
            prefersPreparedUserDirectedOutboundSend: Bool = false,
            threadRole: ExchangeThreadRole = .standalone,
            parentThreadID: ExchangeThread.ID? = nil,
            rootThreadID: ExchangeThread.ID? = nil,
            sourceMatchID: ExchangeMatch.ID? = nil,
            sourceRank: Int? = nil,
            coordinationChildThreadIDs: [ExchangeThread.ID] = [],
            coordinationChildSummaries: [CoordinationChildThreadSummary] = [],
            discoveryProjectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade? = nil
        ) {
            self.threadID = threadID
            self.title = title
            self.capturedRequestText = capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.subtitle = subtitle
            self.state = state
            self.stateTitle = stateTitle
            self.updatedAt = updatedAt

            self.requiresHumanDecision = requiresHumanDecision
            self.hasFailure = hasFailure

            self.visibleSummary = visibleSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.selectedCounterpartyID = selectedCounterpartyID
            self.selectedCounterpartyName = selectedCounterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.selectedPublicProfileID = selectedPublicProfileID
            self.selectedOfferID = selectedOfferID
            self.latestMatchID = latestMatchID
            self.latestMatch = latestMatch

            self.candidateCount = max(0, candidateCount)
            self.alternateCandidateHeadlines = alternateCandidateHeadlines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.hasPendingApproval = hasPendingApproval
            self.hasDraft = hasDraft
            self.hasActionableExternalOutboundDraft = hasActionableExternalOutboundDraft
            self.awaitingReply = awaitingReply

            self.latestFailureSummary = latestFailureSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.deliveryStatusText = deliveryStatusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.outcomeStatusText = outcomeStatusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.trustPathSummary = trustPathSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.requiresAttentionReason = requiresAttentionReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.nextStepText = nextStepText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.selectedMatchSummary = selectedMatchSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.selectedMatchWhy = selectedMatchWhy?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.draftedSubject = draftedSubject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.draftedBodyPreview = draftedBodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.clarificationPrompt = clarificationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.failureWhatHappened = failureWhatHappened?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.failureWhatDidNotHappen = failureWhatDidNotHappen?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.failureNextMove = failureNextMove?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.interpretationSummary = interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.interpretationQuestion = interpretationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.interpretationNextStep = interpretationNextStep?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.needsClarification = needsClarification
            self.shouldDiscover = shouldDiscover
            self.shouldDraft = shouldDraft
            self.shouldFederate = shouldFederate
            self.semanticTags = semanticTags
            self.discoveryKeywords = discoveryKeywords
            self.targetTags = targetTags
            self.workTrace = workTrace
            self.secondHalfDisplay = secondHalfDisplay
            self.surfaceListImageURLCandidates = surfaceListImageURLCandidates
            self.prefersInboundProviderCardTitleRewrite = prefersInboundProviderCardTitleRewrite
            self.cardInboundSenderLabel = cardInboundSenderLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.cardInboundRequesterPreview = cardInboundRequesterPreview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.isInboundProviderDesk = isInboundProviderDesk
            self.hasFederatedInboundEnvelope = hasFederatedInboundEnvelope
            self.prefersPreparedUserDirectedOutboundSend = prefersPreparedUserDirectedOutboundSend

            self.threadRole = threadRole
            self.parentThreadID = parentThreadID
            self.rootThreadID = rootThreadID
            self.sourceMatchID = sourceMatchID
            self.sourceRank = sourceRank
            self.coordinationChildThreadIDs = coordinationChildThreadIDs
            self.coordinationChildSummaries = coordinationChildSummaries
            self.discoveryProjectedGrade = discoveryProjectedGrade
        }
    }

    /// UI-friendly translated work trace/card shape.
    ///
    /// This projects the durable thread-owned work trace into a shape that
    /// cards and detail screens can render directly without understanding the
    /// raw domain model.
    public struct WorkTraceCard: Sendable, Hashable {
        public enum Status: String, Codable, Sendable, Hashable {
            case idle
            case running
            case completed
            case blocked
        }

        public struct Step: Sendable, Hashable, Identifiable {
            public var id: UUID
            public var key: String
            public var title: String
            public var detail: String?
            public var isActive: Bool
            public var isComplete: Bool
            public var createdAt: Date
            public var updatedAt: Date

            public init(
                id: UUID,
                key: String,
                title: String,
                detail: String?,
                isActive: Bool,
                isComplete: Bool,
                createdAt: Date,
                updatedAt: Date
            ) {
                self.id = id
                self.key = key
                self.title = title
                self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
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

        public var activeStep: Step?
        public var latestStep: Step?
        public var completedStepCount: Int
        public var totalStepCount: Int

        public init(
            status: Status,
            headline: String?,
            steps: [Step],
            updatedAt: Date
        ) {
            self.status = status
            self.headline = headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.steps = steps
            self.updatedAt = updatedAt
            self.activeStep = steps.last(where: { $0.isActive })
            self.latestStep = steps.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.createdAt < rhs.createdAt
            }
            self.completedStepCount = steps.reduce(into: 0) { count, step in
                if step.isComplete { count += 1 }
            }
            self.totalStepCount = steps.count
        }

        public init?(_ snapshot: ExchangeThread.WorkTraceSnapshot?) {
            guard let snapshot else { return nil }

            let status: Status
            switch snapshot.status {
            case .idle:
                status = .idle
            case .running:
                status = .running
            case .completed:
                status = .completed
            case .blocked:
                status = .blocked
            }

            let projectedSteps = snapshot.steps
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                    return lhs.createdAt < rhs.createdAt
                }
                .map {
                    Step(
                        id: $0.id,
                        key: $0.key,
                        title: $0.title,
                        detail: $0.detail,
                        isActive: $0.isActive,
                        isComplete: $0.isComplete,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                }

            self.init(
                status: status,
                headline: snapshot.headline,
                steps: projectedSteps,
                updatedAt: snapshot.updatedAt
            )
        }
    }

    public struct PendingApproval: Sendable, Hashable, Identifiable {
        public var id: ExchangeApproval.ID { approval.id }
        public var threadID: ExchangeThread.ID
        public var approval: ExchangeApproval
        public var draft: ExchangeMessageDraft?
        public var summary: String

        public init(
            threadID: ExchangeThread.ID,
            approval: ExchangeApproval,
            draft: ExchangeMessageDraft?,
            summary: String
        ) {
            self.threadID = threadID
            self.approval = approval
            self.draft = draft
            self.summary = summary
        }
    }

    public struct TrustedNodeItem: Sendable, Hashable, Identifiable {
        public var id: String { nodeID }
        public var nodeID: String
        /// Primary human-facing name for lists (resolved; never a raw node id).
        public var displayName: String
        public var relationshipType: ExchangeTrustEdge.RelationshipType
        public var trustLevel: ExchangeTrustEdge.TrustLevel
        public var scopes: Set<ExchangeTrustEdge.TrustScope>
        public var isMutual: Bool
        public var trustedByCount: Int
        public var trustedByYourTrustedCount: Int
        public var lastConfirmedAt: Date?
        public var note: String?
        /// True when local counterparty has a public coordination surface (required for direct Message send).
        public var hasPublicProfileForMessaging: Bool

        // MARK: - Public coordination surface (optional; from `ExchangePublicNodeProfile` at list time)

        public var publicDisplayName: String?
        public var publicHeadline: String?
        public var publicSummaryLine: String?
        public var publicIntroLine: String?
        public var publicRegionLine: String?
        public var publicOpenToLine: String?
        public var publicActivityLine: String?
        public var publicPrimaryOfferLine: String?
        public var publicImageURL: String?
        /// When the counterparty public profile snapshot was last updated (projection only; not persisted on trust edge).
        public var publicProfileUpdatedAt: Date?
        /// Local seller-surface offer id when list resolution picked a primary offer (diagnostics / correlation).
        public var preferredOfferID: String?
        /// True when any published public-surface field is present for UI affordances.
        public var hasPublicSurface: Bool

        public init(
            nodeID: String,
            displayName: String,
            relationshipType: ExchangeTrustEdge.RelationshipType,
            trustLevel: ExchangeTrustEdge.TrustLevel,
            scopes: Set<ExchangeTrustEdge.TrustScope>,
            isMutual: Bool,
            trustedByCount: Int,
            trustedByYourTrustedCount: Int,
            lastConfirmedAt: Date?,
            note: String?,
            hasPublicProfileForMessaging: Bool = false,
            publicDisplayName: String? = nil,
            publicHeadline: String? = nil,
            publicSummaryLine: String? = nil,
            publicIntroLine: String? = nil,
            publicRegionLine: String? = nil,
            publicOpenToLine: String? = nil,
            publicActivityLine: String? = nil,
            publicPrimaryOfferLine: String? = nil,
            publicImageURL: String? = nil,
            publicProfileUpdatedAt: Date? = nil,
            preferredOfferID: String? = nil,
            hasPublicSurface: Bool = false
        ) {
            self.nodeID = nodeID
            self.displayName = displayName
            self.relationshipType = relationshipType
            self.trustLevel = trustLevel
            self.scopes = scopes
            self.isMutual = isMutual
            self.trustedByCount = max(0, trustedByCount)
            self.trustedByYourTrustedCount = max(0, trustedByYourTrustedCount)
            self.lastConfirmedAt = lastConfirmedAt
            self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.hasPublicProfileForMessaging = hasPublicProfileForMessaging
            self.publicDisplayName = publicDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicHeadline = publicHeadline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicSummaryLine = publicSummaryLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicIntroLine = publicIntroLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicRegionLine = publicRegionLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicOpenToLine = publicOpenToLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicActivityLine = publicActivityLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicPrimaryOfferLine = publicPrimaryOfferLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicImageURL = publicImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicProfileUpdatedAt = publicProfileUpdatedAt
            self.preferredOfferID = preferredOfferID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.hasPublicSurface = hasPublicSurface
        }
    }

    public struct TrustedNodeProfileView: Sendable, Hashable, Identifiable {
        public var id: String { nodeID }
        public var nodeID: String
        public var displayName: String
        public var counterparty: ExchangeCounterparty?
        public var profile: ExchangeTrustedNodeProfile
        public var evidence: [ExchangeTrustEvidence]

        public init(
            nodeID: String,
            displayName: String,
            counterparty: ExchangeCounterparty?,
            profile: ExchangeTrustedNodeProfile,
            evidence: [ExchangeTrustEvidence]
        ) {
            self.nodeID = nodeID
            self.displayName = displayName
            self.counterparty = counterparty
            self.profile = profile
            self.evidence = evidence.sorted { lhs, rhs in
                if lhs.recordedAt != rhs.recordedAt {
                    return lhs.recordedAt > rhs.recordedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    public struct OutboxItemView: Sendable, Hashable, Identifiable {
        public var id: ExchangeOutboxItem.ID { item.id }
        public var item: ExchangeOutboxItem
        public var threadTitle: String?
        public var targetDisplayName: String
        public var statusLine: String
        public var updatedAt: Date

        public init(
            item: ExchangeOutboxItem,
            threadTitle: String?,
            targetDisplayName: String,
            statusLine: String,
            updatedAt: Date
        ) {
            self.item = item
            self.threadTitle = threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.targetDisplayName = targetDisplayName
            self.statusLine = statusLine
            self.updatedAt = updatedAt
        }
    }

    public struct InboxEnvelopeView: Sendable, Hashable, Identifiable {
        public var id: ExchangeInboxItem.ID { item.id }
        public var item: ExchangeInboxItem
        public var threadTitle: String?
        public var senderDisplayName: String
        public var statusLine: String
        public var receivedAt: Date

        public init(
            item: ExchangeInboxItem,
            threadTitle: String?,
            senderDisplayName: String,
            statusLine: String,
            receivedAt: Date
        ) {
            self.item = item
            self.threadTitle = threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.senderDisplayName = senderDisplayName
            self.statusLine = statusLine
            self.receivedAt = receivedAt
        }
    }

    public struct AuditRecordView: Sendable, Hashable, Identifiable {
        public var id: ExchangeAuditRecord.ID { record.id }
        public var record: ExchangeAuditRecord
        public var title: String
        public var subtitle: String?
        public var createdAt: Date

        public init(
            record: ExchangeAuditRecord,
            title: String,
            subtitle: String?,
            createdAt: Date
        ) {
            self.record = record
            self.title = title
            self.subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.createdAt = createdAt
        }
    }

    public struct ThreadTimelineItem: Sendable, Hashable, Identifiable {
        public enum Tone: String, Codable, Sendable, Hashable {
            case neutral
            case active
            case success
            case warning
            case blocked
        }

        public let id: UUID
        public let date: Date
        public let title: String
        public let summary: String
        public let secondary: String?
        public let tone: Tone

        public init(
            id: UUID = UUID(),
            date: Date,
            title: String,
            summary: String,
            secondary: String? = nil,
            tone: Tone = .neutral
        ) {
            self.id = id
            self.date = date
            self.title = title
            self.summary = summary
            self.secondary = secondary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.tone = tone
        }
    }

    public struct PublicProfileView: Sendable, Hashable, Identifiable {
        public var id: String { profile.id }

        public var profile: ExchangePublicNodeProfile
        public var displayName: String
        public var headline: String?

        public var summary: String?
        public var summaryLine: String?
        public var publicIntroLine: String?
        public var discoverabilityLine: String?

        public var publicationStatus: ExchangePublicationState.Status?
        public var publicationStatusText: String?
        public var publicationBadgeText: String?
        public var publicationDetailLine: String?
        public var lastPublishedAt: Date?

        public var activeOfferCount: Int
        public var visibleOfferCount: Int

        public var openToItems: [String]
        public var offerItems: [String]
        public var interestItems: [String]
        public var activityItems: [String]
        public var regionItems: [String]

        public var openToLine: String?
        public var offerLine: String?
        public var interestLine: String?
        public var activityLine: String?
        public var regionLine: String?

        public init(
            profile: ExchangePublicNodeProfile,
            displayName: String,
            headline: String? = nil,
            summary: String? = nil,
            summaryLine: String? = nil,
            publicIntroLine: String? = nil,
            discoverabilityLine: String? = nil,
            publicationStatus: ExchangePublicationState.Status? = nil,
            publicationStatusText: String? = nil,
            publicationBadgeText: String? = nil,
            publicationDetailLine: String? = nil,
            lastPublishedAt: Date? = nil,
            activeOfferCount: Int = 0,
            visibleOfferCount: Int = 0,
            openToItems: [String] = [],
            offerItems: [String] = [],
            interestItems: [String] = [],
            activityItems: [String] = [],
            regionItems: [String] = [],
            openToLine: String? = nil,
            offerLine: String? = nil,
            interestLine: String? = nil,
            activityLine: String? = nil,
            regionLine: String? = nil
        ) {
            self.profile = profile
            self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            self.headline = headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.summaryLine = summaryLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicIntroLine = publicIntroLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.discoverabilityLine = discoverabilityLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            self.publicationStatus = publicationStatus
            self.publicationStatusText = publicationStatusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicationBadgeText = publicationBadgeText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.publicationDetailLine = publicationDetailLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.lastPublishedAt = lastPublishedAt

            self.activeOfferCount = max(0, activeOfferCount)
            self.visibleOfferCount = max(0, visibleOfferCount)

            self.openToItems = openToItems
            self.offerItems = offerItems
            self.interestItems = interestItems
            self.activityItems = activityItems
            self.regionItems = regionItems

            self.openToLine = openToLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.offerLine = offerLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.interestLine = interestLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.activityLine = activityLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.regionLine = regionLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    public struct OfferView: Sendable, Hashable, Identifiable {
        public var id: ExchangeOffer.ID { offer.id }

        public var offer: ExchangeOffer
        public var displayTitle: String
        public var subtitle: String?
        public var statusText: String
        public var visibilityText: String
        public var fulfillmentText: String
        public var priceText: String?
        public var regionText: String?
        public var tagLine: String?
        public var contactSummary: String?
        public var updatedAt: Date

        public init(
            offer: ExchangeOffer,
            displayTitle: String? = nil,
            subtitle: String? = nil,
            statusText: String,
            visibilityText: String,
            fulfillmentText: String,
            priceText: String? = nil,
            regionText: String? = nil,
            tagLine: String? = nil,
            contactSummary: String? = nil,
            updatedAt: Date? = nil
        ) {
            self.offer = offer
            self.displayTitle = (
                displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? offer.title
            )
            self.subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? offer.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.statusText = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.visibilityText = visibilityText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.fulfillmentText = fulfillmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.priceText = priceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.regionText = regionText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.tagLine = tagLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.contactSummary = contactSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.updatedAt = updatedAt ?? offer.updatedAt
        }
    }

    public struct SellerWorkspaceSummary: Sendable, Hashable {
        public var ownerDisplayName: String?
        public var publicProfile: PublicProfileView?
        public var offers: [OfferView]
        public var publicationState: ExchangePublicationState?
        public var activeOfferCount: Int
        public var draftOfferCount: Int
        public var pausedOfferCount: Int
        public var archivedOfferCount: Int
        public var needsPublicationAttention: Bool
        public var statusLine: String
        public var nextStepText: String?
        public var lastPublishedAt: Date?

        public var publicationBadgeText: String?
        public var publicationDetailLine: String?
        public var discoverabilityLine: String?
        public var primaryCTAHint: String?

        public init(
            ownerDisplayName: String? = nil,
            publicProfile: PublicProfileView? = nil,
            offers: [OfferView],
            publicationState: ExchangePublicationState? = nil,
            activeOfferCount: Int,
            draftOfferCount: Int,
            pausedOfferCount: Int,
            archivedOfferCount: Int,
            needsPublicationAttention: Bool,
            statusLine: String,
            nextStepText: String? = nil,
            lastPublishedAt: Date? = nil,
            publicationBadgeText: String? = nil,
            publicationDetailLine: String? = nil,
            discoverabilityLine: String? = nil,
            primaryCTAHint: String? = nil
        ) {
            self.ownerDisplayName = ownerDisplayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.publicProfile = publicProfile
            self.offers = offers.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayTitle < rhs.displayTitle
            }
            self.publicationState = publicationState
            self.activeOfferCount = max(0, activeOfferCount)
            self.draftOfferCount = max(0, draftOfferCount)
            self.pausedOfferCount = max(0, pausedOfferCount)
            self.archivedOfferCount = max(0, archivedOfferCount)
            self.needsPublicationAttention = needsPublicationAttention
            self.statusLine = statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
            self.nextStepText = nextStepText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.lastPublishedAt = lastPublishedAt

            self.publicationBadgeText = publicationBadgeText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.publicationDetailLine = publicationDetailLine?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.discoverabilityLine = discoverabilityLine?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.primaryCTAHint = primaryCTAHint?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Autonomous For You types

public extension ExchangeModels {

    /// Controls how far the autonomous secretary pass is allowed to go.
    /// Only `safeAutoSend` is permitted to queue an outbound message.
    enum SecretaryDiscoveryMode: String, Sendable, CaseIterable {
        case off
        case discoverOnly
        case draftOnly
        case safeAutoSend
    }

    /// Controls autonomous sending authority for second-half thread execution.
    /// This setting is distinct from For-You discovery mode.
    enum ExchangeThreadAutonomyMode: String, Sendable, CaseIterable {
        case manualOnly
        case draftOnly
        case routineAutoRespond
        case fullWithinBoundaries
    }

    /// A lightweight display record for one discovered candidate shown in the For You rail.
    struct ForYouItem: Identifiable, Sendable, Hashable {
        /// Stable identity: the candidate's counterparty/node ID.
        public var id: String
        public var displayName: String
        public var headline: String?
        public var matchReasonSummary: String?
        /// Raw value of `ExchangeDirectoryMatch.ReachabilityPreview.AccessMode`.
        public var accessMode: String
        public var dominantTags: [String]
        public var topOfferTitle: String?
        public var nodeID: String
        public var publicProfileID: String?
        public var acceptingInbound: Bool
        public var discoveredAt: Date
        /// True only when reachability allows direct contact and no introduction is required.
        public var canAutonomouslyContact: Bool
        /// Non-nil when `canAutonomouslyContact == false`; describes the blocker.
        public var blockedReason: String?
        /// Non-nil when an autonomous (or user-initiated) thread already exists for this
        /// candidate. Tapping the For You card should open this thread rather than starting
        /// a new one.
        public var linkedThreadID: ExchangeThread.ID?
        /// Optional HTTPS URL for the best available public image for this candidate.
        /// Selection is surface-aware: profile/social-led discovery prefers the public profile image first;
        /// offer/commercial-led discovery prefers the surfaced offer image first; unknown or mixed matches default
        /// profile-first (person-first). The other side is used when the preferred image is missing or blank.
        /// nil when neither source has a usable URL.
        public var primaryImageURL: String?
        /// All public image URLs from the surfaced offer (hero first, max five). Empty when none.
        public var surfacedOfferImageURLs: [String] = []
        /// Structured, outward-safe contact details from the surfaced offer (if published).
        public var publicOfferContactInfo: ExchangeOffer.ContactInfo?

        // MARK: - Discovery / agency testing (additive; defaults keep older items valid)

        /// Directory `matchedTerms` for “why this matched”.
        public var discoveryMatchedTerms: [String]
        /// Human-facing discovery context derived from profile, themes, and offers.
        public var discoveryFactLines: [String]
        /// Compact lines from the first offer's `commercialFacts` + fulfillment posture.
        public var publicFactLines: [String]
        /// From `commercialFacts.requiredBuyerInputs` on the first surfaced offer.
        public var suggestedBuyerInputHints: [String]
        /// Optional directory ranking score when present.
        public var retrievalFitScore: Double?
        /// Short provenance label (e.g. federation directory).
        public var discoverySourceLabel: String?
        /// Optional chips from ``ForYouResultMixer`` (e.g. "Nearby"); UI may ignore until wired.
        public var mixReasonChips: [String] = []
        /// Canonical separated provider display (Phase 1 For You). In-memory only; not persisted.
        public var displayCard: ExchangeProviderDisplayCard? = nil
        /// Public Guardian crown frame when published on the counterparty profile.
        public var publicSupporterPresentation: ExchangeSupporterPresentation? = nil
    }

    /// Legibility tier for the autonomous For You rail (after directory + mixer).
    enum ForYouDiscoveryQualityTier: String, Sendable, CaseIterable, Hashable {
        case strong
        case weak
        case sparse
        case empty
    }

    /// Lightweight quality snapshot for UI / summaries (no private text).
    struct ForYouDiscoveryQuality: Sendable, Hashable {
        public var tier: ForYouDiscoveryQualityTier
        public var title: String
        public var message: String
        public var suggestedAction: String?
        public var resultCount: Int
        public var rawDirectoryMatchCount: Int
        public var afterLocalFilterCount: Int
        public var weakReason: String?

        public init(
            tier: ForYouDiscoveryQualityTier,
            title: String,
            message: String,
            suggestedAction: String? = nil,
            resultCount: Int,
            rawDirectoryMatchCount: Int,
            afterLocalFilterCount: Int,
            weakReason: String? = nil
        ) {
            self.tier = tier
            self.title = title
            self.message = message
            self.suggestedAction = suggestedAction
            self.resultCount = max(0, resultCount)
            self.rawDirectoryMatchCount = max(0, rawDirectoryMatchCount)
            self.afterLocalFilterCount = max(0, afterLocalFilterCount)
            self.weakReason = weakReason
        }
    }

    /// Directory discovery outcome with mixed items and a quality snapshot.
    struct DiscoverForYouOutcome: Sendable {
        public var items: [ForYouItem]
        public var discoveryQuality: ForYouDiscoveryQuality

        public init(items: [ForYouItem], discoveryQuality: ForYouDiscoveryQuality) {
            self.items = items
            self.discoveryQuality = discoveryQuality
        }
    }

    /// Outcome returned by `ExchangeFacade.runAutonomousForYouPass`.
    struct AutonomousPassResult: Sendable {
        public enum SendOutcome: String, Sendable {
            /// Pass was `.off` or `.discoverOnly` — discovery only, no thread action.
            case noAction
            /// A draft/thread was created but send was skipped (`draftOnly` mode).
            case draftOnly
            /// Outbound message was queued successfully.
            case queued
            /// No candidate met the criteria in this pass.
            case noCandidates
            /// Cooldown is still active for all eligible candidates.
            case cooldownActive
            /// Second-half display was nil or boundary was not safe.
            case unsafeBoundary
            /// `evaluateSendEligibility` returned ineligible.
            case notEligible
            /// Created thread could not be tied to the candidate — left as draft.
            case candidateBindingFailed
            /// Thread autonomy (UserDefaults `secretary.threadAutonomy.mode`) does not allow autonomous outbound.
            case disabledByThreadAutonomy
        }

        public var forYouItems: [ForYouItem]
        /// The counterparty node ID that was contacted, if any.
        public var contactedCounterpartyID: String?
        public var contactedAt: Date?
        public var contactedThreadID: ExchangeThread.ID?
        public var sendOutcome: SendOutcome
        /// Present after a discovery pass when For You ran; `nil` when discovery mode is `.off` or pass skipped early.
        public var forYouDiscoveryQuality: ForYouDiscoveryQuality? = nil
    }
}
