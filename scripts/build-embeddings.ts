import fs from "fs";
import path from "path";

type CompactHadith = [string, string, string, string, string, string];

const MODEL_ID = "Xenova/all-MiniLM-L6-v2";
const DIM = 384;
const BATCH_SIZE = 32;

async function main() {
  const { pipeline } = await import("@huggingface/transformers");

  const dataPath = path.join(process.cwd(), "public", "hadith-data.json");
  const data: CompactHadith[] = JSON.parse(fs.readFileSync(dataPath, "utf-8"));

  console.log(`Loading model: ${MODEL_ID}`);
  const extractor = await pipeline("feature-extraction", MODEL_ID);

  console.log(`Computing embeddings for ${data.length} hadith...`);
  const embeddings = new Float32Array(data.length * DIM);

  for (let i = 0; i < data.length; i += BATCH_SIZE) {
    const end = Math.min(i + BATCH_SIZE, data.length);
    const batch = data.slice(i, end);

    const texts = batch.map((h) => {
      const narrator = h[2];
      const english = h[3];
      return narrator ? `${narrator} ${english}` : english;
    });

    const output = await extractor(texts, {
      pooling: "mean",
      normalize: true,
    });

    const outputData = output.data as Float32Array;
    for (let j = 0; j < batch.length; j++) {
      embeddings.set(
        outputData.slice(j * DIM, (j + 1) * DIM),
        (i + j) * DIM
      );
    }

    if (i % (BATCH_SIZE * 100) === 0 || end >= data.length) {
      console.log(
        `  ${end}/${data.length} (${Math.round((end / data.length) * 100)}%)`
      );
    }
  }

  const outPath = path.join(process.cwd(), "public", "hadith-embeddings.bin");
  fs.writeFileSync(outPath, Buffer.from(embeddings.buffer));

  const size = fs.statSync(outPath).size;
  console.log(`\nhadith-embeddings.bin: ${(size / 1024 / 1024).toFixed(2)} MB`);
  console.log("Done!");
}

main().catch(console.error);
