// A 3D person for the camera preview.
// The face is MediaPipe's canonical face model (the geometry face trackers fit to real people);
// the skull, hair, ears, neck and shoulders are built around it. This module owns the geometry and
// the per-frame pose. head-gl.js shades it with WebGL; drawHead() below is the plain-canvas fallback
// (also used by dev/fake-camera.html). Eyes and brows are drawn on top in 2D either way.
import { VERTICES, TRIANGLES } from "./face-model.js";

const EYES = [[33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
              [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466]];
const BROWS = [[46, 53, 52, 65, 55], [276, 283, 282, 295, 285]];
const LIPS = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185];
const INNER_LIPS = [78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191];
const PIVOT = [0, -1.5, -4.5], CAMERA = 58, LIGHT = [-0.36, 0.46, 0.81];
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const tone = (rgb, light) => `rgb(${rgb.map(c => Math.round(clamp(c * light, 0, 255))).join(",")})`;

// ---- geometry ---------------------------------------------------------------
// Every vertex has a kind: what it is made of, how much of the head's rotation it follows
// (the neck follows a little, the shoulders barely), and the centre its surface faces away from.
export const FACE = 0, HAIR = 1, NECK = 2, CLOTH = 3, SKIN = 4;
const FOLLOW = [1, 1, 0.35, 0.06, 1], CENTRES = [[0, 0.5, -3], [0, 1.9, -2.6], [0, -12, -4.5], [0, -27, -6], [0, 1.6, -3.6]];
const model = Array.from(VERTICES, v => v / 100), kind = new Array(VERTICES.length / 3).fill(FACE), along = new Array(VERTICES.length / 3).fill(0);
const tris = Array.from(TRIANGLES);

function ellipsoid(what, centre, radii, columns, rings, edgeAt, lift = () => 1) {
  const first = model.length / 3;
  for (let c = 0; c < columns; c++) {
    const phi = c / columns * Math.PI * 2, fromFront = Math.abs(Math.atan2(Math.sin(phi), Math.cos(phi))) * 180 / Math.PI;   // 0° = front, 180° = back
    const stop = Math.acos(clamp((edgeAt(fromFront) - centre[1]) / radii[1], -1, 1));
    for (let r = 0; r <= rings; r++) {
      const theta = stop * r / rings, k = lift(theta, phi);
      model.push(centre[0] + radii[0] * Math.sin(theta) * Math.sin(phi) * k, centre[1] + radii[1] * Math.cos(theta) * k, centre[2] + radii[2] * Math.sin(theta) * Math.cos(phi) * k);
      kind.push(what); along.push(c / columns);
    }
  }
  for (let c = 0; c < columns; c++) for (let r = 0; r < rings; r++) {
    const a = first + c * (rings + 1) + r, b = first + ((c + 1) % columns) * (rings + 1) + r;
    tris.push(a, a + 1, b + 1, a, b + 1, b);
  }
}
const FACE_COUNT = VERTICES.length / 3;
// Hair: a hairline over the forehead, down past the ears at the sides, to the nape at the back.
ellipsoid(HAIR, CENTRES[HAIR], [8.5, 10.3, 10.1], 48, 14,
  a => (a < 38 ? 6.7 - 0.6 * Math.cos(a / 38 * Math.PI) : a < 80 ? 7.3 - (a - 38) / 42 * 8.7 : -1.4 - Math.min(1, (a - 80) / 50) * 4.2) + 0.35 * Math.sin(a * 0.9) + 0.2 * Math.sin(a * 2.3),
  (theta, phi) => 1 + 0.05 * Math.sin(theta) * Math.max(0, Math.cos(phi)) + 0.02 * Math.sin(phi * 9 + theta * 5));
ellipsoid(SKIN, CENTRES[SKIN], [7.8, 9.7, 8.3], 32, 12, () => -7.4);                                     // skull, under the hair and behind the face
for (const side of [-1, 1]) ellipsoid(SKIN, [side * 7.75, -0.7, -3.1], [0.95, 2.7, 1.7], 12, 6, () => -9);  // ears
ellipsoid(NECK, [0, -12, -4.6], [4.9, 9, 5.3], 24, 8, () => -22);
ellipsoid(CLOTH, CENTRES[CLOTH], [25, 13.5, 12], 40, 10, () => -30);

