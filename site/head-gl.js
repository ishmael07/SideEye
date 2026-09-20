// WebGL shading for the person in head.js: per-pixel lighting instead of flat triangles.
// Skin gets wrapped diffuse light with a warm terminator, a soft highlight and a cool rim from
// the window; hair gets strand texture and a sheen. Geometry is posed on the CPU (head.js) and
// uploaded every frame, which is cheap at a few thousand vertices.
import { MESH, HAIR, CLOTH } from "./head.js";

const VERTEX = `
attribute vec2 screen; attribute float depth; attribute vec3 normal; attribute vec3 albedo; attribute vec3 extra;   // extra: kind, occlusion, along
uniform vec2 size; varying vec3 vNormal; varying vec3 vAlbedo; varying vec3 vExtra; varying vec2 vScreen;
void main() {
  vNormal = normal; vAlbedo = albedo; vExtra = extra; vScreen = screen;
  gl_Position = vec4(screen.x / size.x * 2.0 - 1.0, 1.0 - screen.y / size.y * 2.0, -depth / 80.0, 1.0);
}`;
const FRAGMENT = `
precision mediump float;
uniform float dim; varying vec3 vNormal; varying vec3 vAlbedo; varying vec3 vExtra; varying vec2 vScreen;
float hash(float n) { return fract(sin(n * 91.345) * 47453.31); }
void main() {
  vec3 n = normalize(vNormal), key = normalize(vec3(-0.36, 0.46, 0.81)), fill = normalize(vec3(0.7, -0.1, 0.55)), view = vec3(0.0, 0.0, 1.0);
  float lit = dot(n, key), wrap = clamp((lit + 0.4) / 1.4, 0.0, 1.0), soft = wrap * wrap * (3.0 - 2.0 * wrap);
  float kind = vExtra.x, shine = pow(max(dot(n, normalize(key + view)), 0.0), 28.0), edge = pow(1.0 - max(n.z, 0.0), 3.0);
  vec3 colour;
  if (kind > ${HAIR - 0.5} && kind < ${HAIR + 0.5}) {
    float strand = 0.78 + 0.34 * hash(floor(vExtra.z * 260.0)) + 0.12 * hash(floor(vExtra.z * 90.0));
    colour = vAlbedo * strand * (0.3 + 1.0 * soft) + vec3(0.55, 0.45, 0.36) * pow(max(dot(n, normalize(key + view)), 0.0), 9.0) * 0.5 * strand;
  } else if (kind > ${CLOTH - 0.5} && kind < ${CLOTH + 0.5}) {
    colour = vAlbedo * (0.34 + 0.9 * soft) + vec3(0.6, 0.7, 0.9) * edge * 0.06;
  } else {
    vec3 light = vec3(1.0, 0.97, 0.93) * soft * 0.8 + vec3(0.31, 0.29, 0.31) + vec3(0.9, 0.62, 0.5) * clamp(dot(n, fill), 0.0, 1.0) * 0.16;
    float terminator = smoothstep(-0.35, 0.05, lit) * (1.0 - smoothstep(0.05, 0.55, lit));
    colour = vAlbedo * light + vAlbedo * vec3(0.9, 0.3, 0.2) * terminator * 0.09         // light bleeding through skin at the shadow edge
      + vec3(1.0) * shine * 0.08 + vec3(0.62, 0.74, 1.0) * edge * step(n.x, 0.1) * 0.2;       // soft highlight, cool rim from the window
  }
  gl_FragColor = vec4(colour * vExtra.y * dim, 1.0);
}`;

export function createHeadGL() {
  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl", { antialias: true, alpha: true, premultipliedAlpha: true });
  if (!gl) return null;
  const compile = (type, source) => { const shader = gl.createShader(type); gl.shaderSource(shader, source); gl.compileShader(shader); if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader)); return shader; };
  let program;
  try {
    program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX)); gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT)); gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  } catch (error) { console.warn("SideEye demo: WebGL shading unavailable, using the canvas renderer.", error); return null; }
  gl.useProgram(program);

  const STRIDE = 12, data = new Float32Array(MESH.count * STRIDE), buffer = gl.createBuffer(), indices = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indices); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(MESH.tris), gl.STATIC_DRAW);
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  let offset = 0;
  for (const [name, length] of [["screen", 2], ["depth", 1], ["normal", 3], ["albedo", 3], ["extra", 3]]) {
    const at = gl.getAttribLocation(program, name);
    if (at >= 0) { gl.enableVertexAttribArray(at); gl.vertexAttribPointer(at, length, gl.FLOAT, false, STRIDE * 4, offset * 4); }
    offset += length;
  }
  const uSize = gl.getUniformLocation(program, "size"), uDim = gl.getUniformLocation(program, "dim");
  gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.clearColor(0, 0, 0, 0);

  /** Shades the person most recently posed with poseHead(). Returns the canvas to composite. */
  return function shade(person, width, height) {
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    const base = [person.skin, person.hair, person.skin, person.shirt, person.skin];
    for (let i = 0, o = 0; i < MESH.count; i++, o += STRIDE) {
      const colour = base[MESH.kind[i]];
      data[o] = MESH.px[i]; data[o + 1] = MESH.py[i]; data[o + 2] = MESH.wz[i];
      data[o + 3] = MESH.nx[i]; data[o + 4] = MESH.ny[i]; data[o + 5] = MESH.nz[i];
      data[o + 6] = colour[0] / 255 * MESH.tint[i * 3]; data[o + 7] = colour[1] / 255 * MESH.tint[i * 3 + 1]; data[o + 8] = colour[2] / 255 * MESH.tint[i * 3 + 2];
      data[o + 9] = MESH.kind[i]; data[o + 10] = MESH.occlusion[i]; data[o + 11] = MESH.along[i];
    }
    gl.viewport(0, 0, width, height); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.DYNAMIC_DRAW);
    gl.uniform2f(uSize, width, height); gl.uniform1f(uDim, person.dim);
    gl.drawElements(gl.TRIANGLES, MESH.tris.length, gl.UNSIGNED_SHORT, 0);
    return canvas;
  };
}
