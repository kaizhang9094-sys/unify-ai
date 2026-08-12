import Foundation

/// Deterministic allowed optional enrichment for requester autonomous compose (not compare gaps).
public enum RequesterOutboundEnrichmentPolicy: Sendable {

    public struct Input: Sendable, Hashable {
        public var pass2LLMCompareSucceeded: Bool
        public var providerDirectedQuestionLines: [String]
        public var routingSurface: String?
        public var queryIntentClass: ExchangeIntent.QueryIntentClass?
        public var surfacePreference: ExchangeIntent.SurfacePreference?
        public var domainCategory: ExchangeIntentFacets.DomainCategory?
        public var requesterRequirementsSummary: String?
        public var originalUserRequest: String

        public init(
            pass2LLMCompareSucceeded: Bool,
            providerDirectedQuestionLines: [String],
            routingSurface: String? = nil,
            queryIntentClass: ExchangeIntent.QueryIntentClass? = nil,
            surfacePreference: ExchangeIntent.SurfacePreference? = nil,
            domainCategory: ExchangeIntentFacets.DomainCategory? = nil,
            requesterRequirementsSummary: String? = nil,
            originalUserRequest: String = ""
        ) {
            self.pass2LLMCompareSucceeded = pass2LLMCompareSucceeded
            self.providerDirectedQuestionLines = providerDirectedQuestionLines
            self.routingSurface = routingSurface
            self.queryIntentClass = queryIntentClass
            self.surfacePreference = surfacePreference
            self.domainCategory = domainCategory
            self.requesterRequirementsSummary = requesterRequirementsSummary
            self.originalUserRequest = originalUserRequest
        }
    }

    public struct Outcome: Sendable, Hashable {
        public var allowedEnrichmentDimensions: [RequesterOutboundEnrichmentDimension]
        public var allowedEnrichmentHints: [String]

        public init(
            allowedEnrichmentDimensions: [RequesterOutboundEnrichmentDimension] = [],
            allowedEnrichmentHints: [String] = []
        ) {
            self.allowedEnrichmentDimensions = allowedEnrichmentDimensions
            self.allowedEnrichmentHints = allowedEnrichmentHints
        }
    }

    public static func resolve(_ input: Input) -> Outcome {
        let directed = input.providerDirectedQuestionLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard input.pass2LLMCompareSucceeded else {
            return Outcome()
        }

        guard !directed.isEmpty else {
            return Outcome()
        }

        let routing = normalizedRoutingSurface(
            explicit: input.routingSurface,
            queryIntentClass: input.queryIntentClass,
            surfacePreference: input.surfacePreference
        )
        let domain = input.domainCategory ?? .general
        let blob = intentBlob(
            summary: input.requesterRequirementsSummary,
            originalUserRequest: input.originalUserRequest
        )
        let budgetRequired = blobContains(blob, "budgetorpricerequired: true")
            || requesterMentionsBudget(blob)
        let credentialRequired = blobContains(blob, "credentialorlicenserequired: true")
            || requesterMentionsCredential(blob)

        if isSocialOrRelationshipSurface(routing) {
            return Outcome()
        }

        var dimensions: [RequesterOutboundEnrichmentDimension] = []

        if isProviderOfferSurface(routing) {
            switch domain {
            case .homeService, .professionalService:
                dimensions.append(.pricingProcess)
                dimensions.append(.estimateRange)
                if budgetRequired {
                    dimensions.append(.budgetAlignment)
                }
            case .product:
                dimensions.append(.commercialTerms)
                dimensions.append(.shippingOrDelivery)
                dimensions.append(.productCondition)
            case .realEstate:
                dimensions.append(.commercialTerms)
            case .general:
                dimensions.append(.pricingProcess)
                dimensions.append(.estimateRange)
            }
        }

        if isCollaborationSurface(routing), hasCollaborationSignals(blob, input: input) {
            dimensions.append(.collaborationMode)
        }

        if credentialRequired {
            // Prefer compare-required credential asks; do not add as optional enrichment.
        }

        let unique = dedupeDimensions(dimensions)
        let hints = unique.map { hint(for: $0) }.filter { !$0.isEmpty }
        return Outcome(allowedEnrichmentDimensions: unique, allowedEnrichmentHints: hints)
    }

