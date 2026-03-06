import "server-only";
import { searchFts } from "./db";
import { semanticSearch } from "./semantic-search-server";
import type { Hadith } from "./types";

export async function hybridSearch(
  query: string,
  limit = 20,
): Promise<{ hadith: Hadith; score: number }[]> {
  // Run FTS and semantic search in parallel
  const [ftsResults, semanticResults] = await Promise.all([
    Promise.resolve(searchFts(query, limit * 2)),
    semanticSearch(query, limit * 2).catch(() => []),
  ]);

  // Reciprocal Rank Fusion
  const K = 60;
  const scores = new Map<number, number>();
  const hadithMap = new Map<number, Hadith>();

  ftsResults.forEach(({ hadith }, rank) => {
    const id = hadith.id;
    scores.set(id, (scores.get(id) ?? 0) + 1 / (K + rank + 1));
    hadithMap.set(id, hadith);
  });

  semanticResults.forEach(({ hadith }, rank) => {
    const id = hadith.id;
    scores.set(id, (scores.get(id) ?? 0) + 1 / (K + rank + 1));
    hadithMap.set(id, hadith);
  });

  const ranked = [...scores.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit);

  const maxScore = ranked[0]?.[1] ?? 1;

  return ranked.map(([id, score]) => ({
    hadith: hadithMap.get(id)!,
    score: Math.round((score / maxScore) * 100),
  }));
}
