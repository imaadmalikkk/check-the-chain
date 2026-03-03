# Browsing & Detail Pages Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add hash-based client-side routing with individual hadith detail pages (including Arabic text), collection browsing, and search filter chips.

**Architecture:** A custom `useHashRoute()` hook handles all routing within the existing static export. The current `SearchApp` component becomes a router shell that delegates to view components. Arabic text is lazy-loaded from `hadith-arabic.json` on first detail page visit. No new dependencies.

**Tech Stack:** Next.js 16 (static export), React 19, TypeScript 5, Tailwind CSS 4

---

### Task 1: Collection metadata module

**Files:**
- Create: `src/lib/collections.ts`

**Step 1: Create the collections module**

This module provides the slug-to-name mapping and metadata for all 17 collections. The slug format is lowercase-hyphenated. Collection names must match the data exactly.

```typescript
"use client";

export interface CollectionMeta {
  name: string;
  slug: string;
  group: "nine-books" | "other" | "forties";
  description: string;
}

const COLLECTIONS: CollectionMeta[] = [
  { name: "Sahih al-Bukhari", slug: "sahih-al-bukhari", group: "nine-books", description: "The most authentic collection, compiled by Imam al-Bukhari (d. 870 CE)." },
  { name: "Sahih Muslim", slug: "sahih-muslim", group: "nine-books", description: "The second most authentic collection, compiled by Imam Muslim (d. 875 CE)." },
  { name: "Sunan al-Nasa'i", slug: "sunan-al-nasai", group: "nine-books", description: "Known for its strict criteria, compiled by Imam al-Nasa'i (d. 915 CE)." },
  { name: "Sunan Abi Dawud", slug: "sunan-abi-dawud", group: "nine-books", description: "Focused on legal hadith, compiled by Imam Abu Dawud (d. 889 CE)." },
  { name: "Sunan Ibn Majah", slug: "sunan-ibn-majah", group: "nine-books", description: "Part of the six major collections, compiled by Imam Ibn Majah (d. 887 CE)." },
  { name: "Jami' al-Tirmidhi", slug: "jami-al-tirmidhi", group: "nine-books", description: "Known for grading each hadith, compiled by Imam al-Tirmidhi (d. 892 CE)." },
  { name: "Muwatta Malik", slug: "muwatta-malik", group: "nine-books", description: "The earliest compiled collection, by Imam Malik (d. 795 CE)." },
  { name: "Musnad Ahmad ibn Hanbal", slug: "musnad-ahmad", group: "nine-books", description: "One of the largest collections, compiled by Imam Ahmad (d. 855 CE)." },
  { name: "Mishkat al-Masabih", slug: "mishkat-al-masabih", group: "other", description: "A comprehensive compilation drawing from the six major books and more." },
  { name: "Riyad as-Salihin", slug: "riyad-as-salihin", group: "other", description: "Gardens of the Righteous, compiled by Imam al-Nawawi (d. 1277 CE)." },
  { name: "Bulugh al-Maram", slug: "bulugh-al-maram", group: "other", description: "Hadith related to jurisprudence, compiled by Ibn Hajar al-Asqalani (d. 1449 CE)." },
  { name: "Al-Adab Al-Mufrad", slug: "al-adab-al-mufrad", group: "other", description: "Hadith on manners and etiquette, compiled by Imam al-Bukhari." },
  { name: "Shama'il Muhammadiyah", slug: "shamail-muhammadiyah", group: "other", description: "Description of Prophet Muhammad's appearance and character, by Imam al-Tirmidhi." },
  { name: "The Forty Hadith of Imam Nawawi", slug: "nawawi-40", group: "forties", description: "40 foundational hadith selected by Imam al-Nawawi." },
  { name: "The Forty Hadith Qudsi", slug: "qudsi-40", group: "forties", description: "40 hadith in which Allah speaks in the first person." },
  { name: "The Forty Hadith of Shah Waliullah", slug: "shah-waliullah-40", group: "forties", description: "40 hadith selected by Shah Waliullah al-Dihlawi (d. 1762 CE)." },
];

const bySlug = new Map(COLLECTIONS.map((c) => [c.slug, c]));
const byName = new Map(COLLECTIONS.map((c) => [c.name, c]));

export function getCollectionBySlug(slug: string): CollectionMeta | undefined {
  return bySlug.get(slug);
}

export function getCollectionByName(name: string): CollectionMeta | undefined {
  return byName.get(name);
}

export function slugFromName(name: string): string {
  return byName.get(name)?.slug ?? name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

export function getAllCollections(): CollectionMeta[] {
  return COLLECTIONS;
}

export function getCollectionsByGroup(group: CollectionMeta["group"]): CollectionMeta[] {
  return COLLECTIONS.filter((c) => c.group === group);
}
```

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes with no TypeScript errors.

