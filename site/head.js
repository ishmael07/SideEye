// A lit 3D head for the camera preview, drawn on a 2D canvas.
// The face is MediaPipe's canonical face model (the geometry face trackers fit to real
// people); hair, ears, neck and shoulders are built around it. Flat-shaded triangles with
// smoothed normals, depth-sorted, no WebGL.
import { VERTICES, TRIANGLES } from "./face-model.js";

const EYES = [[33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
              [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466]];
const BROWS = [[46, 53, 52, 65, 55], [276, 283, 282, 295, 285]];
const LIPS = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185];
const PIVOT = [0, -1.5, -4.5], CAMERA = 58, LIGHT = [-0.36, 0.46, 0.81], FACE_COUNT = VERTICES.length / 3;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const tone = (rgb, light) => `rgb(${rgb.map(c => Math.round(clamp(c * light, 0, 255))).join(",")})`;

// ---- geometry: the face, plus a hair cap on an ellipsoid around the skull ----
const SKULL = { c: [0, 1.6, -2.4], r: [7.9, 9.7, 9.4] }, HAIR = { c: [0, 1.9, -2.6], r: [8.5, 10.3, 10.1] };
const model = Array.from(VERTICES, v => v / 100), tris = Array.from(TRIANGLES), material = new Array(TRIANGLES.length / 3).fill(0);
(function growHair() {
  const columns = 40, rings = 12, first = model.length / 3;
  for (let c = 0; c < columns; c++) {
    const phi = c / columns * Math.PI * 2, fromFront = Math.abs(Math.atan2(Math.sin(phi), Math.cos(phi))) * 180 / Math.PI;   // 0° = forehead, 180° = nape
    // Where the hair stops: a hairline over the forehead, down past the ears at the sides, to the nape at the back.
    const edge = fromFront < 38 ? 6.5 - 0.5 * Math.cos(fromFront / 38 * Math.PI) : fromFront < 80 ? 7 - (fromFront - 38) / 42 * 8.4 : -1.4 - Math.min(1, (fromFront - 80) / 50) * 4.2;
    const stop = Math.acos(clamp((edge - HAIR.c[1]) / HAIR.r[1], -1, 1));
    for (let r = 0; r <= rings; r++) {
      const theta = stop * r / rings, lift = 1 + 0.05 * Math.sin(theta) * Math.max(0, Math.cos(phi)) + 0.018 * Math.sin(phi * 9 + theta * 5);   // a little volume and texture
      model.push(HAIR.c[0] + HAIR.r[0] * Math.sin(theta) * Math.sin(phi) * lift, HAIR.c[1] + HAIR.r[1] * Math.cos(theta) * lift, HAIR.c[2] + HAIR.r[2] * Math.sin(theta) * Math.cos(phi) * lift);
    }
  }
  for (let c = 0; c < columns; c++) for (let r = 0; r < rings; r++) {
    const a = first + c * (rings + 1) + r, b = first + ((c + 1) % columns) * (rings + 1) + r;
    tris.push(a, a + 1, b + 1, a, b + 1, b); material.push(1, 1);
  }
})();
const COUNT = model.length / 3, TRI_COUNT = tris.length / 3;
const px = new Float32Array(COUNT), py = new Float32Array(COUNT), wx = new Float32Array(COUNT), wy = new Float32Array(COUNT), wz = new Float32Array(COUNT);
const nx = new Float32Array(COUNT), ny = new Float32Array(COUNT), nz = new Float32Array(COUNT);
const order = Array.from({ length: TRI_COUNT }, (_, i) => i), depth = new Float32Array(TRI_COUNT), front = new Int8Array(TRI_COUNT);
let faceWinding = 0;

function place(p, x, y, z) {               // model space (cm) → rotated world space
  x -= PIVOT[0]; y -= PIVOT[1]; z -= PIVOT[2];
  const x1 = x * p.cr - y * p.sr, y1 = x * p.sr + y * p.cr;              // roll
  const y2 = y1 * p.cp - z * p.sp, z2 = y1 * p.sp + z * p.cp;            // pitch (positive looks down)
  return [x1 * p.cy + z2 * p.sy + PIVOT[0], y2 + PIVOT[1], -x1 * p.sy + z2 * p.cy + PIVOT[2]];   // yaw
}
const flat = (p, v) => { const k = p.scale * CAMERA / (CAMERA - v[2]); return [p.x + v[0] * k, p.y - v[1] * k]; };
const signedArea = t => { const a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2]; return (px[b] - px[a]) * (py[c] - py[a]) - (px[c] - px[a]) * (py[b] - py[a]); };

/**
 * Draws one person and returns the face's bounding box [x, y, w, h] in canvas pixels.
 * person: { x, y, scale (px per cm), yaw, pitch, roll (degrees; yaw > 0 = turned to their left, shown mirrored
 * like a selfie view), gazeX, gazeY (-1…1), blink (0|1), breath (px), dim (0…1), skin, hair, shirt ([r,g,b]) }
 */
