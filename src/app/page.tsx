import { Suspense } from "react";
import { SearchView } from "@/components/search-view";

export default function Home() {
  return (
    <Suspense>
      <SearchView />
    </Suspense>
  );
}
