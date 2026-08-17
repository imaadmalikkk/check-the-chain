import Foundation
@testable import HadithKit

/// Shared fixtures.
///
/// The test bundle is hosted by the app (`TEST_HOST` in `project.yml`), so it
/// runs inside `CheckTheChain.app/PlugIns/` and `Bundle.main` is the app itself.
/// That is deliberate: the tests exercise the exact artifacts that ship, not a
/// second copy that could drift.
enum TestFixtures {
    /// Loaded once — opening the database and mapping 18MB of embeddings for
    /// every test would dominate the run.
    ///
    /// `libraryURL: nil` — the engine tests must not create or mutate a real
    /// favourites store in the app's container.
    private static let sharedCorpus = Result { try Corpus(bundle: .main, libraryURL: nil) }
    private static let sharedGolden = Result { try loadGolden() }

    static func corpus() throws -> Corpus { try sharedCorpus.get() }
    static func golden() throws -> Golden { try sharedGolden.get() }

    /// A fresh (not cached) `Corpus` built through the designated initialiser so
    /// a specific `libraryURL` can be forced — the convenience init resolves its
    /// own. Used only by the test that proves a library which cannot be opened
    /// is swallowed rather than propagated.
    static func corpus(libraryURL: URL?) throws -> Corpus {
        try Corpus(
            databaseURL: resource("hadith", "sqlite", in: .main),
            embeddingsURL: resource("embeddings", "bin", in: .main),
            embeddingsMetadataURL: resource("embeddings", "json", in: .main),
            modelURL: resource("MiniLM", "mlmodelc", in: .main),
            vocabularyURL: resource("vocab", "txt", in: .main),
            libraryURL: libraryURL
        )
    }

    static func vectorIndex() throws -> VectorIndex {
        try VectorIndex(
            binaryURL: try resource("embeddings", "bin", in: .main),
            metadataURL: try resource("embeddings", "json", in: .main)
        )
    }

    static func tokenizer() throws -> BertTokenizer {
        try BertTokenizer(vocabularyURL: try resource("vocab", "txt", in: .main))
    }

    private static func loadGolden() throws -> Golden {
        let url = try resource("golden", "json", in: Bundle(for: TestBundleToken.self))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private static func resource(_ name: String, _ ext: String, in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw HadithKitError.missingResource("\(name).\(ext)")
        }
        return url
    }
}

struct Golden: Decodable {
    struct Expectation: Decodable {
        let ref: String
        let score: Int
    }

    struct Case: Decodable {
        let query: String
        /// The vector Transformers.js produced for this query, so the ranking
        /// can be tested independently of the on-device embedder.
        let embedding: [Float]
        let expected: [Expectation]
    }

    let topN: Int
    let cases: [Case]
}

/// Anchors `Bundle(for:)` to the test bundle rather than the host app.
private final class TestBundleToken {}
