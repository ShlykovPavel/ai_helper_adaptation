import { test } from "node:test";
import assert from "node:assert/strict";
import {
  getProviderBadgeColor,
  getCompactEyeOffsets,
  getCompactSpecularOffsets,
  getCompactCheekOffsets,
  drawCompactMascot,
} from "../src/mascot/shapeshifter-compact.ts";

function createMockContext() {
  const operations = [];
  return {
    operations,
    save: () => operations.push(["save"]),
    restore: () => operations.push(["restore"]),
    translate: (x, y) => operations.push(["translate", x, y]),
    beginPath: () => operations.push(["beginPath"]),
    closePath: () => operations.push(["closePath"]),
    stroke: () => operations.push(["stroke"]),
    fill: () => operations.push(["fill"]),
    roundRect: (...args) => operations.push(["roundRect", ...args]),
    arc: (...args) => operations.push(["arc", ...args]),
    moveTo: (...args) => operations.push(["moveTo", ...args]),
    quadraticCurveTo: (...args) => operations.push(["quadraticCurveTo", ...args]),
    ellipse: (...args) => operations.push(["ellipse", ...args]),
    createRadialGradient: (...args) => ({
      addColorStop: () => {},
    }),
    strokeStyle: "",
    fillStyle: "",
    lineWidth: 1,
    shadowColor: "",
    shadowBlur: 0,
  };
}

test("Compact LOD badge colors and astral fallback", () => {
  assert.equal(getProviderBadgeColor("claude"), "#D97757");
  assert.equal(getProviderBadgeColor("gemini"), "#4E80EE");
  assert.equal(getProviderBadgeColor("openai"), "#10A37F");
  assert.equal(getProviderBadgeColor("antigravity"), "#8B5CF6");
  assert.equal(getProviderBadgeColor("custom"), "#64D2FF");
  assert.equal(getProviderBadgeColor("unknown_provider"), "#64D2FF");
});

test("Compact LOD eye tracking offsets and specular highlights", () => {
  const eyes = getCompactEyeOffsets(1.0, -1.0, 24);
  assert.ok(Math.abs(eyes.left.x) <= 6.0, "Left eye within safe horizontal boundary");
  assert.ok(Math.abs(eyes.right.x) <= 6.0, "Right eye within safe horizontal boundary");

  const highlights = getCompactSpecularOffsets(0.0, 0.0, 24);
  assert.ok(
    highlights.leftPrimary.x < eyes.left.x && highlights.leftPrimary.y < eyes.left.y,
    "Left eye primary specular dot is in top-left quadrant"
  );
});

test("Compact LOD rosy cheek blush geometry", () => {
  const cheeks = getCompactCheekOffsets(24);
  assert.ok(cheeks.left.y > 0 && cheeks.right.y > 0, "Cheeks are positioned below eye level");
  assert.ok(cheeks.radius >= 1.2 && cheeks.radius <= 3.0, "Cheek radius is proportional");
});

test("drawCompactMascot renders shapes with 1:1 clamping and mock canvas", () => {
  const shapes = ["squircle", "orb", "flameWisp"];

  for (const shape of shapes) {
    const ctx = createMockContext();
    drawCompactMascot({
      ctx,
      width: 40,
      height: 20,
      lookX: 0.5,
      lookY: -0.5,
      shape,
      provider: "claude",
      isPulsing: true,
    });

    // ox should be (40 - 20) / 2 = 10, oy should be 0
    const translateOp = ctx.operations.find((op) => op[0] === "translate");
    assert.ok(translateOp, `translate should be called for ${shape}`);
    assert.equal(translateOp[1], 10);
    assert.equal(translateOp[2], 0);

    // Context should be restored
    assert.equal(ctx.operations[0][0], "save");
    assert.equal(ctx.operations[ctx.operations.length - 1][0], "restore");

    // Must have multiple fill operations (body, flame tuft, cheeks, eyes, specular, badge)
    const fillOps = ctx.operations.filter((op) => op[0] === "fill");
    assert.ok(fillOps.length >= 5, `Expected multiple fills for spirit body, eyes, cheeks, got ${fillOps.length}`);

    // Must have stroke for outer rim
    const strokeOps = ctx.operations.filter((op) => op[0] === "stroke");
    assert.ok(strokeOps.length >= 1, "Expected rim stroke");
  }

  // Early return for side < 8
  const smallCtx = createMockContext();
  drawCompactMascot({
    ctx: smallCtx,
    width: 6,
    height: 6,
    lookX: 0,
    lookY: 0,
    shape: "squircle",
    provider: "openai",
  });
  assert.equal(smallCtx.operations.length, 0);
});
