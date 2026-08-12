import Foundation

/// Publication state for a node-owned seller surface.
///
/// This is not federation transport state.
/// It describes whether a local public profile / offer set is draft, pending,
/// published, stale, paused, archived, or failed to publish.
///
/// Important:
/// - local public profile existence is NOT the same as remote discoverability
/// - published means federation confirmed the outward projection
/// - stale means the local public surface changed after the last successful publish
public struct ExchangePublicationState: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case draft
        case pendingPublish
        case published
        case stale
        case paused
        case pendingUnpublish
        case archived
        case failed
    }

    public var status: Status

    /// True when the local public surface changed and remote projection no longer matches.
    public var isDirty: Bool

    public var publishedAt: Date?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastLocalMutationAt: Date?

    public var lastFailureSummary: String?
    public var lastRemoteProfileID: String?
    public var lastRemoteOfferIDs: [String]
    public var lastPublishedFingerprint: String?

    public var metadata: [String: String]

    public init(
        status: Status = .draft,
        isDirty: Bool = false,
        publishedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastLocalMutationAt: Date? = nil,
        lastFailureSummary: String? = nil,
        lastRemoteProfileID: String? = nil,
        lastRemoteOfferIDs: [String] = [],
        lastPublishedFingerprint: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.status = status
        self.isDirty = isDirty
        self.publishedAt = publishedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastLocalMutationAt = lastLocalMutationAt
        self.lastFailureSummary = lastFailureSummary?.nilIfBlank
        self.lastRemoteProfileID = lastRemoteProfileID?.nilIfBlank
        self.lastRemoteOfferIDs = Array(
            Set(
                lastRemoteOfferIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.lastPublishedFingerprint = lastPublishedFingerprint?.nilIfBlank
        self.metadata = metadata
    }
}

public extension ExchangePublicationState {
    var isPublishedRemotely: Bool {
        status == .published && !isDirty && lastSuccessAt != nil
    }

    var needsPublicationAttempt: Bool {
        switch status {
        case .draft, .pendingPublish, .stale, .failed:
            return true
        case .published:
            return isDirty
        case .paused, .pendingUnpublish, .archived:
            return false
        }
    }

    func markingLocalMutation(
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.isDirty = true
        copy.lastLocalMutationAt = date

        switch copy.status {
        case .published:
            copy.status = .stale
        case .paused, .pendingUnpublish, .archived:
            break
        case .draft, .pendingPublish, .stale, .failed:
            break
        }

        return copy
    }

    func markingPublishStarted(
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .pendingPublish
        copy.lastAttemptAt = date
        copy.lastFailureSummary = nil
        return copy
    }

    func markingPublished(
        remoteProfileID: String,
        remoteOfferIDs: [String],
        fingerprint: String?,
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .published
        copy.isDirty = false
        copy.publishedAt = date
        copy.lastAttemptAt = date
        copy.lastSuccessAt = date
        copy.lastFailureSummary = nil
        copy.lastRemoteProfileID = remoteProfileID.nilIfBlank
        copy.lastRemoteOfferIDs = Array(
            Set(
                remoteOfferIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        copy.lastPublishedFingerprint = fingerprint?.nilIfBlank
        return copy
    }

    func markingPublishFailed(
        summary: String,
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .failed
        copy.isDirty = true
        copy.lastAttemptAt = date
        copy.lastFailureSummary = summary.nilIfBlank
        return copy
    }

    func markingPaused(
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .paused
        copy.isDirty = false
        copy.lastLocalMutationAt = date
        return copy
    }

    func markingPendingUnpublish(
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .pendingUnpublish
        copy.lastAttemptAt = date
        return copy
    }

    func markingArchived(
        at date: Date = Date()
    ) -> ExchangePublicationState {
        var copy = self
        copy.status = .archived
        copy.isDirty = false
        copy.lastLocalMutationAt = date
        return copy
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
