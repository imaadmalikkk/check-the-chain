import { pipeline } from "@huggingface/transformers";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let pipe: any = null;

async function getPipeline() {
  if (!pipe) {
    pipe = await (pipeline as Function)("feature-extraction", "Xenova/all-MiniLM-L6-v2", {
      dtype: "q8",
      progress_callback: (data: Record<string, unknown>) => {
        self.postMessage({ type: "progress", data });
      },
    });
  }
  return pipe;
}

self.onmessage = async (e: MessageEvent) => {
  const { type, id, text } = e.data;

  if (type === "init") {
    try {
      await getPipeline();
      self.postMessage({ type: "ready" });
    } catch (err) {
      self.postMessage({ type: "error", id: "", error: String(err) });
    }
    return;
  }

  if (type === "embed") {
    try {
      const p = await getPipeline();
      const output = await p(text, { pooling: "mean", normalize: true });
      const embedding = Array.from(output.data as Float32Array);
      // Free WASM tensor memory to prevent OOM on repeated searches
      if (typeof output.dispose === "function") output.dispose();
      self.postMessage({ type: "result", id, embedding });
    } catch (err) {
      self.postMessage({ type: "error", id, error: String(err) });
    }
  }
};
