import Foundation

/// Per-thread role for the local node.
///
/// A node is not globally a buyer or seller.
/// It is a requester in some threads and a provider in others.
public enum ExchangeSecondHalfRole: String, Codable, CaseIterable, Hashable, Sendable {
    case requester
    case provider
}

public extension ExchangeSecondHalfRole {
    var displayTitle: String {
        switch self {
        case .requester: return "Requester"
        case .provider: return "Provider"
        }
    }

    var counterparty: ExchangeSecondHalfRole {
        switch self {
        case .requester: return .provider
        case .provider: return .requester
        }
    }

    var isRequester: Bool {
        self == .requester
    }

    var isProvider: Bool {
        self == .provider
    }
}
