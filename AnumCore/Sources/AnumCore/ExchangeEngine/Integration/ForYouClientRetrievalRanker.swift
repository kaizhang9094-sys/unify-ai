import Foundation

#if DEBUG
private func forYouClientRetrievalLog(_ message: @autoclosure () -> String) {
    Swift.print(message())
}
#else
private func forYouClientRetrievalLog(_ message: @autoclosure () -> String) {}
#endif

#if DEBUG
/// Carries per-node retrieval diagnostics for DEBUG mixer logging (cleared after ``take()``).
internal struct ForYouClientRetrievalRerankDebugSnapshot: Sendable {
    let bm25ScoreByNodeID: [String: Double]
    let bm25HitPresentByNodeID: [String: Bool]
    let serverBestVectorSurfaceByNodeID: [String: String?]
    let serverBestVectorDocByNodeID: [String: String?]
}

internal final class ForYouClientRetrievalDebugSnapshotCoordinator: @unchecked Sendable {
    internal static let shared = ForYouClientRetrievalDebugSnapshotCoordinator()

    private let lock = NSLock()
    private var snapshot: ForYouClientRetrievalRerankDebugSnapshot?

    func set(_ value: ForYouClientRetrievalRerankDebugSnapshot?) {
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func take() -> ForYouClientRetrievalRerankDebugSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let out = snapshot
        snapshot = nil
        return out
    }
}
#endif

/// Log-only semantics for BM25 rank lines (scoring unchanged).
enum ForYouClientRetrievalBM25LogSemantics: Sendable {
    static func bm25HitPresent(bestScoreByNode: [String: Double], nodeID: String) -> Bool {
        guard let v = bestScoreByNode[nodeID] else { return false }
        return v > 0
    }

    static func bm25RankSource(bestScoreByNode: [String: Double], nodeID: String, bm25Rank: Int?) -> String {
        guard bm25Rank != nil else { return "positionalFallback" }
        return bm25HitPresent(bestScoreByNode: bestScoreByNode, nodeID: nodeID) ? "hit" : "positionalFallback"
    }
}

/// Client-side BM25 rerank over federation directory recall, optionally fused with server vector ranks via RRF.
public enum ForYouClientRetrievalRanker: Sendable {
    /// When `false`, directory match order stays as returned by the server (before ``ForYouResultMixer``).
    /// Defaults to `true` in all build configurations.
    nonisolated(unsafe) public static var useClientBM25Rerank: Bool = true

