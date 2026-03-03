"use client";

import { Index } from "flexsearch";
import {
  type CompactHadith,
  type Hadith,
  type SearchResult,
  parseCompactHadith,
} from "./types";
import {
  initSemanticSearch,
  semanticSearch,
  isSemanticReady,
} from "./semantic-search";

const STOP_WORDS = new Set([
  "the",
  "a",
  "an",
  "and",
  "or",
  "but",
  "in",
  "on",
  "at",
  "to",
  "for",
  "of",
  "with",
  "by",
  "is",
  "was",
  "are",
  "were",
  "be",
  "been",
  "has",
  "have",
  "had",
  "do",
  "does",
  "did",
  "will",
  "would",
  "could",
  "should",
  "may",
  "might",
  "shall",
  "it",
  "its",
  "he",
  "she",
  "his",
  "her",
  "they",
  "them",
  "their",
  "we",
  "us",
  "our",
  "you",
  "your",
  "i",
  "me",
  "my",
  "that",
  "this",
  "these",
  "those",
  "which",
  "who",
  "whom",
  "what",
  "when",
  "where",
  "how",
  "not",
  "no",
  "nor",
  "if",
  "then",
  "than",
  "so",
  "as",
  "from",
  "into",
  "about",
  "said",
]);

function removeStopWords(text: string): string {
  return text
    .split(/\s+/)
    .filter((w) => !STOP_WORDS.has(w.toLowerCase()))
    .join(" ");
}

let index: Index | null = null;
let hadithData: Hadith[] = [];
let loading: Promise<void> | null = null;

async function loadData(): Promise<void> {
  if (hadithData.length > 0) return;

  const res = await fetch("/hadith-data.json");
  const compact: CompactHadith[] = await res.json();

  hadithData = compact.map((c, i) => parseCompactHadith(c, i));

  index = new Index({
    tokenize: "forward",
    resolution: 9,
    cache: true,
  });

  for (const h of hadithData) {
    index.add(h.id, removeStopWords(`${h.narrator} ${h.english}`));
  }
}

export async function initSearch(): Promise<void> {
  if (!loading) {
    loading = loadData();
  }
  await loading;

  // Start semantic search in background — don't block
  initSemanticSearch().catch(() => {});
}

export async function searchHadith(
  query: string,
  limit = 20
): Promise<SearchResult[]> {
  await initSearch();
  if (!query.trim() || query.trim().length < 3) return [];

  // Use semantic search if ready
  if (isSemanticReady()) {
    return semanticSearch(query, hadithData, limit);
  }

  // Fallback: FlexSearch with stop words removed
  if (!index) return [];

  const cleaned = removeStopWords(query.trim());
  if (!cleaned) return [];

  const ids = index.search(cleaned, { limit });

  return (ids as number[]).map((id, rank) => ({
    hadith: hadithData[id],
    score: Math.max(0, Math.round(100 - rank * (80 / limit))),
  }));
}

export function isLoaded(): boolean {
  return hadithData.length > 0;
}
