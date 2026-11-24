"""Contact sheets of the compatibility items (dev tool, not in the .gma): every item of
lua/advinv/sh_compat_data.lua worn on playermodels, with the fits of cl_fits_compat.lua, seen from the
front, three quarters and the side. Needs the addons' folders in MDL_EXTRA_DIRS (see fit_compat.py).

    python compat_sheets.py <out_dir> [--only substring] [playermodel ...]
One image per pack and playermodel: a row per item.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdl_render as mr  # noqa: E402
import mount_check as mc  # noqa: E402

LUA = Path(__file__).resolve().parent.parent / "lua" / "advinv"
SIZE = 170
VIEWS = [("front", 0, 5), ("3/4", 40, 10), ("side", 90, 5), ("back", 180, 5)]
NUM = r"(-?[\d.]+)"


def items():
    t = (LUA / "sh_compat_data.lua").read_text(encoding="utf-8")
    out = []
    for m in re.finditer(r'id = (\d+), class = "([^"]+)", model = "([^"]+)",.*?bone = "([^"]+)"', t, re.S):
        out.append({"id": int(m.group(1)), "class": m.group(2), "model": m.group(3), "bone": m.group(4)})
    return out


def fits():
    t = (LUA / "cl_fits_compat.lua").read_text(encoding="utf-8")
    models = re.findall(r'^    "([^"]+)",$', t.split("local F")[0], re.M)
    out = {}
    for cls, packed in re.findall(r'^    (\w+) = "([^"]*)",$', t, re.M):
        per = {}
        for m, e in zip(models, packed.split("|")):
            if e:
                n = [float(x) for x in e.split()]
                per[m] = (np.array(n[:3]), tuple(n[3:6]), n[6])
        out[cls] = per
    return out


def main():
    args = sys.argv[1:]
    out = Path(args.pop(0))
    only = None
    if args[:1] == ["--only"]:
        args.pop(0)
        only = args.pop(0)
    out.mkdir(parents=True, exist_ok=True)
    pms = args or ["models/player/group01/male_07.mdl"]
    F = fits()
    its = [i for i in items() if not only or only in i["class"]]
    for pm in pms:
        body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
        groups = {}
        for it in its:
            groups.setdefault(it["class"].split("_")[2], []).append(it)
        for g, lst in groups.items():
            for start in range(0, len(lst), 12):
                chunk = lst[start:start + 12]
                sheet = Image.new("RGB", (SIZE * len(VIEWS), SIZE * len(chunk)), (40, 42, 46))
                for row, it in enumerate(chunk):
                    f = F.get(it["class"], {}).get(pm)
                    if not f:
                        continue
                    att = {"bone": it["bone"], "pos": f[0], "ang": f[1], "scale": f[2]}
                    item = mc.place_item(it["model"], att, bones)
                    if item is None:
                        continue
                    ip = item[0][sorted({t[k] for t in item[3] for k in range(3)})]
                    c = (ip.min(0) + ip.max(0)) / 2
                    r = np.linalg.norm(ip.max(0) - ip.min(0)) / 2
                    near = body[0][np.linalg.norm(body[0] - c, axis=1) < r * 1.4 + 3]
                    scene = mc.merge(body, item)
                    for col, (name, yaw, pitch) in enumerate(VIEWS):
                        img = mr.rasterize(*scene, face + yaw, pitch, np.r_[ip, near], size=SIZE)
                        bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
                        bg.alpha_composite(img)
                        lab = f"{it['id']} x{f[2]:g} {name}" if col == 0 else name
                        sheet.paste(mc.label(bg.convert("RGB"), lab), (col * SIZE, row * SIZE))
                name = f"{Path(pm).stem}_{g}_{start // 12}.png"
                sheet.save(out / name)
                print(name, len(chunk))


if __name__ == "__main__":
    mr.WORK.mkdir(parents=True, exist_ok=True)
    main()
