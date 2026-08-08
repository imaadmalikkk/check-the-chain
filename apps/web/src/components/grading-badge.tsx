import type { Grading } from "@/lib/types";

const gradingStyles: Record<Grading, string> = {
  Sahih: "bg-emerald-50 text-emerald-700 border-emerald-200",
  Hasan: "bg-amber-50 text-amber-700 border-amber-200",
  "Da'if": "bg-red-50 text-red-700 border-red-200",
  "Mawdu'": "bg-red-100 text-red-900 border-red-300",
  Unknown: "bg-neutral-50 text-neutral-500 border-neutral-200",
};

const gradingLabels: Record<Grading, string> = {
  Sahih: "Authentic",
  Hasan: "Good",
  "Da'if": "Weak",
  "Mawdu'": "Fabricated",
  Unknown: "Ungraded",
};

const VALID_GRADINGS = new Set<string>(Object.keys(gradingStyles));

export function GradingBadge({ grading }: { grading: string }) {
  const g: Grading = VALID_GRADINGS.has(grading) ? (grading as Grading) : "Unknown";
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium tracking-wide ${gradingStyles[g]}`}
    >
      {g}
      <span className="text-[10px] opacity-60">({gradingLabels[g]})</span>
    </span>
  );
}
