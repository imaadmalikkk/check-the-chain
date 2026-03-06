import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getCollectionBySlug } from "@/lib/collections";
import { getHadithByRef, getIsnadChain } from "@/lib/db";
import { HadithDetail } from "@/components/hadith-detail";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ collection: string; number: string }>;
}): Promise<Metadata> {
  const { collection: slug, number } = await params;
  const collection = getCollectionBySlug(slug);
  if (!collection) return {};

  const hadith = getHadithByRef(slug, number);
  if (!hadith) return {};

  const title = `${collection.name} ${number} — Check the Chain`;
  const description = hadith.english.slice(0, 160);

  return {
    title,
    description,
    openGraph: { title, description },
    twitter: { title, description },
  };
}

export default async function HadithPage({
  params,
}: {
  params: Promise<{ collection: string; number: string }>;
}) {
  const { collection: slug, number } = await params;
  const collection = getCollectionBySlug(slug);
  if (!collection) notFound();

  const hadith = getHadithByRef(slug, number);
  if (!hadith) notFound();

  const chain = getIsnadChain(hadith.id);

  return (
    <HadithDetail
      hadith={hadith}
      collection={collection}
      hasIsnad={!!chain}
    />
  );
}
