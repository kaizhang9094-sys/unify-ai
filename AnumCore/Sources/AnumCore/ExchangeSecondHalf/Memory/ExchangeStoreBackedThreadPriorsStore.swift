import Foundation

/// Durable `ExchangeThreadPriorsStore` backed by `ExchangeStore` thread metadata.
public actor ExchangeStoreBackedThreadPriorsStore: ExchangeThreadPriorsStore {
    private let exchangeStore: any ExchangeStore
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(exchangeStore: any ExchangeStore) {
        self.exchangeStore = exchangeStore
    }

    public func loadPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadPriors? {
        guard let thread = try await exchangeStore.fetchThread(id: threadID) else { return nil }
        guard
            let raw = thread.metadata[metadataKey(role: role)],
            let data = Data(base64Encoded: raw)
        else {
            return nil
        }
        return try? decoder.decode(ExchangeThreadPriors.self, from: data)
    }

    public func savePriors(
        _ priors: ExchangeThreadPriors,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        guard var thread = try await exchangeStore.fetchThread(id: threadID) else { return }
        let data = try encoder.encode(priors)
        thread.metadata[metadataKey(role: role)] = data.base64EncodedString()
        thread.updatedAt = Date()
        try await exchangeStore.updateThread(thread)
    }

    public func clearPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        guard var thread = try await exchangeStore.fetchThread(id: threadID) else { return }
        thread.metadata.removeValue(forKey: metadataKey(role: role))
        thread.updatedAt = Date()
        try await exchangeStore.updateThread(thread)
    }

    private func metadataKey(role: ExchangeSecondHalfRole) -> String {
        "second_half.priors.\(role.rawValue)"
    }
}
