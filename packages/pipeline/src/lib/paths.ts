import { fileURLToPath } from "node:url";
import path from "node:path";

/** packages/pipeline */
export const PACKAGE_ROOT = fileURLToPath(new URL("../..", import.meta.url));

/** repo root */
export const REPO_ROOT = path.resolve(PACKAGE_ROOT, "../..");

/** Convex lives in the web app; the CLI must run from there to pick up .env.local. */
export const WEB_APP = path.join(REPO_ROOT, "apps/web");

/** Intermediate, regenerable. Gitignored. */
export const CACHE_DIR = path.join(PACKAGE_ROOT, ".cache");
export const EXPORT_ZIP = path.join(CACHE_DIR, "convex-export.zip");
export const EXPORT_DIR = path.join(CACHE_DIR, "convex-export");

/** Build output, staged before being copied into the app bundle. Gitignored. */
export const OUT_DIR = path.join(PACKAGE_ROOT, "out");

/** Where the iOS app expects to find the artifacts. */
export const IOS_RESOURCES = path.join(
  REPO_ROOT,
  "apps/ios/CheckTheChain/Resources",
);

export const GOLDEN_FILE = path.join(
  REPO_ROOT,
  "apps/ios/Tests/HadithKitTests/Resources/golden.json",
);

export function tableJsonl(table: string): string {
  return path.join(EXPORT_DIR, table, "documents.jsonl");
}
