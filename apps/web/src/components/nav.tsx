"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export function Nav() {
  const pathname = usePathname();

  const links = [
    { label: "Search", href: "/", active: pathname === "/" },
    { label: "Browse", href: "/browse", active: pathname.startsWith("/browse") },
  ];

  return (
    <nav className="flex gap-6 text-sm">
      {links.map((link) => (
        <Link
          key={link.label}
          href={link.href}
          className={`transition-colors ${
            link.active
              ? "text-neutral-900 font-medium"
              : "text-neutral-500 hover:text-neutral-700"
          }`}
        >
          {link.label}
        </Link>
      ))}
    </nav>
  );
}