**Step 3: Commit**

```bash
git add src/lib/collections.ts
git commit -m "feat: add collection metadata module with slug mappings"
```

---

### Task 2: Hash router

**Files:**
- Create: `src/lib/router.ts`

**Step 1: Create the router module**

This is a lightweight hash-based router. It parses `window.location.hash` and re-renders on `hashchange`. No external dependencies.

```typescript
"use client";

import { useState, useEffect, useCallback, useSyncExternalStore } from "react";

export type Route =
  | { page: "search" }
  | { page: "browse" }
  | { page: "collection"; slug: string }
  | { page: "hadith"; slug: string; number: string };

function parseHash(hash: string): Route {
  const path = hash.replace(/^#\/?/, "");
  const segments = path.split("/").filter(Boolean);

  if (segments[0] === "browse" && segments[1]) {
    return { page: "collection", slug: segments[1] };
  }
  if (segments[0] === "browse") {
    return { page: "browse" };
  }
  if (segments[0] === "hadith" && segments[1] && segments[2]) {
    return { page: "hadith", slug: segments[1], number: segments[2] };
  }
  return { page: "search" };
}

let currentRoute: Route = { page: "search" };
let listeners: Array<() => void> = [];

function notify() {
  for (const fn of listeners) fn();
}

function subscribe(fn: () => void): () => void {
  listeners.push(fn);
  return () => {
    listeners = listeners.filter((l) => l !== fn);
  };
}

function getSnapshot(): Route {
  return currentRoute;
}

function getServerSnapshot(): Route {
  return { page: "search" };
}

if (typeof window !== "undefined") {
  currentRoute = parseHash(window.location.hash);
  window.addEventListener("hashchange", () => {
    currentRoute = parseHash(window.location.hash);
    notify();
  });
}

export function useRoute(): Route {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export function navigate(path: string) {
  window.location.hash = path.startsWith("/") ? `#${path}` : `#/${path}`;
}

export function hadithUrl(slug: string, number: string): string {
  return `/#/hadith/${slug}/${number}`;
}

export function collectionUrl(slug: string): string {
  return `/#/browse/${slug}`;
}

export function browseUrl(): string {
  return "/#/browse";
}

export function searchUrl(): string {
  return "/";
}
```

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes.

**Step 3: Commit**

```bash
git add src/lib/router.ts
git commit -m "feat: add hash-based client-side router"
```

---

### Task 3: Arabic text loader

**Files:**
- Create: `src/lib/arabic.ts`

**Step 1: Create the Arabic loader module**

Lazy-loads `hadith-arabic.json` on demand. Caches in memory after first load.

```typescript
"use client";

let arabicTexts: string[] | null = null;
let loadPromise: Promise<string[]> | null = null;

export async function loadArabicData(): Promise<string[]> {
  if (arabicTexts) return arabicTexts;
  if (loadPromise) return loadPromise;

  loadPromise = fetch("/hadith-arabic.json")
    .then((res) => res.json())
    .then((data: string[]) => {
      arabicTexts = data;
      return data;
    });

  return loadPromise;
}

export function getArabicText(hadithId: number): string | undefined {
  return arabicTexts?.[hadithId];
}

export function isArabicLoaded(): boolean {
  return arabicTexts !== null;
}
```

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes.

**Step 3: Commit**

```bash
git add src/lib/arabic.ts
git commit -m "feat: add lazy Arabic text loader"
```

---

### Task 4: Expose hadith data from search module

**Files:**
- Modify: `src/lib/search.ts`

**Step 1: Add `getHadithData()` and `getHadithByRef()` exports**

The browse and detail views need access to the loaded hadith data without going through the search pipeline. Add these exports to the bottom of `src/lib/search.ts`:

```typescript
export function getHadithData(): Hadith[] {
  return hadithData;
}

export function getHadithByRef(collection: string, number: string): Hadith | undefined {
  return hadithData.find((h) => h.collection === collection && h.hadithNumber === number);
}

export function getHadithByCollection(collection: string): Hadith[] {
  return hadithData.filter((h) => h.collection === collection);
}
```

The existing `hadithData` array is already module-scoped and populated by `loadData()`. These functions simply expose it for read-only access. Callers must await `initSearch()` before calling these.

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes.

**Step 3: Commit**

```bash
git add src/lib/search.ts
git commit -m "feat: expose hadith data accessors from search module"
```

---

### Task 5: Nav component

**Files:**
- Create: `src/components/nav.tsx`

**Step 1: Create the Nav component**

Minimal navigation with "Search" and "Browse" links. Uses the hash router to detect active page.

```typescript
"use client";

