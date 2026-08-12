import Foundation

/// Structured provider/requester operating facts used by the second half.
///
/// The goal of this model is to keep routine answering and qualification
/// grounded in durable structured data before freeform generation is used.
public struct ExchangeStructuredOperatingMemory: Codable, Hashable, Sendable {
    public struct PricingRule: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var label: String
        public var amountDescription: String
        public var notes: String?

        public init(
            id: UUID = UUID(),
            label: String,
            amountDescription: String,
            notes: String? = nil
        ) {
            self.id = id
            self.label = label
            self.amountDescription = amountDescription
            self.notes = notes
        }
    }

    public struct ServiceItem: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var details: String?
        public var isActive: Bool

        public init(
            id: UUID = UUID(),
            name: String,
            details: String? = nil,
            isActive: Bool = true
        ) {
            self.id = id
            self.name = name
            self.details = details
            self.isActive = isActive
        }
    }

    public struct CoverageArea: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var details: String?

        public init(
            id: UUID = UUID(),
            name: String,
            details: String? = nil
        ) {
            self.id = id
            self.name = name
            self.details = details
        }
    }

    public struct AvailabilityWindow: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var label: String
        public var details: String?

        public init(
            id: UUID = UUID(),
            label: String,
            details: String? = nil
        ) {
            self.id = id
            self.label = label
            self.details = details
        }
    }

    public struct CapacityRule: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var label: String
        public var details: String?

        public init(
            id: UUID = UUID(),
            label: String,
            details: String? = nil
        ) {
            self.id = id
            self.label = label
            self.details = details
        }
    }

    public struct LeadTimeRule: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var label: String
        public var turnaroundDescription: String

        public init(
            id: UUID = UUID(),
            label: String,
            turnaroundDescription: String
        ) {
            self.id = id
            self.label = label
            self.turnaroundDescription = turnaroundDescription
        }
    }

    public struct PolicyRule: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var details: String

        public init(
            id: UUID = UUID(),
            title: String,
            details: String
        ) {
            self.id = id
            self.title = title
            self.details = details
        }
    }

    public struct RequesterConstraint: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var key: String
        public var value: String

        public init(
            id: UUID = UUID(),
            key: String,
            value: String
        ) {
            self.id = id
            self.key = key
            self.value = value
        }
    }

    /// Provider-side structured memory.
    public var pricingRules: [PricingRule]
    public var serviceItems: [ServiceItem]
    public var coverageAreas: [CoverageArea]
    public var availabilityWindows: [AvailabilityWindow]
    public var capacityRules: [CapacityRule]
    public var leadTimes: [LeadTimeRule]
    public var standardPolicies: [PolicyRule]
    public var exclusions: [String]

    /// Requester-side structured constraints.
    public var requesterConstraints: [RequesterConstraint]

    public init(
        pricingRules: [PricingRule] = [],
        serviceItems: [ServiceItem] = [],
        coverageAreas: [CoverageArea] = [],
        availabilityWindows: [AvailabilityWindow] = [],
        capacityRules: [CapacityRule] = [],
        leadTimes: [LeadTimeRule] = [],
        standardPolicies: [PolicyRule] = [],
        exclusions: [String] = [],
        requesterConstraints: [RequesterConstraint] = []
    ) {
        self.pricingRules = pricingRules
        self.serviceItems = serviceItems
        self.coverageAreas = coverageAreas
        self.availabilityWindows = availabilityWindows
        self.capacityRules = capacityRules
        self.leadTimes = leadTimes
        self.standardPolicies = standardPolicies
        self.exclusions = exclusions
        self.requesterConstraints = requesterConstraints
    }
}

public extension ExchangeStructuredOperatingMemory {
    static let empty = ExchangeStructuredOperatingMemory()

    var hasProviderFacts: Bool {
        !pricingRules.isEmpty ||
        !serviceItems.isEmpty ||
        !coverageAreas.isEmpty ||
        !availabilityWindows.isEmpty ||
        !capacityRules.isEmpty ||
        !leadTimes.isEmpty ||
        !standardPolicies.isEmpty ||
        !exclusions.isEmpty
    }

    var hasRequesterConstraints: Bool {
        !requesterConstraints.isEmpty
    }
}
