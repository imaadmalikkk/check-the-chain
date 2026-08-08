import Foundation

/// Hybrid search: BM25 keyword ranking fused with semantic nearest neighbours.
///
/// A direct port of the `hybridSearch` action in `apps/web/convex/hadith.ts`,
/// including its constants — the same `K = 60`, the same `limit × 2` fetch
/// depth, the same normalization of the top score to 100. Those aren't
/// incidental: `HadithKitTests` replays queries captured from the live web app
/// and requires this engine to reproduce them, so anything tuned here has to be
/// tuned there too.
///
/// Neither leg is sufficient alone. Keyword search nails verbatim quotes and
/// proper nouns but returns nothing for "what did the prophet say about
/// forgiving people"; vector search handles the paraphrase but drifts on exact
/// citations. Reciprocal Rank Fusion combines them using only rank position,
/// which is what makes it safe to fuse two scores that aren't on a common scale.
public final class SearchEngine: Sendable {
    /// RRF damping. Higher values flatten the contribution of top ranks.
    private static let rrfK = 60.0

    private let store: HadithStore
    private let index: VectorIndex
    private let embedder: Embedder

    public init(store: HadithStore, index: VectorIndex, embedder: Embedder) throws {
        guard store.revision == index.metadata.revision else {
            throw HadithKitError.artifactMismatch(
                database: store.revision,
                embeddings: index.metadata.revision
            )
        }
        self.store = store
        self.index = index
        self.embedder = embedder
    }

    /// Runs both legs and fuses them.
    ///
    /// If the embedding model isn't loaded yet, this degrades to keyword-only
    /// rather than blocking on a cold Core ML load. Search stays responsive from
    /// the first keystroke and silently becomes hybrid once the model is warm.
    public func search(query: String, limit: Int = 20) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= FTSQuery.minimumQueryLength else { return [] }

        let fetchLimit = limit * 2

        async let keywordTask = store.fullTextSearch(query: trimmed, limit: fetchLimit)
        async let semanticTask = semanticSearch(query: trimmed, limit: fetchLimit)

        let keyword = try await keywordTask
        let semantic = await semanticTask

        let ranked = Self.fuse(semantic: semantic, keyword: keyword, limit: limit)
        guard let best = ranked.first?.score else { return [] }

        let hadith = try await store.hadith(ids: ranked.map(\.id))
        return ranked.compactMap { entry in
            guard let record = hadith[entry.id] else { return nil }
            return SearchResult(
                hadith: record,
                score: Int((entry.score / best * 100).rounded())
            )
        }
    }

    /// Keyword-only search. Used directly by tests to isolate the two legs.
    public func keywordSearch(query: String, limit: Int = 20) async throws -> [SearchResult] {
        let ids = try await store.fullTextSearch(query: query, limit: limit)
        let hadith = try await store.hadith(ids: ids)
        return ids.enumerated().compactMap { rank, id in
            guard let record = hadith[id] else { return nil }
            return SearchResult(hadith: record, score: Int((Double(ids.count - rank) / Double(ids.count) * 100).rounded()))
        }
    }

    private func semanticSearch(query: String, limit: Int) async -> [Int64] {
        guard await embedder.isReady else { return [] }
        guard let embedding = try? await embedder.embed(query) else { return [] }
        return index.search(embedding: embedding, limit: limit)
    }

    // MARK: - Reciprocal Rank Fusion

    struct Fused {
        let id: Int64
        let score: Double
    }

    static func fuse(semantic: [Int64], keyword: [Int64], limit: Int) -> [Fused] {
        var scores: [Int64: Double] = [:]
        // Insertion order breaks ties the way the Convex action does: vector
        // hits are accumulated first, so an equal-scoring pair keeps the
        // semantic ordering.
        var order: [Int64] = []

        func accumulate(_ ids: [Int64]) {
            for (rank, id) in ids.enumerated() {
                if scores[id] == nil { order.append(id) }
                scores[id, default: 0] += 1.0 / (rrfK + Double(rank) + 1.0)
            }
        }

        accumulate(semantic)
        accumulate(keyword)

        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order
            .sorted { lhs, rhs in
                let a = scores[lhs]!, b = scores[rhs]!
                if a != b { return a > b }
                return position[lhs]! < position[rhs]!
            }
            .prefix(limit)
            .map { Fused(id: $0, score: scores[$0]!) }
    }
}