import { useRoute, searchUrl, browseUrl } from "@/lib/router";

export function Nav() {
  const route = useRoute();

  const links = [
    { label: "Search", href: searchUrl(), active: route.page === "search" },
    { label: "Browse", href: browseUrl(), active: route.page === "browse" || route.page === "collection" },
  ];

  return (
    <nav className="flex gap-6 text-sm">
      {links.map((link) => (
        <a
          key={link.label}
          href={link.href}
          className={`transition-colors ${
            link.active
              ? "text-neutral-900 font-medium"
              : "text-neutral-500 hover:text-neutral-700"
          }`}
        >
          {link.label}
        </a>
      ))}
    </nav>
  );
}
```

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes.

**Step 3: Commit**

```bash
git add src/components/nav.tsx
git commit -m "feat: add navigation component"
```

---

### Task 6: Extract SearchView from page.tsx

**Files:**
- Create: `src/components/search-view.tsx`
- Modify: `src/app/page.tsx`

**Step 1: Create SearchView**

Extract the entire search UI (header, loading bar, search input, results) from the current `SearchApp` function in `page.tsx` into a new `SearchView` component. This is a move, not a rewrite — preserve all existing behavior exactly.

The `SearchView` component should contain:
- All the state hooks currently in `SearchApp` (`query`, `results`, `indexReady`, `searching`, `hasSearched`, `semanticStatus`, `semanticProgress`, `debounceRef`)
- The `isReady` derived value
- All the effects (`initSearch`, `doSearch`, `handleChange`, `loadingLabel`)
- The JSX for the header, loading bar, search input, and results section
- The footer

The only change: `useSearchParams` and `useRouter` from `next/navigation` stay in `SearchView`. The `SearchView` reads the initial query from `searchParams.get("q")`.

```typescript
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { SearchInput } from "@/components/search-input";
import { ResultCard } from "@/components/result-card";
import { initSearch, searchHadith } from "@/lib/search";
import {
  getSemanticStatus,
  getSemanticProgress,
  onSemanticStatusChange,
  type SemanticStatus,
} from "@/lib/semantic-search";
import type { SearchResult } from "@/lib/types";

export function SearchView() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [query, setQuery] = useState(searchParams.get("q") || "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [indexReady, setIndexReady] = useState(false);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [semanticStatus, setSemanticStatus] = useState<SemanticStatus>("idle");
  const [semanticProgress, setSemanticProgress] = useState(0);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  const isReady = semanticStatus === "ready" || semanticStatus === "error";

  useEffect(() => {
    initSearch().then(() => setIndexReady(true));
    setSemanticStatus(getSemanticStatus());
    setSemanticProgress(getSemanticProgress());
    return onSemanticStatusChange((s, p) => {
      setSemanticStatus(s);
      setSemanticProgress(p);
    });
  }, []);

  const doSearch = useCallback(async (q: string) => {
    if (!q.trim()) {
      setResults([]);
      setHasSearched(false);
      return;
    }
    setSearching(true);
    const r = await searchHadith(q);
    setResults(r);
    setHasSearched(true);
    setSearching(false);
  }, []);

  useEffect(() => {
    if (isReady && query) {
      doSearch(query);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isReady, doSearch, query]);

  function handleChange(value: string) {
    setQuery(value);

    const url = value.trim()
      ? `?q=${encodeURIComponent(value.trim())}`
      : "/";
    router.replace(url, { scroll: false });

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      doSearch(value);
    }, 300);
  }

  const loadingLabel =
    !indexReady
      ? "Loading search index…"
      : semanticStatus === "loading-model"
        ? "Downloading AI model…"
        : "Loading embeddings…";

  return (
    <>
      <header className="pt-16 sm:pt-24 pb-8 sm:pb-12">
        <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-neutral-900">
          Is this hadith real?
        </h1>
        <p className="mt-2 text-sm text-neutral-500 leading-relaxed max-w-md">
          Verify hadith against 47,000+ narrations from
          Bukhari, Muslim, and 15 other major collections.
        </p>
      </header>

      <section className="mb-8">
        {!isReady ? (
          <div className="rounded-lg border border-neutral-200 bg-white px-4 py-5">
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm text-neutral-500">{loadingLabel}</p>
              {indexReady && (
                <span className="text-xs text-neutral-400 font-mono tabular-nums">
                  {semanticProgress}%
                </span>
              )}
            </div>
            <div className="h-1.5 w-full rounded-full bg-neutral-100 overflow-hidden">
              <div
                className="h-full rounded-full bg-neutral-900 transition-all duration-300 ease-out"
                role="progressbar"
                aria-valuenow={indexReady ? semanticProgress : 0}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-label={loadingLabel}
                style={{ width: `${indexReady ? semanticProgress : 0}%` }}
              />
            </div>
          </div>
        ) : (
          <SearchInput
            value={query}
            onChange={handleChange}
            isLoading={searching}
          />
        )}
      </section>

      <section id="results" className="space-y-3 pb-16">
        {results.map((r) => (
          <ResultCard key={r.hadith.id} result={r} query={query} />
        ))}

        {hasSearched && results.length === 0 && !searching && (
          <div className="text-center py-12">
            <p className="text-sm text-neutral-600 leading-relaxed max-w-sm mx-auto">
              This hadith was not found in the major collections. This
              doesn&apos;t necessarily mean it doesn&apos;t exist — consult a
              scholar for verification.
            </p>
          </div>
        )}
      </section>
    </>
  );
}
```

**Step 2: Replace page.tsx with router shell**

Replace the entire `SearchApp` function body in `src/app/page.tsx` with a router shell. The `Home` export and `Suspense` wrapper stay.

```typescript
"use client";

