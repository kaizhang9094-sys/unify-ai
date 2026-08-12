import Foundation

public protocol ExchangeSyncStateStore: Sendable {
    func fetchSyncState(id: String) async throws -> ExchangeSyncState?
    func saveSyncState(_ state: ExchangeSyncState) async throws
}
