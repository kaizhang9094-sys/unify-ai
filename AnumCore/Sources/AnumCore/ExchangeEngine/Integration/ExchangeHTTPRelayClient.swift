import Foundation

#if DEBUG
@inline(__always)
private func exchRelayHTTPLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeHTTPRelayClient] \(message())")
}
@inline(__always)
private func refreshTraceRelayLog(_ message: @autoclosure () -> String) {
    Swift.print("[RefreshTrace] \(message())")
}
#else
@inline(__always)
private func exchRelayHTTPLog(_ message: @autoclosure () -> String) {}
@inline(__always)
private func refreshTraceRelayLog(_ message: @autoclosure () -> String) {}
#endif

public final class ExchangeHTTPRelayClient: ExchangeRelayClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let localNodeIDProvider: @Sendable () async throws -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let signer: ExchangeFederationRequestSigner

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        localNodeIDProvider: @escaping @Sendable () async throws -> String,
        signer: ExchangeFederationRequestSigner = .init()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.localNodeIDProvider = localNodeIDProvider
        self.signer = signer

        self.encoder = ExchangeFederationRequestSigner.makeDeterministicJSONEncoder()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        #if DEBUG
        exchRelayHTTPLog("init ExchangeHTTPRelayClient baseURL=\(baseURL.absoluteString)")
        #endif
    }

    public func send(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult {
        let recipientNodeID = try recipientNodeID(from: envelope, route: route)

        var relayMetadata = ExchangeOutboundRelayMetadataSanitizer.allowlisted(from: envelope.metadata)
        if let p = envelope.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            relayMetadata["parent_envelope_id"] = p
        }

        let parentForSend = envelope.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let body = SendRequest(
            envelopeID: envelope.stableEnvelopeID,
            threadID: envelope.threadID.uuidString,
            senderNodeID: envelope.sender.nodeID,
            recipientNodeID: recipientNodeID,
            payload: .init(
                kind: envelope.payload.kind.rawValue,
                subject: envelope.payload.subject,
                body: envelope.payload.body,
                disclosureLevel: envelope.payload.disclosureLevel.rawValue,
                intentTitle: envelope.payload.threadContext?.intentTitle,
                mode: envelope.payload.threadContext?.mode,
                localThreadID: envelope.payload.threadContext?.localThreadID,
                encryption: envelope.payload.encryption
            ),
            metadata: relayMetadata,
            parentEnvelopeID: parentForSend,
            sequenceNumber: envelope.ordering.sequenceNumber
        )

        #if DEBUG
        let outboundRelayAudit =
            " relayMetadataKeys=\(relayMetadata.count) hasSelectedOfferID=\(relayMetadata["selected_offer_id"] != nil)"
        let keysSorted = relayMetadata.keys.sorted().joined(separator: ",")
        Swift.print(
            "[RelayMetadataOut] envelopeID=\(envelope.stableEnvelopeID) keys=\(keysSorted) " +
                "conversation=\(relayMetadata["conversation_id"] ?? "nil") root=\(relayMetadata["root_envelope_id"] ?? "nil") " +
                "original=\(relayMetadata["original_requester_envelope_id"] ?? "nil") parent=\(relayMetadata["parent_envelope_id"] ?? parentForSend ?? "nil") " +
                "orderingParent=\(parentForSend ?? "nil") seq=\(envelope.ordering.sequenceNumber.map(String.init) ?? "nil") " +
                "conversation_surface_envelope=\(envelope.metadata["conversation_surface"] ?? "nil") " +
                "conversation_surface_relay=\(relayMetadata["conversation_surface"] ?? "nil")"
        )
        #else
        let outboundRelayAudit = ""
        #endif

        exchRelayHTTPLog(
            "send start envelopeID=\(envelope.stableEnvelopeID) " +
                "threadID=\(envelope.threadID.uuidString) " +
                "sender=\(envelope.sender.nodeID) recipient=\(recipientNodeID) " +
                "route=\(route?.summaryLine ?? envelope.recipient.route.summaryLine) " +
                "protocolVersion=\(envelope.protocolVersion)" +
                outboundRelayAudit
        )

        let response: SendResponse = try await post(
            path: "/v1/envelopes/send",
            body: body,
            requiresSignature: true
        )

        guard response.ok else {
            exchRelayHTTPLog(
                "send backend returned ok=false envelopeID=\(response.envelopeID) status=\(response.status)"
            )
            throw ExchangeRelayClientError.transportFailure(
                reason: "Relay send returned an unsuccessful response."
            )
        }

        let normalizedStatus = response.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status: ExchangeRelaySendResult.Status

        switch normalizedStatus {
        case "delivered", "accepted":
            status = .accepted
        case "queued":
            status = .queued
        case "rejected":
            status = .rejected
        case "incompatible":
            status = .incompatible
        default:
            status = .unknown
        }

        exchRelayHTTPLog(
            "send done envelopeID=\(response.envelopeID) status=\(response.status) mappedStatus=\(status)"
        )
        refreshTraceRelayLog(
            "[RelaySendAccepted] envelopeID=\(response.envelopeID) recipient=\(recipientNodeID) status=\(status) time=\(Date())"
        )
        #if DEBUG
        ExchangeBilateralConversationDebugTrace.logFederationSend(
            envelopeID: envelope.stableEnvelopeID,
            outboxID: nil,
            sourceThreadID: envelope.threadID,
            routeKey: route?.routeKey ?? route?.summaryLine ?? envelope.recipient.route.summaryLine,
            targetNodeID: recipientNodeID,
            parentEnvelopeID: parentForSend,
            conversationID: relayMetadata["conversation_id"],
            rootEnvelopeID: relayMetadata["root_envelope_id"],
            originalRequesterEnvelopeID: relayMetadata["original_requester_envelope_id"],
            conversationSurface: relayMetadata["conversation_surface"],
            sendResult: String(describing: status)
        )
        #endif

        let resolvedExternalReference =
            response.externalReference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? response.envelopeID

        return ExchangeRelaySendResult(
            status: status,
            externalReference: resolvedExternalReference,
            acceptedAt: Date(),
            routeSummary: route?.summaryLine ?? envelope.recipient.route.summaryLine,
            note: response.status
        )
    }

    public func fetchDeliveryStatus(reference: String) async throws -> ExchangeRelayDeliveryStatus? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let url = try deliveryStatusRequestURL(reference: trimmed)
        exchRelayHTTPLog("fetchDeliveryStatus url=\(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeRelayClientError.transportFailure(
                reason: "Non-HTTP response from federation server."
            )
        }

        if http.statusCode == 404 {
            return nil
        }

        try validateHTTP(response: response, data: data)

        let dto: DeliveryStatusResponseDTO
        do {
            dto = try decoder.decode(DeliveryStatusResponseDTO.self, from: data)
        } catch {
            exchRelayHTTPLog("fetchDeliveryStatus decode failed error=\(error)")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Failed to decode delivery status response: \(error)"
            )
        }

        let mappedStatus = ExchangeRelayDeliveryStatusMapping.mapServerStatus(dto.status)
        let checkedAt = ExchangeRelayDeliveryStatusMapping.parseCheckedAt(dto.checkedAt)
        let note = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let echoReference = dto.reference.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? trimmed

        return ExchangeRelayDeliveryStatus(
            reference: echoReference,
            status: mappedStatus,
            checkedAt: checkedAt,
            note: note
        )
    }

    public func syncInbox(
        request: ExchangeRelayInboxSyncRequest
    ) async throws -> ExchangeRelayInboxSyncResponse {
        let localNodeID = try await localNodeIDProvider()
        let effectiveNodeID = request.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? localNodeID

        var components = URLComponents(
            url: url(for: "/v1/inbox/\(effectiveNodeID)"),
            resolvingAgainstBaseURL: false
        )

        var queryItems: [URLQueryItem] = []
        if let cursor = request.cursor?.trimmingCharacters(in: .whitespacesAndNewlines), !cursor.isEmpty {
            queryItems.append(.init(name: "cursor", value: cursor))
        }
        if let limit = request.limit, limit > 0 {
            queryItems.append(.init(name: "limit", value: String(limit)))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let requestURL = components?.url else {
            throw ExchangeRelayClientError.invalidSyncRequest(
                reason: "Failed to build inbox sync URL."
            )
        }

        exchRelayHTTPLog(
            "syncInbox start node=\(effectiveNodeID) cursor=\(request.cursor ?? "nil") " +
            "limit=\(request.limit.map(String.init) ?? "nil") url=\(requestURL.absoluteString)"
        )
        refreshTraceRelayLog(
            "[InboxSyncStart] runID=http-sync trigger=syncInbox nodeID=\(effectiveNodeID) checkpoint=\(request.cursor ?? "nil") time=\(Date())"
        )

        let response: InboxSyncResponseDTO = try await get(
            url: requestURL,
            requiresSignature: true
        )

        if let ok = response.ok, ok == false {
            exchRelayHTTPLog("syncInbox backend returned ok=false node=\(effectiveNodeID)")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Relay inbox sync returned an unsuccessful response."
            )
        }

        let mapped: [ExchangeRelayInboundReceipt] = response.receipts.compactMap { receipt -> ExchangeRelayInboundReceipt? in
            let recipientTrimmed = receipt.recipientNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recipientTrimmed.isEmpty && recipientTrimmed != effectiveNodeID {
                refreshTraceRelayLog(
                    "[InboundRecipientMismatchIgnored] requestedNodeID=\(effectiveNodeID) recipientNodeID=\(recipientTrimmed) senderNodeID=\(receipt.senderNodeID) envelopeID=\(receipt.envelopeID) receiptID=\(receipt.receiptID)"
                )
                return nil
            }
            guard let threadID = UUID(uuidString: receipt.threadID ?? "") else {
                exchRelayHTTPLog(
                    "syncInbox drop receiptID=\(receipt.receiptID) " +
                    "reason=invalid_thread_id rawThreadID=\(receipt.threadID ?? "nil")"
                )
                return nil
            }

            let createdAt = Self.parseDate(receipt.createdAt) ?? Date()
            let receivedAt = Self.parseDate(receipt.receivedAt ?? receipt.createdAt) ?? createdAt

            let disclosureLevel =
                ExchangeRelayEnvelope.Payload.DisclosureLevel(
                    rawValue: receipt.payload.disclosureLevel ?? ""
                ) ?? .balanced

            let threadContext: ExchangeRelayEnvelope.Payload.ThreadContext? = {
                guard
                    let localThreadID = receipt.payload.localThreadID?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !localThreadID.isEmpty,
                    let mode = receipt.payload.mode?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !mode.isEmpty
                else {
                    return nil
                }

                return .init(
                    localThreadID: localThreadID,
                    mode: mode,
                    intentTitle: receipt.payload.intentTitle
                )
            }()

            let envelope = ExchangeRelayEnvelope(
                id: UUID(),
                createdAt: createdAt,
                protocolVersion: receipt.protocolVersion,
                threadID: threadID,
                sender: .init(
                    nodeID: receipt.senderNodeID,
                    displayName: receipt.senderDisplayName,
                    publicKeyID: receipt.senderPublicKeyID
                ),
                recipient: .init(
                    route: .node(id: receipt.recipientNodeID),
                    displayName: receipt.recipientDisplayName
                ),
                payload: .init(
                    kind: ExchangeRelayEnvelope.Payload.Kind(rawValue: receipt.payload.kind) ?? .other,
                    subject: receipt.payload.subject,
                    body: receipt.payload.body,
                    disclosureLevel: disclosureLevel,
                    threadContext: threadContext,
                    encryption: receipt.payload.encryption
                ),
                signature: nil,
                ordering: .init(
                    sequenceNumber: receipt.sequenceNumber,
                    parentEnvelopeID: receipt.parentEnvelopeID,
                    idempotencyKey: receipt.envelopeID
                ),
                metadata: receipt.metadata.merging(
                    ["relay_status": receipt.status],
                    uniquingKeysWith: { _, new in new }
                )
            )

            #if DEBUG
            let md = envelope.metadata
            let keysSorted = md.keys.sorted().joined(separator: ",")
            let ordParent = envelope.ordering.parentEnvelopeID ?? "nil"
            Swift.print(
                "[RelayMetadataIn] envelopeID=\(envelope.stableEnvelopeID) keys=\(keysSorted) " +
                    "conversation=\(md["conversation_id"] ?? "nil") root=\(md["root_envelope_id"] ?? "nil") " +
                    "original=\(md["original_requester_envelope_id"] ?? "nil") parentMeta=\(md["parent_envelope_id"] ?? "nil") " +
                    "orderingParent=\(ordParent) seq=\(envelope.ordering.sequenceNumber.map(String.init) ?? "nil") " +
                    "conversation_surface=\(md["conversation_surface"] ?? "nil")"
            )
            #endif

            exchRelayHTTPLog(
                "syncInbox.protocolVersion receiptID=\(receipt.receiptID) " +
                "raw=\(receipt.protocolVersion) mapped=\(envelope.protocolVersion)"
            )

            let compatibility: ExchangeRelayInboundReceipt.Compatibility = {
                switch receipt.compatibility?.lowercased() {
                case nil, "", "supported":
                    return .supported
                case "unsupportedversion":
                    return .unsupportedVersion(receipt.compatibilityValue)
                case "unsupportedpayload":
                    return .unsupportedPayload(receipt.compatibilityValue)
                case "malformed":
                    return .malformed(receipt.compatibilityValue ?? "Malformed relay receipt.")
                default:
                    return .supported
                }
            }()

            let status: ExchangeRelayInboundReceipt.Status = {
                switch receipt.status.lowercased() {
                case "redelivered":
                    return .redelivered
                case "acknowledged":
                    return .acknowledged
                case "ignored":
                    return .ignored
                default:
                    return .new
                }
            }()

            let relayRoute: ExchangeRelayRoute? = {
                guard let routeDTO = receipt.route else { return nil }

                let kind = mapRouteKind(routeDTO.kind)
                let destination = routeDTO.destination.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !destination.isEmpty else {
                    exchRelayHTTPLog(
                        "syncInbox drop route receiptID=\(receipt.receiptID) reason=empty_destination"
                    )
                    return nil
                }

                var routeMetadata: [String: String] = [:]

                if let relayNodeID = routeDTO.relayNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !relayNodeID.isEmpty {
                    routeMetadata["relay_node_id"] = relayNodeID
                }

                if let mailboxID = routeDTO.mailboxID?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !mailboxID.isEmpty {
                    routeMetadata["mailbox_id"] = mailboxID
                }

                if let note = routeDTO.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    routeMetadata["route_note"] = note
                }

                return ExchangeRelayRoute(
                    routeKey: "\(kind.rawValue):\(destination)",
                    kind: kind,
                    destination: destination,
                    relayServer: routeDTO.relayNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    protocolVersion: receipt.protocolVersion,
                    priority: .normal,
                    expiresAt: nil,
                    metadata: routeMetadata
                )
            }()

            return ExchangeRelayInboundReceipt(
                receiptID: receipt.receiptID,
                mailboxNodeID: receipt.mailboxNodeID,
                receivedAt: receivedAt,
                envelope: envelope,
                route: relayRoute,
                externalReference: receipt.externalReference ?? receipt.envelopeID,
                status: status,
                compatibility: compatibility,
                metadata: receipt.metadata
            )
        }

        let sorted = mapped.sorted { lhs, rhs in
            if lhs.receivedAt != rhs.receivedAt {
                return lhs.receivedAt < rhs.receivedAt
            }
            return lhs.receiptID < rhs.receiptID
        }

        exchRelayHTTPLog(
            "syncInbox done node=\(effectiveNodeID) rawCount=\(response.receipts.count) " +
            "mappedCount=\(sorted.count) nextCursor=\(response.nextCursor ?? "nil") hasMore=\(response.hasMore)"
        )
        let envelopeIDs = sorted.map { $0.envelope.stableEnvelopeID }.joined(separator: ",")
        refreshTraceRelayLog(
            "[InboxSyncResult] runID=http-sync rawCount=\(response.receipts.count) mappedCount=\(sorted.count) envelopeIDs=\(envelopeIDs) nextCheckpoint=\(response.nextCursor ?? "nil") time=\(Date())"
        )

        return ExchangeRelayInboxSyncResponse(
            receipts: sorted,
            nextCursor: response.nextCursor,
            hasMore: response.hasMore,
            syncedAt: response.syncedAt.flatMap(Self.parseDate),
            note: response.note
        )
    }

    public func acknowledgeInboxItems(
        _ acknowledgements: [ExchangeRelayInboxAcknowledgement]
    ) async throws -> ExchangeRelayInboxAcknowledgeResponse {
        guard !acknowledgements.isEmpty else {
            exchRelayHTTPLog("ack batch skip count=0")
            return ExchangeRelayInboxAcknowledgeResponse(
                acknowledgedReceiptIDs: [],
                rejectedReceiptIDs: [],
                updatedCount: 0,
                note: "No acknowledgements supplied."
            )
        }

        let localNodeID = try await localNodeIDProvider()

        let body = InboxAckRequestDTO(
            acknowledgements: acknowledgements.map {
                .init(
                    receiptID: $0.receiptID,
                    envelopeID: $0.envelopeID,
                    acknowledgedAt: Self.iso8601String(from: $0.acknowledgedAt),
                    result: $0.result.rawValue,
                    note: $0.note
                )
            }
        )

        exchRelayHTTPLog(
            "ack batch start node=\(localNodeID) count=\(acknowledgements.count)"
        )

        let response: InboxAckResponseDTO = try await post(
            path: "/v1/inbox/\(localNodeID)/ack",
            body: body,
            requiresSignature: true
        )

        guard response.ok else {
            exchRelayHTTPLog("ack batch backend returned ok=false node=\(localNodeID)")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Relay inbox acknowledgment returned an unsuccessful response."
            )
        }

        exchRelayHTTPLog(
            "ack batch done node=\(localNodeID) updated=\(response.updatedCount) " +
            "acked=\(response.acknowledgedReceiptIDs.count) rejected=\(response.rejectedReceiptIDs.count)"
        )

        return ExchangeRelayInboxAcknowledgeResponse(
            acknowledgedReceiptIDs: response.acknowledgedReceiptIDs,
            rejectedReceiptIDs: response.rejectedReceiptIDs,
            updatedCount: response.updatedCount,
            note: response.note
        )
    }

    public enum PushRegistrationEnvironment: String, Sendable, Encodable {
        case sandbox
        case production
    }

    public struct PushTokenRegistrationResponse: Decodable, Sendable {
        public let ok: Bool
        public let id: String?
        public let note: String?
    }

    /// Registers (upserts) this device token with the federation server for secretary APNs.
    public func registerPushToken(
        nodeID: String,
        apnsToken: String,
        environment: PushRegistrationEnvironment,
        bundleID: String,
        deviceID: String?
    ) async throws -> PushTokenRegistrationResponse {
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            throw ExchangeRelayClientError.invalidSyncRequest(reason: "nodeID is empty.")
        }

        struct Body: Encodable {
            let platform: String
            let apnsToken: String
            let environment: String
            let bundleID: String
            let deviceID: String?
        }

        let body = Body(
            platform: "ios",
            apnsToken: apnsToken.trimmingCharacters(in: .whitespacesAndNewlines),
            environment: environment.rawValue,
            bundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )

        exchRelayHTTPLog(
            "[APNs] registration start POST /v1/nodes/\(trimmedNode)/push-tokens env=\(body.environment)"
        )

        return try await post(
            path: "/v1/nodes/\(trimmedNode)/push-tokens",
            body: body,
            requiresSignature: true
        )
    }

    public struct PushTokenDisableResponse: Decodable, Sendable {
        public let ok: Bool
        public let disabledRowCount: Int?
        public let note: String?
    }

    /// Disables the given APNs device token for secretary pushes on the federation server (per-device delivery opt-out).
    public func disablePushToken(nodeID: String, apnsToken: String) async throws -> PushTokenDisableResponse {
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            throw ExchangeRelayClientError.invalidSyncRequest(reason: "nodeID is empty.")
        }

        struct Body: Encodable {
            let apnsToken: String
        }

        let trimmedToken = apnsToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedToken.isEmpty else {
            throw ExchangeRelayClientError.invalidSyncRequest(reason: "apnsToken is empty.")
        }

        let body = Body(apnsToken: trimmedToken)

        exchRelayHTTPLog(
            "[APNs] disable start POST /v1/nodes/\(trimmedNode)/push-tokens/disable"
        )

        return try await post(
            path: "/v1/nodes/\(trimmedNode)/push-tokens/disable",
            body: body,
            requiresSignature: true
        )
    }
}

