"use client";

import { useRef, useEffect, useCallback } from "react";

export function SearchInput({
  value,
  onChange,
  isLoading,
  disabled = false,
}: {
  value: string;
  onChange: (value: string) => void;
  isLoading: boolean;
  disabled?: boolean;
}) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const autoResize = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 200)}px`;
  }, []);

  useEffect(() => {
    autoResize();
  }, [value, autoResize]);

  useEffect(() => {
    textareaRef.current?.focus();
  }, []);

  return (
    <div className="relative">
      <textarea
        ref={textareaRef}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder='Paste a hadith to verify — e.g. "The reward of deeds depends upon the intentions"'
        aria-label="Search hadith text"
        rows={2}
        disabled={disabled}
        className={`w-full resize-none rounded-lg border border-neutral-200 bg-white px-4 py-3.5 text-[15px] leading-relaxed text-neutral-800 placeholder:text-neutral-400 focus:border-neutral-400 focus:outline-none transition-colors ${disabled ? "opacity-50 cursor-not-allowed" : ""}`}
      />
      {isLoading && (
        <div className="absolute right-3 top-3.5">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-200 border-t-neutral-500" />
        </div>
      )}
    </div>
  );
}
