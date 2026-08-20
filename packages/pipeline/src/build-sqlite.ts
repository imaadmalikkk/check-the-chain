/**
 * Builds out/hadith.sqlite from the Convex export.
 *
 * The schema mirrors apps/web/convex/schema.ts, with Convex's vector index
 * replaced by a flat embeddings file and its search index replaced by FTS5.
 *
 * Row ids are dense (0..N-1) and assigned in canonical order. They double as
 * row indexes into embeddings.bin, which is why the canonical order lives in
 * lib/corpus.ts and why manifest.json records it — build-embeddings.ts reads
 * that manifest rather than re-deriving the order and hoping it matches.
 */
import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import {
  compareCanonical,
  streamTable,
  readTable,
  type ConvexChapter,
  type ConvexCollectionCount,
  type ConvexHadith,
} from "./lib/corpus.ts";
import { OUT_DIR } from "./lib/paths.ts";

/** Everything except the embedding, which build-embeddings.ts handles. */
type HadithRow = Omit<ConvexHadith, "embedding" | "_id">;

const SCHEMA = `
CREATE TABLE hadith (
  id               INTEGER PRIMARY KEY,
  collection       TEXT    NOT NULL,
  collection_slug  TEXT    NOT NULL,
  hadith_number    TEXT    NOT NULL,
  "order"          INTEGER NOT NULL,
  narrator         TEXT    NOT NULL DEFAULT '',
  english          TEXT    NOT NULL DEFAULT '',
  arabic           TEXT    NOT NULL DEFAULT '',
  grading          TEXT    NOT NULL DEFAULT '',
  graded_by        TEXT    NOT NULL DEFAULT '',
  isnad_narrators  TEXT,
  chapter_id       INTEGER,
  chapter_english  TEXT,
  hadith_in_chapter INTEGER
);

CREATE UNIQUE INDEX idx_slug_number ON hadith(collection_slug, hadith_number);
CREATE INDEX idx_collection_order ON hadith(collection_slug, "order");
CREATE INDEX idx_chapter_order ON hadith(collection_slug, chapter_id, "order");

-- Contentless-linked: the English text is stored once, in the hadith table.
-- remove_diacritics 2 handles the transliterated Arabic that runs through the
-- English translations ("Mu'adh", "Abu Hurayrah").
CREATE VIRTUAL TABLE hadith_fts USING fts5(
  english,
  content='hadith',
  content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE chapters (
  collection_slug TEXT    NOT NULL,
  chapter_id      INTEGER NOT NULL,
  name_english    TEXT    NOT NULL DEFAULT '',
  name_arabic     TEXT    NOT NULL DEFAULT '',
  hadith_count    INTEGER NOT NULL DEFAULT 0,
  "order"         INTEGER NOT NULL,
  PRIMARY KEY (collection_slug, chapter_id)
) WITHOUT ROWID;

CREATE INDEX idx_chapters_order ON chapters(collection_slug, "order");

CREATE TABLE collection_counts (
  collection_slug TEXT PRIMARY KEY,
  count           INTEGER NOT NULL
) WITHOUT ROWID;

-- Lets the app verify at launch that hadith.sqlite and embeddings.bin came
-- from the same pipeline run. Mismatched artifacts return the wrong hadith
-- for every semantic hit, silently.
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
`;

