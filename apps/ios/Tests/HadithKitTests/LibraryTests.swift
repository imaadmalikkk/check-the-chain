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

    @Test("Clearing history leaves the starred list alone")
    func clearRecentKeepsSaved() async throws {
        let library = try Library(url: nil)
        try await library.save(bukhari1)
        await library.recordView(bukhari1)

        try await library.clearRecent()

        #expect(try await library.recent().isEmpty)
        #expect(try await library.saved() == [bukhari1])
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
}
