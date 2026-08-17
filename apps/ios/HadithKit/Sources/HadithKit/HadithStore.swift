import Foundation
import GRDB

/// Read-only access to the bundled corpus.
///
/// Ports the queries in `apps/web/convex/hadith.ts`. The database ships inside
/// the app bundle and is opened in place — it is immutable, so copying it into
/// Application Support would only double the disk footprint.
public final class HadithStore: Sendable {
    private let dbQueue: DatabaseQueue

    public let revision: String
    public let count: Int

    public init(databaseURL: URL) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw HadithKitError.missingResource(databaseURL.lastPathComponent)
        }

        var config = Configuration()
        config.readonly = true
        config.prepareDatabase { db in
            // The database lives in the app bundle, which is read-only. Anything
            // SQLite would otherwise spill to a temporary file has nowhere to go,
            // so keep scratch space in memory — these queries are small and the
            // alternative is an I/O error on a read.
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            // Map the file rather than read() through the page cache. It never
            // changes, so the pages stay clean and evictable, and browsing a
            // 107MB corpus stops paying a copy per row.
            try db.execute(sql: "PRAGMA mmap_size = 268435456")
        }
        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)

        (revision, count) = try dbQueue.read { db in
            let revision = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'revision'") ?? ""
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hadith") ?? 0
            return (revision, count)
        }
    }

    // MARK: - Lookups

    public func hadith(slug: String, number: String) async throws -> Hadith? {
        try await dbQueue.read { db in
            try Hadith.fetchOne(
                db,
                sql: "\(Self.selectColumns) WHERE collection_slug = ? AND hadith_number = ?",
                arguments: [slug, number]
            )
        }
    }

    public func hadith(ids: [Int64]) async throws -> [Int64: Hadith] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = databaseQuestionMarks(count: ids.count)
        let rows = try await dbQueue.read { db in
            try Hadith.fetchAll(
                db,
                sql: "\(Self.selectColumns) WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    /// Resolves saved or recently viewed refs in as few queries as possible.
    ///
    /// Returns a dictionary and leaves ordering to the caller, matching
    /// `hadith(ids:)`. A ref with no row is simply absent: that is how a saved
    /// hadith which a later corpus renumbered or dropped reaches the UI, which
    /// renders it as a dangling entry rather than quietly forgetting it.
    public func hadith(refs: [HadithRef]) async throws -> [HadithRef: Hadith] {
        guard !refs.isEmpty else { return [:] }

        var found: [HadithRef: Hadith] = [:]
        // 200 pairs is 400 bound variables, comfortably inside SQLite's default
        // limit of 999. Saved is unbounded, so this is required, not theoretical.
        for chunk in refs.chunked(into: 200) {
            let predicate = Array(
                repeating: "(collection_slug = ? AND hadith_number = ?)",
                count: chunk.count
            ).joined(separator: " OR ")

            var arguments: [(any DatabaseValueConvertible)?] = []
            arguments.reserveCapacity(chunk.count * 2)
            for ref in chunk {
                arguments.append(ref.collectionSlug)
                arguments.append(ref.number)
            }
            let statementArguments = StatementArguments(arguments)

            let rows: [Hadith] = try await dbQueue.read { db in
                try Hadith.fetchAll(
                    db,
                    sql: "\(Self.selectColumns) WHERE \(predicate)",
                    arguments: statementArguments
                )
            }
            for row in rows {
                found[HadithRef(collectionSlug: row.collectionSlug, number: row.number)] = row
            }
        }
        return found
    }

    // MARK: - Browsing

    public func page(slug: String, page: Int, pageSize: Int = 50) async throws -> Page<Hadith> {
        try await dbQueue.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT count FROM collection_counts WHERE collection_slug = ?",
                arguments: [slug]
            ) ?? 0
            let items = try Hadith.fetchAll(
                db,
                sql: """
                    \(Self.selectColumns) WHERE collection_slug = ?
                    ORDER BY "order" LIMIT ? OFFSET ?
                    """,
                arguments: [slug, pageSize, page * pageSize]
            )
            return Page(items: items, total: total)
        }
    }

    public func page(
        slug: String,
        chapterID: Int,
        page: Int,
        pageSize: Int = 50
    ) async throws -> Page<Hadith> {
        try await dbQueue.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT hadith_count FROM chapters WHERE collection_slug = ? AND chapter_id = ?",
                arguments: [slug, chapterID]
            ) ?? 0
            let items = try Hadith.fetchAll(
                db,
                sql: """
                    \(Self.selectColumns) WHERE collection_slug = ? AND chapter_id = ?
                    ORDER BY "order" LIMIT ? OFFSET ?
                    """,
                arguments: [slug, chapterID, pageSize, page * pageSize]
            )
            return Page(items: items, total: total)
        }
    }

    public func chapters(slug: String) async throws -> [Chapter] {
        try await dbQueue.read { db in
            try Chapter.fetchAll(
                db,
                sql: """
                    SELECT collection_slug, chapter_id, name_english, name_arabic, hadith_count, "order"
                    FROM chapters WHERE collection_slug = ? ORDER BY "order"
                    """,
                arguments: [slug]
            )
        }
    }

    public func collectionCounts() async throws -> [String: Int] {
        let rows: [Row] = try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT collection_slug, count FROM collection_counts")
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["collection_slug"], $0["count"]) })
    }

    /// The same hadith the web app shows on a given day.
    ///
    /// Reproduces the arithmetic in `apps/web/convex/hadith.ts` exactly,
    /// including its use of the local calendar and its fixed 7276 modulus —
    /// changing either would silently desynchronize the two products.
    public func hadithOfTheDay(on date: Date = Date()) async throws -> Hadith? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: date)
        guard let year = components.year,
              let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        else { return nil }

        // JS: `new Date(year, 0, 0)` is December 31st of the previous year, so
        // January 1st yields dayOfYear = 1.
        let previousYearEnd = calendar.date(byAdding: .day, value: -1, to: startOfYear)!
        let dayOfYear = Int(date.timeIntervalSince(previousYearEnd) / 86_400)
        let index = (year * 366 + dayOfYear) % 7276

        return try await dbQueue.read { db in
            try Hadith.fetchOne(
                db,
                sql: """
                    \(Self.selectColumns)
                    WHERE collection_slug = 'sahih-al-bukhari' AND "order" = ?
                    """,
                arguments: [index]
            )
        }
    }

    // MARK: - Full-text search

    /// BM25-ranked keyword search. Returns row ids in rank order; the fusion
    /// step only cares about position, so the raw scores are dropped.
    func fullTextSearch(query: String, limit: Int) async throws -> [Int64] {
        guard let match = FTSQuery.match(for: query) else { return [] }
        return try await dbQueue.read { db in
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT rowid FROM hadith_fts
                    WHERE hadith_fts MATCH ?
                    ORDER BY bm25(hadith_fts) LIMIT ?
                    """,
                arguments: [match, limit]
            )
        }
    }

    private static let selectColumns = """
        SELECT id, collection, collection_slug, hadith_number, "order", narrator,
               english, arabic, grading, graded_by, isnad_narrators,
               chapter_id, chapter_english, hadith_in_chapter
        FROM hadith
        """
}

private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Row decoding

extension Hadith: FetchableRecord {
    public init(row: Row) {
        let isnad: [String]
        if let json: String = row["isnad_narrators"],
           let data = json.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            isnad = parsed
        } else {
            isnad = []
        }

        self.init(
            id: row["id"],
            collection: row["collection"],
            collectionSlug: row["collection_slug"],
            number: row["hadith_number"],
            order: row["order"],
            narrator: row["narrator"],
            english: row["english"],
            arabic: row["arabic"],
            gradingRaw: row["grading"],
            gradedBy: row["graded_by"],
            isnadNarrators: isnad,
            chapterID: row["chapter_id"],
            chapterEnglish: row["chapter_english"],
            hadithInChapter: row["hadith_in_chapter"]
        )
    }
}

extension Chapter: FetchableRecord {
    public init(row: Row) {
        self.init(
            collectionSlug: row["collection_slug"],
            chapterID: row["chapter_id"],
            nameEnglish: row["name_english"],
            nameArabic: row["name_arabic"],
            hadithCount: row["hadith_count"],
            order: row["order"]
        )
    }
}
