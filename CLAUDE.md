# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Check the Chain** — verify hadith authenticity via hybrid semantic + keyword search across 47,000+ hadith from 16 collections.

This is a monorepo with two products that share one corpus:

| Path | What |
|---|---|
| `apps/web` | Next.js app. Convex backend, Transformers.js embeddings in a Web Worker. **Requires network.** |
| `apps/ios` | Native SwiftUI app, iOS 26+. **Fully offline** — bundled SQLite + Core ML, no backend. |
| `packages/pipeline` | Builds the iOS offline artifacts from the Convex corpus. |
| `data/hadith-json` | Source corpus (gitignored, 175MB). |

The iOS app is the primary product. It has no backend by design: zero running cost, instant search, works offline, and none of the WASM/worker memory problems the web app has.

## Commands

```bash
npm install          # installs all workspaces
npm run dev          # Next.js dev server (apps/web)
npm run build        # production build + type check (apps/web) — primary web validation
npm run lint         # ESLint (apps/web)
npm run pipeline     # build iOS offline artifacts (packages/pipeline)
```

iOS:
```bash
cd apps/ios && xcodegen generate          # regenerate CheckTheChain.xcodeproj from project.yml
xcodebuild -scheme CheckTheChain -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' build
xcodebuild test -scheme HadithKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

No JS test framework is configured; `npm run build` is the web validation step. The iOS engine has XCTest coverage in `apps/ios/HadithKit/Tests`.

Data pipeline scripts (run with `npx tsx` from `apps/web`):
- `scripts/seed-convex.ts` — load hadith JSON into Convex. **Clears the table first**, so it destroys embeddings and gradings — never run it to change one derived field
- `scripts/build-embeddings-convex.ts` — generate and store 384-dim embeddings
- `scripts/enrich-gradings.ts` — enrich with scholarly grading data
- `scripts/reparse-isnad.ts` — re-derive `isnad_narrators` in place from the Arabic already in Convex (`--dry-run` to preview). This is the pattern for any parser change: patch, don't re-seed
- `scripts/lib/isnad.ts` — the sanad parser, shared by the seed and the re-parse. `npm run test:isnad -w apps/web`

## apps/web architecture

### Search pipeline
1. User types query → 300ms debounce
2. Client-side Web Worker generates embedding via Transformers.js (`Xenova/all-MiniLM-L6-v2`, 384-dim, q8 quantized)
3. `POST /api/search` sends both query text and embedding vector to Convex
4. Convex runs vector search + full-text search in parallel, combines via Reciprocal Rank Fusion (K=60)
5. Client applies collection/grading filters on returned results

### Layers
- **`src/app/`** — App Router pages and API routes
- **`src/components/`** — React client components (`"use client"` where interactive)
- **`src/lib/`** — Types, hooks, Web Worker, utilities
- **`convex/`** — Backend schema, queries, mutations, actions (auto-generates `convex/_generated/`)
- **`scripts/`** — One-off data pipeline scripts (excluded from TS compilation)

### Convex data model
Three tables in `convex/schema.ts`:
- **`hadith`** — indexes: `by_slug_number`, `by_collection_order`, `by_chapter_order`, `search_english` (FTS), `by_embedding` (vector, 384 dims)
- **`chapters`** — per-collection chapter metadata
- **`collection_counts`** — per-collection hadith counts

### Key patterns
- **Embedding Worker** (`src/lib/embedding-worker.ts`): ML model in a Web Worker. Requires explicit WASM tensor cleanup to prevent OOM.
- **URL-synced search state**: `?q=...` keeps search shareable. AbortController cancels in-flight requests.
- **SSR for detail pages**: `fetchQuery()` from Convex, dynamic OpenGraph metadata.
- **Hybrid scoring**: vector + FTS merged via RRF — neither alone is sufficient.

## apps/ios architecture

Everything runs on-device. No network calls anywhere in the app.

- **`HadithKit`** — local SPM package, the search engine. UI-free and independently testable.
  - `HadithStore` (actor) — GRDB over the bundled read-only SQLite, FTS5 + `bm25()`
  - `Embedder` (actor) — Core ML MiniLM; pooling and L2 norm are baked into the model graph, so it returns a ready-to-use unit vector
  - `VectorIndex` — mmap'd int8 embedding matrix, SIMD dot-product scan over 47k rows
  - `SearchEngine` — fuses FTS + vector with RRF (K=60), mirroring `apps/web/convex/hadith.ts`
  - `NarratorName` — renders Arabic isnad entries in English. The corpus has no English narrator field, so this is on-device transliteration: a 330-token lexicon covering 85% of chain tokens, plus rules for the article, `ibn`/`Abu`/`Abd al-`, and a vowel-inserting fallback
- **`CheckTheChain`** — SwiftUI app target. iOS 26 `TabView` with `Tab(role: .search)`.

**Parity is enforced, not assumed.** `HadithKitTests` replays golden queries captured from the live web app; the offline engine must reproduce the same top-10. Any change to ranking, quantization, or the Core ML conversion must keep that test green.

**Liquid Glass rule:** glass goes on controls floating *above* content (tab bar, search field, filter chips, toolbar buttons) — never behind body text. Result and detail cards are opaque.

All glass is routed through a single `GlassSurface` modifier in `DesignSystem.swift`. This is deliberate: it's the one file an iOS 18 backport would need to touch.

**Surfaces:** ground `#F2F2F3`, surfaces white, **no borders and no shadows** — a card reads as a card because it is lighter than the page, and that contrast step is the only separation it gets. Lists of peers (collections, chapters) are one grouped surface with hairline dividers, not a stack of cards. Colour appears only on the grading badge.

