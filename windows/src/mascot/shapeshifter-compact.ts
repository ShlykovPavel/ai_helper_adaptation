import type { MascotShape, ProviderCoreId } from "./types";

export interface CompactDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  lookX: number;
  lookY: number;
  shape: MascotShape;
  provider: ProviderCoreId;
  isPulsing?: boolean;
}

export function getProviderBadgeColor(provider: ProviderCoreId): string {
  switch (provider) {
    case "claude":      return "#D97757";
    case "gemini":      return "#4E80EE";
    case "openai":      return "#10A37F";
    case "antigravity": return "#8B5CF6";
    default:            return "#64D2FF"; // Astral cyan fallback
  }
}

export function getCompactEyeOffsets(lookX: number, lookY: number, diameter: number): {
  left: { x: number; y: number };
  right: { x: number; y: number };
} {
  const clampedLookX = Math.max(-1.0, Math.min(1.0, lookX));
  const clampedLookY = Math.max(-1.0, Math.min(1.0, lookY));
  const maxOffset = diameter * 0.055;
  const shiftX = clampedLookX * maxOffset;
  const shiftY = -clampedLookY * maxOffset * 0.75;
  const eyeDistance = diameter * 0.18;
  return {
    left: { x: -eyeDistance + shiftX, y: shiftY },
    right: { x: eyeDistance + shiftX, y: shiftY },
  };
}

export function getCompactSpecularOffsets(lookX: number, lookY: number, diameter: number): {
  leftPrimary: { x: number; y: number };
  rightPrimary: { x: number; y: number };
  leftSecondary: { x: number; y: number };
  rightSecondary: { x: number; y: number };
} {
  const eyes = getCompactEyeOffsets(lookX, lookY, diameter);
  const eyeW = Math.max(3.0, diameter * 0.14);
  const eyeH = Math.max(4.5, diameter * 0.24);

  const primOffsetX = -eyeW * 0.24;
  const primOffsetY = -eyeH * 0.24;
  const secOffsetX = eyeW * 0.20;
  const secOffsetY = eyeH * 0.20;

  return {
    leftPrimary: { x: eyes.left.x + primOffsetX, y: eyes.left.y + primOffsetY },
    rightPrimary: { x: eyes.right.x + primOffsetX, y: eyes.right.y + primOffsetY },
    leftSecondary: { x: eyes.left.x + secOffsetX, y: eyes.left.y + secOffsetY },
    rightSecondary: { x: eyes.right.x + secOffsetX, y: eyes.right.y + secOffsetY },
  };
}

export function getCompactCheekOffsets(diameter: number): {
  left: { x: number; y: number };
  right: { x: number; y: number };
  radius: number;
} {
  const cheekDist = diameter * 0.26;
  const cheekY = diameter * 0.14;
  const radius = Math.max(1.5, diameter * 0.08);
  return {
    left: { x: -cheekDist, y: cheekY },
    right: { x: cheekDist, y: cheekY },
    radius,
  };
}

