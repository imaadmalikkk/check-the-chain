import path from "path";

const MODEL_ID = "Xenova/all-MiniLM-L6-v2";

async function main() {
  const cacheDir = path.join(process.cwd(), "data", "models");
  console.log(`Downloading model ${MODEL_ID} to ${cacheDir}...`);

  const { pipeline } = await import("@huggingface/transformers");

  const extractor = await pipeline("feature-extraction", MODEL_ID, {
    cache_dir: cacheDir,
    dtype: "q8",
    progress_callback: (info: { status: string; progress?: number; file?: string }) => {
      if (info.status === "progress" && typeof info.progress === "number") {
        process.stdout.write(`\r  ${info.file ?? ""} ${Math.round(info.progress)}%`);
      } else if (info.status === "done") {
        process.stdout.write("\n");
      }
    },
  });

  // Dispose the pipeline — we just needed to download the files
  await extractor.dispose();

  console.log("Model downloaded successfully!");
}

main().catch((err) => {
  console.error("Failed to download model:", err);
  process.exit(1);
});
