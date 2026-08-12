import Foundation

/// Reciprocal Rank Fusion for merging multiple ranked lists.
///
/// Standard shape:
/// score(doc) += 1 / (k + rank)
///
/// Notes:
/// - Lower rank number is better
/// - RRF does not depend on raw score scale
/// - This makes it ideal for BM25 + vector fusion
public enum ExchangeRRF {
    public struct RankedHit: Sendable, Hashable {
        public let documentID: String
        public let rank: Int
        public let source: String

        public init(
            documentID: String,
            rank: Int,
            source: String
        ) {
            self.documentID = documentID
            self.rank = max(1, rank)
            self.source = source
        }
    }

    public struct FusionResult: Sendable, Hashable {
        public let documentID: String
        public let fusedScore: Double
        public let contributingSources: [String]
        public let bestRankBySource: [String: Int]

        public init(
            documentID: String,
            fusedScore: Double,
            contributingSources: [String],
            bestRankBySource: [String: Int]
        ) {
            self.documentID = documentID
            self.fusedScore = fusedScore
            self.contributingSources = contributingSources.sorted()
            self.bestRankBySource = bestRankBySource
        }
    }

    public static func fuse(
        _ rankedLists: [[RankedHit]],
        k: Int = 60,
        limit: Int? = nil
    ) -> [FusionResult] {
        guard k > 0 else { return [] }

        var scoreByDocumentID: [String: Double] = [:]
        var sourcesByDocumentID: [String: Set<String>] = [:]
        var bestRankBySourceByDocumentID: [String: [String: Int]] = [:]

        for list in rankedLists {
            // Deduplicate within one ranked list/source so the same document
            // cannot contribute multiple times from the same source.
            var bestRankForDocumentInThisList: [String: RankedHit] = [:]

            for hit in list {
                if let existing = bestRankForDocumentInThisList[hit.documentID] {
                    if hit.rank < existing.rank {
                        bestRankForDocumentInThisList[hit.documentID] = hit
                    }
                } else {
                    bestRankForDocumentInThisList[hit.documentID] = hit
                }
            }

            for hit in bestRankForDocumentInThisList.values {
                let contribution = 1.0 / Double(k + hit.rank)
                scoreByDocumentID[hit.documentID, default: 0] += contribution
                sourcesByDocumentID[hit.documentID, default: []].insert(hit.source)

                var ranks = bestRankBySourceByDocumentID[hit.documentID, default: [:]]
                if let existing = ranks[hit.source] {
                    ranks[hit.source] = min(existing, hit.rank)
                } else {
                    ranks[hit.source] = hit.rank
                }
                bestRankBySourceByDocumentID[hit.documentID] = ranks
            }
        }

        let sorted = scoreByDocumentID
            .map { documentID, fusedScore in
                FusionResult(
                    documentID: documentID,
                    fusedScore: fusedScore,
                    contributingSources: Array(sourcesByDocumentID[documentID] ?? []),
                    bestRankBySource: bestRankBySourceByDocumentID[documentID] ?? [:]
                )
            }
            .sorted { lhs, rhs in
                if lhs.fusedScore != rhs.fusedScore {
                    return lhs.fusedScore > rhs.fusedScore
                }

                let lhsBest = lhs.bestRankBySource.values.min() ?? .max
                let rhsBest = rhs.bestRankBySource.values.min() ?? .max
                if lhsBest != rhsBest {
                    return lhsBest < rhsBest
                }

                return lhs.documentID < rhs.documentID
            }

        if let limit {
            return Array(sorted.prefix(max(0, limit)))
        }

        return sorted
    }

    public static func rankedHits(
        documentIDs: [String],
        source: String
    ) -> [RankedHit] {
        var seen = Set<String>()
        var output: [RankedHit] = []
        output.reserveCapacity(documentIDs.count)

        for documentID in documentIDs {
            guard !seen.contains(documentID) else { continue }
            seen.insert(documentID)

            output.append(
                RankedHit(
                    documentID: documentID,
                    rank: output.count + 1,
                    source: source
                )
            )
        }

        return output
    }
}
