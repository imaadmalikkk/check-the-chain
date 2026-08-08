import Foundation
import Testing
@testable import HadithKit

/// The load-bearing test in this project.
///
/// `golden.json` holds 30 queries replayed against the live web app — the same
/// MiniLM model, the same Convex hybrid search, the same RRF — along with the
/// top ten results it returned. This suite runs those queries through the fully
/// offline engine and requires it to reproduce them.
///
/// Everything in the iOS stack is a substitution for a piece of the web stack:
/// int8 quantization for Convex's vector index, a hand-written tokenizer for
/// Transformers.js's, FTS5 for Convex's search index, Core ML for ONNX. Each of
/// those could plausibly be slightly wrong in a way that never crashes and just
/// quietly returns worse hadith. This is what makes that visible.
@Suite("Golden parity with the web app")
struct GoldenParityTests {
    /// FTS5 and Convex's search index are different engines with different
    /// ranking, so the keyword leg cannot match exactly and a demand for 100%
    /// would be a demand to reimplement Convex. What must hold is that the fused
    /// result set is substantially the same and the strongest hits stay on top.
    static let minimumMeanOverlap = 0.7
    static let minimumTopOneRecall = 0.9

    @Test("Offline results reproduce the web app's")
    func matchesGoldenResults() async throws {
        let corpus = try TestFixtures.corpus()
        await corpus.embedder.warmUp()
        let golden = try TestFixtures.golden()

        var overlaps: [Double] = []
        var topOneRecalled = 0
        var weakest: [(String, Double)] = []

        for testCase in golden.cases {
            let results = try await corpus.engine.search(query: testCase.query, limit: 10)
            // golden.json identifies hadith as "slug/number", the same key the
            // pipeline uses — stable across display-name changes.
            let actual = results.map { "\($0.hadith.collectionSlug)/\($0.hadith.number)" }
            let expected = testCase.expected.map(\.ref)

            let overlap = Double(Set(actual).intersection(expected).count) / Double(expected.count)
            overlaps.append(overlap)

            if let best = expected.first, actual.prefix(3).contains(best) {
                topOneRecalled += 1
            }
            if overlap < 0.5 { weakest.append((testCase.query, overlap)) }
        }

        let mean = overlaps.reduce(0, +) / Double(overlaps.count)
        let recall = Double(topOneRecalled) / Double(golden.cases.count)

        print("""

            ── Golden parity ──────────────────────────────────
              mean top-10 overlap:   \(percent(mean))
              web's #1 in our top 3: \(percent(recall))
              weakest queries:       \(weakest.isEmpty ? "none" : weakest.map { "\($0.0) (\(percent($0.1)))" }.joined(separator: "; "))
            ───────────────────────────────────────────────────

            """)

        #expect(mean >= Self.minimumMeanOverlap,
                "Mean top-10 overlap fell to \(percent(mean))")
        #expect(recall >= Self.minimumTopOneRecall,
                "The web app's top result is missing from our top 3 too often (\(percent(recall)))")
    }

    /// Isolates ranking from embedding.
    ///
    /// Feeding in the vector Transformers.js produced takes the Core ML model
    /// and the tokenizer out of the equation, so anything failing here is the
    /// index or the fusion.
    @Test("Vector index returns sane results for reference embeddings")
    func vectorIndexHandlesReferenceEmbeddings() throws {
        let index = try TestFixtures.vectorIndex()
        let golden = try TestFixtures.golden()

        for testCase in golden.cases.prefix(10) {
            let ids = index.search(embedding: testCase.embedding, limit: 20)
            #expect(ids.count == 20, "Expected 20 hits for “\(testCase.query)”")
            #expect(Set(ids).count == ids.count, "Duplicate row ids returned")
            #expect(ids.allSatisfy { $0 >= 0 && $0 < Int64(index.metadata.count) })
        }
    }

    /// Proves the hand-written tokenizer matches the reference one.
    ///
    /// Not by comparing token ids, but by embedding on-device and comparing
    /// against the vector Transformers.js produced. A tokenization difference of
    /// even one token moves the embedding, so cosine against the reference is a
    /// direct check of the thing that actually matters.
    @Test("On-device embeddings match Transformers.js")
    func embeddingsMatchReference() async throws {
        let corpus = try TestFixtures.corpus()
        await corpus.embedder.warmUp()
        let golden = try TestFixtures.golden()

        var worst = 1.0
        var worstQuery = ""

        for testCase in golden.cases {
            let produced = try await corpus.embedder.embed(testCase.query)
            #expect(produced.count == 384)

            let cosine = zip(produced, testCase.embedding)
                .reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            if cosine < worst {
                worst = cosine
                worstQuery = testCase.query
            }
        }

        print("Worst on-device cosine vs Transformers.js: \(worst) — “\(worstQuery)”")
        #expect(worst >= 0.999, "Tokenizer or pooling diverges from the reference")
    }
}

private func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}
