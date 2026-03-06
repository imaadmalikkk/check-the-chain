import { NextRequest, NextResponse } from "next/server";
import { fetchAction, fetchQuery } from "convex/nextjs";
import { api } from "@convex/_generated/api";

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q")?.trim() ?? "";
  const limitParam = request.nextUrl.searchParams.get("limit");
  const limit = Math.min(Math.max(parseInt(limitParam ?? "20", 10) || 20, 1), 100);

  if (q.length < 3) {
    return NextResponse.json({ results: [] });
  }

  try {
    // Dynamic import to avoid crashing serverless if ONNX runtime isn't available
    const { embed } = await import("@/lib/embeddings");
    const embedding = await embed(q);
    const results = await fetchAction(api.hadith.hybridSearch, {
      embedding,
      query: q,
      limit,
    });
    return NextResponse.json({ results });
  } catch {
    // Fallback to FTS-only if embeddings fail
    const results = await fetchQuery(api.hadith.searchFts, { query: q, limit });
    return NextResponse.json({ results });
  }
}
