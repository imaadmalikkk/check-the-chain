/**
 * Copies the built artifacts into the iOS app's Resources folder.
 *
 * They live outside the app target's tree until this point so a partial or
 * failed pipeline run can never leave the app bundling a half-written database
 * next to a stale embeddings file.
 */
import fs from "node:fs";
import path from "node:path";
import { IOS_RESOURCES, OUT_DIR } from "./lib/paths.ts";

const ARTIFACTS = [
  "hadith.sqlite",
  "embeddings.bin",
  "embeddings.json",
  "vocab.txt",
  "MiniLM.mlpackage",
];

function main() {
  fs.mkdirSync(IOS_RESOURCES, { recursive: true });

  const missing = ARTIFACTS.filter((a) => !fs.existsSync(path.join(OUT_DIR, a)));
  if (missing.length > 0) {
    throw new Error(
      `Missing artifact(s): ${missing.join(", ")}. Run \`npm run pipeline\` first.`,
    );
  }

  // The database and the embeddings are indexed by the same row ids, so they
  // are only meaningful as a set — never copy one without the other.
  const dbRevision = readRevision();
  const embRevision = JSON.parse(
    fs.readFileSync(path.join(OUT_DIR, "embeddings.json"), "utf8"),
  ).revision as string;
  if (dbRevision !== embRevision) {
    throw new Error(
      `hadith.sqlite (${dbRevision}) and embeddings.json (${embRevision}) are from ` +
        `different runs. Rebuild both: \`npm run sqlite && npm run embeddings\`.`,
    );
  }

  for (const artifact of ARTIFACTS) {
    const from = path.join(OUT_DIR, artifact);
    const to = path.join(IOS_RESOURCES, artifact);
    fs.rmSync(to, { recursive: true, force: true });
    fs.cpSync(from, to, { recursive: true });
    console.log(`  ${artifact.padEnd(20)} ${(sizeOf(to) / 1e6).toFixed(1)} MB`);
  }

  const total = ARTIFACTS.reduce((n, a) => n + sizeOf(path.join(IOS_RESOURCES, a)), 0);
  console.log(`\nStaged ${(total / 1e6).toFixed(1)} MB into apps/ios/CheckTheChain/Resources`);
  console.log(`Revision ${dbRevision}`);
}

function readRevision(): string {
  return JSON.parse(fs.readFileSync(path.join(OUT_DIR, "manifest.json"), "utf8")).revision;
}

function sizeOf(target: string): number {
  const stat = fs.statSync(target);
  if (!stat.isDirectory()) return stat.size;
  return fs
    .readdirSync(target)
    .reduce((n, entry) => n + sizeOf(path.join(target, entry)), 0);
}

main();
