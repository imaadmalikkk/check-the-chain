export function hadithUrl(slug: string, number: string): string {
  return `/hadith/${slug}/${number}`;
}

export function collectionUrl(slug: string): string {
  return `/browse/${slug}`;
}

export function browseUrl(): string {
  return "/browse";
}

export function isnadUrl(slug: string, number: string): string {
  return `/isnad/${slug}/${number}`;
}

export function chapterUrl(slug: string, chapterId: number): string {
  return `/browse/${slug}/${chapterId}`;
}
