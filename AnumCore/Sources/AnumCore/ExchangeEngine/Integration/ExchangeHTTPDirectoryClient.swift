import Foundation

#if DEBUG
@inline(__always)
private func exchDirectoryHTTPLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeHTTPDirectoryClient] \(message())")
}
#else
@inline(__always)
private func exchDirectoryHTTPLog(_ message: @autoclosure () -> String) {}
#endif

public final class ExchangeHTTPDirectoryClient: ExchangeDirectoryClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let signer: ExchangeFederationRequestSigner

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        signer: ExchangeFederationRequestSigner = .init()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.signer = signer

        self.encoder = ExchangeFederationRequestSigner.makeDeterministicJSONEncoder()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        exchDirectoryHTTPLog("init ExchangeHTTPDirectoryClient baseURL=\(baseURL.absoluteString)")
    }

    public func search(
        _ request: ExchangeDirectorySearchRequest
    ) async throws -> ExchangeDirectorySearchResponse {
        let normalizedQueryText = normalizedQuery(
            request.queryText ?? request.targetDescription ?? ""
        )

        let requestTags = normalizedTags(request.tags)
        let normalizedLimit = max(1, request.limit)

        let payload = RemoteDirectorySearchRequest(
            localNodeID: request.localNodeID,
            threadID: request.threadID?.uuidString,
            mode: request.mode.rawValue,
            intentKind: request.intentKind.rawValue,
            query: normalizedQueryText,
            targetDescription: request.targetDescription,
            tags: requestTags,
            openToTags: normalizedTags(request.openToTags),
            offerTags: normalizedTags(request.offerTags),
            excludedTags: normalizedTags(request.excludedTags),
            regionTags: normalizedTags(request.regionTags),
            queryEmbedding: request.queryEmbedding,
            limit: normalizedLimit,
            scope: request.scope.rawValue,
            routeRequirement: request.routeRequirement.rawValue,
            accessRequirement: request.accessRequirement.rawValue,
            disclosureRequirement: request.disclosureRequirement.rawValue,
            debugRecallToken: request.debugRecallToken,
            debugSeedOnly: request.debugSeedOnly,
            retrievalResponseMode: request.retrievalResponseMode?.rawValue
        )

        exchDirectoryHTTPLog(
            "search start federationBaseURL=\(baseURL.absoluteString) query=\(normalizedQueryText.isEmpty ? "nil" : normalizedQueryText) tags=\(requestTags) limit=\(normalizedLimit)"
        )

        let remote: RemoteDirectorySearchResponse = try await post(
            path: "/v1/directory/search",
            body: payload
        )

        exchDirectoryHTTPLog(
            "search directory response decoded ok rawResults=\(remote.results.count) ok=\(remote.ok)"
        )

        guard remote.ok else {
            exchDirectoryHTTPLog("search backend returned ok=false")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Directory backend returned an unsuccessful search response."
            )
        }

        exchDirectoryHTTPLog("search decoded results count=\(remote.results.count)")

        #if DEBUG
        let withPresentation = remote.results.filter {
            $0.publicProfile.publicSupporterPresentation?.showsGuardianCrown == true
        }.count
        GuardianCrownDebugLog.log(
            "DirectorySearchDecode",
            "profiles=\(remote.results.count) withPresentation=\(withPresentation)"
        )
        for (idx, row) in remote.results.enumerated() {
            let ownerNodeID = row.resolvedOwnerNodeID
            let title = row.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? row.offers.first?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? ownerNodeID
            let firstOffer = row.offers.first
            let category = firstOffer?.category?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? ""
            let img = row.publicProfile.primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? firstOffer?.primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            let imgShort = (img.map { String($0.prefix(72)) } ?? "nil")
            let terms = row.perServerMatchedTerms.isEmpty ? "-" : row.perServerMatchedTerms.joined(separator: ",")
            let scoreStr = row.score.map { String(format: "%.2f", $0) } ?? "nil"
            Swift.print(
                "[ForYouRanking][raw] index=\(idx) title=\(title) nodeID=\(ownerNodeID) score=\(scoreStr) matchedTerms=\(terms) category=\(category) primaryImage=\(imgShort)"
            )
        }
        #endif

        for row in remote.results {
            let ownerNodeID = row.resolvedOwnerNodeID
            let firstOffer = row.offers.first
            let firstOfferID = firstOffer?.id ?? "nil"
            let firstOfferTitle = firstOffer?.title ?? "nil"
            let firstOfferCategory = firstOffer?.category ?? "nil"
            let firstOfferTags = firstOffer?.tags ?? []
            let firstOfferRegions = firstOffer?.regionTags ?? []
            let embeddedDocs = row.retrievalDocuments.filter(\.hasEmbedding).count
            let embeddingDims = Array(
                Set(row.retrievalDocuments.compactMap { $0.embedding?.count }.filter { $0 > 0 })
            ).sorted()

            exchDirectoryHTTPLog(
                "search decoded row ownerNodeID=\(ownerNodeID) profileID=\(row.publicProfile.id) profileNodeID=\(row.publicProfile.nodeID ?? "nil") offerID=\(firstOfferID) resultTitle=\(row.displayName ?? firstOfferTitle) offersCount=\(row.offers.count) retrievalDocs=\(row.retrievalDocuments.count) embeddedDocs=\(embeddedDocs) dims=\(embeddingDims) firstOfferTitle=\(firstOfferTitle) firstOfferCategory=\(firstOfferCategory) firstOfferTags=\(firstOfferTags) firstOfferRegions=\(firstOfferRegions)"
            )

            #if DEBUG
            let v = row.directoryVectorSignals
            let objectPresent = v != nil
            let simStr = v?.vectorSimilarity.map { String(format: "%.4f", $0) } ?? "nil"
            let rankStr = v?.vectorRank.map(String.init) ?? "nil"
            let hitStr = v.map { String($0.vectorHitCount) } ?? "nil"
            let scoreStr = v?.vectorScore.map { String(format: "%.2f", $0) } ?? "nil"
            let bestDocStr = v?.bestVectorRetrievalDocID ?? "nil"
            let surfStr = v?.bestVectorSurfaceType ?? "nil"
            let srcStr = v?.vectorSource ?? "nil"
            Swift.print(
                "[DirectoryVector][decode] nodeID=\(ownerNodeID) objectPresent=\(objectPresent) embeddingAvailable=\(v?.embeddingAvailable ?? false) vectorRank=\(rankStr) vectorSimilarity=\(simStr) vectorScore=\(scoreStr) hitCount=\(hitStr) bestDocID=\(bestDocStr) bestSurfaceType=\(surfStr) source=\(srcStr)"
            )
            #endif

            if ownerNodeID == "node-seller-detailing-1",
               !row.offers.isEmpty {
                exchDirectoryHTTPLog(
                    "stale fixture guard remote_match ownerNodeID=node-seller-detailing-1 profileID=\(row.publicProfile.id) offerID=\(firstOfferID) resultTitle=\(row.displayName ?? firstOfferTitle)"
                )
            }
        }

        let matchedTerms = normalizedTags(
            requestTags + (normalizedQueryText.isEmpty ? [] : [normalizedQueryText])
        )

        var matches: [ExchangeDirectoryMatch] = []
        matches.reserveCapacity(remote.results.count)

        for row in remote.results {
            let match = mapDirectoryMatch(
                row,
                requestFallbackMatchedTerms: matchedTerms
            )
            matches.append(match)
        }

        #if DEBUG
        matches = ExchangeDebugMultilingualFixtureRegistry.mergeOverlay(into: matches)
        #endif

        exchDirectoryHTTPLog("search done count=\(matches.count)")

        #if DEBUG
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: remote.retrievalResponseMode,
            matchCount: matches.count,
            matches: matches
        )
        #endif

        return ExchangeDirectorySearchResponse(
            matches: matches,
            source: .remote,
            summary: remote.count > 0
                ? "Remote federation directory returned \(remote.count) result(s)."
                : "Remote federation directory returned no results.",
            searchedAt: Date(),
            trustAwareRankingApplied: false
        )
    }

    public func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let payload = RemotePublishSellerSurfaceRequest(
            nodeID: request.nodeID.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: request.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            surface: mapPublishedSurfacePayload(request.surface)
        )
        let bodyBytes: Int
        do {
            bodyBytes = try encoder.encode(payload).count
        } catch {
            bodyBytes = -1
        }
        let timeoutSeconds = session.configuration.timeoutIntervalForRequest

        exchDirectoryHTTPLog(
            "publishSellerSurface start nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id) offers=\(payload.surface.offers.count) bodyBytes=\(bodyBytes) timeoutSeconds=\(timeoutSeconds)"
        )

        #if DEBUG
        GuardianCrownDebugLog.log(
            "HTTPPublish",
            "nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id) " +
            "presentation=\(GuardianCrownDebugLog.presentationLabel(payload.surface.publicProfile.publicSupporterPresentation)) " +
            "included=\(payload.surface.publicProfile.publicSupporterPresentation != nil)"
        )
        #endif

        do {
            let response: RemotePublishSellerSurfaceResponse = try await post(
                path: "/v1/directory/publish-seller-surface",
                body: payload,
                requiresSignature: true
            )
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            exchDirectoryHTTPLog(
                "publishSellerSurface response ok=\(response.ok) status=2xx elapsedMs=\(elapsedMs) nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id)"
            )

            guard response.ok else {
                exchDirectoryHTTPLog(
                    "publishSellerSurface backend returned ok=false nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id) elapsedMs=\(elapsedMs)"
                )
                throw ExchangeDirectoryClientError.backendFailure(
                    reason: "Directory backend returned an unsuccessful publish response."
                )
            }

            exchDirectoryHTTPLog(
                "publishSellerSurface done nodeID=\(payload.nodeID) remoteProfileID=\(response.remoteProfileID) offers=\(response.remoteOfferIDs.count) elapsedMs=\(elapsedMs)"
            )

            #if DEBUG
            GuardianCrownDebugLog.log(
                "HTTPPublish",
                "nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id) success=true"
            )
            #endif

            return ExchangeSellerSurfacePublishResponse(
                ok: response.ok,
                remoteProfileID: response.remoteProfileID,
                remoteOfferIDs: response.remoteOfferIDs,
                publishedAt: response.publishedAt,
                note: response.note
            )
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            exchDirectoryHTTPLog(
                "publishSellerSurface error elapsedMs=\(elapsedMs) nodeID=\(payload.nodeID) profileID=\(payload.surface.publicProfile.id) error=\(error)"
            )
            throw error
        }
    }

    public func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        let normalizedNodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProfileID = publicProfileID.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = RemoteUnpublishSellerSurfaceRequest(
            nodeID: normalizedNodeID,
            publicProfileID: normalizedProfileID
        )

        exchDirectoryHTTPLog(
            "unpublishSellerSurface start nodeID=\(normalizedNodeID) profileID=\(normalizedProfileID)"
        )

        let response: RemoteUnpublishSellerSurfaceResponse = try await post(
            path: "/v1/directory/unpublish-seller-surface",
            body: payload,
            requiresSignature: true
        )

        guard response.ok else {
            exchDirectoryHTTPLog(
                "unpublishSellerSurface backend returned ok=false nodeID=\(normalizedNodeID) profileID=\(normalizedProfileID)"
            )
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Directory backend returned an unsuccessful unpublish response."
            )
        }

        exchDirectoryHTTPLog(
            "unpublishSellerSurface done nodeID=\(normalizedNodeID) profileID=\(normalizedProfileID)"
        )

        return ExchangeSellerSurfaceUnpublishResponse(
            ok: response.ok,
            nodeID: response.nodeID,
            publicProfileID: response.publicProfileID,
            unpublishedAt: response.unpublishedAt,
            note: response.note
        )
    }

    public func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse {
        let normalizedNodeID = request.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNodeID.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(
                reason: "Retrieval document publish request requires a node ID."
            )
        }

        let payload = RemotePublishRetrievalDocumentsRequest(
            nodeID: normalizedNodeID,
            sourceKind: request.sourceKind.rawValue,
            replaceAll: request.replaceAll,
            publishedAt: request.publishedAt,
            documents: request.documents
        )

        exchDirectoryHTTPLog(
            "publishRetrievalDocuments start nodeID=\(payload.nodeID) source=\(payload.sourceKind) docs=\(payload.documents.count) replaceAll=\(payload.replaceAll)"
        )

        let response: RemotePublishRetrievalDocumentsResponse = try await post(
            path: "/v1/directory/publish-retrieval-documents",
            body: payload,
            requiresSignature: true
        )

        guard response.ok else {
            exchDirectoryHTTPLog(
                "publishRetrievalDocuments backend returned ok=false nodeID=\(payload.nodeID) source=\(payload.sourceKind)"
            )
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Directory backend returned an unsuccessful retrieval publish response."
            )
        }

        exchDirectoryHTTPLog(
            "publishRetrievalDocuments done nodeID=\(response.nodeID) source=\(response.sourceKind) accepted=\(response.acceptedDocumentCount)"
        )

        return ExchangeRetrievalDocumentPublishResponse(
            ok: response.ok,
            nodeID: response.nodeID,
            sourceKind: ExchangeRetrievalDocument.SourceKind(rawValue: response.sourceKind) ?? request.sourceKind,
            acceptedDocumentCount: response.acceptedDocumentCount,
            publishedAt: response.publishedAt,
            note: response.note
        )
    }

    public func registerNode(
        nodeID: String,
        displayName: String,
        publicKeyID: String?,
        publicProfile: RegisterPublicProfile,
        encryptionKeyID: String? = nil,
        encryptionPublicKey: String? = nil
    ) async throws {
        let signingIdentity = try signer.currentIdentity()
        let normalizedNodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNodeID == signingIdentity.nodeID else {
            throw ExchangeDirectoryClientError.invalidRequest(
                reason: "Registration nodeID does not match local signing identity."
            )
        }
        if let publicKeyID,
           publicKeyID.trimmingCharacters(in: .whitespacesAndNewlines) != signingIdentity.publicKeyID {
            exchDirectoryHTTPLog(
                "registerNode publicKeyID mismatch arg=\(publicKeyID) signing=\(signingIdentity.publicKeyID)"
            )
        }

        let trimmedEncryptionKeyID = encryptionKeyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let trimmedEncryptionPublicKey = encryptionPublicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        let publishEncryption =
            trimmedEncryptionKeyID != nil && trimmedEncryptionPublicKey != nil

        let payload = RegisterNodeRequest(
            nodeID: normalizedNodeID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            publicKeyID: signingIdentity.publicKeyID,
            publicKey: signingIdentity.publicKeyData.base64EncodedString(),
            encryptionKeyID: publishEncryption ? trimmedEncryptionKeyID : nil,
            encryptionPublicKey: publishEncryption ? trimmedEncryptionPublicKey : nil,
            publicProfile: publicProfile
        )

        exchDirectoryHTTPLog(
            "registerNode start nodeID=\(payload.nodeID) displayName=\(payload.displayName) profileID=\(payload.publicProfile.id)"
        )
        let payloadPublicKeyPrefix = String(payload.publicKey.prefix(16))
        let encryptionKeyIDPrefix = trimmedEncryptionKeyID.map { String($0.prefix(8)) } ?? "nil"
        exchDirectoryHTTPLog(
            "registerNode identity signingNodeID=\(signingIdentity.nodeID) " +
            "signingPublicKeyID=\(signingIdentity.publicKeyID) " +
            "argPublicKeyID=\(publicKeyID ?? "nil") " +
            "payloadPublicKeyPrefix=\(payloadPublicKeyPrefix) " +
            "encryptionPublished=\(publishEncryption) encryptionKeyIDPrefix=\(encryptionKeyIDPrefix)"
        )

        let response: RegisterNodeResponse = try await post(
            path: "/v1/nodes/register",
            body: payload,
            requiresSignature: true
        )

        guard response.ok else {
            exchDirectoryHTTPLog("registerNode backend returned ok=false nodeID=\(payload.nodeID)")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Directory backend returned an unsuccessful registration response."
            )
        }

        exchDirectoryHTTPLog(
            "registerNode done nodeID=\(response.nodeID) profileID=\(response.profileID) " +
            "encryptionPublished=\(publishEncryption)"
        )
    }

    /// Fetches a node's published signing and encryption public keys (no auth required).
    public func fetchNodePublicKeys(
        nodeID: String,
        forceRefresh: Bool = false
    ) async throws -> ExchangeNodePublicKeys {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(reason: "nodeID is required.")
        }

        if !forceRefresh {
            if let cached = await ExchangeNodePublicKeysCache.shared.cachedKeys(nodeID: trimmed) {
                return cached
            }
            if await ExchangeNodePublicKeysCache.shared.isNegativeCached(nodeID: trimmed) {
                print("[publicKeyCache] miss negative nodeID=\(trimmed)")
                throw ExchangeDirectoryClientError.backendFailure(
                    reason: "Node public keys are not available (recent negative cache)."
                )
            }
            print("[publicKeyCache] miss nodeID=\(trimmed)")
        } else {
            await ExchangeNodePublicKeysCache.shared.invalidate(nodeID: trimmed)
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        let requestURL = url(for: "/v1/nodes/\(encoded)/keys")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        exchDirectoryHTTPLog("fetchNodePublicKeys start nodeID=\(trimmed) forceRefresh=\(forceRefresh)")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 404 {
            await ExchangeNodePublicKeysCache.shared.storeNegative(nodeID: trimmed)
        }

        try validateHTTP(response: response, data: data)

        let decoded: RemoteNodePublicKeysResponse
        do {
            decoded = try decoder.decode(RemoteNodePublicKeysResponse.self, from: data)
        } catch {
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Failed to decode node public keys response."
            )
        }

        guard decoded.ok else {
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Node public keys request was not successful."
            )
        }

        let hasEncryptionKey =
            decoded.encryptionPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let encryptionKeyIDPrefix = decoded.encryptionKeyID.map { String($0.prefix(8)) } ?? "nil"

        exchDirectoryHTTPLog(
            "fetchNodePublicKeys done nodeID=\(decoded.nodeID) hasEncryptionKey=\(hasEncryptionKey) " +
            "encryptionKeyIDPrefix=\(encryptionKeyIDPrefix)"
        )

        let keys = ExchangeNodePublicKeys(
            nodeID: decoded.nodeID,
            signingKeyID: decoded.signingKeyID,
            signingPublicKey: decoded.signingPublicKey,
            encryptionKeyID: decoded.encryptionKeyID,
            encryptionPublicKey: decoded.encryptionPublicKey
        )

        await ExchangeNodePublicKeysCache.shared.store(keys: keys)
        return keys
    }

    public func uploadPublicMedia(
        data: Data,
        mimeType: String,
        nodeID: String,
        role: String,
        publicProfileID: String?,
        offerID: String?
    ) async throws -> String {
        let trimmedNodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedNodeID.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(reason: "Missing local node ID for media upload.")
        }
        guard !trimmedRole.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(reason: "Missing media role for upload.")
        }
        guard !data.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(reason: "Image data is empty.")
        }
        guard !trimmedMime.isEmpty else {
            throw ExchangeDirectoryClientError.invalidRequest(reason: "Missing image MIME type.")
        }

        let boundary = "ExchangeMediaBoundary-\(UUID().uuidString)"
        let requestURL = url(for: "/v1/media/upload")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("nodeID", trimmedNodeID)
        appendField("role", trimmedRole)
        appendField("mimeType", trimmedMime)

        if let publicProfileID,
           let trimmedID = publicProfileID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            appendField("publicProfileID", trimmedID)
        }

        if let offerID,
           let trimmedID = offerID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            appendField("offerID", trimmedID)
        }

        let filename: String = {
            switch trimmedMime.lowercased() {
            case "image/jpeg", "image/jpg": return "image.jpg"
            case "image/png": return "image.png"
            case "image/heic": return "image.heic"
            case "image/heif": return "image.heif"
            default: return "image.bin"
            }
        }()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(trimmedMime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        do {
            let canonicalPath = try signer.canonicalPath(for: requestURL)
            let signedHeaders = try signer.makeSignedFederationHeaders(
                method: "POST",
                path: canonicalPath,
                bodyData: body,
                endpointLabel: "directory:post:\(requestURL.path)"
            )
            signer.apply(signedHeaders, to: &request)
        } catch {
            throw ExchangeDirectoryClientError.invalidRequest(
                reason: "Failed to sign media upload request."
            )
        }

        exchDirectoryHTTPLog(
            "uploadPublicMedia start nodeID=\(trimmedNodeID) role=\(trimmedRole) bytes=\(data.count) mime=\(trimmedMime)"
        )

        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            exchDirectoryHTTPLog("uploadPublicMedia transport failure error=\(error)")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Media upload network error: \(error.localizedDescription)"
            )
        }

        try validateHTTP(response: response, data: responseData)

        let decoded: RemoteUploadMediaResponse
        do {
            decoded = try decoder.decode(RemoteUploadMediaResponse.self, from: responseData)
        } catch {
            exchDirectoryHTTPLog("uploadPublicMedia decode failure error=\(error)")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Media upload returned an unreadable response."
            )
        }

        guard decoded.ok else {
            exchDirectoryHTTPLog("uploadPublicMedia backend ok=false note=\(decoded.note ?? "nil")")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: decoded.note?.nilIfBlank ?? "Media upload was rejected by the server."
            )
        }

        guard let imageURL = decoded.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            exchDirectoryHTTPLog("uploadPublicMedia missing imageURL in response")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Media upload response did not include a public image URL."
            )
        }

        exchDirectoryHTTPLog(
            "uploadPublicMedia done nodeID=\(trimmedNodeID) role=\(trimmedRole) url=\(imageURL)"
        )

        return imageURL
    }

    public func deletePublicMedia(
        storageKey: String,
        nodeID: String
    ) async -> ExchangePublicMediaDeleteOutcome {
        let trimmedNodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNodeID.isEmpty else {
            return .failed(reason: "Missing local node ID for media delete.")
        }
        guard let basename = PublicMediaURLSupport.storageKeyFromPublicMediaURL(storageKey) else {
            return .invalidStorageKey
        }

        let path = "/v1/media/\(basename)"
        let requestURL = url(for: path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyData = Data("{}".utf8)
        request.httpBody = bodyData
        request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

        do {
            let canonicalPath = try signer.canonicalPath(for: requestURL)
            let signedHeaders = try signer.makeSignedFederationHeaders(
                method: "DELETE",
                path: canonicalPath,
                bodyData: bodyData,
                endpointLabel: "directory:delete:\(path)"
            )
            signer.apply(signedHeaders, to: &request)
        } catch {
            return .failed(reason: "Failed to sign media delete request.")
        }

        exchDirectoryHTTPLog("deletePublicMedia start nodeID=\(trimmedNodeID) storageKey=\(basename)")

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            exchDirectoryHTTPLog("deletePublicMedia transport failure error=\(error)")
            return .failed(reason: "Media delete network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            return .failed(reason: "Non-HTTP response from federation server.")
        }

        let outcome = PublicMediaURLSupport.deleteOutcome(
            statusCode: http.statusCode,
            responseData: responseData
        )
        exchDirectoryHTTPLog(
            "deletePublicMedia done nodeID=\(trimmedNodeID) storageKey=\(basename) outcome=\(outcome)"
        )
        return outcome
    }
}

