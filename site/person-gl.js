// The people in the camera preview: photo-textured characters from the Microsoft Rocketbox avatar
// library (MIT licence, see assets/person/CREDITS.md), converted by dev/make-avatar.py.
//
// Each frame the skeleton is posed (spine, neck and head share a turn the way a body does; the eyes
// look, the lids blink, the chest breathes), the mesh is skinned on the CPU (about 2,500 vertices),
// mirrored like a selfie view, and lit by a small WebGL renderer.
const CAMERA = 58;                                        // camera distance in cm
const FACE_POINTS = [[0, 7.5, 1], [0, -12.6, 1.5], [-7.3, -2, -3], [7.3, -2, -3], [0, -4.6, 2.6]];   // hairline, chin, cheeks, nose
const LID_TOP = 1.12, LID_BOTTOM = 0.3;                  // cm of lid travel for a full blink
const clamp = (v, a, b) => Math.min(b, Math.max(a, v)), mix = (a, b, t) => a + (b - a) * t, RAD = Math.PI / 180;
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

const VERTEX = `
attribute vec3 position; attribute vec3 normal; attribute vec3 uvm;      // uvm: u, v, material
uniform vec3 place; uniform vec2 size;
varying vec3 vWorld; varying vec3 vNormal; varying vec3 vUvm;
void main() {
  vWorld = position; vNormal = normal; vUvm = uvm;
  float k = place.z * ${CAMERA}.0 / (${CAMERA}.0 - position.z);
  gl_Position = vec4((place.x + position.x * k) / size.x * 2.0 - 1.0, 1.0 - (place.y - position.y * k) / size.y * 2.0, -position.z / 200.0, 1.0);
}`;
const FRAGMENT = `
#extension GL_OES_standard_derivatives : enable
precision highp float;
uniform sampler2D headMap; uniform sampler2D bodyMap; uniform sampler2D hairMap; uniform sampler2D headNormal;
uniform float dim; uniform float soft;                     // soft = 1 on the blended pass that draws the hair's edges
varying vec3 vWorld; varying vec3 vNormal; varying vec3 vUvm;
vec3 bumped(vec3 n, vec2 uv) {                             // tangent frame from derivatives, so the mesh needs no tangents
  vec3 dp1 = dFdx(vWorld), dp2 = dFdy(vWorld); vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1), t = dp2perp * duv1.x + dp1perp * duv2.x, b = dp2perp * duv1.y + dp1perp * duv2.y;
  float inv = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
  vec3 m = texture2D(headNormal, uv).xyz * 2.0 - 1.0;
  return normalize(mat3(t * inv, b * inv, n) * vec3(m.xy * 0.8, m.z));
}
float wrapped(vec3 n, vec3 l, float w) { return clamp((dot(n, l) + w) / (1.0 + w), 0.0, 1.0); }
void main() {
  vec2 uv = vUvm.xy; float material = vUvm.z;
  vec3 geo = normalize(vNormal), view = vec3(0.0, 0.0, 1.0);
  if (material > 1.5 && geo.z < 0.0) geo = -geo;            // hair cards are seen from both sides
  vec3 key = normalize(vec3(-0.5, 0.42, 0.76)), fill = normalize(vec3(0.75, 0.05, 0.6)), h = normalize(key + view);
  vec3 colour; float alpha = 1.0;
  if (material > 1.5) {                                    // hair and lashes: alpha-textured cards
    vec4 hair = texture2D(hairMap, uv); alpha = hair.a;
    if (soft < 0.5 ? alpha < 0.6 : alpha >= 0.6) discard;                 // solid strands first, their soft edges in the blended pass
    vec3 albedo = pow(hair.rgb, vec3(2.2));
    colour = albedo * (wrapped(geo, key, 0.6) * 2.0 + wrapped(geo, fill, 0.6) * 0.4 + 0.22) + vec3(0.5, 0.42, 0.34) * pow(max(dot(geo, h), 0.0), 12.0) * 0.12;
  } else if (material > 0.5) {                             // head: skin, plus the eyeballs and mouth that live in the same texture
    vec3 albedo = pow(texture2D(headMap, uv).rgb, vec3(2.2));
    bool eye = uv.x < 0.36 && uv.y < 0.2 && uv.x > 0.18;
    vec3 fine = eye ? geo : bumped(geo, uv);
    // Red light travels furthest under skin, so red sees a smoother normal than blue.
    vec3 nr = normalize(mix(fine, geo, 0.7)), ng = normalize(mix(fine, geo, 0.4));
    vec3 lit = vec3(wrapped(nr, key, 0.5), wrapped(ng, key, 0.34), wrapped(fine, key, 0.22));
    colour = albedo * (lit * vec3(1.0, 0.98, 0.95) * 2.2 + wrapped(geo, fill, 0.6) * vec3(0.5, 0.38, 0.3) * 0.7 + vec3(0.2, 0.21, 0.25));
    float fres = 0.03 + 0.97 * pow(clamp(1.0 - dot(fine, view), 0.0, 1.0), 5.0);
    colour += eye ? vec3(1.0) * pow(max(dot(geo, h), 0.0), 90.0) * 1.4                          // a wet highlight on the eye
                  : vec3(1.0, 0.98, 0.96) * (pow(max(dot(fine, h), 0.0), 36.0) * 0.18 + pow(max(dot(fine, h), 0.0), 8.0) * 0.05) * (0.4 + fres * 2.0);
    colour += vec3(0.5, 0.62, 0.9) * pow(clamp(1.0 - geo.z, 0.0, 1.0), 3.0) * step(geo.x, 0.15) * 0.16;   // cool rim from the window
  } else {                                                 // body: clothes and the skin of the neck
    vec3 albedo = pow(texture2D(bodyMap, uv).rgb, vec3(2.2));
    colour = albedo * (wrapped(geo, key, 0.4) * 2.1 + wrapped(geo, fill, 0.5) * 0.4 + 0.2);
  }
  colour = pow(max(colour, 0.0) * dim / (1.0 + 0.3 * max(colour, 0.0) * dim), vec3(1.0 / 2.2));
  gl_FragColor = vec4(colour * alpha, alpha);
}`;

