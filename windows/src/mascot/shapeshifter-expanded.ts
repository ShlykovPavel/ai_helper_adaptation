import type { MascotActionState, MascotShape, ProviderCoreId } from "./types";
import { getProviderBadgeColor } from "./shapeshifter-compact";

export interface ExpandedDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  action: MascotActionState;
  shape: MascotShape;
  provider: ProviderCoreId;
  lookX: number;
  lookY: number;
  phase: number;
}

export interface ExpandedFaceGeometry {
  leftEyeCenter: { x: number; y: number };
  rightEyeCenter: { x: number; y: number };
  eyeSize: { width: number; height: number };
  leftSpecularPrimary: { x: number; y: number };
  rightSpecularPrimary: { x: number; y: number };
  leftSpecularSecondary: { x: number; y: number };
  rightSpecularSecondary: { x: number; y: number };
  leftCheekCenter: { x: number; y: number };
  rightCheekCenter: { x: number; y: number };
  cheekSize: { width: number; height: number };
  mouthCenter: { x: number; y: number };
  mouthWidth: number;
}

export interface ExpandedActionPropsGeometry {
  propBounds: { x: number; y: number; width: number; height: number };
  primaryAnchor: { x: number; y: number };
  secondaryAnchor: { x: number; y: number };
  strokeColorHex: string;
  handLeft: { x: number; y: number };
  handRight: { x: number; y: number };
}

export function harmonicCoreYOffset(phase: number, amplitude = 2.5): number {
  return Math.sin(phase * Math.PI * 2) * amplitude;
}

export function expandedFaceGeometry(
  rect: { x: number; y: number; width: number; height: number },
  lookX: number,
  lookY: number
): ExpandedFaceGeometry {
  const centerX = rect.x + rect.width / 2;
  const centerY = rect.y + rect.height / 2;
  const diameter = Math.min(rect.width, rect.height);

  const clampedLookX = Math.max(-1.0, Math.min(1.0, lookX));
  const clampedLookY = Math.max(-1.0, Math.min(1.0, lookY));
  const maxShift = diameter * 0.055;
  const shiftX = clampedLookX * maxShift;
  const shiftY = -clampedLookY * maxShift * 0.75;

  const eyeDistance = diameter * 0.18;
  const faceCenterY = centerY - diameter * 0.03;
  const leftEye = { x: centerX - eyeDistance + shiftX, y: faceCenterY + shiftY };
  const rightEye = { x: centerX + eyeDistance + shiftX, y: faceCenterY + shiftY };

  const eyeW = Math.max(5.0, diameter * 0.13);
  const eyeH = Math.max(7.0, diameter * 0.20);
  const eyeSize = { width: eyeW, height: eyeH };

  const primOffsetX = -eyeW * 0.24;
  const primOffsetY = -eyeH * 0.24;
  const secOffsetX = eyeW * 0.20;
  const secOffsetY = eyeH * 0.20;

  const leftSpecularPrimary = { x: leftEye.x + primOffsetX, y: leftEye.y + primOffsetY };
  const rightSpecularPrimary = { x: rightEye.x + primOffsetX, y: rightEye.y + primOffsetY };
  const leftSpecularSecondary = { x: leftEye.x + secOffsetX, y: leftEye.y + secOffsetY };
  const rightSpecularSecondary = { x: rightEye.x + secOffsetX, y: rightEye.y + secOffsetY };

  const cheekDist = diameter * 0.26;
  const cheekYOffset = diameter * 0.14;
  const leftCheek = { x: centerX - cheekDist + shiftX * 0.4, y: leftEye.y + cheekYOffset };
  const rightCheek = { x: centerX + cheekDist + shiftX * 0.4, y: rightEye.y + cheekYOffset };
  const cheekSize = { width: Math.max(4.0, diameter * 0.14), height: Math.max(2.5, diameter * 0.09) };

  const mouthCenter = { x: centerX + shiftX * 0.5, y: leftCheek.y + 1.0 };
  const mouthWidth = Math.max(4.0, diameter * 0.10);

  return {
    leftEyeCenter: leftEye,
    rightEyeCenter: rightEye,
    eyeSize,
    leftSpecularPrimary,
    rightSpecularPrimary,
    leftSpecularSecondary,
    rightSpecularSecondary,
    leftCheekCenter: leftCheek,
    rightCheekCenter: rightCheek,
    cheekSize,
    mouthCenter,
    mouthWidth
  };
}