const COUNT = model.length / 3, TRI_COUNT = tris.length / 3;

// Skin is not one colour: lips, a flush over the cheeks and nose, a shadow of stubble, darker eye sockets.
const tint = new Float32Array(COUNT * 3).fill(1), occlusion = new Float32Array(COUNT).fill(1);
(function paint() {
  const blob = (i, x, y, z, size) => Math.exp(-((model[i * 3] - x) ** 2 + (model[i * 3 + 1] - y) ** 2 + (model[i * 3 + 2] - z) ** 2) / size);
  const mix = (i, rgb, amount) => { for (let c = 0; c < 3; c++) tint[i * 3 + c] += (rgb[c] - tint[i * 3 + c]) * amount; };
  for (let i = 0; i < FACE_COUNT; i++) {
    mix(i, [1.03, 0.9, 0.88], 0.4 * (blob(i, 4.6, -1.6, 4.2, 9) + blob(i, -4.6, -1.6, 4.2, 9)) + 0.22 * blob(i, 0, -1.2, 7.4, 3));       // cheeks, nose
    mix(i, [0.8, 0.84, 0.9], 0.3 * (blob(i, 0, -7.2, 5, 16) + 0.7 * blob(i, 4.4, -5.6, 3, 9) + 0.7 * blob(i, -4.4, -5.6, 3, 9)));       // stubble
    occlusion[i] -= 0.2 * (blob(i, 3.1, 2.5, 4.2, 5) + blob(i, -3.1, 2.5, 4.2, 5)) + 0.3 * (blob(i, 1.5, -2.2, 5.6, 0.9) + blob(i, -1.5, -2.2, 5.6, 0.9)) + 0.18 * blob(i, 0, -5.3, 5.4, 2.2);
  }
  for (const i of LIPS) mix(i, [0.92, 0.72, 0.7], 0.55);
  for (const i of INNER_LIPS) mix(i, [0.78, 0.54, 0.54], 0.75);
  for (let i = FACE_COUNT; i < COUNT; i++) if (kind[i] === NECK) occlusion[i] = 0.62 + 0.38 * clamp((-7 - model[i * 3 + 1]) / 9, 0, 1);   // the chin's shadow
})();

// ---- per-frame pose (shared by both renderers) ------------------------------
const px = new Float32Array(COUNT), py = new Float32Array(COUNT), wx = new Float32Array(COUNT), wy = new Float32Array(COUNT), wz = new Float32Array(COUNT);
const nx = new Float32Array(COUNT), ny = new Float32Array(COUNT), nz = new Float32Array(COUNT);
const order = Array.from({ length: TRI_COUNT }, (_, i) => i), depth = new Float32Array(TRI_COUNT), facing = new Int8Array(TRI_COUNT);
export const MESH = { count: COUNT, tris, kind, along, tint, occlusion, px, py, wz, nx, ny, nz };

function rotation(person, follow) {
  const rad = Math.PI / 180, yaw = -person.yaw * follow * rad, pitch = person.pitch * follow * rad, roll = person.roll * follow * rad;   // mirrored like a selfie view
  return { cr: Math.cos(roll), sr: Math.sin(roll), cp: Math.cos(pitch), sp: Math.sin(pitch), cy: Math.cos(yaw), sy: Math.sin(yaw) };
}
function place(r, x, y, z) {               // model space (cm) → rotated world space
  x -= PIVOT[0]; y -= PIVOT[1]; z -= PIVOT[2];
  const x1 = x * r.cr - y * r.sr, y1 = x * r.sr + y * r.cr, y2 = y1 * r.cp - z * r.sp, z2 = y1 * r.sp + z * r.cp;
  return [x1 * r.cy + z2 * r.sy + PIVOT[0], y2 + PIVOT[1], -x1 * r.sy + z2 * r.cy + PIVOT[2]];
}

