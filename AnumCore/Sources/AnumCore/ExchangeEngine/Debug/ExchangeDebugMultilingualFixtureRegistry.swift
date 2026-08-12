import Foundation

#if DEBUG

/// DEBUG-only overlay registry for multilingual retrieval E2E smoke fixtures.
///
/// Injected directory matches are merged into federation directory search responses so hybrid
/// retrieval can project known local fixtures without a separate publish path.
public enum ExchangeDebugMultilingualFixtureRegistry: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _matches: [ExchangeDirectoryMatch] = []

    public static func setMatches(_ matches: [ExchangeDirectoryMatch]) {
        lock.lock()
        defer { lock.unlock() }
        _matches = matches
    }

    public static func currentMatches() -> [ExchangeDirectoryMatch] {
        lock.lock()
        defer { lock.unlock() }
        return _matches
    }

    public static func clear() {
        setMatches([])
    }

    public static func mergeOverlay(into federationMatches: [ExchangeDirectoryMatch]) -> [ExchangeDirectoryMatch] {
        let overlay = currentMatches()
        guard !overlay.isEmpty else { return federationMatches }

        var seen = Set(federationMatches.map(\.id))
        var merged = overlay
        merged.reserveCapacity(overlay.count + federationMatches.count)
        for match in federationMatches where !seen.contains(match.id) {
            merged.append(match)
            seen.insert(match.id)
        }
        return merged
    }
}

#endif
