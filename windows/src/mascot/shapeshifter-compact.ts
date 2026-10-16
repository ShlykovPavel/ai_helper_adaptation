import type { MascotShape, ProviderCoreId } from "./types";

export interface CompactDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  lookX: number;
  lookY: number;
  shape: MascotShape;
  provider: ProviderCoreId;
}

export function getProviderBadgeColor(provider: ProviderCoreId): string {
  switch (provider) {
    case "claude":      return "#D97757";
    case "gemini":      return "#4E80EE";
    case "openai":      return "#10A37F";
    case "antigravity": return "#8B5CF6";
    default:            return "#64D2FF"; // Astral cyan fallback
  }
}

export function drawCompactMascot(opts: CompactDrawOptions): void {
  const { ctx, width, height, lookX, lookY, shape, provider } = opts;
  const side = Math.min(width, height);
  if (side < 8) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const badgeColor = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  // 1. Neon Glowing Silhouette
  ctx.strokeStyle = "rgba(230, 242, 255, 0.95)";
  ctx.lineWidth = 1.5;
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 4;

  const r = side / 2;
  ctx.beginPath();
  if (shape === "squircle") {
    const radius = r * 0.45;
    if (typeof ctx.roundRect === "function") {
      ctx.roundRect(2, 2, side - 4, side - 4, radius);
    } else {
      ctx.rect(2, 2, side - 4, side - 4);
    }
  } else if (shape === "orb") {
    ctx.arc(r, r, r - 2, 0, Math.PI * 2);
  } else {
    // flame wisp
    ctx.moveTo(r, 2);
    ctx.quadraticCurveTo(side - 2, r, r, side - 2);
    ctx.quadraticCurveTo(2, r, r, 2);
  }
  ctx.stroke();

  // 2. White Pill Eyes
  ctx.shadowBlur = 0;
  ctx.fillStyle = "#FFFFFF";
  const eyeShiftX = Math.max(-1, Math.min(1, lookX)) * side * 0.08;
  const eyeShiftY = -Math.max(-1, Math.min(1, lookY)) * side * 0.06;
  const eyeDist = side * 0.22;
  const eyeW = Math.max(2.5, side * 0.12);
  const eyeH = Math.max(4, side * 0.22);

  ctx.beginPath();
  ctx.ellipse(r - eyeDist + eyeShiftX, r + eyeShiftY, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.ellipse(r + eyeDist + eyeShiftX, r + eyeShiftY, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  // 3. Tiny Badge
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 2;
  ctx.fillStyle = badgeColor;
  const badgeSize = Math.max(3.5, side * 0.16);
  ctx.beginPath();
  ctx.arc(side - badgeSize, badgeSize, badgeSize / 2, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}
