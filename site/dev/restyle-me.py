#!/usr/bin/env python3
"""Restyles the "me" avatar's textures: near-black hair and a younger, clean-shaven face.
Reads the untouched textures from dev/textures and writes assets/person/me/{head.jpg,hair.webp}."""
import os
import numpy as np
from PIL import Image, ImageFilter

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src, out = os.path.join(root, "dev/textures"), os.path.join(root, "assets/person/me")
def blurred(a, radius): return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255

# ---- head map: hair on the scalp, brows; stubble off ----
head = Image.open(os.path.join(src, "me_head_original.jpg")).convert("RGB")
rgb = np.asarray(head).astype(np.float32) / 255
H, W = rgb.shape[:2]
y, x = np.mgrid[0:H, 0:W] / np.array([H, W])[:, None, None]
# Hair vs skin by colour: skin is warm and saturated, hair (even buzzed short over skin) is grey-brown and darker.
r, g, bl = rgb[..., 0], rgb[..., 1], rgb[..., 2]
value = rgb.max(axis=2)
warmth = (r - bl) / (value + 1e-3)
hairness = np.clip((0.34 - warmth) / 0.12, 0, 1) * np.clip((0.92 - value) / 0.3, 0, 1) + np.clip((0.5 - value) / 0.15, 0, 1)
ears = ((x - 0.255) ** 2 / 0.06 ** 2 + (y - 0.36) ** 2 / 0.08 ** 2 < 1) | ((x - 0.745) ** 2 / 0.06 ** 2 + (y - 0.36) ** 2 / 0.08 ** 2 < 1)
face = (np.abs(x - 0.5) < 0.13) & (y > 0.13) & (y < 0.6)                          # eyes, nostrils and lips are dark too; leave them
brows = (y > 0.225) & (y < 0.268) & (np.abs(x - 0.5) < 0.16)
where = ((y < 0.6) & ~ears & ~face) | brows
# The fade in front of and above the ears is skin with sparse stubble in the photo. He gets fuller hair there:
# grown-in dark, fading out toward the face and down past the ear.
temples = (np.abs(x - 0.5) > 0.13) & (np.abs(x - 0.5) < 0.21) & (y > 0.1) & (y < 0.31) & ~ears      # the strip beside the face oval (checked against the mesh's UVs)
rng = np.random.default_rng(7)
strands = blurred(rng.random((H, W)).astype(np.float32), 0.8) ; strands = np.clip((strands - 0.42) / 0.2, 0, 1)   # short hairs, not a wash
grown = temples * np.clip((np.abs(x - 0.5) - 0.13) / 0.03, 0, 1) * np.clip((0.31 - y) / 0.05, 0, 1) * (0.35 + 0.5 * strands)
hair = blurred(np.clip(np.maximum(hairness * where, grown), 0, 1), 1.5)
black = np.array([0.05, 0.04, 0.035]) + rgb * 0.18                            # keeps the strand detail, kills the brown
rgb = rgb * (1 - hair[..., None]) + black * hair[..., None]

# stubble: the lower face and neck. Smooth the speckle, then lift toward the skin tone.
soft = blurred(rgb, 3.2)
lower = np.clip((y - 0.36) / 0.06, 0, 1) * (1 - np.clip((y - 0.72) / 0.08, 0, 1)) * (np.abs(x - 0.5) < 0.3) * (1 - hair)
skin = soft + np.array([0.06, 0.035, 0.025])                                    # a little warmer and lighter, no shadow of beard
rgb = rgb * (1 - lower[..., None] * 0.85) + skin * lower[..., None] * 0.85
face = (y > 0.14) & (y < 0.75) & (np.abs(x - 0.5) < 0.32)                       # a touch smoother everywhere on the face, like young skin
rgb = np.where(face[..., None], rgb * 0.55 + blurred(rgb, 1.1) * 0.45, rgb)
Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out, "head.jpg"), quality=90)

# ---- hair cards ----
cards = np.asarray(Image.open(os.path.join(src, "me_hair_original.webp")).convert("RGBA")).astype(np.float32) / 255
cards[..., :3] = np.array([0.05, 0.04, 0.035]) + cards[..., :3] * 0.24
Image.fromarray((np.clip(cards, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out, "hair.webp"), quality=84)
print("wrote head.jpg and hair.webp")
