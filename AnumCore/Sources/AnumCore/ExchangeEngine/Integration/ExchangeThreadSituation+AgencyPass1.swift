import Foundation

public extension ExchangeThreadSituation {

    /// Baseline narration hooks for deterministic agency overlays (Pass 1–safe: read-only).
    func agencyBaselineBoundaryHints(prefixLimit: Int = 2) -> [String] {
        guard prefixLimit > 0 else { return [] }

        var lines: [String] = []

        if let reach = trim(reachabilityLine) {
            lines.append("Reachability (projection): \(reach)")
        }

        lines.append(contentsOf: explanationLines.prefix(prefixLimit))

        return Array(lines.prefix(prefixLimit))
    }

    private func trim(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