private extension ExchangeHTTPRelayClient {
    static func parseDate(_ raw: String) -> Date? {
        ExchangeRelayDeliveryStatusMapping.parseServerISO8601Date(raw)
    }

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func recipientNodeID(
        from envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) throws -> String {
        if let route {
            switch route.kind {
            case .node:
                let trimmed = route.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            case .relayAddress, .relayMailbox, .emailBridge, .localLoopback:
                break
            }
        }

        switch envelope.recipient.route {
        case .node(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        case .relayAddress(let value),
             .email(let value),
             .other(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        throw ExchangeRelayClientError.invalidEnvelope(
            reason: "Recipient node ID could not be resolved."
        )
    }

    func mapRouteKind(_ raw: String) -> ExchangeRelayRoute.Kind {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "node":
            return .node
        case "relayaddress":
            return .relayAddress
        case "relaymailbox":
            return .relayMailbox
        case "emailbridge":
            return .emailBridge
        case "localloopback":
            return .localLoopback
        default:
            return .node
        }
    }

    func get<Response: Decodable>(
        url: URL,
        requiresSignature: Bool = false
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresSignature {
            do {
                let canonicalPath = try signer.canonicalPath(for: url)
                let signedHeaders = try signer.makeSignedFederationHeaders(
                    method: "GET",
                    path: canonicalPath,
                    bodyData: Data("{}".utf8),
                    endpointLabel: "relay:get:\(url.path)"
                )
                signer.apply(signedHeaders, to: &request)
                let bodyHashHex = ExchangeFederationRequestSigner.bodyHashHex(for: Data("{}".utf8))
                exchRelayHTTPLog(
                    "signedRequest endpoint=relay:get:\(url.path) method=GET " +
                    "canonicalPath=\(canonicalPath) timestamp=\(signedHeaders.timestamp) " +
                    "noncePrefix=\(String(signedHeaders.nonce.prefix(8))) bodyHashPrefix=\(String(bodyHashHex.prefix(12))) " +
                    "bodyBytes=2 nodeID=\(signedHeaders.nodeID) publicKeyID=\(signedHeaders.publicKeyID) " +
                    "signaturePrefix=\(String(signedHeaders.signature.prefix(12)))"
                )
            } catch {
                throw ExchangeRelayClientError.invalidSyncRequest(
                    reason: "Failed to sign protected relay GET request."
                )
            }
        }

        exchRelayHTTPLog("GET \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            exchRelayHTTPLog("GET decode failed url=\(url.absoluteString) error=\(error)")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Failed to decode relay response: \(error)"
            )
        }
    }

    func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        requiresSignature: Bool = false
    ) async throws -> Response {
        let requestURL = url(for: path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
            request.httpBody = bodyData
        } catch {
            exchRelayHTTPLog("POST encode failed url=\(requestURL.absoluteString) error=\(error)")
            throw ExchangeRelayClientError.invalidEnvelope(
                reason: "Failed to encode relay request body: \(error)"
            )
        }

        if requiresSignature {
            do {
                let canonicalPath = try signer.canonicalPath(for: requestURL)
                let signedHeaders = try signer.makeSignedFederationHeaders(
                    method: "POST",
                    path: canonicalPath,
                    bodyData: bodyData,
                    endpointLabel: "relay:post:\(requestURL.path)"
                )
                signer.apply(signedHeaders, to: &request)
                let bodyHashHex = ExchangeFederationRequestSigner.bodyHashHex(for: bodyData)
                let bodyPreview = String(decoding: bodyData.prefix(500), as: UTF8.self)
                exchRelayHTTPLog(
                    "signedRequest endpoint=relay:post:\(requestURL.path) method=POST " +
                    "canonicalPath=\(canonicalPath) timestamp=\(signedHeaders.timestamp) " +
                    "noncePrefix=\(String(signedHeaders.nonce.prefix(8))) bodyHashPrefix=\(String(bodyHashHex.prefix(12))) " +
                    "bodyBytes=\(bodyData.count) bodyPreview=\(bodyPreview) " +
                    "nodeID=\(signedHeaders.nodeID) publicKeyID=\(signedHeaders.publicKeyID) " +
                    "signaturePrefix=\(String(signedHeaders.signature.prefix(12)))"
                )
            } catch {
                throw ExchangeRelayClientError.invalidEnvelope(
                    reason: "Failed to sign protected relay request."
                )
            }
        }

        exchRelayHTTPLog("POST \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            exchRelayHTTPLog("POST decode failed url=\(requestURL.absoluteString) error=\(error)")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Failed to decode relay response: \(error)"
            )
        }
    }

    func url(for path: String) -> URL {
        if path.hasPrefix("/") {
            return baseURL.appendingPathComponent(String(path.dropFirst()))
        }
        return baseURL.appendingPathComponent(path)
    }

    /// Builds `GET /v1/relay/status/<percent-encoded-reference>` against `baseURL` (unsigned; matches current server).
    func deliveryStatusRequestURL(reference: String) throws -> URL {
        let encoded = ExchangeRelayDeliveryStatusMapping.percentEncodedPathSegmentForStatusReference(reference)
        guard !encoded.isEmpty else {
            throw ExchangeRelayClientError.invalidSyncRequest(
                reason: "Failed to percent-encode delivery status reference."
            )
        }

        var base = baseURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }

        guard let url = URL(string: "\(base)/v1/relay/status/\(encoded)") else {
            throw ExchangeRelayClientError.invalidSyncRequest(
                reason: "Failed to build delivery status URL."
            )
        }
        return url
    }

    func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            exchRelayHTTPLog("validateHTTP failed reason=non_http_response")
            throw ExchangeRelayClientError.transportFailure(
                reason: "Non-HTTP response from federation server."
            )
        }

        guard (200...299).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let message = FederationHTTPErrorMessage.userFacingReason(data: data, fallback: rawBody)
            exchRelayHTTPLog("validateHTTP failed status=\(http.statusCode) body=\(message)")

            switch http.statusCode {
            case 400:
                throw ExchangeRelayClientError.invalidSyncRequest(reason: message)
            case 401, 403:
                throw ExchangeRelayClientError.unauthorized(reason: message)
            case 409:
                throw ExchangeRelayClientError.rejected(reason: message)
            case 426:
                throw ExchangeRelayClientError.incompatibleVersion(version: nil)
            case 429:
                if FederationHTTPErrorMessage.isQuotaOrRateLimitResponse(data: data, statusCode: http.statusCode) {
                    let retryAfter = FederationHTTPErrorMessage.resolvedRateLimitRetryAfterSeconds(
                        data: data,
                        http: http
                    )
                    throw ExchangeRelayClientError.rateLimited(
                        reason: message,
                        retryAfterSeconds: retryAfter
                    )
                }
                throw ExchangeRelayClientError.transportFailure(reason: message)
            case 500...599:
                throw ExchangeRelayClientError.unavailable(reason: message)
            default:
                throw ExchangeRelayClientError.transportFailure(reason: message)
            }
        }
    }
}

