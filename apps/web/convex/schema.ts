import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  hadith: defineTable({
    collection: v.string(),
    collection_slug: v.string(),
    hadith_number: v.string(),
    order: v.number(),
    narrator: v.string(),
    english: v.string(),
    arabic: v.string(),
    grading: v.string(),
    graded_by: v.string(),
    isnad_narrators: v.optional(v.array(v.string())),
    embedding: v.optional(v.array(v.float64())),
    chapter_id: v.optional(v.number()),
    chapter_english: v.optional(v.string()),
    hadith_in_chapter: v.optional(v.number()),
  })
    .index("by_slug_number", ["collection_slug", "hadith_number"])
    .index("by_collection_order", ["collection_slug", "order"])
    .index("by_chapter_order", ["collection_slug", "chapter_id", "order"])
    .searchIndex("search_english", {
      searchField: "english",
      filterFields: ["collection_slug"],
    })
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 384,
      filterFields: ["collection_slug"],
    }),

  chapters: defineTable({
    collection_slug: v.string(),
    chapter_id: v.number(),
    name_english: v.string(),
    name_arabic: v.string(),
    hadith_count: v.number(),
    order: v.number(),
  })
    .index("by_collection", ["collection_slug", "order"])
    .index("by_collection_chapter", ["collection_slug", "chapter_id"]),

  collection_counts: defineTable({
    collection_slug: v.string(),
    count: v.number(),
  }).index("by_slug", ["collection_slug"]),
});
