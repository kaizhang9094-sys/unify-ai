import Foundation

public protocol ExchangeClock: Sendable {
    func now() -> Date
}

public struct SystemExchangeClock: ExchangeClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public struct FixedExchangeClock: ExchangeClock {
    private let fixedDate: Date

    public init(_ fixedDate: Date) {
        self.fixedDate = fixedDate
    }

    public func now() -> Date {
        fixedDate
    }
}
