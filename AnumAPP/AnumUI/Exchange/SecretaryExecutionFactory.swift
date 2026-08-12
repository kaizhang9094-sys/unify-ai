import Foundation
import AnumCore

enum SecretaryExecutionFactory {
    static func fromInboxItem(_ item: ExchangeModels.InboxItem) -> SecretaryExecutionDisplay? {
        SecretaryProjectionEngine.executionDisplay(for: item)
    }
}
