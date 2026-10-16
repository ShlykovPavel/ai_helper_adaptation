import type { MascotActionState, MascotShape, ProviderCoreId } from "./types";
import { getProviderBadgeColor } from "./shapeshifter-compact.ts";

export interface ExpandedDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  action: MascotActionState;
  shape: MascotShape;
  provider: ProviderCoreId;
  lookX: number;
  lookY: number;
  phase: number;
}

export function harmonicCoreYOffset(phase: number, amplitude = 2.5): number {
  return Math.sin(phase * Math.PI * 2) * amplitude;
}

export function drawExpandedMascot(opts: ExpandedDrawOptions): void {
  const { ctx, width, height, action, shape, provider, phase } = opts;
  const side = Math.min(width, height);
  if (side < 16) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const tint = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  // 1. Glassmorphic Body
  ctx.shadowColor = tint;
  ctx.shadowBlur = 12;
  ctx.fillStyle = "rgba(220, 235, 255, 0.25)";
  ctx.strokeStyle = "rgba(255, 255, 255, 0.7)";
  ctx.lineWidth = 1.8;

  const r = side / 2;
  ctx.beginPath();
  if (shape === "squircle") {
    if (typeof ctx.roundRect === "function") {
      ctx.roundRect(4, 4, side - 8, side - 8, r * 0.48);
    } else {
      ctx.rect(4, 4, side - 8, side - 8);
    }
  } else if (shape === "orb") {
    ctx.arc(r, r, r - 4, 0, Math.PI * 2);
  } else {
    // flameWisp
    ctx.moveTo(r, 4);
    ctx.quadraticCurveTo(side - 4, r, r, side - 4);
    ctx.quadraticCurveTo(4, r, r, 4);
  }
  ctx.fill();
  ctx.stroke();

  // 2. Floating AI Core
  const yFloat = harmonicCoreYOffset(phase, 2.5);
  ctx.shadowColor = tint;
  ctx.shadowBlur = 8;
  ctx.fillStyle = tint;
  ctx.beginPath();
  ctx.arc(r, r + 4 + yFloat, 7, 0, Math.PI * 2);
  ctx.fill();

  // 3. Action Props
  ctx.shadowBlur = 0;
  ctx.lineWidth = 1.5;
  if (action === "writing") {
    ctx.strokeStyle = "#64D2FF";
    ctx.strokeRect(r - 10, side - 16, 20, 12);
    ctx.beginPath();
    ctx.moveTo(r + 10 - 4, side - 20);
    ctx.lineTo(r + 10 - 8, side - 10);
    ctx.stroke();
  } else if (action === "reading") {
    ctx.strokeStyle = "#FDE047";
    ctx.beginPath();
    ctx.moveTo(r - 12, side - 14);
    ctx.lineTo(r, side - 8);
    ctx.lineTo(r + 12, side - 14);
    ctx.stroke();
  } else if (action === "thinking") {
    ctx.strokeStyle = "#C084FC";
    ctx.beginPath();
    ctx.arc(r + 10, 12, 4, 0, Math.PI * 1.5);
    ctx.stroke();
  } else if (action === "error") {
    ctx.strokeStyle = "#EF4444";
    ctx.beginPath();
    ctx.moveTo(r - 6, 8);
    ctx.lineTo(r + 6, 16);
    ctx.moveTo(r + 6, 8);
    ctx.lineTo(r - 6, 16);
    ctx.stroke();
  } else if (action === "sleeping") {
    ctx.strokeStyle = "#94A3B8";
    ctx.beginPath();
    ctx.moveTo(side - 14, 8);
    ctx.lineTo(side - 8, 8);
    ctx.lineTo(side - 14, 14);
    ctx.lineTo(side - 8, 14);
    ctx.stroke();
  }

  ctx.restore();
}
