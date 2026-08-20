# Saved & Recent — design

**Status:** approved, not yet implemented
**Scope:** `apps/ios` only. No pipeline change, no web change.

## Why

The iOS app stores nothing. There is no SwiftData, no `UserDefaults`, no `@AppStorage`; the only `FileManager` use in the whole target is reading bundled resources. Every launch is byte-identical to the last, so there is no "you" in the app — a hadith you verified yesterday is as hard to find today as it was the first time.

This adds the smallest useful version of that: star a hadith, and keep an automatic list of what you opened.

It is also deliberately the *first* of three features chosen for the next phase, because it establishes the persistence layer the other two (a narrator graph, on-device AI answering) will both want, and because it is the only one of the three that is shippable on its own.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Scope | Favourites + recently viewed | Same store, one more entity. Notes and folders were considered and cut; both are additive later. |
| Sync | **Local only** | The target has no network code and that is a headline property of the product. A store in Application Support is included in iOS device backups, so favourites survive getting a new phone; what is given up is live iPhone↔iPad sync. |
| Where the store lives | **A new `Library` actor inside HadithKit** | The project's rule is logic in HadithKit, pixels in the app. HadithKit is where the test target can reach, and this is the only part of the app that can lose user data — it should not be the one part with no unit tests. SwiftData is iOS 17+, so HadithKit's iOS 18 floor and the documented iOS 18 backport are unaffected. |
| Surface | A sheet from a toolbar icon | Matches the reference designs, which put secondary surfaces behind top-bar icons. A fourth tab was rejected: with `Tab(role: .search)` active, iOS 26 folds the whole tab group behind one collapsed button, and adding an item makes that worse. |
| Identity | `(collection_slug, hadith_number)` | See below. This is the single most important decision in the document. |

### Identity must not be the row id

`hadith.id` is assigned by the pipeline in canonical order (`collection_slug`, `order`, `hadith_number`) and is dense, because it doubles as the row index into `embeddings.bin`. **Adding one collection renumbers every row after it.** Favourites keyed on row id would therefore silently repoint at different narrations on the next `npm run pipeline` — no crash, no error, just the wrong scripture attached to the user's saved list.

The key is the stable natural key `(collection_slug, hadith_number)`, which is also what `HadithStore.hadith(slug:number:)`, the `Route` cases, and the web app's URLs already use.

Nothing is snapshotted. The corpus is bundled, so the text is always available locally, and a stored copy could only ever go stale against a corpus rebuild.

## Non-goals

Notes on saved hadith. Folders or tags. iCloud/CloudKit sync. Manual reordering. Export. A general settings screen. Reading position within a chapter.

## Data model

New file: `HadithKit/Sources/HadithKit/Library.swift`.

```swift
/// The stable identity of a hadith: never a row id. See "Identity" above.
public struct HadithRef: Hashable, Sendable, Codable {
    public let collectionSlug: String
    public let number: String
}

@Model final class SavedHadith {
    #Unique<SavedHadith>([.collectionSlug, .number])
    var collectionSlug: String
    var number: String
    var savedAt: Date
}

@Model final class ViewedHadith {
    #Unique<ViewedHadith>([.collectionSlug, .number])
    var collectionSlug: String
    var number: String
    var viewedAt: Date
}
```

`#Unique` is load-bearing rather than defensive. SwiftData turns an insert that collides with a unique constraint into an update, so re-opening a hadith updates its `viewedAt` instead of appending a duplicate — that *is* the dedupe logic for Recent, and there is no separate fetch-then-branch to get wrong. Un-starring stays an explicit delete.

Both models are internal. `HadithRef` is the only type that crosses the package boundary, so the SwiftData schema is free to change without touching the app.

## API

```swift
@ModelActor
public actor Library {
    /// `url: nil` gives an in-memory store, which is what the tests use.
    public static func container(url: URL?) throws -> ModelContainer
    public convenience init(url: URL?) throws

    public func isSaved(_ ref: HadithRef) -> Bool
    /// Returns the new state.
    public func toggleSaved(_ ref: HadithRef) -> Bool
    /// Newest first.
    public func saved() -> [HadithRef]

    public func recordView(_ ref: HadithRef)
    /// Newest first.
    public func recent(limit: Int = Library.recentCap) -> [HadithRef]
    public func clearRecent()

    /// Public because it is the default value of a public parameter, which has
    /// to be resolvable at every call site.
    public static let recentCap = 100
}
```

