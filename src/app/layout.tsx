import type { Metadata } from "next";
import { Inter, Amiri } from "next/font/google";
import Link from "next/link";
import { Nav } from "@/components/nav";
import { Providers } from "./providers";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const amiri = Amiri({
  variable: "--font-arabic",
  subsets: ["arabic"],
  weight: ["400", "700"],
});

export const metadata: Metadata = {
  title: "Check the Chain",
  description:
    "Verify hadith authenticity against 47,000+ narrations from Bukhari, Muslim, and 15 other major collections.",
  openGraph: {
    title: "Check the Chain",
    description:
      "Verify hadith authenticity against 47,000+ narrations from major collections.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Check the Chain",
    description:
      "Verify hadith authenticity against 47,000+ narrations from major collections.",
  },
};

// Static string literal for redirecting old hash-based URLs to new paths.
// This is NOT user input — it's a hardcoded redirect script for backwards compatibility.
const HASH_REDIRECT_SCRIPT = `(function(){var h=location.hash;if(h&&h.length>2){var p=h.replace(/^#\\/?/,"");if(p){location.replace("/"+p+location.search)}}})()`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <script dangerouslySetInnerHTML={{ __html: HASH_REDIRECT_SCRIPT }} />
      </head>
      <body className={`${inter.variable} ${amiri.variable} antialiased`}>
        <Providers>
        <div className="min-h-screen flex flex-col">
          <a
            href="#main-content"
            className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-neutral-900 focus:text-white focus:rounded-md focus:text-sm"
          >
            Skip to content
          </a>
          <main
            id="main-content"
            className="flex-1 w-full max-w-2xl mx-auto px-4 sm:px-6"
          >
            <div className="pt-8 sm:pt-12 flex items-center justify-between">
              <Link
                href="/"
                className="text-sm font-medium text-neutral-900 hover:text-neutral-700 transition-colors"
              >
                Check the Chain
              </Link>
              <Nav />
            </div>

            {children}
          </main>

          <footer className="border-t border-neutral-100 py-8 px-4 sm:px-6">
            <div className="max-w-2xl mx-auto">
              <p className="text-xs text-neutral-500 leading-relaxed mb-3">
                This tool searches major hadith collections. It is not a
                substitute for scholarly verification.
              </p>
              <a
                href="https://github.com/imaadmalikkk/check-the-chain"
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-neutral-500 hover:text-neutral-700 transition-colors"
              >
                Open source on GitHub
              </a>
            </div>
          </footer>
        </div>
        </Providers>
      </body>
    </html>
  );
}
