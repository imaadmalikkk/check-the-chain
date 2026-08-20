# Saved & Recent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let someone star a hadith and see an automatic list of what they opened, stored on-device only.

**Architecture:** A SwiftData-backed `Library` actor inside the HadithKit package stores `HadithRef` values — `(collection_slug, hadith_number)` pairs, never row ids. The app resolves those refs back to hadith through a new batched `HadithStore.hadith(refs:)` and presents them in a sheet reached from a toolbar icon on all three tab roots. Nothing in the app depends on the library existing: if its store fails to open, `Corpus.library` is nil and the app is exactly what it is today.

**Tech Stack:** Swift 6 (strict concurrency), SwiftData, GRDB 7, SwiftUI (iOS 26), swift-testing for engine tests, XCTest/XCUITest for UI.

## Global Constraints

- Favourites are keyed on `(collection_slug, hadith_number)`. **Never on `hadith.id`** — row ids are dense and reassigned in canonical order by the pipeline because they double as row indexes into `embeddings.bin`, so adding one collection renumbers everything after it.
- No network code. Local storage only, no CloudKit, no iCloud entitlement.
- HadithKit targets iOS 18 / macOS 15 (`HadithKit/Package.swift`). SwiftData is iOS 17+, so this floor does not move.
- HadithKit stays UI-free. No `import SwiftUI` anywhere in `HadithKit/Sources`.
- `SWIFT_STRICT_CONCURRENCY: complete`. Everything crossing an isolation boundary is `Sendable`.
- Engine tests use swift-testing (`@Suite` / `@Test` / `#expect`), matching `Tests/HadithKitTests/EngineTests.swift`. UI tests use XCTest.
- Run `xcodegen generate` from `apps/ios` after adding any source file, before building.
- All commands below run from `apps/ios` unless stated otherwise.
- Test destination: `-destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro'`

---

### Task 1: `HadithRef` and saved-hadith storage

**Files:**
- Create: `apps/ios/HadithKit/Sources/HadithKit/Library.swift`
- Create: `apps/ios/Tests/HadithKitTests/LibraryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct HadithRef: Hashable, Sendable, Codable` with `public let collectionSlug: String`, `public let number: String`, and `public init(collectionSlug: String, number: String)`
  - `public actor Library` with `public init(url: URL?) throws`, `public func isSaved(_ ref: HadithRef) throws -> Bool`, `public func toggleSaved(_ ref: HadithRef) throws -> Bool` (returns the new state), `public func saved() throws -> [HadithRef]`
  - `public static let recentCap = 100` on `Library`

- [ ] **Step 1: Write the failing test**

Create `apps/ios/Tests/HadithKitTests/LibraryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd apps/ios && xcodegen generate && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/LibraryTests 2>&1 | grep -E "error:|✘|Test run"
```

Expected: compile failure — `cannot find 'Library' in scope` and `cannot find 'HadithRef' in scope`.

- [ ] **Step 3: Write the implementation**

Create `apps/ios/HadithKit/Sources/HadithKit/Library.swift`:

```swift
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
    public static let schema: [any PersistentModel.Type] = [SavedHadith.self]

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
            for: SavedHadith.self,
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
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/ios && xcodegen generate && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/LibraryTests 2>&1 | grep -E "error:|✘|✔|Test run"
```

Expected: three passing tests.

If `savedOrdering` is flaky, two saves in the same millisecond are tying on `savedAt`. Fix by making the test await a 10ms sleep between saves, not by loosening the assertion — the ordering is real behaviour.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/HadithKit/Sources/HadithKit/Library.swift apps/ios/Tests/HadithKitTests/LibraryTests.swift
git commit -m "feat(ios): store starred hadith, keyed on slug and number"
```

---

### Task 2: Recently viewed, with pruning

**Files:**
- Modify: `apps/ios/HadithKit/Sources/HadithKit/Library.swift`
- Modify: `apps/ios/Tests/HadithKitTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `HadithRef`, `Library`, `Library.recentCap` from Task 1.
- Produces: `public func recordView(_ ref: HadithRef)` (non-throwing, swallows failures), `public func recent(limit: Int = Library.recentCap) throws -> [HadithRef]`, `public func clearRecent() throws`

