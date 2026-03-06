import fs from "fs";
import path from "path";
import Database from "better-sqlite3";

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

// Slug mapping matching src/lib/collections.ts
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
  return COLLECTION_SLUGS[name] ?? name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

function cleanText(text: string): string {
  return text.replace(/\s+/g, " ").replace(/\n/g, " ").trim();
}

// --- Isnad parsing (from build-isnad.ts) ---

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stripDiacritics(text: string): string {
  return text.replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7-\u06E8\u06EA-\u06ED]/g, "");
}

const TRANSMISSION_VERBS_PLAIN = [
  "حدثنا", "حدثني", "أخبرنا", "أخبرني", "سمعت", "سمع", "عن",
];

const verbSplitPattern = TRANSMISSION_VERBS_PLAIN
  .map((v) => `(?<=^|\\s)${escapeRegex(v)}(?=\\s|$)`)
  .join("|");

const HONORIFIC_PATTERNS = [
  /رضي الله عنه(ا|م|ما)?/g,
  /رضى الله عنه(ا|م|ما)?/g,
  /صلى الله عليه وسلم/g,
  /عليه السلام/g,
  /عليها السلام/g,
  /أم المؤمنين/g,
];

const NON_NAME_SEGMENTS = new Set([
  "يقول", "أنه", "أنها", "في", "إن", "على", "هو", "هي", "لم", "قد",
  "كان", "ثم", "بهذا الحديث", "المنبر", "بهذا", "نحوه", "مثله", "فيه",
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
  name = name.replace(/\s+(قال|يقول|أنه|أنها|أنهم|بهذا|نحوه|مثله)$/g, "");
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
    if (/^(لما|بينا|إذ|فلما|وكان|فكان|كان|كنت|إذا|لا|ما|من|لك|به|هذا|ذلك|الذي|التي)/.test(name) && name.length > 15) continue;
    narrators.push(name);
  }

  if (narrators.length < 2) return null;
  return narrators;
}

// --- Main build ---

function main() {
  const dataDir = path.join(process.cwd(), "data", "hadith-json", "db", "by_book");
  const dbPath = path.join(process.cwd(), "data", "hadith.db");
  const embeddingsPath = path.join(process.cwd(), "public", "hadith-embeddings.bin");

  // Remove old DB if exists
  if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);

  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = OFF");

  // Create tables
  db.exec(`
    CREATE TABLE hadith (
      id INTEGER PRIMARY KEY,
      collection TEXT NOT NULL,
      collection_slug TEXT NOT NULL,
      hadith_number TEXT NOT NULL,
      narrator TEXT NOT NULL DEFAULT '',
      english TEXT NOT NULL,
      arabic TEXT NOT NULL DEFAULT '',
      grading TEXT NOT NULL DEFAULT '',
      graded_by TEXT NOT NULL DEFAULT '',
      UNIQUE(collection_slug, hadith_number)
    );

    CREATE TABLE isnad (
      hadith_id INTEGER PRIMARY KEY REFERENCES hadith(id),
      narrators TEXT NOT NULL
    );

    CREATE TABLE embeddings (
      hadith_id INTEGER PRIMARY KEY REFERENCES hadith(id),
      embedding BLOB NOT NULL
    );

    CREATE INDEX idx_hadith_lookup ON hadith(collection_slug, hadith_number);
    CREATE INDEX idx_hadith_collection ON hadith(collection_slug);
  `);

  const insertHadith = db.prepare(`
    INSERT INTO hadith (id, collection, collection_slug, hadith_number, narrator, english, arabic, grading, graded_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertIsnad = db.prepare(`
    INSERT INTO isnad (hadith_id, narrators) VALUES (?, ?)
  `);

  const insertEmbedding = db.prepare(`
    INSERT INTO embeddings (hadith_id, embedding) VALUES (?, ?)
  `);

  const dirs = ["the_9_books", "other_books", "forties"];
  let globalId = 0;
  let isnadCount = 0;

  const insertAll = db.transaction(() => {
    for (const dir of dirs) {
      const fullDir = path.join(dataDir, dir);
      if (!fs.existsSync(fullDir)) continue;

      const files = fs.readdirSync(fullDir).filter((f) => f.endsWith(".json")).sort();
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

          const grading = isSahih ? "Sahih" : "";
          const gradedBy = isSahih ? "Scholarly consensus (Ijma')" : "";

          insertHadith.run(
            globalId,
            collectionName,
            collectionSlug,
            String(h.idInBook),
            cleanText(h.english.narrator || ""),
            englishText,
            h.arabic || "",
            grading,
            gradedBy,
          );

          // Parse isnad
          const chain = parseIsnad(h.arabic);
          if (chain) {
            insertIsnad.run(globalId, JSON.stringify(chain));
            isnadCount++;
          }

          globalId++;
        }

        console.log(`Processed: ${collectionName} (${collectionSlug})`);
      }
    }
  });

  insertAll();
  console.log(`\nInserted ${globalId} hadith, ${isnadCount} with isnad chains`);

  // Create FTS5 virtual table
  console.log("Building FTS5 index...");
  db.exec(`
    CREATE VIRTUAL TABLE hadith_fts USING fts5(
      narrator, english,
      content=hadith, content_rowid=id,
      tokenize='porter unicode61'
    );

    INSERT INTO hadith_fts(rowid, narrator, english)
    SELECT id, narrator, english FROM hadith;
  `);
  console.log("FTS5 index built");

  // Import embeddings
  if (fs.existsSync(embeddingsPath)) {
    console.log("Importing embeddings...");
    const buffer = fs.readFileSync(embeddingsPath);
    const DIM = 384;
    const BYTES_PER_EMBEDDING = DIM * 4; // float32
    const count = buffer.length / BYTES_PER_EMBEDDING;

    if (count !== globalId) {
      console.warn(`Warning: embeddings count (${count}) != hadith count (${globalId})`);
    }

    const insertEmbeddings = db.transaction(() => {
      for (let i = 0; i < Math.min(count, globalId); i++) {
        const offset = i * BYTES_PER_EMBEDDING;
        const chunk = buffer.subarray(offset, offset + BYTES_PER_EMBEDDING);
        insertEmbedding.run(i, chunk);
      }
    });
    insertEmbeddings();
    console.log(`Imported ${Math.min(count, globalId)} embeddings`);
  } else {
    console.warn("No embeddings file found at", embeddingsPath);
  }

  // Optimize
  console.log("Running ANALYZE...");
  db.exec("ANALYZE");
  console.log("Running VACUUM...");
  db.exec("VACUUM");

  db.close();

  const dbSize = fs.statSync(dbPath).size;
  console.log(`\ndata/hadith.db: ${(dbSize / 1024 / 1024).toFixed(2)} MB`);
  console.log("Database build complete!");
}

main();
