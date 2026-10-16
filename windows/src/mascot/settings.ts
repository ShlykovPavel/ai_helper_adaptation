import type { MascotId, MascotShape } from "./types";

const SELECTED_MASCOT_KEY = "coucou_selected_mascot";
const MASCOT_SHAPE_KEY = "coucou_mascot_shape";

export class MascotSettingsManager {
  static getSelectedMascot(storage?: Storage): MascotId {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    const raw = s?.getItem(SELECTED_MASCOT_KEY);
    if (raw === "mochi" || raw === "shapeshifter") return raw;
    return "shapeshifter"; // Review Focus 1: safe fallback
  }

  static setSelectedMascot(mascot: MascotId, storage?: Storage): void {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    s?.setItem(SELECTED_MASCOT_KEY, mascot);
  }

  static getShape(storage?: Storage): MascotShape {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    const raw = s?.getItem(MASCOT_SHAPE_KEY);
    if (raw === "squircle" || raw === "orb" || raw === "flameWisp") return raw;
    return "squircle";
  }

  static setShape(shape: MascotShape, storage?: Storage): void {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    s?.setItem(MASCOT_SHAPE_KEY, shape);
  }
}
