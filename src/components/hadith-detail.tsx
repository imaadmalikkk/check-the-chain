"use client";

import { useState } from "react";
import Link from "next/link";
import { collectionUrl, chapterUrl, isnadUrl } from "@/lib/urls";
import { GradingBadge } from "@/components/grading-badge";
import { ShareCardPreview } from "@/components/share-card-preview";
import { renderShareCard } from "@/lib/share-card";
import type { ShareCardData } from "@/lib/share-card";
import type { Hadith } from "@/lib/types";
import type { CollectionMeta } from "@/lib/collections";

export function HadithDetail({
  hadith,
  collection,
  hasIsnad,
}: {
  hadith: Hadith;
  collection: CollectionMeta;
  hasIsnad: boolean;
}) {
  const [copied, setCopied] = useState<"link" | "text" | null>(null);
  const [cardBlob, setCardBlob] = useState<Blob | null>(null);
  const [cardData, setCardData] = useState<ShareCardData | null>(null);
  const [cardLoading, setCardLoading] = useState(false);

  const reference = `${collection.name} ${hadith.hadith_number}`;

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(window.location.href);
    } catch {
      fallbackCopy(window.location.href);
    }
    setCopied("link");
    setTimeout(() => setCopied(null), 2000);
  }

  async function copyText() {
    const text = `${reference}\n\n${hadith.english}${hadith.narrator ? `\n\n${hadith.narrator}` : ""}`;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      fallbackCopy(text);
    }
    setCopied("text");
    setTimeout(() => setCopied(null), 2000);
  }

  function fallbackCopy(text: string) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    document.body.removeChild(textarea);
  }

  async function generateCard() {
    if (cardLoading) return;
    setCardLoading(true);
    try {
      const data: ShareCardData = {
        english: hadith.english,
        narrator: hadith.narrator,
        reference,
        grading: (hadith.grading || "Unknown") as ShareCardData["grading"],
        gradedBy: hadith.graded_by,
        arabicText: hadith.arabic || undefined,
      };
      const blob = await renderShareCard(data);
      setCardData(data);
      setCardBlob(blob);
    } finally {
      setCardLoading(false);
    }
  }

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <Link
        href={hadith.chapter_id != null ? chapterUrl(collection.slug, hadith.chapter_id) : collectionUrl(collection.slug)}
        className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
      >
        &larr; {hadith.chapter_english || collection.name}
      </Link>

      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-1">
        {reference}
      </h1>
      {hadith.chapter_id != null && hadith.chapter_english && (
        <p className="text-sm text-neutral-500 mb-3">
          Book {hadith.chapter_id}
          {hadith.hadith_in_chapter != null && `, Hadith ${hadith.hadith_in_chapter}`}
          {" — "}
          {hadith.chapter_english}
        </p>
      )}
      {!(hadith.chapter_id != null && hadith.chapter_english) && <div className="mb-3" />}

      {hadith.grading && hadith.grading !== "Unknown" && (
        <div className="mb-6">
          <GradingBadge grading={hadith.grading} />
          {hadith.graded_by && (
            <span
              className="text-xs text-neutral-500 ml-2"
              title={
                hadith.graded_by.includes("consensus")
                  ? "All major Islamic scholars agree on the authenticity of hadith in this collection"
                  : hadith.graded_by === "Darussalam"
                    ? "Darussalam is a publisher, not a hadith scholar"
                    : undefined
              }
            >
              Graded by {hadith.graded_by}
              {hadith.graded_by === "Darussalam" && (
                <span className="text-neutral-400"> (publisher)</span>
              )}
            </span>
          )}
        </div>
      )}

      {hadith.arabic ? (
        <div className="bg-neutral-50 rounded-lg p-5 sm:p-6 mb-6" dir="rtl" lang="ar">
          <p className="text-xl sm:text-2xl leading-loose text-neutral-800">
            {hadith.arabic}
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

      <div className="flex flex-wrap gap-3" aria-live="polite">
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
        <button
          onClick={generateCard}
          disabled={cardLoading}
          className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors border border-neutral-200 rounded-md px-3 py-1.5 cursor-pointer disabled:opacity-50"
          aria-label="Share as image"
        >
          {cardLoading ? "Generating..." : "Share as image"}
        </button>
        {hasIsnad && (
          <Link
            href={isnadUrl(collection.slug, hadith.hadith_number)}
            className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors border border-neutral-200 rounded-md px-3 py-1.5"
          >
            View chain
          </Link>
        )}
      </div>

      {cardBlob && cardData && (
        <ShareCardPreview
          blob={cardBlob}
          data={cardData}
          hasArabic={!!hadith.arabic}
          filename={`${collection.slug}-${hadith.hadith_number}.png`}
          onClose={() => { setCardBlob(null); setCardData(null); }}
        />
      )}
    </div>
  );
}
