"use client";

import { useState } from "react";
import type { SearchResult } from "@/lib/types";
import { hadithUrl } from "@/lib/router";
import { slugFromName } from "@/lib/collections";
import { GradingBadge } from "./grading-badge";

const STOP_WORDS = new Set([
  "the","a","an","and","or","but","in","on","at","to","for","of","with","by",
  "is","was","are","were","be","been","has","have","had","do","does","did",
  "will","would","could","should","may","might","shall","it","its","he","she",
  "his","her","they","them","their","we","us","our","you","your","i","me","my",
  "that","this","these","those","which","who","whom","what","when","where","how",
  "not","no","nor","if","then","than","so","as","from","into","about","said",
]);

function highlightMatch(text: string, query: string): React.ReactNode {
  if (!query.trim()) return text;

  const words = query
    .trim()
    .split(/\s+/)
    .filter((w) => w.length > 2 && !STOP_WORDS.has(w.toLowerCase()))
    .map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));

  if (words.length === 0) return text;

  const pattern = new RegExp(`(${words.join("|")})`, "gi");
  const parts = text.split(pattern);

  return parts.map((part, i) =>
    pattern.test(part) ? (
      <mark key={i} className="bg-amber-100 text-inherit rounded-sm px-0.5">
        {part}
      </mark>
    ) : (
      part
    )
  );
}

export function ResultCard({
  result,
  query,
}: {
  result: SearchResult;
  query: string;
}) {
  const [copied, setCopied] = useState(false);
  const { hadith, score } = result;

  const slug = slugFromName(hadith.collection);
  const detailPath = hadithUrl(slug, hadith.hadithNumber);
  const shareUrl = `${typeof window !== "undefined" ? window.location.origin : ""}${detailPath}`;

  function handleShare() {
    navigator.clipboard.writeText(shareUrl).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <article className="border border-neutral-200 rounded-lg p-5 sm:p-6 transition-colors hover:border-neutral-300">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-center gap-2.5 flex-wrap">
          {hadith.grading !== "Unknown" && (
            <GradingBadge grading={hadith.grading} />
          )}
          <span className="text-xs text-neutral-500 font-mono">
            {score}% match
          </span>
        </div>
        <button
          onClick={handleShare}
          className="text-xs text-neutral-500 hover:text-neutral-600 transition-colors shrink-0 cursor-pointer"
          title="Copy share link"
          aria-label={copied ? "Link copied" : "Copy share link"}
          aria-live="polite"
        >
          {copied ? "Copied!" : "Share"}
        </button>
      </div>

      <h3 className="text-sm mb-1.5 font-medium">
        <a
          href={detailPath}
          className="text-neutral-700 hover:text-neutral-900 transition-colors"
        >
          {hadith.reference}
        </a>
      </h3>

      {hadith.narrator && (
        <p className="text-sm text-neutral-500 mb-2 italic">
          {hadith.narrator}
        </p>
      )}

      <p className="text-base leading-relaxed text-neutral-800">
        {highlightMatch(hadith.english, query)}
      </p>

      {hadith.gradedBy && (
        <p className="text-xs text-neutral-500 mt-3">
          Graded by: {hadith.gradedBy}
        </p>
      )}
    </article>
  );
}
