import Foundation

public struct FederationHealthResponse: Codable, Sendable {
    public let ok: Bool
    public let service: String
    public let time: String

    public init(
        ok: Bool,
        service: String,
        time: String
    ) {
        self.ok = ok
        self.service = service
        self.time = time
    }
}

// MARK: - Node public keys

public struct ExchangeNodePublicKeys: Codable, Sendable, Hashable {
    public let nodeID: String
    public let signingKeyID: String?
    public let signingPublicKey: String?
    public let encryptionKeyID: String?
    public let encryptionPublicKey: String?

    public init(
        nodeID: String,
        signingKeyID: String? = nil,
        signingPublicKey: String? = nil,
        encryptionKeyID: String? = nil,
        encryptionPublicKey: String? = nil
    ) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.signingKeyID = signingKeyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.signingPublicKey = signingPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.encryptionKeyID = encryptionKeyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.encryptionPublicKey = encryptionPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Registration / publication

public struct FederationRegisterNodeRequest: Codable, Sendable {
    public let nodeID: String
    public let displayName: String
    public let publicKeyID: String?
    public let publicProfile: FederationPublicProfileDTO
    public let offers: [FederationOfferDTO]

    public init(
        nodeID: String,
        displayName: String,
        publicKeyID: String? = nil,
        publicProfile: FederationPublicProfileDTO,
        offers: [FederationOfferDTO] = []
    ) {
        self.nodeID = nodeID
        self.displayName = displayName
        self.publicKeyID = publicKeyID
        self.publicProfile = publicProfile
        self.offers = offers
    }
}

public struct FederationRegisterNodeResponse: Codable, Sendable {
    public let ok: Bool
    public let nodeID: String
    public let profileID: String
    public let offerIDs: [String]

    public init(
        ok: Bool,
        nodeID: String,
        profileID: String,
        offerIDs: [String] = []
    ) {
        self.ok = ok
        self.nodeID = nodeID
        self.profileID = profileID
        self.offerIDs = offerIDs
    }
}

// MARK: - Directory search

public struct FederationDirectorySearchRequest: Codable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

public struct FederationDirectorySearchResponse: Codable, Sendable {
    public let ok: Bool
    public let count: Int
    public let results: [FederationDirectorySurfaceDTO]

    public init(
        ok: Bool,
        count: Int,
        results: [FederationDirectorySurfaceDTO]
    ) {
        self.ok = ok
        self.count = count
        self.results = results
    }
}

/// Search result is surface-first, not counterparty-first.
public struct FederationDirectorySurfaceDTO: Codable, Sendable {
    public let nodeID: String
    public let displayName: String
    public let publicKeyID: String?
    public let publicProfile: FederationPublicProfileDTO
    public let offers: [FederationOfferDTO]

    public init(
        nodeID: String,
        displayName: String,
        publicKeyID: String? = nil,
        publicProfile: FederationPublicProfileDTO,
        offers: [FederationOfferDTO] = []
    ) {
        self.nodeID = nodeID
        self.displayName = displayName
        self.publicKeyID = publicKeyID
        self.publicProfile = publicProfile
        self.offers = offers
    }
}

// MARK: - Public profile DTO

public struct FederationPublicProfileDTO: Codable, Sendable {
    public let id: String
    public let nodeID: String
    public let displayName: String?
    public let headline: String?
    public let summary: String?
    public let visibility: String
    public let availability: String

    public let interests: [String]
    public let openTo: [String]
    public let excludedTopics: [String]
    public let activityTags: [String]
    public let regionTags: [String]

    public let semantic: FederationSemanticSurfaceDTO?
    public let reachability: FederationReachabilityDTO
    public let approach: FederationApproachDTO?

