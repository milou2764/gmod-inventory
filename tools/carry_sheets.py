"""Contact sheets of the carry modes (dev tool, not in the .gma): each long gun in each of its
modes on every playermodel, placed from lua/advinv/cl_carry_data.lua like the game does
(the playermodel's alias set, or "default").

    python carry_sheets.py <out_dir> [playermodels.txt] [--weapon weapon_ar2] [--mode back_carry]
    python carry_sheets.py <out_dir> --one models/player/group01/male_07.mdl   (all modes, 4 views)
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import mount_check as mc  # noqa: E402
from fit_carry import WEAPONS, MODES  # noqa: E402

TOOLS = Path(__file__).resolve().parent
DATA = TOOLS.parent / "lua" / "advinv" / "cl_carry_data.lua"
THUMB, COLS = 150, 10
VIEW = {"sling_up": 200, "sling_down": 180, "front_hang": 20}


def carry_data():
    sets, aliases, cur, wcls, stack, cur_s = {}, {}, None, None, {}, None
    num = lambda s: [float(x) for x in s.split(",")]
    section = None
    for line in DATA.read_text(encoding="utf-8").splitlines():
        if line.startswith("AdvInv.CarryOffsets"):
            section = "o"
        elif line.startswith("AdvInv.CarryAliases"):
            section = "a"
        elif line.startswith("AdvInv.CarryStack"):
            section = "s"
        elif line.startswith("AdvInv."):
            section = None
        if section == "o":
            m = re.match(r'    \["([^"]+)"\] = \{', line)
            if m:
                cur = sets.setdefault(m.group(1), {})
                continue
            m = re.match(r"        (\w+) = \{$", line)
            if m:
                wcls = cur.setdefault(m.group(1), {})
                continue
            m = re.match(r'\s*(\w+) = \{ "([^"]+)", V\(([^)]*)\), A\(([^)]*)\), V\(([^)]*)\) \},', line)
            if m:
                wcls[m.group(1)] = {"bone": m.group(2), "pos": np.array(num(m.group(3))),
                                    "ang": num(m.group(4)), "out": np.array(num(m.group(5)))}
        elif section == "s":
            m = re.match(r'    \["([^"]+)"\] = \{', line)
            if m:
                cur_s = stack.setdefault(m.group(1), {})
                continue
            m = re.match(r'\s*\["([^"]+)"\] = (-?[\d.]+),', line)
            if m:
                cur_s[m.group(1)] = float(m.group(2))
        elif section == "a":
            m = re.match(r'\s*\["([^"]+)"\] = "([^"]+)",', line)
            if m:
                aliases[m.group(1)] = m.group(2)
    return sets, aliases, stack


def weapon_mesh(path, e, bones, push=0.0):
    pos, nrm, uv, tris, mats = anim0.posed_mesh(path)
    Bw = bones[e["bone"]]
    M = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    t = Bw[:3, :3] @ (e["pos"] + push * e["out"] / np.linalg.norm(e["out"])) + Bw[:3, 3]
    return pos @ M.T + t, nrm @ M.T, uv, tris, mats


def pairs(out, pm, sets, aliases, stack):
    """The launcher with each primary weapon in each mode, on one playermodel."""
    body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
    name = aliases.get(pm, "default")
    s, st = sets[name], stack.get(name, {})
    combos = [(lm, cls, pm_) for lm in s["weapon_rpg"] for cls in WEAPONS if cls != "weapon_rpg"
              for pm_ in s[cls] if f"weapon_rpg {lm}|{cls} {pm_}" in st]
    sheet = Image.new("RGB", (4 * 220, ((len(combos) + 1) // 2) * 220), (30, 30, 34))
    for k, (lm, cls, pmode) in enumerate(combos):
        push = st[f"weapon_rpg {lm}|{cls} {pmode}"]
        scene = mc.merge(body, weapon_mesh(WEAPONS["weapon_rpg"][0], s["weapon_rpg"][lm], bones, max(push, 0)))
        scene = mc.merge(scene, weapon_mesh(WEAPONS[cls][0], s[cls][pmode], bones, max(-push, 0)))
        for c, yaw in enumerate((180, 270)):
            sheet.paste(thumb(scene, face + yaw, 5, f"rpg {lm} + {cls[7:]} {pmode} {push:+.1f}", 220),
                        (((k % 2) * 2 + c) * 220, (k // 2) * 220))
    sheet.save(out / f"carry_pairs_{Path(pm).stem}.jpg", quality=88)


def thumb(scene, yaw, pitch, title, size=THUMB):
    P = scene[0][sorted({t[j] for t in scene[3] for j in range(3)})]
    img = mr.rasterize(*scene, yaw, pitch, P, size=size)
    bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
    bg.alpha_composite(img)
    bg = bg.convert("RGB")
    d = ImageDraw.Draw(bg)
    d.rectangle((0, size - 13, size, size), fill=(0, 0, 0))
    d.text((3, size - 12), title, fill=(235, 235, 235))
    return bg


def short(model):
    return model.replace("models/player/", "").replace(".mdl", "").replace("group0", "g")


def one(out, pm, sets, aliases):
    body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
    s = sets[aliases.get(pm, "default")]
    views = (("front", 0, 5), ("back", 180, 5), ("right", 270, 5), ("left", 90, 5))
    rows = [(cls, mode) for cls in WEAPONS for mode in MODES if mode in s[cls]]
    sheet = Image.new("RGB", (len(views) * 220, len(rows) * 220), (30, 30, 34))
    for r, (cls, mode) in enumerate(rows):
        scene = mc.merge(body, weapon_mesh(WEAPONS[cls][0], s[cls][mode], bones))
        for c, (name, yaw, pitch) in enumerate(views):
            sheet.paste(thumb(scene, face + yaw, pitch, f"{cls[7:]} {mode} {name}", 220), (c * 220, r * 220))
    sheet.save(out / f"carry_{Path(pm).stem}.jpg", quality=88)


def main():
    args = sys.argv[1:]
    out = Path(args.pop(0))
    out.mkdir(parents=True, exist_ok=True)
    opt = {}
    while any(k in args for k in ("--weapon", "--mode", "--one", "--pairs")):
        for k in ("--weapon", "--mode", "--one", "--pairs"):
            if k in args:
                i = args.index(k)
                opt[k] = args[i + 1]
                del args[i:i + 2]
    sets, aliases, stack = carry_data()
    if "--pairs" in opt:
        pairs(out, opt["--pairs"], sets, aliases, stack)
        return
    if "--one" in opt:
        one(out, opt["--one"], sets, aliases)
        return
    lst = Path(args[0]) if args else TOOLS / "playermodels.txt"
    models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    combos = [(cls, mode) for cls in WEAPONS for mode in MODES
              if (opt.get("--weapon", cls) == cls and opt.get("--mode", mode) == mode)
              and mode in sets["default"][cls]]
    rows = (len(models) + COLS - 1) // COLS
    sheets = {c: Image.new("RGB", (COLS * THUMB, rows * THUMB), (30, 30, 34)) for c in combos}
    for k, pm in enumerate(models):
        body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
        s = sets[aliases.get(pm, "default")]
        x, y = (k % COLS) * THUMB, (k // COLS) * THUMB
        for cls, mode in combos:
            e = s[cls][mode]
            if e["bone"] not in bones:
                continue
            scene = mc.merge(body, weapon_mesh(WEAPONS[cls][0], e, bones))
            sheets[(cls, mode)].paste(thumb(scene, face + VIEW[mode], 6, short(pm)), (x, y))
        print(f"{k + 1}/{len(models)} {pm}", flush=True)
    for (cls, mode), img in sheets.items():
        img.save(out / f"carry_{cls[7:]}_{mode}.jpg", quality=86)


if __name__ == "__main__":
    mr.WORK.mkdir(parents=True, exist_ok=True)
    main()
