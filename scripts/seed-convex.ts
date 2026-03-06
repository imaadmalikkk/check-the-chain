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

// --- Isnad parsing ---

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stripDiacritics(text: string): string {
  return text.replace(
    /[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7-\u06E8\u06EA-\u06ED]/g,
    ""
  );
}

const TRANSMISSION_VERBS_PLAIN = [
  "حدثنا",
  "حدثني",
  "أخبرنا",
  "أخبرني",
  "سمعت",
  "سمع",
  "عن",
];

const verbSplitPattern = TRANSMISSION_VERBS_PLAIN.map(
  (v) => `(?<=^|\\s)${escapeRegex(v)}(?=\\s|$)`
).join("|");

const HONORIFIC_PATTERNS = [
  /رضي الله عنه(ا|م|ما)?/g,
  /رضى الله عنه(ا|م|ما)?/g,
  /صلى الله عليه وسلم/g,
  /عليه السلام/g,
  /عليها السلام/g,
  /أم المؤمنين/g,
];

const NON_NAME_SEGMENTS = new Set([
  "يقول",
  "أنه",
  "أنها",
  "في",
  "إن",
  "على",
  "هو",
  "هي",
  "لم",
  "قد",
  "كان",
  "ثم",
  "بهذا الحديث",
  "المنبر",
  "بهذا",
  "نحوه",
  "مثله",
  "فيه",
]);

const MATN_MARKERS = [/[""«»\u201C\u201D‏]/];

function extractIsnadPortion(arabic: string): string {
  for (const marker of MATN_MARKERS) {
    const match = arabic.search(marker);
    if (match !== -1) return arabic.substring(0, match);
  }
  const plain = stripDiacritics(arabic);
  const prophetRef = plain.search(/رسول الله|النبي/);
  if (prophetRef !== -1) {
    const afterProphet = plain.indexOf("،", prophetRef);
    if (afterProphet !== -1) return arabic.substring(0, afterProphet);
    return arabic.substring(0, Math.min(prophetRef + 80, arabic.length));
  }
  return arabic.substring(0, Math.floor(arabic.length * 0.6));
}

function cleanName(name: string): string {
  for (const pattern of HONORIFIC_PATTERNS) {
    name = name.replace(pattern, " ");
  }
  name = name.replace(/ـ/g, "");
  for (const verb of TRANSMISSION_VERBS_PLAIN) {
    const re = new RegExp(`^${escapeRegex(verb)}\\s+`, "g");
    name = name.replace(re, "");
  }
  name = name.replace(/[،,:;.!?(){}\[\]]/g, " ");
  name = name.replace(/\s+/g, " ").trim();
  name = name.replace(
    /\s+(قال|يقول|أنه|أنها|أنهم|بهذا|نحوه|مثله)$/g,
    ""
  );
  name = name.replace(/\s+على المنبر$/g, "");
  name = name.replace(/\s+في حديثه$/g, "");
  return name.trim();
}

function parseIsnad(arabic: string): string[] | null {
  if (!arabic || arabic.length < 20) return null;
  const isnadPortion = extractIsnadPortion(arabic);
  if (isnadPortion.length < 10) return null;
  const plain = stripDiacritics(isnadPortion);
  const splitRegex = new RegExp(`(?:${verbSplitPattern})`, "g");
  const segments = plain.split(splitRegex);
  const narrators: string[] = [];

  for (const segment of segments) {
    const name = cleanName(segment);
    if (!name || name.length < 3 || name.length > 60) continue;
    if (NON_NAME_SEGMENTS.has(name)) continue;
    if (
      /^(لما|بينا|إذ|فلما|وكان|فكان|كان|كنت|إذا|لا|ما|من|لك|به|هذا|ذلك|الذي|التي)/.test(
        name
      ) &&
      name.length > 15
    )
      continue;
    narrators.push(name);
  }

  if (narrators.length < 2) return null;
  return narrators;
}

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

      for (const h of raw.hadiths) {
        const englishText = cleanText(h.english.text);
        if (!englishText) continue;

        const order = orderMap.get(collectionSlug) ?? 0;
        orderMap.set(collectionSlug, order + 1);

        const grading = isSahih ? "Sahih" : "";
        const gradedBy = isSahih ? "Scholarly consensus (Ijma')" : "";

        const chain = parseIsnad(h.arabic);
        if (chain) isnadCount++;

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
        };

        batch.push(doc);
        if (batch.length >= BATCH_SIZE) {
          await flushBatch();
          if (totalInserted % 500 === 0) {
            process.stdout.write(`\rInserted ${totalInserted} hadith...`);
          }
        }
      }

      console.log(`\nProcessed: ${collectionName} (${collectionSlug})`);
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
