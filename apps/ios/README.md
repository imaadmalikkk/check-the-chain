# Check the Chain — iOS

A native SwiftUI app for searching 47,442 hadith from 16 collections. **Everything runs on-device.** There is no backend, no API key, and no network code anywhere in this target — the corpus, its embeddings, and the embedding model all ship inside the app.

That is the central design decision, and it buys four things at once:

- **Free to run, permanently.** No server cost that scales with users.
- **Fast.** A full semantic scan of the corpus takes 0.5ms; a warm hybrid search takes ~30ms.
- **Works offline.** In a masjid with no signal, on a plane, anywhere.
- **No leak class.** The web version leaks WASM tensors until Safari OOMs. There is no worker, no WASM heap, and no in-flight request to race here.

## Build

```bash
npm run pipeline                     # from the repo root — builds the offline artifacts (~10 min first time)
cd apps/ios && xcodegen generate
open CheckTheChain.xcodeproj
```

`xcodegen generate` is required after any change to `project.yml` and after adding or removing source files. The `.xcodeproj` is generated and gitignored; **never edit build settings in Xcode's inspector** — the change is lost on the next regeneration.

The app will not build without the pipeline artifacts in `CheckTheChain/Resources/`. That is deliberate: a missing artifact should be a build error, not an app that launches and then can't find its corpus.

```bash
# Engine + parity + performance
xcodebuild test -project CheckTheChain.xcodeproj -scheme CheckTheChain \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' \
  -only-testing:HadithKitTests

# Screens, across appearance / text size / device
./scripts/uitest.sh
```

`uitest.sh` exists because XCTest has no API for the interface style or the
Dynamic Type size — they have to be set on the simulator from outside. It runs
the walkthrough on iPhone and iPad, dark mode, and the largest accessibility
text size, and every screen attaches a screenshot. The appearance tests assert
which appearance actually resolved, so a misconfigured simulator fails loudly
instead of quietly passing in the wrong mode.

Signing is on: `project.yml` sets `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY: "Apple Development"` with `CODE_SIGN_STYLE: Automatic`, and the app has been built and run on a physical iPhone. The first device build needs `-allowProvisioningUpdates` so Xcode can register the bundle ID and issue the profile:

```bash
xcodebuild -scheme CheckTheChain -destination 'platform=iOS,name=<your device>' -allowProvisioningUpdates build
```

Both `HadithKitTests` and `CheckTheChainUITests` set `GENERATE_INFOPLIST_FILE: YES` in `project.yml` — a test bundle has to be code-signed once signing is on, and it cannot be signed without an Info.plist, which nothing generated while signing was off.

## Layout

| Path | What |
|---|---|
| `HadithKit/` | Local SPM package. The search engine, UI-free and independently testable. |
| `CheckTheChain/` | App target — SwiftUI views, design tokens, app state. |
| `CheckTheChain/Resources/` | Pipeline artifacts + fonts. Gitignored except the fonts. |
| `Tests/HadithKitTests/` | Engine tests, hosted by the app so they read the shipping artifacts. |
| `Tests/CheckTheChainUITests/` | Screen-by-screen walkthrough that attaches screenshots. |

## How search works

```
query → BertTokenizer          (BERT-uncased WordPiece, hand-written)
      → Core ML MiniLM          (~10ms; pooling + L2 norm baked into the graph)
      → VectorIndex             (int8 dot products over 47,442 × 384, ~0.5ms)
      ⊕ FTS5 bm25               (~9ms, in parallel)
      → Reciprocal Rank Fusion  (K = 60)
      → results
```

Neither leg is sufficient alone. Keyword search nails verbatim quotes and proper nouns but returns nothing for "what did the prophet say about forgiving people"; vector search handles the paraphrase but drifts on exact citations. RRF fuses them using only rank position, which is what makes it safe to combine two scores that aren't on a common scale.

Both stored and query vectors are L2-normalized, so ranking by the **raw integer dot product** is monotonic in cosine similarity — the quantization scale is a positive constant shared by every row and cancels out of the comparison. It's recorded in `embeddings.json` but never applied to a score.

## Parity is enforced, not assumed

