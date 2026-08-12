import Foundation

public struct DirectReplyContactBrief: Codable, Sendable, Equatable {
    public enum Stakes: String, Codable, Sendable, Hashable {
        case low
        case medium
        case high
    }

    public var relationship: String
    public var goal: String
    public var tone: String
    public var stakes: Stakes
    public var styleConstraints: [String]
    public var boundaries: [String]
    public var avoid: [String]
    public var alwaysDo: [String]
    public var neverDo: [String]
    public var sourceVersion: Int

    public init(
        relationship: String,
        goal: String,
        tone: String,
        stakes: Stakes = .medium,
        styleConstraints: [String],
        boundaries: [String],
        avoid: [String],
        alwaysDo: [String] = [],
        neverDo: [String] = [],
        sourceVersion: Int = 1
    ) {
        self.relationship = relationship
        self.goal = goal
        self.tone = tone
        self.stakes = stakes
        self.styleConstraints = styleConstraints
        self.boundaries = boundaries
        self.avoid = avoid
        self.alwaysDo = alwaysDo
        self.neverDo = neverDo
        self.sourceVersion = sourceVersion
    }
}

public enum DirectReplyContactBriefCompiler {
    public static let notesMaxChars = 160
    public static let toneOverrideMaxChars = 120
    public static let goalNotesMaxChars = 120

    public static func compile(
        contactContext: ExchangeModels.ContactContext?
    ) -> DirectReplyContactBrief? {
        guard let contactContext else { return nil }

        let relationship = effectiveRelationshipLabel(for: contactContext)
        let goal = effectiveGoalLabel(for: contactContext)
        var tone = baseTone(for: contactContext.relationshipType)
        var styleConstraints = styleConstraintsFor(goal: contactContext.relationshipGoal)
        var boundaries: [String] = []
        var avoid = avoidPhrases(for: contactContext.relationshipType)

        if let toneOverride = clipped(contactContext.toneOverride, maxChars: toneOverrideMaxChars) {
            tone = toneOverride
            boundaries.append("Honor saved tone preference.")
        }

        if let notes = clipped(contactContext.notes, maxChars: notesMaxChars), !notes.isEmpty {
            boundaries.append("Contact notes: \(notes)")
        }

        if let goalNotes = clipped(contactContext.goalNotes, maxChars: goalNotesMaxChars), !goalNotes.isEmpty {
            boundaries.append("Goal notes: \(goalNotes)")
        }

        let stakes = stakesFor(contactContext)
        let alwaysDo = alwaysDoFor(contactContext)
        var neverDo = neverDoFor(contactContext)
        neverDo.append(contentsOf: avoid)
        neverDo = Array(Set(neverDo.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty })
        neverDo = Array(neverDo.prefix(4))

        styleConstraints = Array(styleConstraints.prefix(3))
        boundaries = Array(boundaries.prefix(3))
        avoid = Array(avoid.prefix(3))
        let clippedAlwaysDo = Array(alwaysDo.prefix(3))

        return DirectReplyContactBrief(
            relationship: relationship,
            goal: goal,
            tone: tone,
            stakes: stakes,
            styleConstraints: styleConstraints,
            boundaries: boundaries,
            avoid: avoid,
            alwaysDo: clippedAlwaysDo,
            neverDo: neverDo,
            sourceVersion: 1
        )
    }

    static func stakesFor(_ context: ExchangeModels.ContactContext) -> DirectReplyContactBrief.Stakes {
        switch context.relationshipType {
        case .friend, .family:
            return .low
        case .client, .lead, .investor, .broker, .supplier, .contractor:
            return .high
        case .colleague, .professionalContact, .custom:
            return .medium
        }
    }

    static func alwaysDoFor(_ context: ExchangeModels.ContactContext) -> [String] {
        switch context.relationshipGoal {
        case .maintainFriendship, .becomeCloserFriends, .reconnectCasually, .personalRelationship:
            return ["keep the tone warm and easy to continue"]
        case .warmProfessionalContact, .developClientRelationship:
            return ["stay clear, polite, and responsive"]
        case .winFutureContract, .explorePartnership, .referralContact:
            return ["answer logistics directly"]
        case .maintainSupplierRelationship:
            return ["stay brief and bounded"]
        case .buildInvestorRelationship:
            return ["stay precise and credible"]
        case .custom:
            return ["stay within the saved relationship goal"]
        }
    }

