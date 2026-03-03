# Hadith Browsing & Detail Pages — Design Doc

**Date:** 2026-03-03
**Status:** Approved

## Summary

Add individual hadith detail pages, collection browsing, and search filter chips to hadith-check. Uses hash-based client-side routing to keep the static export architecture. Arabic text displayed on detail pages via lazy-loaded `hadith-arabic.json`.

## Goals

- **Individual hadith permalinks** — shareable URLs for any hadith (`/#/hadith/sahih-al-bukhari/1`)
- **Collection browsing** — discover hadith outside of search
- **Search filtering** — narrow results by collection and grading
- **Arabic text** — display original Arabic on detail pages

## Non-Goals

- Server-side rendering or SEO for individual hadith (accepted trade-off of client-side routing)
- Search history or bookmarks (future feature)
- Advanced narrator chain (isnad) display

## Audience

Progressive layering for all users: casual learners (quick verify), students of knowledge (Arabic, browsing), and sharers/educators (permalinks, copy-to-share).

---

## Architecture

### Routing

Hash-based routing via a custom `useHashRoute()` hook (~30 lines). No new dependencies.

| Route | View | Description |
|-------|------|-------------|
| `/#/` or `/` | SearchView | Existing search page (unchanged behavior) |
| `/#/browse` | BrowseView | Grid of 17 collections with counts |
| `/#/browse/:collection` | CollectionView | Paginated hadith list for one collection |
| `/#/hadith/:collection/:number` | HadithView | Full hadith detail with Arabic |

### Component Structure

```
page.tsx (Router shell)
├── Nav                  (Search | Browse links)
├── SearchView           (extracted from current page.tsx)
│   ├── SearchInput      (existing)
│   ├── FilterChips      (new)
│   └── ResultCard       (existing, modified)
├── BrowseView           (new — collection index)
├── CollectionView       (new — single collection list)
└── HadithView           (new — hadith detail)
```

---

## Feature Details

### 1. Hadith Detail Page

**URL:** `/#/hadith/:collection-slug/:hadith-number`

**Layout (top to bottom):**
1. Back link — "Back to search" or "Back to [collection]" (contextual)
2. Reference as `<h1>` — e.g. "Sahih al-Bukhari 1"
3. Grading badge — existing `GradingBadge` component
4. Arabic text — right-aligned, 20-24px, from `hadith-arabic.json`
5. English text — comfortable reading size
6. Narrator — italic
7. Graded by — if available
8. Actions — Copy link, Copy text (formatted: "Reference: Text — Source")

**Arabic text loading:**
- `hadith-arabic.json` (44 MB) lazy-loaded on first detail page visit
- Cached in memory after first load
- Loading skeleton shown while Arabic loads
- New `src/lib/arabic.ts` module handles loading and caching

**Collection slugs:**
- Lowercase, hyphenated: `sahih-al-bukhari`, `sunan-abu-dawud`, etc.
- Bidirectional mapping in `src/lib/collections.ts`

### 2. Collection Browsing

**Browse Index (`/#/browse`):**
- Grid of cards, one per collection (17 total)
- Each card: collection name, hadith count, brief description
- Grouped: "The Nine Books", "Other Collections", "Forties"

**Collection Detail (`/#/browse/:collection-slug`):**
- Header with collection name and total count
- Paginated list, 50 hadith per page (client-side)
- Each row: hadith number, first ~120 chars of English, grading badge
- Click navigates to hadith detail page
- Prev/next pagination controls

### 3. Search Filter Chips

**Location:** Between search input and results (visible only when results exist).

**Chip types:**
- **Collection chips** — dynamically generated from collections present in results
- **Grading chips** — "Sahih", "Hasan", "Da'if" (only if mixed gradings in results)

**Behavior:**
- Toggle on/off, multiple active simultaneously
- Instant client-side filtering of already-returned results
- Active = filled style, inactive = outline style
- Resets when search query changes
- Not persisted in URL

### 4. Navigation

- Minimal nav in header: "Search" | "Browse"
- Current page gets subtle visual indicator
- Result card references become clickable (navigate to detail page)
- Share button copies hadith detail URL instead of search URL
- Detail page includes "Browse more from this collection" link

---

## New Files

| File | Purpose |
|------|---------|
| `src/lib/router.ts` | `useHashRoute()` hook, `navigate()`, route parsing |
| `src/lib/arabic.ts` | Lazy-load and cache `hadith-arabic.json` |
| `src/lib/collections.ts` | Collection metadata: slugs, names, descriptions, counts |
| `src/components/filter-chips.tsx` | Toggleable filter chips |
| `src/components/hadith-view.tsx` | Hadith detail page |
| `src/components/browse-view.tsx` | Collection index |
| `src/components/collection-view.tsx` | Single collection hadith list |
| `src/components/search-view.tsx` | Extracted current search UI |
| `src/components/nav.tsx` | Navigation links |

## Modified Files

| File | Changes |
|------|---------|
| `src/app/page.tsx` | Becomes router shell, delegates to view components |
| `src/components/result-card.tsx` | Clickable reference, updated share URL |
| `src/lib/types.ts` | Add slug mapping types, Arabic data type |
