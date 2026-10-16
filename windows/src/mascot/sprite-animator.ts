import type { MascotActionState } from "./types";

export interface SpriteSheetConfig {
  frameCount: number;
  fps: number;
  columns: number;
  rows: number;
  frameWidth: number;
  frameHeight: number;
}

export function defaultConfigForAction(action: MascotActionState): SpriteSheetConfig {
  switch (action) {
    case "idle":     return { frameCount: 20, fps: 24, columns: 20, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "writing":  return { frameCount: 24, fps: 24, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "reading":  return { frameCount: 20, fps: 24, columns: 20, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "thinking": return { frameCount: 18, fps: 24, columns: 18, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "approval": return { frameCount: 16, fps: 24, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "error":    return { frameCount: 16, fps: 24, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "sleeping": return { frameCount: 16, fps: 16, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
  }
}

export class SpriteSheetAnimator {
  config: SpriteSheetConfig;
  isPaused = false;
  currentAction: MascotActionState = "idle";
  private accumulatedTime = 0;

  constructor(config: SpriteSheetConfig) {
    this.config = config;
  }

  get currentFrameIndex(): number {
    if (this.config.frameCount <= 0) return 0;
    const idx = Math.floor(this.accumulatedTime * this.config.fps) % this.config.frameCount;
    return idx >= 0 ? idx : 0;
  }

  update(dt: number): number {
    // Review Focus 2: 0 CPU work when paused
    if (this.isPaused || dt <= 0) return this.currentFrameIndex;
    this.accumulatedTime += dt;
    return this.currentFrameIndex;
  }

  getFrameSourceRect(frameIndex: number): { sx: number; sy: number; sw: number; sh: number } {
    const validIndex = frameIndex % this.config.frameCount;
    const col = validIndex % this.config.columns;
    const row = Math.floor(validIndex / this.config.columns);
    return {
      sx: col * this.config.frameWidth,
      sy: row * this.config.frameHeight,
      sw: this.config.frameWidth,
      sh: this.config.frameHeight,
    };
  }

  frameRect(frameIndex: number): { x: number; y: number; width: number; height: number } {
    const rect = this.getFrameSourceRect(frameIndex);
    return {
      x: rect.sx,
      y: rect.sy,
      width: rect.sw,
      height: rect.sh,
    };
  }

  setAction(action: MascotActionState): void {
    if (this.currentAction !== action) {
      this.currentAction = action;
      this.config = defaultConfigForAction(action);
      this.reset();
    }
  }

  reset(): void {
    this.accumulatedTime = 0;
  }
}