/** Moves the geometry into `person`'s pose. Returns the face's bounding box [x, y, w, h] in canvas pixels. */
export function poseHead(person) {
  const turns = FOLLOW.map(follow => rotation(person, follow)), centres = CENTRES.map((c, k) => place(turns[k], ...c));
  for (let i = 0; i < COUNT; i++) {
    const v = place(turns[kind[i]], model[i * 3], model[i * 3 + 1] + (kind[i] === CLOTH ? -person.breath / person.scale : 0), model[i * 3 + 2]);
    const k = person.scale * CAMERA / (CAMERA - v[2]);
    wx[i] = v[0]; wy[i] = v[1]; wz[i] = v[2]; px[i] = person.x + v[0] * k; py[i] = person.y - v[1] * k;
  }
  nx.fill(0); ny.fill(0); nz.fill(0);
  for (let t = 0; t < TRI_COUNT; t++) {     // smooth normals: area-weighted, facing away from the middle of whatever this is part of
    const a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2], mid = centres[kind[a]];
    let fx = (wy[b] - wy[a]) * (wz[c] - wz[a]) - (wz[b] - wz[a]) * (wy[c] - wy[a]), fy = (wz[b] - wz[a]) * (wx[c] - wx[a]) - (wx[b] - wx[a]) * (wz[c] - wz[a]), fz = (wx[b] - wx[a]) * (wy[c] - wy[a]) - (wy[b] - wy[a]) * (wx[c] - wx[a]);
    if (fx * (wx[a] - mid[0]) + fy * (wy[a] - mid[1]) + fz * (wz[a] - mid[2]) < 0) { fx = -fx; fy = -fy; fz = -fz; }
    for (const v of [a, b, c]) { nx[v] += fx; ny[v] += fy; nz[v] += fz; }
    facing[t] = fz > 0 ? 1 : 0; depth[t] = wz[a] + wz[b] + wz[c];
  }
  person.turn = turns[FACE];
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
  for (let i = 0; i < FACE_COUNT; i++) { x0 = Math.min(x0, px[i]); x1 = Math.max(x1, px[i]); y0 = Math.min(y0, py[i]); y1 = Math.max(y1, py[i]); }
  return [x0, y0, x1 - x0, y1 - y0];
}

/** Eyes, lashes and brows, drawn over whichever renderer shaded the head. Call after poseHead(). */
export function drawFeatures(ctx, person) {
  const { scale, dim, skin, hair } = person;
  const trace = ids => { ctx.beginPath(); ids.forEach((id, i) => i ? ctx.lineTo(px[id], py[id]) : ctx.moveTo(px[id], py[id])); };
  const shownArea = ids => { let sum = 0; ids.forEach((id, i) => { const j = ids[(i + 1) % ids.length]; sum += px[id] * py[j] - px[j] * py[id]; }); return Math.abs(sum) / 2; };
  ctx.lineCap = ctx.lineJoin = "round";
  BROWS.forEach((brow, side) => {
    if (shownArea(EYES[side]) < 0.4 * scale * scale) return;
    ctx.strokeStyle = tone(hair, 1.15 * dim); ctx.globalAlpha = 0.6;
    for (const [width, from] of [[0.7, 0], [0.5, 1]]) { ctx.lineWidth = width * scale; trace(brow.slice(from)); ctx.stroke(); }   // thicker toward the nose
    ctx.globalAlpha = 1;
  });
  for (const eye of EYES) {
    if (shownArea(eye) < 0.55 * scale * scale) continue;                    // turned out of sight
    const cx = eye.reduce((n, id) => n + px[id], 0) / eye.length, cy = eye.reduce((n, id) => n + py[id], 0) / eye.length;
    const open = ids => { ctx.beginPath(); ids.forEach((id, i) => { const y = cy + (py[id] - cy) * 1.45; i ? ctx.lineTo(px[id], y) : ctx.moveTo(px[id], y); }); };   // the model's eyes are nearly shut
    ctx.save(); open(eye); ctx.closePath();
    if (person.blink > 0.5) { ctx.fillStyle = tone(skin, 0.7 * dim); ctx.fill(); ctx.restore(); }
    else {
      const white = ctx.createRadialGradient(cx, cy, 0, cx, cy, 1.7 * scale);
      white.addColorStop(0, tone([244, 241, 238], 0.95 * dim)); white.addColorStop(1, tone([196, 186, 182], 0.8 * dim));
      ctx.fillStyle = white; ctx.fill(); ctx.clip();
      const ix = cx + person.gazeX * 0.75 * scale, iy = cy + person.gazeY * 0.4 * scale, r = 0.7 * scale, squash = Math.max(0.55, Math.abs(person.turn.cy));
      const iris = ctx.createRadialGradient(ix, iy, r * 0.2, ix, iy, r);
      iris.addColorStop(0, tone([140, 96, 58], dim)); iris.addColorStop(0.75, tone([84, 56, 36], dim)); iris.addColorStop(1, tone([34, 24, 18], dim));
      ctx.fillStyle = iris; ctx.beginPath(); ctx.ellipse(ix, iy, r * squash, r, 0, 0, 6.283); ctx.fill();
      ctx.fillStyle = "#08080a"; ctx.beginPath(); ctx.ellipse(ix, iy, r * 0.42 * squash, r * 0.42, 0, 0, 6.283); ctx.fill();
      ctx.fillStyle = `rgba(255,255,255,${0.9 * dim})`; ctx.beginPath(); ctx.arc(ix - r * 0.34, iy - r * 0.36, r * 0.16, 0, 6.283); ctx.fill();
      ctx.fillStyle = "rgba(40,20,14,.22)"; ctx.fillRect(cx - 3 * scale, cy - 2 * scale, 6 * scale, 1.3 * scale);   // the lid's shadow on the eye
      ctx.restore();
    }
    ctx.lineWidth = 0.17 * scale; ctx.strokeStyle = tone([46, 32, 24], dim); open(eye.slice(8).concat(eye[0])); ctx.stroke();   // upper lash line
  }
}