async function loadHadith(): Promise<HadithRow[]> {
  const rows: HadithRow[] = [];
  let withoutEmbedding = 0;
  let withoutEnglish = 0;

  for await (const doc of streamTable<ConvexHadith>("hadith")) {
    if (!doc.embedding) withoutEmbedding++;
    if (!doc.english?.trim()) withoutEnglish++;
    // Drop the embedding immediately — holding 47k × 384 floats as JS arrays
    // alongside the text would blow past the default heap.
    delete doc.embedding;
    rows.push(doc);
  }

  rows.sort(compareCanonical);

  console.log(`  ${rows.length} hadith`);
  if (withoutEmbedding > 0) console.log(`  ${withoutEmbedding} without an embedding`);
  if (withoutEnglish > 0) console.log(`  ${withoutEnglish} without English text`);

  return rows;
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const dbPath = path.join(OUT_DIR, "hadith.sqlite");
  fs.rmSync(dbPath, { force: true });

  console.log("Reading corpus...");
  const hadith = await loadHadith();
  const chapters = await readTable<ConvexChapter>("chapters");
  const counts = await readTable<ConvexCollectionCount>("collection_counts");
  console.log(`  ${chapters.length} chapters, ${counts.length} collections`);

  const db = new Database(dbPath);
  db.pragma("journal_mode = OFF");
  db.pragma("synchronous = OFF");
  db.exec(SCHEMA);

  console.log("Writing hadith...");
  const insertHadith = db.prepare(`
    INSERT INTO hadith (id, collection, collection_slug, hadith_number, "order",
                        narrator, english, arabic, grading, graded_by,
                        isnad_narrators, chapter_id, chapter_english, hadith_in_chapter)
    VALUES (@id, @collection, @collection_slug, @hadith_number, @order,
            @narrator, @english, @arabic, @grading, @graded_by,
            @isnad_narrators, @chapter_id, @chapter_english, @hadith_in_chapter)
  `);

  const manifestOrder: string[] = new Array(hadith.length);

  db.transaction(() => {
    hadith.forEach((h, id) => {
      manifestOrder[id] = `${h.collection_slug}/${h.hadith_number}`;
      insertHadith.run({
        id,
        collection: h.collection,
        collection_slug: h.collection_slug,
        hadith_number: h.hadith_number,
        order: h.order,
        narrator: h.narrator ?? "",
        english: h.english ?? "",
        arabic: h.arabic ?? "",
        grading: h.grading ?? "",
        graded_by: h.graded_by ?? "",
        isnad_narrators: h.isnad_narrators?.length ? JSON.stringify(h.isnad_narrators) : null,
        chapter_id: h.chapter_id ?? null,
        chapter_english: h.chapter_english ?? null,
        hadith_in_chapter: h.hadith_in_chapter ?? null,
      });
    });
  })();

  console.log("Writing chapters and counts...");
  const insertChapter = db.prepare(`
    INSERT OR REPLACE INTO chapters (collection_slug, chapter_id, name_english, name_arabic, hadith_count, "order")
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const insertCount = db.prepare(
    `INSERT OR REPLACE INTO collection_counts (collection_slug, count) VALUES (?, ?)`,
  );
  db.transaction(() => {
    for (const c of chapters) {
      insertChapter.run(
        c.collection_slug,
        c.chapter_id,
        c.name_english ?? "",
        c.name_arabic ?? "",
        c.hadith_count ?? 0,
        c.order,
      );
    }
    for (const c of counts) insertCount.run(c.collection_slug, c.count);
  })();

  console.log("Building FTS5 index...");
  // External-content FTS tables are not populated by the base table's INSERTs;
  // the index has to be filled explicitly.
  db.exec(`INSERT INTO hadith_fts(rowid, english) SELECT id, english FROM hadith`);
  db.exec(`INSERT INTO hadith_fts(hadith_fts) VALUES('optimize')`);

  // A content hash over the canonical order. build-embeddings.ts stamps the
  // same value into embeddings.json; the app refuses to run if they differ.
  const revision = revisionOf(manifestOrder);
  const insertMeta = db.prepare(`INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)`);
  db.transaction(() => {
    insertMeta.run("revision", revision);
    insertMeta.run("hadith_count", String(hadith.length));
    insertMeta.run("schema_version", "1");
  })();

  console.log("Vacuuming...");
  db.pragma("journal_mode = DELETE");
  db.exec("VACUUM");
  db.close();

  fs.writeFileSync(
    path.join(OUT_DIR, "manifest.json"),
    JSON.stringify({ revision, count: hadith.length, order: manifestOrder }),
  );

  const mb = fs.statSync(dbPath).size / 1e6;
  console.log(`\nhadith.sqlite  ${mb.toFixed(1)} MB  (revision ${revision})`);
}

function revisionOf(order: string[]): string {
  // Cheap, stable, order-sensitive digest. Not cryptographic — it only needs to
  // catch "these two artifacts were built from different runs".
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (let i = 0; i < order.length; i++) {
    const s = order[i];
    for (let j = 0; j < s.length; j++) {
      h1 = Math.imul(h1 ^ s.charCodeAt(j), 0x01000193) >>> 0;
      h2 = Math.imul(h2 + s.charCodeAt(j) + i, 0x85ebca6b) >>> 0;
    }
  }
  return `${h1.toString(16).padStart(8, "0")}${h2.toString(16).padStart(8, "0")}`;
}

main();