export function expandedActionPropsGeometry(
  rect: { x: number; y: number; width: number; height: number },
  action: MascotActionState
): ExpandedActionPropsGeometry {
  const centerX = rect.x + rect.width / 2;
  const centerY = rect.y + rect.height / 2;
  const diameter = Math.min(rect.width, rect.height);
  const maxY = rect.y + rect.height;
  const minY = rect.y;

  switch (action) {
    case "writing": {
      const tabletW = Math.max(20.0, diameter * 0.32);
      const tabletH = Math.max(12.0, diameter * 0.18);
      const tabletRect = { x: centerX - tabletW / 2, y: maxY - tabletH - diameter * 0.04, width: tabletW, height: tabletH };
      return {
        propBounds: tabletRect,
        primaryAnchor: { x: tabletRect.x + tabletRect.width - 4, y: tabletRect.y - 5 },
        secondaryAnchor: { x: tabletRect.x + tabletRect.width - 9, y: tabletRect.y + tabletRect.height / 2 },
        strokeColorHex: "#64D2FF",
        handLeft: { x: tabletRect.x + 3, y: tabletRect.y + tabletRect.height / 2 },
        handRight: { x: tabletRect.x + tabletRect.width - 5, y: tabletRect.y }
      };
    }
    case "reading": {
      const bookW = Math.max(24.0, diameter * 0.36);
      const bookH = Math.max(12.0, diameter * 0.18);
      const bookY = maxY - bookH - diameter * 0.04;
      const bookRect = { x: centerX - bookW / 2, y: bookY, width: bookW, height: bookH };
      return {
        propBounds: bookRect,
        primaryAnchor: { x: centerX, y: bookY },
        secondaryAnchor: { x: centerX, y: bookY + bookH },
        strokeColorHex: "#FDE047",
        handLeft: { x: bookRect.x + 2, y: bookY + bookH * 0.5 },
        handRight: { x: bookRect.x + bookRect.width - 2, y: bookY + bookH * 0.5 }
      };
    }
    case "thinking": {
      const swirlSize = Math.max(10.0, diameter * 0.18);
      const swirlRect = { x: centerX + diameter * 0.12, y: minY + diameter * 0.08, width: swirlSize, height: swirlSize };
      return {
        propBounds: swirlRect,
        primaryAnchor: { x: swirlRect.x + swirlSize / 2, y: swirlRect.y + swirlSize / 2 },
        secondaryAnchor: { x: centerX + diameter * 0.06, y: centerY + diameter * 0.16 },
        strokeColorHex: "#C084FC",
        handLeft: { x: centerX - diameter * 0.18, y: centerY + diameter * 0.16 },
        handRight: { x: centerX + diameter * 0.06, y: centerY + diameter * 0.16 }
      };
    }
    case "approval": {
      const shieldW = Math.max(14.0, diameter * 0.22);
      const shieldH = Math.max(16.0, diameter * 0.24);
      const shieldRect = { x: centerX + diameter * 0.10, y: maxY - shieldH - diameter * 0.06, width: shieldW, height: shieldH };
      return {
        propBounds: shieldRect,
        primaryAnchor: { x: shieldRect.x + shieldW / 2, y: shieldRect.y },
        secondaryAnchor: { x: shieldRect.x + shieldW / 2, y: shieldRect.y + shieldH },
        strokeColorHex: "#30D158",
        handLeft: { x: centerX - diameter * 0.18, y: centerY + diameter * 0.18 },
        handRight: { x: centerX + diameter * 0.12, y: maxY - shieldH * 0.6 }
      };
    }
    case "error": {
      const sparkSize = Math.max(12.0, diameter * 0.18);
      const sparkRect = { x: centerX - sparkSize / 2, y: minY + diameter * 0.06, width: sparkSize, height: sparkSize };
      return {
        propBounds: sparkRect,
        primaryAnchor: { x: sparkRect.x, y: sparkRect.y },
        secondaryAnchor: { x: sparkRect.x + sparkSize, y: sparkRect.y + sparkSize },
        strokeColorHex: "#EF4444",
        handLeft: { x: centerX - diameter * 0.22, y: centerY + diameter * 0.12 },
        handRight: { x: centerX + diameter * 0.22, y: centerY + diameter * 0.12 }
      };
    }
    case "sleeping": {
      const zSize = Math.max(12.0, diameter * 0.18);
      const zRect = { x: rect.x + rect.width - zSize - diameter * 0.05, y: minY + diameter * 0.06, width: zSize, height: zSize };
      return {
        propBounds: zRect,
        primaryAnchor: { x: zRect.x, y: zRect.y },
        secondaryAnchor: { x: zRect.x + zSize, y: zRect.y + zSize },
        strokeColorHex: "#94A3B8",
        handLeft: { x: centerX - diameter * 0.08, y: centerY + diameter * 0.20 },
        handRight: { x: centerX + diameter * 0.08, y: centerY + diameter * 0.20 }
      };
    }
    case "idle":
    default: {
      return {
        propBounds: { x: 0, y: 0, width: 0, height: 0 },
        primaryAnchor: { x: centerX, y: centerY },
        secondaryAnchor: { x: centerX, y: centerY },
        strokeColorHex: "#64D2FF",
        handLeft: { x: centerX - diameter * 0.20, y: centerY + diameter * 0.18 },
        handRight: { x: centerX + diameter * 0.20, y: centerY + diameter * 0.18 }
      };
    }
  }
}