    public init(
        id: String,
        nodeID: String,
        displayName: String? = nil,
        headline: String? = nil,
        summary: String? = nil,
        visibility: String,
        availability: String,
        interests: [String] = [],
        openTo: [String] = [],
        excludedTopics: [String] = [],
        activityTags: [String] = [],
        regionTags: [String] = [],
        semantic: FederationSemanticSurfaceDTO? = nil,
        reachability: FederationReachabilityDTO,
        approach: FederationApproachDTO? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.displayName = displayName
        self.headline = headline
        self.summary = summary
        self.visibility = visibility
        self.availability = availability
        self.interests = interests
        self.openTo = openTo
        self.excludedTopics = excludedTopics
        self.activityTags = activityTags
        self.regionTags = regionTags
        self.semantic = semantic
        self.reachability = reachability
        self.approach = approach
    }
}

public struct FederationSemanticSurfaceDTO: Codable, Sendable {
    public let domains: [String]
    public let intentKinds: [String]
    public let audienceKinds: [String]
    public let fulfillmentModes: [String]
    public let notes: String?

    public init(
        domains: [String] = [],
        intentKinds: [String] = [],
        audienceKinds: [String] = [],
        fulfillmentModes: [String] = [],
        notes: String? = nil
    ) {
        self.domains = domains
        self.intentKinds = intentKinds
        self.audienceKinds = audienceKinds
        self.fulfillmentModes = fulfillmentModes
        self.notes = notes
    }
}

public struct FederationReachabilityDTO: Codable, Sendable {
    public let acceptingInbound: Bool
    public let accessMode: String
    public let minimumTrustLevel: String?
    public let requiresCategoryMatch: Bool
    public let requiresMutualFit: Bool
    public let intentCategoryPolicy: String?
    public let disclosureCeiling: String?
    public let routeableOnly: Bool

    public init(
        acceptingInbound: Bool,
        accessMode: String,
        minimumTrustLevel: String? = nil,
        requiresCategoryMatch: Bool = false,
        requiresMutualFit: Bool = false,
        intentCategoryPolicy: String? = nil,
        disclosureCeiling: String? = nil,
        routeableOnly: Bool = true
    ) {
        self.acceptingInbound = acceptingInbound
        self.accessMode = accessMode
        self.minimumTrustLevel = minimumTrustLevel
        self.requiresCategoryMatch = requiresCategoryMatch
        self.requiresMutualFit = requiresMutualFit
        self.intentCategoryPolicy = intentCategoryPolicy
        self.disclosureCeiling = disclosureCeiling
        self.routeableOnly = routeableOnly
    }
}

public struct FederationApproachDTO: Codable, Sendable {
    public let preferredStyle: String?
    public let preferredFirstContactKinds: [String]
    public let note: String?

    public init(
        preferredStyle: String? = nil,
        preferredFirstContactKinds: [String] = [],
        note: String? = nil
    ) {
        self.preferredStyle = preferredStyle
        self.preferredFirstContactKinds = preferredFirstContactKinds
        self.note = note
    }
}

// MARK: - Offer DTO

public struct FederationOfferDTO: Codable, Sendable {
    public let id: String
    public let nodeID: String
    public let publicProfileID: String?
    public let title: String
    public let summary: String?
    public let category: String?
    public let tags: [String]
    public let regionTags: [String]
    public let semantic: FederationOfferSemanticDTO?
    public let fulfillment: FederationOfferFulfillmentDTO?
    public let status: String
    public let visibility: String
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String,
        nodeID: String,
        publicProfileID: String? = nil,
        title: String,
        summary: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        regionTags: [String] = [],
        semantic: FederationOfferSemanticDTO? = nil,
        fulfillment: FederationOfferFulfillmentDTO? = nil,
        status: String,
        visibility: String,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.publicProfileID = publicProfileID
        self.title = title
        self.summary = summary
        self.category = category
        self.tags = tags
        self.regionTags = regionTags
        self.semantic = semantic
        self.fulfillment = fulfillment
        self.status = status
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FederationOfferSemanticDTO: Codable, Sendable {
    public let domains: [String]
    public let serviceKinds: [String]
    public let audienceKinds: [String]
    public let fulfillmentModes: [String]
    public let notes: String?

    public init(
        domains: [String] = [],
        serviceKinds: [String] = [],
        audienceKinds: [String] = [],
        fulfillmentModes: [String] = [],
        notes: String? = nil
    ) {
        self.domains = domains
        self.serviceKinds = serviceKinds
        self.audienceKinds = audienceKinds
        self.fulfillmentModes = fulfillmentModes
        self.notes = notes
    }
}

public struct FederationOfferFulfillmentDTO: Codable, Sendable {
    public let pricingMode: String?
    public let commitmentMode: String?
    public let remoteFriendly: Bool?
    public let leadTimeNote: String?
    public let capacityNote: String?