private extension ExchangeHTTPRelayClient {
    struct SendRequest: Encodable {
        let envelopeID: String
        let threadID: String?
        let senderNodeID: String
        let recipientNodeID: String
        let payload: PayloadDTO
        /// Allowlisted outbound anchor/routing hints for federation `relay_envelopes.metadata_json`.
        /// Keys must remain snake_case; values are trimmed non-empty strings only.
        let metadata: [String: String]
        /// Wire-level reply linkage (mirrors `ExchangeRelayEnvelope.Ordering`); omitted when nil.
        let parentEnvelopeID: String?
        let sequenceNumber: Int?

        struct PayloadDTO: Encodable {
            let kind: String
            let subject: String?
            let body: String
            let disclosureLevel: String?
            let intentTitle: String?
            let mode: String?
            let localThreadID: String?
            let encryption: ExchangeRelayPayloadEncryption?

            enum CodingKeys: String, CodingKey {
                case kind
                case subject
                case body
                case disclosureLevel
                case intentTitle
                case mode
                case localThreadID
                case encryption
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(kind, forKey: .kind)
                try container.encodeIfPresent(subject, forKey: .subject)
                try container.encode(body, forKey: .body)
                try container.encodeIfPresent(disclosureLevel, forKey: .disclosureLevel)
                try container.encodeIfPresent(intentTitle, forKey: .intentTitle)
                try container.encodeIfPresent(mode, forKey: .mode)
                try container.encodeIfPresent(localThreadID, forKey: .localThreadID)
                try container.encodeIfPresent(encryption, forKey: .encryption)
            }
        }

