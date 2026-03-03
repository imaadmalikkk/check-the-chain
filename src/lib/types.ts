export type Grading = "Sahih" | "Hasan" | "Da'if" | "Mawdu'" | "Unknown";

// Compact format from JSON: [collection, hadithNumber, narrator, english, grading, gradedBy]
export type CompactHadith = [string, string, string, string, string, string];

export interface Hadith {
  id: number;
  collection: string;
  hadithNumber: string;
  narrator: string;
  english: string;
  grading: Grading;
  gradedBy: string;
  reference: string;
}

export interface SearchResult {
  hadith: Hadith;
  score: number;
}

export function parseCompactHadith(compact: CompactHadith, id: number): Hadith {
  const [collection, hadithNumber, narrator, english, grading, gradedBy] = compact;
  return {
    id,
    collection,
    hadithNumber,
    narrator,
    english,
    grading: (grading || "Unknown") as Grading,
    gradedBy,
    reference: `${collection} ${hadithNumber}`,
  };
}