    public init(
        pricingMode: String? = nil,
        commitmentMode: String? = nil,
        remoteFriendly: Bool? = nil,
        leadTimeNote: String? = nil,
        capacityNote: String? = nil
    ) {
        self.pricingMode = pricingMode
        self.commitmentMode = commitmentMode
        self.remoteFriendly = remoteFriendly
        self.leadTimeNote = leadTimeNote
        self.capacityNote = capacityNote
    }
}

// MARK: - Envelopes

public struct FederationSendEnvelopeRequest: Codable, Sendable {
    public let envelopeID: String
    public let threadID: String?
    public let senderNodeID: String
    public let recipientNodeID: String
    public let payload: FederationEnvelopePayloadDTO

    public init(
        envelopeID: String,
        threadID: String? = nil,
        senderNodeID: String,
        recipientNodeID: String,
        payload: FederationEnvelopePayloadDTO
    ) {
        self.envelopeID = envelopeID
        self.threadID = threadID
        self.senderNodeID = senderNodeID
        self.recipientNodeID = recipientNodeID
        self.payload = payload
    }
}

public struct FederationEnvelopePayloadDTO: Codable, Sendable {
    public let kind: String
    public let subject: String?
    public let body: String

    /// Selected execution basis on the recipient's public seller surface.
    public let targetPublicProfileID: String?
    public let targetOfferID: String?

    public init(
        kind: String,
        subject: String? = nil,
        body: String,
        targetPublicProfileID: String? = nil,
        targetOfferID: String? = nil
    ) {
        self.kind = kind
        self.subject = subject
        self.body = body
        self.targetPublicProfileID = targetPublicProfileID
        self.targetOfferID = targetOfferID
    }
}

public struct FederationSendEnvelopeResponse: Codable, Sendable {
    public let ok: Bool
    public let envelopeID: String
    public let status: String

    public init(
        ok: Bool,
        envelopeID: String,
        status: String
    ) {
        self.ok = ok
        self.envelopeID = envelopeID
        self.status = status
    }
}

public struct FederationInboxResponse: Codable, Sendable {
    public let ok: Bool
    public let count: Int
    public let items: [FederationInboxEnvelopeDTO]

    public init(
        ok: Bool,
        count: Int,
        items: [FederationInboxEnvelopeDTO]
    ) {
        self.ok = ok
        self.count = count
        self.items = items
    }
}

public struct FederationInboxEnvelopeDTO: Codable, Sendable {
    public let envelopeID: String
    public let threadID: String?
    public let senderNodeID: String
    public let recipientNodeID: String
    public let payload: FederationEnvelopePayloadDTO
    public let protocolVersion: String
    public let status: String
    public let createdAt: String

    public init(
        envelopeID: String,
        threadID: String? = nil,
        senderNodeID: String,
        recipientNodeID: String,
        payload: FederationEnvelopePayloadDTO,
        protocolVersion: String,
        status: String,
        createdAt: String
    ) {
        self.envelopeID = envelopeID
        self.threadID = threadID
        self.senderNodeID = senderNodeID
        self.recipientNodeID = recipientNodeID
        self.payload = payload
        self.protocolVersion = protocolVersion
        self.status = status
        self.createdAt = createdAt
    }
}

public struct FederationAckRequest: Codable, Sendable {
    public let envelopeID: String

    public init(envelopeID: String) {
        self.envelopeID = envelopeID
    }
}

public struct FederationAckResponse: Codable, Sendable {
    public let ok: Bool
    public let updated: Int

    public init(
        ok: Bool,
        updated: Int
    ) {
        self.ok = ok
        self.updated = updated
    }
}
