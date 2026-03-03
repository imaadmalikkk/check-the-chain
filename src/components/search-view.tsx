"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { SearchInput } from "@/components/search-input";
import { ResultCard } from "@/components/result-card";
import { FilterChips } from "@/components/filter-chips";
import { initSearch, searchHadith } from "@/lib/search";
import {
  getSemanticStatus,
  getSemanticProgress,
  onSemanticStatusChange,
  type SemanticStatus,
} from "@/lib/semantic-search";
import type { SearchResult, Grading } from "@/lib/types";

export function SearchView() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [query, setQuery] = useState(searchParams.get("q") || "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [indexReady, setIndexReady] = useState(false);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [semanticStatus, setSemanticStatus] = useState<SemanticStatus>(getSemanticStatus);
  const [semanticProgress, setSemanticProgress] = useState(getSemanticProgress);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [activeCollections, setActiveCollections] = useState<Set<string>>(new Set());
  const [activeGradings, setActiveGradings] = useState<Set<Grading>>(new Set());

  const isReady = semanticStatus === "ready" || semanticStatus === "error";

  useEffect(() => {
    initSearch().then(() => setIndexReady(true));
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

  // Auto-search from URL param once semantic search is ready
  useEffect(() => {
    if (isReady && query) {
      const run = async () => { await doSearch(query); };
      run();
    }
  }, [isReady, doSearch, query]);

  function handleChange(value: string) {
    setQuery(value);

    const url = value.trim()
      ? `?q=${encodeURIComponent(value.trim())}`
      : "/";
    router.replace(url, { scroll: false });

    if (debounceRef.current) clearTimeout(debounceRef.current);
    setActiveCollections(new Set());
    setActiveGradings(new Set());
    debounceRef.current = setTimeout(() => {
      doSearch(value);
    }, 300);
  }

  const resultCollections = [...new Set(results.map((r) => r.hadith.collection))];
  const resultGradings = [...new Set(results.map((r) => r.hadith.grading).filter((g) => g !== "Unknown"))] as Grading[];

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
