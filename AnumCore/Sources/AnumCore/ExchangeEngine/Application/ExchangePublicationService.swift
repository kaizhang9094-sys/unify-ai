import Foundation

public struct ExchangePublicationReadiness: Sendable, Hashable {
    public enum NextAction: String, Sendable, Hashable {
        case createProfile
        case fixProfile
        case addOffer
        case publishSurface
        case republishSurface
        case manageLiveSurface
    }

    public var hasPublicProfile: Bool
    public var hasActiveOffer: Bool
    public var hasAnyOffer: Bool
    public var validationIssues: [ExchangeSellerValidationIssue]
    public var publicationState: ExchangePublicationState?
    public var isReadyToPublish: Bool
    public var nextAction: NextAction
    public var statusLine: String
    public var nextStepText: String?

    public init(
        hasPublicProfile: Bool,
        hasActiveOffer: Bool,
        hasAnyOffer: Bool,
        validationIssues: [ExchangeSellerValidationIssue],
        publicationState: ExchangePublicationState?,
        isReadyToPublish: Bool,
        nextAction: NextAction,
        statusLine: String,
        nextStepText: String?
    ) {
        self.hasPublicProfile = hasPublicProfile
        self.hasActiveOffer = hasActiveOffer
        self.hasAnyOffer = hasAnyOffer
        self.validationIssues = validationIssues
        self.publicationState = publicationState
        self.isReadyToPublish = isReadyToPublish
        self.nextAction = nextAction
        self.statusLine = statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nextStepText = nextStepText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public protocol ExchangePublicationService: Sendable {
    func makeDefaultPublicationState(
        publicProfileID: String,
        now: Date
    ) -> ExchangePublicationState

    func evaluateReadiness(
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?,
        validationIssues: [ExchangeSellerValidationIssue]
    ) -> ExchangePublicationReadiness
}

public struct ExchangeDefaultPublicationService: ExchangePublicationService, Sendable {
    public init() {}

    public func makeDefaultPublicationState(
        publicProfileID _: String,
        now: Date = Date()
    ) -> ExchangePublicationState {
        ExchangePublicationState(
            status: .draft,
            isDirty: true,
            publishedAt: nil,
            lastAttemptAt: nil,
            lastSuccessAt: nil,
            lastLocalMutationAt: now,
            lastFailureSummary: nil,
            lastRemoteProfileID: nil,
            lastRemoteOfferIDs: [],
            lastPublishedFingerprint: nil,
            metadata: [:]
        )
    }

    public func evaluateReadiness(
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?,
        validationIssues: [ExchangeSellerValidationIssue]
    ) -> ExchangePublicationReadiness {
        let hasPublicProfile = (publicProfile != nil)
        let hasAnyOffer = !offers.isEmpty
        let hasActiveOffer = offers.contains { $0.status == .active && $0.visibility != .hidden }

        let hasBlockingIssues = validationIssues.contains { $0.severity == .error }
        let hasIssues = !validationIssues.isEmpty

        let isReadyToPublish = hasPublicProfile && hasActiveOffer && !hasBlockingIssues

        let state = publicationState
        let status = state?.status

        let nextAction: ExchangePublicationReadiness.NextAction
        let statusLine: String
        let nextStepText: String?

        if !hasPublicProfile {
            nextAction = .createProfile
            statusLine = "No public seller surface exists yet."
            nextStepText = "Create a public profile before expecting seller-side discovery."
        } else if hasBlockingIssues || hasIssues {
            nextAction = .fixProfile
            statusLine = "Your seller surface needs attention before it can safely publish."
            nextStepText = "Fix validation issues on the profile or offers."
        } else if !hasAnyOffer {
            nextAction = .addOffer
            statusLine = "Your public profile exists, but nothing is available outward yet."
            nextStepText = "Add your first offering so others can discover what you provide."
        } else if !isReadyToPublish {
            nextAction = .fixProfile
            statusLine = "Your seller surface is not ready to publish."
            nextStepText = "Fix the remaining issues before publishing."
        } else {
            switch status {
            case .published? where state?.isDirty == true:
                nextAction = .republishSurface
                statusLine = "Your seller surface changed locally and needs republishing."
                nextStepText = "Republish to make the remote directory reflect the latest public surface."

            case .stale?:
                nextAction = .republishSurface
                statusLine = "Your remote seller surface is stale."
                nextStepText = "Republish so discovery reflects the current public profile and offers."

            case .failed?:
                nextAction = .republishSurface
                statusLine = "The last publish attempt failed."
                nextStepText = state?.lastFailureSummary?.nilIfBlank
                    ?? "Retry publication to make the surface discoverable."

            case .pendingPublish?:
                nextAction = .republishSurface
                statusLine = "Your seller surface is waiting on publication."
                nextStepText = "Finish publication to make the surface discoverable."

            case .published?:
                nextAction = .manageLiveSurface
                statusLine = "Your seller surface is live."
                nextStepText = "Manage offers, pause visibility, or update the public surface."

            case .paused?:
                nextAction = .manageLiveSurface
                statusLine = "Your seller surface is paused."
                nextStepText = "Resume publication when you want to be discoverable again."

            case .pendingUnpublish?:
                nextAction = .manageLiveSurface
                statusLine = "Your seller surface is being withdrawn."
                nextStepText = "Wait for unpublish to complete or retry if needed."

            case .archived?:
                nextAction = .manageLiveSurface
                statusLine = "Your seller surface is archived."
                nextStepText = "Restore and republish if you want it discoverable again."

            case .draft?, nil:
                nextAction = .publishSurface
                statusLine = "Your seller surface is ready, but not published yet."
                nextStepText = "Publish the surface when you are ready to be discoverable."
            }
        }

        return ExchangePublicationReadiness(
            hasPublicProfile: hasPublicProfile,
            hasActiveOffer: hasActiveOffer,
            hasAnyOffer: hasAnyOffer,
            validationIssues: validationIssues,
            publicationState: publicationState,
            isReadyToPublish: isReadyToPublish,
            nextAction: nextAction,
            statusLine: statusLine,
            nextStepText: nextStepText
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
