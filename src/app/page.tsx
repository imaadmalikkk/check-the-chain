"use client";

import { useState, useEffect, useCallback, useRef, Suspense } from "react";
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

function SearchApp() {
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

  // Auto-search from URL param once semantic search is ready
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
    <div className="min-h-screen flex flex-col">
      <a href="#results" className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-neutral-900 focus:text-white focus:rounded-md focus:text-sm">
        Skip to results
      </a>
      <main className="flex-1 w-full max-w-2xl mx-auto px-4 sm:px-6">
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
      </main>

      <footer className="border-t border-neutral-100 py-8 px-4 sm:px-6">
        <div className="max-w-2xl mx-auto">
          <p className="text-xs text-neutral-500 leading-relaxed mb-3">
            This tool searches major hadith collections. It is not a substitute
            for scholarly verification.
          </p>
          <p className="text-xs text-neutral-500 leading-relaxed mb-4">
            Collections: Bukhari, Muslim, Tirmidhi, Abu Dawud, Nasa&apos;i, Ibn
            Majah, Muwatta Malik, Musnad Ahmad, Darimi, Riyad as-Salihin,
            Mishkat al-Masabih, Bulugh al-Maram, Al-Adab Al-Mufrad, Shamail
            Muhammadiyah, Nawawi 40, Qudsi 40.
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
      <SearchApp />
    </Suspense>
  );
}
