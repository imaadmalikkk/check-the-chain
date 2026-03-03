import type { Hadith, SearchResult } from "./types";

const MODEL_ID = "Xenova/all-MiniLM-L6-v2";
const DIM = 384;

type Extractor = (
  text: string | string[],
  opts: { pooling: string; normalize: boolean }
) => Promise<{ data: Float32Array }>;

let extractor: Extractor | null = null;
let storedEmbeddings: Float32Array | null = null;
let initPromise: Promise<void> | null = null;

export type SemanticStatus =
  | "idle"
  | "loading-model"
  | "loading-embeddings"
  | "ready"
  | "error";

let currentStatus: SemanticStatus = "idle";
let currentProgress = 0; // 0-100
let statusListeners: Array<(s: SemanticStatus, progress: number) => void> = [];

function setStatus(s: SemanticStatus, progress = 0) {
  currentStatus = s;
  currentProgress = progress;
  for (const fn of statusListeners) fn(s, progress);
}

export function getSemanticStatus(): SemanticStatus {
  return currentStatus;
}

export function getSemanticProgress(): number {
  return currentProgress;
}

export function onSemanticStatusChange(
  fn: (s: SemanticStatus, progress: number) => void
): () => void {
  statusListeners.push(fn);
  return () => {
    statusListeners = statusListeners.filter((f) => f !== fn);
  };
}

export function isSemanticReady(): boolean {
  return extractor !== null && storedEmbeddings !== null;
}

async function fetchWithProgress(
  url: string,
  onProgress: (pct: number) => void
): Promise<ArrayBuffer> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch failed: ${res.status}`);

  const contentLength = Number(res.headers.get("content-length") || 0);
  if (!contentLength || !res.body) {
    return res.arrayBuffer();
  }

  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let received = 0;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;
    onProgress(Math.round((received / contentLength) * 100));
  }

  const buffer = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) {
    buffer.set(chunk, offset);
    offset += chunk.length;
  }
  return buffer.buffer;
}

export async function initSemanticSearch(): Promise<void> {
  if (initPromise) return initPromise;
  if (typeof window === "undefined") return;

  initPromise = (async () => {
    try {
      setStatus("loading-model", 0);
      const transformers = await import("@huggingface/transformers");
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const create = transformers.pipeline as any;
      extractor = await create("feature-extraction", MODEL_ID, {
        progress_callback: (info: { status: string; progress?: number }) => {
          if (info.status === "progress" && typeof info.progress === "number") {
            setStatus("loading-model", Math.round(info.progress));
          }
        },
      });

      setStatus("loading-embeddings", 0);
      const buffer = await fetchWithProgress(
        "/hadith-embeddings.bin",
        (pct) => setStatus("loading-embeddings", pct)
      );
      storedEmbeddings = new Float32Array(buffer);

      setStatus("ready");
    } catch (e) {
      console.error("Semantic search init failed:", e);
      setStatus("error");
      initPromise = null;
      throw e;
    }
  })();

  return initPromise;
}

export async function semanticSearch(
  query: string,
  hadithData: Hadith[],
  limit = 20
): Promise<SearchResult[]> {
  if (!extractor || !storedEmbeddings) {
    throw new Error("Semantic search not ready");
  }

  const output = await extractor(query, {
    pooling: "mean",
    normalize: true,
  });
  const queryEmb = output.data;

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

  return indices.slice(0, limit).map((idx) => ({
    hadith: hadithData[idx],
    score: Math.round(scores[idx] * 100),
  }));
}