import { Suspense } from "react";
import { useRoute } from "@/lib/router";
import { Nav } from "@/components/nav";
import { SearchView } from "@/components/search-view";

function App() {
  const route = useRoute();

  return (
    <div className="min-h-screen flex flex-col">
      <a href="#main-content" className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-neutral-900 focus:text-white focus:rounded-md focus:text-sm">
        Skip to content
      </a>
      <main id="main-content" className="flex-1 w-full max-w-2xl mx-auto px-4 sm:px-6">
        <div className="pt-8 sm:pt-12 flex items-center justify-between">
          <a href="/" className="text-sm font-medium text-neutral-900 hover:text-neutral-700 transition-colors">
            hadith-check
          </a>
          <Nav />
        </div>

        {route.page === "search" && <SearchView />}
        {route.page === "browse" && <div>Browse placeholder</div>}
        {route.page === "collection" && <div>Collection placeholder: {route.slug}</div>}
        {route.page === "hadith" && <div>Hadith placeholder: {route.slug}/{route.number}</div>}
      </main>

      <footer className="border-t border-neutral-100 py-8 px-4 sm:px-6">
        <div className="max-w-2xl mx-auto">
          <p className="text-xs text-neutral-500 leading-relaxed mb-3">
            This tool searches major hadith collections. It is not a substitute
            for scholarly verification.
          </p>
          <a
            href="https://github.com/imaadmalik/hadith-check"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors"
          >
            Open source on GitHub
          </a>
        </div>
      </footer>
    </div>
  );
}

export default function Home() {
  return (
    <Suspense>
      <App />
    </Suspense>
  );
}
```

Note: The footer is simplified (collections list removed — it's now accessible via Browse). The header now contains the site name and nav.

**Step 3: Verify build and test**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Navigating to `/` shows the existing search UI. The nav shows "Search" and "Browse" links.

**Step 4: Commit**

```bash
git add src/components/search-view.tsx src/app/page.tsx
git commit -m "refactor: extract SearchView, add router shell with nav"
```

---

### Task 7: Hadith detail page

**Files:**
- Create: `src/components/hadith-view.tsx`
- Modify: `src/app/page.tsx` (replace placeholder)

**Step 1: Create HadithView component**

```typescript
"use client";

import { useState, useEffect } from "react";
import { getCollectionBySlug } from "@/lib/collections";
import { navigate, collectionUrl } from "@/lib/router";
import { initSearch, getHadithByRef } from "@/lib/search";
import { loadArabicData, getArabicText } from "@/lib/arabic";
import { GradingBadge } from "@/components/grading-badge";
import type { Hadith } from "@/lib/types";

