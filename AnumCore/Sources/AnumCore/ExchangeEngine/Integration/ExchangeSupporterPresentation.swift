import Foundation

/// Public cosmetic supporter signal for avatar presentation only.
/// Must never feed retrieval, ranking, trust, reachability, or routing.
public struct ExchangeSupporterPresentation: Codable, Equatable, Sendable, Hashable {
    public var kind: Kind
    public var cosmeticFrame: CosmeticFrame
    public var displayLabel: String?
    public var since: Date?

    public enum Kind: String, Codable, Sendable, Hashable {
        case guardian
    }

    public enum CosmeticFrame: String, Codable, Sendable, Hashable {
        case crown
    }

    public init(
        kind: Kind,
        cosmeticFrame: CosmeticFrame,
        displayLabel: String? = nil,
        since: Date? = nil
    ) {
        self.kind = kind
        self.cosmeticFrame = cosmeticFrame
        let trimmedLabel = displayLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
        self.since = since
    }

    public var showsGuardianCrown: Bool {
        kind == .guardian && cosmeticFrame == .crown
    }

    public static func guardianCrown(
        displayLabel: String? = "Guardian",
        since: Date? = nil
    ) -> ExchangeSupporterPresentation {
        ExchangeSupporterPresentation(
            kind: .guardian,
            cosmeticFrame: .crown,
            displayLabel: displayLabel,
            since: since
        )
    }

    public static func guardianCrownIfActive(
        _ isActive: Bool,
        displayLabel: String? = "Guardian",
        since: Date? = nil
    ) -> ExchangeSupporterPresentation? {
        isActive ? guardianCrown(displayLabel: displayLabel, since: since) : nil
    }
}

#if DEBUG
/// Grep-able Guardian Crown diagnostics (`[GuardianCrown][Tag] ...`). Presentation/routing only.
public enum GuardianCrownDebugLog {
    public static func presentationLabel(_ presentation: ExchangeSupporterPresentation?) -> String {
        guard let presentation, presentation.showsGuardianCrown else { return "nil" }
        return "guardian/crown"
    }

    public static func log(_ tag: String, _ message: String) {
        print("[GuardianCrown][\(tag)] \(message)")
    }
}
#endif
