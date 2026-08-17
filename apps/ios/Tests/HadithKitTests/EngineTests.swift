import Foundation
import Testing
@testable import HadithKit

@Suite("Store")
struct StoreTests {
    @Test("Artifacts come from the same pipeline run")
    func artifactsAgree() throws {
        let corpus = try TestFixtures.corpus()
        let index = try TestFixtures.vectorIndex()

        #expect(corpus.store.revision == index.metadata.revision)
        #expect(corpus.store.count == index.metadata.count)
        #expect(corpus.store.count == 47_442)
    }

    @Test("Lookup by reference")
    func lookup() async throws {
        let store = try TestFixtures.corpus().store
        let hadith = try await store.hadith(slug: "nawawi-40", number: "1")

        let found = try #require(hadith)
        #expect(found.collection == "The Forty Hadith of Imam Nawawi")
        #expect(found.number == "1")
        // This translation renders niyyah as "motives", not "intentions" — a
        // reminder that the corpus is one specific set of translations and
        // assertions have to match it rather than the phrasing we remember.
        #expect(found.english.lowercased().contains("niyyah"))
        #expect(!found.arabic.isEmpty)
        #expect(found.arabic.contains("بِالنِّيَّاتِ"))
    }

    @Test("Unknown references return nil rather than throwing")
    func missingLookup() async throws {
        let store = try TestFixtures.corpus().store
        #expect(try await store.hadith(slug: "sahih-al-bukhari", number: "999999") == nil)
        #expect(try await store.hadith(slug: "not-a-collection", number: "1") == nil)
    }

    @Test("Every shipped collection has hadith and chapters")
    func collectionsPopulated() async throws {
        let store = try TestFixtures.corpus().store
        let counts = try await store.collectionCounts()

        for collection in HadithCollection.all {
            let count = counts[collection.slug] ?? 0
            #expect(count > 0, "\(collection.slug) has no hadith")

            let page = try await store.page(slug: collection.slug, page: 0, pageSize: 5)
            #expect(!page.items.isEmpty, "\(collection.slug) returned an empty first page")
            #expect(page.total == count)
        }
    }

    @Test("Paging does not repeat or skip")
    func pagingBoundaries() async throws {
        let store = try TestFixtures.corpus().store
        let first = try await store.page(slug: "nawawi-40", page: 0, pageSize: 10)
        let second = try await store.page(slug: "nawawi-40", page: 1, pageSize: 10)

        #expect(first.items.count == 10)
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))

        // Past the end is empty, not an error.
        let beyond = try await store.page(slug: "nawawi-40", page: 999, pageSize: 10)
        #expect(beyond.items.isEmpty)
        #expect(beyond.total > 0)
    }

    /// Web and iOS must show the same hadith on the same day. The formula is
    /// duplicated across two languages, which is exactly the kind of thing that
    /// drifts silently.
    @Test("Hadith of the day matches the web app's formula", arguments: [
        (2026, 1, 1), (2026, 8, 7), (2026, 12, 31), (2027, 3, 15),
    ])
    func hadithOfTheDay(year: Int, month: Int, day: Int) async throws {
        let store = try TestFixtures.corpus().store
        let date = try #require(
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        )

        let hadith = try #require(try await store.hadithOfTheDay(on: date))
        #expect(hadith.collectionSlug == "sahih-al-bukhari")

        let startOfYear = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))!
        let previousYearEnd = Calendar.current.date(byAdding: .day, value: -1, to: startOfYear)!
        let dayOfYear = Int(date.timeIntervalSince(previousYearEnd) / 86_400)
        #expect(hadith.order == (year * 366 + dayOfYear) % 7276)
    }

    @Test("Batch ref lookup resolves what exists and omits what doesn't")
    func batchRefLookup() async throws {
        let store = try TestFixtures.corpus().store
        let real = HadithRef(collectionSlug: "sahih-al-bukhari", number: "1")
        let missing = HadithRef(collectionSlug: "sahih-al-bukhari", number: "999999")

        let found = try await store.hadith(refs: [real, missing])

        #expect(found.count == 1)
        #expect(found[real]?.number == "1")
        // A saved hadith that is no longer in the corpus must be absent, not a
        // crash and not a wrong row — the sheet renders it as a dangling entry.
        #expect(found[missing] == nil)
    }

    @Test("Batch ref lookup chunks past SQLite's variable limit")
    func batchRefLookupChunks() async throws {
        let store = try TestFixtures.corpus().store
        // 250 refs is 500 bound variables, past the 200-per-chunk boundary.
        let refs = (1...250).map { HadithRef(collectionSlug: "sahih-al-bukhari", number: "\($0)") }

        let found = try await store.hadith(refs: refs)

        #expect(found.count == 250)
    }
}

@Suite("Query handling")
struct QueryTests {
    @Test("Short queries return nothing rather than scanning the corpus")
    func shortQueries() async throws {
        let engine = try TestFixtures.corpus().engine
        #expect(try await engine.search(query: "").isEmpty)
        #expect(try await engine.search(query: "ab").isEmpty)
        #expect(try await engine.search(query: "   ").isEmpty)
    }