// ---- 4x4 matrices, column-major ----
const multiply = (a, b, out = new Float64Array(16)) => {
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
  return out;
};
function inverse(m) {                                      // affine
  const [a, b, c, , d, e, f, , g, h, i] = m, det = a * (e * i - f * h) - d * (b * i - c * h) + g * (b * f - c * e);
  const r = [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det];
  return Float64Array.of(r[0], r[1], r[2], 0, r[3], r[4], r[5], 0, r[6], r[7], r[8], 0, -(r[0] * m[12] + r[3] * m[13] + r[6] * m[14]), -(r[1] * m[12] + r[4] * m[13] + r[7] * m[14]), -(r[2] * m[12] + r[5] * m[13] + r[8] * m[14]), 1);
}
/** Rotation in the character's own axes: yaw > 0 turns to their left, pitch > 0 looks down, roll > 0 tips toward their left shoulder. */
function turn(yaw = 0, pitch = 0, roll = 0) {
  const cy = Math.cos(yaw * RAD), sy = Math.sin(yaw * RAD), cp = Math.cos(pitch * RAD), sp = Math.sin(pitch * RAD), cr = Math.cos(-roll * RAD), sr = Math.sin(-roll * RAD);
  // R = Ry(yaw) * Rx(pitch) * Rz(roll), written out column by column
  return Float64Array.of(cy * cr + sy * sp * sr, cp * sr, -sy * cr + cy * sp * sr, 0, -cy * sr + sy * sp * cr, cp * cr, sy * sr + cy * sp * cr, 0, sy * cp, -sp, cy * cp, 0, 0, 0, 0, 1);
}

const loadImage = url => new Promise((resolve, reject) => { const image = new Image(); image.onload = () => resolve(image); image.onerror = () => reject(new Error("missing " + url)); image.src = url; });