export function HadithView({ slug, number }: { slug: string; number: string }) {
  const [hadith, setHadith] = useState<Hadith | null>(null);
  const [arabicText, setArabicText] = useState<string | null>(null);
  const [arabicLoading, setArabicLoading] = useState(true);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState<"link" | "text" | null>(null);

  const collection = getCollectionBySlug(slug);

  useEffect(() => {
    if (!collection) return;

    initSearch().then(() => {
      const h = getHadithByRef(collection.name, number);
      setHadith(h ?? null);
      setLoading(false);

      if (h) {
        loadArabicData().then(() => {
          setArabicText(getArabicText(h.id) ?? null);
          setArabicLoading(false);
        });
      }
    });
  }, [collection, number]);

  function copyLink() {
    navigator.clipboard.writeText(window.location.href).then(() => {
      setCopied("link");
      setTimeout(() => setCopied(null), 2000);
    });
  }

  function copyText() {
    if (!hadith) return;
    const text = `${hadith.reference}\n\n${hadith.english}${hadith.narrator ? `\n\n${hadith.narrator}` : ""}`;
    navigator.clipboard.writeText(text).then(() => {
      setCopied("text");
      setTimeout(() => setCopied(null), 2000);
    });
  }

  if (!collection) {
    return (
      <div className="pt-16 sm:pt-24 text-center">
        <p className="text-sm text-neutral-500">Collection not found.</p>
        <a href="/" className="text-sm text-neutral-700 hover:text-neutral-900 mt-2 inline-block">
          Back to search
        </a>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="pt-16 sm:pt-24">
        <div className="animate-pulse space-y-4">
          <div className="h-4 w-32 bg-neutral-100 rounded" />
          <div className="h-8 w-64 bg-neutral-100 rounded" />
          <div className="h-24 w-full bg-neutral-100 rounded" />
          <div className="h-32 w-full bg-neutral-100 rounded" />
        </div>
      </div>
    );
  }

  if (!hadith) {
    return (
      <div className="pt-16 sm:pt-24 text-center">
        <p className="text-sm text-neutral-500">Hadith not found.</p>
        <a href={collectionUrl(slug)} className="text-sm text-neutral-700 hover:text-neutral-900 mt-2 inline-block">
          Browse {collection.name}
        </a>
      </div>
    );
  }

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <a
        href={collectionUrl(slug)}
        className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
      >
        &larr; {collection.name}
      </a>

      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-3">
        {hadith.reference}
      </h1>

      {hadith.grading !== "Unknown" && (
        <div className="mb-6">
          <GradingBadge grading={hadith.grading} />
          {hadith.gradedBy && (
            <span className="text-xs text-neutral-500 ml-2">
              Graded by: {hadith.gradedBy}
            </span>
          )}
        </div>
      )}

      {arabicLoading ? (
        <div className="animate-pulse h-20 w-full bg-neutral-50 rounded-lg mb-6" />
      ) : arabicText ? (
        <div className="bg-neutral-50 rounded-lg p-5 sm:p-6 mb-6" dir="rtl" lang="ar">
          <p className="text-xl sm:text-2xl leading-loose text-neutral-800 font-serif">
            {arabicText}
          </p>
        </div>
      ) : null}

      {hadith.narrator && (
        <p className="text-sm text-neutral-500 mb-3 italic">
          {hadith.narrator}
        </p>
      )}

      <p className="text-base sm:text-lg leading-relaxed text-neutral-800 mb-8">
        {hadith.english}
      </p>

      <div className="flex gap-3" aria-live="polite">
        <button
          onClick={copyLink}
          className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors border border-neutral-200 rounded-md px-3 py-1.5 cursor-pointer"
          aria-label={copied === "link" ? "Link copied" : "Copy link to this hadith"}
        >
          {copied === "link" ? "Copied!" : "Copy link"}
        </button>
        <button
          onClick={copyText}
          className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors border border-neutral-200 rounded-md px-3 py-1.5 cursor-pointer"
          aria-label={copied === "text" ? "Text copied" : "Copy hadith text"}
        >
          {copied === "text" ? "Copied!" : "Copy text"}
        </button>
      </div>
    </div>
  );
}
```

**Step 2: Wire into page.tsx**

In `src/app/page.tsx`, add the import and replace the hadith placeholder:

Replace:
```typescript
{route.page === "hadith" && <div>Hadith placeholder: {route.slug}/{route.number}</div>}
```
With:
```typescript
{route.page === "hadith" && <HadithView slug={route.slug} number={route.number} />}
```

Add import:
```typescript
import { HadithView } from "@/components/hadith-view";
```

**Step 3: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Navigating to `/#/hadith/sahih-al-bukhari/1` shows the hadith detail page.

**Step 4: Commit**

```bash
git add src/components/hadith-view.tsx src/app/page.tsx
git commit -m "feat: add hadith detail page with Arabic text"
```

---

### Task 8: Browse view (collection index)

**Files:**
- Create: `src/components/browse-view.tsx`
- Modify: `src/app/page.tsx` (replace placeholder)

**Step 1: Create BrowseView component**

