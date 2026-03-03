"use client";

import { useRoute, searchUrl, browseUrl } from "@/lib/router";

export function Nav() {
  const route = useRoute();

  const links = [
    { label: "Search", href: searchUrl(), active: route.page === "search" },
    { label: "Browse", href: browseUrl(), active: route.page === "browse" || route.page === "collection" },
  ];

  return (
    <nav className="flex gap-6 text-sm">
      {links.map((link) => (
        <a
          key={link.label}
          href={link.href}
          className={`transition-colors ${
            link.active
              ? "text-neutral-900 font-medium"
              : "text-neutral-500 hover:text-neutral-700"
          }`}
        >
          {link.label}
        </a>
      ))}
    </nav>
  );
}