export function drawHead(ctx, person) {
  const rad = Math.PI / 180, { scale, dim, skin, hair, shirt } = person;
  const p = Object.assign(person, { cr: Math.cos(person.roll * rad), sr: Math.sin(person.roll * rad), cp: Math.cos(person.pitch * rad), sp: Math.sin(person.pitch * rad), cy: Math.cos(-person.yaw * rad), sy: Math.sin(-person.yaw * rad) });
  for (let i = 0; i < COUNT; i++) {
    const v = place(p, model[i * 3], model[i * 3 + 1], model[i * 3 + 2]);
    wx[i] = v[0]; wy[i] = v[1]; wz[i] = v[2]; [px[i], py[i]] = flat(p, v);
  }

  // Behind the face: shoulders, neck, the skull, and the ears.
  const chest = flat(p, [0, -25, -6]), neckTop = flat(p, place(p, 0, -7.5, -4)), neckHalf = 4.9 * scale;
  const cloth = ctx.createLinearGradient(0, chest[1] - 13 * scale, 0, chest[1] + 8 * scale);
  cloth.addColorStop(0, tone(shirt, 1.15 * dim)); cloth.addColorStop(1, tone(shirt, 0.6 * dim));
  ctx.fillStyle = cloth; ctx.beginPath(); ctx.ellipse(chest[0] - person.yaw * 0.04 * scale, chest[1] + person.breath, 25 * scale, 14 * scale, 0, 0, 6.283); ctx.fill();
  const neck = ctx.createLinearGradient(neckTop[0] - neckHalf, 0, neckTop[0] + neckHalf, 0);
  neck.addColorStop(0, tone(skin, 0.66 * dim)); neck.addColorStop(0.45, tone(skin, 0.52 * dim)); neck.addColorStop(1, tone(skin, 0.32 * dim));
  ctx.fillStyle = neck; ctx.beginPath(); ctx.roundRect(neckTop[0] - neckHalf, neckTop[1], neckHalf * 2, chest[1] - 10 * scale - neckTop[1] + person.breath, neckHalf * 0.5); ctx.fill();
  const skull = flat(p, place(p, ...SKULL.c)), rx = Math.hypot(SKULL.r[0] * p.cy, SKULL.r[2] * p.sy) * scale, ry = SKULL.r[1] * scale;
  ctx.fillStyle = tone(skin, 0.6 * dim); ctx.beginPath(); ctx.ellipse(skull[0], skull[1], rx, ry, -person.roll * rad, 0, 6.283); ctx.fill();
  for (const side of [-1, 1]) {
    const ear = place(p, side * 7.7, -0.6, -3.2); if (ear[2] < -9) continue;
    const at = flat(p, ear); ctx.fillStyle = tone(skin, 0.74 * dim);
    ctx.beginPath(); ctx.ellipse(at[0], at[1], (0.8 + 1.3 * Math.abs(p.sy)) * scale, 2.5 * scale, -person.roll * rad, 0, 6.283); ctx.fill();
  }

  // Face and hair share one depth-sorted pass so they hide each other correctly.
  if (!faceWinding) { let sum = 0; for (let t = 0; t < TRI_COUNT; t++) if (!material[t]) sum += Math.sign(signedArea(t)); faceWinding = Math.sign(sum) || 1; }
  nx.fill(0); ny.fill(0); nz.fill(0);
  for (let t = 0; t < TRI_COUNT; t++) {
    const a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
    let fx = (wy[b] - wy[a]) * (wz[c] - wz[a]) - (wz[b] - wz[a]) * (wy[c] - wy[a]), fy = (wz[b] - wz[a]) * (wx[c] - wx[a]) - (wx[b] - wx[a]) * (wz[c] - wz[a]), fz = (wx[b] - wx[a]) * (wy[c] - wy[a]) - (wy[b] - wy[a]) * (wx[c] - wx[a]);
    if (material[t]) {                        // hair: outward means away from the middle of the head
      const mid = place(p, ...HAIR.c);
      if (fx * (wx[a] - mid[0]) + fy * (wy[a] - mid[1]) + fz * (wz[a] - mid[2]) < 0) { fx = -fx; fy = -fy; fz = -fz; }
      front[t] = fz > 0 ? 1 : 0;
    } else {
      front[t] = signedArea(t) * faceWinding > 0 ? 1 : 0;
      if ((fz < 0) === (front[t] === 1)) { fx = -fx; fy = -fy; fz = -fz; }
    }
    for (const v of [a, b, c]) { nx[v] += fx; ny[v] += fy; nz[v] += fz; }
    depth[t] = wz[a] + wz[b] + wz[c];
  }
  order.sort((m, n) => depth[m] - depth[n]);
  ctx.lineJoin = "round"; ctx.lineWidth = 0.8;
  for (const t of order) {
    if (!front[t]) continue;
    const a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
    const sx = nx[a] + nx[b] + nx[c], sy = ny[a] + ny[b] + ny[c], sz = nz[a] + nz[b] + nz[c], len = Math.hypot(sx, sy, sz) || 1;
    const diffuse = Math.max(0, (sx * LIGHT[0] + sy * LIGHT[1] + sz * LIGHT[2]) / len);
    ctx.fillStyle = ctx.strokeStyle = material[t] ? tone(hair, (0.45 + 0.75 * diffuse + 0.7 * Math.pow(diffuse, 14)) * dim) : tone(skin, (0.36 + 0.68 * diffuse) * dim);
    ctx.beginPath(); ctx.moveTo(px[a], py[a]); ctx.lineTo(px[b], py[b]); ctx.lineTo(px[c], py[c]); ctx.closePath(); ctx.fill(); ctx.stroke();
  }

  const trace = ids => { ctx.beginPath(); ids.forEach((id, i) => i ? ctx.lineTo(px[id], py[id]) : ctx.moveTo(px[id], py[id])); };
  const shownArea = ids => { let sum = 0; ids.forEach((id, i) => { const j = ids[(i + 1) % ids.length]; sum += px[id] * py[j] - px[j] * py[id]; }); return Math.abs(sum) / 2; };
  trace(LIPS); ctx.closePath(); ctx.fillStyle = tone([skin[0] * 0.9, skin[1] * 0.76, skin[2] * 0.76], 0.9 * dim); ctx.fill();
  ctx.lineCap = "round"; ctx.lineWidth = 0.66 * scale; ctx.strokeStyle = tone(hair, 1.1 * dim);
  for (const brow of BROWS) { trace(brow); ctx.stroke(); }
  for (const eye of EYES) {
    if (shownArea(eye) < 0.55 * scale * scale) continue;                    // turned out of sight
    const cx = eye.reduce((n, id) => n + px[id], 0) / eye.length, cy = eye.reduce((n, id) => n + py[id], 0) / eye.length;
    ctx.save(); trace(eye); ctx.closePath();
    if (person.blink > 0.5) { ctx.fillStyle = tone(skin, 0.66 * dim); ctx.fill(); ctx.restore(); }
    else {
      ctx.fillStyle = tone([240, 238, 236], 0.9 * dim); ctx.fill(); ctx.clip();
      const ix = cx + person.gazeX * 0.75 * scale, iy = cy + person.gazeY * 0.4 * scale, r = 0.68 * scale;
      ctx.fillStyle = tone([78, 54, 38], dim); ctx.beginPath(); ctx.ellipse(ix, iy, r * Math.max(0.55, Math.abs(p.cy)), r, 0, 0, 6.283); ctx.fill();
      ctx.fillStyle = "#0b0b0d"; ctx.beginPath(); ctx.arc(ix, iy, r * 0.45, 0, 6.283); ctx.fill();
      ctx.fillStyle = `rgba(255,255,255,${0.85 * dim})`; ctx.beginPath(); ctx.arc(ix - r * 0.32, iy - r * 0.34, r * 0.17, 0, 6.283); ctx.fill();
      ctx.restore();
    }
    ctx.lineWidth = 0.2 * scale; ctx.strokeStyle = tone(hair, 0.8 * dim); trace(eye.slice(8).concat(eye[0])); ctx.stroke();   // upper lash line
  }
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
  for (let i = 0; i < FACE_COUNT; i++) { x0 = Math.min(x0, px[i]); x1 = Math.max(x1, px[i]); y0 = Math.min(y0, py[i]); y1 = Math.max(y1, py[i]); }
  return [x0, y0, x1 - x0, y1 - y0];
}

/** A dim room behind the person: wall, a soft window light, a shelf edge. */
export function drawRoom(ctx, w, h) {
  const wall = ctx.createLinearGradient(0, 0, w, h); wall.addColorStop(0, "#3a3d46"); wall.addColorStop(1, "#16171b"); ctx.fillStyle = wall; ctx.fillRect(0, 0, w, h);
  const glow = ctx.createRadialGradient(w * 0.14, h * 0.2, 0, w * 0.14, h * 0.2, w * 0.45);
  glow.addColorStop(0, "rgba(205,215,238,.4)"); glow.addColorStop(1, "rgba(205,215,238,0)"); ctx.fillStyle = glow; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = "rgba(0,0,0,.22)"; ctx.fillRect(w * 0.66, h * 0.3, w * 0.34, h * 0.035);
}

export const PEOPLE = {
  me: { skin: [228, 178, 146], hair: [62, 42, 30], shirt: [70, 76, 92] },
  them: { skin: [196, 146, 116], hair: [28, 24, 22], shirt: [92, 58, 54] },
};
