import Foundation

/// Runs async compose racing a timeout; returns `nil` if the timeout wins first or compose fails before success.
public enum ExchangeRequesterClosureComposeSupport {
    private enum Race: Sendable {
        case composed(ExchangeRequesterClosureComposedCopy?)
        case timedOut
    }

    public static func composeWithTimeout(
        composer: any ExchangeRequesterClosureComposing,
        input: ExchangeRequesterClosureComposerInput,
        timeoutSeconds: Double = 2.5
    ) async -> ExchangeRequesterClosureComposedCopy? {
        await withTaskGroup(of: Race.self) { group in
            group.addTask {
                .composed(try? await composer.compose(input))
            }
            group.addTask {
                let ns = UInt64(max(0.05, timeoutSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                return .timedOut
            }
            for await event in group {
                switch event {
                case .timedOut:
                    group.cancelAll()
                    return nil
                case .composed(let copy):
                    if let copy {
                        group.cancelAll()
                        return copy
                    }
                }
            }
            return nil
        }
    }
}
