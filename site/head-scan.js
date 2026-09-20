// The realistic person in the camera preview: a 3D scan of a real head and shoulders
// ("Infinite, 3D Head Scan" by Lee Perry-Smith, www.ir-ltd.net, CC BY 3.0 - see assets/head/),
// with its photographed skin texture and normal map, lit by a small hand-written WebGL renderer.
// The scan's eyes are closed, so open eyes are drawn over the lids in 2D; a blink just skips them.
const ASSETS = new URL("./assets/head/", import.meta.url);
const UNIT = 4.2, CAMERA = 58;                         // centimetres per model unit (eyes 6.3 cm apart); camera distance in cm
const ANCHOR = [-0.09, 1.6, 0.5], PIVOT = [-0.09, -0.25, -0.35];   // what person.x/y points at (between the eyes); top of the spine
const EYES = [[-0.851, 1.652, 1.74], [0.651, 1.652, 1.75]];
const FACE_POINTS = [[-0.09, 2.95, 1.9], [-0.09, -0.62, 1.95], [-1.62, 1.2, 0.85], [1.44, 1.2, 0.85], [-0.09, 0.98, 2.46], ...EYES];   // brow-line top, chin, cheeks, nose
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

const VERTEX = `
attribute vec3 position; attribute vec3 normal; attribute vec2 uv;
uniform mat3 turn; uniform vec3 pivot; uniform vec3 anchor; uniform vec3 place; uniform vec2 size;
varying vec3 vWorld; varying vec3 vNormal; varying vec2 vUv; varying vec3 vModel;
void main() {
  float follow = smoothstep(-1.45, -0.45, position.y + 0.35 * position.z);          // the head turns, the neck twists, the shoulders stay
  vec3 p = mix(position, pivot + turn * (position - pivot), follow);
  vNormal = normalize(mix(normal, turn * normal, follow)); vUv = uv; vModel = position;
  vWorld = (p - anchor) * ${UNIT.toFixed(1)};
  float k = place.z * ${CAMERA.toFixed(1)} / (${CAMERA.toFixed(1)} - vWorld.z);
  gl_Position = vec4((place.x + vWorld.x * k) / size.x * 2.0 - 1.0, 1.0 - (place.y - vWorld.y * k) / size.y * 2.0, -vWorld.z / 140.0, 1.0);
}`;
const FRAGMENT = `
#extension GL_OES_standard_derivatives : enable
precision highp float;
uniform sampler2D colourMap; uniform sampler2D normalMap; uniform float dim; uniform vec3 skinTint; uniform vec3 shirt;
varying vec3 vWorld; varying vec3 vNormal; varying vec2 vUv; varying vec3 vModel;
vec3 bumped(vec3 n) {                                  // tangent frame from screen-space derivatives, so the mesh needs no tangents
  vec3 dp1 = dFdx(vWorld), dp2 = dFdy(vWorld); vec2 duv1 = dFdx(vUv), duv2 = dFdy(vUv);
  vec3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1), t = dp2perp * duv1.x + dp1perp * duv2.x, b = dp2perp * duv1.y + dp1perp * duv2.y;
  float inv = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
  vec3 m = texture2D(normalMap, vUv).xyz * 2.0 - 1.0;
  return normalize(mat3(t * inv, b * inv, n) * vec3(m.xy * 0.85, m.z));
}
float wrapped(vec3 n, vec3 l, float w) { return clamp((dot(n, l) + w) / (1.0 + w), 0.0, 1.0); }
void main() {
  vec3 geo = normalize(vNormal), fine = bumped(geo), view = vec3(0.0, 0.0, 1.0);
  vec3 key = normalize(vec3(-0.5, 0.42, 0.76)), fill = normalize(vec3(0.75, 0.05, 0.6));
  float collar = -1.27 - 0.3 * clamp(vModel.z + 0.5, 0.0, 2.5), cloth = smoothstep(collar + 0.025, collar - 0.025, vModel.y);
  // Skin: red light travels furthest under the surface, so red sees a smoother normal than blue.
  vec3 albedo = pow(texture2D(colourMap, vUv).rgb, vec3(2.2)) * skinTint;
  vec3 nr = normalize(mix(fine, geo, 0.75)), ng = normalize(mix(fine, geo, 0.45));
  vec3 lit = vec3(wrapped(nr, key, 0.5), wrapped(ng, key, 0.32), wrapped(fine, key, 0.2));
  vec3 skin = albedo * (lit * vec3(1.0, 0.98, 0.95) * 2.35 + wrapped(geo, fill, 0.6) * vec3(0.5, 0.36, 0.28) * 0.7 + vec3(0.2, 0.21, 0.25));
  vec3 h = normalize(key + view); float fres = 0.03 + 0.97 * pow(1.0 - max(dot(fine, view), 0.0), 5.0);
  skin += (pow(max(dot(fine, h), 0.0), 38.0) * 0.22 + pow(max(dot(fine, h), 0.0), 9.0) * 0.06) * (0.4 + fres * 2.0) * vec3(1.0, 0.98, 0.96);
  skin += vec3(0.5, 0.62, 0.9) * pow(1.0 - max(geo.z, 0.0), 3.0) * step(geo.x, 0.15) * 0.22;   // cool rim from the window
  // Shirt: matte, a faint knit, a shadow where it meets the neck.
  float knit = 0.92 + 0.08 * sin(vModel.x * 90.0) * sin(vModel.y * 90.0);
  vec3 fabric = shirt * knit * (wrapped(geo, key, 0.35) * 1.9 + wrapped(geo, fill, 0.5) * 0.35 + 0.16);
  vec3 colour = mix(skin * (1.0 - 0.35 * smoothstep(collar + 0.35, collar, vModel.y)), fabric * (0.7 + 0.3 * smoothstep(collar, collar - 0.12, vModel.y)), cloth);
  gl_FragColor = vec4(pow(colour * dim / (1.0 + 0.35 * colour * dim), vec3(1.0 / 2.2)), 1.0);   // soft shoulder on the highlights, then to sRGB
}`;

