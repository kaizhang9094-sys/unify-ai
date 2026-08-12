import Foundation

/// Structured meaning extracted from the user's natural-language request.
///
/// Canonical ownership:
/// - ExchangeIntent owns interpreted meaning
/// - ExchangeIntent owns routing enums used by retrieval/discovery
/// - downstream layers consume these enums instead of redefining them
///
/// It should describe:
/// - what the user wants
/// - what kind of coordination/search this is
/// - how retrieval should be routed
/// - whether current interpretation is strong enough to act
///
/// It should NOT describe:
/// - UI state
/// - storage state
/// - transport state
public struct ExchangeIntent: Codable, Sendable, Hashable {
    /// The primary coordination shape inferred for the request.
    public var kind: Kind

    /// The broader social / coordination family the request belongs to.
    public var mode: ExchangeMode

    /// Canonical fast routing class used by retrieval and discovery.
    public var queryIntentClass: QueryIntentClass

    /// Canonical preferred surface weighting for retrieval.
    public var surfacePreference: SurfacePreference

    /// Short human-readable title for logs, thread headers, and summaries.
    public var title: String

    /// Canonical statement of what the user wants the secretary to help accomplish.
    public var objective: String

    /// Optional target description when the user has described who or what
    /// they want to coordinate with.
    public var targetDescription: String?

    /// Constraints explicitly stated or confidently inferred from the request.
    public var constraints: [Constraint]

    /// Structured milestones or outputs the user is trying to reach.
    public var desiredOutcomes: [DesiredOutcome]

    /// Whether the system can move forward confidently, or whether the request
    /// still needs clarification before trustworthy action.
    public var readiness: Readiness

    /// Compact natural-language explanation of what the interpreter believes
    /// the user is asking for.
    public var interpretationNotes: String?

    /// Confidence in the interpreted routing/result.
    /// This is interpretation confidence, not match confidence.
    public var interpretationConfidence: Double

    /// Whether the current interpretation path believes a fuller interpretation
    /// pass is still needed before discovery/drafting should proceed.
    public var needsFullLLMInterpretation: Bool

    public init(
        kind: Kind,
        mode: ExchangeMode,
        queryIntentClass: QueryIntentClass = .generalDiscovery,
        surfacePreference: SurfacePreference = .mixed,
        title: String,
        objective: String,
        targetDescription: String? = nil,
        constraints: [Constraint] = [],
        desiredOutcomes: [DesiredOutcome] = [],
        readiness: Readiness = .ready,
        interpretationNotes: String? = nil,
        interpretationConfidence: Double = 0.0,
        needsFullLLMInterpretation: Bool = false
    ) {
        self.kind = kind
        self.mode = mode
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.title = title.exNormalizedNonEmpty ?? "Exchange Request"
        self.objective = objective.exNormalizedNonEmpty ?? "Interpret and coordinate the request."
        self.targetDescription = targetDescription?.exNormalizedNonEmpty
        self.constraints = Self.sanitizeConstraints(constraints)
        self.desiredOutcomes = Array(desiredOutcomes.prefix(8))
        self.readiness = readiness
        self.interpretationNotes = interpretationNotes?.exNormalizedNonEmpty?.exCapped(300)
        self.interpretationConfidence = Self.clampConfidence(interpretationConfidence)
        self.needsFullLLMInterpretation = needsFullLLMInterpretation
    }
}

public extension ExchangeIntent {
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case find
        case source
        case introduce
        case message
        case requestQuote
        case negotiate
        case arrangeCall
        case arrangeMeeting
        case plan
        case followUp
        case checkStatus
        case invite
        case coordinate
        case other
    }

    enum Readiness: String, Codable, Sendable, CaseIterable, Hashable {
        case ready
        case needsClarification
        case underSpecified
    }

    /// Canonical routing class for interpretation, retrieval, discovery, and fit.
    enum QueryIntentClass: String, Codable, Sendable, CaseIterable, Hashable {
        case providerSearch
        case offerSearch
        case capabilitySearch
        case collaborationSearch
        case socialAffinitySearch
        case relationshipSearch
        case directOutreach
        case followUp
        case statusCheck
        case generalDiscovery
    }

    /// Canonical preferred surface weighting for retrieval.
    ///
    /// Keep this intentionally small:
    /// - offer
    /// - capability
    /// - affinity
    /// - mixed
    ///
    /// Do not reintroduce over-modeled variants.
    enum SurfacePreference: String, Codable, Sendable, CaseIterable, Hashable {
        case offer
        case capability
        case affinity
        case mixed
    }

    struct Constraint: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var key: String
        public var value: String
        public var isHardConstraint: Bool

        public init(
            id: UUID = UUID(),
            key: String,
            value: String,
            isHardConstraint: Bool = true
        ) {
            self.id = id
            self.key = key.exNormalizedNonEmpty ?? ""
            self.value = value.exNormalizedNonEmpty ?? ""
            self.isHardConstraint = isHardConstraint
        }
    }

    enum DesiredOutcome: String, Codable, Sendable, CaseIterable, Hashable {
        case shortlist
        case intro
        case response
        case quote
        case proposal
        case meeting
        case booked
        case aligned
        case resolved
    }
}