- [ ] **Step 1: Write the failing tests**

Append to `apps/ios/Tests/HadithKitTests/LibraryTests.swift`, inside `LibraryTests`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd apps/ios && xcodegen generate && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/LibraryTests 2>&1 | grep -E "error:|✘|Test run"
```

Expected: compile failure — no `recordView`, `recent` or `clearRecent`.

- [ ] **Step 3: Write the implementation**

In `Library.swift`, add the model beneath `SavedHadith`:

```swift
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
```

Update the schema and container in `init(url:)` to include it:

```swift
    public static let schema: [any PersistentModel.Type] = [SavedHadith.self, ViewedHadith.self]
```

```swift
        let container = try ModelContainer(
            for: SavedHadith.self, ViewedHadith.self,
            configurations: configuration
        )
```

Add a `// MARK: - Recently viewed` section to the actor:

```swift
    /// Failures are swallowed on purpose. Not logging a view is invisible to
    /// someone who is reading, it cannot corrupt anything they asked for, and an
    /// error here must not interrupt them.
    public func recordView(_ ref: HadithRef) {
        do {
            modelContext.insert(ViewedHadith(ref: ref, viewedAt: Date()))
            try modelContext.save()
            try prune()
        } catch {
            // Intentionally ignored — see above.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/ios && xcodegen generate && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/LibraryTests 2>&1 | grep -E "error:|✘|✔|Test run"
```

Expected: six passing tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/HadithKit/Sources/HadithKit/Library.swift apps/ios/Tests/HadithKitTests/LibraryTests.swift
git commit -m "feat(ios): record recently viewed hadith, capped at 100"
```

---

### Task 3: Resolve refs back to hadith in one query

**Files:**
- Modify: `apps/ios/HadithKit/Sources/HadithKit/HadithStore.swift` (add after `hadith(ids:)`, which ends at line 65; add the chunking helper beside `databaseQuestionMarks` at the end of the file)
- Modify: `apps/ios/Tests/HadithKitTests/EngineTests.swift` (add to the `StoreTests` suite)

**Interfaces:**
- Consumes: `HadithRef` from Task 1.
- Produces: `public func hadith(refs: [HadithRef]) async throws -> [HadithRef: Hadith]` on `HadithStore`

- [ ] **Step 1: Write the failing tests**

Add inside `@Suite("Store") struct StoreTests` in `apps/ios/Tests/HadithKitTests/EngineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd apps/ios && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/StoreTests 2>&1 | grep -E "error:|✘|Test run"
```

Expected: compile failure — no `hadith(refs:)`.

- [ ] **Step 3: Write the implementation**

In `HadithStore.swift`, after `hadith(ids:)`:

```swift
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

            var arguments: [DatabaseValueConvertible] = []
            arguments.reserveCapacity(chunk.count * 2)
            for ref in chunk {
                arguments.append(ref.collectionSlug)
                arguments.append(ref.number)
            }

            let rows: [Hadith] = try await dbQueue.read { db in
                try Hadith.fetchAll(
                    db,
                    sql: "\(Self.selectColumns) WHERE \(predicate)",
                    arguments: StatementArguments(arguments)
                )
            }
            for row in rows {
                found[HadithRef(collectionSlug: row.collectionSlug, number: row.number)] = row
            }
        }
        return found
    }
```

At the end of the file, beside `databaseQuestionMarks`:

```swift
extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/ios && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/StoreTests 2>&1 | grep -E "error:|✘|✔|Test run"
```

Expected: all `StoreTests` pass, including the two new ones.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/HadithKit/Sources/HadithKit/HadithStore.swift apps/ios/Tests/HadithKitTests/EngineTests.swift
git commit -m "feat(ios): batch-resolve hadith refs, chunked for SQLite's variable limit"
```