    static func neverDoFor(_ context: ExchangeModels.ContactContext) -> [String] {
        var output = avoidPhrases(for: context.relationshipType)
        if context.relationshipType == .client || context.relationshipType == .lead {
            output.append("overpromise delivery or terms")
        }
        return output
    }

    static func effectiveRelationshipLabel(for context: ExchangeModels.ContactContext) -> String {
        if context.relationshipType == .custom,
           let custom = clipped(context.customRelationshipLabel, maxChars: 80) {
            return custom
        }
        return relationshipLabel(for: context.relationshipType)
    }

    static func effectiveGoalLabel(for context: ExchangeModels.ContactContext) -> String {
        if context.relationshipGoal == .custom,
           let custom = clipped(context.customRelationshipGoal, maxChars: 80) {
            return custom
        }
        return goalLabel(for: context.relationshipGoal)
    }

    static func relationshipLabel(for type: ExchangeModels.ContactRelationshipType) -> String {
        switch type {
        case .friend:
            return "friend"
        case .family:
            return "family"
        case .colleague:
            return "colleague"
        case .professionalContact:
            return "professional contact"
        case .client, .lead:
            return "client or lead"
        case .supplier, .contractor:
            return "supplier or contractor"
        case .investor, .broker:
            return "investor or broker"
        case .custom:
            return "custom relationship"
        }
    }

    static func goalLabel(for goal: ExchangeModels.RelationshipGoal) -> String {
        switch goal {
        case .maintainFriendship:
            return "maintain friendship"
        case .becomeCloserFriends:
            return "become closer friends"
        case .warmProfessionalContact:
            return "warm professional contact"
        case .developClientRelationship:
            return "develop client relationship"
        case .winFutureContract:
            return "win future contract"
        case .explorePartnership:
            return "explore partnership"
        case .buildInvestorRelationship:
            return "build investor relationship"
        case .maintainSupplierRelationship:
            return "maintain supplier relationship"
        case .referralContact:
            return "referral contact"
        case .reconnectCasually:
            return "reconnect casually"
        case .personalRelationship:
            return "personal relationship"
        case .custom:
            return "custom goal"
        }
    }

    static func baseTone(for type: ExchangeModels.ContactRelationshipType) -> String {
        switch type {
        case .friend, .family:
            return "warm, natural, casual"
        case .colleague, .professionalContact, .client, .lead, .supplier, .contractor, .investor, .broker:
            return "clear, polite, concise"
        case .custom:
            return "neutral, respectful, low-assumption"
        }
    }

    static func avoidPhrases(for type: ExchangeModels.ContactRelationshipType) -> [String] {
        switch type {
        case .friend, .family:
            return ["sounding formal", "overexplaining"]
        case .colleague, .professionalContact, .client, .lead, .supplier, .contractor, .investor, .broker:
            return ["sounding stiff", "overpromising"]
        case .custom:
            return ["sounding presumptuous", "overexplaining"]
        }
    }

    static func styleConstraintsFor(goal: ExchangeModels.RelationshipGoal) -> [String] {
        switch goal {
        case .maintainFriendship, .becomeCloserFriends, .reconnectCasually, .personalRelationship:
            return ["make it easy to continue the conversation"]
        case .warmProfessionalContact, .developClientRelationship, .buildInvestorRelationship:
            return ["clear and friendly without overfamiliarity"]
        case .winFutureContract, .explorePartnership, .referralContact:
            return ["answer logistics directly"]
        case .maintainSupplierRelationship:
            return ["brief, bounded, no extra invitation"]
        case .custom:
            return ["stay within the relationship goal"]
        }
    }

    static func clipped(_ value: String?, maxChars: Int) -> String? {
        let trimmed = value?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
