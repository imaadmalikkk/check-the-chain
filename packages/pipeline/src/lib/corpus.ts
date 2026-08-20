import fs from "node:fs";
import readline from "node:readline";
import { tableJsonl } from "./paths.ts";

/**
 * A hadith document as Convex stores it. Mirrors apps/web/convex/schema.ts.
 * `embedding` is present for every collection except Darimi, which has no
 * English translation and is therefore excluded from the app entirely.
 */
export interface ConvexHadith {
  _id: string;
  collection: string;
  collection_slug: string;
  hadith_number: string;
  order: number;
  narrator: string;
  english: string;
  arabic: string;
  grading: string;
  graded_by: string;
  isnad_narrators?: string[];
  embedding?: number[];
  chapter_id?: number;
  chapter_english?: string;
  hadith_in_chapter?: number;
}

export interface ConvexChapter {
  _id: string;
  collection_slug: string;
  chapter_id: number;
  name_english: string;
  name_arabic: string;
  hadith_count: number;
  order: number;
}

export interface ConvexCollectionCount {
  _id: string;
  collection_slug: string;
  count: number;
}

/**
 * Streams a Convex export JSONL file. These files are large — the hadith table
 * is ~700MB once embeddings are inlined as JSON arrays — so nothing here may
 * read the whole file into memory.
 */
export async function* streamTable<T>(table: string): AsyncGenerator<T> {
  const file = tableJsonl(table);
  if (!fs.existsSync(file)) {
    throw new Error(
      `Missing ${file}. Run \`npm run export -w @check-the-chain/pipeline\` first.`,
    );
  }
  const rl = readline.createInterface({
    input: fs.createReadStream(file, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (line.trim()) yield JSON.parse(line) as T;
  }
}

export async function readTable<T>(table: string): Promise<T[]> {
  const rows: T[] = [];
  for await (const row of streamTable<T>(table)) rows.push(row);
  return rows;
}

/**
 * The canonical ordering for the shipped corpus. SQLite row ids and
 * embeddings.bin row indexes are both assigned from this order, so it must be
 * total, deterministic, and identical across runs.
 */
export function compareCanonical(a: ConvexHadith, b: ConvexHadith): number {
  if (a.collection_slug !== b.collection_slug) {
    return a.collection_slug < b.collection_slug ? -1 : 1;
  }
  if (a.order !== b.order) return a.order - b.order;
  return a.hadith_number < b.hadith_number ? -1 : 1;
}