Every piece of the iOS stack substitutes for a piece of the web stack: int8 quantization for Convex's vector index, a hand-written tokenizer for Transformers.js's, FTS5 for Convex's search index, Core ML for ONNX. Each could plausibly be slightly wrong in a way that never crashes and just quietly returns worse hadith.

`Tests/HadithKitTests/Resources/golden.json` holds 30 queries replayed against the **live web app**, with the top ten results it returned and the exact embedding Transformers.js produced for each. `GoldenParityTests` requires the offline engine to reproduce them.

Current numbers:

| Measure | Result |
|---|---|
| Mean top-10 overlap with the web app | **92.0%** |
| Web app's #1 result inside our top 3 | **100%** |
| Worst on-device embedding cosine vs Transformers.js | **0.99998** |

The overlap is not 100% because FTS5 and Convex's search index are genuinely different engines with different ranking; demanding an exact match would be demanding a reimplementation of Convex. What must hold is that the fused set is substantially the same and the strongest hits stay on top.

To regenerate the baseline after a corpus change:

```bash
npm run capture-golden -w @check-the-chain/pipeline
```

## Performance budgets

Asserted by `PerformanceTests`, measured on the simulator — where Core ML has **no Neural Engine** and falls back to CPU, so device numbers can only be better.

| Measure | Budget | Actual |
|---|---|---|
| Vector scan, full corpus | < 5ms | 0.50ms |
| Keyword search | < 50ms | 9.3ms |
| Warm hybrid search, end to end | < 150ms | 27ms |
| Memory growth over 50 searches | < 10MB | +0.8MB |

**HadithKit is compiled with `-O` even in Debug** (`Package.swift`). This is not a micro-optimization: the vector scan runs at 0.5ms optimized and 412ms unoptimized — an 800× difference that decides whether search feels instant or broken. Without it, anyone running the app from Xcode sees the broken version with no way to know it isn't the real one. The app target stays at `-Onone` in Debug so UI code remains debuggable.

## Size

167MB installed, **80MB compressed** — the App Store download. Well inside the over-cellular limit.

| Artifact | Size |
|---|---|
| `hadith.sqlite` | 103MB |
| `MiniLM.mlmodelc` | 43MB |
| `embeddings.bin` | 17MB |
| Everything else | ~4MB |

If this ever needs trimming, the lever is the Arabic column — 48.6MB of the 68.4MB of text — which compresses roughly 4:1 with per-row zlib, at the cost of a decompress on read in the detail view. Not worth doing at 80MB.

## Surfaces

The single most consequential value in the design system is the ground colour. It used to be `#FAFAFA`, which is near-white — and against near-white a white card is invisible, so every card needed a border drawn around it to exist at all. Once every card has a border the screen is a grid of boxes.

The ground is now `#F2F2F3`. A white card is simply *lighter than the page*, so:

- **No borders and no shadows.** A card is a fill and a 22pt radius, nothing else. It does not need to pretend to float. A soft drop shadow under every card is the tell of a design that doesn't trust its own contrast, and next to flat fills it looks cheap.
- **Lists are one surface, not a stack of cards.** Sixteen collections as sixteen separate cards is sixteen objects to look at; one block per group with hairline dividers is a list. Same for the 97 chapters of Bukhari.
- **Both appearances carry their own contrast step.** `Palette.surface` sits a different distance from the ground in light and dark, because that step is now the only thing separating a card from the page.

Colour appears in exactly one place: the grading badge. That is the answer to "is this hadith real", and it is the only thing on screen that earns a hue.

## What the app remembers

Until recently: nothing. No SwiftData, no `UserDefaults`, no `@AppStorage` — the only `FileManager` use was reading bundled resources, and every launch was identical to the last.

`Library` (in HadithKit) now stores two things locally: hadith you starred, and the last 100 you opened.

