"use client";

let arabicTexts: string[] | null = null;
let loadPromise: Promise<string[]> | null = null;

export async function loadArabicData(): Promise<string[]> {
  if (arabicTexts) return arabicTexts;
  if (loadPromise) return loadPromise;

  loadPromise = fetch("/hadith-arabic.json")
    .then((res) => res.json())
    .then((data: string[]) => {
      arabicTexts = data;
      return data;
    });

  return loadPromise;
}

export function getArabicText(hadithId: number): string | undefined {
  return arabicTexts?.[hadithId];
}

export function isArabicLoaded(): boolean {
  return arabicTexts !== null;
}
