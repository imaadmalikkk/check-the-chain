/**
 * Recomputes `isnad_narrators` for every hadith already in Convex.
 *
 * This exists so a parser fix does not cost a re-seed. `seed-convex.ts` clears
 * the table before inserting, which would throw away the 384-dim embeddings and
 * the backfilled gradings along with it — hours of work to change one derived
 * field. This reads the Arabic that is already there, re-derives the chain with
 * the same `parseIsnad` the seed uses, and patches only the documents whose
 * chain actually changed.
 *
 *   npx tsx scripts/reparse-isnad.ts --dry-run    # report, write nothing
 *   npx tsx scripts/reparse-isnad.ts
 */
import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import { parseIsnad } from "./lib/isnad.ts";

// Pages carry the full Arabic text, which is the largest field on the document
// — 200 at a time keeps a page comfortably inside Convex's read limit.
const PAGE_SIZE = 200;
const PATCH_SIZE = 100;

const dryRun = process.argv.includes("--dry-run");

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withRetry<T>(fn: () => Promise<T>, retries = 3): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === retries) throw err;
      await sleep(2000 * 2 ** attempt);
    }
  }
}

function same(a: string[] | null, b: string[] | null): boolean {
  if (a === null || b === null) return a === b;
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

async function main() {
  const url = process.env.CONVEX_URL ?? process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) {
    console.error("Set CONVEX_URL (or NEXT_PUBLIC_CONVEX_URL).");
    process.exit(1);
  }
  const client = new ConvexHttpClient(url);

  const collections = await withRetry(() =>
    client.query(api.hadith.getCollectionCounts, {})
  );

  let scanned = 0;
  let changed = 0;
  let added = 0;
  let removed = 0;
  let linksBefore = 0;
  let linksAfter = 0;
  const examples: string[] = [];

  for (const { slug, count } of collections) {
    let pending: { id: Id<"hadith">; isnad_narrators: string[] | null }[] = [];

    async function flush() {
      if (pending.length === 0) return;
      const patches = pending;
      pending = [];
      if (!dryRun) {
        await withRetry(() => client.mutation(api.hadith.patchIsnad, { patches }));
        await sleep(40);
      }
    }

    for (let offset = 0; offset < count; offset += PAGE_SIZE) {
      const docs = await withRetry(() =>
        client.query(api.hadith.listArabicBySlug, {
          slug,
          offset,
          limit: PAGE_SIZE,
        })
      );

      for (const doc of docs) {
        scanned++;
        const before = doc.isnad_narrators;
        const after = parseIsnad(doc.arabic);
        linksBefore += before?.length ?? 0;
        linksAfter += after?.length ?? 0;

        if (same(before, after)) continue;
        changed++;
        if (!before && after) added++;
        if (before && !after) removed++;
        if (examples.length < 5 && before && after) {
          examples.push(
            `  ${slug} ${doc.hadith_number}\n    before: ${before.join(" | ")}\n    after:  ${after.join(" | ")}`
          );
        }

        pending.push({ id: doc._id, isnad_narrators: after });
        if (pending.length >= PATCH_SIZE) await flush();
      }

      process.stdout.write(`\r${slug}: ${Math.min(offset + PAGE_SIZE, count)}/${count}   `);
    }

    await flush();
    process.stdout.write(`\r${slug}: ${count}/${count} done          \n`);
  }

  console.log(`\n${dryRun ? "DRY RUN — nothing written" : "Patched"}`);
  console.log(`  scanned        ${scanned.toLocaleString()}`);
  console.log(`  changed        ${changed.toLocaleString()}`);
  console.log(`    gained a chain  ${added.toLocaleString()}`);
  console.log(`    lost a chain    ${removed.toLocaleString()}`);
  console.log(`  chain links    ${linksBefore.toLocaleString()} → ${linksAfter.toLocaleString()}`);
  if (examples.length) console.log(`\nExamples:\n${examples.join("\n")}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