public extension ExchangeHTTPDirectoryClient {
    struct RegisterPublicProfile: Codable, Sendable, Hashable {
        public struct Reachability: Codable, Sendable, Hashable {
            public var acceptingInbound: Bool
            public var accessMode: String

            public init(
                acceptingInbound: Bool,
                accessMode: String
            ) {
                self.acceptingInbound = acceptingInbound
                self.accessMode = accessMode.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        public var id: String
        public var visibility: String
        public var availability: String
        public var openTo: [String]
        public var offers: [String]
        public var semantic: [String: [String]]
        public var reachability: Reachability

        public init(
            id: String,
            visibility: ExchangePublicNodeProfile.Visibility,
            availability: ExchangePublicNodeProfile.Availability,
            openTo: [String],
            offers: [String],
            semantic: [String: [String]] = [:],
            reachability: Reachability
        ) {
            self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.visibility = visibility.rawValue
            self.availability = availability.rawValue
            self.openTo = openTo
            self.offers = offers
            self.semantic = semantic
            self.reachability = reachability
        }
    }
}

private extension ExchangeHTTPDirectoryClient {
    struct RemoteDirectorySearchRequest: Encodable {
        let localNodeID: String?
        let threadID: String?

        let mode: String
        let intentKind: String

        let query: String
        let targetDescription: String?
        let tags: [String]