```typescript
"use client";

import { useState, useEffect } from "react";
import { getAllCollections, getCollectionsByGroup, type CollectionMeta } from "@/lib/collections";
import { collectionUrl } from "@/lib/router";
import { initSearch, getHadithByCollection } from "@/lib/search";

export function BrowseView() {
  const [counts, setCounts] = useState<Map<string, number>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    initSearch().then(() => {
      const map = new Map<string, number>();
      for (const col of getAllCollections()) {
        map.set(col.name, getHadithByCollection(col.name).length);
      }
      setCounts(map);
      setLoading(false);
    });
  }, []);

  const groups: { title: string; key: CollectionMeta["group"] }[] = [
    { title: "The Nine Books", key: "nine-books" },
    { title: "Other Collections", key: "other" },
    { title: "Forties", key: "forties" },
  ];

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-neutral-900 mb-2">
        Browse Collections
      </h1>
      <p className="text-sm text-neutral-500 mb-10">
        Explore 47,000+ hadith across 17 collections.
      </p>

      {groups.map((group) => (
        <div key={group.key} className="mb-10">
          <h2 className="text-xs font-medium text-neutral-400 uppercase tracking-wider mb-4">
            {group.title}
          </h2>
          <div className="grid gap-3">
            {getCollectionsByGroup(group.key).map((col) => (
              <a
                key={col.slug}
                href={collectionUrl(col.slug)}
                className="block border border-neutral-200 rounded-lg p-4 hover:border-neutral-300 transition-colors"
              >
                <div className="flex items-center justify-between mb-1">
                  <h3 className="text-sm font-medium text-neutral-900">
                    {col.name}
                  </h3>
                  {loading ? (
                    <span className="h-4 w-12 bg-neutral-100 rounded animate-pulse" />
                  ) : (
                    <span className="text-xs text-neutral-400 font-mono">
                      {(counts.get(col.name) ?? 0).toLocaleString()}
                    </span>
                  )}
                </div>
                <p className="text-xs text-neutral-500 leading-relaxed">
                  {col.description}
                </p>
              </a>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
```

**Step 2: Wire into page.tsx**

Replace the browse placeholder in `src/app/page.tsx`:

Replace:
```typescript
{route.page === "browse" && <div>Browse placeholder</div>}
```
With:
```typescript
{route.page === "browse" && <BrowseView />}
```

Add import:
```typescript
import { BrowseView } from "@/components/browse-view";
```

**Step 3: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Navigating to `/#/browse` shows the collection grid.

**Step 4: Commit**

```bash
git add src/components/browse-view.tsx src/app/page.tsx
git commit -m "feat: add collection browse index page"
```

---

### Task 9: Collection detail view

**Files:**
- Create: `src/components/collection-view.tsx`
- Modify: `src/app/page.tsx` (replace placeholder)

**Step 1: Create CollectionView component**

Paginated list of hadith within a collection, 50 per page.

```typescript
"use client";

import { useState, useEffect, useMemo } from "react";
import { getCollectionBySlug } from "@/lib/collections";
import { hadithUrl, browseUrl } from "@/lib/router";
import { initSearch, getHadithByCollection } from "@/lib/search";
import { GradingBadge } from "@/components/grading-badge";
import type { Hadith } from "@/lib/types";

const PAGE_SIZE = 50;

export function CollectionView({ slug }: { slug: string }) {
  const [hadithList, setHadithList] = useState<Hadith[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);

  const collection = getCollectionBySlug(slug);

  useEffect(() => {
    if (!collection) return;
    initSearch().then(() => {
      setHadithList(getHadithByCollection(collection.name));
      setLoading(false);
    });
  }, [collection]);

  // Reset page when slug changes
  useEffect(() => {
    setPage(0);
  }, [slug]);

  const totalPages = Math.ceil(hadithList.length / PAGE_SIZE);
  const pageItems = useMemo(
    () => hadithList.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE),
    [hadithList, page]
  );

  if (!collection) {
    return (
      <div className="pt-16 sm:pt-24 text-center">
        <p className="text-sm text-neutral-500">Collection not found.</p>
        <a href={browseUrl()} className="text-sm text-neutral-700 hover:text-neutral-900 mt-2 inline-block">
          Browse all collections
        </a>
      </div>
    );
  }

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <a
        href={browseUrl()}
        className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
      >
        &larr; All collections
      </a>

      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-1">
        {collection.name}
      </h1>
      <p className="text-sm text-neutral-500 mb-8">
        {loading ? "Loading…" : `${hadithList.length.toLocaleString()} hadith`}
      </p>

      {loading ? (
        <div className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="animate-pulse h-16 bg-neutral-50 rounded-lg" />
          ))}
        </div>
      ) : (
        <>
          <div className="space-y-1">
            {pageItems.map((h) => (
              <a
                key={h.id}
                href={hadithUrl(slug, h.hadithNumber)}
                className="flex items-start gap-3 rounded-lg px-3 py-3 hover:bg-neutral-50 transition-colors"
              >
                <span className="text-xs text-neutral-400 font-mono w-10 shrink-0 pt-0.5 text-right">
                  {h.hadithNumber}
                </span>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-neutral-700 line-clamp-2 leading-relaxed">
                    {h.english.slice(0, 150)}{h.english.length > 150 ? "…" : ""}
                  </p>
                </div>
                {h.grading !== "Unknown" && (
                  <div className="shrink-0 pt-0.5">
                    <GradingBadge grading={h.grading} />
                  </div>
                )}
              </a>
            ))}
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between mt-8 pt-4 border-t border-neutral-100">
              <button
                onClick={() => { setPage((p) => Math.max(0, p - 1)); window.scrollTo(0, 0); }}
                disabled={page === 0}
                className="text-sm text-neutral-600 hover:text-neutral-900 disabled:text-neutral-300 disabled:cursor-not-allowed transition-colors cursor-pointer"
              >
                Previous
              </button>
              <span className="text-xs text-neutral-400 font-mono">
                {page + 1} / {totalPages}
              </span>
              <button
                onClick={() => { setPage((p) => Math.min(totalPages - 1, p + 1)); window.scrollTo(0, 0); }}
                disabled={page >= totalPages - 1}
                className="text-sm text-neutral-600 hover:text-neutral-900 disabled:text-neutral-300 disabled:cursor-not-allowed transition-colors cursor-pointer"
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
```

