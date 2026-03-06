import { NextRequest, NextResponse } from "next/server";
import { hybridSearch } from "@/lib/search-server";

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q")?.trim() ?? "";
  const limitParam = request.nextUrl.searchParams.get("limit");
  const limit = Math.min(Math.max(parseInt(limitParam ?? "20", 10) || 20, 1), 100);

  if (q.length < 3) {
    return NextResponse.json({ results: [] });
  }

  const results = await hybridSearch(q, limit);
  return NextResponse.json({ results });
}
