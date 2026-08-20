import fs from "fs";
import path from "path";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";

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
  const url = process.env.CONVEX_URL || process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) {
    console.error("CONVEX_URL or NEXT_PUBLIC_CONVEX_URL environment variable is required");
    process.exit(1);
  }

  const client = new ConvexHttpClient(url);
  const dataDir = path.join(process.cwd(), "data", "hadith-json", "db", "by_book");
  const dirs = ["the_9_books", "other_books", "forties"];

  // Clear existing chapters
  console.log("Clearing existing chapters...");
  let cleared: number;
  do {
    cleared = await withRetry(() =>
      client.mutation(api.hadith.clearAll, { table: "chapters" })
    );
    if (cleared > 0) console.log(`  Cleared ${cleared} chapter docs`);
  } while (cleared > 0);
  console.log("Chapters cleared.\n");

  const PATCH_BATCH_SIZE = 50;
  let totalPatched = 0;
  let totalChaptersInserted = 0;

  for (const dir of dirs) {
    const fullDir = path.join(dataDir, dir);
    if (!fs.existsSync(fullDir)) continue;

    const files = fs
      .readdirSync(fullDir)
      .filter((f) => f.endsWith(".json"))
      .sort();

    for (const file of files) {
      const filePath = path.join(fullDir, file);
      const raw: BookFile = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const collectionName = raw.metadata.english.title;
      const collectionSlug = slugFromName(collectionName);

      // Build chapter lookup (skip chapters with null IDs)
      const chapterMap = new Map<number, { english: string; arabic: string }>();
      for (const ch of raw.chapters) {
        if (ch.id == null) continue;
        chapterMap.set(ch.id, { english: ch.english, arabic: ch.arabic });
      }

      // Build hadith-to-chapter mapping from source data
      // Map hadith_number (idInBook as string) → { chapterId, chapterEnglish, positionInChapter }
      const chapterPositionCounters = new Map<number, number>();
      const hadithChapterInfo = new Map<string, {
        chapterId: number;
        chapterEnglish: string;
        hadithInChapter: number;
      }>();

      for (const h of raw.hadiths) {
        if (!h.english.text.trim()) continue; // Skip empty (matches seed behavior)
        if (h.chapterId == null) continue; // Skip hadith with null chapter
        const posInChapter = (chapterPositionCounters.get(h.chapterId) ?? 0) + 1;
        chapterPositionCounters.set(h.chapterId, posInChapter);
        hadithChapterInfo.set(String(h.idInBook), {
          chapterId: h.chapterId,
          chapterEnglish: chapterMap.get(h.chapterId)?.english ?? "",
          hadithInChapter: posInChapter,
        });
      }

      // Insert chapters (skip chapters with null IDs)
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
        totalChaptersInserted += chapterDocs.length;
      }

      // Fetch existing hadith and patch chapter fields
      let offset = 0;
      const FETCH_LIMIT = 500;
      let collectionPatched = 0;

      while (true) {
        const existing = await withRetry(() =>
          client.query(api.hadith.listBySlug, { slug: collectionSlug, offset, limit: FETCH_LIMIT })
        );
        if (existing.length === 0) break;

        type Patch = {
          id: typeof existing[0]["_id"];
          chapter_id: number;
          chapter_english: string;
          hadith_in_chapter: number;
        };
        const patches: Patch[] = [];

        for (const doc of existing) {
          const info = hadithChapterInfo.get(doc.hadith_number);
          if (info) {
            patches.push({
              id: doc._id,
              chapter_id: info.chapterId,
              chapter_english: info.chapterEnglish,
              hadith_in_chapter: info.hadithInChapter,
            });
          }
        }

        // Send patches in batches
        for (let i = 0; i < patches.length; i += PATCH_BATCH_SIZE) {
          const batch = patches.slice(i, i + PATCH_BATCH_SIZE);
          await withRetry(() =>
            client.mutation(api.hadith.patchChapterFields, { patches: batch })
          );
          totalPatched += batch.length;
          collectionPatched += batch.length;
          await sleep(50);
        }

        offset += FETCH_LIMIT;
        if (existing.length < FETCH_LIMIT) break;
      }

      console.log(
        `${collectionName}: ${chapterDocs.length} chapters, ${collectionPatched} hadith patched`
      );
    }
  }

  console.log(
    `\nDone! Inserted ${totalChaptersInserted} chapters, patched ${totalPatched} hadith with chapter data.`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