export function drawCompactMascot(opts: CompactDrawOptions): void {
  const { ctx, width, height, lookX, lookY, shape, provider, isPulsing } = opts;
  const side = Math.min(width, height);
  if (side < 8) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const badgeColor = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  const center = { x: side / 2, y: side / 2 };
  const radius = side / 2;

  // 1. Subsurface Glowing Aura & Body Path
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = isPulsing ? 6 : 4;

  const bodyPath = () => {
    ctx.beginPath();
    if (shape === "squircle") {
      const corner = radius * 0.45;
      if (typeof ctx.roundRect === "function") {
        ctx.roundRect(2, 2, side - 4, side - 4, corner);
      } else {
        ctx.rect(2, 2, side - 4, side - 4);
      }
    } else if (shape === "orb") {
      ctx.arc(center.x, center.y, radius - 2, 0, Math.PI * 2);
    } else {
      // flame wisp
      ctx.moveTo(center.x, 2);
      ctx.quadraticCurveTo(side - 2, center.y, center.x, side - 2);
      ctx.quadraticCurveTo(2, center.y, center.x, 2);
    }
  };

  // 2. Translucent Gradient-Filled Spirit Body
  bodyPath();
  if (typeof ctx.createRadialGradient === "function") {
    const lightX = center.x - radius * 0.2;
    const lightY = center.y - radius * 0.2;
    const grad = ctx.createRadialGradient(lightX, lightY, 0, center.x, center.y, radius);
    grad.addColorStop(0, "rgba(240, 248, 255, 0.75)");
    grad.addColorStop(0.55, "rgba(191, 219, 255, 0.45)");
    grad.addColorStop(1, "rgba(140, 190, 255, 0.25)");
    ctx.fillStyle = grad;
  } else {
    ctx.fillStyle = "rgba(240, 248, 255, 0.65)";
  }
  ctx.fill();

  // 3. Ethereal Flame Crown Tuft at Top Center
  ctx.save();
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 3;
  ctx.fillStyle = "rgba(240, 248, 255, 0.85)";
  ctx.beginPath();
  const tuftTip = { x: center.x, y: 0.8 };
  const tuftBaseY = side * 0.24;
  const tuftHalfW = side * 0.10;
  ctx.moveTo(center.x - tuftHalfW, tuftBaseY);
  ctx.quadraticCurveTo(center.x - tuftHalfW * 0.8, 1.2, tuftTip.x, tuftTip.y);
  ctx.quadraticCurveTo(center.x + tuftHalfW * 0.8, 1.2, center.x + tuftHalfW, tuftBaseY);
  if (typeof ctx.closePath === "function") {
    ctx.closePath();
  }
  ctx.fill();
  ctx.restore();

  // 4. Subtle Outer Rim Stroke
  ctx.shadowBlur = 0;
  ctx.strokeStyle = "rgba(255, 255, 255, 0.65)";
  ctx.lineWidth = 1.0;
  bodyPath();
  ctx.stroke();

  // 5. Soft Rosy Blush Cheeks (#FF85A1 at 0.40 alpha)
  const blush = getCompactCheekOffsets(side);
  ctx.fillStyle = "rgba(255, 133, 161, 0.40)";
  const blushW = blush.radius * 2.0;
  const blushH = blush.radius * 1.3;
  ctx.beginPath();
  ctx.ellipse(center.x + blush.left.x, center.y + blush.left.y, blushW / 2, blushH / 2, 0, 0, Math.PI * 2);
  ctx.ellipse(center.x + blush.right.x, center.y + blush.right.y, blushW / 2, blushH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  // 6. Big Glossy Dark Oval Eyes (rgba(20, 26, 41, 0.95))
  const eyeOffsets = getCompactEyeOffsets(lookX, lookY, side);
  const eyeW = Math.max(3.0, side * 0.14);
  const eyeH = Math.max(4.5, side * 0.24);
  ctx.fillStyle = "rgba(20, 26, 41, 0.95)";
  ctx.beginPath();
  ctx.ellipse(center.x + eyeOffsets.left.x, center.y + eyeOffsets.left.y, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.ellipse(center.x + eyeOffsets.right.x, center.y + eyeOffsets.right.y, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  // 7. Specular White Highlight Dots
  const highlights = getCompactSpecularOffsets(lookX, lookY, side);
  const primR = Math.max(0.7, eyeW * 0.25);
  const secR = Math.max(0.4, eyeW * 0.14);

  // Primary highlights
  ctx.fillStyle = "rgba(255, 255, 255, 0.95)";
  ctx.beginPath();
  ctx.arc(center.x + highlights.leftPrimary.x, center.y + highlights.leftPrimary.y, primR, 0, Math.PI * 2);
  ctx.arc(center.x + highlights.rightPrimary.x, center.y + highlights.rightPrimary.y, primR, 0, Math.PI * 2);
  ctx.fill();

  // Secondary highlights
  ctx.fillStyle = "rgba(255, 255, 255, 0.70)";
  ctx.beginPath();
  ctx.arc(center.x + highlights.leftSecondary.x, center.y + highlights.leftSecondary.y, secR, 0, Math.PI * 2);
  ctx.arc(center.x + highlights.rightSecondary.x, center.y + highlights.rightSecondary.y, secR, 0, Math.PI * 2);
  ctx.fill();

  // 8. Micro Provider Jewel Badge
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 2.5;
  ctx.fillStyle = badgeColor;
  const badgeSize = Math.max(3.5, side * 0.16);
  ctx.beginPath();
  ctx.arc(side - badgeSize / 2 - 1, badgeSize / 2 + 1, badgeSize / 2, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}
