import { test } from "node:test";
import assert from "node:assert/strict";
import { getProviderBadgeColor, drawCompactMascot } from "../src/mascot/shapeshifter-compact.ts";

function createMockContext() {
  const operations = [];
  return {
    operations,
    save: () => operations.push(["save"]),
    restore: () => operations.push(["restore"]),
    translate: (x, y) => operations.push(["translate", x, y]),
    beginPath: () => operations.push(["beginPath"]),
    stroke: () => operations.push(["stroke"]),
    fill: () => operations.push(["fill"]),
    roundRect: (...args) => operations.push(["roundRect", ...args]),
    arc: (...args) => operations.push(["arc", ...args]),
    moveTo: (...args) => operations.push(["moveTo", ...args]),
    quadraticCurveTo: (...args) => operations.push(["quadraticCurveTo", ...args]),
    ellipse: (...args) => operations.push(["ellipse", ...args]),
    strokeStyle: "",
    fillStyle: "",
    lineWidth: 1,
    shadowColor: "",
    shadowBlur: 0
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
      provider: "claude"
    });

    // ox should be (40 - 20) / 2 = 10, oy should be 0
    const translateOp = ctx.operations.find(op => op[0] === "translate");
    assert.ok(translateOp, `translate should be called for ${shape}`);
    assert.equal(translateOp[1], 10);
    assert.equal(translateOp[2], 0);

    // Context should be restored
    assert.equal(ctx.operations[0][0], "save");
    assert.equal(ctx.operations[ctx.operations.length - 1][0], "restore");
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
    provider: "openai"
  });
  assert.equal(smallCtx.operations.length, 0);
});
