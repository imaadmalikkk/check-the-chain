# Check the Chain

Verify hadith authenticity against 47,000+ narrations from Bukhari, Muslim, and 15 other major collections.

---

## What it does

Type a hadith — or even a rough description of one — and Check the Chain finds matching narrations across 17 classical collections. Results include the source, book, chapter, hadith number, and grading where available.

Search is powered by a local AI model that runs in your browser using [Transformers.js](https://huggingface.co/docs/transformers.js) for semantic matching, alongside keyword search for fast exact lookups.

## Collections

**The Nine Books** — Sahih al-Bukhari, Sahih Muslim, Sunan al-Nasa'i, Sunan Abi Dawud, Sunan Ibn Majah, Jami' al-Tirmidhi, Muwatta Malik, Musnad Ahmad ibn Hanbal

**Other Collections** — Mishkat al-Masabih, Riyad as-Salihin, Bulugh al-Maram, Al-Adab Al-Mufrad, Shama'il Muhammadiyah

**Forties** — Imam Nawawi's 40, 40 Hadith Qudsi, Shah Waliullah's 40

## Running locally

### 1. Get the source data

Download the hadith JSON data into `data/hadith-json/`. The build script expects JSON files at `data/hadith-json/db/by_book/`.

### 2. Install and build

```
npm install
npm run build:db        # builds SQLite database from source JSON
npm run build:embeddings # builds semantic search embeddings
npm run dev             # start dev server
```

The `prebuild` script runs `build:db` and downloads the ML model automatically when you run `npm run build`.

### 3. Production build

```
npm run build
npm start
```

## Stack

- [Next.js](https://nextjs.org) with App Router
- [Transformers.js](https://huggingface.co/docs/transformers.js) for in-browser semantic search
- [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) for server-side hadith storage and search
- [Tailwind CSS](https://tailwindcss.com)

## Disclaimer

This tool searches major hadith collections. It is not a substitute for scholarly verification.

## License

MIT — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.