**The app launches on the search tab.** While a `Tab(role: .search)` is active, iOS 26 folds the whole tab group behind one button whose accessibility value is `Collapsed` — the other tabs are absent from the view hierarchy, not just off screen. Hence the "Browse N collections" link on the search canvas, and the expand step in `XCUIApplication.tabButton(_:)`.

## packages/pipeline

`Convex export → hadith.sqlite + embeddings.bin + MiniLM.mlpackage`, written into `apps/ios/CheckTheChain/Resources/`.

Convex is the source of truth — it already holds the enriched corpus (gradings, chapters, isnad, embeddings), so the pipeline dumps it rather than re-deriving anything. That's what guarantees web/iOS parity.

Row ids in `hadith.sqlite` are dense and double as row indexes into `embeddings.bin`. **The two artifacts must be built in the same run** or search returns the wrong hadith.

The Core ML conversion needs Python 3.11/3.12 (`packages/pipeline/coreml/.venv`) — coremltools does not support the system Python 3.14.

## Path aliases (apps/web)

- `@/*` → `./src/*`
- `@convex/*` → `./convex/*`

## URL routes (apps/web)

- `/` — Search (with `?q=...`)
- `/hadith/{collection-slug}/{number}` — Hadith detail
- `/isnad/{collection-slug}/{number}` — Chain of narrators
- `/browse` and `/browse/{collection-slug}?page=N` — Collection browsing

## Environment variables

```
NEXT_PUBLIC_CONVEX_URL       # Convex deployment endpoint
CONVEX_DEPLOYMENT            # Convex deployment ID (local dev)
```

Lives in `apps/web/.env.local`. The iOS app needs none.

## Build considerations

- **Vercel's Root Directory must be set to `apps/web`.**
- `apps/web/next.config.ts` aliases `sharp` and `onnxruntime-node` to empty strings in browser builds (Turbopack) — Node-only deps that would crash the client bundle
- Web embedding model loads lazily on first search with a progress bar; not bundled at build time
- Grading types: `Sahih`, `Hasan`, `Da'if`, `Mawdu'`, `Unknown` — `apps/web/src/lib/types.ts`, mirrored in `HadithKit/Models`
- Arabic text uses `Noto Naskh Arabic` with `lang="ar" dir="rtl"` on web, and the same bundled face on iOS