---

### Task 4: Hang the library off `Corpus`

**Files:**
- Modify: `apps/ios/HadithKit/Sources/HadithKit/Corpus.swift`
- Modify: `apps/ios/Tests/HadithKitTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `Library` from Tasks 1–2.
- Produces: `public let library: Library?` on `Corpus`; `Corpus.init(databaseURL:embeddingsURL:embeddingsMetadataURL:modelURL:vocabularyURL:libraryURL:)` with `libraryURL: URL?`; `public static func defaultLibraryURL() -> URL?` on `Corpus`

- [ ] **Step 1: Write the failing test**

Add to `LibraryTests` in `apps/ios/Tests/HadithKitTests/LibraryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/ios && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests/LibraryTests 2>&1 | grep -E "error:|✘|Test run"
```

Expected: compile failure — `value of type 'Corpus' has no member 'library'`.

- [ ] **Step 3: Write the implementation**

In `Corpus.swift`, add the property and extend both initialisers:

```swift
    public let store: HadithStore
    public let engine: SearchEngine
    public let embedder: Embedder
    /// Nil when the store could not be opened. Nothing else in the app depends
    /// on it, so a broken favourites store costs favourites and nothing more.
    public let library: Library?
```

```swift
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
        // corpus that refuses to open because of the library is not.
        library = libraryURL.flatMap { try? Library(url: $0) }
    }