        let openToTags: [String]
        let offerTags: [String]
        let excludedTags: [String]
        let regionTags: [String]

        let queryEmbedding: [Float]?

        let limit: Int

        let scope: String
        let routeRequirement: String
        let accessRequirement: String
        let disclosureRequirement: String

        let debugRecallToken: String?
        let debugSeedOnly: Bool?
        let retrievalResponseMode: String?
    }

    struct RemotePublishSellerSurfaceRequest: Encodable {
        let nodeID: String
        let displayName: String?
        let surface: RemotePublishedSellerSurfacePayload
    }

    struct RemotePublishedSellerSurfacePayload: Encodable {
        struct IndexedProviderSurfaceProjection: Encodable {
            struct RegionEvidence: Encodable {
                let regionTags: [String]
                let canonicalRegionIDs: [String]
                let parentRegionIDs: [String]
                let regionAliases: [String]
                let serviceAreaNotes: [String]
            }

            struct ReachabilitySummary: Encodable {
                let accessMode: String
                let acceptingInbound: Bool
                let disclosureCeiling: String
                let routeableOnly: Bool
                let intentCategoryPolicy: String
            }

            struct CommercialConstraint: Encodable {
                let text: String
                let isHard: Bool
            }

            struct TimeAvailabilityConstraint: Encodable {
                let text: String
                let isHard: Bool
            }

            let schemaVersion: Int
            let semanticConcepts: [String]
            let broadRecallTokens: [String]
            let hardConstraints: [String]
            let softPreferences: [String]
            let commercialConstraints: [CommercialConstraint]
            let timeAvailabilityConstraints: [TimeAvailabilityConstraint]
            let sourceTextBlocks: [String]
            let regions: RegionEvidence
            let reachability: ReachabilitySummary?
            let updatedAt: Date?
        }

        struct IndexedOfferSurfaceProjection: Encodable {
            struct CommercialConstraint: Encodable {
                let text: String
                let isHard: Bool
            }

            struct TimeAvailabilityConstraint: Encodable {
                let text: String
                let isHard: Bool
            }

            struct FulfillmentSummary: Encodable {
                let pricingMode: String
                let commitmentMode: String
                let remoteFriendly: Bool
                let leadTimeNote: String?
                let capacityNote: String?
                let serviceAreaNote: String?
            }

            let offerID: String
            let schemaVersion: Int
            let semanticConcepts: [String]
            let broadRecallTokens: [String]
            let hardConstraints: [String]
            let softPreferences: [String]
            let commercialConstraints: [CommercialConstraint]
            let timeAvailabilityConstraints: [TimeAvailabilityConstraint]
            let fulfillment: FulfillmentSummary?
            let sourceTextBlocks: [String]
            let visibility: String?
            let status: String?
            let updatedAt: Date?
        }

        struct PublicProfileProjection: Encodable {
            struct Reachability: Encodable {
                let acceptingInbound: Bool
                let accessMode: String
                let disclosureCeiling: String
                let routeableOnly: Bool
                let intentCategoryPolicy: String
            }

            let id: String
            let displayName: String?
            let headline: String?
            let summary: String?
            let visibility: String
            let availability: String
            let interests: [String]
            let offers: [String]
            let openTo: [String]
            let excludedTopics: [String]
            let activityTags: [String]
            let regionTags: [String]
            let semantic: [String: [String]]
            let reachability: Reachability
            let primaryImageURL: String?
            let publicSupporterPresentation: ExchangeSupporterPresentation?
        }

        struct PublishedOffer: Encodable {
            let id: String
            let title: String
            let summary: String?
            let category: String?
            let tags: [String]
            let regionTags: [String]
            let visibility: String
            let semantic: [String: [String]]
            let fulfillment: [String: String]
            let primaryImageURL: String?
            let galleryImageURLs: [String]
            /// Omitted when nil (older directory peers ignore unknown keys).
            let commercialFacts: ExchangeOffer.CommercialFacts?
            /// Omitted when nil (older directory peers ignore unknown keys).
            let contactInfo: ExchangeOffer.ContactInfo?
            /// Declared service areas with optional spatial metadata (omitted when empty).
            let serviceAreas: [ExchangeDeclaredServiceArea]?
        }