public extension ExchangeIntent {
    var requiresClarificationBeforeAction: Bool {
        if title.isEmpty || objective.isEmpty {
            return true
        }

        switch readiness {
        case .ready:
            return false
        case .needsClarification, .underSpecified:
            return true
        }
    }

    var summaryLine: String {
        if let targetDescription, !targetDescription.isEmpty {
            return "\(kind.displayTitle): \(targetDescription)"
        }
        return "\(kind.displayTitle): \(title)"
    }

    var prefersOfferSurfaces: Bool {
        surfacePreference == .offer
    }

    var prefersCapabilitySurfaces: Bool {
        surfacePreference == .capability
    }

    var prefersAffinitySurfaces: Bool {
        surfacePreference == .affinity
    }

    var isMixedSurfaceSearch: Bool {
        surfacePreference == .mixed
    }
}

public extension ExchangeIntent.Kind {
    var displayTitle: String {
        switch self {
        case .find: return "Find"
        case .source: return "Source"
        case .introduce: return "Introduce"
        case .message: return "Message"
        case .requestQuote: return "Request Quote"
        case .negotiate: return "Negotiate"
        case .arrangeCall: return "Arrange Call"
        case .arrangeMeeting: return "Arrange Meeting"
        case .plan: return "Plan"
        case .followUp: return "Follow Up"
        case .checkStatus: return "Check Status"
        case .invite: return "Invite"
        case .coordinate: return "Coordinate"
        case .other: return "Other"
        }
    }
}

private extension ExchangeIntent {
    static func clampConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    static func sanitizeConstraints(_ values: [Constraint]) -> [Constraint] {
        var seen = Set<String>()
        var output: [Constraint] = []

        for item in values {
            let key = item.key.exNormalizedNonEmpty?.lowercased() ?? ""
            let value = item.value.exNormalizedNonEmpty?.lowercased() ?? ""
            guard !key.isEmpty, !value.isEmpty else { continue }

            let dedupeKey = "\(key)|||\(value)|||\(item.isHardConstraint)"
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)

            output.append(
                Constraint(
                    id: item.id,
                    key: String((item.key.exNormalizedNonEmpty ?? "").prefix(80)),
                    value: String((item.value.exNormalizedNonEmpty ?? "").prefix(200)),
                    isHardConstraint: item.isHardConstraint
                )
            )

            if output.count >= 24 {
                break
            }
        }

        return output
    }
}

// MARK: - Opportunity / discovery card surface anchor

/// Which durable surface should drive human-facing “current opportunity” copy.
public enum ExchangeOpportunitySurfaceAnchor: String, Sendable, Hashable {
    case offerSurface
    case profileSurface
    case counterpartyNode
}

// MARK: - Opportunity missing-facts (surface-aware)

public extension ExchangeOpportunitySurfaceAnchor {
    /// Removes deterministic / agency missing-fact lines that conflict with the resolved opportunity surface,
    /// or that are redundant once a hydrated offer/profile row is present on the snapshot.
    func filterOpportunityMissingFactLines(
        _ lines: [String],
        hasHydratedOffer: Bool,
        hasHydratedProfile: Bool
    ) -> [String] {
        lines.filter {
            !Self.shouldSuppressOpportunityMissingFactLine(
                $0,
                anchor: self,
                hasHydratedOffer: hasHydratedOffer,
                hasHydratedProfile: hasHydratedProfile
            )
        }
    }

