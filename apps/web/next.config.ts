import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: { unoptimized: true },
  turbopack: {
    resolveAlias: {
      sharp: { browser: "" },
      "onnxruntime-node": { browser: "" },
    },
  },
};

export default nextConfig;