/** Plain-canvas fallback: flat-shaded triangles, depth sorted. Returns the face's bounding box. */
export function drawHead(ctx, person) {
  const box = poseHead(person), { dim, skin, hair, shirt } = person;
  const base = [skin, hair, skin, shirt, skin];
  order.sort((m, n) => depth[m] - depth[n]);
  ctx.lineJoin = "round"; ctx.lineWidth = 0.8;
  for (const t of order) {
    if (!facing[t]) continue;
    const a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2], what = kind[a];
    const sx = nx[a] + nx[b] + nx[c], sy = ny[a] + ny[b] + ny[c], sz = nz[a] + nz[b] + nz[c], len = Math.hypot(sx, sy, sz) || 1;
    const diffuse = Math.max(0, (sx * LIGHT[0] + sy * LIGHT[1] + sz * LIGHT[2]) / len), shade = (what === HAIR ? 0.45 + 0.75 * diffuse + 0.7 * diffuse ** 14 : 0.36 + 0.68 * diffuse) * occlusion[a] * dim;
    ctx.fillStyle = ctx.strokeStyle = tone([0, 1, 2].map(ch => base[what][ch] * (tint[a * 3 + ch] + tint[b * 3 + ch] + tint[c * 3 + ch]) / 3), shade);
    ctx.beginPath(); ctx.moveTo(px[a], py[a]); ctx.lineTo(px[b], py[b]); ctx.lineTo(px[c], py[c]); ctx.closePath(); ctx.fill(); ctx.stroke();
  }
  drawFeatures(ctx, person);
  return box;
}

/** A dim room behind the person: wall, a soft window light, a shelf edge. */
export function drawRoom(ctx, w, h) {
  const wall = ctx.createLinearGradient(0, 0, w, h); wall.addColorStop(0, "#3a3d46"); wall.addColorStop(1, "#16171b"); ctx.fillStyle = wall; ctx.fillRect(0, 0, w, h);
  const glow = ctx.createRadialGradient(w * 0.14, h * 0.2, 0, w * 0.14, h * 0.2, w * 0.45);
  glow.addColorStop(0, "rgba(205,215,238,.4)"); glow.addColorStop(1, "rgba(205,215,238,0)"); ctx.fillStyle = glow; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = "rgba(0,0,0,.22)"; ctx.fillRect(w * 0.66, h * 0.3, w * 0.34, h * 0.035);
}

export const PEOPLE = {
  me: { skin: [212, 168, 138], hair: [58, 40, 28], shirt: [66, 72, 88] },
  them: { skin: [190, 140, 110], hair: [26, 22, 20], shirt: [88, 54, 50] },
};
