import fs from "fs";
import path from "path";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";
import { parseIsnad } from "./lib/isnad.ts";

interface RawHadith {
  id: number;
  idInBook: number;
  arabic: string;
  english: { narrator: string; text: string };
  chapterId: number;
  bookId: number;
}

interface BookFile {
  id: number;
  metadata: {
    id: number;
    length: number;
    arabic: { title: string; author: string };
    english: { title: string; author: string };
  };
  chapters: { id: number; bookId: number; arabic: string; english: string }[];
  hadiths: RawHadith[];
}

const SAHIH_COLLECTIONS = new Set(["bukhari", "muslim"]);

const COLLECTION_SLUGS: Record<string, string> = {
  "Sahih al-Bukhari": "sahih-al-bukhari",
  "Sahih Muslim": "sahih-muslim",
  "Sunan al-Nasa'i": "sunan-al-nasai",
  "Sunan Abi Dawud": "sunan-abi-dawud",
  "Sunan Ibn Majah": "sunan-ibn-majah",
  "Jami' al-Tirmidhi": "jami-al-tirmidhi",
  "Muwatta Malik": "muwatta-malik",
  "Musnad Ahmad ibn Hanbal": "musnad-ahmad",
  "Mishkat al-Masabih": "mishkat-al-masabih",
  "Riyad as-Salihin": "riyad-as-salihin",
  "Bulugh al-Maram": "bulugh-al-maram",
  "Al-Adab Al-Mufrad": "al-adab-al-mufrad",
  "Shama'il Muhammadiyah": "shamail-muhammadiyah",
  "The Forty Hadith of Imam Nawawi": "nawawi-40",
  "The Forty Hadith Qudsi": "qudsi-40",
  "The Forty Hadith of Shah Waliullah": "shah-waliullah-40",
};

function slugFromName(name: string): string {
  return (
    COLLECTION_SLUGS[name] ??
    name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "")
  );
}

function cleanText(text: string): string {
  return text.replace(/\s+/g, " ").replace(/\n/g, " ").trim();
}

// --- Isnad parsing lives in ./lib/isnad.ts, shared with reparse-isnad.ts ---

// --- Main seeding ---

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withRetry<T>(
  fn: () => Promise<T>,
  retries = 3,
  baseDelay = 2000
): Promise<T> {
  for (let i = 0; i <= retries; i++) {
    try {
      return await fn();
    } catch (err) {
      if (i === retries) throw err;
      const delay = baseDelay * Math.pow(2, i);
      console.warn(`\nRetry ${i + 1}/${retries} after ${delay}ms...`);
      await sleep(delay);
    }
  }
  throw new Error("unreachable");
}

