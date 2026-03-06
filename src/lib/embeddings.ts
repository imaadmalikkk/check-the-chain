import { pipeline } from "@huggingface/transformers";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let embeddingPipeline: any = null;

async function getPipeline() {
  if (!embeddingPipeline) {
    embeddingPipeline = await (pipeline as Function)(
      "feature-extraction",
      "Xenova/all-MiniLM-L6-v2",
    );
  }
  return embeddingPipeline;
}

export async function embed(text: string): Promise<number[]> {
  const pipe = await getPipeline();
  const output = await pipe(text, { pooling: "mean", normalize: true });
  return Array.from(output.data as Float32Array);
}