        enum CodingKeys: String, CodingKey {
            case envelopeID
            case threadID
            case senderNodeID
            case recipientNodeID
            case payload
            case metadata
            case parentEnvelopeID
            case sequenceNumber
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(envelopeID, forKey: .envelopeID)
            try c.encodeIfPresent(threadID, forKey: .threadID)
            try c.encode(senderNodeID, forKey: .senderNodeID)
            try c.encode(recipientNodeID, forKey: .recipientNodeID)
            try c.encode(payload, forKey: .payload)
            try c.encode(metadata, forKey: .metadata)
            try c.encodeIfPresent(parentEnvelopeID, forKey: .parentEnvelopeID)
            try c.encodeIfPresent(sequenceNumber, forKey: .sequenceNumber)
        }
    }

    struct SendResponse: Decodable {
        let ok: Bool
        let envelopeID: String
        let status: String
        let externalReference: String?
    }

    struct DeliveryStatusResponseDTO: Decodable {
        let reference: String
        let status: String
        let checkedAt: String?
        let note: String?
    }

    struct InboxSyncResponseDTO: Decodable {
        let ok: Bool?
        let receipts: [InboxReceiptDTO]
        let nextCursor: String?
        let hasMore: Bool
        let syncedAt: String?
        let note: String?
    }

