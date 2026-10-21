import type { MascotActionState, ProviderCoreId } from "./types";
import { MascotSettingsManager } from "./settings.ts";
import { drawCompactMascot } from "./shapeshifter-compact.ts";
import { drawExpandedMascot } from "./shapeshifter-expanded.ts";

export function mapActionFromBotState(botState: string): MascotActionState {
  switch (botState) {
    case "working":    return "writing";
    case "searching":  return "reading";
    case "thinking":   return "thinking";
    case "approval":
    case "permission":
    case "question":   return "approval";
    case "error":
    case "ratelimit":
    case "dizzy":      return "error";
    case "sleeping":   return "sleeping";
    default:           return "idle";
  }
}

export interface MascotFacadeGeometry {
  overhang?: number;
  diameter?: number;
  lookX?: number;
  lookY?: number;
}

export function getMascotBodyBounds(
  w: number,
  h: number,
  geom?: MascotFacadeGeometry
): { x: number; y: number; width: number; height: number; cx: number; cy: number } {
  const overhang = geom?.overhang ?? (h > w ? h - w : 0);
  const side = Math.max(8, geom?.diameter ?? (w * 0.6));
  const cx = w / 2;
  const cy = (h + overhang) / 2;
  const x0 = cx - side / 2;
  const y0 = cy - side / 2;
  return { x: x0, y: y0, width: side, height: side, cx, cy };
}

export function renderMascotFacade(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  state: { mode: string; effectiveState: string; focusTask?: { id: string } | null; mouse?: { x: number; y: number } },
  phase: number,
  geom?: MascotFacadeGeometry
): boolean {
  if (MascotSettingsManager.getSelectedMascot() !== "shapeshifter") {
    return false; // Let original Mochi engine draw
  }

  const action = mapActionFromBotState(state.effectiveState);
  const shape = MascotSettingsManager.getShape();
  const provider = (state.focusTask?.id?.includes("claude") ? "claude" : "antigravity") as ProviderCoreId;

  const bounds = getMascotBodyBounds(w, h, geom);
  const lookX = geom?.lookX ?? 0;
  const lookY = geom?.lookY ?? 0;

  ctx.save();
  ctx.translate(bounds.x, bounds.y);
  if (state.mode === "compact") {
    drawCompactMascot({ ctx, width: bounds.width, height: bounds.height, lookX, lookY, shape, provider });
  } else {
    drawExpandedMascot({ ctx, width: bounds.width, height: bounds.height, action, shape, provider, lookX, lookY, phase });
  }
  ctx.restore();
  return true;
}