- **Keyed on `(collection_slug, hadith_number)`, never on the row id.** Row ids are dense and assigned in canonical order because they double as row indexes into `embeddings.bin`, so adding one collection renumbers everything after it. Saved row ids would silently repoint at different narrations on the next `npm run pipeline` — no crash, just the wrong scripture.
- **Local only, and that is a decision.** CloudKit would give live iPhone↔iPad sync and end the claim at the top of this file. A store in Application Support is included in iOS device backups, so favourites survive a new phone anyway; live sync is what is given up.
- **Nothing depends on it.** `Corpus.library` is optional. If the store will not open, the bookmark icons disappear and the app is exactly what it was before. A corrupt favourites store cannot take down search.
- **A dangling ref renders as a row.** If a later corpus drops or renumbers a hadith, the saved entry says so and offers to remove itself, rather than quietly vanishing.
- **Recent is capped at 100 and pruned on write**, so it cannot grow without bound on a device nobody tidies.

The history log can be cleared, and switched off, from the overflow menu in the sheet. Reading history in a religious app is sensitive: someone researching a ruling on a shared iPad should not have to discover that a log exists.

## Liquid Glass

The rule Apple states and most apps break: **glass belongs on controls floating above content, never behind body text.** A blurred backdrop under a paragraph of hadith would look modern and read worse, and reading is the only thing this app does.

- Glass: the tab bar, the search field, filter chips, floating toolbar buttons.
- Not glass: result cards, detail surfaces, anything containing a narration.

All glass routes through a single `glassSurface(in:interactive:)` modifier in `DesignSystem.swift`. That is deliberate — see below.

## The app opens on search

Verifying a hadith someone sent you is what this is for, so launch lands on an almost empty canvas: a wordmark, three example queries, and the search field. With `Tab(role: .search)` the tab bar *is* the search field, so there is one obvious control and nothing else asking for attention.

That has one trap, and it is not documented anywhere obvious: **while the search tab is active, iOS 26 folds the entire tab group behind a single button** whose accessibility value is `Collapsed`. The other tabs are not merely off screen — they are absent from the hierarchy. On a cold launch that made Browse unreachable except by tapping a control that gives no hint of what it holds, which is why the canvas carries its own "Browse 16 collections" link. `XCUIApplication.tabButton(_:)` expands the collapsed group before giving up, for the same reason.

## Arabic typography

Arabic is set in Noto Naskh — the same face the web app loads — and it is the primary text on a hadith page, not decoration. Two things about it are easy to get wrong and were:

- **`leading` and `trailing` resolve against the layout direction.** Inside the right-to-left environment an Arabic block needs, `.leading` is the *right* edge. `arabicText` originally said `.trailing`, which pinned the paragraph to the left and left the ragged edge on the right — the exact inverse of how Arabic sets, and visible as short closing lines drifting away from the margin.
- **Naskh already has tall intrinsic line metrics.** Adding another 0.55em of leading on top pulled the lines so far apart they read as unrelated fragments. It's 0.3em now.

A short name in a list is not a paragraph: `arabicName` keeps the right-to-left base direction so glyphs and punctuation order correctly, but leaves the block flush with the English labels beside it. 95% of narrator names fit on one line, where the distinction doesn't arise.

The detail page is three labelled blocks — reference and grading, **Arabic**, **Translation** — because the Arabic in most collections includes the full sanad while the English translation omits it. Unlabelled and uncarded, the two ran together with only a rule between them and no way to tell where the narration ended.

## The chain, in English

The corpus stores isnad chains **only in Arabic**. There is no English narrator field anywhere upstream and no open dataset maps these 34,317 distinct strings, so `NarratorName` transliterates them on-device rather than looking them up. Two layers:

1. **A lexicon** of the 330 most frequent tokens, spelled the way the English hadith literature spells them — "Shu'ba", "al-Zuhri", "Abu Hurayra". Those 330 tokens are **85% of every token in every chain**, which is what makes a hand-written list worth having: the alternative is rule output for names that already have a settled spelling.
2. **Rules** for the rest — the prefixes Arabic writes joined to the next word (`و` "and", the article `ال`), the structural words that build a name (`ibn`, `Abu`/`Abi`, `Abd al-`), and a letter-by-letter fallback.

The fallback is approximate and can't be otherwise. Arabic writes long vowels and omits short ones, so `قتادة` is literally `q-t-a-d-a`; "Qatada" comes from assuming the missing vowel is *a*. That's right for `منصور` → Mansur, roughly right for `شعبة` → Sha'ba (Shu'ba), and wrong often enough that the screen says so.

