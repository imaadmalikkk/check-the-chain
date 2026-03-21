export type Grading = "Sahih" | "Hasan" | "Da'if" | "Mawdu'" | "Unknown";

export interface Hadith {
  _id: string;
  collection: string;
  collection_slug: string;
  hadith_number: string;
  order: number;
  narrator: string;
  english: string;
  arabic: string;
  grading: string;
  graded_by: string;
  isnad_narrators?: string[];
  chapter_id?: number;
  chapter_english?: string;
  hadith_in_chapter?: number;
}

export interface SearchResult {
  hadith: Hadith;
  score: number;
}
