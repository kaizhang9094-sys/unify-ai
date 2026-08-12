import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfStoreAdapterLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfStoreAdapter] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfStoreAdapterLog(_ message: @autoclosure () -> String) {}
#endif

/// Adapter to existing or future store layers.
///
/// This lets the new second-half code read/write its own durable shapes without
/// redefining all persistence at once.
public protocol ExchangeSecondHalfStoreAdapter: Sendable {
    func loadSecondHalfRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecondHalfRecord?

    func saveSecondHalfRecord(
        _ record: ExchangeSecondHalfRecord
    ) async throws

    func loadStanceRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadStanceRecord?

    func saveStanceRecord(
        _ record: ExchangeThreadStanceRecord
    ) async throws

    func loadDecisionFrameRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeDecisionFrameRecord?

    func saveDecisionFrameRecord(
        _ record: ExchangeDecisionFrameRecord
    ) async throws

    func loadDeltaRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadDeltaRecord?

    func saveDeltaRecord(
        _ record: ExchangeThreadDeltaRecord
    ) async throws
}

/// Default in-memory adapter so the second half can run end-to-end before
/// a real backing store is wired in.
public actor ExchangeDefaultSecondHalfStoreAdapter: ExchangeSecondHalfStoreAdapter {
    private struct Key: Hashable, Sendable {
        let threadID: UUID
        let role: ExchangeSecondHalfRole
    }

    private var secondHalfRecords: [Key: ExchangeSecondHalfRecord] = [:]
    private var stanceRecords: [Key: ExchangeThreadStanceRecord] = [:]
    private var decisionFrameRecords: [Key: ExchangeDecisionFrameRecord] = [:]
    private var deltaRecords: [Key: ExchangeThreadDeltaRecord] = [:]
    private let exchangeStore: (any ExchangeStore)?

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

    public init(exchangeStore: (any ExchangeStore)? = nil) {
        self.exchangeStore = exchangeStore
    }

    public func loadSecondHalfRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecondHalfRecord? {
        if let persisted: ExchangeSecondHalfRecord = try await loadPersisted(
            key: metadataKey(kind: "record", role: role),
            threadID: threadID
        ) {
            return persisted
        }
        return secondHalfRecords[Key(threadID: threadID, role: role)]
    }

    public func saveSecondHalfRecord(
        _ record: ExchangeSecondHalfRecord
    ) async throws {
        exchSecondHalfStoreAdapterLog(
            "saveSecondHalfRecord thread=\(record.threadID.uuidString) state=\(record.state.rawValue)"
        )
        try await persist(record, key: metadataKey(kind: "record", role: record.role), threadID: record.threadID)
        secondHalfRecords[Key(threadID: record.threadID, role: record.role)] = record
    }

    public func loadStanceRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadStanceRecord? {
        if let persisted: ExchangeThreadStanceRecord = try await loadPersisted(
            key: metadataKey(kind: "stance", role: role),
            threadID: threadID
        ) {
            return persisted
        }
        return stanceRecords[Key(threadID: threadID, role: role)]
    }

    public func saveStanceRecord(
        _ record: ExchangeThreadStanceRecord
    ) async throws {
        try await persist(record, key: metadataKey(kind: "stance", role: record.role), threadID: record.threadID)
        stanceRecords[Key(threadID: record.threadID, role: record.role)] = record
    }

    public func loadDecisionFrameRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeDecisionFrameRecord? {
        if let persisted: ExchangeDecisionFrameRecord = try await loadPersisted(
            key: metadataKey(kind: "frame", role: role),
            threadID: threadID
        ) {
            return persisted
        }
        return decisionFrameRecords[Key(threadID: threadID, role: role)]
    }

    public func saveDecisionFrameRecord(
        _ record: ExchangeDecisionFrameRecord
    ) async throws {
        try await persist(record, key: metadataKey(kind: "frame", role: record.role), threadID: record.threadID)
        decisionFrameRecords[Key(threadID: record.threadID, role: record.role)] = record
    }

    public func loadDeltaRecord(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadDeltaRecord? {
        if let persisted: ExchangeThreadDeltaRecord = try await loadPersisted(
            key: metadataKey(kind: "delta", role: role),
            threadID: threadID
        ) {
            return persisted
        }
        return deltaRecords[Key(threadID: threadID, role: role)]
    }

    public func saveDeltaRecord(
        _ record: ExchangeThreadDeltaRecord
    ) async throws {
        try await persist(record, key: metadataKey(kind: "delta", role: record.role), threadID: record.threadID)
        deltaRecords[Key(threadID: record.threadID, role: record.role)] = record
    }

    private func metadataKey(kind: String, role: ExchangeSecondHalfRole) -> String {
        "second_half.\(kind).\(role.rawValue)"
    }

    private func persist<T: Codable>(
        _ value: T,
        key: String,
        threadID: UUID
    ) async throws {
        guard let exchangeStore else { return }
        guard var thread = try await exchangeStore.fetchThread(id: threadID) else { return }
        let data = try encoder.encode(value)
        thread.metadata[key] = data.base64EncodedString()
        thread.updatedAt = Date()
        try await exchangeStore.updateThread(thread)
    }

    private func loadPersisted<T: Codable>(
        key: String,
        threadID: UUID
    ) async throws -> T? {
        guard let exchangeStore else { return nil }
        guard let thread = try await exchangeStore.fetchThread(id: threadID) else { return nil }
        guard let raw = thread.metadata[key], let data = Data(base64Encoded: raw) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            exchSecondHalfStoreAdapterLog(
                "loadPersisted decode_failed | key=\(key) | thread=\(threadID.uuidString) | type=\(String(describing: T.self)) | error=\(error)"
            )
            #endif
            return nil
        }
    }
}
