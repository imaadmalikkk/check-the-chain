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

## Running locally

```bash
npm install
npm run dev
```

Requires a [Convex](https://convex.dev) deployment. Set `NEXT_PUBLIC_CONVEX_URL` in `.env.local`.

## Stack

- [Next.js](https://nextjs.org) with App Router
- [Convex](https://convex.dev) serverless backend
- [Transformers.js](https://huggingface.co/docs/transformers.js) for in-browser semantic search
- [Tailwind CSS](https://tailwindcss.com)

## Disclaimer

This tool searches major hadith collections. It is not a substitute for scholarly verification.

## License

MIT — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.