    public static func hint(for dimension: RequesterOutboundEnrichmentDimension) -> String {
        switch dimension {
        case .pricingProcess:
            return "how estimates or pricing usually work"
        case .estimateRange:
            return "whether they can share how estimates are handled"
        case .budgetAlignment:
            return "whether the budget range can work"
        case .commercialTerms:
            return "what commercial terms would apply"
        case .shippingOrDelivery:
            return "how shipping or delivery would work"
        case .productCondition:
            return "what condition details are available"
        case .collaborationMode:
            return "how collaboration would usually work"
        case .basicLogistics:
            return "basic logistics or next steps to proceed"
        }
    }

    // MARK: - Routing / surface

    private static func normalizedRoutingSurface(
        explicit: String?,
        queryIntentClass: ExchangeIntent.QueryIntentClass?,
        surfacePreference: ExchangeIntent.SurfacePreference?
    ) -> String {
        let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !trimmed.isEmpty { return trimmed }

        if let queryIntentClass {
            switch queryIntentClass {
            case .offerSearch, .providerSearch, .directOutreach, .followUp, .statusCheck:
                return "provider/offer"
            case .capabilitySearch, .collaborationSearch:
                return "capability/collaboration"
            case .socialAffinitySearch:
                return "social/affinity"
            case .relationshipSearch:
                return "relationship"
            case .generalDiscovery:
                break
            }
        }

        if let surfacePreference {
            switch surfacePreference {
            case .offer:
                return "provider/offer"
            case .capability:
                return "capability/collaboration"
            case .affinity:
                return "social/affinity"
            case .mixed:
                return "mixed"
            }
        }

        return "provider/offer"
    }

    private static func isProviderOfferSurface(_ routing: String) -> Bool {
        routing.contains("provider/offer") || routing == "mixed"
    }

    private static func isCollaborationSurface(_ routing: String) -> Bool {
        routing.contains("capability/collaboration") || routing.contains("collaboration")
    }

    private static func isSocialOrRelationshipSurface(_ routing: String) -> Bool {
        routing.contains("social/affinity") || routing.contains("relationship")
    }

    private static func hasCollaborationSignals(_ blob: String, input: Input) -> Bool {
        if input.queryIntentClass == .collaborationSearch || input.queryIntentClass == .capabilitySearch {
            return true
        }
        let needles = ["collaboration", "collaborate", "partner", "co-develop", "joint project", "work together"]
        return needles.contains { blob.contains($0) }
    }

    // MARK: - Grounding blob

    private static func intentBlob(summary: String?, originalUserRequest: String) -> String {
        [summary ?? "", originalUserRequest]
            .joined(separator: "\n")
            .lowercased()
    }

    private static func blobContains(_ blob: String, _ needle: String) -> Bool {
        blob.contains(needle.lowercased())
    }

    private static func requesterMentionsBudget(_ blob: String) -> Bool {
        let needles = ["budget", "under $", "under ", " dollars", "price", "pricing", "cost", "$"]
        return needles.contains { blob.contains($0) }
    }

    private static func requesterMentionsCredential(_ blob: String) -> Bool {
        let needles = ["licensed", "license", "certified", "insured", "credential"]
        return needles.contains { blob.contains($0) }
    }

    private static func dedupeDimensions(
        _ values: [RequesterOutboundEnrichmentDimension]
    ) -> [RequesterOutboundEnrichmentDimension] {
        var seen = Set<String>()
        var out: [RequesterOutboundEnrichmentDimension] = []
        for value in values {
            let key = value.rawValue
            guard seen.insert(key).inserted else { continue }
            out.append(value)
        }
        return out
    }
}
