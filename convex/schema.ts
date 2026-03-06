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
  })
    .index("by_slug_number", ["collection_slug", "hadith_number"])
    .index("by_collection_order", ["collection_slug", "order"])
    .searchIndex("search_english", {
      searchField: "english",
      filterFields: ["collection_slug"],
    })
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 384,
      filterFields: ["collection_slug"],
    }),

  collection_counts: defineTable({
    collection_slug: v.string(),
    count: v.number(),
  }).index("by_slug", ["collection_slug"]),
});