    /// FTS5's query language is not a safe place to interpolate a text field.
    @Test("Punctuation in the query cannot break the FTS expression", arguments: [
        "prophet's advice", "\"quoted\"", "faith OR", "a* b*", "NEAR(x y)",
        "-negation", "(unbalanced", "col:umn", "^caret", "hadith -- comment",
    ])
    func hostileQueries(query: String) async throws {
        let engine = try TestFixtures.corpus().engine
        // The requirement is that it doesn't throw. Results may be empty.
        _ = try await engine.search(query: query, limit: 5)
    }

    @Test("Keyword search finds verbatim wording")
    func keywordSearch() async throws {
        let engine = try TestFixtures.corpus().engine
        let results = try await engine.keywordSearch(query: "actions are by intentions", limit: 20)
        #expect(!results.isEmpty)
    }

    @Test("Scores are normalized to 0–100, highest first")
    func scoreNormalization() async throws {
        let corpus = try TestFixtures.corpus()
        await corpus.embedder.warmUp()

        let results = try await corpus.engine.search(query: "the virtue of praying at night", limit: 10)
        #expect(!results.isEmpty)
        #expect(results.first?.score == 100)
        #expect(results.allSatisfy { $0.score >= 0 && $0.score <= 100 })
        #expect(zip(results, results.dropFirst()).allSatisfy { $0.score >= $1.score })
    }
}

@Suite("Reciprocal rank fusion")
struct FusionTests {
    @Test("A hadith found by both legs outranks one found by either alone")
    func agreementWins() {
        let fused = SearchEngine.fuse(semantic: [1, 2, 3], keyword: [3, 4, 5], limit: 5)
        #expect(fused.first?.id == 3)
    }

    @Test("Results from one empty leg pass through in order")
    func singleLeg() {
        let fused = SearchEngine.fuse(semantic: [7, 8, 9], keyword: [], limit: 10)
        #expect(fused.map(\.id) == [7, 8, 9])
    }

    @Test("Both legs empty yields nothing")
    func bothEmpty() {
        #expect(SearchEngine.fuse(semantic: [], keyword: [], limit: 10).isEmpty)
    }

    @Test("Duplicates across legs are merged, not repeated")
    func deduplicates() {
        let fused = SearchEngine.fuse(semantic: [1, 2], keyword: [1, 2], limit: 10)
        #expect(fused.map(\.id).sorted() == [1, 2])
    }

    @Test("Respects the limit")
    func honorsLimit() {
        let fused = SearchEngine.fuse(semantic: Array(0..<50), keyword: Array(50..<100), limit: 10)
        #expect(fused.count == 10)
    }
}

@Suite("Tokenizer")
struct TokenizerTests {
    @Test("Wraps sequences in [CLS] and [SEP] and pads to the requested length")
    func specialTokens() throws {
        let tokenizer = try TestFixtures.tokenizer()
        let encoded = tokenizer.encode("prayer", paddedTo: 32)

        #expect(encoded.ids.count == 32)
        #expect(encoded.attentionMask.count == 32)
        #expect(encoded.ids.first == 101)
        #expect(encoded.ids[encoded.attentionMask.filter { $0 == 1 }.count - 1] == 102)
        #expect(encoded.attentionMask.reduce(0, +) == Int32(tokenizer.tokenCount("prayer")))
    }

    /// `[SEP]` must survive truncation, otherwise the model sees a sequence it
    /// was never trained on.
    @Test("Truncation keeps [SEP] at the end")
    func truncation() throws {
        let tokenizer = try TestFixtures.tokenizer()
        let long = String(repeating: "narration about prayer and fasting ", count: 40)
        let encoded = tokenizer.encode(long, paddedTo: 32)

        #expect(encoded.ids.count == 32)
        #expect(encoded.ids.first == 101)
        #expect(encoded.ids.last == 102)
        #expect(encoded.attentionMask.allSatisfy { $0 == 1 })
    }

    @Test("Lowercases, strips accents, and splits punctuation")
    func normalization() {
        #expect(BertTokenizer.normalize("Mu'ādh") == "mu'adh")
        #expect(BertTokenizer.normalize("A\tB\nC") == "a b c")
        #expect(BertTokenizer.preTokenize("prophet's advice.") == ["prophet", "'", "s", "advice", "."])
    }

    @Test("Unknown words fall back to [UNK] rather than crashing")
    func unknownWords() throws {
        let tokenizer = try TestFixtures.tokenizer()
        let encoded = tokenizer.encode("zzqqxxjj \u{1F600} 日本", paddedTo: 32)
        #expect(encoded.ids.first == 101)
        #expect(encoded.ids.count == 32)
    }

    @Test("Empty input still produces a valid sequence")
    func emptyInput() throws {
        let tokenizer = try TestFixtures.tokenizer()
        let encoded = tokenizer.encode("", paddedTo: 32)
        #expect(encoded.ids.prefix(2) == [101, 102])
        #expect(encoded.attentionMask.prefix(3) == [1, 1, 0])
    }
}
