import Foundation

#if DEBUG
@inline(__always)
private func exchDMAttachmentLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeDMAttachment] \(message())")
}
#else
@inline(__always)
private func exchDMAttachmentLog(_ message: @autoclosure () -> String) {}
#endif

public enum ExchangeDMAttachmentClientError: Error, Sendable, Hashable {
    case invalidRequest(reason: String)
    case transportFailure(reason: String)
    case backendFailure(reason: String)
    case encryptedDecryptFailed(reason: String)
}

/// Signed upload/download for private DM attachments (`/v1/dm-attachments/*`).
public struct ExchangeHTTPDMAttachmentClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let signer: ExchangeFederationRequestSigner
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.signer = ExchangeFederationRequestSigner()
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func uploadDMAttachment(
        fileData: Data,
        filename: String,
        mimeType: String,
        recipientNodeID: String,
        encrypted: Bool = false
    ) async throws -> DirectMessageAttachmentDescriptor {
        let trimmedRecipient = recipientNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRecipient.isEmpty else {
            throw ExchangeDMAttachmentClientError.invalidRequest(reason: "Missing recipient node ID.")
        }
        guard !fileData.isEmpty else {
            throw ExchangeDMAttachmentClientError.invalidRequest(reason: "Attachment file is empty.")
        }

        let trimmedMime: String
        let trimmedName: String
        if encrypted {
            trimmedMime = Self.encryptedUploadMIME
            trimmedName = Self.encryptedUploadFilename
        } else {
            trimmedMime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmedMime.isEmpty else {
                throw ExchangeDMAttachmentClientError.invalidRequest(reason: "Missing MIME type.")
            }
            trimmedName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw ExchangeDMAttachmentClientError.invalidRequest(reason: "Missing filename.")
            }
        }

        let material = try signer.currentIdentity()
        let boundary = "DMAttachmentBoundary-\(UUID().uuidString)"
        let requestURL = url(for: "/v1/dm-attachments/upload")
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

        appendField("nodeID", material.nodeID)
        appendField("recipientNodeID", trimmedRecipient)
        appendField("mimeType", trimmedMime)
        appendField("filename", trimmedName)
        if encrypted {
            appendField("encrypted", "true")
        }

        let safeFilename = (trimmedName as NSString).lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(trimmedMime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        let canonicalPath = try signer.canonicalPath(for: requestURL)
        let signedHeaders = try signer.makeSignedFederationHeaders(
            method: "POST",
            path: canonicalPath,
            bodyData: body,
            endpointLabel: "dm-attachment:post:upload"
        )
        signer.apply(signedHeaders, to: &request)

        exchDMAttachmentLog(
            "upload start recipient=\(trimmedRecipient) bytes=\(fileData.count) encrypted=\(encrypted) mime=\(trimmedMime)"
        )

        let (responseData, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: responseData)

        let decoded: UploadResponse
        do {
            decoded = try decoder.decode(UploadResponse.self, from: responseData)
        } catch {
            throw ExchangeDMAttachmentClientError.backendFailure(
                reason: "DM attachment upload returned an unreadable response."
            )
        }

        guard decoded.ok == true,
              let storageKey = decoded.storageKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
              let downloadPath = decoded.downloadPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            throw ExchangeDMAttachmentClientError.backendFailure(
                reason: decoded.error ?? "DM attachment upload was not accepted."
            )
        }

        let descriptor = DirectMessageAttachmentDescriptor(
            attachmentID: UUID(),
            filename: encrypted ? trimmedName : (decoded.filename ?? trimmedName),
            mimeType: encrypted ? trimmedMime : (decoded.mimeType ?? trimmedMime),
            byteSize: decoded.byteSize ?? fileData.count,
            storageKey: storageKey,
            downloadPath: downloadPath,
            sha256: decoded.sha256,
            uploadedAt: Date(),
            accessScope: .dmPrivate
        )

        exchDMAttachmentLog(
            "upload done encrypted=\(encrypted) storageKeyPrefix=\(String(storageKey.prefix(12))) bytes=\(descriptor.byteSize)"
        )
        return descriptor
    }

    private static let encryptedUploadMIME = "application/vnd.unify.encrypted-attachment"
    private static let encryptedUploadFilename = "encrypted.bin"

    public func downloadDMAttachment(
        storageKey: String,
        downloadPath: String?,
        filename: String
    ) async throws -> URL {
        try await downloadDMAttachment(
            descriptor: DirectMessageAttachmentDescriptor(
                filename: filename,
                mimeType: "application/octet-stream",
                byteSize: 0,
                storageKey: storageKey,
                downloadPath: downloadPath ?? ""
            )
        )
    }

    public func downloadDMAttachment(
        descriptor: DirectMessageAttachmentDescriptor
    ) async throws -> URL {
        let key = descriptor.storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ExchangeDMAttachmentClientError.invalidRequest(reason: "Missing storage key.")
        }

        let filename = descriptor.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if DirectMessageAttachmentCache.isCached(storageKey: key, filename: filename),
           let cached = try? DirectMessageAttachmentCache.cachedFileURL(storageKey: key, filename: filename) {
            return cached
        }

        let path = normalizedDownloadPath(downloadPath: descriptor.downloadPath.nilIfBlank, storageKey: key)
        let requestURL = url(for: path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let canonicalPath = try signer.canonicalPath(for: requestURL)
        let signedHeaders = try signer.makeSignedFederationHeaders(
            method: "GET",
            path: canonicalPath,
            bodyData: Data("{}".utf8),
            endpointLabel: "dm-attachment:get"
        )
        signer.apply(signedHeaders, to: &request)

        exchDMAttachmentLog("download start storageKeyPrefix=\(String(key.prefix(12))) encrypted=\(descriptor.isEncrypted)")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        let bytesToCache: Data
        if let encryption = descriptor.encryption {
            let localEncryptionMaterial: NodeEncryptionMaterial
            do {
                localEncryptionMaterial = try NodeIdentityVault.shared.loadOrCreateEncryptionMaterial()
            } catch {
                ExchangeFederationAttachmentE2EE.logDownload(
                    encrypted: true,
                    decrypted: false,
                    reason: "missingLocalEncryptionKey"
                )
                throw ExchangeDMAttachmentClientError.encryptedDecryptFailed(reason: "missingLocalEncryptionKey")
            }

            do {
                bytesToCache = try ExchangeAttachmentOpener().open(
                    encryptedFileData: data,
                    encryption: encryption,
                    localEncryptionMaterial: localEncryptionMaterial
                )
                ExchangeFederationAttachmentE2EE.logDownload(
                    encrypted: true,
                    decrypted: true,
                    reason: nil
                )
            } catch {
                let reason = ExchangeFederationAttachmentE2EE.downloadFailureReason(error)
                ExchangeFederationAttachmentE2EE.logDownload(
                    encrypted: true,
                    decrypted: false,
                    reason: reason
                )
                throw ExchangeDMAttachmentClientError.encryptedDecryptFailed(reason: reason)
            }
        } else {
            bytesToCache = data
        }

        let cached = try DirectMessageAttachmentCache.write(
            data: bytesToCache,
            storageKey: key,
            filename: filename
        )
        exchDMAttachmentLog("download done bytes=\(bytesToCache.count) cached=\(cached.lastPathComponent)")
        return cached
    }

    private func normalizedDownloadPath(downloadPath: String?, storageKey: String) -> String {
        if let trimmed = downloadPath?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            if trimmed.hasPrefix("/") { return trimmed }
            return "/\(trimmed)"
        }
        let encoded = storageKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storageKey
        return "/v1/dm-attachments/\(encoded)"
    }

    private func url(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return baseURL.appendingPathComponent(String(normalized.dropFirst()))
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeDMAttachmentClientError.transportFailure(reason: "Invalid HTTP response.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let fallback = "HTTP \(http.statusCode)"
            let message = FederationHTTPErrorMessage.userFacingReason(data: data, fallback: fallback)
            throw ExchangeDMAttachmentClientError.backendFailure(reason: message)
        }
    }

    private struct UploadResponse: Decodable {
        let ok: Bool?
        let error: String?
        let storageKey: String?
        let filename: String?
        let mimeType: String?
        let byteSize: Int?
        let sha256: String?
        let downloadPath: String?
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
