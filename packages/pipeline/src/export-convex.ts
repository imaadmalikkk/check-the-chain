/**
 * Dumps the Convex deployment to packages/pipeline/.cache/convex-export/.
 *
 * Convex holds the enriched corpus — gradings backfilled from the hadith-api
 * CDN, chapter metadata, parsed isnad chains, and the 384-dim embeddings. The
 * iOS artifacts are built from this dump rather than re-derived from
 * data/hadith-json, which is what makes web/iOS search parity structural
 * instead of something we have to keep re-verifying by hand.
 */
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { CACHE_DIR, EXPORT_DIR, EXPORT_ZIP, WEB_APP, tableJsonl } from "./lib/paths.ts";

const REQUIRED_TABLES = ["hadith", "chapters", "collection_counts"];

function run(cmd: string, args: string[], cwd: string) {
  execFileSync(cmd, args, { cwd, stdio: "inherit" });
}

function main() {
  const force = process.argv.includes("--force");
  const alreadyExtracted = REQUIRED_TABLES.every((t) => fs.existsSync(tableJsonl(t)));

  if (alreadyExtracted && !force) {
    console.log("Export already present in .cache — skipping. Use --force to re-download.");
    return;
  }

  fs.mkdirSync(CACHE_DIR, { recursive: true });
  fs.rmSync(EXPORT_DIR, { recursive: true, force: true });
  fs.rmSync(EXPORT_ZIP, { force: true });

  // Run from apps/web so the CLI resolves CONVEX_DEPLOYMENT from its .env.local.
  console.log("Exporting Convex deployment (this pulls ~47k documents with embeddings)...");
  run("npx", ["convex", "export", "--path", EXPORT_ZIP], WEB_APP);

  console.log("Unzipping...");
  fs.mkdirSync(EXPORT_DIR, { recursive: true });
  run("unzip", ["-q", "-o", EXPORT_ZIP, "-d", EXPORT_DIR], CACHE_DIR);

  const missing = REQUIRED_TABLES.filter((t) => !fs.existsSync(tableJsonl(t)));
  if (missing.length > 0) {
    const found = fs
      .readdirSync(EXPORT_DIR, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name);
    throw new Error(
      `Export is missing table(s): ${missing.join(", ")}. Found: ${found.join(", ") || "(none)"}`,
    );
  }

  for (const table of REQUIRED_TABLES) {
    const bytes = fs.statSync(tableJsonl(table)).size;
    console.log(`  ${table.padEnd(18)} ${(bytes / 1e6).toFixed(1)} MB`);
  }
  console.log(`\nExport ready at ${path.relative(process.cwd(), EXPORT_DIR)}`);
}

main();
