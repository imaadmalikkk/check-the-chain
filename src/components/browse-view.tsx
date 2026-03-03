"use client";

import { useState, useEffect } from "react";
import { getAllCollections, getCollectionsByGroup, type CollectionMeta } from "@/lib/collections";
import { collectionUrl } from "@/lib/router";
import { initSearch, getHadithByCollection } from "@/lib/search";

export function BrowseView() {
  const [counts, setCounts] = useState<Map<string, number>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    initSearch().then(() => {
      const map = new Map<string, number>();
      for (const col of getAllCollections()) {
        map.set(col.name, getHadithByCollection(col.name).length);
      }
      setCounts(map);
      setLoading(false);
    });
  }, []);

  const groups: { title: string; key: CollectionMeta["group"] }[] = [
    { title: "The Nine Books", key: "nine-books" },
    { title: "Other Collections", key: "other" },
    { title: "Forties", key: "forties" },
  ];

  return (
    <div className="pt-12 sm:pt-16 pb-16">
      <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-neutral-900 mb-2">
        Browse Collections
      </h1>
      <p className="text-sm text-neutral-500 mb-10">
        Explore 47,000+ hadith across 17 collections.
      </p>

      {groups.map((group) => (
        <div key={group.key} className="mb-10">
          <h2 className="text-xs font-medium text-neutral-400 uppercase tracking-wider mb-4">
            {group.title}
          </h2>
          <div className="grid gap-3">
            {getCollectionsByGroup(group.key).map((col) => (
              <a
                key={col.slug}
                href={collectionUrl(col.slug)}
                className="block border border-neutral-200 rounded-lg p-4 hover:border-neutral-300 transition-colors"
              >
                <div className="flex items-center justify-between mb-1">
                  <h3 className="text-sm font-medium text-neutral-900">
                    {col.name}
                  </h3>
                  {loading ? (
                    <span className="h-4 w-12 bg-neutral-100 rounded animate-pulse" />
                  ) : (
                    <span className="text-xs text-neutral-400 font-mono">
                      {(counts.get(col.name) ?? 0).toLocaleString()}
                    </span>
                  )}
                </div>
                <p className="text-xs text-neutral-500 leading-relaxed">
                  {col.description}
                </p>
              </a>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
