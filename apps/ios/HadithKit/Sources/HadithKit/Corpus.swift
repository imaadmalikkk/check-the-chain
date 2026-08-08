import Foundation

/// Everything the app needs, assembled from bundled resources.
///
/// The whole corpus, its embeddings, and the embedding model ship inside the
/// app. There is no network path in this package — not a lazy one, not a
/// fallback one. That is the point: search works on a plane, costs nothing to
/// run, and cannot be broken by a backend outage.
public final class Corpus: Sendable {
    public let store: HadithStore
    public let engine: SearchEngine
    public let embedder: Embedder

    public var hadithCount: Int { store.count }

    public init(
        databaseURL: URL,
        embeddingsURL: URL,
        embeddingsMetadataURL: URL,
        modelURL: URL,
        vocabularyURL: URL
    ) throws {
        store = try HadithStore(databaseURL: databaseURL)
        let index = try VectorIndex(binaryURL: embeddingsURL, metadataURL: embeddingsMetadataURL)
        embedder = try Embedder(compiledModelURL: modelURL, vocabularyURL: vocabularyURL)
        engine = try SearchEngine(store: store, index: index, embedder: embedder)
    }

    /// Loads from a bundle's resources under the names the pipeline emits.
    ///
    /// Xcode compiles `MiniLM.mlpackage` into `MiniLM.mlmodelc` at build time,
    /// so that — not the package — is what exists at runtime.
    public convenience init(bundle: Bundle = .main) throws {
        func resource(_ name: String, _ ext: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                throw HadithKitError.missingResource("\(name).\(ext)")
            }
            return url
        }

        try self.init(
            databaseURL: resource("hadith", "sqlite"),
            embeddingsURL: resource("embeddings", "bin"),
            embeddingsMetadataURL: resource("embeddings", "json"),
            modelURL: resource("MiniLM", "mlmodelc"),
            vocabularyURL: resource("vocab", "txt")
        )
    }
}
