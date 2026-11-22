"""Contact sheets of the per-playermodel fits (dev tool, not in the .gma): each worn item on every
playermodel of playermodels.txt, and a weapon loadout (AR2, RPG, pistol) on every playermodel, using
lua/advinv/cl_fits_data.lua like the game does.

    python fit_sheets.py <out_dir> [playermodels.txt]
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdl_render as mr  # noqa: E402
import mount_check as mc  # noqa: E402
import weapon_check as wc  # noqa: E402

TOOLS = Path(__file__).resolve().parent
THUMB, COLS = 150, 10
BACK_ITEMS = {"advinv_jetpack", "advinv_suitcase"}


def weapon_fits():
    p = TOOLS.parent / "lua" / "advinv" / "cl_fits_data.lua"
    out, cur = {}, None
    num = lambda s: np.array([float(x) for x in s.split(",")])
    for line in p.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*\["([^"]+)"\] = \{', line)
        if m:
            cur = out.setdefault(m.group(1), {})
            continue
        m = re.match(r"\s*(\w+) = \{ V\(([^)]*)\), V\(([^)]*)\), A\(([^)]*)\) \},", line)
        if m and cur is not None:
            cur[m.group(1)] = (num(m.group(2)), num(m.group(3)), list(num(m.group(4))))
    return out


def thumb(scene, fit, yaw, pitch, title):
    img = mr.rasterize(*scene, yaw, pitch, fit, size=THUMB)
    bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
    bg.alpha_composite(img)
    bg = bg.convert("RGB")
    d = ImageDraw.Draw(bg)
    d.rectangle((0, THUMB - 13, THUMB, THUMB), fill=(0, 0, 0))
    d.text((3, THUMB - 12), title, fill=(235, 235, 235))
    return bg


def short(model):
    p = model.replace("models/player/", "").replace(".mdl", "")
    return p.replace("group0", "g").replace("hostage/", "")


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    lst = Path(sys.argv[2]) if len(sys.argv) > 2 else TOOLS / "playermodels.txt"
    models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    fits, wfits = mc.model_fits(), weapon_fits()
    items = mc.worn_items()
    mounts, gap = wc.weapon_mounts()
    weapons = wc.weapon_items()
    rows = (len(models) + COLS - 1) // COLS
    sheets = {cls: Image.new("RGB", (COLS * THUMB, rows * THUMB), (30, 30, 34)) for cls, *_ in items}
    sheets["weapons"] = Image.new("RGB", (COLS * THUMB, rows * THUMB), (30, 30, 34))
    for k, pm in enumerate(models):
        try:
            body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
        except Exception as e:  # noqa: BLE001
            print(f"{pm}: skipped ({e})")
            continue
        x, y = (k % COLS) * THUMB, (k // COLS) * THUMB
        for cls, model, att0, _ in items:
            att = mc.attach_for(cls, att0, pm, fits)
            item = mc.place_item(model, att, bones)
            if item is None:
                continue
            ipos = item[0][sorted({t[j] for t in item[3] for j in range(3)})]
            c = (ipos.min(0) + ipos.max(0)) / 2
            r = np.linalg.norm(ipos.max(0) - ipos.min(0)) / 2
            fit = np.r_[ipos, body[0][np.linalg.norm(body[0] - c, axis=1) < r * 1.6 + 4]]
            view = (225, 12) if cls in BACK_ITEMS else (45, 10)
            sheets[cls].paste(thumb(mc.merge(body, item), fit, face + view[0], view[1], short(pm)), (x, y))
        # weapons: AR2 + RPG on the back, pistol on the thigh
        scene = body
        primary = 0.0
        for cat, cls in (("PrimaryWep", "advinv_hl2_ar2"), ("RocketLauncher", "advinv_hl2_rpg"),
                         ("SecondaryWep", "advinv_hl2_pistol")):
            m = mounts[cat]
            f = wfits.get(pm, {}).get(cat)
            if f:
                m = {"bone": m["bone"], "pos": f[0], "out": f[1], "ang": f[2]}
            if m["bone"] not in bones:
                continue
            mesh, thick = wc.place_weapon(weapons[cls][0], m, bones, primary if cat == "RocketLauncher" else 0.0, gap)
            scene = mc.merge(scene, mesh)
            if cat == "PrimaryWep":
                primary = thick
        P = scene[0][sorted({t[j] for t in scene[3] for j in range(3)})]
        sheets["weapons"].paste(thumb(scene, P[P[:, 2] > 20], face + 200, 8, short(pm)), (x, y))
        print(f"{k + 1}/{len(models)} {pm}")
    for name, img in sheets.items():
        img.save(out / f"sheet_{name}.jpg", quality=86)
    print("sheets:", ", ".join(sheets))


if __name__ == "__main__":
    mr.WORK.mkdir(parents=True, exist_ok=True)
    main()