/** Loads the avatar in `folder`. Resolves to shade(person, w, h) → { canvas, box }; rejects without WebGL or the files. */
export async function loadPerson(folder) {
  const canvas = document.createElement("canvas"), gl = canvas.getContext("webgl", { antialias: true, alpha: true, premultipliedAlpha: true });
  if (!gl || !gl.getExtension("OES_standard_derivatives")) throw new Error("WebGL with derivatives is not available");
  const at = name => new URL(name, folder).href, need = r => { if (!r.ok) throw new Error("missing " + r.url); return r; };
  const [rig, bin, ...images] = await Promise.all([fetch(at("rig.json")).then(need).then(r => r.json()), fetch(at("mesh.bin")).then(need).then(r => r.arrayBuffer()),
    ...["head.jpg", "body.jpg", "hair.webp", "head_normal.jpg"].map(name => loadImage(at(name)))]);
  const source = new Float32Array(bin, 0, rig.vertices * 17), indices = new Uint16Array(bin, rig.vertices * 68, rig.indices), count = rig.vertices;

  // ---- skeleton ----
  const bones = rig.bones.map(b => ({ ...b, bind: Float64Array.from(b.bind) })), named = Object.fromEntries(bones.map((b, i) => [b.name, i]));
  for (const b of bones) if (b.name.endsWith("Clavicle")) b.parent = named.Spine2;        // Biped hangs the shoulders off the neck; a neck turn must not drag them
  for (const b of bones) {
    b.unbind = inverse(b.bind); b.local = b.parent < 0 ? b.bind : multiply(bones[b.parent].unbind, b.bind);
    b.world = new Float64Array(16); b.skin = new Float64Array(16); b.delta = turn();
    b.axes = Float64Array.from(b.bind); b.axes[12] = b.axes[13] = b.axes[14] = 0; b.unaxes = inverse(b.axes);
  }
  const scratch = new Float64Array(16), scratch2 = new Float64Array(16), still = turn();
  /** Poses bone `name` with a rotation and an offset given in the character's axes, not the bone's own. */
  function pose(name, rotation, dx = 0, dy = 0, dz = 0) {
    const b = bones[named[name]]; if (!b) return;
    multiply(b.unaxes, multiply(rotation, b.axes, scratch), b.delta);
    b.delta[12] = b.unaxes[0] * dx + b.unaxes[4] * dy + b.unaxes[8] * dz; b.delta[13] = b.unaxes[1] * dx + b.unaxes[5] * dy + b.unaxes[9] * dz; b.delta[14] = b.unaxes[2] * dx + b.unaxes[6] * dy + b.unaxes[10] * dz;
  }
  function solve() {
    for (const b of bones) {                                // parents come first in the file
      multiply(b.parent < 0 ? b.local : multiply(bones[b.parent].world, b.local, scratch2), b.delta, b.world);
      multiply(b.world, b.unbind, b.skin);
    }
  }

  // ---- GL ----
  const compile = (type, text) => { const s = gl.createShader(type); gl.shaderSource(s, text); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const program = gl.createProgram(); gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX)); gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT)); gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  const fixed = new Float32Array(count * 3), moving = new Float32Array(count * 6);
  for (let i = 0; i < count; i++) fixed.set(source.subarray(i * 17 + 6, i * 17 + 9), i * 3);
  const attribute = (name, buffer, stride, offset) => { const a = gl.getAttribLocation(program, name); gl.bindBuffer(gl.ARRAY_BUFFER, buffer); gl.enableVertexAttribArray(a); gl.vertexAttribPointer(a, 3, gl.FLOAT, false, stride, offset); };
  const fixedBuffer = gl.createBuffer(), movingBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, fixedBuffer); gl.bufferData(gl.ARRAY_BUFFER, fixed, gl.STATIC_DRAW); attribute("uvm", fixedBuffer, 0, 0);
  gl.bindBuffer(gl.ARRAY_BUFFER, movingBuffer); gl.bufferData(gl.ARRAY_BUFFER, moving, gl.DYNAMIC_DRAW);
  attribute("position", movingBuffer, 24, 0); attribute("normal", movingBuffer, 24, 12);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  images.forEach((image, unit) => {
    gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    if (image.width > 4 && (image.width & (image.width - 1)) === 0) { gl.generateMipmap(gl.TEXTURE_2D); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR); }
    else { gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE); }
  });
  const u = Object.fromEntries(["place", "size", "dim", "soft", "headMap", "bodyMap", "hairMap", "headNormal"].map(name => [name, gl.getUniformLocation(program, name)]));
  ["headMap", "bodyMap", "hairMap", "headNormal"].forEach((name, unit) => gl.uniform1i(u[name], unit));
  gl.enable(gl.DEPTH_TEST); gl.clearColor(0, 0, 0, 0); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

  // ---- behaviour: what the eyes and lids are doing, carried between frames ----
  const life = { t: -1, blinkAt: 1.5 + Math.random() * 2, blinkFrom: -9, gazeX: 0, gazeY: 0, saccadeAt: 0, line: 0, column: -1, lastGaze: 0 };
  function animate(person) {
    const t = person.t ?? 0, dt = life.t < 0 ? 0 : clamp(t - life.t, 0, 0.1); life.t = t;
    const Y = person.yaw, P = person.pitch, R = person.roll, gone = person.gone ?? 0, lean = person.lean ?? 0;
    const breath = Math.sin(t * 1.35), sway = Math.sin(t * 0.37) + 0.5 * Math.sin(t * 0.83 + 1);

    // A big turn is shared down the body: the shoulders come round once the neck runs out.
    const torso = Math.sign(Y) * Math.max(0, Math.abs(Y) - 26) * 0.4;
    const spine = [0.03 * Y + 0.3 * torso, 0.05 * Y + 0.35 * torso, 0.08 * Y + 0.35 * torso], neckYaw = 0.3 * (Y - torso);
    pose("Pelvis", turn(70 * gone, 0, 0));
    pose("Spine", turn(spine[0], lean * 0.4, 0.5 * sway), 0.25 * sway);
    pose("Spine1", turn(spine[1], lean * 0.3 + 0.35 * breath, 0.3 * sway));
    pose("Spine2", turn(spine[2], lean * 0.3 + 0.06 * P + 0.5 * breath, -0.5 * sway));
    pose("Neck", turn(neckYaw, 0.34 * P - lean * 0.4, 0.4 * R));
    pose("Head", turn(Y - spine[0] - spine[1] - spine[2] - neckYaw, 0.6 * P - lean * 0.5, 0.6 * R));
    pose("L Clavicle", turn(0, 0, 0.9 * breath), 0, 0.12 * breath); pose("R Clavicle", turn(0, 0, -0.9 * breath), 0, 0.12 * breath);

    // Eyes. Facing the screen they stay on it while the head drifts, and scan it in little jumps like reading;
    // when the head turns away they get there first, then settle straight ahead.
    const onScreen = person.stare ? 1 : 1 - smooth(14, 26, Math.max(Math.abs(Y), Math.abs(P) * 1.3));
    if (t > life.saccadeAt) {
      life.column++; if (life.column > 5) { life.column = -1 - Math.floor(Math.random() * 2); life.line = (life.line + 1) % 4; }
      life.saccadeAt = t + 0.22 + Math.random() * (life.column < 0 ? 0.9 : 0.3);
    }
    const readX = life.column * 2.6 - 5, readY = 5 + life.line * 1.3;
    const leadYaw = clamp(((person.targetYaw ?? Y) - Y) * 0.7, -26, 26), leadPitch = clamp(((person.targetPitch ?? P) - P) * 0.6, -16, 16);
    const wantX = clamp(mix(leadYaw, -0.85 * Y + readX + leadYaw * 0.3, onScreen), -32, 32), wantY = clamp(mix(leadPitch, -0.8 * P + readY, onScreen), -18, 22);
    if (person.look) { life.gazeX = person.look[0]; life.gazeY = person.look[1]; }   // held gaze, for checking the rig
    const snap = person.look ? 0 : 1 - Math.exp(-dt / 0.035);               // eyes move fast, in jumps
    life.gazeX += (wantX - life.gazeX) * snap; life.gazeY += (wantY - life.gazeY) * snap;

    // Blinks: every few seconds, and usually when the eyes make a big jump.
    if (Math.abs(wantX - life.lastGaze) > 14 && t - life.blinkFrom > 0.9) life.blinkAt = Math.min(life.blinkAt, t + 0.03);
    life.lastGaze = wantX;
    if (t >= life.blinkAt) { life.blinkFrom = t; life.blinkAt = t + 2.2 + Math.random() * 4 + (Math.random() < 0.15 ? -1.9 : 0); }
    const phase = t - life.blinkFrom, blink = phase < 0.075 ? phase / 0.075 : phase < 0.11 ? 1 : Math.max(0, 1 - (phase - 0.11) / 0.16);
    const lid = clamp(Math.max(blink * blink * (3 - 2 * blink), person.blink ?? 0) + Math.max(0, life.gazeY) / 55, 0, 1);   // lids follow a downward look
    for (const side of ["L", "R"]) {
      pose(side + "Eye", turn(life.gazeX, life.gazeY, 0));
      pose(side + "EyeBlinkTop", still, 0, -LID_TOP * lid, -0.12 * lid); pose(side + "EyeBlinkBottom", still, 0, LID_BOTTOM * lid, 0);
    }
    const lift = 0.22 * smooth(4, 22, -P - life.gazeY * 0.4) + 0.04 * sway;          // brows rise a little with an upward look
    for (const brow of ["LInnerEyebrow", "RInnerEyebrow", "LOuterEyebrow", "ROuterEyebrow", "MMiddleEyebrow"]) pose(brow, still, 0, lift, 0);
    solve();
  }

  function skin() {
    for (let i = 0, o = 0; i < count; i++, o += 6) {
      const s = i * 17, x = source[s], y = source[s + 1], z = source[s + 2], nx = source[s + 3], ny = source[s + 4], nz = source[s + 5];
      let px = 0, py = 0, pz = 0, qx = 0, qy = 0, qz = 0;
      for (let k = 0; k < 4; k++) {
        const w = source[s + 13 + k]; if (w === 0) continue;
        const m = bones[source[s + 9 + k]].skin;
        px += w * (m[0] * x + m[4] * y + m[8] * z + m[12]); py += w * (m[1] * x + m[5] * y + m[9] * z + m[13]); pz += w * (m[2] * x + m[6] * y + m[10] * z + m[14]);
        qx += w * (m[0] * nx + m[4] * ny + m[8] * nz); qy += w * (m[1] * nx + m[5] * ny + m[9] * nz); qz += w * (m[2] * nx + m[6] * ny + m[10] * nz);
      }
      moving[o] = -px; moving[o + 1] = py; moving[o + 2] = pz; moving[o + 3] = -qx; moving[o + 4] = qy; moving[o + 5] = qz;   // mirrored, like a selfie view
    }
  }

  return function shade(person, width, height) {
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    animate(person); skin();
    gl.viewport(0, 0, width, height); gl.depthMask(true); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);   // clear honours the depth mask the hair pass leaves off
    gl.bindBuffer(gl.ARRAY_BUFFER, movingBuffer); gl.bufferSubData(gl.ARRAY_BUFFER, 0, moving);
    gl.uniform3f(u.place, person.x, person.y, person.scale); gl.uniform2f(u.size, width, height); gl.uniform1f(u.dim, person.dim);
    gl.disable(gl.BLEND); gl.uniform1f(u.soft, 0); gl.drawElements(gl.TRIANGLES, rig.indices, gl.UNSIGNED_SHORT, 0);                      // everything solid
    gl.enable(gl.BLEND); gl.depthMask(false); gl.uniform1f(u.soft, 1);
    gl.drawElements(gl.TRIANGLES, rig.indices - rig.hairStart, gl.UNSIGNED_SHORT, rig.hairStart * 2);                                    // then the soft edges of the hair

    const head = bones[named.Head].skin, xs = [], ys = [];
    for (const [x, y, z] of FACE_POINTS) {
      const wx = -(head[0] * x + head[4] * y + head[8] * z + head[12]), wy = head[1] * x + head[5] * y + head[9] * z + head[13], wz = head[2] * x + head[6] * y + head[10] * z + head[14];
      const k = person.scale * CAMERA / (CAMERA - wz); xs.push(person.x + wx * k); ys.push(person.y - wy * k);
    }
    return { canvas, box: [Math.min(...xs), Math.min(...ys), Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)] };
  };
}
