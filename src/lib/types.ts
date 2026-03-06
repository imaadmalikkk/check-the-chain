export type Grading = "Sahih" | "Hasan" | "Da'if" | "Mawdu'" | "Unknown";

export interface Hadith {
  id: number;
  collection: string;
  collection_slug: string;
  hadith_number: string;
  narrator: string;
  english: string;
  arabic: string;
  grading: string;
  graded_by: string;
}

export interface SearchResult {
  hadith: Hadith;
  score: number;
}
