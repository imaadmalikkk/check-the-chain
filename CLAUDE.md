# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Check the Chain** — a Next.js app for verifying hadith authenticity via hybrid semantic + keyword search across 47,000+ hadith from 17 collections. Uses client-side ML embeddings (Transformers.js) with a Convex serverless backend.

## Commands

```bash
npm run dev       # Start Next.js dev server (Turbopack)
npm run build     # Production build (includes type checking)
npm run lint      # ESLint
npm run start     # Serve production build
```

No test framework is configured. `npm run build` is the primary validation step.

Data pipeline scripts (run with `npx tsx`):
- `scripts/seed-convex.ts` — Load hadith JSON into Convex
- `scripts/build-embeddings-convex.ts` — Generate and store 384-dim embeddings
- `scripts/enrich-gradings.ts` — Enrich with scholarly grading data

## Architecture

### Search Pipeline

1. User types query → 300ms debounce
2. Client-side Web Worker generates embedding via Transformers.js (`Xenova/all-MiniLM-L6-v2`, 384-dim, q8 quantized)
3. `POST /api/search` sends both query text and embedding vector to Convex
4. Convex runs vector search + full-text search in parallel, combines via Reciprocal Rank Fusion (K=60)
5. Client applies collection/grading filters on returned results

### Layers

- **`src/app/`** — Next.js App Router pages and API routes
- **`src/components/`** — React client components (`"use client"` where interactive)
- **`src/lib/`** — Types, hooks, Web Worker, utilities
- **`convex/`** — Backend schema, queries, mutations, and actions (auto-generates types in `convex/_generated/`)
- **`scripts/`** — One-off data pipeline scripts (excluded from TS compilation)
- **`data/hadith-json/`** — Source JSON hadith files organized by book category

### Convex Data Model

Two tables defined in `convex/schema.ts`:
- **`hadith`** — Main table with indexes: `by_slug_number` (lookup), `by_collection_order` (pagination), `search_english` (FTS), `by_embedding` (vector search, 384 dims)
- **`collection_counts`** — Per-collection hadith counts

### Key Patterns

- **Embedding Worker** (`src/lib/embedding-worker.ts`): Runs ML model in Web Worker to avoid blocking main thread. Requires explicit WASM tensor memory cleanup to prevent OOM.
- **URL-synced search state**: Query param `?q=...` keeps search shareable. AbortController cancels in-flight requests on new input.
- **SSR for detail pages**: `fetchQuery()` from Convex for server-side rendering with dynamic OpenGraph metadata.
- **Hybrid search scoring**: Vector similarity and FTS results merged via RRF — neither alone is sufficient.

## Path Aliases

- `@/*` → `./src/*`
- `@convex/*` → `./convex/*`

## URL Routes

- `/` — Search (with `?q=...`)
- `/hadith/{collection-slug}/{number}` — Hadith detail
- `/isnad/{collection-slug}/{number}` — Chain of narrators
- `/browse` and `/browse/{collection-slug}?page=N` — Collection browsing

## Environment Variables

```
NEXT_PUBLIC_CONVEX_URL       # Convex deployment endpoint
CONVEX_DEPLOYMENT            # Convex deployment ID (local dev)
```

## Build Considerations

- `next.config.ts` aliases `sharp` and `onnxruntime-node` to empty strings in browser builds (Turbopack) — these are Node-only deps that would crash the client bundle
- Embedding model is loaded lazily on first search with a progress bar; not bundled at build time
- Grading types: `Sahih`, `Hasan`, `Da'if`, `Mawdu'`, `Unknown` — defined in `src/lib/types.ts`
- Arabic text uses `Noto Naskh Arabic` font with `lang="ar" dir="rtl"` attributes
