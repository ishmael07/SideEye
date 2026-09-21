#!/usr/bin/env python3
"""Turns a Microsoft Rocketbox avatar (MIT licence) into the chest-up mesh and web-sized textures the
landing page's camera preview uses.

    python3 dev/make-avatar.py <avatar.fbx> <textures dir> <texture prefix, e.g. m014> <output dir>

Output: person.bin (float32, 9 per vertex: x y z  nx ny nz  u v  material; centimetres, y up, z toward the
camera, origin between the eyes; materials 0 body, 1 head, 2 hair/lashes), head.jpg, body.jpg, head_normal.jpg, hair.png.
"""
import os, struct, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbx import parse, find, child

fbx_path, texture_dir, prefix, out = sys.argv[1:5]
os.makedirs(out, exist_ok=True)
_, nodes = parse(fbx_path)
geometry = find(find(nodes, "Objects")[0]["children"], "Geometry")[0]
points = child(geometry, "Vertices")["props"][0]
corners = child(geometry, "PolygonVertexIndex")["props"][0]
normals = child(child(geometry, "LayerElementNormal"), "Normals")["props"][0]
uv_layer = child(geometry, "LayerElementUV")
uvs, uv_index = child(uv_layer, "UV")["props"][0], child(uv_layer, "UVIndex")["props"][0]
materials = child(child(geometry, "LayerElementMaterial"), "Materials")["props"][0]
assert len(corners) == 3 * len(materials), "expected a triangulated mesh"

# Rocketbox geometry is z-up in centimetres. Which way it faces: the nose sticks out furthest at face height.
top = max(points[2::3])
face = [i for i in range(len(points) // 3) if top - 22 < points[i * 3 + 2] < top - 8 and abs(points[i * 3]) < 4]
front = -1 if abs(min(points[i * 3 + 1] for i in face)) > abs(max(points[i * 3 + 1] for i in face)) else 1
nose = max(face, key=lambda i: points[i * 3 + 1] * front)
eye_height = points[nose * 3 + 2] + 4.6                       # eyes sit about 4.6 cm above the nose tip
origin = (0.0, eye_height, points[nose * 3 + 1] * front - 2.5)  # ...and about 2.5 cm behind it
print("faces", "-y" if front < 0 else "+y", "| top of head", round(top, 1), "| eye height", round(eye_height, 1))

def convert(x, y, z): return (x * -front, z - origin[1], y * front - origin[2])   # → x right (viewer's), y up, z toward camera

CROP = -46                                                     # keep everything above mid-chest
data, kept = [], 0
for t, material in enumerate(materials):
    tri = []
    for c in range(3):
        k = t * 3 + c
        v = corners[k] if corners[k] >= 0 else ~corners[k]
        p = convert(*points[v * 3:v * 3 + 3])
        n = (normals[k * 3] * -front, normals[k * 3 + 2], normals[k * 3 + 1] * front)
        tri.append(p + n + (uvs[uv_index[k] * 2], uvs[uv_index[k] * 2 + 1], float(material)))
    if min(v[1] for v in tri) < CROP: continue
    if front > 0: tri = [tri[0], tri[2], tri[1]]                # mirroring x flips the winding
    for v in tri: data.extend(v)
    kept += 1
open(os.path.join(out, "person.bin"), "wb").write(struct.pack("<%df" % len(data), *data))
print("triangles", kept, "of", len(materials), "| person.bin", len(data) * 4 // 1024, "KB")

def texture(name, target, size, mode="RGB", **save):
    image = Image.open(os.path.join(texture_dir, "%s_%s.tga" % (prefix, name))).convert(mode).resize((size, size), Image.LANCZOS)
    image.save(os.path.join(out, target), **save); print(target, os.path.getsize(os.path.join(out, target)) // 1024, "KB")
texture("head_color", "head.jpg", 1024, quality=88)
texture("body_color", "body.jpg", 1024, quality=85)
texture("head_normal", "head_normal.jpg", 1024, quality=88)
hair_source = os.path.join(texture_dir, prefix + "_opacity_color.tga")
if os.path.exists(hair_source) and os.path.getsize(hair_source) > 1024: texture("opacity_color", "hair.webp", 1024, mode="RGBA", quality=82)
else: Image.new("RGBA", (4, 4), (0, 0, 0, 0)).save(os.path.join(out, "hair.webp")); print("no hair layer: the hair is part of the head texture")
