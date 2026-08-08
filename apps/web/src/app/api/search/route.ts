import { NextRequest, NextResponse } from "next/server";
import { fetchAction } from "convex/nextjs";
import { api } from "@convex/_generated/api";

export async function POST(request: NextRequest) {
  const { query, embedding, limit: rawLimit } = await request.json();
  const q = (query ?? "").trim();
  const limit = Math.min(Math.max(parseInt(rawLimit ?? "20", 10) || 20, 1), 100);

  if (q.length < 3) {
    return NextResponse.json({ results: [] });
  }

  if (!embedding) {
    return NextResponse.json({ results: [], error: "embedding required" });
  }

  const results = await fetchAction(api.hadith.hybridSearch, {
    embedding,
    query: q,
    limit,
  });
  return NextResponse.json({ results });
}
