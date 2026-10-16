import { test } from "node:test";
import assert from "node:assert/strict";
import { harmonicCoreYOffset, drawExpandedMascot } from "../src/mascot/shapeshifter-expanded.ts";
import { getProviderBadgeColor } from "../src/mascot/shapeshifter-compact.ts";

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
    rect: (...args) => operations.push(["rect", ...args]),
    strokeRect: (...args) => operations.push(["strokeRect", ...args]),
    arc: (...args) => operations.push(["arc", ...args]),
    moveTo: (...args) => operations.push(["moveTo", ...args]),
    lineTo: (...args) => operations.push(["lineTo", ...args]),
    quadraticCurveTo: (...args) => operations.push(["quadraticCurveTo", ...args]),
    strokeStyle: "",
    fillStyle: "",
    lineWidth: 1,
    shadowColor: "",
    shadowBlur: 0
  };
}

test("Expanded LOD harmonic float calculation", () => {
  assert.ok(Math.abs(harmonicCoreYOffset(0)) < 1e-4);
  assert.ok(Math.abs(harmonicCoreYOffset(0.25) - 2.5) < 1e-4);
  assert.ok(Math.abs(harmonicCoreYOffset(0.75) - (-2.5)) < 1e-4);
  assert.ok(Math.abs(harmonicCoreYOffset(1.0)) < 1e-4);
});

test("Expanded LOD provider fallback", () => {
  assert.equal(getProviderBadgeColor("claude"), "#D97757");
  assert.equal(getProviderBadgeColor("gemini"), "#4E80EE");
  assert.equal(getProviderBadgeColor("openai"), "#10A37F");
  assert.equal(getProviderBadgeColor("antigravity"), "#8B5CF6");
  assert.equal(getProviderBadgeColor("custom"), "#64D2FF");
  assert.equal(getProviderBadgeColor("generic_agent"), "#64D2FF");
});

test("drawExpandedMascot renders shapes with 1:1 clamping and mock canvas", () => {
  const shapes = ["squircle", "orb", "flameWisp"];

  for (const shape of shapes) {
    const ctx = createMockContext();
    drawExpandedMascot({
      ctx,
      width: 120,
      height: 60,
      action: "idle",
      shape,
      provider: "antigravity",
      lookX: 0,
      lookY: 0,
      phase: 0.25
    });

    const translateOp = ctx.operations.find(op => op[0] === "translate");
    assert.ok(translateOp, `translate should be called for ${shape}`);
    assert.equal(translateOp[1], 30);
    assert.equal(translateOp[2], 0);

    assert.equal(ctx.operations[0][0], "save");
    assert.equal(ctx.operations[ctx.operations.length - 1][0], "restore");
  }

  const smallCtx = createMockContext();
  drawExpandedMascot({
    ctx: smallCtx,
    width: 12,
    height: 12,
    action: "idle",
    shape: "squircle",
    provider: "claude",
    lookX: 0,
    lookY: 0,
    phase: 0
  });
  assert.equal(smallCtx.operations.length, 0);
});

test("drawExpandedMascot handles actions", () => {
  const actions = ["idle", "writing", "reading", "thinking", "error", "sleeping"];

  for (const action of actions) {
    const ctx = createMockContext();
    drawExpandedMascot({
      ctx,
      width: 64,
      height: 64,
      action,
      shape: "squircle",
      provider: "claude",
      lookX: 0,
      lookY: 0,
      phase: 0.5
    });
    assert.ok(ctx.operations.length > 5, `operations recorded for ${action}`);
    assert.equal(ctx.operations[0][0], "save");
    assert.equal(ctx.operations[ctx.operations.length - 1][0], "restore");
  }
});
