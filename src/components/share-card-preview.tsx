"use client";

import { useState, useMemo, useEffect, useCallback } from "react";

interface ShareCardPreviewProps {
  blob: Blob;
  filename: string;
  onClose: () => void;
}

export function ShareCardPreview({ blob, filename, onClose }: ShareCardPreviewProps) {
  const url = useMemo(() => URL.createObjectURL(blob), [blob]);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    return () => URL.revokeObjectURL(url);
  }, [url]);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    },
    [onClose],
  );

  useEffect(() => {
    document.addEventListener("keydown", handleKeyDown);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [handleKeyDown]);

  function download() {
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
  }

  async function copyToClipboard() {
    try {
      await navigator.clipboard.write([
        new ClipboardItem({ "image/png": blob }),
      ]);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback: download if clipboard write not supported
      download();
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      role="dialog"
      aria-modal="true"
      aria-label="Share card preview"
    >
      <div className="bg-white rounded-lg shadow-xl max-w-lg w-full mx-4">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={url}
          alt="Share card preview"
          className="w-full rounded-t-lg"
        />
        <div className="flex gap-3 p-4">
          <button
            onClick={download}
            className="flex-1 text-sm font-medium text-neutral-700 hover:text-neutral-900 transition-colors border border-neutral-200 rounded-md px-3 py-2 cursor-pointer"
          >
            Download
          </button>
          <button
            onClick={copyToClipboard}
            className="flex-1 text-sm font-medium text-white bg-neutral-900 hover:bg-neutral-800 transition-colors rounded-md px-3 py-2 cursor-pointer"
          >
            {copied ? "Copied!" : "Copy image"}
          </button>
          <button
            onClick={onClose}
            className="text-sm text-neutral-500 hover:text-neutral-700 transition-colors border border-neutral-200 rounded-md px-3 py-2 cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