    struct InboxReceiptDTO: Decodable {
        let receiptID: String
        let mailboxNodeID: String?
        let envelopeID: String
        let externalReference: String?
        let threadID: String?
        let senderNodeID: String
        let senderDisplayName: String?
        let senderPublicKeyID: String?
        let recipientNodeID: String
        let recipientDisplayName: String?
        let payload: InboxPayloadDTO
        let protocolVersion: String
        let status: String
        let compatibility: String?
        let compatibilityValue: String?
        let createdAt: String
        let receivedAt: String?
        let sequenceNumber: Int?
        let parentEnvelopeID: String?
        let route: RouteDTO?
        let metadata: [String: String]
    }

    struct InboxPayloadDTO: Decodable {
        let kind: String
        let subject: String?
        let body: String
        let disclosureLevel: String?
        let intentTitle: String?
        let mode: String?
        let localThreadID: String?
        let encryption: ExchangeRelayPayloadEncryption?

        enum CodingKeys: String, CodingKey {
            case kind
            case subject
            case body
            case disclosureLevel
            case intentTitle
            case mode
            case localThreadID
            case encryption
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "message"
            subject = try container.decodeIfPresent(String.self, forKey: .subject)
            body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            disclosureLevel = try container.decodeIfPresent(String.self, forKey: .disclosureLevel)
            intentTitle = try container.decodeIfPresent(String.self, forKey: .intentTitle)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            localThreadID = try container.decodeIfPresent(String.self, forKey: .localThreadID)
            encryption = try container.decodeIfPresent(ExchangeRelayPayloadEncryption.self, forKey: .encryption)
        }
    }