```

In the `convenience init(bundle:)`, add the parameter and pass it through:

```swift
    public convenience init(bundle: Bundle = .main, libraryURL: URL? = Corpus.defaultLibraryURL()) throws {
```

```swift
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
```

In `apps/ios/Tests/HadithKitTests/TestFixtures.swift`, make the shared corpus library-free so tests never write into the app container:

```swift
    /// `libraryURL: nil` — the engine tests must not create or mutate a real
    /// favourites store in the app's container.
    private static let sharedCorpus = Result { try Corpus(bundle: .main, libraryURL: nil) }
```

- [ ] **Step 4: Run the full engine suite to verify nothing regressed**

```bash
cd apps/ios && xcodebuild test \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -only-testing:HadithKitTests 2>&1 | grep -E "error:|✘|✔|Test run"
```

Expected: every suite passes — Store, Query handling, Reciprocal rank fusion, Tokenizer, Golden parity, Narrator names, Performance, Library. Golden parity must still pass; if it does not, the change touched search, which it should not have.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/HadithKit/Sources/HadithKit/Corpus.swift apps/ios/Tests/HadithKitTests/
git commit -m "feat(ios): expose an optional library on Corpus"
```

---

### Task 5: Star the hadith you're reading, and log that you read it

**Files:**
- Modify: `apps/ios/CheckTheChain/Views/HadithDetailView.swift`

**Interfaces:**
- Consumes: `Library`, `HadithRef`, `Corpus.library`.
- Produces: `AppStorageKey.recordsHistory` — the string literal `"recordsHistory"`, used again in Task 7.

- [ ] **Step 1: Add the state and the ref**

In `struct HadithDetailView`, beside `@State private var hadith: Hadith?`:

```swift
    @State private var isSaved = false
    /// Default on. Someone who wants no reading history can turn it off in the
    /// library sheet; see Task 7.
    @AppStorage("recordsHistory") private var recordsHistory = true

    private var ref: HadithRef { HadithRef(collectionSlug: slug, number: number) }
```

- [ ] **Step 2: Record the view and load the saved state**

Replace the existing `.task` on the `ScrollView`:

```swift
        .task {
            hadith = try? await corpus.store.hadith(slug: slug, number: number)
            guard let library = corpus.library else { return }
            isSaved = (try? await library.isSaved(ref)) ?? false
            if recordsHistory {
                await library.recordView(ref)
            }
        }
```

- [ ] **Step 3: Add the star to the toolbar**

Replace the existing `.toolbar` block:

```swift
        .toolbar {
            if let hadith {
                if corpus.library != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await toggleSaved() }
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        }
                        .accessibilityLabel(isSaved ? "Remove from saved" : "Save")
                        .accessibilityIdentifier("saveToggle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(hadith)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
```

Add the method to `HadithDetailView`:

```swift
    /// Unlike `recordView`, a failure here has to be visible: the reader asked
    /// for this, so it must not appear to have worked when it did not.
    private func toggleSaved() async {
        guard let library = corpus.library else { return }
        do {
            isSaved = try await library.toggleSaved(ref)
        } catch {
            isSaved = (try? await library.isSaved(ref)) ?? isSaved
        }
    }
```

- [ ] **Step 4: Build and check it by hand**

```bash
cd apps/ios && xcodegen generate && xcodebuild build \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData 2>&1 | grep -E "error:|BUILD"
xcrun simctl install "iPhone 17 Pro" DerivedData/Build/Products/Debug-iphonesimulator/CheckTheChain.app
xcrun simctl launch "iPhone 17 Pro" com.checkthechain.app
```

Expected: BUILD SUCCEEDED. Open any hadith; the bookmark outlines and fills as it is tapped, and stays filled when the screen is left and reopened.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/CheckTheChain/Views/HadithDetailView.swift
git commit -m "feat(ios): star a hadith from its detail page"
```

---

### Task 6: Star from a list without opening it

**Files:**
- Create: `apps/ios/CheckTheChain/Views/SavedMenu.swift`
- Modify: `apps/ios/CheckTheChain/Views/SearchView.swift` (the `NavigationLink` inside `content(_:)`)
- Modify: `apps/ios/CheckTheChain/Views/BrowseView.swift` (the `NavigationLink` inside `ChapterView.body`)

**Interfaces:**
- Consumes: `Library`, `HadithRef`.
- Produces: `func savedMenu(ref: HadithRef, library: Library?) -> some View` — a `View` extension.

- [ ] **Step 1: Write the modifier**

Create `apps/ios/CheckTheChain/Views/SavedMenu.swift`:

```swift
import SwiftUI
import HadithKit

/// Long-press a result to star it.
///
/// A modifier applied where cards are used, rather than a parameter on
/// `HadithCard`. The card stays a pure function of a hadith and knows nothing
/// about persistence, and the two call sites that need this opt in.
///
/// No star is drawn *on* the card. That would put a glyph on every row for a
/// state that is false almost always.
private struct SavedMenu: ViewModifier {
    let ref: HadithRef
    let library: Library?

    @State private var isSaved = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if library != nil {
                    Button {
                        Task { await toggle() }
                    } label: {
                        Label(
                            isSaved ? "Remove from Saved" : "Save",
                            systemImage: isSaved ? "bookmark.slash" : "bookmark"
                        )
                    }
                }
            }
            .task {
                guard let library else { return }
                isSaved = (try? await library.isSaved(ref)) ?? false
            }
    }

    private func toggle() async {
        guard let library else { return }
        isSaved = (try? await library.toggleSaved(ref)) ?? isSaved
    }
}

extension View {
    func savedMenu(ref: HadithRef, library: Library?) -> some View {
        modifier(SavedMenu(ref: ref, library: library))
    }
}
```

- [ ] **Step 2: Apply it in search results**

In `SearchView.content(_:)`, the `ForEach` body currently reads:

```swift
                ForEach(model.visibleResults) { result in
                    NavigationLink(value: Route.hadith(result.hadith.collectionSlug, result.hadith.number)) {
                        HadithCard(hadith: result.hadith, query: model.query, score: result.score)
                    }
                    .buttonStyle(.plain)
                }
