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
