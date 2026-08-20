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
    /// Nil when the store could not be opened. Nothing else in the app depends
    /// on it, so a broken favourites store costs favourites and nothing more.
    public let library: Library?

    public var hadithCount: Int { store.count }

    public init(
        databaseURL: URL,
        embeddingsURL: URL,
        embeddingsMetadataURL: URL,
        modelURL: URL,
        vocabularyURL: URL,
        libraryURL: URL?
    ) throws {
        store = try HadithStore(databaseURL: databaseURL)
        let index = try VectorIndex(binaryURL: embeddingsURL, metadataURL: embeddingsMetadataURL)
        embedder = try Embedder(compiledModelURL: modelURL, vocabularyURL: vocabularyURL)
        engine = try SearchEngine(store: store, index: index, embedder: embedder)
        // Deliberately not `try`. A corpus with no library is a working app; a
        // corpus that refuses to open because of the library is not. The
        // failure is still logged, though — silently swallowing it would mean
        // a future SwiftData migration failure makes every favourite vanish
        // with no crash, no message, and no trace to find later.
        library = libraryURL.flatMap { url in
            do {
                return try Library(url: url)
            } catch {
                Log.library.error("Failed to open library at \(url.path, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
    }

    /// Loads from a bundle's resources under the names the pipeline emits.
    ///
    /// Xcode compiles `MiniLM.mlpackage` into `MiniLM.mlmodelc` at build time,
    /// so that — not the package — is what exists at runtime.
    public convenience init(bundle: Bundle = .main, libraryURL: URL? = Corpus.defaultLibraryURL()) throws {
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
            vocabularyURL: resource("vocab", "txt"),
            libraryURL: libraryURL
        )
    }

    /// Application Support, created if absent.
    ///
    /// A store here is included in iOS device backups, which is what stands in
    /// for sync: favourites survive a new phone even though nothing is uploaded
    /// anywhere. Returns nil if the directory cannot be made, which the
    /// initialiser treats as "no library".
    public static func defaultLibraryURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("library.store")
    }
}