function parseGlb(bytes) {
  const view = new DataView(bytes), jsonLength = view.getUint32(12, true), json = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes, 20, jsonLength)));
  const bin = 20 + jsonLength + 8, primitive = json.meshes[0].primitives[0];
  const read = (index, Type, width) => { const a = json.accessors[index], v = json.bufferViews[a.bufferView]; return new Type(bytes.slice(bin + (v.byteOffset || 0) + (a.byteOffset || 0), bin + (v.byteOffset || 0) + (a.byteOffset || 0) + a.count * width * Type.BYTES_PER_ELEMENT)); };
  return { position: read(primitive.attributes.POSITION, Float32Array, 3), normal: read(primitive.attributes.NORMAL, Float32Array, 3), uv: read(primitive.attributes.TEXCOORD_0, Float32Array, 2), index: read(primitive.indices, Uint16Array, 1) };
}
const loadImage = name => new Promise((resolve, reject) => { const image = new Image(); image.onload = () => resolve(image); image.onerror = reject; image.src = new URL(name, ASSETS); });

function rotationOf(person) {              // same convention as head.js: mirrored like a selfie view, pitch > 0 looks down
  const rad = Math.PI / 180, cy = Math.cos(-person.yaw * rad), sy = Math.sin(-person.yaw * rad), cp = Math.cos(person.pitch * rad), sp = Math.sin(person.pitch * rad), cr = Math.cos(person.roll * rad), sr = Math.sin(person.roll * rad);
  return [[cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp], [cp * sr, cp * cr, -sp], [-sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp]];
}
function project(person, rows, point, normal) {
  const follow = clamp((point[1] + 0.35 * point[2] + 1.45) / 1, 0, 1), blend = follow * follow * (3 - 2 * follow), d = point.map((c, i) => c - PIVOT[i]);
  const p = point.map((c, i) => c + (PIVOT[i] + rows[i][0] * d[0] + rows[i][1] * d[1] + rows[i][2] * d[2] - c) * blend), world = p.map((c, i) => (c - ANCHOR[i]) * UNIT);
  const k = person.scale * CAMERA / (CAMERA - world[2]);
  return { x: person.x + world[0] * k, y: person.y - world[1] * k, k: k * UNIT, facing: normal ? rows[2][0] * normal[0] + rows[2][1] * normal[1] + rows[2][2] * normal[2] : 1 };
}

