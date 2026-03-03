import fs from "fs";
import path from "path";

interface RawHadith {
  id: number;
  idInBook: number;
  arabic: string;
  english: { narrator: string; text: string };
  chapterId: number;
  bookId: number;
}

interface BookFile {
  id: number;
  metadata: {
    id: number;
    length: number;
    arabic: { title: string; author: string };
    english: { title: string; author: string };
  };
  chapters: { id: number; bookId: number; arabic: string; english: string }[];
  hadiths: RawHadith[];
}

// Compact format: [collection, hadithNumber, narrator, english, grading, gradedBy]
type CompactHadith = [string, string, string, string, string, string];

const SAHIH_COLLECTIONS = new Set(["bukhari", "muslim"]);

function cleanText(text: string): string {
  return text.replace(/\s+/g, " ").replace(/\n/g, " ").trim();
}

function processBook(filePath: string, collectionKey: string): { compact: CompactHadith[]; arabic: string[] } {
  const raw: BookFile = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  const collectionName = raw.metadata.english.title;
  const compact: CompactHadith[] = [];
  const arabic: string[] = [];

  const isSahih = SAHIH_COLLECTIONS.has(collectionKey);

  for (const h of raw.hadiths) {
    const englishText = cleanText(h.english.text);
    if (!englishText) continue;

    const grading = isSahih ? "Sahih" : "";
    const gradedBy = isSahih ? "By consensus" : "";

    compact.push([
      collectionName,
      String(h.idInBook),
      cleanText(h.english.narrator || ""),
      englishText,
      grading,
      gradedBy,
    ]);
    arabic.push(h.arabic);
  }

  return { compact, arabic };
}

function main() {
  const dataDir = path.join(process.cwd(), "data", "hadith-json", "db", "by_book");
  const outputDir = path.join(process.cwd(), "public");

  const dirs = ["the_9_books", "other_books", "forties"];
  const allCompact: CompactHadith[] = [];
  const allArabic: string[] = [];

  for (const dir of dirs) {
    const fullDir = path.join(dataDir, dir);
    if (!fs.existsSync(fullDir)) continue;

    const files = fs.readdirSync(fullDir).filter((f) => f.endsWith(".json"));
    for (const file of files) {
      const collectionKey = file.replace(".json", "");
      const filePath = path.join(fullDir, file);
      console.log(`Processing: ${dir}/${file}`);
      const { compact, arabic } = processBook(filePath, collectionKey);
      allCompact.push(...compact);
      allArabic.push(...arabic);
    }
  }

  console.log(`Total hadith: ${allCompact.length}`);

  // Write compact hadith data (no Arabic)
  fs.writeFileSync(
    path.join(outputDir, "hadith-data.json"),
    JSON.stringify(allCompact)
  );

  // Write Arabic text separately (lazy loaded)
  fs.writeFileSync(
    path.join(outputDir, "hadith-arabic.json"),
    JSON.stringify(allArabic)
  );

  const dataSize = fs.statSync(path.join(outputDir, "hadith-data.json")).size;
  const arabicSize = fs.statSync(path.join(outputDir, "hadith-arabic.json")).size;
  console.log(`hadith-data.json: ${(dataSize / 1024 / 1024).toFixed(2)} MB`);
  console.log(`hadith-arabic.json: ${(arabicSize / 1024 / 1024).toFixed(2)} MB`);
  console.log("Build complete!");
}

main();
