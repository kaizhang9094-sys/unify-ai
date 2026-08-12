import Foundation

/// Compact `profileSummary` for `providerInquiryCompare`, aligned with `ProviderAllowedFactSurfaces`.
public enum ProviderInquiryCompareProfileSummaryGate: Sendable {

    /// Returns nil when public profile facts are excluded by surface gating.
    public static func compactProfileSummary(
        profile: ExchangePublicNodeProfile?,
        allowedSurfaces: ProviderAllowedFactSurfaces?,
        applyFactSurfaceGating: Bool,
        includeContactReachability: Bool = true
    ) -> String? {
        guard let profile else { return nil }
        let gate = applyFactSurfaceGating ? allowedSurfaces : nil
        if gate?.includePublicProfile == false {
            return nil
        }
        let includeContact = gate?.includeContactReachability ?? includeContactReachability

        var parts: [String] = []
        let n = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty { parts.append(n) }
        if let h = profile.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            parts.append(h)
        }
        if includeContact {
            parts.append("availability: \(profile.availability.rawValue)")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// Defensive check: profile channel must not leak when `PROFILE_FACTS` is excluded.
    public static func logProfileSummarySurfaceAlignment(
        profileSummary: String?,
        sellerControlledFacts: String,
        allowedSurfaces: ProviderAllowedFactSurfaces?,
        applyFactSurfaceGating: Bool,
        threadID: UUID? = nil,
        context: String
    ) {
        guard applyFactSurfaceGating, allowedSurfaces?.includePublicProfile == false else { return }
        let facts = sellerControlledFacts.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProfileSection = facts.contains("=== PROFILE_FACTS ===")
        let summaryPresent = !(profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard summaryPresent || hasProfileSection else { return }

        let tid = threadID.map { $0.uuidString } ?? "nil"
        let parts: [String] = [
            "[ProviderProfileSummaryGate]",
            "context=\(context)",
            "thread=\(tid)",
            "violation=profile_channel_leak_when_public_profile_excluded",
            "profileSummaryPresent=\(summaryPresent)",
            "sellerControlledHasProfileSection=\(hasProfileSection)",
            "gatingReason=\(allowedSurfaces?.reason ?? "nil")"
        ]
        Swift.print(parts.joined(separator: " "))
    }
}
