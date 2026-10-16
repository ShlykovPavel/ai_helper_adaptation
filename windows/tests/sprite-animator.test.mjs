import { test } from "node:test";
import assert from "node:assert/strict";
import { SpriteSheetAnimator } from "../src/mascot/sprite-animator.ts";

test("SpriteSheetAnimator frame math & 0% CPU paused behavior", () => {
  const config = { frameCount: 24, fps: 24, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240 };
  const anim = new SpriteSheetAnimator(config);

  assert.equal(anim.currentFrameIndex, 0);
  anim.update(1 / 24);
  assert.equal(anim.currentFrameIndex, 1);

  // Advance 23 more frames -> frame 0 (modulo wrap)
  anim.update(23 / 24);
  assert.equal(anim.currentFrameIndex, 0);

  // Paused state: Review Focus 2
  anim.isPaused = true;
  anim.update(10);
  assert.equal(anim.currentFrameIndex, 0);

  anim.isPaused = false;
  anim.update(2 / 24);
  assert.equal(anim.currentFrameIndex, 2);

  const rect = anim.getFrameSourceRect(2);
  assert.equal(rect.sx, 480);
  assert.equal(rect.sy, 0);
  assert.equal(rect.sw, 240);
  assert.equal(rect.sh, 240);

  // Action state switch resets time
  anim.setAction("writing");
  assert.equal(anim.currentFrameIndex, 0);
  assert.equal(anim.currentAction, "writing");
});
