import Foundation
import Testing
@testable import HadithKit

/// `url: nil` gives an in-memory store, so these never touch the app container
/// and never leak state between runs.
@Suite("Library")
struct LibraryTests {
    private let bukhari1 = HadithRef(collectionSlug: "sahih-al-bukhari", number: "1")
    private let muslim1 = HadithRef(collectionSlug: "sahih-muslim", number: "1")

    @Test("Starring is a round trip")
    func toggleSaved() async throws {
        let library = try Library(url: nil)

        #expect(try await library.isSaved(bukhari1) == false)
        #expect(try await library.toggleSaved(bukhari1) == true)
        #expect(try await library.isSaved(bukhari1) == true)
        #expect(try await library.saved() == [bukhari1])

        #expect(try await library.toggleSaved(bukhari1) == false)
        #expect(try await library.isSaved(bukhari1) == false)
        #expect(try await library.saved().isEmpty)
    }

    /// Proves the `#Unique` constraint, which is what the whole dedupe story
    /// rests on — for Recent as well as Saved.
    @Test("Saving the same hadith twice leaves one row")
    func savingTwiceIsIdempotent() async throws {
        let library = try Library(url: nil)
        _ = try await library.toggleSaved(bukhari1)
        try await library.save(bukhari1)

        #expect(try await library.saved() == [bukhari1])
    }

    @Test("Saved is newest first")
    func savedOrdering() async throws {
        let library = try Library(url: nil)
        try await library.save(bukhari1)
        try await library.save(muslim1)

        #expect(try await library.saved() == [muslim1, bukhari1])
    }

    @Test("Re-opening a hadith reorders Recent rather than duplicating it")
    func recentDedupes() async throws {
        let library = try Library(url: nil)
        await library.recordView(bukhari1)
        try await Task.sleep(for: .milliseconds(10))
        await library.recordView(muslim1)
        try await Task.sleep(for: .milliseconds(10))
        await library.recordView(bukhari1)

        #expect(try await library.recent() == [bukhari1, muslim1])
    }

    @Test("Recent is pruned at the cap")
    func recentPrunes() async throws {
        let library = try Library(url: nil)
        for index in 0...Library.recentCap {
            await library.recordView(HadithRef(collectionSlug: "sahih-al-bukhari", number: "\(index)"))
        }

        let recent = try await library.recent(limit: Library.recentCap * 2)
        #expect(recent.count == Library.recentCap)
        // The oldest is the one that went, not an arbitrary one.
        #expect(!recent.contains(HadithRef(collectionSlug: "sahih-al-bukhari", number: "0")))
    }

    /// Backs the dangling row's "Remove" action under the Recent segment.
    /// `toggleSaved` cannot remove a Recent entry — it operates on `SavedHadith`
    /// — so this is the API that actually does it, and it must leave everything
    /// else (other Recent rows, all of Saved) untouched.
    @Test("Removing one Recent entry leaves the rest of Recent and all of Saved alone")
    func removeRecentIsTargeted() async throws {
        let library = try Library(url: nil)
        try await library.save(bukhari1)
        await library.recordView(bukhari1)
        await library.recordView(muslim1)

        try await library.removeRecent(bukhari1)

        #expect(try await library.recent() == [muslim1])
        #expect(try await library.saved() == [bukhari1])
    }

    /// The dangling row's ref is by definition not resolvable against the
    /// corpus, so the caller has no way to check membership first — removal
    /// must tolerate a ref that was never in Recent to begin with.
    @Test("Removing a ref that isn't in Recent does not throw")
    func removeRecentAbsentRefIsNoOp() async throws {
        let library = try Library(url: nil)
        await library.recordView(muslim1)

        try await library.removeRecent(bukhari1)

        #expect(try await library.recent() == [muslim1])
    }

    /// Backs the dangling row's Remove action under the Saved segment — the
    /// counterpart to `removeRecentIsTargeted` above. The Saved side used to
    /// have no API of its own and called `toggleSaved` instead, which is only
    /// correct as long as the ref really is saved.
    @Test("Removing one Saved entry leaves the rest of Saved and all of Recent alone")
    func removeSavedIsTargeted() async throws {
        let library = try Library(url: nil)
        try await library.save(bukhari1)
        try await library.save(muslim1)
        await library.recordView(bukhari1)

        try await library.removeSaved(bukhari1)

        #expect(try await library.saved() == [muslim1])
        #expect(try await library.recent() == [bukhari1])
    }

    @Test("Removing a ref that isn't saved does not throw")
    func removeSavedAbsentRefIsNoOp() async throws {
        let library = try Library(url: nil)
        try await library.save(muslim1)

        try await library.removeSaved(bukhari1)

        #expect(try await library.saved() == [muslim1])
    }

    @Test("Clearing history leaves the starred list alone")
    func clearRecentKeepsSaved() async throws {
        let library = try Library(url: nil)
        try await library.save(bukhari1)
        await library.recordView(bukhari1)

        try await library.clearRecent()

        #expect(try await library.recent().isEmpty)
        #expect(try await library.saved() == [bukhari1])
    }

    /// Every other test in this suite uses `Library(url: nil)` — in memory —
    /// which proves nothing about data actually reaching disk and never
    /// exercises the `#Unique` upsert path against a real SQLite file. This
    /// writes through one `Library`, releases it, opens a second `Library` at
    /// the same URL, and reads the data back.
    @Test("Saved and Recent survive closing and reopening the store on disk")
    func onDiskRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-round-trip-\(UUID().uuidString).store")
        let directory = url.deletingLastPathComponent()
        let walURL = directory.appendingPathComponent(url.lastPathComponent + "-wal")
        let shmURL = directory.appendingPathComponent(url.lastPathComponent + "-shm")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
        }

        do {
            let library = try Library(url: url)
            try await library.save(bukhari1)
            await library.recordView(muslim1)
        }

        let reopened = try Library(url: url)
        #expect(try await reopened.saved() == [bukhari1])
        #expect(try await reopened.recent() == [muslim1])
    }

    /// The app must survive a library that will not open. Search and browsing
    /// have nothing to do with favourites and must not be able to fail with them.
    @Test("A corpus built without a library still works")
    func libraryIsOptional() async throws {
        let corpus = try TestFixtures.corpus()
        // The shared fixture is built with libraryURL: nil.
        #expect(corpus.library == nil)
        #expect(corpus.hadithCount == 47_442)
        #expect(try await corpus.store.hadith(slug: "sahih-al-bukhari", number: "1") != nil)
    }

    /// This is the test that fails if `library = libraryURL.flatMap { try?
    /// Library(url: $0) }` in `Corpus.init` ever becomes `try`. Unlike
    /// `libraryIsOptional` above, this gives `Corpus` a *non-nil* `libraryURL`
    /// that `ModelContainer` cannot open — a directory, not a file — so the
    /// `try?` swallow path is actually exercised. `Corpus.init` must not throw,
    /// `library` must come back nil, and the rest of the corpus must still work.
    @Test("A corpus survives a library URL that cannot be opened")
    func libraryFailureIsSwallowed() async throws {
        let unopenable = FileManager.default.temporaryDirectory

        let corpus = try TestFixtures.corpus(libraryURL: unopenable)

        #expect(corpus.library == nil)
        #expect(corpus.hadithCount == 47_442)
        #expect(try await corpus.store.hadith(slug: "sahih-al-bukhari", number: "1") != nil)
    }
}