export function drawExpandedMascot(opts: ExpandedDrawOptions): void {
  const { ctx, width, height, action, shape, provider, lookX = 0, lookY = 0, phase = 0 } = opts;
  const side = Math.min(width, height);
  if (side < 16) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const tint = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  // 1. Top Flickering Flame Crown Tuft
  ctx.save();
  ctx.shadowColor = tint;
  ctx.shadowBlur = 5;
  ctx.fillStyle = "rgba(240, 248, 255, 0.85)";
  const r = side / 2;
  const tuftBaseY = side * 0.24;
  const tuftHalfW = side * 0.11;
  ctx.beginPath();
  ctx.moveTo(r - tuftHalfW, tuftBaseY);
  ctx.quadraticCurveTo(r - tuftHalfW * 0.85, side * 0.14, r - tuftHalfW * 0.3, side * 0.09);
  ctx.quadraticCurveTo(r - tuftHalfW * 0.15, 3.0, r, 2.0);
  ctx.quadraticCurveTo(r + tuftHalfW * 0.15, 3.0, r + tuftHalfW * 0.3, side * 0.09);
  ctx.quadraticCurveTo(r + tuftHalfW * 0.85, side * 0.14, r + tuftHalfW, tuftBaseY);
  if (typeof ctx.closePath === "function") ctx.closePath();
  ctx.fill();
  ctx.restore();

  // 2. Glassmorphic Body Fill & Rim Stroke
  ctx.shadowColor = tint;
  ctx.shadowBlur = 12;
  ctx.fillStyle = "rgba(220, 235, 255, 0.25)";
  ctx.strokeStyle = "rgba(255, 255, 255, 0.7)";
  ctx.lineWidth = 1.8;

  ctx.beginPath();
  if (shape === "squircle") {
    if (typeof ctx.roundRect === "function") {
      ctx.roundRect(4, 4, side - 8, side - 8, r * 0.48);
    } else {
      ctx.rect(4, 4, side - 8, side - 8);
    }
  } else if (shape === "orb") {
    ctx.arc(r, r, r - 4, 0, Math.PI * 2);
  } else {
    // flameWisp
    ctx.moveTo(r, 4);
    ctx.quadraticCurveTo(side - 4, r, r, side - 4);
    ctx.quadraticCurveTo(4, r, r, 4);
  }
  ctx.fill();
  ctx.stroke();

  // 3. Floating AI Core with Harmonic Oscillation
  const yFloat = harmonicCoreYOffset(phase, 2.5);
  ctx.shadowColor = tint;
  ctx.shadowBlur = 8;
  ctx.fillStyle = tint;
  ctx.beginPath();
  ctx.arc(r, r + 4 + yFloat, 7, 0, Math.PI * 2);
  ctx.fill();

  // 4. Expressive Character Face
  ctx.shadowBlur = 0;
  const face = expandedFaceGeometry({ x: 0, y: 0, width: side, height: side }, lookX, lookY);

  // Soft Rosy Blush Cheeks (#FF85A1 at 0.45 alpha)
  ctx.fillStyle = "rgba(255, 133, 161, 0.45)";
  ctx.beginPath();
  ctx.arc(face.leftCheekCenter.x, face.leftCheekCenter.y, face.cheekSize.width / 2, 0, Math.PI * 2);
  ctx.arc(face.rightCheekCenter.x, face.rightCheekCenter.y, face.cheekSize.width / 2, 0, Math.PI * 2);
  ctx.fill();

  // Eyes
  const eyeColor = "rgba(20, 26, 46, 0.95)";
  if (action === "sleeping") {
    ctx.strokeStyle = eyeColor;
    ctx.lineWidth = Math.max(2.0, face.eyeSize.width * 0.22);
    ctx.beginPath();
    ctx.arc(face.leftEyeCenter.x, face.leftEyeCenter.y - face.eyeSize.height * 0.05, face.eyeSize.width * 0.5, 0.2, Math.PI - 0.2);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(face.rightEyeCenter.x, face.rightEyeCenter.y - face.eyeSize.height * 0.05, face.eyeSize.width * 0.5, 0.2, Math.PI - 0.2);
    ctx.stroke();
  } else {
    // Big dark glossy oval eyes
    ctx.fillStyle = eyeColor;
    ctx.beginPath();
    ctx.arc(face.leftEyeCenter.x, face.leftEyeCenter.y, face.eyeSize.width / 2, 0, Math.PI * 2);
    ctx.arc(face.rightEyeCenter.x, face.rightEyeCenter.y, face.eyeSize.width / 2, 0, Math.PI * 2);
    ctx.fill();

    // Primary bright white specular highlights
    const primR = Math.max(1.2, face.eyeSize.width * 0.25);
    ctx.fillStyle = "rgba(255, 255, 255, 0.95)";
    ctx.beginPath();
    ctx.arc(face.leftSpecularPrimary.x, face.leftSpecularPrimary.y, primR, 0, Math.PI * 2);
    ctx.arc(face.rightSpecularPrimary.x, face.rightSpecularPrimary.y, primR, 0, Math.PI * 2);
    ctx.fill();

    // Secondary micro-dots
    const secR = Math.max(0.6, face.eyeSize.width * 0.13);
    ctx.fillStyle = "rgba(255, 255, 255, 0.70)";
    ctx.beginPath();
    ctx.arc(face.leftSpecularSecondary.x, face.leftSpecularSecondary.y, secR, 0, Math.PI * 2);
    ctx.arc(face.rightSpecularSecondary.x, face.rightSpecularSecondary.y, secR, 0, Math.PI * 2);
    ctx.fill();
  }

  // Mouth Arc tailored to action
  ctx.strokeStyle = "rgba(30, 36, 56, 0.85)";
  ctx.lineWidth = Math.max(1.4, face.mouthWidth * 0.20);
  ctx.beginPath();
  const mw = face.mouthWidth;
  const mc = face.mouthCenter;
  if (action === "reading" || action === "thinking") {
    ctx.arc(mc.x, mc.y, mw * 0.25, 0, Math.PI * 2);
  } else if (action === "error") {
    ctx.moveTo(mc.x - mw * 0.5, mc.y);
    if (typeof ctx.bezierCurveTo === "function") {
      ctx.bezierCurveTo(mc.x - mw * 0.2, mc.y - 2, mc.x + mw * 0.2, mc.y + 2, mc.x + mw * 0.5, mc.y);
    } else {
      ctx.lineTo(mc.x + mw * 0.5, mc.y);
    }
  } else {
    // smile arc
    ctx.moveTo(mc.x - mw * 0.5, mc.y - 0.5);
    ctx.quadraticCurveTo(mc.x, mc.y + mw * 0.45, mc.x + mw * 0.5, mc.y - 0.5);
  }
  ctx.stroke();

  // 5. Cute Stubby Hands & Action Props
  const props = expandedActionPropsGeometry({ x: 0, y: 0, width: side, height: side }, action);
  ctx.lineWidth = 1.5;

  if (action === "writing") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.strokeRect(props.propBounds.x, props.propBounds.y, props.propBounds.width, props.propBounds.height);
    ctx.beginPath();
    ctx.moveTo(props.primaryAnchor.x, props.primaryAnchor.y);
    ctx.lineTo(props.secondaryAnchor.x, props.secondaryAnchor.y);
    ctx.stroke();
  } else if (action === "reading") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.beginPath();
    ctx.moveTo(props.propBounds.x, props.propBounds.y);
    ctx.lineTo(r, props.propBounds.y + 2);
    ctx.lineTo(props.propBounds.x + props.propBounds.width, props.propBounds.y);
    ctx.moveTo(r, props.propBounds.y + 2);
    ctx.lineTo(r, props.propBounds.y + props.propBounds.height);
    ctx.stroke();
  } else if (action === "thinking") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.beginPath();
    ctx.arc(props.primaryAnchor.x, props.primaryAnchor.y, props.propBounds.width * 0.4, 0, Math.PI * 1.5);
    ctx.stroke();
  } else if (action === "approval") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.strokeRect(props.propBounds.x, props.propBounds.y, props.propBounds.width, props.propBounds.height);
  } else if (action === "error") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.beginPath();
    ctx.moveTo(props.primaryAnchor.x, props.primaryAnchor.y);
    ctx.lineTo(props.secondaryAnchor.x, props.secondaryAnchor.y);
    ctx.moveTo(props.secondaryAnchor.x, props.primaryAnchor.y);
    ctx.lineTo(props.primaryAnchor.x, props.secondaryAnchor.y);
    ctx.stroke();
  } else if (action === "sleeping") {
    ctx.strokeStyle = props.strokeColorHex;
    ctx.beginPath();
    ctx.moveTo(props.primaryAnchor.x, props.primaryAnchor.y);
    ctx.lineTo(props.secondaryAnchor.x, props.primaryAnchor.y);
    ctx.lineTo(props.primaryAnchor.x, props.secondaryAnchor.y);
    ctx.lineTo(props.secondaryAnchor.x, props.secondaryAnchor.y);
    ctx.stroke();
  }

  // Draw cute translucent spirit paws/hands
  const handR = Math.max(3.0, side * 0.055);
  ctx.fillStyle = "rgba(240, 248, 255, 0.85)";
  ctx.strokeStyle = "rgba(255, 255, 255, 0.60)";
  ctx.lineWidth = 1.0;
  ctx.beginPath();
  ctx.arc(props.handLeft.x, props.handLeft.y, handR, 0, Math.PI * 2);
  ctx.arc(props.handRight.x, props.handRight.y, handR, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  ctx.restore();
}
