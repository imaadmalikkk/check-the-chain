import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";

const CDN_BASE =
  "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions";

// Map our collection_slug → API edition key
const COLLECTION_MAP: Record<string, string> = {
  "sunan-abi-dawud": "abudawud",
  "sunan-al-nasai": "nasai",
  "jami-al-tirmidhi": "tirmidhi",
  "sunan-ibn-majah": "ibnmajah",
  "muwatta-malik": "malik",
  "nawawi-40": "nawawi",
  "qudsi-40": "qudsi",
  "shah-waliullah-40": "dehlawi",
  // Skip bukhari & muslim — already graded by scholarly consensus
};

interface ApiHadith {
  hadithnumber: number;
  grades: { name: string; grade: string }[];
}

interface ApiResponse {
  metadata: Record<string, unknown>;
  hadiths: ApiHadith[];
}

// Normalize raw grade string to our valid Grading values
function normalizeGrade(raw: string): string | null {
  const g = raw.toLowerCase();
  if (g.includes("maudu") || g.includes("mawdu")) return "Mawdu'";
  if (g.includes("sahih")) return "Sahih"; // covers "Hasan Sahih", "Sahih Lighairihi"
  if (g.includes("hasan")) return "Hasan"; // "Hasan", "Isnaad Hasan"
  if (g.includes("daif") || g.includes("da'if") || g.includes("munkar") || g.includes("shadh"))
    return "Da'if";
  return null; // unrecognized — skip
}

// Pick best grade: Al-Albani first, then Zubair Ali Zai
function pickGrade(grades: { name: string; grade: string }[]): string | null {
  const albani = grades.find((g) => g.name === "Al-Albani");
  if (albani) {
    const normalized = normalizeGrade(albani.grade);
    if (normalized) return normalized;
  }
  const zubair = grades.find((g) => g.name === "Zubair Ali Zai");
  if (zubair) {
    const normalized = normalizeGrade(zubair.grade);
    if (normalized) return normalized;
  }
  // Try any grader as last resort
  for (const g of grades) {
    const normalized = normalizeGrade(g.grade);
    if (normalized) return normalized;
  }
  return null;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withRetry<T>(fn: () => Promise<T>, retries = 3, baseDelay = 2000): Promise<T> {
  for (let i = 0; i <= retries; i++) {
    try {
      return await fn();
    } catch (err) {
      if (i === retries) throw err;
      const delay = baseDelay * Math.pow(2, i);
      console.warn(`  Retry ${i + 1}/${retries} after ${delay}ms...`);
      await sleep(delay);
    }
  }
  throw new Error("unreachable");
}

async function main() {
  const url = process.env.CONVEX_URL ?? process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) {
    console.error("CONVEX_URL or NEXT_PUBLIC_CONVEX_URL environment variable is required");
    process.exit(1);
  }

  const client = new ConvexHttpClient(url);
  const BATCH_SIZE = 50;

  let totalUpdated = 0;
  let totalSkipped = 0;
  let totalUnmatched = 0;

  for (const [slug, apiKey] of Object.entries(COLLECTION_MAP)) {
    console.log(`\nProcessing: ${slug} (${apiKey})`);

    // Fetch grading data from CDN
    const cdnUrl = `${CDN_BASE}/eng-${apiKey}.min.json`;
    const res = await fetch(cdnUrl);
    if (!res.ok) {
      console.error(`  Failed to fetch ${cdnUrl}: ${res.status}`);
      continue;
    }
    const data: ApiResponse = await res.json();
    const apiHadith = data.hadiths;
    console.log(`  Fetched ${apiHadith.length} hadith from CDN`);

    // Build grade map: hadith_number → normalized grade
    const gradeMap = new Map<string, string>();
    for (const h of apiHadith) {
      const grade = pickGrade(h.grades);
      if (grade) {
        gradeMap.set(String(h.hadithnumber), grade);
      }
    }
    console.log(`  ${gradeMap.size} hadith with usable grades`);

    // Fetch existing hadith IDs from Convex (paginated to avoid byte limit)
    const PAGE_SIZE = 500;
    const existing: { _id: Id<"hadith">; hadith_number: string; order: number }[] = [];
    let offset = 0;
    while (true) {
      const page = await withRetry(() =>
        client.query(api.hadith.listBySlug, { slug, offset, limit: PAGE_SIZE })
      );
      existing.push(...page);
      if (page.length < PAGE_SIZE) break;
      offset += PAGE_SIZE;
    }
    console.log(`  ${existing.length} hadith in database`);

    // Build patches
    type Patch = { id: Id<"hadith">; grading: string; graded_by: string };
    const patches: Patch[] = [];
    let skipped = 0;
    let unmatched = 0;

    for (const doc of existing) {
      const grade = gradeMap.get(doc.hadith_number);
      if (grade) {
        patches.push({
          id: doc._id,
          grading: grade,
          graded_by: "Darussalam",
        });
      } else {
        unmatched++;
      }
    }

    // Send patches in batches
    for (let i = 0; i < patches.length; i += BATCH_SIZE) {
      const batch = patches.slice(i, i + BATCH_SIZE);
      await withRetry(() =>
        client.mutation(api.hadith.patchGradings, { patches: batch })
      );
      await sleep(50);
      if ((i + BATCH_SIZE) % 500 === 0 || i + BATCH_SIZE >= patches.length) {
        process.stdout.write(`\r  Patched ${Math.min(i + BATCH_SIZE, patches.length)}/${patches.length}`);
      }
    }

    console.log(`\n  Updated: ${patches.length}, Skipped: ${skipped}, Unmatched: ${unmatched}`);
    totalUpdated += patches.length;
    totalSkipped += skipped;
    totalUnmatched += unmatched;
  }

  console.log(`\n--- Done ---`);
  console.log(`Total updated: ${totalUpdated}`);
  console.log(`Total skipped (already graded): ${totalSkipped}`);
  console.log(`Total unmatched (no grade found): ${totalUnmatched}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