    /// Reorders ``matches`` by client BM25 when ``useClientBM25Rerank`` is `true`; otherwise returns ``matches`` unchanged.
    public static func rerankMatchesIfEnabled(
        matches: [ExchangeDirectoryMatch],
        queryText: String,
        directoryTags: [String],
        openToTags: [String],
        regionTags: [String],
        interestTags: [String],
        roleTags: [String]
    ) async -> [ExchangeDirectoryMatch] {
        #if DEBUG
        ForYouClientRetrievalDebugSnapshotCoordinator.shared.set(nil)
        #endif

        guard useClientBM25Rerank else { return matches }

        let builder = ExchangeRetrievalDocumentBuilder()
        let documents = builder.buildDocuments(matches: matches, sourceKind: .remote)
        if documents.isEmpty {
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][skipped] reason=noDocs serverCandidates=\(matches.count)"
            )
            return matches
        }

        let query = ForYouRetrievalQueryBuilder.buildForDirectoryRerank(
            queryText: queryText,
            directoryTags: directoryTags,
            openToTags: openToTags,
            regionTags: regionTags,
            interestTags: interestTags,
            roleTags: roleTags,
            candidateDocumentCount: documents.count
        )

        guard query.hasLexicalSignal else {
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][skipped] reason=emptyQuery serverCandidates=\(matches.count) docs=\(documents.count)"
            )
            return matches
        }

        for doc in documents where doc.searchableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][warn] empty searchableText docID=\(doc.id) counterpartyID=\(doc.counterpartyID)"
            )
        }

        forYouClientRetrievalLog(
            "[ForYouClientRetrieval][input] query=\(queryText.prefix(200)) tags=\(directoryTags.prefix(12)) " +
            "openTo=\(openToTags.prefix(8)) region=\(regionTags.prefix(8)) interest=\(interestTags.prefix(8)) " +
            "role=\(roleTags.prefix(8)) serverCandidates=\(matches.count) docs=\(documents.count)"
        )

        let docIDToNodeID: [String: String] = Dictionary(
            uniqueKeysWithValues: documents.map { ($0.id, $0.counterpartyID) }
        )

        #if DEBUG
        Self.logForYouBM25Diagnostics(
            documents: documents,
            query: query,
            docIDToNodeID: docIDToNodeID
        )
        #endif

        let store = ExchangeRetrievalStore()
        await store.replaceAllDocuments(documents)

        let bm25Limit = max(documents.count, 1)
        let hits = await store.searchBM25(query: query, limit: bm25Limit)

        #if DEBUG
        Self.logForYouBM25HitsDiagnostics(
            documents: documents,
            query: query,
            hits: hits,
            docIDToNodeID: docIDToNodeID
        )
        #endif

        var bestScoreByNode: [String: Double] = [:]
        for hit in hits {
            guard let nodeID = docIDToNodeID[hit.documentID], !nodeID.isEmpty else { continue }
            let prev = bestScoreByNode[nodeID] ?? 0
            if hit.score > prev {
                bestScoreByNode[nodeID] = hit.score
            }
        }

        let titleForLog: (ExchangeDirectoryMatch) -> String = { m in
            m.counterparty.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let bm25LogCap = 24
        for (idx, hit) in hits.prefix(bm25LogCap).enumerated() {
            let nodeID = docIDToNodeID[hit.documentID] ?? ""
            let serverIdx = matches.firstIndex { $0.counterparty.id == nodeID } ?? -1
            let serverScore = serverIdx >= 0 ? matches[serverIdx].score : nil
            let title = serverIdx >= 0 ? titleForLog(matches[serverIdx]) : nodeID
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][bm25] rank=\(idx + 1) title=\(title) nodeID=\(nodeID) " +
                "score=\(String(format: "%.4f", hit.score)) serverRank=\(serverIdx >= 0 ? serverIdx + 1 : 0) " +
                "serverScore=\(serverScore.map { String(format: "%.2f", $0) } ?? "nil")"
            )
        }
        if hits.count > bm25LogCap {
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][bm25] …truncated hits=\(hits.count) (showing first \(bm25LogCap))"
            )
        }

        #if DEBUG
        Self.logBestBM25SlicePerNode(
            matches: matches,
            documents: documents,
            hits: hits,
            docIDToNodeID: docIDToNodeID,
            bestScoreByNode: bestScoreByNode
        )
        #endif

        let sortedMatches = matches.enumerated().sorted { a, b in
            let sa = bestScoreByNode[a.element.counterparty.id] ?? 0
            let sb = bestScoreByNode[b.element.counterparty.id] ?? 0
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }.map(\.element)

        let bm25RankByNodeID: [String: Int] = Dictionary(
            sortedMatches.enumerated().map { ($0.element.counterparty.id, $0.offset + 1) },
            uniquingKeysWith: { first, _ in first }
        )

        let vectorCandidates = sortedMatches.filter { m in
            guard let v = m.vectorSignals, v.embeddingAvailable else { return false }
            return v.vectorRank != nil || v.vectorSimilarity != nil
        }
        let vectorOrdered = vectorCandidates.sorted(by: compareVectorLaneMatches)

        for (idx, m) in vectorOrdered.enumerated() {
            let v = m.vectorSignals
            let simStr = v?.vectorSimilarity.map { String(format: "%.4f", $0) } ?? "nil"
            let rankStr = v?.vectorRank.map(String.init) ?? "nil"
            let hitCount = v?.vectorHitCount ?? 0
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][vector] rank=\(idx + 1) title=\(titleForLog(m)) nodeID=\(m.counterparty.id) " +
                "similarity=\(simStr) vectorRank=\(rankStr) hitCount=\(hitCount)"
            )
        }

        var outputMatches: [ExchangeDirectoryMatch]
        let finalSource: String
        if vectorOrdered.isEmpty {
            outputMatches = sortedMatches
            finalSource = "bm25Only"
        } else {
            let bm25Hits = ExchangeRRF.rankedHits(
                documentIDs: sortedMatches.map(\.counterparty.id),
                source: "bm25"
            )
            let vectorHits = ExchangeRRF.rankedHits(
                documentIDs: vectorOrdered.map(\.counterparty.id),
                source: "serverVector"
            )
            let fused = ExchangeRRF.fuse(
                [bm25Hits, vectorHits],
                k: 60,
                limit: matches.count
            )

            var byNodeID: [String: ExchangeDirectoryMatch] = [:]
            for m in sortedMatches {
                byNodeID[m.counterparty.id] = m
            }

            for (idx, row) in fused.enumerated() {
                guard let m = byNodeID[row.documentID] else { continue }
                let br = row.bestRankBySource
                let bm25R = br["bm25"].map(String.init) ?? "nil"
                let vecR = br["serverVector"].map(String.init) ?? "nil"
                let nid = row.documentID
                let bm25Score = bestScoreByNode[nid] ?? 0
                let bm25Hit = ForYouClientRetrievalBM25LogSemantics.bm25HitPresent(
                    bestScoreByNode: bestScoreByNode,
                    nodeID: nid
                )
                let bm25RankSource = ForYouClientRetrievalBM25LogSemantics.bm25RankSource(
                    bestScoreByNode: bestScoreByNode,
                    nodeID: nid,
                    bm25Rank: br["bm25"]
                )
                forYouClientRetrievalLog(
                    "[ForYouClientRetrieval][rrf] rank=\(idx + 1) title=\(titleForLog(m)) nodeID=\(nid) " +
                    "bm25Score=\(String(format: "%.4f", bm25Score)) bm25Rank=\(bm25R) bm25HitPresent=\(bm25Hit) " +
                    "bm25RankSource=\(bm25RankSource) vectorRank=\(vecR) fusedScore=\(String(format: "%.5f", row.fusedScore))"
                )
            }

            var seen = Set<String>()
            var fusedOrder: [ExchangeDirectoryMatch] = []
            fusedOrder.reserveCapacity(sortedMatches.count)
            for row in fused {
                guard let m = byNodeID[row.documentID], !seen.contains(m.counterparty.id) else { continue }
                fusedOrder.append(m)
                seen.insert(m.counterparty.id)
            }
            for m in sortedMatches where !seen.contains(m.counterparty.id) {
                fusedOrder.append(m)
                seen.insert(m.counterparty.id)
            }
            outputMatches = fusedOrder
            finalSource = "bm25VectorRRF"
        }

        for (idx, m) in outputMatches.enumerated() {
            let nid = m.counterparty.id
            let bm = bestScoreByNode[nid] ?? 0
            let bm25Rank = bm25RankByNodeID[nid].map(String.init) ?? "nil"
            let serverIdx = matches.firstIndex { $0.counterparty.id == nid } ?? -1
            let v = m.vectorSignals
            let vecServerRank = v?.vectorRank.map(String.init) ?? "nil"
            let bm25Hit = ForYouClientRetrievalBM25LogSemantics.bm25HitPresent(
                bestScoreByNode: bestScoreByNode,
                nodeID: nid
            )
            let bm25RankSource = ForYouClientRetrievalBM25LogSemantics.bm25RankSource(
                bestScoreByNode: bestScoreByNode,
                nodeID: nid,
                bm25Rank: bm25RankByNodeID[nid]
            )
            let serverBestVectorDocID = v?.bestVectorRetrievalDocID ?? "nil"
            let serverBestVectorSurface = v?.bestVectorSurfaceType ?? "nil"
            forYouClientRetrievalLog(
                "[ForYouClientRetrieval][final] source=\(finalSource) rank=\(idx + 1) title=\(titleForLog(m)) nodeID=\(nid) " +
                "bm25Score=\(String(format: "%.4f", bm)) bm25Rank=\(bm25Rank) bm25HitPresent=\(bm25Hit) " +
                "bm25RankSource=\(bm25RankSource) serverVectorRank=\(vecServerRank) " +
                "serverBestVectorSurfaceType=\(serverBestVectorSurface) serverBestVectorDocID=\(serverBestVectorDocID) " +
                "serverRank=\(serverIdx >= 0 ? serverIdx + 1 : 0)"
            )
        }

        #if DEBUG
        var hitPresentByNode: [String: Bool] = [:]
        var serverSurf: [String: String?] = [:]
        var serverDoc: [String: String?] = [:]
        for m in matches {
            let nid = m.counterparty.id
            hitPresentByNode[nid] = ForYouClientRetrievalBM25LogSemantics.bm25HitPresent(
                bestScoreByNode: bestScoreByNode,
                nodeID: nid
            )
            serverSurf[nid] = m.vectorSignals?.bestVectorSurfaceType
            serverDoc[nid] = m.vectorSignals?.bestVectorRetrievalDocID
        }
        ForYouClientRetrievalDebugSnapshotCoordinator.shared.set(
            ForYouClientRetrievalRerankDebugSnapshot(
                bm25ScoreByNodeID: bestScoreByNode,
                bm25HitPresentByNodeID: hitPresentByNode,
                serverBestVectorSurfaceByNodeID: serverSurf,
                serverBestVectorDocByNodeID: serverDoc
            )
        )
        #endif

        return outputMatches
    }

    private static func compareVectorLaneMatches(_ a: ExchangeDirectoryMatch, _ b: ExchangeDirectoryMatch) -> Bool {
        let ra = a.vectorSignals?.vectorRank
        let rb = b.vectorSignals?.vectorRank
        switch (ra, rb) {
        case let (ixa?, ixb?):
            if ixa != ixb { return ixa < ixb }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        let sa = a.vectorSignals?.vectorSimilarity ?? 0
        let sb = b.vectorSignals?.vectorSimilarity ?? 0
        if sa != sb { return sa > sb }
        return a.counterparty.id < b.counterparty.id
    }

    #if DEBUG
    private static func debugSurfaceTypeLabel(_ surface: ExchangeRetrievalDocument.SurfaceType) -> String {
        switch surface {
        case .offer: return "offer"
        case .publicProfile: return "publicProfile"
        case .publicProfileCapability: return "publicProfileCapability"
        case .publicProfileSeeking: return "publicProfileSeeking"
        case .publicProfileAffinity: return "publicProfileAffinity"
        case .unknown(let u):
            let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "unknown" : "unknown:\(t.prefix(48))"
        }
    }

    private static func joinTokensForLog(_ tokens: [String], cap: Int) -> String {
        guard cap > 0 else { return "" }
        return tokens.prefix(cap).joined(separator: ",")
    }

    private static func oneLinePreview(_ text: String, maxChars: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard maxChars > 0 else { return "" }
        if collapsed.count <= maxChars { return collapsed }
        return String(collapsed.prefix(maxChars)) + "…"
    }

    private static func logForYouBM25Diagnostics(
        documents: [ExchangeRetrievalDocument],
        query: ExchangeRetrievalQuery,
        docIDToNodeID: [String: String]
    ) {
        let joinedQueryText = ExchangeBM25Index.lexicalQueryTextForBM25Search(query)
        let queryTokens = ExchangeBM25Index.debugTokenize(joinedQueryText)
        forYouClientRetrievalLog(
            "[ForYouBM25Diag][query] queryChars=\(joinedQueryText.count) tokenCount=\(queryTokens.count) " +
            "tokens=\(joinTokensForLog(queryTokens, cap: 60))"
        )

        let queryTokenSet = Set(queryTokens)
        for doc in documents {
            let st = doc.searchableText
            let docTokens = ExchangeBM25Index.debugTokenize(st)
            let docSet = Set(docTokens)
            let overlap = queryTokenSet.intersection(docSet).sorted()
            let queryOnly = queryTokenSet.subtracting(docSet).sorted()
            let docOnly = docSet.subtracting(queryTokenSet).sorted()
            let nodeID = docIDToNodeID[doc.id] ?? doc.counterpartyID
            forYouClientRetrievalLog(
                "[ForYouBM25Diag][doc] nodeID=\(nodeID) docID=\(doc.id) surfaceType=\(debugSurfaceTypeLabel(doc.surfaceType)) " +
                "searchableChars=\(st.count) tokenCount=\(docTokens.count) " +
                "tokens=\(joinTokensForLog(docTokens, cap: 30)) " +
                "preview=\(oneLinePreview(st, maxChars: 160))"
            )
            forYouClientRetrievalLog(
                "[ForYouBM25Diag][overlap] nodeID=\(nodeID) docID=\(doc.id) surfaceType=\(debugSurfaceTypeLabel(doc.surfaceType)) " +
                "overlapCount=\(overlap.count) overlapTokens=\(joinTokensForLog(overlap, cap: 24)) " +
                "queryOnlySample=\(joinTokensForLog(queryOnly, cap: 12)) docOnlySample=\(joinTokensForLog(docOnly, cap: 12))"
            )
        }
    }

    private static func logForYouBM25HitsDiagnostics(
        documents: [ExchangeRetrievalDocument],
        query: ExchangeRetrievalQuery,
        hits: [ExchangeBM25Index.SearchHit],
        docIDToNodeID: [String: String]
    ) {
        let docByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        let joinedQueryText = ExchangeBM25Index.lexicalQueryTextForBM25Search(query)
        let queryTokens = ExchangeBM25Index.debugTokenize(joinedQueryText)
        let indexedDocCount = documents.count
        let nonEmptyIndexedDocCount = documents.filter { !ExchangeBM25Index.debugTokenize($0.searchableText).isEmpty }.count

        if let top = hits.first {
            let surf = docByID[top.documentID].map { debugSurfaceTypeLabel($0.surfaceType) } ?? "nil"
            let nodeID = docIDToNodeID[top.documentID] ?? ""
            forYouClientRetrievalLog(
                "[ForYouBM25Diag][hits] hits=\(hits.count) topHitDocID=\(top.documentID) topHitScore=\(String(format: "%.4f", top.score)) " +
                "topHitSurfaceType=\(surf) topHitNodeID=\(nodeID)"
            )
        } else {
            let reason: String
            if queryTokens.isEmpty {
                reason = "emptyQueryTokens"
            } else if indexedDocCount == 0 {
                reason = "emptyIndexedDocs"
            } else if nonEmptyIndexedDocCount == 0 {
                reason = "emptyIndexedDocs"
            } else {
                reason = "noExactTokenOverlap"
            }
            forYouClientRetrievalLog(
                "[ForYouBM25Diag][noHits] reason=\(reason) queryTokens=\(joinTokensForLog(queryTokens, cap: 40)) " +
                "indexedDocCount=\(indexedDocCount) nonEmptyIndexedDocCount=\(nonEmptyIndexedDocCount)"
            )
        }

        for (idx, hit) in hits.prefix(8).enumerated() {
            let d = docByID[hit.documentID]
            let surf = d.map { debugSurfaceTypeLabel($0.surfaceType) } ?? "nil"
            let nodeID = docIDToNodeID[hit.documentID] ?? ""
            forYouClientRetrievalLog(
                "[ForYouBM25Diag][hit] rank=\(idx + 1) score=\(String(format: "%.4f", hit.score)) nodeID=\(nodeID) " +
                "docID=\(hit.documentID) surfaceType=\(surf)"
            )
        }
    }

    private static func logBestBM25SlicePerNode(
        matches: [ExchangeDirectoryMatch],
        documents: [ExchangeRetrievalDocument],
        hits: [ExchangeBM25Index.SearchHit],
        docIDToNodeID: [String: String],
        bestScoreByNode: [String: Double]
    ) {
        let docByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        var bestHitPerNode: [String: (docID: String, score: Double, surface: String)] = [:]
        for hit in hits where hit.score > 0 {
            guard let nodeID = docIDToNodeID[hit.documentID], !nodeID.isEmpty else { continue }
            let prev = bestHitPerNode[nodeID]
            if prev == nil || hit.score > prev!.score {
                let surf = docByID[hit.documentID].map { debugSurfaceTypeLabel($0.surfaceType) } ?? "nil"
                bestHitPerNode[nodeID] = (hit.documentID, hit.score, surf)
            }
        }

        let nodeIDs = matches.map(\.counterparty.id)
        for nid in nodeIDs {
            if let row = bestHitPerNode[nid] {
                forYouClientRetrievalLog(
                    "[ForYouClientRetrieval][bm25BestSlice] nodeID=\(nid) bestDocID=\(row.docID) surfaceType=\(row.surface) " +
                    "score=\(String(format: "%.4f", row.score))"
                )
            } else {
                let agg = bestScoreByNode[nid] ?? 0
                let reason = agg > 0 ? "noPositiveDocHit" : "noPositiveBM25Hit"
                forYouClientRetrievalLog(
                    "[ForYouClientRetrieval][bm25BestSlice] nodeID=\(nid) bestDocID=nil surfaceType=nil score=0 reason=\(reason)"
                )
            }
        }
    }

    #endif
}
