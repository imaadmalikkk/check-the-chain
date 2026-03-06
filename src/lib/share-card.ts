import type { Grading } from "@/lib/types";

export interface ShareCardData {
  english: string;
  narrator: string;
  reference: string;
  grading: Grading;
  gradedBy: string;
  arabicText?: string;
}

const CARD_SIZE = 1080;
const PAD = 72;
const BG = "#FAFAF9";
const TEXT_COLOR = "#1C1917";
const MUTED = "#78716C";
const WATERMARK = "#A8A29E";

const GRADING_COLORS: Record<Grading, string> = {
  Sahih: "#059669",
  Hasan: "#D97706",
  "Da'if": "#DC2626",
  "Mawdu'": "#991B1B",
  Unknown: "#737373",
};

const GRADING_LABELS: Record<Grading, string> = {
  Sahih: "Authentic",
  Hasan: "Good",
  "Da'if": "Weak",
  "Mawdu'": "Fabricated",
  Unknown: "Ungraded",
};

// Inter for English, Amiri for Arabic — loaded via next/font/google
const ENGLISH_FONT = `"Inter", "Helvetica Neue", Arial, sans-serif`;
const ARABIC_FONT = `"Amiri", "Noto Naskh Arabic", serif`;

function wrapText(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const test = current ? `${current} ${word}` : word;
    if (ctx.measureText(test).width > maxWidth && current) {
      lines.push(current);
      current = word;
    } else {
      current = test;
    }
  }
  if (current) lines.push(current);
  return lines;
}

export async function renderShareCard(data: ShareCardData): Promise<Blob> {
  await document.fonts.ready;

  const canvas = document.createElement("canvas");
  canvas.width = CARD_SIZE;
  canvas.height = CARD_SIZE;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas 2D context not available");

  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, CARD_SIZE, CARD_SIZE);

  const contentWidth = CARD_SIZE - PAD * 2;
  let y = PAD;

  const footerSpace = 120;
  const maxContentY = CARD_SIZE - footerSpace;
  const hasArabic = !!data.arabicText;

  // Arabic gets at most 30% of available space, English gets the rest
  const availableSpace = maxContentY - PAD;
  const maxArabicHeight = hasArabic ? availableSpace * 0.3 : 0;

  // Fit Arabic into its budget
  let arabicLines: string[] = [];
  let arabicFontSize = 28;
  let arabicLineHeight = 42;
  if (hasArabic) {
    for (let size = 28; size >= 16; size -= 2) {
      ctx.font = `${size}px ${ARABIC_FONT}`;
      const lines = wrapText(ctx, data.arabicText!, contentWidth);
      const lh = size * 1.6;
      // Cap at 3 lines max
      const capped = lines.slice(0, 3);
      if (capped.length * lh <= maxArabicHeight) {
        arabicLines = capped;
        arabicFontSize = size;
        arabicLineHeight = lh;
        if (lines.length > 3) {
          arabicLines[2] += "...";
        }
        break;
      }
    }
  }

  // Render Arabic
  if (arabicLines.length > 0) {
    ctx.save();
    ctx.direction = "rtl";
    ctx.textAlign = "right";
    ctx.font = `${arabicFontSize}px ${ARABIC_FONT}`;
    ctx.fillStyle = MUTED;

    for (const line of arabicLines) {
      y += arabicLineHeight;
      ctx.fillText(line, CARD_SIZE - PAD, y);
    }
    ctx.restore();
    y += 24;
  }

  // Fit English into remaining space
  const englishBudget = maxContentY - y;
  let bestSize = 22;
  let bestLines: string[] = [];

  for (let size = 56; size >= 22; size -= 2) {
    ctx.font = `400 ${size}px ${ENGLISH_FONT}`;
    const lines = wrapText(ctx, `\u201C${data.english}\u201D`, contentWidth);
    const lh = size * 1.45;
    if (lines.length * lh <= englishBudget) {
      bestSize = size;
      bestLines = lines;
      break;
    }
  }

  // Truncate if still overflowing at min size
  if (bestLines.length === 0) {
    ctx.font = `400 22px ${ENGLISH_FONT}`;
    bestLines = wrapText(ctx, `\u201C${data.english}\u201D`, contentWidth);
    bestSize = 22;
  }
  const lineHeight = bestSize * 1.45;
  const maxLines = Math.floor(englishBudget / lineHeight);
  if (bestLines.length > maxLines && maxLines > 0) {
    bestLines = bestLines.slice(0, maxLines);
    bestLines[maxLines - 1] = bestLines[maxLines - 1].replace(/\s*\u201D$/, "...\u201D");
  }

  // Render English
  ctx.textAlign = "left";
  ctx.fillStyle = TEXT_COLOR;
  ctx.font = `400 ${bestSize}px ${ENGLISH_FONT}`;
  for (const line of bestLines) {
    y += lineHeight;
    ctx.fillText(line, PAD, y);
  }

  // Divider
  y += 32;
  ctx.strokeStyle = "#D6D3D1";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(PAD, y);
  ctx.lineTo(PAD + 80, y);
  ctx.stroke();

  // Footer
  const footerBaseY = CARD_SIZE - PAD;

  // Watermark — bottom right
  ctx.font = `400 20px ${ENGLISH_FONT}`;
  ctx.fillStyle = WATERMARK;
  ctx.textAlign = "right";
  ctx.fillText("checkthechain.org", CARD_SIZE - PAD, footerBaseY);

  // Reference — bottom left
  ctx.font = `600 24px ${ENGLISH_FONT}`;
  ctx.fillStyle = TEXT_COLOR;
  ctx.textAlign = "left";
  ctx.fillText(data.reference, PAD, footerBaseY - 28);

  // Grading
  if (data.grading !== "Unknown" || !data.gradedBy) {
    const dotColor = GRADING_COLORS[data.grading];

    ctx.beginPath();
    ctx.arc(PAD + 6, footerBaseY - 6, 6, 0, Math.PI * 2);
    ctx.fillStyle = dotColor;
    ctx.fill();

    const label =
      data.grading === "Unknown"
        ? "Ungraded"
        : `${GRADING_LABELS[data.grading]}${data.gradedBy ? ` — ${data.gradedBy}` : ""}`;
    ctx.font = `400 20px ${ENGLISH_FONT}`;
    ctx.fillStyle = MUTED;
    ctx.textAlign = "left";
    ctx.fillText(label, PAD + 20, footerBaseY);
  }

  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("Canvas toBlob failed"))),
      "image/png",
    );
  });
}