**Step 2: Wire into page.tsx**

Replace the collection placeholder in `src/app/page.tsx`:

Replace:
```typescript
{route.page === "collection" && <div>Collection placeholder: {route.slug}</div>}
```
With:
```typescript
{route.page === "collection" && <CollectionView slug={route.slug} />}
```

Add import:
```typescript
import { CollectionView } from "@/components/collection-view";
```

**Step 3: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Navigating to `/#/browse/sahih-al-bukhari` shows the paginated hadith list.

**Step 4: Commit**

```bash
git add src/components/collection-view.tsx src/app/page.tsx
git commit -m "feat: add collection detail view with pagination"
```

---

### Task 10: Filter chips for search results

**Files:**
- Create: `src/components/filter-chips.tsx`
- Modify: `src/components/search-view.tsx`

**Step 1: Create FilterChips component**

```typescript
"use client";

import type { Grading } from "@/lib/types";

interface FilterChipsProps {
  collections: string[];
  gradings: Grading[];
  activeCollections: Set<string>;
  activeGradings: Set<Grading>;
  onToggleCollection: (collection: string) => void;
  onToggleGrading: (grading: Grading) => void;
}

export function FilterChips({
  collections,
  gradings,
  activeCollections,
  activeGradings,
  onToggleCollection,
  onToggleGrading,
}: FilterChipsProps) {
  if (collections.length <= 1 && gradings.length <= 1) return null;

  return (
    <div className="flex flex-wrap gap-2 mb-4">
      {collections.map((col) => {
        const active = activeCollections.has(col);
        return (
          <button
            key={col}
            onClick={() => onToggleCollection(col)}
            className={`text-xs px-2.5 py-1 rounded-full border transition-colors cursor-pointer ${
              active
                ? "bg-neutral-900 text-white border-neutral-900"
                : "bg-white text-neutral-600 border-neutral-200 hover:border-neutral-300"
            }`}
          >
            {col}
          </button>
        );
      })}
      {gradings.length > 1 &&
        gradings.map((g) => {
          const active = activeGradings.has(g);
          return (
            <button
              key={g}
              onClick={() => onToggleGrading(g)}
              className={`text-xs px-2.5 py-1 rounded-full border transition-colors cursor-pointer ${
                active
                  ? "bg-neutral-900 text-white border-neutral-900"
                  : "bg-white text-neutral-600 border-neutral-200 hover:border-neutral-300"
              }`}
            >
              {g}
            </button>
          );
        })}
    </div>
  );
}
```

**Step 2: Integrate FilterChips into SearchView**

In `src/components/search-view.tsx`, add filter state and wire up the chips. Add these imports and state:

Add import at top:
```typescript
import { FilterChips } from "@/components/filter-chips";
import type { Grading } from "@/lib/types";
```

Add state after `debounceRef`:
```typescript
const [activeCollections, setActiveCollections] = useState<Set<string>>(new Set());
const [activeGradings, setActiveGradings] = useState<Set<Grading>>(new Set());
```

