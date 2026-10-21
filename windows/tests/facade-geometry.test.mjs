import { test } from "node:test";
import assert from "node:assert/strict";
import { botPosition } from "../src/core/layout.ts";
import {
  mapActionFromBotState,
  getMascotBodyBounds,
  renderMascotFacade,
} from "../src/mascot/shapeshifter-host.ts";
import { MascotSettingsManager } from "../src/mascot/settings.ts";

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
    strokeRect: (...args) => operations.push(["strokeRect", ...args]),
    fillRect: (...args) => operations.push(["fillRect", ...args]),
    roundRect: (...args) => operations.push(["roundRect", ...args]),
    arc: (...args) => operations.push(["arc", ...args]),
    moveTo: (...args) => operations.push(["moveTo", ...args]),
    quadraticCurveTo: (...args) => operations.push(["quadraticCurveTo", ...args]),
    ellipse: (...args) => operations.push(["ellipse", ...args]),
    createRadialGradient: () => ({ addColorStop: () => {} }),
    strokeStyle: "",
    fillStyle: "",
    lineWidth: 1,
    shadowColor: "",
    shadowBlur: 0,
  };
}

test("R11: BotState to MascotActionState mapping handles approval and all states", () => {
  // R11 bugfix: real BotState.approval must map to "approval", not "idle"
  assert.equal(mapActionFromBotState("approval"), "approval", "approval must map to approval");
  assert.equal(mapActionFromBotState("permission"), "approval", "permission must map to approval");
  assert.equal(mapActionFromBotState("question"), "approval", "question must map to approval");

  assert.equal(mapActionFromBotState("working"), "writing");
  assert.equal(mapActionFromBotState("searching"), "reading");
  assert.equal(mapActionFromBotState("thinking"), "thinking");
  assert.equal(mapActionFromBotState("error"), "error");
  assert.equal(mapActionFromBotState("ratelimit"), "error");
  assert.equal(mapActionFromBotState("dizzy"), "error");
  assert.equal(mapActionFromBotState("sleeping"), "sleeping");
  assert.equal(mapActionFromBotState("idle"), "idle");
  assert.equal(mapActionFromBotState("finished"), "idle");
});

test("R10: Compact island mascot bounds align with [6, 26] and do not clip at top", () => {
  const BOT_OVERHANG = 40;
  const BOT_SIDE = 30;

  // Compact layout: cx = 40, cy = 16, diameter = 20
  const placement = botPosition("compact", "overview", 32);
  assert.equal(placement.cx, 40);
  assert.equal(placement.cy, 16);
  assert.equal(placement.diameter, 20);

  // Island engine target size: diameter / 0.6
  const targetBotSize = placement.diameter / 0.6; // 33.333...
  const w = Math.round(targetBotSize); // 33
  const hCss = w + BOT_OVERHANG; // 73
  const wCss = w + BOT_SIDE * 2; // 93

  // Canvas style positioning from island.ts:1059-1060
  const canvasLeft = placement.cx - wCss / 2;
  const canvasTop = placement.cy - BOT_OVERHANG / 2 - hCss / 2;

  // Facade body geometry
  const geom = {
    overhang: BOT_OVERHANG,
    diameter: placement.diameter,
    lookX: 0,
    lookY: 0,
  };
  const bounds = getMascotBodyBounds(w, hCss, geom);

  assert.equal(bounds.width, 20, "Mascot body diameter matches target 20");
  assert.equal(bounds.height, 20, "Mascot body diameter matches target 20");

  // Screen-space coordinates: canvasTop + bounds.y
  const screenBodyTop = canvasTop + bounds.y;
  const screenBodyBottom = screenBodyTop + bounds.height;
  const screenBodyCenterY = (screenBodyTop + screenBodyBottom) / 2;

  assert.equal(screenBodyTop, 6, "Expected top bound of body is 6");
  assert.equal(screenBodyBottom, 26, "Expected bottom bound of body is 26");
  assert.equal(screenBodyCenterY, 16, "Mascot body is vertically centered at botCy = 16");

  // Horizontal screen-space coordinates: canvasLeft + BOT_SIDE + bounds.x
  const screenBodyLeft = canvasLeft + BOT_SIDE + bounds.x;
  const screenBodyRight = screenBodyLeft + bounds.width;
  const screenBodyCenterX = (screenBodyLeft + screenBodyRight) / 2;

  assert.equal(screenBodyLeft, 30);
  assert.equal(screenBodyRight, 50);
  assert.equal(screenBodyCenterX, 40, "Mascot body is horizontally centered at botCx = 40");
});

