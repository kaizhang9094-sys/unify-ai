import Foundation

/// The user's stance within a coordination request.
///
/// Posture is not the same as intent.
///
/// - Intent answers: "What is the user trying to do?"
/// - Posture answers: "How should the secretary carry the user into the exchange?"
///
/// Keep this as a compact, portable snapshot that can travel with a thread.
/// It should shape discovery, drafting tone, and disclosure posture, but it
/// should not become a hidden policy engine.
public struct ExchangePosture: Codable, Sendable, Hashable {
    public var urgency: Urgency
    public var warmth: Warmth
    public var directness: Directness
    public var openness: Openness
    public var commitment: Commitment
    public var privacy: Privacy
    public var priceSensitivity: PriceSensitivity
    public var flexibility: Flexibility

    /// Freeform nuance that does not fit neatly into the structured posture axes.
    ///
    /// Example:
    /// "User prefers concise outreach and does not want to sound desperate."
    public var notes: String?

    public init(
        urgency: Urgency = .normal,
        warmth: Warmth = .neutral,
        directness: Directness = .balanced,
        openness: Openness = .selective,
        commitment: Commitment = .exploring,
        privacy: Privacy = .guarded,
        priceSensitivity: PriceSensitivity = .notSpecified,
        flexibility: Flexibility = .moderate,
        notes: String? = nil
    ) {
        self.urgency = urgency
        self.warmth = warmth
        self.directness = directness
        self.openness = openness
        self.commitment = commitment
        self.privacy = privacy
        self.priceSensitivity = priceSensitivity
        self.flexibility = flexibility
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public extension ExchangePosture {
    enum Urgency: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case normal
        case high
        case immediate
    }

    enum Warmth: String, Codable, Sendable, CaseIterable, Hashable {
        case reserved
        case neutral
        case warm
    }

    enum Directness: String, Codable, Sendable, CaseIterable, Hashable {
        case soft
        case balanced
        case firm
    }

    enum Openness: String, Codable, Sendable, CaseIterable, Hashable {
        /// Only narrow, high-fit options should be surfaced.
        case selective

        /// User is open to a healthy range of possibilities.
        case open

        /// User wants broad exploration.
        case exploratory
    }

    enum Commitment: String, Codable, Sendable, CaseIterable, Hashable {
        /// User is exploring and does not want the system to overstate intent.
        case exploring

        /// User is serious and ready to move if the fit is good.
        case serious

        /// User is ready for active commitment if alignment appears.
        case committed
    }

    enum Privacy: String, Codable, Sendable, CaseIterable, Hashable {
        /// Minimize unnecessary disclosure.
        case guarded

        /// Balanced disclosure as needed to progress coordination.
        case balanced

        /// More generous disclosure is acceptable when useful.
        case disclosive
    }

    enum PriceSensitivity: String, Codable, Sendable, CaseIterable, Hashable {
        case notSpecified
        case low
        case moderate
        case high
    }

    enum Flexibility: String, Codable, Sendable, CaseIterable, Hashable {
        case rigid
        case moderate
        case flexible
    }
}

public extension ExchangePosture {
    static let `default` = ExchangePosture()

    /// Conservative posture appropriate when the system has only weak signals.
    static let cautious = ExchangePosture(
        urgency: .normal,
        warmth: .neutral,
        directness: .balanced,
        openness: .selective,
        commitment: .exploring,
        privacy: .guarded,
        priceSensitivity: .notSpecified,
        flexibility: .moderate,
        notes: "Defaulted conservatively due to limited signal."
    )

    /// Whether the secretary should bias toward tighter matching and lower-volume
    /// outreach because the user's stance suggests selectivity or caution.
    var prefersDisciplinedFiltering: Bool {
        openness == .selective ||
        privacy == .guarded ||
        commitment == .serious ||
        commitment == .committed
    }

    /// Whether the secretary should favor more direct, less padded communication.
    var prefersDirectCommunication: Bool {
        switch directness {
        case .soft:
            return false
        case .balanced, .firm:
            return true
        }
    }

    /// Compact summary for thread headers, traces, and debugging.
    var summaryLine: String {
        [
            "urgency=\(urgency.rawValue)",
            "warmth=\(warmth.rawValue)",
            "directness=\(directness.rawValue)",
            "openness=\(openness.rawValue)",
            "commitment=\(commitment.rawValue)",
            "privacy=\(privacy.rawValue)",
            "priceSensitivity=\(priceSensitivity.rawValue)",
            "flexibility=\(flexibility.rawValue)"
        ].joined(separator: ", ")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
