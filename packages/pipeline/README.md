# @check-the-chain/pipeline

Builds the iOS app's offline artifacts from the Convex corpus.

```bash
npm run pipeline          # from the repo root — runs everything below in order
```

| Step | Script | Output |
|---|---|---|
| `export` | `src/export-convex.ts` | `.cache/convex-export/` (~470MB JSONL) |
| `sqlite` | `src/build-sqlite.ts` | `out/hadith.sqlite` (108MB), `out/manifest.json` |
| `embeddings` | `src/build-embeddings.ts` | `out/embeddings.bin` (18MB), `out/embeddings.json` |
| `coreml` | `coreml/run-convert.sh` | `out/MiniLM.mlpackage` (45MB), `out/vocab.txt` |
| `stage` | `src/stage-ios.ts` | copies into `apps/ios/CheckTheChain/Resources/` |

Also, run separately when the corpus changes:

```bash
npm run capture-golden -w @check-the-chain/pipeline
```

which replays 30 queries against the live web app and writes the parity baseline the iOS tests assert against.

## Why it builds from Convex, not from `data/hadith-json`

Convex holds the *enriched* corpus: gradings backfilled from the hadith-api CDN, chapter metadata, parsed isnad chains, and the 384-dim embeddings. Rebuilding any of that here would create a second implementation that could drift. Dumping Convex makes web/iOS parity structural rather than something to keep re-verifying.

If the deployment is unavailable, everything can be re-derived: `apps/web/scripts/seed-convex.ts` parses `data/hadith-json`, `enrich-gradings.ts` re-fetches gradings, and `build-embeddings-convex.ts` regenerates embeddings. It just takes 30–40 minutes instead of two.

## The two artifacts are one unit

Row ids in `hadith.sqlite` are dense and double as row indexes into `embeddings.bin`. **Build them in the same run.** A mismatch doesn't crash — it returns the wrong hadith for every semantic hit, silently. Both files carry a `revision` digest, `stage` refuses to copy a mismatched pair, and `SearchEngine` refuses to construct one.

## Python setup for the Core ML step

`coreml/run-convert.sh` creates its own Python 3.12 venv via `uv` on first run. This is not optional: **coremltools does not support Python 3.14**, which is the system Python on this machine, and it pins older torch/numpy than a general environment wants.

```bash
brew install uv    # if not already present
```

The conversion bakes mean-pooling and L2 normalization into the traced graph, so the model's single output is a ready-to-use 384-dim unit vector and the Swift side does no tensor math. It then validates itself: every golden query is re-embedded through the converted model and compared against the vector Transformers.js produced, requiring cosine ≥ 0.999. It currently measures 0.999999.
