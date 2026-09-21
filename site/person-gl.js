// The person in the camera preview: a professionally made, photo-textured character from the
// Microsoft Rocketbox avatar library (MIT licence, see assets/CREDITS.md), converted by
// dev/make-avatar.py and lit by this small WebGL renderer. The head turns and nods by bending
// the neck in the vertex shader; the shoulders stay where they are.
const CAMERA = 58, PIVOT = [0, -13, -5];                 // camera distance (cm); the top of the spine, relative to the eyes
const FACE_POINTS = [[0, 7.5, 1], [0, -12.6, 1.5], [-7.3, -2, -3], [7.3, -2, -3], [0, -4.6, 2.6]];   // hairline, chin, cheeks, nose

const VERTEX = `
attribute vec3 position; attribute vec3 normal; attribute vec3 uvm;      // uvm: u, v, material
uniform mat3 turn; uniform vec3 pivot; uniform vec3 place; uniform vec2 size;
varying vec3 vWorld; varying vec3 vNormal; varying vec3 vUvm;
void main() {
  float follow = smoothstep(-21.5, -11.5, position.y + 0.4 * position.z);   // head follows fully, neck twists, shoulders stay
  vWorld = mix(position, pivot + turn * (position - pivot), follow);
  vNormal = normalize(mix(normal, turn * normal, follow)); vUvm = uvm;
  float k = place.z * ${CAMERA}.0 / (${CAMERA}.0 - vWorld.z);
  gl_Position = vec4((place.x + vWorld.x * k) / size.x * 2.0 - 1.0, 1.0 - (place.y - vWorld.y * k) / size.y * 2.0, -vWorld.z / 160.0, 1.0);
}`;
const FRAGMENT = `
#extension GL_OES_standard_derivatives : enable
precision highp float;
uniform sampler2D headMap; uniform sampler2D bodyMap; uniform sampler2D hairMap; uniform sampler2D headNormal;
uniform float dim; uniform float soft;                     // soft = 1 on the blended pass that draws only hair edges
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
  } else if (material > 0.5) {                               // head: skin, plus the eyeballs and mouth that live in the same texture
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

const loadImage = url => new Promise((resolve, reject) => { const image = new Image(); image.onload = () => resolve(image); image.onerror = () => reject(new Error("missing " + url)); image.src = url; });

function rotationOf(person) {              // mirrored like a selfie view; pitch > 0 looks down
  const rad = Math.PI / 180, cy = Math.cos(-person.yaw * rad), sy = Math.sin(-person.yaw * rad), cp = Math.cos(person.pitch * rad), sp = Math.sin(person.pitch * rad), cr = Math.cos(person.roll * rad), sr = Math.sin(person.roll * rad);
  return [[cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp], [cp * sr, cp * cr, -sp], [-sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp]];
}

/** Loads the avatar in `folder`. Resolves to shade(person, w, h) → { canvas, box }; rejects without WebGL or the files. */
export async function loadPerson(folder) {
  const canvas = document.createElement("canvas"), gl = canvas.getContext("webgl", { antialias: true, alpha: true, premultipliedAlpha: true });
  if (!gl || !gl.getExtension("OES_standard_derivatives")) throw new Error("WebGL with derivatives is not available");
  const at = name => new URL(name, folder).href;
  const [bin, ...images] = await Promise.all([fetch(at("person.bin")).then(r => { if (!r.ok) throw new Error("missing person.bin"); return r.arrayBuffer(); }), ...["head.jpg", "body.jpg", "hair.webp", "head_normal.jpg"].map(name => loadImage(at(name)))]);
  // Solid triangles first, hair last, so the blended pass can draw just the hair's range.
  const source = new Float32Array(bin), vertices = new Float32Array(source.length), TRI = 27;
  let write = 0, hairStart = 0;
  for (const wantHair of [false, true]) {
    if (wantHair) hairStart = write / 9;
    for (let t = 0; t < source.length; t += TRI) if ((source[t + 8] > 1.5) === wantHair) { vertices.set(source.subarray(t, t + TRI), write); write += TRI; }
  }
  const count = vertices.length / 9;

  const compile = (type, source) => { const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const program = gl.createProgram(); gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX)); gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT)); gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  [["position", 0], ["normal", 3], ["uvm", 6]].forEach(([name, offset]) => { const a = gl.getAttribLocation(program, name); gl.enableVertexAttribArray(a); gl.vertexAttribPointer(a, 3, gl.FLOAT, false, 36, offset * 4); });
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  images.forEach((image, unit) => {
    gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image); gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  });
  const u = Object.fromEntries(["turn", "pivot", "place", "size", "dim", "soft", "headMap", "bodyMap", "hairMap", "headNormal"].map(name => [name, gl.getUniformLocation(program, name)]));
  ["headMap", "bodyMap", "hairMap", "headNormal"].forEach((name, unit) => gl.uniform1i(u[name], unit));
  gl.uniform3fv(u.pivot, PIVOT); gl.enable(gl.DEPTH_TEST); gl.clearColor(0, 0, 0, 0); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

  return function shade(person, width, height) {
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    const r = rotationOf(person);
    gl.viewport(0, 0, width, height); gl.depthMask(true); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);   // clear honours the depth mask the hair pass leaves off
    gl.uniformMatrix3fv(u.turn, false, [r[0][0], r[1][0], r[2][0], r[0][1], r[1][1], r[2][1], r[0][2], r[1][2], r[2][2]]);   // column-major
    gl.uniform3f(u.place, person.x, person.y, person.scale); gl.uniform2f(u.size, width, height); gl.uniform1f(u.dim, person.dim);
    gl.disable(gl.BLEND); gl.uniform1f(u.soft, 0); gl.drawArrays(gl.TRIANGLES, 0, count);        // everything solid
    gl.enable(gl.BLEND); gl.depthMask(false); gl.uniform1f(u.soft, 1); gl.drawArrays(gl.TRIANGLES, hairStart, count - hairStart);   // then the soft edges of the hair

    const points = FACE_POINTS.map(p => {
      const d = p.map((c, i) => c - PIVOT[i]), w = p.map((c, i) => PIVOT[i] + r[i][0] * d[0] + r[i][1] * d[1] + r[i][2] * d[2]), k = person.scale * CAMERA / (CAMERA - w[2]);
      return [person.x + w[0] * k, person.y - w[1] * k];
    });
    const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
    return { canvas, box: [Math.min(...xs), Math.min(...ys), Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)] };
  };
}