    private static func shouldSuppressOpportunityMissingFactLine(
        _ line: String,
        anchor: ExchangeOpportunitySurfaceAnchor,
        hasHydratedOffer: Bool,
        hasHydratedProfile: Bool
    ) -> Bool {
        let lower = line.lowercased()

        if hasHydratedOffer {
            if lower.contains("no selected offer id") { return true }
            if lower.contains("surfaced offer") { return true }
            if lower.contains("offer row") { return true }
            if lower.contains("commercial economics are not anchored") { return true }
            if lower.contains("numeric tariff") { return true }
            if lower.contains("invoiced amount") { return true }
            if lower.contains("published seller surfaces are not anchored") { return true }
        }

        if hasHydratedProfile {
            if lower.contains("no selected public profile id") { return true }
            if lower.contains("public profile row") { return true }
            if lower.contains("no public profile row") { return true }
            if lower.contains("no explicit public profile") { return true }
            if lower.contains("published seller surfaces are not anchored") { return true }
        }

        switch anchor {
        case .offerSurface:
            if lower.contains("public profile")
                && (lower.contains("no ") || lower.contains("not ") || lower.contains("null")) {
                return true
            }

        case .profileSurface:
            if lower.contains("surfaced offer")
                || lower.contains("offer row")
                || lower.contains("commercial economics")
                || lower.contains("numeric tariff")
                || lower.contains("invoiced amount")
                || lower.contains("quoting workbook")
                || lower.contains("negotiation/discount knobs")
                || lower.contains("freight / shipping channel")
                || lower.contains("throughput / concurrency")
                || lower.contains("hardened production / delivery timeline")
                || lower.contains("capacity / throughput specifics")
                || lower.contains("shipping/delivery modality") {
                return true
            }

        case .counterpartyNode:
            if lower.contains("no selected offer id") || lower.contains("no selected public profile id") {
                return true
            }
            if lower.contains("commercial economics are not anchored") {
                return true
            }
        }

        return false
    }
}

public extension ExchangeIntent {
    /// Resolves whether offer, public profile, or coarse counterparty identity should
    /// anchor dashboard / compare / inbox opportunity lines for a thread.
    func resolvedOpportunitySurfaceAnchor(
        selectedOfferID: String?,
        selectedPublicProfileID: String?,
        selectedCounterpartyID: String?
    ) -> ExchangeOpportunitySurfaceAnchor {
        let offer = Self.nonBlank(selectedOfferID)
        let profile = Self.nonBlank(selectedPublicProfileID)
        let _ = Self.nonBlank(selectedCounterpartyID)

        switch surfacePreference {
        case .offer:
            return .offerSurface
        case .affinity:
            return .profileSurface
        case .capability:
            if offer != nil { return .offerSurface }
            if profile != nil { return .profileSurface }
            return .counterpartyNode
        case .mixed:
            switch queryIntentClass {
            case .socialAffinitySearch, .relationshipSearch:
                if profile != nil { return .profileSurface }
                if offer != nil { return .offerSurface }
                return .counterpartyNode
            case .providerSearch, .offerSearch, .capabilitySearch:
                if offer != nil { return .offerSurface }
                if profile != nil { return .profileSurface }
                return .counterpartyNode
            default:
                if offer != nil, profile == nil { return .offerSurface }
                if profile != nil, offer == nil { return .profileSurface }
                if offer != nil { return .offerSurface }
                if profile != nil { return .profileSurface }
                return .counterpartyNode
            }
        }
    }

    private static func nonBlank(_ raw: String?) -> String? {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Label for provider-inquiry-compare prompts. Reuses `resolvedOpportunitySurfaceAnchor` and adds
    /// `mixed` / `unknown` for explicit routing instructions without a new enum.
    ///
    /// - `unknown`: neither hydrated offer nor profile row available for grounding.
    /// - `mixed`: seller weighted mixed surfaces and both offer + profile rows are hydrated.
    /// - Otherwise: `resolvedAnchor.rawValue` (`offerSurface`, `profileSurface`, `counterpartyNode`).
    func primaryOpportunitySurfacePromptLabel(
        resolvedAnchor: ExchangeOpportunitySurfaceAnchor,
        hasHydratedOffer: Bool,
        hasHydratedProfile: Bool
    ) -> String {
        if !hasHydratedOffer && !hasHydratedProfile {
            return "unknown"
        }
        if surfacePreference == .mixed && hasHydratedOffer && hasHydratedProfile {
            return "mixed"
        }
        return resolvedAnchor.rawValue
    }
}

private extension String {
    var exNormalizedNonEmpty: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned
    }

    func exCapped(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