### What this exposed, and what it fixed

Rendering the chain in English made a pre-existing data problem visible: the sanad parser was splitting on seven transmission verbs, none of them the conjunction forms Arabic actually writes, so whole clauses survived as "narrators". `قال` ("said") was the 5th most common token in the entire chain corpus. **20.4% of chain links contained something that was not part of a name.**

That is now fixed at the source — see `apps/web/scripts/lib/isnad.ts`. Rebuilt, the numbers are:

| | Before | After |
|---|---|---|
| Chains found | 41,507 | 44,340 |
| Chain links | 199,392 | 238,624 |
| Links containing a non-name token | 20.45% | **0.11%** |
| Distinct tokens across all chains | 11,066 | 5,988 |

The lexicon still carries translations for `قال`, `وحدثنا`, `ح` and the rest. They are close to dead code now, and deliberately kept: the residual 0.11% is mostly `عن` meaning "about" rather than "from", which no split can disambiguate, and a fragment that slips through should still read as a fragment rather than as an invented narrator called "Qal".

## Layout rules the corpus forced

Three constraints came out of looking at real data and real screens rather than from taste:

- **`readableWidth()` on every scroll view.** Unconstrained, a hadith sets at roughly 150 characters per line on a 13" iPad — more than twice the measure at which prose stays readable. Capped at 700pt and centred, mirroring the web app's `max-w-2xl mx-auto`. Helps landscape iPhone for free.
- **The narrator is capped at two lines in cards.** That field holds everything up to the colon introducing the quote, and 522 hadith have one over 250 characters — Muwatta 1467's runs to 5,323. Uncapped, one attribution fills the card and pushes the hadith out of view. The detail view shows it in full, switching from italic label styling to body prose past 200 characters.
- **Controls cap their Dynamic Type at `accessibility1`; content doesn't.** Filter chips allowed to scale freely reach ~350pt of stacked pills and bury the results they filter. Collection rows switch to a stacked layout via `ViewThatFits` instead of letting "7,276" wrap to "7,27 / 6".

## Backporting to iOS 18

The app currently requires iOS 26. **HadithKit already targets iOS 18** and needs no changes: the Core ML model is built for `iOS18`, and nothing in the engine touches SwiftUI. The work is entirely in the app target.

What has to change:

| API | Used in | Replacement on iOS 18 |
|---|---|---|
| `glassEffect(_:in:)` | `glassSurface` in `DesignSystem.swift` | `.background(.ultraThinMaterial, in: shape)` |
| `GlassEffectContainer`, `glassEffectID` | `FilterChips` | Drop the container; chips animate individually |
| `Tab(role: .search)` | `RootView` | A fourth `Tab` with a magnifying-glass icon |
| `tabBarMinimizeBehavior(.onScrollDown)` | `RootView` | No equivalent — drop it |
| `scrollEdgeEffectStyle(_:for:)` | Scroll views | No equivalent — drop it |
| `buttonStyle(.glass)` | `ChapterView` load-more | `.buttonStyle(.bordered)` |

Because every glass call already funnels through `glassSurface`, the material fallback is **one function body**, not an `#available` check scattered through every view. The remaining five are single-line changes in `RootView` and the scroll modifiers.

Then set `deploymentTarget.iOS: "18.0"` in `project.yml` and regenerate.

The honest trade: `.ultraThinMaterial` approximates Liquid Glass but does not match it — no specular edge, no lensing, no morph transitions. Ship iOS 26 as the designed experience and treat 18–25 as a graceful degradation, not a second design.

## Not built (deliberately)

Out of scope for v1, listed so the boundary is explicit rather than forgotten:

- **AI chat over retrieved hadith** via the Foundation Models framework. On-device, free, private — and the closest thing to a real differentiator. Needs a capability fallback: Apple Intelligence requires iPhone 15 Pro or newer.
- **Widgets, daily notification, share cards.**
- **Arabic full-text search** — a second FTS5 table with `remove_diacritics 2`. Cheap to add and genuinely useful for a corpus that is 71% Arabic by volume.
- **Universal links.** `Route` already mirrors the web app's URL shapes, so this is mostly an entitlement and a path parser.
