import "server-only";
import path from "path";
import { getAllEmbeddings, getHadithByIds } from "./db";
import type { Hadith } from "./types";

const MODEL_ID = "Xenova/all-MiniLM-L6-v2";
const MODEL_CACHE_DIR = path.join(process.cwd(), "data", "models");
const DIM = 384;

type Extractor = (
  text: string | string[],
  opts: { pooling: string; normalize: boolean }
) => Promise<{ data: Float32Array }>;

let extractor: Extractor | null = null;
let loadingPromise: Promise<void> | null = null;

async function ensureModel(): Promise<void> {
  if (extractor) return;
  if (loadingPromise) return loadingPromise;

  loadingPromise = (async () => {
    const transformers = await import("@huggingface/transformers");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const create = transformers.pipeline as any;
    extractor = await create("feature-extraction", MODEL_ID, {
      cache_dir: MODEL_CACHE_DIR,
      dtype: "q8",
      local_files_only: true,
    });
  })();

  return loadingPromise;
}

export async function semanticSearch(
  query: string,
  limit = 20,
): Promise<{ hadith: Hadith; score: number }[]> {
  await ensureModel();
  if (!extractor) throw new Error("Model not loaded");

  const output = await extractor(query, { pooling: "mean", normalize: true });
  const queryEmb = output.data;

  const storedEmbeddings = getAllEmbeddings();
  const numHadith = storedEmbeddings.length / DIM;
  const scores = new Float32Array(numHadith);

  for (let i = 0; i < numHadith; i++) {
    let dot = 0;
    const offset = i * DIM;
    for (let d = 0; d < DIM; d++) {
      dot += queryEmb[d] * storedEmbeddings[offset + d];
    }
    scores[i] = dot;
  }

  const indices = Array.from({ length: numHadith }, (_, i) => i);
  indices.sort((a, b) => scores[b] - scores[a]);

  const topIds = indices.slice(0, limit);
  const hadithList = getHadithByIds(topIds);

  return hadithList.map((h, i) => ({
    hadith: h,
    score: Math.round(scores[topIds[i]] * 100),
  }));
}
