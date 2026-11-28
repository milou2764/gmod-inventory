"""Close look at one playermodel: four views (front, side, back, 3/4 from above) of a bodygroup selection.

    python look.py <model path> <out.jpg> [bodypart=value ...] [--bare] [--head]

--bare: every bodypart with an empty choice set to it first (then the given values). --head: frame the
head and shoulders only. Prints the bodyparts (index name: submodels, * = empty choice) and the selection.
Needs MDL_EXTRA_DIRS (set by the caller: the collection folders).
"""
import sys

TOOLS = r"C:/Program Files (x86)/Steam/steamapps/common/GarrysMod/garrysmod/addons/advanced-inventory/tools"
sys.path.insert(0, TOOLS)
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

import mdl_render as mr  # noqa: E402
import modelgear_pack as mp  # noqa: E402
import mount_check as mc  # noqa: E402

args = sys.argv[1:]
bare, head = "--bare" in args, "--head" in args
args = [a for a in args if not a.startswith("--")]
model, out = args[0], args[1]
parts = mp.bodyparts(model)
sel = {b: 0 for b in range(len(parts))}
if bare:
    sel.update(mp.empty_choices(parts))
for a in args[2:]:
    k, v = a.split("=")
    sel[int(k)] = int(v)
for b, (name, subs) in enumerate(parts):
    print(f"{b} {name}: " + ", ".join(f"{s}{'*' if not m else ''}" + ("<" if sel[b] == k else "") for k, (s, m) in enumerate(subs)))
P, N, uv, tris, mats = mp.posed(model, sel)
frame = P
if head:
    z = P[:, 2]
    frame = P[z > z.max() - 22]
face = mc.facing_yaw(model)
S = 420
views = []
for yaw, pitch in ((10, 5), (90, 5), (190, 5), (40, 35)):
    img = mr.rasterize(P, N, uv, tris, mats, face + yaw, pitch, frame, size=S)
    bg = Image.new("RGBA", img.size, (104, 108, 116, 255))
    bg.alpha_composite(img)
    views.append(bg.convert("RGB"))
sheet = Image.new("RGB", (4 * S, S + 20), (22, 22, 24))
for k, v in enumerate(views):
    sheet.paste(v, (k * S, 0))
ImageDraw.Draw(sheet).text((4, S + 3), f"{model}  sel={sel}", fill=(250, 220, 110))
sheet.save(out, quality=88)
print("->", out)
