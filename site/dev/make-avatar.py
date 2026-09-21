#!/usr/bin/env python3
"""Turns a Microsoft Rocketbox avatar (MIT licence) into what the landing page's camera preview loads:
a chest-up, indexed, skinned mesh, its skeleton, and web-sized textures.

    python3 dev/make-avatar.py <avatar.fbx> <output dir> [<textures dir> <texture prefix, e.g. m014>]

Output (textures only when a textures dir is given):
  mesh.bin   float32 x17 per vertex: position(3) normal(3) uv(2) material(1) bones(4) weights(4), then uint16 triangle
             indices with the hair triangles last. Centimetres, y up, z toward the camera, origin between the eyes.
             Materials: 0 body, 1 head, 2 hair and lashes.
  rig.json   { vertices, indices, hairStart, bones: [{ name, parent, bind: 4x4 column-major, in the same space }] }
  head.jpg body.jpg head_normal.jpg hair.webp
"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbx import parse, find, child

fbx_path, out = sys.argv[1:3]
texture_dir, prefix = (sys.argv[3], sys.argv[4]) if len(sys.argv) > 4 else (None, None)
os.makedirs(out, exist_ok=True)
CROP = -46                                                     # keep everything above mid-chest (cm below the eyes)

# ---- small 4x4 helpers, column-major like the FBX arrays ----
def mul(a, b): return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]
def apply(m, p, w=1.0): return tuple(m[0 + r] * p[0] + m[4 + r] * p[1] + m[8 + r] * p[2] + m[12 + r] * w for r in range(3))

# ---- read the FBX ----
_, nodes = parse(fbx_path)
objects = find(nodes, "Objects")[0]["children"]
name = {o["props"][0]: o["props"][1].split("\x00")[0] for o in objects}
kind = {o["props"][0]: (o["name"], o["props"][2] if len(o["props"]) > 2 else "") for o in objects}
parent_of, bone_of_cluster = {}, {}
for c in find(nodes, "Connections")[0]["children"]:
    a, b = c["props"][1], c["props"][2]
    if kind.get(a, ("",))[0] == "Model" and kind.get(b, ("",))[0] == "Model": parent_of[a] = b
    if kind.get(a, ("",))[0] == "Model" and kind.get(b) == ("Deformer", "Cluster"): bone_of_cluster[b] = a

geometry = find(objects, "Geometry")[0]
points = child(geometry, "Vertices")["props"][0]
corners = child(geometry, "PolygonVertexIndex")["props"][0]
normals = child(child(geometry, "LayerElementNormal"), "Normals")["props"][0]
uv_layer = child(geometry, "LayerElementUV")
uvs, uv_index = child(uv_layer, "UV")["props"][0], child(uv_layer, "UVIndex")["props"][0]
materials = child(child(geometry, "LayerElementMaterial"), "Materials")["props"][0]
assert len(corners) == 3 * len(materials), "expected a triangulated mesh"

clusters = {}
for o in objects:
    if o["name"] == "Deformer" and o["props"][2] == "Cluster" and child(o, "Indexes"):
        clusters[bone_of_cluster[o["props"][0]]] = (child(o, "Indexes")["props"][0], child(o, "Weights")["props"][0], child(o, "Transform")["props"][0], child(o, "TransformLink")["props"][0])
# Each cluster stores the mesh's transform relative to its bone, so bone * relative is the mesh's world transform at bind time.
mesh_world = mul(*[clusters[b][k] for b in [next(iter(clusters))] for k in (3, 2)])
for _, _, relative, link in clusters.values():
    assert max(abs(x - y) for x, y in zip(mul(link, relative), mesh_world)) < 1e-3, "clusters disagree about the mesh transform"

# ---- world space → ours: x to the viewer's right, y up, z toward the camera, origin between the eyes ----
world = [apply(mesh_world, points[i:i + 3]) for i in range(0, len(points), 3)]
extent = [max(p[a] for p in world) - min(p[a] for p in world) for a in range(3)]
up = max(range(3), key=lambda a: max(p[a] for p in world))
side = max((a for a in range(3) if a != up), key=lambda a: extent[a])
depth = 3 - up - side
eyes = [apply(clusters[b][3], (0, 0, 0)) for b in clusters if name[b] in ("Bip01 LEye", "Bip01 REye")]
assert len(eyes) == 2, "expected two eye bones"
centre = [(eyes[0][a] + eyes[1][a]) / 2 for a in range(3)]
nose = [apply(clusters[b][3], (0, 0, 0)) for b in clusters if name[b] == "Bip01 MNose"][0]
front = 1 if nose[depth] > centre[depth] else -1                 # the nose is in front of the eyes
rows = [[0, 0, 0] for _ in range(3)]
rows[1][up] = 1; rows[2][depth] = front; rows[0][side] = 1
if rows[0][0] * (rows[1][1] * rows[2][2] - rows[1][2] * rows[2][1]) - rows[0][1] * (rows[1][0] * rows[2][2] - rows[1][2] * rows[2][0]) + rows[0][2] * (rows[1][0] * rows[2][1] - rows[1][1] * rows[2][0]) < 0: rows[0][side] = -1
offset = [-sum(rows[r][a] * centre[a] for a in range(3)) for r in range(3)]
to_ours = [rows[0][0], rows[1][0], rows[2][0], 0, rows[0][1], rows[1][1], rows[2][1], 0, rows[0][2], rows[1][2], rows[2][2], 0, offset[0], offset[1], offset[2], 1]
mesh_to_ours = mul(to_ours, mesh_world)
print("up axis", "xyz"[up], "| faces", "+-"[front < 0] + "xyz"[depth], "| eyes %.1f cm apart" % abs(eyes[0][side] - eyes[1][side]))

# ---- skin weights per control point, four strongest ----
influences = {}
for bone, (indexes, weights, _, _) in clusters.items():
    for i, w in zip(indexes, weights):
        if w > 1e-4: influences.setdefault(i, []).append((w, bone))

# ---- triangles above the crop, de-duplicated into an indexed mesh ----
position = [apply(mesh_to_ours, points[i:i + 3]) for i in range(0, len(points), 3)]
vertex_of, vertices, solid, hair, used_bones = {}, [], [], [], set()
for t, material in enumerate(materials):
    tri = []
    for c in range(3):
        k = t * 3 + c
        v = corners[k] if corners[k] >= 0 else ~corners[k]
        n = apply(mesh_to_ours, normals[k * 3:k * 3 + 3], 0.0)
        key = (v, uv_index[k], round(n[0], 2), round(n[1], 2), round(n[2], 2))
        tri.append((key, v, n, (uvs[uv_index[k] * 2], uvs[uv_index[k] * 2 + 1])))
    if min(position[v][1] for _, v, _, _ in tri) < CROP: continue
    for key, v, n, uv in tri:
        if key not in vertex_of:
            best = sorted(influences.get(v, []), reverse=True)[:4]
            total = sum(w for w, _ in best) or 1.0
            used_bones.update(b for _, b in best)
            vertex_of[key] = len(vertices); vertices.append((position[v], n, uv, material, [(b, w / total) for w, b in best]))
        (hair if material == 2 else solid).append(vertex_of[key])
assert len(vertices) < 65536

# ---- the bones those vertices need, plus their ancestors, parents first ----
needed = set()
for b in used_bones:
    while b in clusters and b not in needed: needed.add(b); b = parent_of.get(b)
def depth_of(b): return 0 if parent_of.get(b) not in needed else 1 + depth_of(parent_of[b])
order = sorted(needed, key=lambda b: (depth_of(b), name[b]))
index_of = {b: i for i, b in enumerate(order)}
bones = [{"name": name[b].replace("Bip01 ", ""), "parent": index_of.get(parent_of.get(b), -1), "bind": [round(x, 5) for x in mul(to_ours, clusters[b][3])]} for b in order]

data = []
for p, n, uv, material, weights in vertices:
    weights = weights + [(order[0], 0.0)] * (4 - len(weights))
    data.extend(p + n + uv + (float(material),) + tuple(float(index_of[b]) for b, _ in weights) + tuple(w for _, w in weights))
indices = solid + hair
with open(os.path.join(out, "mesh.bin"), "wb") as f:
    f.write(struct.pack("<%df" % len(data), *data)); f.write(struct.pack("<%dH" % len(indices), *indices))
json.dump({"vertices": len(vertices), "indices": len(indices), "hairStart": len(solid), "bones": bones}, open(os.path.join(out, "rig.json"), "w"), separators=(",", ":"))
print("vertices", len(vertices), "| triangles", len(indices) // 3, "| bones", len(bones), "| mesh.bin", os.path.getsize(os.path.join(out, "mesh.bin")) // 1024, "KB")

# ---- textures ----
if texture_dir:
    from PIL import Image
    def texture(source, target, size, mode="RGB", **save):
        image = Image.open(os.path.join(texture_dir, "%s_%s.tga" % (prefix, source))).convert(mode).resize((size, size), Image.LANCZOS)
        image.save(os.path.join(out, target), **save); print(target, os.path.getsize(os.path.join(out, target)) // 1024, "KB")
    texture("head_color", "head.jpg", 1024, quality=88)
    texture("body_color", "body.jpg", 1024, quality=85)
    texture("head_normal", "head_normal.jpg", 1024, quality=88)
    hair_source = os.path.join(texture_dir, prefix + "_opacity_color.tga")
    if os.path.exists(hair_source) and os.path.getsize(hair_source) > 1024: texture("opacity_color", "hair.webp", 1024, mode="RGBA", quality=82)
    else: Image.new("RGBA", (4, 4), (0, 0, 0, 0)).save(os.path.join(out, "hair.webp")); print("no hair layer: the hair is part of the head texture")
