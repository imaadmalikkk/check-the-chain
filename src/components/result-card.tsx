"use client";

import { useState } from "react";
import Link from "next/link";
import type { SearchResult } from "@/lib/types";
import { hadithUrl } from "@/lib/urls";
import { STOP_WORDS } from "@/lib/stop-words";
import { GradingBadge } from "./grading-badge";

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

  const detailPath = hadithUrl(hadith.collection_slug, hadith.hadith_number);
  const shareUrl = `${typeof window !== "undefined" ? window.location.origin : ""}${detailPath}`;
  const reference = `${hadith.collection} ${hadith.hadith_number}`;

  async function handleShare(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(shareUrl);
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = shareUrl;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <Link
      href={detailPath}
      className="block border border-neutral-200 rounded-lg p-5 sm:p-6 transition-colors hover:border-neutral-300"
    >
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-center gap-2.5 flex-wrap">
          {hadith.grading && hadith.grading !== "Unknown" && (
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

      <h3 className="text-sm mb-1.5 font-medium text-neutral-700">
        {reference}
      </h3>

      {hadith.narrator && (
        <p className="text-sm text-neutral-500 mb-2 italic">
          {hadith.narrator}
        </p>
      )}

      <p className="text-base leading-relaxed text-neutral-800">
        {highlightMatch(hadith.english, query)}
      </p>

      {hadith.graded_by && (
        <p className="text-xs text-neutral-500 mt-3">
          {hadith.graded_by}
        </p>
      )}
    </Link>
  );
}
