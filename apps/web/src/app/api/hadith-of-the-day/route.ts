import { NextResponse } from "next/server";
import { fetchQuery } from "convex/nextjs";
import { api } from "@convex/_generated/api";

export async function GET() {
  const hadith = await fetchQuery(api.hadith.getHadithOfTheDay);
  return NextResponse.json({ hadith });
}
