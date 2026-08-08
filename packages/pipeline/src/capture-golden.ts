/**
 * Captures the web app's search results as the parity baseline for the offline
 * iOS engine.
 *
 * This runs the exact production path — same MiniLM model, same Convex
 * `hybridSearch` action, same RRF — so the output is what the shipping web app
 * would show. HadithKitTests replays these queries against the offline engine
 * and asserts it reproduces them. If that test ever goes red, the offline stack
 * has diverged from the thing it replaces.
 */
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "@huggingface/transformers";
import { ConvexHttpClient } from "convex/browser";
import { GOLDEN_FILE, WEB_APP } from "./lib/paths.ts";

/**
 * Chosen to exercise every leg of the hybrid: verbatim quotes (FTS should
 * dominate), loose paraphrases and topical asks (vector should dominate),
 * transliterated Arabic, and short queries near the 3-character floor.
 */
const QUERIES = [
  // Verbatim or near-verbatim — keyword search should carry these
  "Actions are but by intention",
  "None of you truly believes until he loves for his brother what he loves for himself",
  "The best of you are those who learn the Quran and teach it",
  "Whoever believes in Allah and the Last Day should speak good or remain silent",
  "Cleanliness is half of faith",
  "Paradise lies at the feet of the mother",
  "The strong man is not the one who wrestles",
  "Islam is built upon five pillars",
  "Whoever innovates something in this matter of ours",
  "A Muslim is the one from whose tongue and hand other Muslims are safe",

  // Paraphrase and description — semantic search should carry these
  "hadith about being kind to your neighbours",
  "narration about smiling being charity",
  "what did the prophet say about seeking knowledge",
  "the reward for fasting on the day of Arafah",
  "warning against backbiting and gossip",
  "how should a person treat orphans",
  "hadith on forgiving others who wronged you",
  "the virtue of praying in congregation at the mosque",
  "prophet's advice about anger and how to control it",
  "narration describing the signs of the hypocrite",
  "what happens to a person in the grave",
  "hadith about honesty in trade and business",
  "the importance of keeping family ties",
  "prophet's teaching on moderation in worship",
  "rulings about wudu and ablution being broken",

  // Transliterated Arabic and proper nouns
  "Abu Hurayrah narrated about the night prayer",
  "hadith qudsi where Allah says I am as my servant thinks of me",
  "Aisha described the prophet's character",

  // Short / edge-of-threshold
  "zakat",
  "sabr patience",
];

const TOP_N = 10;

interface ConvexResult {
  hadith: { collection_slug: string; hadith_number: string; collection: string };
  score: number;
}

function convexUrl(): string {
  const fromEnv = process.env.NEXT_PUBLIC_CONVEX_URL;
  if (fromEnv) return fromEnv;

  const envFile = path.join(WEB_APP, ".env.local");
  const match = fs
    .readFileSync(envFile, "utf8")
    .match(/^NEXT_PUBLIC_CONVEX_URL=(.+)$/m);
  if (!match) {
    throw new Error(`NEXT_PUBLIC_CONVEX_URL not set and not found in ${envFile}`);
  }
  return match[1].trim().replace(/^["']|["']$/g, "");
}

async function main() {
  const client = new ConvexHttpClient(convexUrl());

  console.log("Loading Xenova/all-MiniLM-L6-v2 (same model the web worker uses)...");
  const embed = await pipeline("feature-extraction", "Xenova/all-MiniLM-L6-v2");

  const cases: Array<{
    query: string;
    embedding: number[];
    expected: Array<{ ref: string; score: number }>;
  }> = [];

  for (const query of QUERIES) {
    const output = await embed(query, { pooling: "mean", normalize: true });
    const embedding = Array.from(output.data as Float32Array).slice(0, 384);

    const results = (await client.action("hadith:hybridSearch" as never, {
      embedding,
      query,
      limit: TOP_N,
    } as never)) as unknown as ConvexResult[];

    cases.push({
      query,
      // Stored so the Swift test can isolate a ranking regression from an
      // embedding regression: feed this vector in directly and the only thing
      // left under test is the index and the fusion.
      embedding,
      expected: results.map((r) => ({
        ref: `${r.hadith.collection_slug}/${r.hadith.hadith_number}`,
        score: r.score,
      })),
    });

    const top = cases.at(-1)!.expected[0];
    console.log(`  ${query.slice(0, 52).padEnd(54)} → ${top ? top.ref : "(no results)"}`);
  }

  fs.mkdirSync(path.dirname(GOLDEN_FILE), { recursive: true });
  fs.writeFileSync(
    GOLDEN_FILE,
    JSON.stringify(
      {
        capturedFrom: "convex hadith:hybridSearch via Xenova/all-MiniLM-L6-v2",
        topN: TOP_N,
        cases,
      },
      null,
      1,
    ),
  );

  const mb = fs.statSync(GOLDEN_FILE).size / 1e6;
  console.log(`\n${cases.length} cases → ${path.relative(process.cwd(), GOLDEN_FILE)} (${mb.toFixed(1)} MB)`);
}

main();