test("R10: Expanded island mascot bounds align with botCy and target diameter", () => {
  const BOT_OVERHANG = 40;
  const BOT_SIDE = 30;

  // Expanded overview: botDiameter = 58
  const placement = botPosition("expanded", "overview", 160);
  const targetBotSize = placement.diameter / 0.6;
  const w = Math.round(targetBotSize);
  const hCss = w + BOT_OVERHANG;
  const wCss = w + BOT_SIDE * 2;

  const canvasTop = placement.cy - BOT_OVERHANG / 2 - hCss / 2;
  const bounds = getMascotBodyBounds(w, hCss, {
    overhang: BOT_OVERHANG,
    diameter: placement.diameter,
  });

  assert.equal(bounds.width, placement.diameter);
  const screenBodyCenterY = canvasTop + bounds.y + bounds.height / 2;
  assert.equal(screenBodyCenterY, placement.cy, "Mascot center matches botCy in expanded mode");
});

test("R10: Dynamic resizing preserves centering at botCy", () => {
  const BOT_OVERHANG = 40;
  // Test intermediate interpolation values between 20 and 58
  for (let diam = 20; diam <= 58; diam += 5) {
    const cy = 50;
    const w = Math.round(diam / 0.6);
    const hCss = w + BOT_OVERHANG;
    const canvasTop = cy - BOT_OVERHANG / 2 - hCss / 2;
    const bounds = getMascotBodyBounds(w, hCss, { overhang: BOT_OVERHANG, diameter: diam });
    const screenCenterY = canvasTop + bounds.y + bounds.height / 2;
    assert.ok(Math.abs(screenCenterY - cy) <= 0.5, `Resizing diameter ${diam} preserves center`);
  }
});

test("R10 & R11: renderMascotFacade renders compact and expanded without clipping", () => {
  MascotSettingsManager.setSelectedMascot("shapeshifter");

  // Compact test
  const ctxCompact = createMockContext();
  const compactRendered = renderMascotFacade(
    ctxCompact,
    33,
    73,
    { mode: "compact", effectiveState: "approval", focusTask: null },
    0.5,
    { overhang: 40, diameter: 20 }
  );
  assert.ok(compactRendered, "renderMascotFacade returns true when shapeshifter selected");

  const compactTranslate = ctxCompact.operations.find((op) => op[0] === "translate");
  assert.ok(compactTranslate, "Context translate is called once");
  // bounds.x = 33/2 - 10 = 6.5
  // bounds.y = (73 + 40)/2 - 10 = 46.5
  assert.equal(compactTranslate[1], 6.5);
  assert.equal(compactTranslate[2], 46.5);

  // Expanded test with approval state
  const ctxExpanded = createMockContext();
  const expandedRendered = renderMascotFacade(
    ctxExpanded,
    97,
    137,
    { mode: "expanded", effectiveState: "approval", focusTask: null },
    0.5,
    { overhang: 40, diameter: 58 }
  );
  assert.ok(expandedRendered);

  const expandedTranslate = ctxExpanded.operations.find((op) => op[0] === "translate");
  assert.ok(expandedTranslate);
  assert.equal(expandedTranslate[1], 19.5);
  assert.equal(expandedTranslate[2], 59.5);
});
