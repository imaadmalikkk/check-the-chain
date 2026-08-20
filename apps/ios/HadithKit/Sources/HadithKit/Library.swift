import Foundation
import SwiftData

/// The stable identity of a hadith.
///
/// Deliberately not a row id. `hadith.id` is dense and assigned in canonical
/// order by the pipeline because it doubles as the row index into
/// `embeddings.bin`, so adding a single collection renumbers every row after it.
/// A saved row id would then silently point at a different narration after the
/// next pipeline run — no crash, no error, just the wrong scripture. The
/// collection slug and hadith number are what the corpus, the `Route` cases and
/// the web app's URLs all key on, and they do not move.
public struct HadithRef: Hashable, Sendable, Codable {
    public let collectionSlug: String
    public let number: String

    public init(collectionSlug: String, number: String) {
        self.collectionSlug = collectionSlug
        self.number = number
    }
}

@Model
final class SavedHadith {
    #Unique<SavedHadith>([\.collectionSlug, \.number])

    var collectionSlug: String = ""
    var number: String = ""
    var savedAt: Date = Date.distantPast

    init(ref: HadithRef, savedAt: Date) {
        self.collectionSlug = ref.collectionSlug
        self.number = ref.number
        self.savedAt = savedAt
    }

    var ref: HadithRef { HadithRef(collectionSlug: collectionSlug, number: number) }
}

@Model
final class ViewedHadith {
    #Unique<ViewedHadith>([\.collectionSlug, \.number])

    var collectionSlug: String = ""
    var number: String = ""
    var viewedAt: Date = Date.distantPast

    init(ref: HadithRef, viewedAt: Date) {
        self.collectionSlug = ref.collectionSlug
        self.number = ref.number
        self.viewedAt = viewedAt
    }

    var ref: HadithRef { HadithRef(collectionSlug: collectionSlug, number: number) }
}

/// What the app remembers between launches, and the only place it can lose user
/// data. It lives in the package rather than the app target so it is reachable
/// from `HadithKitTests` — the one stateful thing in the product should not also
/// be the one thing with no unit tests.
///
/// `@ModelActor` rather than a hand-written actor: `ModelContext` is not
/// `Sendable`, and the macro exists to bind a context to an actor's executor.
/// It generates `init(modelContainer:)`, so the URL-taking initialiser below is
/// a convenience that builds the container first.
@ModelActor
public actor Library {
    /// Public because it is the default value of a public parameter, which has
    /// to be resolvable at every call site.
    public static let recentCap = 100

    /// `url` of nil gives an in-memory store, which is what the tests use.
    public init(url: URL?) throws {
        let configuration = if let url {
            ModelConfiguration(url: url)
        } else {
            ModelConfiguration(isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(
            for: SavedHadith.self, ViewedHadith.self,
            configurations: configuration
        )
        self.init(modelContainer: container)
    }

    // MARK: - Saved

    public func isSaved(_ ref: HadithRef) throws -> Bool {
        try existing(ref) != nil
    }

    /// Returns the new state.
    public func toggleSaved(_ ref: HadithRef) throws -> Bool {
        if let row = try existing(ref) {
            modelContext.delete(row)
            try modelContext.save()
            return false
        }
        try save(ref)
        return true
    }

    /// Idempotent by construction: `#Unique` turns a colliding insert into an
    /// update, so this refreshes `savedAt` rather than adding a second row.
    ///
    /// That refresh is user-visible: calling this on a ref that is already
    /// saved does not no-op, it bumps `savedAt` to now, which jumps that
    /// entry to the top of `saved()`'s newest-first order. Harmless when the
    /// caller only cares whether the ref ends up saved — which is the case in
    /// `SavedMenu`, where "Save" is always offered even on an already-saved
    /// row and tapping it there is a deliberate no-op on *state* — but worth
    /// knowing before calling this from anywhere that cares about order too.
    public func save(_ ref: HadithRef) throws {
        modelContext.insert(SavedHadith(ref: ref, savedAt: Date()))
        try modelContext.save()
    }

    /// Newest first.
    public func saved() throws -> [HadithRef] {
        let descriptor = FetchDescriptor<SavedHadith>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.ref)
    }

    private func existing(_ ref: HadithRef) throws -> SavedHadith? {
        // `#Predicate` cannot reach through a struct, so the components are
        // bound to locals first.
        let slug = ref.collectionSlug
        let number = ref.number
        var descriptor = FetchDescriptor<SavedHadith>(
            predicate: #Predicate { $0.collectionSlug == slug && $0.number == number }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Removes a single Saved entry. Mirrors `removeRecent` below: the
    /// dangling row's Saved-segment Remove used to call `toggleSaved`,
    /// relying on "it came from `saved()`, so toggling removes it" — correct
    /// only as long as that assumption holds, and structurally the same bug
    /// already fixed on the Recent side. This is the API that lets the Saved
    /// side stop relying on it. A no-op, not an error, if the ref isn't saved.
    public func removeSaved(_ ref: HadithRef) throws {
        guard let row = try existing(ref) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    // MARK: - Recently viewed

    /// Failures are swallowed on purpose. Not logging a view is invisible to
    /// someone who is reading, it cannot corrupt anything they asked for, and an
    /// error here must not interrupt them.
    public func recordView(_ ref: HadithRef) {
        do {
            modelContext.insert(ViewedHadith(ref: ref, viewedAt: Date()))
            try modelContext.save()
            try prune()
        } catch {
            // Not surfaced to the reader — see above — but still logged. An
            // error here can only mean something is wrong with the store
            // itself (e.g. a failed migration), and that should be visible
            // somewhere even though it must never interrupt anyone reading.
            Log.library.error("recordView failed for \(ref.collectionSlug, privacy: .public)/\(ref.number, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Newest first.
    public func recent(limit: Int = Library.recentCap) throws -> [HadithRef] {
        var descriptor = FetchDescriptor<ViewedHadith>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.ref)
    }

    public func clearRecent() throws {
        try modelContext.delete(model: ViewedHadith.self)
        try modelContext.save()
    }

    /// Removes a single Recent entry. A no-op, not an error, if the ref isn't
    /// there — this backs the dangling row's "Remove" action, where the ref is
    /// by definition not resolvable against anything the caller can check first.
    public func removeRecent(_ ref: HadithRef) throws {
        // `#Predicate` cannot reach through a struct, so the components are
        // bound to locals first — same shape as `existing(_:)` above.
        let slug = ref.collectionSlug
        let number = ref.number
        var descriptor = FetchDescriptor<ViewedHadith>(
            predicate: #Predicate { $0.collectionSlug == slug && $0.number == number }
        )
        descriptor.fetchLimit = 1
        guard let row = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    /// Pruned on write rather than on read, so the store cannot grow without
    /// bound on a device whose owner never opens the Recent list.
    private func prune() throws {
        var descriptor = FetchDescriptor<ViewedHadith>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        descriptor.fetchOffset = Library.recentCap
        let stale = try modelContext.fetch(descriptor)
        guard !stale.isEmpty else { return }
        for row in stale { modelContext.delete(row) }
        try modelContext.save()
    }
}
