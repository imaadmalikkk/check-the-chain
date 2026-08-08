/**
 * Builds out/embeddings.bin — the flat matrix the iOS app scans instead of
 * calling Convex's vector index.
 *
 * The stored vectors are already L2-normalized (apps/web/scripts/build-embeddings-convex.ts
 * generates them with `{ pooling: "mean", normalize: true }`), and the query
 * vector will be too. That means ranking by the raw integer dot product of the
 * quantized vectors is monotonic in true cosine similarity: the scale factor is
 * a positive constant common to every row, so it cancels out of the comparison
 * entirely and never has to be applied at query time.
 */
import fs from "node:fs";
import path from "node:path";
import { streamTable, type ConvexHadith } from "./lib/corpus.ts";
import { OUT_DIR } from "./lib/paths.ts";

const DIM = 384;
/**
 * Pseudo-queries drawn from the corpus itself for the fidelity report. Each one
 * costs a full 47k × 384 scan in both precisions, so this is deliberately modest
 * — it only needs to catch a systematic quantization problem, not measure one
 * precisely.
 */
const FIDELITY_SAMPLES = 50;
const FIDELITY_TOP_K = 20;
/** Below this, int8 is losing real ranking information — switch to Float16. */
const FIDELITY_THRESHOLD = 0.95;

interface Manifest {
  revision: string;
  count: number;
  order: string[];
}

function loadManifest(): Manifest {
  const file = path.join(OUT_DIR, "manifest.json");
  if (!fs.existsSync(file)) {
    throw new Error("Missing out/manifest.json. Run `npm run sqlite` first.");
  }
  return JSON.parse(fs.readFileSync(file, "utf8")) as Manifest;
}

async function collectFloats(manifest: Manifest) {
  const indexByKey = new Map<string, number>();
  manifest.order.forEach((key, id) => indexByKey.set(key, id));

  const floats = new Float32Array(manifest.count * DIM);
  const filled = new Uint8Array(manifest.count);
  let maxAbs = 0;
  let seen = 0;

  for await (const doc of streamTable<ConvexHadith>("hadith")) {
    const key = `${doc.collection_slug}/${doc.hadith_number}`;
    const id = indexByKey.get(key);
    if (id === undefined) {
      throw new Error(`Hadith ${key} is in the export but not in the manifest — rebuild the DB.`);
    }
    const vec = doc.embedding;
    if (!vec) continue;
    if (vec.length !== DIM) {
      throw new Error(`Hadith ${key} has a ${vec.length}-dim embedding, expected ${DIM}.`);
    }

    const base = id * DIM;
    for (let i = 0; i < DIM; i++) {
      const v = vec[i];
      floats[base + i] = v;
      const a = Math.abs(v);
      if (a > maxAbs) maxAbs = a;
    }
    filled[id] = 1;
    seen++;
  }

  const missing: number[] = [];
  for (let id = 0; id < manifest.count; id++) if (!filled[id]) missing.push(id);

  return { floats, maxAbs, seen, missing };
}

function quantize(floats: Float32Array, count: number, scale: number): Int8Array {
  const out = new Int8Array(count * DIM);
  for (let i = 0; i < out.length; i++) {
    const q = Math.round(floats[i] * scale);
    out[i] = q > 127 ? 127 : q < -127 ? -127 : q;
  }
  return out;
}

function topK(
  scoreAt: (row: number) => number,
  count: number,
  k: number,
): number[] {
  const idx = new Array<number>(count);
  for (let i = 0; i < count; i++) idx[i] = i;
  idx.sort((a, b) => scoreAt(b) - scoreAt(a));
  return idx.slice(0, k);
}

function fidelityReport(floats: Float32Array, ints: Int8Array, count: number) {
  // Deterministic sample so the report is comparable between runs.
  const stride = Math.max(1, Math.floor(count / FIDELITY_SAMPLES));
  let overlapTotal = 0;
  let samples = 0;

  for (let q = 0; q < count && samples < FIDELITY_SAMPLES; q += stride) {
    const qBase = q * DIM;

    const floatScores = new Float32Array(count);
    const intScores = new Int32Array(count);
    for (let row = 0; row < count; row++) {
      const rBase = row * DIM;
      let fs = 0;
      let is = 0;
      for (let i = 0; i < DIM; i++) {
        fs += floats[qBase + i] * floats[rBase + i];
        is += ints[qBase + i] * ints[rBase + i];
      }
      floatScores[row] = fs;
      intScores[row] = is;
    }

    const a = new Set(topK((r) => floatScores[r], count, FIDELITY_TOP_K));
    const b = topK((r) => intScores[r], count, FIDELITY_TOP_K);
    overlapTotal += b.filter((r) => a.has(r)).length / FIDELITY_TOP_K;
    samples++;
  }

  return { overlap: overlapTotal / samples, samples };
}

async function main() {
  const manifest = loadManifest();
  console.log(`Manifest: ${manifest.count} hadith, revision ${manifest.revision}`);

  console.log("Reading embeddings...");
  const { floats, maxAbs, seen, missing } = await collectFloats(manifest);
  console.log(`  ${seen} embeddings, max |component| = ${maxAbs.toFixed(4)}`);

  if (missing.length > 0) {
    throw new Error(
      `${missing.length} hadith have no embedding (first: row ${missing[0]}, ` +
        `${manifest.order[missing[0]]}). Semantic search would silently skip them. ` +
        `Run apps/web/scripts/build-embeddings-convex.ts to backfill.`,
    );
  }

  const scale = 127 / maxAbs;
  console.log(`Quantizing to int8 (scale ${scale.toFixed(3)})...`);
  const ints = quantize(floats, manifest.count, scale);

  console.log(`Checking fidelity over ${FIDELITY_SAMPLES} sampled queries...`);
  const { overlap, samples } = fidelityReport(floats, ints, manifest.count);
  const pct = (overlap * 100).toFixed(2);
  console.log(`  top-${FIDELITY_TOP_K} overlap vs float32: ${pct}% (${samples} samples)`);

  if (overlap < FIDELITY_THRESHOLD) {
    throw new Error(
      `int8 quantization is losing ranking information (${pct}% < ` +
        `${FIDELITY_THRESHOLD * 100}%). Switch the artifact to Float16 and update ` +
        `VectorIndex.swift to read halves.`,
    );
  }

  const binPath = path.join(OUT_DIR, "embeddings.bin");
  fs.writeFileSync(binPath, Buffer.from(ints.buffer, ints.byteOffset, ints.byteLength));
  fs.writeFileSync(
    path.join(OUT_DIR, "embeddings.json"),
    JSON.stringify(
      {
        revision: manifest.revision,
        count: manifest.count,
        dim: DIM,
        dtype: "int8",
        scale,
        fidelity: { topK: FIDELITY_TOP_K, overlap, samples },
      },
      null,
      2,
    ),
  );

  console.log(`\nembeddings.bin  ${(fs.statSync(binPath).size / 1e6).toFixed(1)} MB`);
}

main();
