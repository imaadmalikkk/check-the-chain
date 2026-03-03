import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Is This Hadith Real?",
  description:
    "Verify hadith authenticity against 47,000+ narrations from Bukhari, Muslim, and 15 other major collections. Free, open source, fully client-side.",
  openGraph: {
    title: "Is This Hadith Real?",
    description:
      "Verify hadith authenticity against 47,000+ narrations from major collections.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Is This Hadith Real?",
    description:
      "Verify hadith authenticity against 47,000+ narrations from major collections.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
