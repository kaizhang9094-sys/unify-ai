import Foundation

/// Builds a usable operating memory packet for the current thread role.
///
/// This lets the second half work from a compact role-aware fact packet
/// rather than manually mixing node-level and thread-level memory in the
/// coordinator every time.
public struct ExchangeOperatingMemoryAssembler: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var threadScoped: ExchangeStructuredOperatingMemory?
        public var nodeScoped: ExchangeStructuredOperatingMemory?
        public var fallback: ExchangeStructuredOperatingMemory?

        public init(
            role: ExchangeSecondHalfRole,
            threadScoped: ExchangeStructuredOperatingMemory? = nil,
            nodeScoped: ExchangeStructuredOperatingMemory? = nil,
            fallback: ExchangeStructuredOperatingMemory? = nil
        ) {
            self.role = role
            self.threadScoped = threadScoped
            self.nodeScoped = nodeScoped
            self.fallback = fallback
        }
    }

    public func assemble(
        input: Input
    ) -> ExchangeStructuredOperatingMemory {
        let base = input.nodeScoped ?? input.fallback ?? .empty
        let overlay = input.threadScoped

        guard let overlay else {
            return normalized(base, role: input.role)
        }

        let merged = ExchangeStructuredOperatingMemory(
            pricingRules: overlay.pricingRules.isEmpty ? base.pricingRules : overlay.pricingRules,
            serviceItems: overlay.serviceItems.isEmpty ? base.serviceItems : overlay.serviceItems,
            coverageAreas: overlay.coverageAreas.isEmpty ? base.coverageAreas : overlay.coverageAreas,
            availabilityWindows: overlay.availabilityWindows.isEmpty ? base.availabilityWindows : overlay.availabilityWindows,
            capacityRules: overlay.capacityRules.isEmpty ? base.capacityRules : overlay.capacityRules,
            leadTimes: overlay.leadTimes.isEmpty ? base.leadTimes : overlay.leadTimes,
            standardPolicies: overlay.standardPolicies.isEmpty ? base.standardPolicies : overlay.standardPolicies,
            exclusions: overlay.exclusions.isEmpty ? base.exclusions : overlay.exclusions,
            requesterConstraints: overlay.requesterConstraints.isEmpty ? base.requesterConstraints : overlay.requesterConstraints
        )

        return normalized(merged, role: input.role)
    }

    private func normalized(
        _ memory: ExchangeStructuredOperatingMemory,
        role: ExchangeSecondHalfRole
    ) -> ExchangeStructuredOperatingMemory {
        switch role {
        case .provider:
            // Provider role should keep all provider-side facts and any requester constraints
            // that have been attached to this specific thread.
            return memory

        case .requester:
            // Requester role still benefits from provider-side facts when reviewing a surfaced
            // opportunity, so we keep the full packet rather than stripping it.
            return memory
        }
    }
}
