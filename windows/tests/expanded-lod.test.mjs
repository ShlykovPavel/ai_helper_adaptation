import { test } from "node:test";
import assert from "node:assert/strict";
import {
  harmonicCoreYOffset,
  drawExpandedMascot,
  expandedFaceGeometry,
  expandedActionPropsGeometry
} from "../src/mascot/shapeshifter-expanded.ts";
import { getProviderBadgeColor } from "../src/mascot/shapeshifter-compact.ts";

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
    rect: (...args) => operations.push(["rect", ...args]),
    strokeRect: (...args) => operations.push(["strokeRect", ...args]),
    arc: (...args) => operations.push(["arc", ...args]),
    moveTo: (...args) => operations.push(["moveTo", ...args]),
    lineTo: (...args) => operations.push(["lineTo", ...args]),
    quadraticCurveTo: (...args) => operations.push(["quadraticCurveTo", ...args]),
    bezierCurveTo: (...args) => operations.push(["bezierCurveTo", ...args]),
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

test("Expanded face geometry calculations", () => {
  const rect = { x: 0, y: 0, width: 80, height: 80 };
  const face = expandedFaceGeometry(rect, 0.5, -0.5);

  assert.ok(face.leftEyeCenter.x < face.rightEyeCenter.x, "left eye must be to the left of right eye");
  assert.ok(face.leftSpecularPrimary.x < face.leftEyeCenter.x, "specular primary highlight must be offset left of pupil");
  assert.ok(face.leftCheekCenter.y > face.leftEyeCenter.y, "left cheek must be below left eye");
  assert.ok(face.rightCheekCenter.y > face.rightEyeCenter.y, "right cheek must be below right eye");
  assert.ok(face.mouthCenter.y >= face.leftCheekCenter.y - 2, "mouth must be level with or slightly below cheeks");
  assert.ok(face.mouthCenter.x > face.leftCheekCenter.x && face.mouthCenter.x < face.rightCheekCenter.x, "mouth between cheeks");
});

test("Expanded action props geometry calculations", () => {
  const rect = { x: 0, y: 0, width: 80, height: 80 };

  const writing = expandedActionPropsGeometry(rect, "writing");
  assert.ok(writing.propBounds.width > 0, "writing prop has tablet bounds");
  assert.equal(writing.strokeColorHex, "#64D2FF");
  assert.ok(writing.handLeft.x < writing.handRight.x);

  const reading = expandedActionPropsGeometry(rect, "reading");
  assert.ok(reading.propBounds.width > 0, "reading prop has book bounds");
  assert.equal(reading.strokeColorHex, "#FDE047");

  const thinking = expandedActionPropsGeometry(rect, "thinking");
  assert.ok(thinking.propBounds.width > 0, "thinking prop has swirl bounds");
  assert.equal(thinking.strokeColorHex, "#C084FC");

  const approval = expandedActionPropsGeometry(rect, "approval");
  assert.ok(approval.propBounds.width > 0, "approval prop has shield bounds");
  assert.equal(approval.strokeColorHex, "#30D158");

  const error = expandedActionPropsGeometry(rect, "error");
  assert.ok(error.propBounds.width > 0);
  assert.equal(error.strokeColorHex, "#EF4444");

  const sleeping = expandedActionPropsGeometry(rect, "sleeping");
  assert.ok(sleeping.propBounds.width > 0);
  assert.equal(sleeping.strokeColorHex, "#94A3B8");
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

test("drawExpandedMascot handles all actions and renders face and hands", () => {
  const actions = ["idle", "writing", "reading", "thinking", "approval", "error", "sleeping"];

  for (const action of actions) {
    const ctx = createMockContext();
    drawExpandedMascot({
      ctx,
      width: 80,
      height: 80,
      action,
      shape: "squircle",
      provider: "claude",
      lookX: 0.3,
      lookY: -0.2,
      phase: 0.5
    });
    // With flame crown, body, core, face, eyes, blush, and hands/props, operations count is > 20
    assert.ok(ctx.operations.length > 20, `operations recorded for ${action}: got ${ctx.operations.length}`);
    assert.equal(ctx.operations[0][0], "save");
    assert.equal(ctx.operations[ctx.operations.length - 1][0], "restore");
  }
});
