import { query, action, mutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";

export const getByRef = query({
  args: { slug: v.string(), number: v.string() },
  handler: async (ctx, { slug, number }) => {
    return ctx.db
      .query("hadith")
      .withIndex("by_slug_number", (q) =>
        q.eq("collection_slug", slug).eq("hadith_number", number)
      )
      .unique();
  },
});

export const getByCollectionPaginated = query({
  args: {
    slug: v.string(),
    page: v.number(),
    pageSize: v.optional(v.number()),
  },
  handler: async (ctx, { slug, page, pageSize: ps }) => {
    const pageSize = ps ?? 50;
    const offset = page * pageSize;

    const countDoc = await ctx.db
      .query("collection_counts")
      .withIndex("by_slug", (q) => q.eq("collection_slug", slug))
      .unique();
    const total = countDoc?.count ?? 0;

    const hadith = await ctx.db
      .query("hadith")
      .withIndex("by_collection_order", (q) =>
        q
          .eq("collection_slug", slug)
          .gte("order", offset)
          .lt("order", offset + pageSize)
      )
      .collect();

    return { hadith, total };
  },
});

export const getCollectionCounts = query({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("collection_counts").collect();
    return rows.map((r) => ({ slug: r.collection_slug, count: r.count }));
  },
});

// FTS-only search (used as fallback and one leg of hybrid)
export const searchFts = query({
  args: { query: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { query: q, limit: lim }) => {
    const limit = lim ?? 20;
    const results = await ctx.db
      .query("hadith")
      .withSearchIndex("search_english", (sq) => sq.search("english", q))
      .take(limit);

    return results.map((hadith, i) => ({
      hadith,
      score: Math.round(Math.max(0, ((limit - i) / limit) * 100)),
    }));
  },
});

// Internal query to fetch hadith by IDs (for vector search results)
export const fetchByIds = internalQuery({
  args: { ids: v.array(v.id("hadith")) },
  handler: async (ctx, { ids }) => {
    const results = [];
    for (const id of ids) {
      const doc = await ctx.db.get(id);
      if (doc) results.push(doc);
    }
    return results;
  },
});

// Hybrid search action: vector search + FTS combined via RRF
export const hybridSearch = action({
  args: {
    embedding: v.array(v.float64()),
    query: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { embedding, query: q, limit: lim }): Promise<
    Array<{ hadith: Record<string, unknown>; score: number }>
  > => {
    const limit = lim ?? 20;
    const fetchLimit = limit * 2;

    // Run vector search and FTS separately (avoid Promise.all inference issues)
    const vectorResults = await ctx.vectorSearch("hadith", "by_embedding", {
      vector: embedding,
      limit: fetchLimit,
    });

    const ftsResults = await ctx.runQuery(internal.hadith.searchFtsInternal, {
      query: q,
      limit: fetchLimit,
    });

    // Fetch full documents for vector search results
    const vectorIds = vectorResults.map(
      (r: { _id: string; _score: number }) => r._id as Id<"hadith">
    );
    const vectorDocs =
      vectorIds.length > 0
        ? await ctx.runQuery(internal.hadith.fetchByIds, {
            ids: vectorIds,
          })
        : [];
    const vectorDocMap = new Map(
      vectorDocs.map((d: Record<string, unknown>) => [d._id as string, d])
    );

    // Reciprocal Rank Fusion
    const K = 60;
    const scores = new Map<string, number>();
    const hadithMap = new Map<string, Record<string, unknown>>();

    vectorResults.forEach(
      (r: { _id: string; _score: number }, rank: number) => {
        const id = r._id as string;
        scores.set(id, (scores.get(id) ?? 0) + 1 / (K + rank + 1));
        const doc = vectorDocMap.get(id);
        if (doc) hadithMap.set(id, doc);
      }
    );

    ftsResults.forEach((doc: Record<string, unknown>, rank: number) => {
      const id = doc._id as string;
      scores.set(id, (scores.get(id) ?? 0) + 1 / (K + rank + 1));
      if (!hadithMap.has(id)) hadithMap.set(id, doc);
    });

    const ranked = [...scores.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit);

    const maxScore = ranked[0]?.[1] ?? 1;

    const results: Array<{ hadith: Record<string, unknown>; score: number }> =
      [];
    for (const [id, score] of ranked) {
      const hadith = hadithMap.get(id);
      if (hadith) {
        results.push({
          hadith,
          score: Math.round((score / maxScore) * 100),
        });
      }
    }
    return results;
  },
});

// Internal FTS query (for use within the hybridSearch action)
export const searchFtsInternal = internalQuery({
  args: { query: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { query: q, limit: lim }) => {
    const limit = lim ?? 20;
    return ctx.db
      .query("hadith")
      .withSearchIndex("search_english", (sq) => sq.search("english", q))
      .take(limit);
  },
});

// Seed-only mutations
export const insertBatch = mutation({
  args: {
    hadith: v.array(
      v.object({
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
      })
    ),
  },
  handler: async (ctx, { hadith }) => {
    for (const h of hadith) {
      await ctx.db.insert("hadith", h);
    }
  },
});

export const insertCollectionCounts = mutation({
  args: {
    counts: v.array(
      v.object({ collection_slug: v.string(), count: v.number() })
    ),
  },
  handler: async (ctx, { counts }) => {
    for (const c of counts) {
      await ctx.db.insert("collection_counts", c);
    }
  },
});

export const clearAll = mutation({
  args: { table: v.union(v.literal("hadith"), v.literal("collection_counts")) },
  handler: async (ctx, { table }) => {
    const docs = await ctx.db.query(table).take(500);
    for (const doc of docs) {
      await ctx.db.delete(doc._id);
    }
    return docs.length;
  },
});

// Patch embeddings onto existing hadith documents
export const patchEmbeddings = mutation({
  args: {
    patches: v.array(
      v.object({
        id: v.id("hadith"),
        embedding: v.array(v.float64()),
      })
    ),
  },
  handler: async (ctx, { patches }) => {
    for (const { id, embedding } of patches) {
      await ctx.db.patch(id, { embedding });
    }
  },
});