Add derived values before the JSX `return`:
```typescript
// Derive unique collections and gradings from results
const resultCollections = [...new Set(results.map((r) => r.hadith.collection))];
const resultGradings = [...new Set(results.map((r) => r.hadith.grading).filter((g) => g !== "Unknown"))] as Grading[];

// Filter results
const filteredResults = results.filter((r) => {
  if (activeCollections.size > 0 && !activeCollections.has(r.hadith.collection)) return false;
  if (activeGradings.size > 0 && !activeGradings.has(r.hadith.grading)) return false;
  return true;
});

function toggleCollection(col: string) {
  setActiveCollections((prev) => {
    const next = new Set(prev);
    if (next.has(col)) next.delete(col);
    else next.add(col);
    return next;
  });
}

function toggleGrading(g: Grading) {
  setActiveGradings((prev) => {
    const next = new Set(prev);
    if (next.has(g)) next.delete(g);
    else next.add(g);
    return next;
  });
}
```

Reset filters when query changes — add to the `handleChange` function after clearing the debounce:
```typescript
setActiveCollections(new Set());
setActiveGradings(new Set());
```

In the results section JSX, add FilterChips before the results map, and change `results.map` to `filteredResults.map`:

```tsx
<section id="results" className="space-y-3 pb-16">
  {results.length > 0 && (
    <FilterChips
      collections={resultCollections}
      gradings={resultGradings}
      activeCollections={activeCollections}
      activeGradings={activeGradings}
      onToggleCollection={toggleCollection}
      onToggleGrading={toggleGrading}
    />
  )}
  {filteredResults.map((r) => (
    <ResultCard key={r.hadith.id} result={r} query={query} />
  ))}

  {hasSearched && results.length === 0 && !searching && (
    ...existing "not found" markup unchanged...
  )}
</section>
```

**Step 3: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Searching shows filter chips above results. Clicking a chip filters the results.

**Step 4: Commit**

```bash
git add src/components/filter-chips.tsx src/components/search-view.tsx
git commit -m "feat: add filter chips for search results"
```

---

### Task 11: Update ResultCard with clickable reference and detail-page share URL

**Files:**
- Modify: `src/components/result-card.tsx`

**Step 1: Update ResultCard**

Two changes:
1. Make the reference (`<h3>`) a link to the hadith detail page.
2. Change the share URL from the search query URL to the hadith detail URL.

Add imports at top of file:
```typescript
import { hadithUrl } from "@/lib/router";
import { slugFromName } from "@/lib/collections";
```

Replace the `shareUrl` computation:
```typescript
// Old:
const shareUrl = `${typeof window !== "undefined" ? window.location.origin : ""}?q=${encodeURIComponent(query)}`;

// New:
const slug = slugFromName(hadith.collection);
const detailPath = hadithUrl(slug, hadith.hadithNumber);
const shareUrl = `${typeof window !== "undefined" ? window.location.origin : ""}${detailPath}`;
```

Replace the reference `<h3>`:
```tsx
// Old:
<h3 className="text-sm text-neutral-700 mb-1.5 font-medium">
  {hadith.reference}
</h3>

// New:
<h3 className="text-sm mb-1.5 font-medium">
  <a
    href={detailPath}
    className="text-neutral-700 hover:text-neutral-900 transition-colors"
  >
    {hadith.reference}
  </a>
</h3>
```

**Step 2: Verify build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Build passes. Result card references are clickable links. Share copies the detail page URL.

**Step 3: Commit**

```bash
git add src/components/result-card.tsx
git commit -m "feat: make result references link to detail page, update share URL"
```

---

### Task 12: Final verification and build

**Files:** None (verification only)

**Step 1: Full build**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run build`
Expected: Clean build with no errors or warnings.

**Step 2: Lint**

Run: `cd /Users/imaadmalik/Developer/hadith-check && npm run lint`
Expected: No lint errors.

**Step 3: Manual smoke test checklist**

Start the dev server (`npm run dev`) and verify:

1. **`/`** — Search page loads, search works, filter chips appear, results link to detail pages
2. **`/#/browse`** — Shows 17 collections in 3 groups with counts
3. **`/#/browse/sahih-al-bukhari`** — Shows paginated list, pagination works, items link to detail
4. **`/#/hadith/sahih-al-bukhari/1`** — Shows full hadith with Arabic text, copy buttons work
5. **Nav** — "Search" and "Browse" links work, active state shows correctly
6. **Browser back/forward** — Hash navigation works naturally
7. **Direct URL** — Paste `/#/hadith/sahih-muslim/1` into address bar, page loads correctly
8. **Share URL** — Click share on a result card, verify copied URL points to detail page
9. **Accessibility** — Tab through page, verify skip link works, screen reader labels present

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: final verification pass"
```

Only commit if there are actual changes (lint fixes, etc.). Skip if working tree is clean.
