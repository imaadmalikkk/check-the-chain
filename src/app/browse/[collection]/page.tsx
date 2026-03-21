import Link from "next/link";
import { notFound } from "next/navigation";
import { fetchQuery } from "convex/nextjs";
import { api } from "@convex/_generated/api";
import { getCollectionBySlug } from "@/lib/collections";
import { hadithUrl, browseUrl, chapterUrl } from "@/lib/urls";
import { GradingBadge } from "@/components/grading-badge";

const PAGE_SIZE = 50;

export default async function CollectionPage({
  params,
  searchParams,
}: {
  params: Promise<{ collection: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { collection: slug } = await params;
  const { page: pageParam } = await searchParams;
  const collection = getCollectionBySlug(slug);
  if (!collection) notFound();

  // Fetch chapters for this collection
  const chapters = await fetchQuery(api.hadith.getChaptersByCollection, { slug });

  // If 0-1 chapters (Forties, etc.), show flat hadith list directly
  if (chapters.length <= 1) {
    const page = Math.max(0, parseInt(pageParam ?? "1", 10) - 1);
    const { hadith: hadithList, total } = await fetchQuery(
      api.hadith.getByCollectionPaginated,
      { slug, page, pageSize: PAGE_SIZE }
    );
    const totalPages = Math.ceil(total / PAGE_SIZE);

    return (
      <div className="pt-12 sm:pt-16 pb-16">
        <Link
          href={browseUrl()}
          className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
        >
          &larr; All collections
        </Link>

        <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-1">
          {collection.name}
        </h1>
        <p className="text-sm text-neutral-500 mb-8">
          {total.toLocaleString()} hadith
        </p>

        <div className="space-y-1">
          {hadithList.map((h) => (
            <Link
              key={h._id}
              href={hadithUrl(slug, h.hadith_number)}
              className="flex items-start gap-2 sm:gap-3 rounded-lg px-1 sm:px-3 py-3 hover:bg-neutral-50 transition-colors"
            >
              <span className="text-xs text-neutral-400 font-mono w-6 sm:w-10 shrink-0 pt-0.5 text-right">
                {h.hadith_number}
              </span>
              <div className="flex-1 min-w-0">
                <p className="text-sm text-neutral-700 line-clamp-2 leading-relaxed">
                  {h.english.slice(0, 150)}{h.english.length > 150 ? "…" : ""}
                </p>
              </div>
              {h.grading && h.grading !== "Unknown" && (
                <div className="shrink-0 pt-0.5">
                  <GradingBadge grading={h.grading} />
                </div>
              )}
            </Link>
          ))}
        </div>

        {totalPages > 1 && (
          <div className="flex items-center justify-between mt-8 pt-4 border-t border-neutral-100">
            {page > 0 ? (
              <Link
                href={`/browse/${slug}?page=${page}`}
                className="text-sm text-neutral-600 hover:text-neutral-900 transition-colors"
              >
                Previous
              </Link>
            ) : (
              <span className="text-sm text-neutral-300">Previous</span>
            )}
            <span className="text-xs text-neutral-400 font-mono">
              {page + 1} / {totalPages}
            </span>
            {page < totalPages - 1 ? (
              <Link
                href={`/browse/${slug}?page=${page + 2}`}
                className="text-sm text-neutral-600 hover:text-neutral-900 transition-colors"
              >
                Next
              </Link>
            ) : (
              <span className="text-sm text-neutral-300">Next</span>
            )}
          </div>
        )}
      </div>
    );
  }

  // Multiple chapters — show chapter list
  const totalHadith = chapters.reduce((sum, ch) => sum + ch.hadith_count, 0);

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <Link
        href={browseUrl()}
        className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
      >
        &larr; All collections
      </Link>

      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-1">
        {collection.name}
      </h1>
      <p className="text-sm text-neutral-500 mb-8">
        {totalHadith.toLocaleString()} hadith across {chapters.length} books
      </p>

      <div className="space-y-1">
        {chapters.map((ch) => (
          <Link
            key={ch.chapter_id}
            href={chapterUrl(slug, ch.chapter_id)}
            className="flex items-start gap-3 rounded-lg px-2 sm:px-3 py-3 hover:bg-neutral-50 transition-colors"
          >
            <span className="text-xs text-neutral-400 font-mono w-6 sm:w-10 shrink-0 pt-1 text-right">
              {ch.chapter_id}
            </span>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-neutral-700">
                {ch.name_english}
              </p>
              <p
                className="text-sm text-neutral-400 mt-0.5 font-[family-name:var(--font-arabic)]"
                dir="rtl"
                lang="ar"
              >
                {ch.name_arabic}
              </p>
            </div>
            <span className="text-xs text-neutral-400 shrink-0 pt-1">
              {ch.hadith_count}
            </span>
          </Link>
        ))}
      </div>
    </div>
  );
}
