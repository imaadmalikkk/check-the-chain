"use client";

import { Suspense } from "react";
import { useRoute } from "@/lib/router";
import { Nav } from "@/components/nav";
import { SearchView } from "@/components/search-view";
import { BrowseView } from "@/components/browse-view";
import { CollectionView } from "@/components/collection-view";
import { HadithView } from "@/components/hadith-view";

function App() {
  const route = useRoute();

  return (
    <div className="min-h-screen flex flex-col">
      <a href="#main-content" className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-neutral-900 focus:text-white focus:rounded-md focus:text-sm">
        Skip to content
      </a>
      <main id="main-content" className="flex-1 w-full max-w-2xl mx-auto px-4 sm:px-6">
        <div className="pt-8 sm:pt-12 flex items-center justify-between">
          <a href="/" className="text-sm font-medium text-neutral-900 hover:text-neutral-700 transition-colors">
            hadith-check
          </a>
          <Nav />
        </div>

        {route.page === "search" && <SearchView />}
        {route.page === "browse" && <BrowseView />}
        {route.page === "collection" && <CollectionView slug={route.slug} />}
        {route.page === "hadith" && <HadithView slug={route.slug} number={route.number} />}
      </main>

      <footer className="border-t border-neutral-100 py-8 px-4 sm:px-6">
        <div className="max-w-2xl mx-auto">
          <p className="text-xs text-neutral-500 leading-relaxed mb-3">
            This tool searches major hadith collections. It is not a substitute
            for scholarly verification.
          </p>
          <a
            href="https://github.com/imaadmalik/hadith-check"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors"
          >
            Open source on GitHub
          </a>
        </div>
      </footer>
    </div>
  );
}

export default function Home() {
  return (
    <Suspense>
      <App />
    </Suspense>
  );
}