/** Resolves to { shade(person, w, h) → canvas, features(ctx, person) → face box }, or rejects if WebGL or the assets aren't available. */
export async function loadScan() {
  const canvas = document.createElement("canvas"), gl = canvas.getContext("webgl", { antialias: true, alpha: true, premultipliedAlpha: true });
  if (!gl || !gl.getExtension("OES_standard_derivatives")) throw new Error("WebGL with derivatives is not available");
  const [glb, colour, bumps] = await Promise.all([fetch(new URL("LeePerrySmith.glb", ASSETS)).then(r => { if (!r.ok) throw new Error("head scan missing"); return r.arrayBuffer(); }), loadImage("Map-COL.jpg"), loadImage("Infinite-Level_02_Tangent_SmoothUV.jpg")]);
  const mesh = parseGlb(glb);

  const compile = (type, source) => { const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const program = gl.createProgram(); gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX)); gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT)); gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  for (const [name, data, width] of [["position", mesh.position, 3], ["normal", mesh.normal, 3], ["uv", mesh.uv, 2]]) {
    const at = gl.getAttribLocation(program, name); gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(at); gl.vertexAttribPointer(at, width, gl.FLOAT, false, 0, 0);
  }
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, mesh.index, gl.STATIC_DRAW);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);                     // these UVs count v from the bottom of the image
  [colour, bumps].forEach((image, unit) => {
    gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, image); gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  });
  const u = Object.fromEntries(["turn", "pivot", "anchor", "place", "size", "colourMap", "normalMap", "dim", "skinTint", "shirt"].map(name => [name, gl.getUniformLocation(program, name)]));
  gl.uniform1i(u.colourMap, 0); gl.uniform1i(u.normalMap, 1); gl.uniform3fv(u.pivot, PIVOT); gl.uniform3fv(u.anchor, ANCHOR);
  gl.enable(gl.DEPTH_TEST); gl.enable(gl.CULL_FACE); gl.clearColor(0, 0, 0, 0);

  function shade(person, width, height) {
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    const r = rotationOf(person);
    gl.viewport(0, 0, width, height); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.uniformMatrix3fv(u.turn, false, [r[0][0], r[1][0], r[2][0], r[0][1], r[1][1], r[2][1], r[0][2], r[1][2], r[2][2]]);   // column-major
    gl.uniform3f(u.place, person.x, person.y, person.scale); gl.uniform2f(u.size, width, height); gl.uniform1f(u.dim, person.dim);
    gl.uniform3fv(u.skinTint, person.skinTint); gl.uniform3fv(u.shirt, person.shirt.map(c => (c / 255) ** 2.2));
    gl.drawElements(gl.TRIANGLES, mesh.index.length, gl.UNSIGNED_SHORT, 0);
    return canvas;
  }

  function features(ctx, person) {
    const rows = rotationOf(person);
    EYES.forEach((centre, side) => {
      const eye = project(person, rows, centre, [side ? 0.22 : -0.22, 0, 0.975]);
      if (eye.facing < 0.3 || person.blink > 0.5) return;               // turned away, or blinking: the scan's own closed lid shows
      const s = eye.k, squash = clamp(eye.facing * 1.15, 0.35, 1);
      ctx.save(); ctx.translate(eye.x, eye.y); ctx.rotate(-person.roll * Math.PI / 180); ctx.scale(squash, 1);
      const lids = () => { ctx.beginPath(); ctx.moveTo(-0.31 * s, 0.015 * s); ctx.bezierCurveTo(-0.17 * s, -0.17 * s, 0.13 * s, -0.175 * s, 0.31 * s, 0.0); ctx.bezierCurveTo(0.15 * s, 0.115 * s, -0.15 * s, 0.12 * s, -0.31 * s, 0.015 * s); };
      ctx.save(); lids(); ctx.clip();
      const white = ctx.createLinearGradient(-0.31 * s, 0, 0.31 * s, 0);
      for (const [at, shade] of [[0, 0.74], [0.35, 0.97], [0.65, 0.97], [1, 0.74]]) white.addColorStop(at, `rgb(${[232, 222, 216].map(c => Math.round(c * shade * person.dim)).join(",")})`);
      ctx.fillStyle = white; ctx.fillRect(-s, -s, 2 * s, 2 * s);
      const ix = person.gazeX * 0.09 * s, iy = -0.02 * s + person.gazeY * 0.045 * s, r = 0.138 * s;
      const iris = ctx.createRadialGradient(ix, iy, r * 0.25, ix, iy, r);
      for (const [at, c] of [[0, [120, 88, 56]], [0.7, [78, 54, 34]], [1, [24, 18, 14]]]) iris.addColorStop(at, `rgb(${c.map(v => Math.round(v * person.dim)).join(",")})`);
      ctx.fillStyle = iris; ctx.beginPath(); ctx.arc(ix, iy, r, 0, 6.283); ctx.fill();
      ctx.fillStyle = "#060607"; ctx.beginPath(); ctx.arc(ix, iy, r * 0.42, 0, 6.283); ctx.fill();
      ctx.fillStyle = `rgba(255,255,255,${0.8 * person.dim})`; ctx.beginPath(); ctx.arc(ix - r * 0.38, iy - r * 0.4, r * 0.15, 0, 6.283); ctx.fill();
      const lidShadow = ctx.createLinearGradient(0, -0.17 * s, 0, 0.02 * s); lidShadow.addColorStop(0, "rgba(30,14,10,.3)"); lidShadow.addColorStop(1, "rgba(30,14,10,0)");
      ctx.fillStyle = lidShadow; ctx.fillRect(-s, -s, 2 * s, 2 * s);
      ctx.restore();
      ctx.strokeStyle = `rgba(44,28,20,${0.6 * person.dim})`; ctx.lineWidth = 0.024 * s; ctx.lineCap = "round";     // upper lash line, heavier toward the outer corner
      ctx.beginPath(); ctx.moveTo(-0.31 * s, 0.015 * s); ctx.bezierCurveTo(-0.17 * s, -0.17 * s, 0.13 * s, -0.175 * s, 0.31 * s, 0.0); ctx.stroke();
      ctx.strokeStyle = `rgba(110,64,50,${0.25 * person.dim})`; ctx.lineWidth = 0.014 * s;
      ctx.beginPath(); ctx.moveTo(0.31 * s, 0.0); ctx.bezierCurveTo(0.15 * s, 0.115 * s, -0.15 * s, 0.12 * s, -0.31 * s, 0.015 * s); ctx.stroke();
      ctx.restore();
    });
    const points = FACE_POINTS.map(p => project(person, rows, p)), xs = points.map(p => p.x), ys = points.map(p => p.y);
    return [Math.min(...xs), Math.min(...ys), Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)];
  }
  return { shade, features };
}
