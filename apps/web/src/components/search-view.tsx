"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { SearchInput } from "@/components/search-input";
import { ResultCard } from "@/components/result-card";
import { FilterChips } from "@/components/filter-chips";
import { useEmbedding } from "@/lib/use-embedding";
import { hadithUrl } from "@/lib/urls";
import type { SearchResult, Grading, Hadith } from "@/lib/types";

export function SearchView() {
  const searchParams = useSearchParams();
  const [query, setQuery] = useState(searchParams.get("q") || "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [progressVisible, setProgressVisible] = useState(true);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [activeCollections, setActiveCollections] = useState<Set<string>>(new Set());
  const [activeGradings, setActiveGradings] = useState<Set<Grading>>(new Set());
  const [page, setPage] = useState(0);
  const RESULTS_PER_PAGE = 20;
  const { embed, ready: embeddingReady, progress } = useEmbedding();
  const hasAutoSearched = useRef(false);
  const abortRef = useRef<AbortController | null>(null);
  const [dailyHadith, setDailyHadith] = useState<Hadith | null>(null);

  // Once ready, fade out progress bar then enable search
  useEffect(() => {
    if (embeddingReady) {
      const timer = setTimeout(() => setProgressVisible(false), 400);
      return () => clearTimeout(timer);
    }
  }, [embeddingReady]);

  // Clean up debounce timer and in-flight requests on unmount
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      abortRef.current?.abort();
    };
  }, []);

  // Fetch Hadith of the Day
  useEffect(() => {
    fetch("/api/hadith-of-the-day")
      .then((res) => res.json())
      .then((data) => { if (data.hadith) setDailyHadith(data.hadith); })
      .catch(() => {});
  }, []);

  const doSearch = useCallback(async (q: string) => {
    if (!q.trim() || q.trim().length < 3) {
      setResults([]);
      setHasSearched(false);
      return;
    }

    // Abort any in-flight search
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setSearching(true);
    try {
      const embedding = await embed(q.trim());
      if (controller.signal.aborted) return;
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: q.trim(), embedding, limit: 100 }),
        signal: controller.signal,
      });
      const data = await res.json();
      if (controller.signal.aborted) return;
      setResults(data.results);
      setHasSearched(true);
      // On mobile, scroll results into view above the keyboard
      setTimeout(() => {
        document.getElementById("results")?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 100);
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      console.error("Search failed:", err);
    } finally {
      if (!controller.signal.aborted) setSearching(false);
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
    window.history.replaceState(null, "", url);

    if (debounceRef.current) clearTimeout(debounceRef.current);
    setActiveCollections(new Set());
    setActiveGradings(new Set());
    setPage(0);
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
    setPage(0);
  }

  function toggleGrading(g: Grading) {
    setActiveGradings((prev) => {
      const next = new Set(prev);
      if (next.has(g)) next.delete(g);
      else next.add(g);
      return next;
    });
    setPage(0);
  }

  return (
    <>
      <header className="pt-16 sm:pt-24 pb-8 sm:pb-12">
        <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-neutral-900">
          Check the Chain
        </h1>
        <p className="mt-2 text-sm text-neutral-500 leading-relaxed max-w-lg">
          Search by meaning, not just keywords. Paste any hadith and find its
          source, grading, and chain of narrators across the major collections.
        </p>
        {!query && !hasSearched && (
          <div className="flex gap-4 mt-4 text-xs text-neutral-400 font-mono">
            <span>47,000+ hadith</span>
            <span className="text-neutral-200">|</span>
            <span>16 collections</span>
            <span className="text-neutral-200">|</span>
            <span>605 chapters</span>
          </div>
        )}
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

      {!query && !hasSearched && (
        <section className="mb-8 space-y-8">
          {/* Hadith of the Day */}
          {dailyHadith && (
            <Link
              href={hadithUrl(dailyHadith.collection_slug, dailyHadith.hadith_number)}
              className="block border border-neutral-200 rounded-lg p-5 hover:border-neutral-300 transition-colors"
            >
              <p className="text-xs text-neutral-400 mb-2">Hadith of the Day</p>
              <p className="text-sm leading-relaxed text-neutral-800">
                {dailyHadith.english.length > 250
                  ? dailyHadith.english.slice(0, 250) + "..."
                  : dailyHadith.english}
              </p>
              <p className="text-xs text-neutral-500 mt-3">
                {dailyHadith.collection} {dailyHadith.hadith_number}
              </p>
            </Link>
          )}

          {/* Example queries */}
          <div>
            <p className="text-xs text-neutral-400 mb-2">Try an example —</p>
            <div className="flex flex-wrap gap-2">
              {[
                "The reward of deeds depends upon the intentions",
                "Whoever believes in Allah and the Last Day should speak good or remain silent",
                "The best of you are those who are best to their families",
                "Do not be angry",
              ].map((example) => (
                <button
                  key={example}
                  onClick={() => handleChange(example)}
                  disabled={!embeddingReady}
                  className="rounded-full border border-neutral-200 bg-white px-3 py-1.5 text-xs text-neutral-600 hover:border-neutral-300 hover:text-neutral-800 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {example}
                </button>
              ))}
            </div>
          </div>

          {/* Browse collections */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <p className="text-xs text-neutral-400">Browse collections</p>
              <Link href="/browse" className="text-xs text-neutral-400 hover:text-neutral-600 transition-colors">
                View all &rarr;
              </Link>
            </div>
            <div className="grid grid-cols-3 sm:grid-cols-3 gap-2">
              {[
                { name: "Bukhari", slug: "sahih-al-bukhari" },
                { name: "Muslim", slug: "sahih-muslim" },
                { name: "Tirmidhi", slug: "jami-al-tirmidhi" },
                { name: "Abu Dawud", slug: "sunan-abi-dawud" },
                { name: "Nawawi 40", slug: "nawawi-40" },
                { name: "Ibn Majah", slug: "sunan-ibn-majah" },
              ].map((col) => (
                <Link
                  key={col.slug}
                  href={`/browse/${col.slug}`}
                  className="rounded-lg border border-neutral-300 px-3 py-2.5 text-xs text-neutral-600 hover:border-neutral-400 hover:text-neutral-800 transition-colors text-center"
                >
                  {col.name}
                </Link>
              ))}
            </div>
          </div>
        </section>
      )}

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
        {(() => {
          const totalPages = Math.ceil(filteredResults.length / RESULTS_PER_PAGE);
          const paginatedResults = filteredResults.slice(
            page * RESULTS_PER_PAGE,
            (page + 1) * RESULTS_PER_PAGE
          );
          return (
            <>
              {paginatedResults.map((r) => (
                <ResultCard key={r.hadith._id} result={r} query={query} />
              ))}

              {totalPages > 1 && (
                <div className="flex items-center justify-between pt-4 border-t border-neutral-100">
                  {page > 0 ? (
                    <button
                      onClick={() => setPage(page - 1)}
                      className="text-sm text-neutral-600 hover:text-neutral-900 transition-colors cursor-pointer"
                    >
                      Previous
                    </button>
                  ) : (
                    <span className="text-sm text-neutral-300">Previous</span>
                  )}
                  <span className="text-xs text-neutral-400 font-mono">
                    {page + 1} / {totalPages}
                  </span>
                  {page < totalPages - 1 ? (
                    <button
                      onClick={() => setPage(page + 1)}
                      className="text-sm text-neutral-600 hover:text-neutral-900 transition-colors cursor-pointer"
                    >
                      Next
                    </button>
                  ) : (
                    <span className="text-sm text-neutral-300">Next</span>
                  )}
                </div>
              )}
            </>
          );
        })()}

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
