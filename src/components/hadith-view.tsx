"use client";

import { useState, useEffect } from "react";
import { getCollectionBySlug } from "@/lib/collections";
import { collectionUrl } from "@/lib/router";
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
