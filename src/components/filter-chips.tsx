"use client";

import type { Grading } from "@/lib/types";

interface FilterChipsProps {
  collections: string[];
  gradings: Grading[];
  activeCollections: Set<string>;
  activeGradings: Set<Grading>;
  onToggleCollection: (collection: string) => void;
  onToggleGrading: (grading: Grading) => void;
}

export function FilterChips({
  collections,
  gradings,
  activeCollections,
  activeGradings,
  onToggleCollection,
  onToggleGrading,
}: FilterChipsProps) {
  if (collections.length <= 1 && gradings.length <= 1) return null;

  return (
    <div className="flex flex-wrap gap-2 mb-4">
      {collections.map((col) => {
        const active = activeCollections.has(col);
        return (
          <button
            key={col}
            onClick={() => onToggleCollection(col)}
            className={`text-xs px-2.5 py-1 rounded-full border transition-colors cursor-pointer ${
              active
                ? "bg-neutral-900 text-white border-neutral-900"
                : "bg-white text-neutral-600 border-neutral-200 hover:border-neutral-300"
            }`}
          >
            {col}
          </button>
        );
      })}
      {gradings.length > 1 &&
        gradings.map((g) => {
          const active = activeGradings.has(g);
          return (
            <button
              key={g}
              onClick={() => onToggleGrading(g)}
              className={`text-xs px-2.5 py-1 rounded-full border transition-colors cursor-pointer ${
                active
                  ? "bg-neutral-900 text-white border-neutral-900"
                  : "bg-white text-neutral-600 border-neutral-200 hover:border-neutral-300"
              }`}
            >
              {g}
            </button>
          );
        })}
    </div>
  );
}