        let nodeID: String
        let displayName: String?
        let publicProfile: PublicProfileProjection
        let offers: [PublishedOffer]
        let indexedSurfaceVersion: Int?
        let indexedProviderSurface: IndexedProviderSurfaceProjection?
        let indexedOffers: [IndexedOfferSurfaceProjection]?
        let publishedAt: Date
        let fingerprint: String?
    }

    struct RemotePublishSellerSurfaceResponse: Decodable {
        let ok: Bool
        let remoteProfileID: String
        let remoteOfferIDs: [String]
        let publishedAt: Date
        let note: String?
    }

    struct RemoteUnpublishSellerSurfaceRequest: Encodable {
        let nodeID: String
        let publicProfileID: String
    }

    struct RemoteUnpublishSellerSurfaceResponse: Decodable {
        let ok: Bool
        let nodeID: String
        let publicProfileID: String
        let unpublishedAt: Date
        let note: String?
    }

    struct RemotePublishRetrievalDocumentsRequest: Encodable {
        let nodeID: String
        let sourceKind: String
        let replaceAll: Bool
        let publishedAt: Date
        let documents: [ExchangeRetrievalDocument]
    }

    struct RemotePublishRetrievalDocumentsResponse: Decodable {
        let ok: Bool
        let nodeID: String
        let sourceKind: String
        let acceptedDocumentCount: Int
        let publishedAt: Date
        let note: String?
    }

    func mapRemoteOffers(
        _ offers: [RemoteOffer],
        fallbackNodeID: String,
        fallbackPublicProfileID: String
    ) -> [ExchangeOffer] {
        let mapped = offers.compactMap {
            mapRemoteOffer(
                $0,
                fallbackNodeID: fallbackNodeID,
                fallbackPublicProfileID: fallbackPublicProfileID
            )
        }

        exchDirectoryHTTPLog(
            "mapRemoteOffers nodeID=\(fallbackNodeID) publicProfileID=\(fallbackPublicProfileID) remote=\(offers.count) mapped=\(mapped.count)"
        )

        return mapped
    }

    func mapRemoteOffer(
        _ remote: RemoteOffer,
        fallbackNodeID: String,
        fallbackPublicProfileID: String
    ) -> ExchangeOffer? {
        let resolvedID = remote.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = remote.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedID.isEmpty, !resolvedTitle.isEmpty else {
            exchDirectoryHTTPLog(
                "mapRemoteOffer dropped invalid offer id=\(remote.id) title=\(remote.title)"
            )
            return nil
        }

        let resolvedNodeID =
            remote.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? fallbackNodeID

        let resolvedPublicProfileID =
            remote.publicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? fallbackPublicProfileID

        let commercial =
            remote.commercialFacts?.normalized()
            ?? .empty
        let contact = remote.contactInfo?.normalized()

        let trimmedPrimary = remote.primaryImageURL
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        let normalizedGallery = ExchangeOffer.normalizedGalleryStorage(
            primary: trimmedPrimary,
            gallery: remote.galleryImageURLs
        )
        var offer = ExchangeOffer(
            id: resolvedID,
            nodeID: resolvedNodeID,
            publicProfileID: resolvedPublicProfileID,
            title: resolvedTitle,
            summary: remote.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            category: remote.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            tags: normalizedTags(remote.tags),
            regionTags: normalizedTags(remote.regionTags),
            serviceAreas: remote.serviceAreas,
            canonicalRegionIDs: normalizedTags(remote.canonicalRegionIDs),
            parentRegionIDs: normalizedTags(remote.parentRegionIDs),
            regionAliases: normalizedTags(remote.regionAliases),
            semantic: mapOfferSemantic(remote.semantic),
            fulfillment: mapOfferFulfillment(remote.fulfillment),
            status: mapOfferStatus(remote.status),
            visibility: mapOfferVisibility(remote.visibility),
            primaryImageURL: trimmedPrimary,
            galleryImageURLs: normalizedGallery,
            commercialFacts: commercial,
            contactInfo: (contact?.isEmpty == false) ? contact : nil
        )
        if !offer.serviceAreas.isEmpty {
            ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)
        }

        exchDirectoryHTTPLog(
            "mapRemoteOffer id=\(offer.id) title=\(offer.title) category=\(offer.category ?? "nil") visibility=\(offer.visibility.rawValue) status=\(offer.status.rawValue) searchableTerms=\(offer.semantic.searchableTerms)"
        )

        return offer
    }

    func mapOfferStatus(_ raw: String?) -> ExchangeOffer.Status {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return .active
        }

        if let exact = ExchangeOffer.Status(rawValue: raw) {
            return exact
        }

        switch raw.lowercased() {
        case "active":
            return .active
        case "paused":
            return .paused
        case "archived":
            return .archived
        case "draft":
            return .draft
        default:
            return .active
        }
    }

    func mapOfferVisibility(_ raw: String?) -> ExchangeOffer.Visibility {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return .publicDiscoverable
        }

        if let exact = ExchangeOffer.Visibility(rawValue: raw) {
            return exact
        }