async function main() {
  const url = process.env.CONVEX_URL;
  if (!url) {
    console.error("CONVEX_URL environment variable is required");
    process.exit(1);
  }

  const client = new ConvexHttpClient(url);
  const dataDir = path.join(
    process.cwd(),
    "data",
    "hadith-json",
    "db",
    "by_book"
  );

  // Clear existing data first
  console.log("Clearing existing data...");
  let cleared: number;
  do {
    cleared = await withRetry(() =>
      client.mutation(api.hadith.clearAll, { table: "hadith" })
    );
    if (cleared > 0) console.log(`  Cleared ${cleared} hadith docs`);
  } while (cleared > 0);
  do {
    cleared = await withRetry(() =>
      client.mutation(api.hadith.clearAll, { table: "collection_counts" })
    );
    if (cleared > 0) console.log(`  Cleared ${cleared} count docs`);
  } while (cleared > 0);
  do {
    cleared = await withRetry(() =>
      client.mutation(api.hadith.clearAll, { table: "chapters" })
    );
    if (cleared > 0) console.log(`  Cleared ${cleared} chapter docs`);
  } while (cleared > 0);
  console.log("Data cleared.\n");

  const dirs = ["the_9_books", "other_books", "forties"];
  const orderMap = new Map<string, number>();

  let totalInserted = 0;
  let isnadCount = 0;
  const BATCH_SIZE = 25;

  type HadithDoc = {
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
    chapter_id?: number;
    chapter_english?: string;
    hadith_in_chapter?: number;
  };

  let batch: HadithDoc[] = [];

  async function flushBatch() {
    if (batch.length === 0) return;
    const toInsert = [...batch];
    batch = [];
    await withRetry(() =>
      client.mutation(api.hadith.insertBatch, { hadith: toInsert })
    );
    totalInserted += toInsert.length;
    // Small delay to avoid overwhelming the server
    await sleep(50);
  }

  for (const dir of dirs) {
    const fullDir = path.join(dataDir, dir);
    if (!fs.existsSync(fullDir)) continue;

    const files = fs
      .readdirSync(fullDir)
      .filter((f) => f.endsWith(".json"))
      .sort();
    for (const file of files) {
      const collectionKey = file.replace(".json", "");
      const filePath = path.join(fullDir, file);
      const raw: BookFile = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const collectionName = raw.metadata.english.title;
      const collectionSlug = slugFromName(collectionName);
      const isSahih = SAHIH_COLLECTIONS.has(collectionKey);

      // Build chapter lookup (skip chapters with null IDs)
      const chapterMap = new Map<number, { english: string; arabic: string }>();
      for (const ch of raw.chapters) {
        if (ch.id == null) continue;
        chapterMap.set(ch.id, { english: ch.english, arabic: ch.arabic });
      }

      // Track hadith position within each chapter for "Book X, Hadith Y" references
      const chapterPositionCounters = new Map<number, number>();

      for (const h of raw.hadiths) {
        const englishText = cleanText(h.english.text);
        if (!englishText) continue;

        const order = orderMap.get(collectionSlug) ?? 0;
        orderMap.set(collectionSlug, order + 1);

        const grading = isSahih ? "Sahih" : "";
        const gradedBy = isSahih ? "Scholarly consensus (Ijma')" : "";

        const chain = parseIsnad(h.arabic);
        if (chain) isnadCount++;

        const hasChapter = h.chapterId != null;
        const chapterInfo = hasChapter ? chapterMap.get(h.chapterId) : undefined;
        let posInChapter: number | undefined;
        if (hasChapter) {
          posInChapter = (chapterPositionCounters.get(h.chapterId) ?? 0) + 1;
          chapterPositionCounters.set(h.chapterId, posInChapter);
        }

        const doc: HadithDoc = {
          collection: collectionName,
          collection_slug: collectionSlug,
          hadith_number: String(h.idInBook),
          order,
          narrator: cleanText(h.english.narrator || ""),
          english: englishText,
          arabic: h.arabic || "",
          grading,
          graded_by: gradedBy,
          ...(chain ? { isnad_narrators: chain } : {}),
          ...(hasChapter ? {
            chapter_id: h.chapterId,
            chapter_english: chapterInfo?.english ?? "",
            hadith_in_chapter: posInChapter,
          } : {}),
        };

        batch.push(doc);
        if (batch.length >= BATCH_SIZE) {
          await flushBatch();
          if (totalInserted % 500 === 0) {
            process.stdout.write(`\rInserted ${totalInserted} hadith...`);
          }
        }
      }

      // Insert chapters for this collection (skip chapters with null IDs)
      const chapterDocs = raw.chapters
        .filter((ch) => ch.id != null)
        .map((ch, idx) => ({
          collection_slug: collectionSlug,
          chapter_id: ch.id,
          name_english: ch.english,
          name_arabic: ch.arabic,
          hadith_count: chapterPositionCounters.get(ch.id) ?? 0,
          order: idx,
        }));
      if (chapterDocs.length > 0) {
        await withRetry(() =>
          client.mutation(api.hadith.insertChaptersBatch, { chapters: chapterDocs })
        );
      }

      console.log(`\nProcessed: ${collectionName} (${collectionSlug}) — ${chapterDocs.length} chapters`);
    }
  }

  // Flush remaining
  await flushBatch();
  console.log(`\nInserted ${totalInserted} hadith, ${isnadCount} with isnad chains`);

  // Insert collection counts
  const counts = [...orderMap.entries()].map(([slug, count]) => ({
    collection_slug: slug,
    count,
  }));
  await withRetry(() =>
    client.mutation(api.hadith.insertCollectionCounts, { counts })
  );
  console.log(`Inserted ${counts.length} collection counts`);

  console.log("Seeding complete!");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
