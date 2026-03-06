import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  serverExternalPackages: ["better-sqlite3"],
  images: { unoptimized: true },
  outputFileTracingExcludes: {
    "*": ["node_modules/@img/**"],
  },
  outputFileTracingIncludes: {
    "/api/search": ["./data/hadith.db", "./data/models/**/*"],
    "/hadith/[collection]/[number]": ["./data/hadith.db"],
    "/isnad/[collection]/[number]": ["./data/hadith.db"],
    "/browse/[collection]": ["./data/hadith.db"],
  },
};

export default nextConfig;