```

Add the modifier after `.buttonStyle(.plain)`:

```swift
                    .savedMenu(
                        ref: HadithRef(
                            collectionSlug: result.hadith.collectionSlug,
                            number: result.hadith.number
                        ),
                        library: corpus.library
                    )
```

- [ ] **Step 3: Apply it in a chapter listing**

In `ChapterView.body`, after the `.buttonStyle(.plain)` on the `NavigationLink` wrapping `HadithCard(hadith: item)`:

```swift
                    .savedMenu(
                        ref: HadithRef(collectionSlug: item.collectionSlug, number: item.number),
                        library: corpus.library
                    )
```

- [ ] **Step 4: Build and check by hand**

```bash
cd apps/ios && xcodegen generate && xcodebuild build \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED. Long-press a search result: a Save item appears; long-press again after saving and it reads Remove from Saved.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/CheckTheChain/Views/SavedMenu.swift apps/ios/CheckTheChain/Views/SearchView.swift apps/ios/CheckTheChain/Views/BrowseView.swift
git commit -m "feat(ios): star a hadith from a result list via long-press"
```

---

### Task 7: The Saved & Recent sheet, and the way in

**Files:**
- Create: `apps/ios/CheckTheChain/Views/LibraryView.swift`
- Modify: `apps/ios/CheckTheChain/Views/SearchView.swift`
- Modify: `apps/ios/CheckTheChain/Views/TodayView.swift`
- Modify: `apps/ios/CheckTheChain/Views/BrowseView.swift` (`BrowseView.body` only, not `CollectionView` or `ChapterView`)

**Interfaces:**
- Consumes: `Library`, `HadithRef`, `HadithStore.hadith(refs:)`, `HadithCard`, `Palette`, `Radius`, `RowDivider`, `Route`, the `"recordsHistory"` key from Task 5.
- Produces: `struct LibraryView: View` with `init(corpus: Corpus)`; `func libraryToolbar(corpus: Corpus) -> some View` — a `View` extension.

- [ ] **Step 1: Write the sheet**

Create `apps/ios/CheckTheChain/Views/LibraryView.swift`:

```swift
import SwiftUI
import HadithKit

/// What the app remembers: what you starred, and what you opened.
///
/// A sheet behind a toolbar icon rather than a fourth tab. With
/// `Tab(role: .search)` active, iOS 26 folds the whole tab group behind one
/// collapsed button, so a fourth item would make an existing problem worse.
struct LibraryView: View {
    let corpus: Corpus

    private enum Segment: String, CaseIterable, Identifiable {
        case saved = "Saved"
        case recent = "Recent"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("recordsHistory") private var recordsHistory = true

