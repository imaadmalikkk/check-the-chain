import { pipeline, type FeatureExtractionPipeline } from "@huggingface/transformers";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";

const BATCH_SIZE = 25;
const PAGE_SIZE = 100;

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

  console.log("Loading embedding model (Xenova/all-MiniLM-L6-v2)...");
  const pipe = await pipeline(
    "feature-extraction",
    "Xenova/all-MiniLM-L6-v2",
  );
  console.log("Model loaded.\n");

  const client = new ConvexHttpClient(url);

  // Get all collections to iterate through
  const collections = await client.query(api.hadith.getCollectionCounts);
  console.log(`Found ${collections.length} collections\n`);

  let totalPatched = 0;
  let totalSkipped = 0;

  for (const col of collections) {
    const totalPages = Math.ceil(col.count / PAGE_SIZE);
    console.log(`\n${col.slug}: ${col.count} hadith (${totalPages} pages)`);

    for (let page = 0; page < totalPages; page++) {
      const { hadith } = await client.query(
        api.hadith.getByCollectionPaginated,
        { slug: col.slug, page, pageSize: PAGE_SIZE }
      );

      // Filter to only hadith without embeddings
      const needsEmbedding = hadith.filter((h) => !h.embedding);
      if (needsEmbedding.length === 0) {
        totalSkipped += hadith.length;
        continue;
      }

      // Generate embeddings in batches
      for (let i = 0; i < needsEmbedding.length; i += BATCH_SIZE) {
        const batch = needsEmbedding.slice(i, i + BATCH_SIZE);
        const texts = batch.map((h) => h.english);

        // Generate embeddings
        const output = await pipe(texts, { pooling: "mean", normalize: true });

        // Extract individual embeddings from the batched output
        const dim = 384;
        const patches = batch.map((h, j) => {
          const start = j * dim;
          const embeddingData = Array.from(
            (output.data as Float32Array).slice(start, start + dim)
          );
          return { id: h._id, embedding: embeddingData };
        });

        // Patch in Convex
        await withRetry(() =>
          client.mutation(api.hadith.patchEmbeddings, { patches })
        );
        totalPatched += batch.length;
        await sleep(50);
      }

      process.stdout.write(
        `\r  ${col.slug}: page ${page + 1}/${totalPages} (${totalPatched} patched, ${totalSkipped} skipped)`
      );
    }
  }

  console.log(`\n\nDone! Patched ${totalPatched} embeddings, skipped ${totalSkipped} already-embedded.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
