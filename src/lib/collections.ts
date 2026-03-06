export interface CollectionMeta {
  name: string;
  slug: string;
  group: "nine-books" | "other" | "forties";
  description: string;
}

const COLLECTIONS: CollectionMeta[] = [
  { name: "Sahih al-Bukhari", slug: "sahih-al-bukhari", group: "nine-books", description: "The most authentic collection, compiled by Imam al-Bukhari (d. 870 CE)." },
  { name: "Sahih Muslim", slug: "sahih-muslim", group: "nine-books", description: "The second most authentic collection, compiled by Imam Muslim (d. 875 CE)." },
  { name: "Sunan al-Nasa'i", slug: "sunan-al-nasai", group: "nine-books", description: "Known for its strict criteria, compiled by Imam al-Nasa'i (d. 915 CE)." },
  { name: "Sunan Abi Dawud", slug: "sunan-abi-dawud", group: "nine-books", description: "Focused on legal hadith, compiled by Imam Abu Dawud (d. 889 CE)." },
  { name: "Sunan Ibn Majah", slug: "sunan-ibn-majah", group: "nine-books", description: "Part of the six major collections, compiled by Imam Ibn Majah (d. 887 CE)." },
  { name: "Jami' al-Tirmidhi", slug: "jami-al-tirmidhi", group: "nine-books", description: "Known for grading each hadith, compiled by Imam al-Tirmidhi (d. 892 CE)." },
  { name: "Muwatta Malik", slug: "muwatta-malik", group: "nine-books", description: "The earliest compiled collection, by Imam Malik (d. 795 CE)." },
  { name: "Musnad Ahmad ibn Hanbal", slug: "musnad-ahmad", group: "nine-books", description: "One of the largest collections, compiled by Imam Ahmad (d. 855 CE)." },
  { name: "Mishkat al-Masabih", slug: "mishkat-al-masabih", group: "other", description: "A comprehensive compilation drawing from the six major books and more." },
  { name: "Riyad as-Salihin", slug: "riyad-as-salihin", group: "other", description: "Gardens of the Righteous, compiled by Imam al-Nawawi (d. 1277 CE)." },
  { name: "Bulugh al-Maram", slug: "bulugh-al-maram", group: "other", description: "Hadith related to jurisprudence, compiled by Ibn Hajar al-Asqalani (d. 1449 CE)." },
  { name: "Al-Adab Al-Mufrad", slug: "al-adab-al-mufrad", group: "other", description: "Hadith on manners and etiquette, compiled by Imam al-Bukhari." },
  { name: "Shama'il Muhammadiyah", slug: "shamail-muhammadiyah", group: "other", description: "Description of Prophet Muhammad's appearance and character, by Imam al-Tirmidhi." },
  { name: "The Forty Hadith of Imam Nawawi", slug: "nawawi-40", group: "forties", description: "40 foundational hadith selected by Imam al-Nawawi." },
  { name: "The Forty Hadith Qudsi", slug: "qudsi-40", group: "forties", description: "40 hadith in which Allah speaks in the first person." },
  { name: "The Forty Hadith of Shah Waliullah", slug: "shah-waliullah-40", group: "forties", description: "40 hadith selected by Shah Waliullah al-Dihlawi (d. 1762 CE)." },
];

const bySlug = new Map(COLLECTIONS.map((c) => [c.slug, c]));
const byName = new Map(COLLECTIONS.map((c) => [c.name, c]));

export function getCollectionBySlug(slug: string): CollectionMeta | undefined {
  return bySlug.get(slug);
}

export function getCollectionByName(name: string): CollectionMeta | undefined {
  return byName.get(name);
}

export function slugFromName(name: string): string {
  return byName.get(name)?.slug ?? name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

export function getAllCollections(): CollectionMeta[] {
  return COLLECTIONS;
}

export function getCollectionsByGroup(group: CollectionMeta["group"]): CollectionMeta[] {
  return COLLECTIONS.filter((c) => c.group === group);
}
