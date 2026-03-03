# Check the Chain

Verify hadith authenticity against 47,000+ narrations from Bukhari, Muslim, and 15 other major collections.

Fully client-side. No server. No tracking. Just search.

---

## What it does

Type a hadith — or even a rough description of one — and Check the Chain finds matching narrations across 17 classical collections. Results include the source, book, chapter, hadith number, and grading where available.

Search is powered by a local AI model that runs entirely in your browser using [Transformers.js](https://huggingface.co/docs/transformers.js). Nothing leaves your device.

## Collections

**The Nine Books** — Sahih al-Bukhari, Sahih Muslim, Sunan al-Nasa'i, Sunan Abi Dawud, Sunan Ibn Majah, Jami' al-Tirmidhi, Muwatta Malik, Musnad Ahmad ibn Hanbal

**Other Collections** — Mishkat al-Masabih, Riyad as-Salihin, Bulugh al-Maram, Al-Adab Al-Mufrad, Shama'il Muhammadiyah

**Forties** — Imam Nawawi's 40, 40 Hadith Qudsi, Shah Waliullah's 40

## Running locally

```
npm install
npm run dev
```

To rebuild the search index and embeddings:

```
npm run build
npm run build:embeddings
```

## Stack

- [Next.js](https://nextjs.org) with static export
- [Transformers.js](https://huggingface.co/docs/transformers.js) for in-browser semantic search
- [FlexSearch](https://github.com/nextapps-de/flexsearch) for keyword search
- [Tailwind CSS](https://tailwindcss.com)

## Disclaimer

This tool searches major hadith collections. It is not a substitute for scholarly verification.

## License

MIT