`@ModelActor` rather than a hand-written actor: `ModelContext` is not `Sendable`, and the macro exists precisely to bind a context to an actor's executor. It generates `init(modelContainer:)`, so the `url`-taking initialiser is a convenience that builds the container first.

`recordView` prunes inside itself — upsert, then delete anything beyond the newest `recentCap`. Pruning at write time rather than read time means the store cannot grow without bound on a device that is never opened to the Recent list.

### One addition to `HadithStore`

```swift
public func hadith(refs: [HadithRef]) async throws -> [HadithRef: Hadith]
```

Mirrors the existing `hadith(ids:)`, which also returns a dictionary and leaves ordering to the caller. Resolving a saved list one `hadith(slug:number:)` call at a time would be up to hundreds of sequential actor hops and read transactions for a single screen.

Implementation: one query per chunk of 200 refs, predicate built from OR-joined `(collection_slug = ? AND hadith_number = ?)` pairs. 200 pairs is 400 bound variables, comfortably inside SQLite's default 999 limit, and Saved is unbounded so chunking is required rather than theoretical.

## Integration

- `Corpus` gains `public let library: Library?`, built from a URL in Application Support (created if absent).
- `HadithDetailView.task` calls `recordView(ref)`, unless the history preference is off. The preference is owned by the app target as `@AppStorage` and `Library` knows nothing about it — the app simply does not call `recordView`. Keeping the switch out of the package means the store has one job and the tests do not have to set up a preference to exercise it.
- `HadithDetailView` toolbar gains a star beside the existing share button.
- `HadithCard` gains a context menu — long-press to Save / Remove — so a result can be starred without opening it. No star drawn *on* the card: that is a glyph on every row for a state that is false almost always.
- A shared `savedToolbar(library:)` modifier puts the bookmark icon on all three tab roots, so the list is reachable from wherever you are rather than only from the launch screen.
- The sheet has two segments, Saved and Recent, and an overflow menu carrying **Clear history** and a **Record history** toggle (`@AppStorage`, default on).

The history controls live in the sheet's overflow menu rather than in a settings screen, because the app has no settings screen and adding one is out of scope. They are placed where the thing they control is visible.

### Why a history switch at all

Reading history in a religious app is sensitive. Someone researching a ruling on a shared iPad may not want a log of it sitting on the device. Local-only storage covers most of that concern, but the ability to clear the log and to stop writing it is the part the user should control rather than infer.

## Error handling

- **A dangling ref renders as a row, not a gap.** If a future corpus renumbers or drops a hadith, `hadith(refs:)` returns no entry for it; the sheet shows the reference with "no longer in this corpus" and an action to remove it. Silently dropping unresolvable refs is how a user loses saved items without ever learning they had them.
- **`Corpus.library` is optional and nothing else depends on it.** If the `ModelContainer` fails to open, the property is nil, the bookmark icon and the star hide, `recordView` is never called, and the app behaves exactly as it does today. A corrupt favourites store must not be able to take down search or the corpus.
- **`recordView` failures are swallowed.** Failing to log a view is not worth surfacing to someone who is reading, and it cannot corrupt anything the user asked for.
- **`toggleSaved` failures are surfaced.** That one *was* asked for, so it must not appear to succeed silently.

## Testing

`HadithKitTests`, in-memory container, alongside the existing suites:

- `toggleSaved` round-trips, and reports the new state correctly both ways.
- Saving the same ref twice leaves one row — proves `#Unique` and therefore the whole dedupe story.
- Re-viewing a hadith reorders Recent rather than duplicating it.
- Recent prunes at `recentCap`, asserted at cap + 1.
- `clearRecent` empties Recent and leaves Saved untouched.
- A ref that is not in the corpus resolves to no entry rather than throwing.
- `hadith(refs:)` chunking is exercised with more than 200 refs.

`CheckTheChainUITests`, one test:

- Star Bukhari 1, open the sheet, assert it is listed, **terminate the app, relaunch**, assert it is still listed.

That last one is the point. A favourites feature can pass every in-process test and still lose everything on cold launch, and no other test in the suite would notice.

## Consequences for the docs

`apps/ios/README.md` currently states that the target has no network code and that the app stores nothing. The first stays true and should be reasserted deliberately as the reason CloudKit was declined. The second becomes false and needs replacing with a short section on the library, the natural-key decision, and the backup behaviour that stands in for sync.