        switch raw.lowercased() {
        case "publicdiscoverable", "public_discoverable", "public":
            return .publicDiscoverable
        case "limitedsurface", "limited_surface", "limited":
            return .limitedSurface
        case "hidden":
            return .hidden
        default:
            return .publicDiscoverable
        }
    }

    func mapOfferSemantic(
        _ semantic: [String: [String]]
    ) -> ExchangeOffer.SemanticSurface {
        ExchangeOffer.SemanticSurface(
            domains: normalizedTags(
                semantic["domains"] ?? semantic["domain"] ?? []
            ),
            serviceKinds: normalizedTags(
                semantic["serviceKinds"] ?? semantic["service_kinds"] ?? []
            ),
            audienceKinds: mapOfferAudienceKinds(
                semantic["audienceKinds"] ?? semantic["audience_kinds"] ?? []
            ),
            fulfillmentModes: mapOfferFulfillmentModes(
                semantic["fulfillmentModes"] ?? semantic["fulfillment_modes"] ?? []
            ),
            notes: (
                semantic["notes"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? semantic["note"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            )
        )
    }

    func mapOfferFulfillment(
        _ fulfillment: RemoteFulfillment
    ) -> ExchangeOffer.Fulfillment {
        return ExchangeOffer.Fulfillment(
            pricingMode: mapOfferPricingMode(fulfillment.pricingMode),
            commitmentMode: mapOfferCommitmentMode(fulfillment.commitmentMode),
            remoteFriendly: fulfillment.remoteFriendly,
            leadTimeNote: fulfillment.leadTime?.nilIfBlank,
            capacityNote: fulfillment.capacity?.nilIfBlank
        )
    }

    func mapOfferPricingMode(
        _ raw: String?
    ) -> ExchangeOffer.Fulfillment.PricingMode {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fixed":
            return .fixed
        case "custom":
            return .custom
        case "undisclosed":
            return .undisclosed
        case "quoterequired", "quote_required", "quote required":
            return .quoteRequired
        default:
            return .undisclosed
        }
    }

    func mapOfferCommitmentMode(
        _ raw: String?
    ) -> ExchangeOffer.Fulfillment.CommitmentMode {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "active":
            return .active
        case "approvalrequired", "approval_required", "approval required":
            return .approvalRequired
        case "exploratory":
            return .exploratory
        default:
            return .exploratory
        }
    }

    func mapOfferAudienceKinds(
        _ values: [String]
    ) -> [ExchangeOffer.SemanticSurface.AudienceKind] {
        values.compactMap {
            ExchangeOffer.SemanticSurface.AudienceKind(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func mapOfferFulfillmentModes(
        _ values: [String]
    ) -> [ExchangeOffer.SemanticSurface.FulfillmentMode] {
        values.compactMap {
            ExchangeOffer.SemanticSurface.FulfillmentMode(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func mapPublishedSurfacePayload(
        _ payload: ExchangePublishedSellerSurfacePayload
    ) -> RemotePublishedSellerSurfacePayload {
        let publicProfile = RemotePublishedSellerSurfacePayload.PublicProfileProjection(
            id: payload.publicProfile.id,
            displayName: payload.publicProfile.displayName,
            headline: payload.publicProfile.headline,
            summary: payload.publicProfile.summary,
            visibility: payload.publicProfile.visibility,
            availability: payload.publicProfile.availability,
            interests: payload.publicProfile.interests,
            offers: payload.publicProfile.offers,
            openTo: payload.publicProfile.openTo,
            excludedTopics: payload.publicProfile.excludedTopics,
            activityTags: payload.publicProfile.activityTags,
            regionTags: payload.publicProfile.regionTags,
            semantic: payload.publicProfile.semantic,
            reachability: .init(
                acceptingInbound: payload.publicProfile.reachability.acceptingInbound,
                accessMode: payload.publicProfile.reachability.accessMode,
                disclosureCeiling: payload.publicProfile.reachability.disclosureCeiling,
                routeableOnly: payload.publicProfile.reachability.routeableOnly,
                intentCategoryPolicy: payload.publicProfile.reachability.intentCategoryPolicy
            ),
            primaryImageURL: payload.publicProfile.primaryImageURL,
            publicSupporterPresentation: payload.publicProfile.publicSupporterPresentation
        )

        let offers = payload.offers.map {
            RemotePublishedSellerSurfacePayload.PublishedOffer(
                id: $0.id,
                title: $0.title,
                summary: $0.summary,
                category: $0.category,
                tags: $0.tags,
                regionTags: $0.regionTags,
                visibility: $0.visibility,
                semantic: $0.semantic,
                fulfillment: $0.fulfillment,
                primaryImageURL: $0.primaryImageURL,
                galleryImageURLs: $0.galleryImageURLs,
                commercialFacts: $0.commercialFacts,
                contactInfo: $0.contactInfo,
                serviceAreas: $0.serviceAreas.isEmpty ? nil : $0.serviceAreas
            )
        }

        let indexedProviderSurface = payload.indexedProviderSurface.map { provider in
            RemotePublishedSellerSurfacePayload.IndexedProviderSurfaceProjection(
                schemaVersion: provider.schemaVersion,
                semanticConcepts: provider.semanticConcepts,
                broadRecallTokens: provider.broadRecallTokens,
                hardConstraints: provider.hardConstraints,
                softPreferences: provider.softPreferences,
                commercialConstraints: provider.commercialConstraints.map {
                    .init(text: $0.text, isHard: $0.isHard)
                },
                timeAvailabilityConstraints: provider.timeAvailabilityConstraints.map {
                    .init(text: $0.text, isHard: $0.isHard)
                },
                sourceTextBlocks: provider.sourceTextBlocks,
                regions: .init(
                    regionTags: provider.regions.regionTags,
                    canonicalRegionIDs: provider.regions.canonicalRegionIDs,
                    parentRegionIDs: provider.regions.parentRegionIDs,
                    regionAliases: provider.regions.regionAliases,
                    serviceAreaNotes: provider.regions.serviceAreaNotes
                ),
                reachability: provider.reachability.map {
                    .init(
                        accessMode: $0.accessMode,
                        acceptingInbound: $0.acceptingInbound,
                        disclosureCeiling: $0.disclosureCeiling,
                        routeableOnly: $0.routeableOnly,
                        intentCategoryPolicy: $0.intentCategoryPolicy
                    )
                },
                updatedAt: provider.updatedAt
            )
        }

        let indexedOffers = payload.indexedOffers?.map { offer in
            RemotePublishedSellerSurfacePayload.IndexedOfferSurfaceProjection(
                offerID: offer.offerID,
                schemaVersion: offer.schemaVersion,
                semanticConcepts: offer.semanticConcepts,
                broadRecallTokens: offer.broadRecallTokens,
                hardConstraints: offer.hardConstraints,
                softPreferences: offer.softPreferences,
                commercialConstraints: offer.commercialConstraints.map {
                    .init(text: $0.text, isHard: $0.isHard)
                },
                timeAvailabilityConstraints: offer.timeAvailabilityConstraints.map {
                    .init(text: $0.text, isHard: $0.isHard)
                },
                fulfillment: offer.fulfillment.map {
                    .init(
                        pricingMode: $0.pricingMode,
                        commitmentMode: $0.commitmentMode,
                        remoteFriendly: $0.remoteFriendly,
                        leadTimeNote: $0.leadTimeNote,
                        capacityNote: $0.capacityNote,
                        serviceAreaNote: $0.serviceAreaNote
                    )
                },
                sourceTextBlocks: offer.sourceTextBlocks,
                visibility: offer.visibility,
                status: offer.status,
                updatedAt: offer.updatedAt
            )
        }

        return RemotePublishedSellerSurfacePayload(
            nodeID: payload.nodeID,
            displayName: payload.displayName,
            publicProfile: publicProfile,
            offers: offers,
            indexedSurfaceVersion: payload.indexedSurfaceVersion,
            indexedProviderSurface: indexedProviderSurface,
            indexedOffers: indexedOffers,
            publishedAt: payload.publishedAt,
            fingerprint: payload.fingerprint
        )
    }

    func mapDirectoryMatch(
        _ row: RemoteDirectoryRow,
        requestFallbackMatchedTerms: [String]
    ) -> ExchangeDirectoryMatch {
        let rowSpecificMatched = normalizedTags(row.perServerMatchedTerms)
        let effectiveMatchedTerms = rowSpecificMatched.isEmpty ? requestFallbackMatchedTerms : rowSpecificMatched

        let ownerNodeID = row.resolvedOwnerNodeID
        let resolvedDisplayName = row.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        let publicProfile = mapPublicProfile(
            nodeID: ownerNodeID,
            displayName: resolvedDisplayName,
            remote: row.publicProfile
        )

        let hydratedOffers = mapRemoteOffers(
            row.offers,
            fallbackNodeID: ownerNodeID,
            fallbackPublicProfileID: row.publicProfile.id
        )

        let counterpartyIdentity = ExchangeCounterparty.Identity(
            nodeID: ownerNodeID,
            publicKeyID: row.publicKeyID,
            verification: row.publicKeyID == nil ? .unverified : .selfAsserted
        )

        let remoteOfferTerms = buildRemoteOfferTerms(from: row.offers)

        let counterpartyTags = normalizedTags(
            publicProfile.openTo +
            publicProfile.offers +
            publicProfile.activityTags +
            publicProfile.regionTags +
            publicProfile.interests +
            row.publicProfile.interests +
            row.publicProfile.activityTags +
            row.publicProfile.regionTags +
            row.publicProfile.openTo +
            row.publicProfile.offers +
            remoteOfferTerms
        )

        let counterpartySemantic = mapSemanticProfile(
            publicProfile.semantic,
            remoteOffers: row.offers
        )

        let preferredRoute = ExchangeCounterparty.ContactRoute(
            kind: .exchangeNode,
            value: ownerNodeID,
            isPreferred: true
        )

        let counterpartyStatus = mapCounterpartyStatus(publicProfile.availability)

        let counterparty = ExchangeCounterparty(
            id: ownerNodeID,
            kind: inferredKind(from: publicProfile, remoteOffers: row.offers),
            displayName: resolvedDisplayName ?? ownerNodeID,
            source: .relayNetwork,
            identity: counterpartyIdentity,
            publicProfile: publicProfile,
            tags: counterpartyTags,
            semantic: counterpartySemantic,
            contactRoutes: [preferredRoute],
            status: counterpartyStatus
        )

        exchDirectoryHTTPLog(
            "counterparty upsert counterpartyID=\(counterparty.id) identityNodeID=\(counterparty.identity?.nodeID ?? "nil") publicProfileID=\(publicProfile.id) publicProfileNodeID=\(publicProfile.nodeID)"
        )

        return ExchangeDirectoryMatch.fromCounterparty(
            counterparty,
            offers: hydratedOffers,
            retrievalDocuments: hydrateRetrievalDocumentsWithHitEmbeddings(
                row.retrievalDocuments,
                hits: row.retrievalHits
            ),
            matchReason: "Remote federation directory match",
            matchedTerms: effectiveMatchedTerms,
            score: row.score,
            vectorSignals: row.directoryVectorSignals,
            retrievalHits: row.retrievalHits,
            candidateOfferIDsFromDocs: row.candidateOfferIDsFromDocs
        )
    }

    func hydrateRetrievalDocumentsWithHitEmbeddings(
        _ documents: [ExchangeRetrievalDocument],
        hits: [ExchangeDirectoryRetrievalHit]
    ) -> [ExchangeRetrievalDocument] {
        guard !documents.isEmpty, !hits.isEmpty else { return documents }

        let embeddingsByDocID = Dictionary(
            uniqueKeysWithValues: hits.compactMap { hit -> (String, [Float])? in
                guard let docID = hit.retrievalDocID?.nilIfBlank,
                      let embedding = hit.embedding,
                      !embedding.isEmpty else {
                    return nil
                }
                return (docID, embedding)
            }
        )
        guard !embeddingsByDocID.isEmpty else { return documents }

        return documents.map { document in
            guard !document.hasEmbedding,
                  let embedding = embeddingsByDocID[document.id] else {
                return document
            }
            return document.updatingEmbedding(embedding)
        }
    }

    func buildRemoteOfferTerms(from offers: [RemoteOffer]) -> [String] {
        var terms: [String] = []

        for offer in offers {
            terms.append(contentsOf: offerTerms(offer))
        }

        return normalizedTags(terms)
    }

    func offerTerms(_ offer: RemoteOffer) -> [String] {
        var values: [String] = []
        values.append(offer.title)

        if let summary = offer.summary {
            values.append(summary)
        }

        if let category = offer.category {
            values.append(category)
        }

        values.append(contentsOf: offer.tags)
        values.append(contentsOf: offer.regionTags)
        values.append(contentsOf: semanticValues(offer.semantic))

        return values
    }

    func semanticValues(_ semantic: [String: [String]]) -> [String] {
        var values: [String] = []
        values.append(contentsOf: semantic["domains"] ?? [])
        values.append(contentsOf: semantic["serviceKinds"] ?? [])
        values.append(contentsOf: semantic["audienceKinds"] ?? [])
        values.append(contentsOf: semantic["fulfillmentModes"] ?? [])
        return values
    }

    struct RemoteDirectorySearchResponse: Decodable {
        let ok: Bool
        let count: Int
        let results: [RemoteDirectoryRow]
        let retrievalResponseMode: String?
    }

    struct RemoteDirectoryRow: Decodable {
        let nodeID: String
        let ownerNodeID: String?
        let displayName: String?
        let publicKeyID: String?
        let publicProfile: RemotePublicProfile
        let offers: [RemoteOffer]
        let retrievalDocuments: [ExchangeRetrievalDocument]
        let retrievalHits: [ExchangeDirectoryRetrievalHit]
        let candidateOfferIDsFromDocs: [String]
        let score: Double?
        /// Per-result matched terms from directory JSON when present; empty if omitted.
        let perServerMatchedTerms: [String]
        let directoryVectorSignals: ExchangeDirectoryVectorSignals?

        enum CodingKeys: String, CodingKey {
            case nodeID
            case nodeId
            case ownerNodeID
            case ownerNodeId
            case displayName
            case publicKeyID
            case publicKeyId
            case publicProfile
            case offers
            case retrievalDocuments
            case retrievalHits
            case candidateOfferIDsFromDocs
            case score
            case matchedTerms
            case matchedTermsSnake = "matched_terms"
            case directoryVectorSignals
            case directoryVectorSignalsSnake = "directory_vector_signals"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.nodeID =
                try container.decodeIfPresent(String.self, forKey: .nodeID)
                ?? container.decodeIfPresent(String.self, forKey: .nodeId)
                ?? ""
            self.ownerNodeID =
                try container.decodeIfPresent(String.self, forKey: .ownerNodeID)
                ?? container.decodeIfPresent(String.self, forKey: .ownerNodeId)

            self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)

            self.publicKeyID =
                try container.decodeIfPresent(String.self, forKey: .publicKeyID)
                ?? container.decodeIfPresent(String.self, forKey: .publicKeyId)

            self.publicProfile = try container.decode(RemotePublicProfile.self, forKey: .publicProfile)
            self.offers = try container.decodeIfPresent([RemoteOffer].self, forKey: .offers) ?? []
            self.retrievalDocuments = try container.decodeIfPresent([ExchangeRetrievalDocument].self, forKey: .retrievalDocuments) ?? []
            self.retrievalHits = try container.decodeIfPresent([ExchangeDirectoryRetrievalHit].self, forKey: .retrievalHits) ?? []
            self.candidateOfferIDsFromDocs = try container.decodeIfPresent([String].self, forKey: .candidateOfferIDsFromDocs) ?? []
            self.score = try container.decodeIfPresent(Double.self, forKey: .score)

            let camelMatched = try container.decodeIfPresent([String].self, forKey: .matchedTerms) ?? []
            let snakeMatched = try container.decodeIfPresent([String].self, forKey: .matchedTermsSnake) ?? []
            if !camelMatched.isEmpty {
                self.perServerMatchedTerms = camelMatched
            } else {
                self.perServerMatchedTerms = snakeMatched
            }

            self.directoryVectorSignals =
                try container.decodeIfPresent(ExchangeDirectoryVectorSignals.self, forKey: .directoryVectorSignals)
                ?? container.decodeIfPresent(ExchangeDirectoryVectorSignals.self, forKey: .directoryVectorSignalsSnake)
        }

        init(
            nodeID: String,
            ownerNodeID: String? = nil,
            displayName: String?,
            publicKeyID: String?,
            publicProfile: RemotePublicProfile,
            offers: [RemoteOffer] = [],
            retrievalDocuments: [ExchangeRetrievalDocument] = [],
            retrievalHits: [ExchangeDirectoryRetrievalHit] = [],
            candidateOfferIDsFromDocs: [String] = [],
            score: Double? = nil,
            perServerMatchedTerms: [String] = [],
            directoryVectorSignals: ExchangeDirectoryVectorSignals? = nil
        ) {
            self.nodeID = nodeID
            self.ownerNodeID = ownerNodeID
            self.displayName = displayName
            self.publicKeyID = publicKeyID
            self.publicProfile = publicProfile
            self.offers = offers
            self.retrievalDocuments = retrievalDocuments
            self.retrievalHits = retrievalHits
            self.candidateOfferIDsFromDocs = candidateOfferIDsFromDocs
            self.score = score
            self.perServerMatchedTerms = perServerMatchedTerms
            self.directoryVectorSignals = directoryVectorSignals
        }

        var resolvedOwnerNodeID: String {
            ownerNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? nodeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? publicProfile.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? offers.compactMap { $0.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }.first
                ?? ""
        }
    }

    struct RemotePublicProfile: Decodable {
        let id: String
        let nodeID: String?
        let displayName: String?
        let headline: String?
        let summary: String?
        let visibility: String
        let availability: String
        let interests: [String]
        let offers: [String]
        let openTo: [String]
        let excludedTopics: [String]
        let activityTags: [String]
        let regionTags: [String]
        let canonicalRegionIDs: [String]
        let parentRegionIDs: [String]
        let regionAliases: [String]
        let semantic: [String: [String]]
        let reachability: RemoteReachability
        let approach: RemoteApproach
        let primaryImageURL: String?
        let publicSupporterPresentation: ExchangeSupporterPresentation?

        enum CodingKeys: String, CodingKey {
            case id
            case nodeID
            case nodeId
            case displayName
            case headline
            case summary
            case visibility
            case availability
            case interests
            case offers
            case openTo
            case excludedTopics
            case activityTags
            case regionTags
            case canonicalRegionIDs
            case canonical_region_ids
            case parentRegionIDs
            case parent_region_ids
            case regionAliases
            case region_aliases
            case semantic
            case reachability
            case approach
            case primaryImageURL
            case publicSupporterPresentation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.id = try container.decode(String.self, forKey: .id)
            self.nodeID =
                try container.decodeIfPresent(String.self, forKey: .nodeID)
                ?? container.decodeIfPresent(String.self, forKey: .nodeId)
            self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            self.headline = try container.decodeIfPresent(String.self, forKey: .headline)
            self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
            self.visibility = try container.decode(String.self, forKey: .visibility)
            self.availability = try container.decode(String.self, forKey: .availability)
            self.interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
            self.offers = try container.decodeIfPresent([String].self, forKey: .offers) ?? []
            self.openTo = try container.decodeIfPresent([String].self, forKey: .openTo) ?? []
            self.excludedTopics = try container.decodeIfPresent([String].self, forKey: .excludedTopics) ?? []
            self.activityTags = try container.decodeIfPresent([String].self, forKey: .activityTags) ?? []
            self.regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
            if let ids = try container.decodeIfPresent([String].self, forKey: .canonicalRegionIDs) {
                self.canonicalRegionIDs = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .canonical_region_ids) {
                self.canonicalRegionIDs = ids
            } else {
                self.canonicalRegionIDs = []
            }
            if let ids = try container.decodeIfPresent([String].self, forKey: .parentRegionIDs) {
                self.parentRegionIDs = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .parent_region_ids) {
                self.parentRegionIDs = ids
            } else {
                self.parentRegionIDs = []
            }
            if let ids = try container.decodeIfPresent([String].self, forKey: .regionAliases) {
                self.regionAliases = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .region_aliases) {
                self.regionAliases = ids
            } else {
                self.regionAliases = []
            }
            self.semantic = try container.decodeIfPresent([String: [String]].self, forKey: .semantic) ?? [:]
            self.reachability = try container.decodeIfPresent(RemoteReachability.self, forKey: .reachability) ?? .init()
            self.approach = try container.decodeIfPresent(RemoteApproach.self, forKey: .approach) ?? .init()
            self.primaryImageURL = try container.decodeIfPresent(String.self, forKey: .primaryImageURL)
            self.publicSupporterPresentation = try container.decodeIfPresent(
                ExchangeSupporterPresentation.self,
                forKey: .publicSupporterPresentation
            )
        }
    }
    
    struct RemoteOffer: Decodable {
        let id: String
        let nodeID: String?
        let publicProfileID: String?
        let title: String
        let summary: String?
        let category: String?
        let tags: [String]
        let regionTags: [String]
        let canonicalRegionIDs: [String]
        let parentRegionIDs: [String]
        let regionAliases: [String]
        let semantic: [String: [String]]
        let fulfillment: RemoteFulfillment
        let status: String?
        let visibility: String?
        let primaryImageURL: String?
        let galleryImageURLs: [String]
        let commercialFacts: ExchangeOffer.CommercialFacts?
        let contactInfo: ExchangeOffer.ContactInfo?
        let serviceAreas: [ExchangeDeclaredServiceArea]

        enum CodingKeys: String, CodingKey {
            case id
            case nodeID
            case nodeId
            case publicProfileID
            case publicProfileId
            case title
            case summary
            case category
            case tags
            case regionTags
            case region_tags = "region_tags"
            case canonicalRegionIDs
            case canonical_region_ids
            case parentRegionIDs
            case parent_region_ids
            case regionAliases
            case region_aliases
            case semantic
            case fulfillment
            case status
            case visibility
            case primaryImageURL
            case galleryImageURLs
            case gallery_image_urls
            case commercialFacts
            case contactInfo
            case serviceAreas
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.nodeID =
                try container.decodeIfPresent(String.self, forKey: .nodeID)
                ?? container.decodeIfPresent(String.self, forKey: .nodeId)
            self.publicProfileID =
                try container.decodeIfPresent(String.self, forKey: .publicProfileID)
                ?? container.decodeIfPresent(String.self, forKey: .publicProfileId)
            self.title = try container.decode(String.self, forKey: .title)
            self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
            self.category = try container.decodeIfPresent(String.self, forKey: .category)
            self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            self.regionTags =
                try container.decodeIfPresent([String].self, forKey: .regionTags)
                ?? container.decodeIfPresent([String].self, forKey: .region_tags)
                ?? []
            if let ids = try container.decodeIfPresent([String].self, forKey: .canonicalRegionIDs) {
                self.canonicalRegionIDs = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .canonical_region_ids) {
                self.canonicalRegionIDs = ids
            } else {
                self.canonicalRegionIDs = []
            }
            if let ids = try container.decodeIfPresent([String].self, forKey: .parentRegionIDs) {
                self.parentRegionIDs = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .parent_region_ids) {
                self.parentRegionIDs = ids
            } else {
                self.parentRegionIDs = []
            }
            if let ids = try container.decodeIfPresent([String].self, forKey: .regionAliases) {
                self.regionAliases = ids
            } else if let ids = try container.decodeIfPresent([String].self, forKey: .region_aliases) {
                self.regionAliases = ids
            } else {
                self.regionAliases = []
            }
            self.semantic = try container.decodeIfPresent([String: [String]].self, forKey: .semantic) ?? [:]
            self.fulfillment = try container.decodeIfPresent(RemoteFulfillment.self, forKey: .fulfillment) ?? .init()
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
            self.primaryImageURL = try container.decodeIfPresent(String.self, forKey: .primaryImageURL)
            if let g = try container.decodeIfPresent([String].self, forKey: .galleryImageURLs) {
                self.galleryImageURLs = g
            } else if let g2 = try container.decodeIfPresent([String].self, forKey: .gallery_image_urls) {
                self.galleryImageURLs = g2
            } else {
                self.galleryImageURLs = []
            }
            self.commercialFacts = try container.decodeIfPresent(
                ExchangeOffer.CommercialFacts.self,
                forKey: .commercialFacts
            )
            self.contactInfo = try container.decodeIfPresent(
                ExchangeOffer.ContactInfo.self,
                forKey: .contactInfo
            )
            self.serviceAreas = try container.decodeIfPresent(
                [ExchangeDeclaredServiceArea].self,
                forKey: .serviceAreas
            ) ?? []
        }
    }

    struct RemoteFulfillment: Decodable {
        let pricingMode: String?
        let commitmentMode: String?
        let remoteFriendly: Bool
        let leadTime: String?
        let capacity: String?

        init(
            pricingMode: String? = "undisclosed",
            commitmentMode: String? = "exploratory",
            remoteFriendly: Bool = true,
            leadTime: String? = nil,
            capacity: String? = nil
        ) {
            self.pricingMode = pricingMode
            self.commitmentMode = commitmentMode
            self.remoteFriendly = remoteFriendly
            self.leadTime = leadTime
            self.capacity = capacity
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)

            let pricingMode = Self.decodeString(
                from: container,
                keys: ["pricingMode", "pricing_mode", "pricing mode"]
            )

            let commitmentMode = Self.decodeString(
                from: container,
                keys: ["commitmentMode", "commitment_mode", "commitment mode"]
            )

            let remoteFriendly = Self.decodeBool(
                from: container,
                keys: ["remoteFriendly", "remote_friendly", "remote friendly"],
                defaultValue: true
            )

            let leadTime = Self.decodeString(
                from: container,
                keys: ["leadTime", "lead_time", "lead time"]
            )

            let capacity = Self.decodeString(
                from: container,
                keys: ["capacity", "capacityNote", "capacity_note", "capacity note"]
            )

            self.init(
                pricingMode: pricingMode ?? "undisclosed",
                commitmentMode: commitmentMode ?? "exploratory",
                remoteFriendly: remoteFriendly,
                leadTime: leadTime,
                capacity: capacity
            )
        }

        private static func decodeString(
            from container: KeyedDecodingContainer<AnyCodingKey>,
            keys: [String]
        ) -> String? {
            for key in keys {
                guard let codingKey = AnyCodingKey(stringValue: key) else { continue }

                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }

            return nil
        }

        private static func decodeBool(
            from container: KeyedDecodingContainer<AnyCodingKey>,
            keys: [String],
            defaultValue: Bool
        ) -> Bool {
            for key in keys {
                guard let codingKey = AnyCodingKey(stringValue: key) else { continue }

                if let value = try? container.decodeIfPresent(Bool.self, forKey: codingKey) {
                    return value
                }

                if let stringValue = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                    let normalized = stringValue
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    switch normalized {
                    case "true", "yes", "1":
                        return true
                    case "false", "no", "0":
                        return false
                    default:
                        break
                    }
                }
            }

            return defaultValue
        }
    }
    struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    struct RemoteReachability: Decodable {
        let acceptingInbound: Bool
        let accessMode: String
        let disclosureCeiling: String?
        let routeableOnly: Bool?
        let intentCategoryPolicy: String?

        enum CodingKeys: String, CodingKey {
            case acceptingInbound
            case accessMode
            case disclosureCeiling
            case routeableOnly
            case intentCategoryPolicy
        }

        init(
            acceptingInbound: Bool = true,
            accessMode: String = ExchangePublicNodeProfile.ReachabilityPolicy.AccessMode.direct.rawValue,
            disclosureCeiling: String? = ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling.balanced.rawValue,
            routeableOnly: Bool? = false,
            intentCategoryPolicy: String? = ExchangePublicNodeProfile.ReachabilityPolicy.IntentCategoryPolicy.permissive.rawValue
        ) {
            self.acceptingInbound = acceptingInbound
            self.accessMode = accessMode
            self.disclosureCeiling = disclosureCeiling
            self.routeableOnly = routeableOnly
            self.intentCategoryPolicy = intentCategoryPolicy
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.acceptingInbound =
                try container.decodeIfPresent(Bool.self, forKey: .acceptingInbound) ?? true

            self.accessMode =
                try container.decodeIfPresent(String.self, forKey: .accessMode)
                ?? ExchangePublicNodeProfile.ReachabilityPolicy.AccessMode.direct.rawValue

            self.disclosureCeiling =
                try container.decodeIfPresent(String.self, forKey: .disclosureCeiling)
                ?? ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling.balanced.rawValue

            self.routeableOnly =
                try container.decodeIfPresent(Bool.self, forKey: .routeableOnly) ?? false

            self.intentCategoryPolicy =
                try container.decodeIfPresent(String.self, forKey: .intentCategoryPolicy)
                ?? ExchangePublicNodeProfile.ReachabilityPolicy.IntentCategoryPolicy.permissive.rawValue
        }
    }

    struct RemoteApproach: Decodable {
        let preferredStyle: String?
        let preferredFirstContactKinds: [String]
        let note: String?

        enum CodingKeys: String, CodingKey {
            case preferredStyle
            case preferredFirstContactKinds
            case preferredFirstContactKindsSnake = "preferred_first_contact_kinds"
            case note
        }

        init(
            preferredStyle: String? = nil,
            preferredFirstContactKinds: [String] = [],
            note: String? = nil
        ) {
            self.preferredStyle = preferredStyle
            self.preferredFirstContactKinds = preferredFirstContactKinds
            self.note = note
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.preferredStyle = try container.decodeIfPresent(String.self, forKey: .preferredStyle)
            self.preferredFirstContactKinds =
                try container.decodeIfPresent([String].self, forKey: .preferredFirstContactKinds)
                ?? container.decodeIfPresent([String].self, forKey: .preferredFirstContactKindsSnake)
                ?? []
            self.note = try container.decodeIfPresent(String.self, forKey: .note)
        }
    }

    struct RegisterNodeRequest: Encodable {
        let nodeID: String
        let displayName: String
        let publicKeyID: String?
        let publicKey: String
        let encryptionKeyID: String?
        let encryptionPublicKey: String?
        let publicProfile: ExchangeHTTPDirectoryClient.RegisterPublicProfile

        enum CodingKeys: String, CodingKey {
            case nodeID
            case displayName
            case publicKeyID
            case publicKey
            case encryptionKeyID
            case encryptionPublicKey
            case publicProfile
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(nodeID, forKey: .nodeID)
            try container.encode(displayName, forKey: .displayName)
            try container.encodeIfPresent(publicKeyID, forKey: .publicKeyID)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encodeIfPresent(encryptionKeyID, forKey: .encryptionKeyID)
            try container.encodeIfPresent(encryptionPublicKey, forKey: .encryptionPublicKey)
            try container.encode(publicProfile, forKey: .publicProfile)
        }
    }

    struct RemoteNodePublicKeysResponse: Decodable {
        let ok: Bool
        let nodeID: String
        let signingKeyID: String?
        let signingPublicKey: String?
        let encryptionKeyID: String?
        let encryptionPublicKey: String?
    }

    struct RegisterNodeResponse: Decodable {
        let ok: Bool
        let nodeID: String
        let profileID: String
    }

    struct RemoteUploadMediaResponse: Decodable {
        let ok: Bool
        let imageURL: String?
        let storageKey: String?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case imageURL
            case imageUrl
            case storageKey
            case storage_key = "storage_key"
            case note
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            self.imageURL =
                try container.decodeIfPresent(String.self, forKey: .imageURL)
                ?? container.decodeIfPresent(String.self, forKey: .imageUrl)
            self.storageKey =
                try container.decodeIfPresent(String.self, forKey: .storageKey)
                ?? container.decodeIfPresent(String.self, forKey: .storage_key)
            self.note = try container.decodeIfPresent(String.self, forKey: .note)
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
            exchDirectoryHTTPLog("POST encode failed url=\(requestURL.absoluteString) error=\(error)")
            throw ExchangeDirectoryClientError.invalidRequest(
                reason: "Failed to encode directory request body: \(error)"
            )
        }

        if requiresSignature {
            do {
                let canonicalPath = try signer.canonicalPath(for: requestURL)
                let signedHeaders = try signer.makeSignedFederationHeaders(
                    method: "POST",
                    path: canonicalPath,
                    bodyData: bodyData,
                    endpointLabel: "directory:post:\(requestURL.path)"
                )
                signer.apply(signedHeaders, to: &request)

                let bodyHashHex = ExchangeFederationRequestSigner.bodyHashHex(for: bodyData)
                let bodyPreview = String(decoding: bodyData.prefix(500), as: UTF8.self)
                exchDirectoryHTTPLog(
                    "signedRequest endpoint=directory:post:\(requestURL.path) " +
                    "method=POST canonicalPath=\(canonicalPath) " +
                    "timestamp=\(signedHeaders.timestamp) noncePrefix=\(String(signedHeaders.nonce.prefix(8))) " +
                    "bodyHashPrefix=\(String(bodyHashHex.prefix(12))) " +
                    "bodyBytes=\(bodyData.count) bodyPreview=\(bodyPreview) " +
                    "nodeID=\(signedHeaders.nodeID) publicKeyID=\(signedHeaders.publicKeyID) " +
                    "signaturePrefix=\(String(signedHeaders.signature.prefix(12)))"
                )
            } catch {
                throw ExchangeDirectoryClientError.invalidRequest(
                    reason: "Failed to sign protected directory request."
                )
            }
        }

        exchDirectoryHTTPLog("POST \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            exchDirectoryHTTPLog("POST decode failed url=\(requestURL.absoluteString) error=\(error)")
            if let responseText = String(data: data, encoding: .utf8) {
                exchDirectoryHTTPLog("POST decode raw body=\(responseText)")
            }
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Failed to decode directory response: \(error)"
            )
        }
    }

    func url(for path: String) -> URL {
        if path.hasPrefix("/") {
            return baseURL.appendingPathComponent(String(path.dropFirst()))
        }
        return baseURL.appendingPathComponent(path)
    }

    func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            exchDirectoryHTTPLog("validateHTTP failed reason=non_http_response")
            throw ExchangeDirectoryClientError.backendFailure(
                reason: "Non-HTTP response from federation server."
            )
        }

        guard (200...299).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let message = FederationHTTPErrorMessage.userFacingReason(data: data, fallback: rawBody)
            exchDirectoryHTTPLog("validateHTTP failed status=\(http.statusCode) body=\(message)")

            switch http.statusCode {
            case 400:
                throw ExchangeDirectoryClientError.invalidRequest(reason: message)
            case 429:
                if FederationHTTPErrorMessage.isQuotaOrRateLimitResponse(data: data, statusCode: http.statusCode) {
                    let retryAfter = FederationHTTPErrorMessage.resolvedRateLimitRetryAfterSeconds(
                        data: data,
                        http: http
                    )
                    throw ExchangeDirectoryClientError.rateLimited(
                        reason: message,
                        retryAfterSeconds: retryAfter
                    )
                }
                throw ExchangeDirectoryClientError.backendFailure(reason: message)
            case 500...599:
                throw ExchangeDirectoryClientError.unavailable(reason: message)
            default:
                throw ExchangeDirectoryClientError.backendFailure(reason: message)
            }
        }
    }

    func mapPublicProfile(
        nodeID: String,
        displayName: String?,
        remote: RemotePublicProfile
    ) -> ExchangePublicNodeProfile {
        let visibility = ExchangePublicNodeProfile.Visibility(rawValue: remote.visibility) ?? .discoverable
        let availability = ExchangePublicNodeProfile.Availability(rawValue: remote.availability) ?? .open
        let accessMode = ExchangePublicNodeProfile.ReachabilityPolicy.AccessMode(rawValue: remote.reachability.accessMode) ?? .direct
        let disclosureCeiling = ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling(
            rawValue: remote.reachability.disclosureCeiling ?? ""
        ) ?? .balanced

        let intentCategoryPolicy = ExchangePublicNodeProfile.ReachabilityPolicy.IntentCategoryPolicy(
            rawValue: remote.reachability.intentCategoryPolicy ?? ""
        ) ?? .permissive

        let semantic = ExchangePublicNodeProfile.SemanticSurface(
            domains: normalizedTags(remote.semantic["domains"] ?? remote.semantic["tags"] ?? []),
            intentKinds: normalizedTags(remote.semantic["intentKinds"] ?? remote.semantic["intent_kinds"] ?? []),
            audienceKinds: mapAudienceKinds(remote.semantic["audienceKinds"] ?? remote.semantic["audience_kinds"] ?? []),
            fulfillmentModes: mapFulfillmentModes(remote.semantic["fulfillmentModes"] ?? remote.semantic["fulfillment_modes"] ?? []),
            notes: nil
        )

        let reachability = ExchangePublicNodeProfile.ReachabilityPolicy(
            accessMode: accessMode,
            acceptingInbound: remote.reachability.acceptingInbound,
            allowedModes: [],
            allowedIntentKinds: [],
            allowedAudienceKinds: [],
            minimumTrustLevel: nil,
            requiresCategoryMatch: false,
            requiresMutualFit: false,
            intentCategoryPolicy: intentCategoryPolicy,
            disclosureCeiling: disclosureCeiling,
            routeableOnly: remote.reachability.routeableOnly ?? false
        )

        let preferredStyle = remote.approach.preferredStyle.flatMap {
            ExchangePublicNodeProfile.ApproachPreferences.Style(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let preferredKinds = remote.approach.preferredFirstContactKinds.compactMap {
            ExchangePublicNodeProfile.ApproachPreferences.FirstContactKind(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let approach = ExchangePublicNodeProfile.ApproachPreferences(
            preferredStyle: preferredStyle,
            preferredFirstContactKinds: preferredKinds,
            note: remote.approach.note
        )

        let profile = ExchangePublicNodeProfile(
            id: remote.id,
            nodeID: nodeID,
            displayName: displayName,
            headline: remote.headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            summary: remote.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            visibility: visibility,
            interests: normalizedTags(remote.interests),
            offers: normalizedTags(remote.offers),
            openTo: normalizedTags(remote.openTo),
            excludedTopics: normalizedTags(remote.excludedTopics),
            activityTags: normalizedTags(remote.activityTags),
            regionTags: normalizedTags(remote.regionTags),
            canonicalRegionIDs: normalizedTags(remote.canonicalRegionIDs),
            parentRegionIDs: normalizedTags(remote.parentRegionIDs),
            regionAliases: normalizedTags(remote.regionAliases),
            semantic: semantic,
            reachability: reachability,
            approach: approach,
            availability: availability,
            primaryImageURL: remote.primaryImageURL,
            publicSupporterPresentation: remote.publicSupporterPresentation
        )

        #if DEBUG
        GuardianCrownDebugLog.log(
            "RemoteMap",
            "nodeID=\(nodeID) profileID=\(remote.id) " +
            "presentation=\(GuardianCrownDebugLog.presentationLabel(remote.publicSupporterPresentation))"
        )
        #endif

        return profile
    }
    
    func mapSemanticProfile(
        _ semantic: ExchangePublicNodeProfile.SemanticSurface,
        remoteOffers: [RemoteOffer]
    ) -> ExchangeCounterparty.SemanticProfile {
        let offerDomains = remoteOffers.flatMap { $0.semantic["domains"] ?? [] }
        let offerServiceKinds = remoteOffers.flatMap { $0.semantic["serviceKinds"] ?? [] }
        let offerAudienceKinds = remoteOffers.flatMap { $0.semantic["audienceKinds"] ?? [] }
        let offerRegions = remoteOffers.flatMap { $0.regionTags }

        return ExchangeCounterparty.SemanticProfile(
            activities: [],
            serviceCategories: normalizedTags(semantic.domains + offerDomains + offerServiceKinds),
            productCategories: [],
            marketTags: normalizedTags(semantic.intentKinds + offerAudienceKinds),
            placeTags: normalizedTags(offerRegions)
        )
    }

    func inferredKind(
        from publicProfile: ExchangePublicNodeProfile,
        remoteOffers: [RemoteOffer]
    ) -> ExchangeCounterparty.Kind {
        let audienceKinds = Set(publicProfile.semantic.audienceKinds.map(\.rawValue))
        let offerAudienceKinds = remoteOffers.flatMap { $0.semantic["audienceKinds"] ?? [] }
        let offerServiceKinds = remoteOffers.flatMap { $0.semantic["serviceKinds"] ?? [] }

        let all = Set(
            normalizedTags(
                publicProfile.openTo +
                publicProfile.offers +
                publicProfile.interests +
                publicProfile.activityTags +
                publicProfile.semantic.domains +
                publicProfile.semantic.intentKinds +
                Array(audienceKinds) +
                offerAudienceKinds +
                offerServiceKinds
            )
        )

        if all.contains("person") {
            return .person
        }
        if all.contains("provider") || all.contains("service") {
            return .provider
        }
        if all.contains("business") || all.contains("company") {
            return .business
        }
        if all.contains("organization") {
            return .organization
        }
        if all.contains("group") || all.contains("community") {
            return .group
        }
        if all.contains("secretarynode") || all.contains("secretary_node") || all.contains("secretary") || all.contains("node") {
            return .secretaryNode
        }

        return .secretaryNode
    }

    func mapCounterpartyStatus(
        _ availability: ExchangePublicNodeProfile.Availability
    ) -> ExchangeCounterparty.Status {
        switch availability {
        case .open:
            return .active
        case .limited:
            return .paused
        case .paused, .unavailable:
            return .unavailable
        }
    }

    func mapAudienceKinds(
        _ values: [String]
    ) -> [ExchangePublicNodeProfile.SemanticSurface.AudienceKind] {
        values.compactMap {
            ExchangePublicNodeProfile.SemanticSurface.AudienceKind(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func mapFulfillmentModes(
        _ values: [String]
    ) -> [ExchangePublicNodeProfile.SemanticSurface.FulfillmentMode] {
        values.compactMap {
            ExchangePublicNodeProfile.SemanticSurface.FulfillmentMode(
                rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func normalizedTags(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    func normalizedQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }
}

#if DEBUG
public enum ExchangeHTTPDirectorySearchCapture: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _lastRetrievalResponseMode: String?
    nonisolated(unsafe) private static var _lastMatchCount: Int = 0
    nonisolated(unsafe) private static var _lastMatches: [ExchangeDirectoryMatch] = []

    public static var lastRetrievalResponseMode: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastRetrievalResponseMode
    }

    public static var lastMatches: [ExchangeDirectoryMatch] {
        lock.lock()
        defer { lock.unlock() }
        return _lastMatches
    }

    public static func record(
        retrievalResponseMode: String?,
        matchCount: Int,
        matches: [ExchangeDirectoryMatch] = []
    ) {
        lock.lock()
        _lastRetrievalResponseMode = retrievalResponseMode
        _lastMatchCount = matchCount
        if !matches.isEmpty {
            _lastMatches = matches
        }
        lock.unlock()
    }
}
#endif

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