    struct RouteDTO: Decodable {
        let kind: String
        let destination: String
        let relayNodeID: String?
        let mailboxID: String?
        let note: String?
    }

    struct InboxAckRequestDTO: Encodable {
        let acknowledgements: [AcknowledgementDTO]
    }

    struct AcknowledgementDTO: Encodable {
        let receiptID: String
        let envelopeID: String?
        let acknowledgedAt: String
        let result: String
        let note: String?
    }

    struct InboxAckResponseDTO: Decodable {
        let ok: Bool
        let acknowledgedReceiptIDs: [String]
        let rejectedReceiptIDs: [String]
        let updatedCount: Int
        let note: String?
    }
}

// MARK: - Outbound relay metadata (POST `/v1/envelopes/send`)

/// Projects `ExchangeRelayEnvelope.metadata` into a federation-safe outbound map (`raw.metadata`).
/// Does **not** include large free-form fields such as `target_description`.
internal enum ExchangeOutboundRelayMetadataSanitizer {
    internal static let allowlistedKeysInOrder: [String] = [
        "selected_offer_id",
        "selected_public_profile_id",
        "public_profile_id",
        "selected_counterparty_id",
        "counterparty_id",
        "matched_offer_id",
        "matched_profile_id",
        "thread_id",
        "thread_mode",
        "intent_kind",
        "draft_id",
        "draft_kind",
        "target_node_id",
        "route_kind",
        "route_destination",
        "requested_disclosure_level",
        "effective_disclosure_level",
        "conversation_id",
        "conversation_surface",
        "conversation_kind",
        "payload_kind",
        "contact_request",
        "introduction_request",
        "target_node_id",
        "sender_node_id",
        "root_envelope_id",
        "original_requester_envelope_id",
        "parent_envelope_id",
        "source_envelope_id",
        "reply_to_envelope_id",
        "dm_attachment_count",
        "dm_has_attachments",
        "dm_attachments_json",
        "dm_attachments_encrypted"
    ]

    /// Returns only allowlisted entries with trimmed non-empty string values (stable insertion order).
    internal static func allowlisted(from envelopeMetadata: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(allowlistedKeysInOrder.count)
        for key in allowlistedKeysInOrder {
            guard let raw = envelopeMetadata[key] else { continue }
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }
            let trimmedValue = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            out[trimmedKey] = trimmedValue
        }
        return out
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
