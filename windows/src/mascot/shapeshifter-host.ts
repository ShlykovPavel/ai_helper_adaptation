import type { MascotActionState, ProviderCoreId } from "./types";
import { MascotSettingsManager } from "./settings.ts";
import { drawCompactMascot } from "./shapeshifter-compact.ts";
import { drawExpandedMascot } from "./shapeshifter-expanded.ts";

export function mapActionFromBotState(botState: string): MascotActionState {
  switch (botState) {
    case "working":    return "writing";
    case "searching":  return "reading";
    case "thinking":   return "thinking";
    case "permission":
    case "question":   return "approval";
    case "error":      return "error";
    case "sleeping":   return "sleeping";
    default:           return "idle";
  }
}

export function renderMascotFacade(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  state: { mode: string; effectiveState: string; focusTask?: { id: string } | null; mouse?: { x: number; y: number } },
  phase: number
): boolean {
  if (MascotSettingsManager.getSelectedMascot() !== "shapeshifter") {
    return false; // Let original Mochi engine draw
  }

  const action = mapActionFromBotState(state.effectiveState);
  const shape = MascotSettingsManager.getShape();
  const provider = (state.focusTask?.id?.includes("claude") ? "claude" : "antigravity") as ProviderCoreId;

  if (state.mode === "compact") {
    drawCompactMascot({ ctx, width: w, height: h, lookX: 0, lookY: 0, shape, provider });
  } else {
    drawExpandedMascot({ ctx, width: w, height: h, action, shape, provider, lookX: 0, lookY: 0, phase });
  }
  return true;
}
