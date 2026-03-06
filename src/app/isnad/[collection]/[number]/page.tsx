import { notFound } from "next/navigation";
import Link from "next/link";
import { fetchQuery } from "convex/nextjs";
import { api } from "@convex/_generated/api";
import { getCollectionBySlug } from "@/lib/collections";
import { hadithUrl } from "@/lib/urls";

function ChainNode({
  name,
  index,
  total,
}: {
  name: string;
  index: number;
  total: number;
}) {
  const isFirst = index === 0;
  const isLast = index === total - 1;

  const roleLabel = isFirst ? "Collector" : isLast ? "Source" : null;

  const dotColor = isLast
    ? "bg-amber-500"
    : isFirst
      ? "bg-neutral-800"
      : "bg-neutral-400";

  return (
    <div className="flex items-start gap-4">
      <div className="flex flex-col items-center shrink-0 w-6">
        {!isFirst && <div className="w-px h-4 bg-neutral-200" />}
        <div className={`w-3 h-3 rounded-full ${dotColor} shrink-0`} />
        {!isLast && <div className="w-px flex-1 bg-neutral-200 min-h-4" />}
      </div>
      <div className={`pb-6 ${isLast ? "pb-0" : ""}`}>
        {roleLabel && (
          <span className="text-[11px] uppercase tracking-wider text-neutral-400 block mb-0.5">
            {roleLabel}
          </span>
        )}
        <p className="text-base text-neutral-800 leading-relaxed" dir="rtl" lang="ar">
          {name}
        </p>
        <p className="text-xs text-neutral-400 mt-0.5">
          {isFirst ? "Narrator #1" : isLast ? `Narrator #${total}` : `Narrator #${index + 1}`}
        </p>
      </div>
    </div>
  );
}

export default async function IsnadPage({
  params,
}: {
  params: Promise<{ collection: string; number: string }>;
}) {
  const { collection: slug, number } = await params;
  const collection = getCollectionBySlug(slug);
  if (!collection) notFound();

  const hadith = await fetchQuery(api.hadith.getByRef, { slug, number });
  if (!hadith) notFound();

  const chain = hadith.isnad_narrators ?? null;
  const reference = `${collection.name} ${number}`;

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <Link
        href={hadithUrl(slug, number)}
        className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors"
      >
        &larr; {reference}
      </Link>

      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-neutral-900 mt-4 mb-2">
        Chain of Narration
      </h1>

      <p className="text-sm text-neutral-500 mb-6">
        {reference} — {chain ? `${chain.length} narrators in this chain` : ""}
      </p>

      {!chain ? (
        <div className="bg-neutral-50 rounded-lg p-6 text-center">
          <p className="text-sm text-neutral-500">
            No chain data available for this hadith.
          </p>
          <Link
            href={hadithUrl(slug, number)}
            className="text-sm text-neutral-700 hover:text-neutral-900 mt-2 inline-block"
          >
            View hadith
          </Link>
        </div>
      ) : (
        <div className="bg-neutral-50 rounded-lg p-5 sm:p-8">
          <div className="flex items-center gap-2 mb-6 pb-4 border-b border-neutral-200">
            <div className="w-3 h-3 rounded-full bg-neutral-800" />
            <span className="text-xs text-neutral-500">= Collector</span>
            <div className="w-3 h-3 rounded-full bg-neutral-400 ml-3" />
            <span className="text-xs text-neutral-500">= Transmitter</span>
            <div className="w-3 h-3 rounded-full bg-amber-500 ml-3" />
            <span className="text-xs text-neutral-500">= Source</span>
          </div>

          {chain.map((name, i) => (
            <ChainNode key={i} name={name} index={i} total={chain.length} />
          ))}
        </div>
      )}

      <p className="text-xs text-neutral-400 mt-4 leading-relaxed">
        This chain is automatically parsed from the Arabic text. Narrator names
        are shown from the collector (who compiled it) to the original source.
      </p>
    </div>
  );
}
