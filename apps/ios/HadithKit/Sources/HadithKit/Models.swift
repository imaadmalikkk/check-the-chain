import Foundation

/// Scholarly authenticity grading. Mirrors `Grading` in
/// `apps/web/src/lib/types.ts`; the raw string is kept in the database so an
/// unrecognized value degrades to `.unknown` rather than failing to decode.
public enum Grading: String, Sendable, CaseIterable, Hashable {
    case sahih = "Sahih"
    case hasan = "Hasan"
    case daif = "Da'if"
    case mawdu = "Mawdu'"
    case unknown = "Unknown"

    public init(raw: String) {
        self = Grading(rawValue: raw) ?? .unknown
    }

    /// The plain-English gloss shown beside the Arabic term, matching
    /// `apps/web/src/components/grading-badge.tsx`.
    public var meaning: String {
        switch self {
        case .sahih: "Authentic"
        case .hasan: "Good"
        case .daif: "Weak"
        case .mawdu: "Fabricated"
        case .unknown: "Ungraded"
        }
    }
}

public struct Hadith: Sendable, Identifiable, Hashable {
    /// Dense row id. Also the row index into `embeddings.bin`.
    public let id: Int64
    public let collection: String
    public let collectionSlug: String
    public let number: String
    public let order: Int
    public let narrator: String
    public let english: String
    public let arabic: String
    public let gradingRaw: String
    public let gradedBy: String
    public let isnadNarrators: [String]
    public let chapterID: Int?
    public let chapterEnglish: String?
    public let hadithInChapter: Int?

    public var grading: Grading { Grading(raw: gradingRaw) }

    /// e.g. "Sahih al-Bukhari 1"
    public var reference: String { "\(collection) \(number)" }

    /// `Darussalam` is a publisher, not a hadith scholar — the web app
    /// discloses this and so must the app.
    public var gradedByIsPublisher: Bool { gradedBy == "Darussalam" }
}

public struct SearchResult: Sendable, Identifiable, Hashable {
    public let hadith: Hadith
    /// 0–100, normalized against the top hit — the same presentation the
    /// Convex action produces.
    public let score: Int

    public var id: Int64 { hadith.id }
}

public struct Chapter: Sendable, Identifiable, Hashable {
    public let collectionSlug: String
    public let chapterID: Int
    public let nameEnglish: String
    public let nameArabic: String
    public let hadithCount: Int
    public let order: Int

    public var id: Int { chapterID }
}

public struct Page<Element: Sendable>: Sendable {
    public let items: [Element]
    public let total: Int
}

public enum HadithKitError: Error, LocalizedError {
    case missingResource(String)
    case invalidVocabulary
    case artifactMismatch(database: String, embeddings: String)
    case corruptEmbeddings(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing bundled resource: \(name). Run `npm run pipeline` and rebuild."
        case .invalidVocabulary:
            "vocab.txt is not a valid BERT vocabulary."
        case .artifactMismatch(let db, let emb):
            """
            hadith.sqlite (revision \(db)) and embeddings.bin (revision \(emb)) came \
            from different pipeline runs. Semantic search would return the wrong \
            hadith for every hit. Rebuild both with `npm run pipeline`.
            """
        case .corruptEmbeddings(let detail):
            "embeddings.bin is unusable: \(detail)"
        }
    }
}
