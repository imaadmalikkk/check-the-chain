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
}