    @State private var segment: Segment = .saved
    @State private var refs: [HadithRef] = []
    @State private var resolved: [HadithRef: Hadith] = [:]
    @State private var isLoading = true
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Palette.ground)
                .navigationTitle(segment.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) { overflow }
                }
                .safeAreaInset(edge: .top) { picker }
        }
        .task(id: segment) { await reload() }
    }

    private var picker: some View {
        Picker("View", selection: $segment) {
            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The history controls live here rather than in a settings screen, because
    /// there is no settings screen and this is where the thing they control is.
    private var overflow: some View {
        Menu {
            Toggle("Record history", isOn: $recordsHistory)
            Button("Clear history", systemImage: "trash", role: .destructive) {
                Task {
                    try? await corpus.library?.clearRecent()
                    await reload()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityIdentifier("libraryOverflow")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        } else if refs.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(refs, id: \.self) { ref in
                        row(ref)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableWidth()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private func row(_ ref: HadithRef) -> some View {
        if let hadith = resolved[ref] {
            NavigationLink(value: Route.hadith(ref.collectionSlug, ref.number)) {
                HadithCard(hadith: hadith)
            }
            .buttonStyle(.plain)
        } else {
            dangling(ref)
        }
    }

    /// A saved hadith the corpus no longer has — renumbered or dropped by a
    /// later pipeline run. Shown rather than skipped: silently dropping refs is
    /// how someone loses saved items without ever learning they had them.
    private func dangling(_ ref: HadithRef) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(HadithCollection.named(slug: ref.collectionSlug)?.name ?? ref.collectionSlug) \(ref.number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("No longer in this corpus.")
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
            Button("Remove") {
                Task {
                    _ = try? await corpus.library?.toggleSaved(ref)
                    await reload()
                }
            }
            .font(.caption.weight(.medium))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(
                segment == .saved ? "Nothing saved yet" : "Nothing read yet",
                systemImage: segment == .saved ? "bookmark" : "clock"
            )
        } description: {
            Text(segment == .saved
                 ? "Tap the bookmark on any hadith to keep it here."
                 : "Hadith you open will appear here.")
        }
        .padding(.top, 40)
    }

    private func reload() async {
        guard let library = corpus.library else {
            refs = []
            isLoading = false
            return
        }
        isLoading = true
        let next = switch segment {
        case .saved: (try? await library.saved()) ?? []
        case .recent: (try? await library.recent()) ?? []
        }
        resolved = (try? await corpus.store.hadith(refs: next)) ?? [:]
        refs = next
        isLoading = false
    }
}

extension View {
    /// Puts the bookmark icon on a tab root, so the list is reachable from
    /// wherever you are rather than only from the launch screen.
    func libraryToolbar(corpus: Corpus) -> some View {
        modifier(LibraryToolbar(corpus: corpus))
    }
}

private struct LibraryToolbar: ViewModifier {
    let corpus: Corpus
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if corpus.library != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isPresented = true } label: {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Saved and recent")
                        .accessibilityIdentifier("libraryButton")
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                LibraryView(corpus: corpus)
            }
    }
}
```

- [ ] **Step 2: Add the entry points**

In `SearchView.body`, on the `Group` that already carries `.navigationTitle("")`, after `.navigationBarTitleDisplayMode(.inline)`:

```swift
            .libraryToolbar(corpus: corpus)
```

In `TodayView.body`, on the `ScrollView`, after `.navigationBarTitleDisplayMode(.inline)`:

```swift
            .libraryToolbar(corpus: corpus)
```

In `BrowseView.body`, on the `ScrollView`, after `.navigationBarTitleDisplayMode(.inline)`:

```swift
            .libraryToolbar(corpus: corpus)
```

- [ ] **Step 3: Build and walk it by hand**

```bash
cd apps/ios && xcodegen generate && xcodebuild build \
  -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData 2>&1 | grep -E "error:|BUILD"
xcrun simctl install "iPhone 17 Pro" DerivedData/Build/Products/Debug-iphonesimulator/CheckTheChain.app
xcrun simctl launch "iPhone 17 Pro" com.checkthechain.app
```

Expected: BUILD SUCCEEDED. The bookmark icon appears top-right on all three tabs. Star a hadith, open the sheet, and it is under Saved; opening a hadith puts it under Recent; Clear history empties Recent and leaves Saved alone.

- [ ] **Step 4: Confirm the empty states**

Delete and reinstall so the store starts fresh, then open the sheet without saving anything:

```bash
xcrun simctl uninstall "iPhone 17 Pro" com.checkthechain.app
xcrun simctl install "iPhone 17 Pro" DerivedData/Build/Products/Debug-iphonesimulator/CheckTheChain.app
xcrun simctl launch "iPhone 17 Pro" com.checkthechain.app
```

Expected: "Nothing saved yet" on Saved, "Nothing read yet" on Recent — not a blank screen and not a spinner that never stops.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/CheckTheChain/Views/LibraryView.swift apps/ios/CheckTheChain/Views/SearchView.swift apps/ios/CheckTheChain/Views/TodayView.swift apps/ios/CheckTheChain/Views/BrowseView.swift
git commit -m "feat(ios): Saved and Recent sheet, reachable from every tab"
```

---

### Task 8: Prove it survives a cold launch

**Files:**
- Create: `apps/ios/Tests/CheckTheChainUITests/LibraryTests.swift`
- Modify: `apps/ios/scripts/uitest.sh`

**Interfaces:**
- Consumes: the accessibility identifiers `saveToggle` and `libraryButton` from Tasks 5 and 7; `XCUIApplication.tabButton(_:)` from `Tests/CheckTheChainUITests/TabNavigation.swift`.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Create `apps/ios/Tests/CheckTheChainUITests/LibraryTests.swift`:

```swift
import XCTest

/// The only test that proves persistence.
///
/// A favourites feature can pass every in-process unit test and still lose
/// everything on a cold launch — the store never gets written, or gets written
/// somewhere that does not survive the process. Nothing else in the suite would
/// notice, so this terminates the app and starts it again.
final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSavedHadithSurvivesRelaunch() {
        var app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The search canvas never appeared"
        )

        // Bukhari 1 is reached through Browse, which is a known-stable path.
        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari"].waitForExistence(timeout: 10))
        app.staticTexts["Sahih al-Bukhari"].tap()
        XCTAssertTrue(app.staticTexts["Revelation"].waitForExistence(timeout: 10))
        app.staticTexts["Revelation"].tap()
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 10))
        app.staticTexts["Sahih al-Bukhari 1"].tap()

        let star = app.buttons["saveToggle"]
        XCTAssertTrue(star.waitForExistence(timeout: 10), "No save button on the detail page")
        star.tap()

        app.terminate()

        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The app did not come back up"
        )

        let library = app.buttons["libraryButton"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "No library button after relaunch")
        library.tap()

        XCTAssertTrue(
            app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 15),
            "The starred hadith did not survive a cold launch"
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails against a fresh install**

```bash
cd apps/ios && xcodegen generate
xcrun simctl uninstall "iPhone 17 Pro" com.checkthechain.app || true
xcodebuild test -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData \
  -only-testing:CheckTheChainUITests/LibraryUITests 2>&1 | grep -E "error:|Test Case.*(passed|failed)|XCTAssert"
```

Expected before Tasks 5 and 7 land: failure at `No save button on the detail page`. After them: PASS. If it is being run after those tasks, confirm it fails for the right reason by temporarily commenting out the `star.tap()` line — the final assertion must then fail.

- [ ] **Step 3: Add it to the matrix**

In `apps/ios/scripts/uitest.sh`, after the `testLongestAttribution` line:

```bash
# Persistence has to be checked on a clean install, or a store left behind by a
# previous run makes the test pass without proving anything.
xcrun simctl uninstall "$DEVICE" com.checkthechain.app 2>/dev/null || true
run_suite "$DEVICE" light medium CheckTheChainUITests/LibraryUITests
```

- [ ] **Step 4: Run the whole matrix**

```bash
cd apps/ios && ./scripts/uitest.sh 2>&1 | tail -30
```

Expected: six passing configurations — iPhone light, dark, AccessibilityXXXL, longest attribution, library persistence, iPad.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/Tests/CheckTheChainUITests/LibraryTests.swift apps/ios/scripts/uitest.sh
git commit -m "test(ios): starred hadith survive a cold launch"
```

---

### Task 9: Correct the documentation

**Files:**
- Modify: `apps/ios/README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Fix the claim that is now false**

`apps/ios/README.md` opens by saying the target has no backend, no API key and no network code. That stays true and is the reason CloudKit was declined — it should be stated as a decision, not left as an accident. Add a section after **Surfaces**:

```markdown
## What the app remembers

Until recently: nothing. No SwiftData, no `UserDefaults`, no `@AppStorage` — the only `FileManager` use was reading bundled resources, and every launch was identical to the last.

`Library` (in HadithKit) now stores two things locally: hadith you starred, and the last 100 you opened.

- **Keyed on `(collection_slug, hadith_number)`, never on the row id.** Row ids are dense and assigned in canonical order because they double as row indexes into `embeddings.bin`, so adding one collection renumbers everything after it. Saved row ids would silently repoint at different narrations on the next `npm run pipeline` — no crash, just the wrong scripture.
- **Local only, and that is a decision.** CloudKit would give live iPhone↔iPad sync and end the claim at the top of this file. A store in Application Support is included in iOS device backups, so favourites survive a new phone anyway; live sync is what is given up.
- **Nothing depends on it.** `Corpus.library` is optional. If the store will not open, the bookmark icons disappear and the app is exactly what it was before. A corrupt favourites store cannot take down search.
- **A dangling ref renders as a row.** If a later corpus drops or renumbers a hadith, the saved entry says so and offers to remove itself, rather than quietly vanishing.
- **Recent is capped at 100 and pruned on write**, so it cannot grow without bound on a device nobody tidies.

The history log can be cleared, and switched off, from the overflow menu in the sheet. Reading history in a religious app is sensitive: someone researching a ruling on a shared iPad should not have to discover that a log exists.
```

- [ ] **Step 2: Update the architecture summary**

In `CLAUDE.md`, in the `apps/ios` HadithKit bullet list, after the `NarratorName` entry:

```markdown
  - `Library` (`@ModelActor`) — SwiftData store for starred hadith and the last 100 viewed. Keyed on `(collection_slug, hadith_number)`, **never on the row id** — row ids are reassigned by the pipeline. Local only, no CloudKit. `Corpus.library` is optional and nothing else depends on it.
```

- [ ] **Step 3: Check the deferred list is still honest**

`apps/ios/README.md` has a "Not built (deliberately)" section listing "Bookmarks and reading history (SwiftData)". Remove that line — it is built now. Leave the rest.

- [ ] **Step 4: Verify**

```bash
cd /Users/imaadmalik/Developer/hadith-check
grep -n "Bookmarks and reading history" apps/ios/README.md
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /Users/imaadmalik/Developer/hadith-check
git add apps/ios/README.md CLAUDE.md
git commit -m "docs: the app remembers things now"
```

---

## Self-review

**Spec coverage.** Every section of the spec maps to a task: identity decision → Task 1 and the Global Constraints; data model → Tasks 1–2; `Library` API → Tasks 1–2; `hadith(refs:)` → Task 3; `Corpus` integration → Task 4; detail-view star and `recordView` → Task 5; card context menu → Task 6; sheet, segments, overflow menu, toolbar entry points, dangling rows → Task 7; error handling → Tasks 2 (swallowed `recordView`), 4 (optional library), 5 (surfaced toggle), 7 (dangling rows); testing → Tasks 1–3 and 8; docs consequences → Task 9.

**Two refinements against the spec, both deliberate:**
- The spec listed `toggleSaved` as non-throwing but also required its failures to be surfaced. It throws, and Task 5 handles the error by re-reading the true state.
- The spec said "`HadithCard` gains a context menu". Task 6 applies a modifier at the two call sites instead, so `HadithCard` stays a pure function of a hadith. Same behaviour, better boundary.

**Placeholder scan.** No TBDs, no "add error handling", no "similar to Task N". Every code step carries the code.

**Type consistency.** `HadithRef(collectionSlug:number:)` is used identically in Tasks 1, 3, 5, 6, 7, 8. `Library.recentCap` is public and referenced in Tasks 2 and 7. `saved()`, `recent(limit:)`, `clearRecent()`, `toggleSaved(_:)`, `isSaved(_:)`, `save(_:)` and `recordView(_:)` keep their signatures across every task. `"recordsHistory"` is the same literal in Tasks 5 and 7. Identifiers `saveToggle`, `libraryButton` and `libraryOverflow` are declared in Tasks 5 and 7 and consumed in Task 8.
