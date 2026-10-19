export const DURATION = 4000;
export const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
const smooth = v => { const t = clamp(v); return t ** 3 * (t * (6 * t - 15) + 10); };
const mix = (a, b, t) => a + (b - a) * t;

export function poseAt(milliseconds) {
  const t = clamp(milliseconds, 0, DURATION);
  const idle = -125, raised = -6;
  let angle = idle;
  let phase = 'Появление';
  if (t >= 650 && t < 1200) {
    angle = mix(idle, raised, smooth((t - 650) / 550));
    phase = 'Поднимает лапку';
  } else if (t >= 1200 && t < 2500) {
    const progress = (t - 1200) / (1300 / 3);
    const cycle = Math.min(2, Math.floor(progress));
    const swing = (1 - Math.cos(2 * Math.PI * (progress - cycle))) / 2;
    angle = raised - [35, 30, 25][cycle] * swing;
    phase = `Взмах ${cycle + 1} из 3`;
  } else if (t >= 2500 && t < 3450) {
    angle = mix(raised, idle, smooth((t - 2500) / 950));
    phase = 'Мягко опускает лапку';
  } else if (t >= 3450) {
    phase = 'Спокойная поза';
  }
  return { angle, opacity: smooth(t / 400), phase };
}

export function geometry(meta) {
  const b = meta.body, p = meta.paw;
  const bodyScale = 300 / (b.crop[3] - b.crop[1]);
  const body = {
    x: 193 - (b.headCenterX - b.crop[0]) * bodyScale,
    y: 42,
    width: (b.crop[2] - b.crop[0]) * bodyScale,
    height: 300
  };
  const pawScale = 90 / (p.crop[3] - p.crop[1]);
  return { body,
    joint: [body.x + (b.shoulder[0] - b.crop[0]) * bodyScale,
            body.y + (b.shoulder[1] - b.crop[1]) * bodyScale],
    paw: { x: -(p.pivot[0] - p.crop[0]) * pawScale,
           y: -(p.pivot[1] - p.crop[1]) * pawScale,
           width: (p.crop[2] - p.crop[0]) * pawScale,
           height: 90 }
  };
}

export function paint(ctx, bodyImage, pawImage, meta, t, size, pixelRatio = 1) {
  const g = geometry(meta), pose = poseAt(t);
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  const scale = size * pixelRatio / 384;
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.globalAlpha = pose.opacity;
  const draw = (im, crop, rect) => ctx.drawImage(im, crop[0], crop[1], crop[2] - crop[0], crop[3] - crop[1], rect.x, rect.y, rect.width, rect.height);
  draw(bodyImage, meta.body.crop, g.body);
  ctx.save();
  ctx.translate(...g.joint);
  ctx.rotate(pose.angle * Math.PI / 180);
  draw(pawImage, meta.paw.crop, g.paw);
  ctx.restore();
  ctx.globalAlpha = 1;
}
