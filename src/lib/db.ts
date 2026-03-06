import "server-only";
import Database from "better-sqlite3";
import path from "path";
import type { Hadith } from "./types";

let db: Database.Database | null = null;

function getDb(): Database.Database {
  if (!db) {
    const dbPath = path.join(process.cwd(), "data", "hadith.db");
    db = new Database(dbPath, { readonly: true });
    db.pragma("journal_mode = WAL");
  }
  return db;
}

export function getHadithByRef(slug: string, number: string): Hadith | undefined {
  const row = getDb()
    .prepare("SELECT * FROM hadith WHERE collection_slug = ? AND hadith_number = ?")
    .get(slug, number) as Hadith | undefined;
  return row;
}

export function getHadithByCollectionPaginated(
  slug: string,
  page: number,
  pageSize = 50,
): { hadith: Hadith[]; total: number } {
  const d = getDb();
  const total = (d.prepare("SELECT COUNT(*) as cnt FROM hadith WHERE collection_slug = ?").get(slug) as { cnt: number }).cnt;
  const hadith = d
    .prepare("SELECT * FROM hadith WHERE collection_slug = ? ORDER BY id LIMIT ? OFFSET ?")
    .all(slug, pageSize, page * pageSize) as Hadith[];
  return { hadith, total };
}

export function getCollectionCounts(): Map<string, number> {
  const rows = getDb()
    .prepare("SELECT collection_slug, COUNT(*) as cnt FROM hadith GROUP BY collection_slug")
    .all() as { collection_slug: string; cnt: number }[];
  return new Map(rows.map((r) => [r.collection_slug, r.cnt]));
}

export function searchFts(query: string, limit = 20): { hadith: Hadith; score: number }[] {
  const rows = getDb()
    .prepare(`
      SELECT h.*, rank
      FROM hadith_fts fts
      JOIN hadith h ON h.id = fts.rowid
      WHERE hadith_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    `)
    .all(query, limit) as (Hadith & { rank: number })[];

  return rows.map((r) => {
    const { rank, ...hadith } = r;
    return { hadith, score: Math.round(Math.max(0, (1 + rank) * 100)) };
  });
}

let cachedEmbeddings: Float32Array | null = null;

export function getAllEmbeddings(): Float32Array {
  if (cachedEmbeddings) return cachedEmbeddings;

  const DIM = 384;
  const rows = getDb()
    .prepare("SELECT hadith_id, embedding FROM embeddings ORDER BY hadith_id")
    .all() as { hadith_id: number; embedding: Buffer }[];

  const result = new Float32Array(rows.length * DIM);
  for (const row of rows) {
    const floats = new Float32Array(row.embedding.buffer, row.embedding.byteOffset, DIM);
    result.set(floats, row.hadith_id * DIM);
  }

  cachedEmbeddings = result;
  return result;
}

export function getHadithByIds(ids: number[]): Hadith[] {
  if (ids.length === 0) return [];
  const d = getDb();
  const placeholders = ids.map(() => "?").join(",");
  const rows = d
    .prepare(`SELECT * FROM hadith WHERE id IN (${placeholders})`)
    .all(...ids) as Hadith[];
  // Preserve original order
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id)!).filter(Boolean);
}

export function getIsnadChain(hadithId: number): string[] | null {
  const row = getDb()
    .prepare("SELECT narrators FROM isnad WHERE hadith_id = ?")
    .get(hadithId) as { narrators: string } | undefined;
  if (!row) return null;
  return JSON.parse(row.narrators);
}

export function getHadithCount(): number {
  return (getDb().prepare("SELECT COUNT(*) as cnt FROM hadith").get() as { cnt: number }).cnt;
}
