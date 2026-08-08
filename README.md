# Check the Chain

Verify hadith authenticity against 47,000+ narrations from Bukhari, Muslim, and 14 other major collections.

---

## What it does

Type a hadith — or even a rough description of one — and Check the Chain finds matching narrations across 16 classical collections. Results include the source, book, chapter, hadith number, and grading where available.

Search is powered by a local AI model that runs in your browser using [Transformers.js](https://huggingface.co/docs/transformers.js) for semantic matching, alongside keyword search for fast exact lookups.

## Features

- **Semantic search** — find hadith by meaning, not just keywords
- **Book & chapter browsing** — 605 chapters across 16 collections
- **Scholarly gradings** — Sahih, Hasan, Da'if with scholar attribution
- **Chain of narrators** — visual isnad visualization
- **Share cards** — generate images in English, Arabic, or both
- **Hadith of the Day** — daily curated hadith from Sahih al-Bukhari

## Collections

**The Nine Books** — Sahih al-Bukhari, Sahih Muslim, Sunan al-Nasa'i, Sunan Abi Dawud, Sunan Ibn Majah, Jami' al-Tirmidhi, Muwatta Malik, Musnad Ahmad ibn Hanbal

**Other Collections** — Mishkat al-Masabih, Riyad as-Salihin, Bulugh al-Maram, Al-Adab Al-Mufrad, Shama'il Muhammadiyah

**Forties** — Imam Nawawi's 40, 40 Hadith Qudsi, Shah Waliullah's 40

## Repository layout

```
apps/web            Next.js app — Convex backend, in-browser semantic search
apps/ios            Native SwiftUI app, iOS 26+ — fully offline, no backend
packages/pipeline   Builds the iOS offline artifacts from the Convex corpus
data/hadith-json    Source corpus (not committed — see below)
```

## Running locally

```bash
npm install
npm run dev        # web
```

Requires a [Convex](https://convex.dev) deployment. Set `NEXT_PUBLIC_CONVEX_URL` in `apps/web/.env.local`.

For iOS:

```bash
npm run pipeline                    # build the offline SQLite + embeddings + Core ML model
cd apps/ios && xcodegen generate && open CheckTheChain.xcodeproj
```

## Stack

**Web** — [Next.js](https://nextjs.org) App Router, [Convex](https://convex.dev), [Transformers.js](https://huggingface.co/docs/transformers.js), [Tailwind CSS](https://tailwindcss.com)

**iOS** — SwiftUI (iOS 26, Liquid Glass), [GRDB](https://github.com/groue/GRDB.swift) over SQLite FTS5, Core ML MiniLM running on the Neural Engine. The entire 47,000-hadith corpus, its embeddings, and the model ship inside the app — search runs on-device, offline, at no cost.

## Disclaimer

This tool searches major hadith collections. It is not a substitute for scholarly verification.

## License

MIT — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.
