"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { SearchInput } from "@/components/search-input";
import { ResultCard } from "@/components/result-card";
import { FilterChips } from "@/components/filter-chips";
import { useEmbedding } from "@/lib/use-embedding";
import type { SearchResult, Grading } from "@/lib/types";

export function SearchView() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [query, setQuery] = useState(searchParams.get("q") || "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [progressVisible, setProgressVisible] = useState(true);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [activeCollections, setActiveCollections] = useState<Set<string>>(new Set());
  const [activeGradings, setActiveGradings] = useState<Set<Grading>>(new Set());
  const { embed, ready: embeddingReady, progress } = useEmbedding();
  const hasAutoSearched = useRef(false);

  // Once ready, fade out progress bar then enable search
  useEffect(() => {
    if (embeddingReady) {
      const timer = setTimeout(() => setProgressVisible(false), 400);
      return () => clearTimeout(timer);
    }
  }, [embeddingReady]);

  const doSearch = useCallback(async (q: string) => {
    if (!q.trim() || q.trim().length < 3) {
      setResults([]);
      setHasSearched(false);
      return;
    }
    setSearching(true);
    try {
      const embedding = await embed(q.trim());
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: q.trim(), embedding, limit: 20 }),
      });
      const data = await res.json();
      setResults(data.results);
      setHasSearched(true);
    } finally {
      setSearching(false);
    }
  }, [embed]);

  // Auto-search from URL ?q= param once model is ready (not on mount)
  useEffect(() => {
    if (embeddingReady && query && !hasAutoSearched.current) {
      hasAutoSearched.current = true;
      doSearch(query);
    }
  }, [embeddingReady, query, doSearch]);

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
  const resultGradings = [...new Set(results.map((r) => r.hadith.grading).filter((g) => g && g !== "Unknown"))] as Grading[];

  const filteredResults = results.filter((r) => {
    if (activeCollections.size > 0 && !activeCollections.has(r.hadith.collection)) return false;
    if (activeGradings.size > 0 && !activeGradings.has(r.hadith.grading as Grading)) return false;
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

  return (
    <>
      <header className="pt-16 sm:pt-24 pb-8 sm:pb-12">
        <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-neutral-900">
          Check the Chain
        </h1>
        <p className="mt-2 text-sm text-neutral-500 leading-relaxed max-w-md">
          Verify hadith against 47,000+ narrations from
          Bukhari, Muslim, and 15 other major collections.
        </p>
      </header>

      <section className="mb-8">
        <SearchInput
          value={query}
          onChange={handleChange}
          isLoading={searching}
          disabled={!embeddingReady}
        />
        {progressVisible && (
          <div
            className="mt-2 transition-opacity duration-300"
            style={{ opacity: embeddingReady ? 0 : 1 }}
          >
            <div className="h-1 w-full rounded-full bg-neutral-100 overflow-hidden">
              <div
                className="h-full rounded-full bg-neutral-400 transition-[width] duration-300 ease-out"
                style={{ width: `${progress}%` }}
              />
            </div>
            <p className="mt-1.5 text-xs text-neutral-400">Preparing search...</p>
          </div>
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
          <ResultCard key={r.hadith._id} result={r} query={query} />
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
