"""Review sheets (dev tool, not in the .gma): every worn item, built-in and of the compatible addons,
on every playermodel of a list, the way the game places it (cl_fits_data.lua, cl_fits_compat.lua).
One sheet per item, two views per playermodel zoomed on the item. Playermodels whose region (head for
head items, torso for the others) and fit are the same are drawn once, labelled "+N"; index.txt says
which playermodels each cell stands for. A size at the bound of the fitting range is written in
orange (the fit didn't find a size inside it). Needs MDL_EXTRA_DIRS for the addons (fit_compat.py).

    python review_sheets.py <out_dir> <playermodels.txt> [--only substr[,substr...]] [--jobs N (default 8)]
                            [--cell pixels (default 130)]
"""
import hashlib
import os
import re
import shutil
import sys
from io import BytesIO
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

if os.name == "nt":  # below normal priority, the workers too: the computer stays usable meanwhile
    import ctypes
    k32 = ctypes.windll.kernel32
    k32.GetCurrentProcess.restype = ctypes.c_void_p  # a 64-bit handle: the default int would cut it
    k32.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    k32.SetPriorityClass(k32.GetCurrentProcess(), 0x4000)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdl_render as mr  # noqa: E402

# textures are converted per process (the workers import fit_items, which loads a model at import)
mr.WORK = Path(mr.WORK.parent) / f"advinv_review_{os.getpid()}"
mr.WORK.mkdir(parents=True, exist_ok=True)

import compat_sheets as cs  # noqa: E402
import fit_items as fi  # noqa: E402
import mount_check as mc  # noqa: E402

LUA = Path(__file__).resolve().parent.parent / "lua" / "advinv"
CELL, COLS, ROWS = 130, 6, 12
VIEWS = {"head": [(35, 8), (100, 4)], "vest": [(25, 6), (90, 4)], "back": [(150, 10), (85, 4)]}
BACK = {"advinv_jetpack", "advinv_suitcase"}
BOUNDS = {"head": (0.7, 0.85, 1.2, 1.4), "vest": (0.75, 1.45), "back": ()}


def compat_defaults():
    """Default attach of every compatibility item (sh_compat_data.lua): its fit on male_07."""
    t = (LUA / "sh_compat_data.lua").read_text(encoding="utf-8")
    out = {}
    num = lambda s: np.array([float(x) for x in s.split(",")])
    for m in re.finditer(r'class = "([^"]+)".*?attach = \{ bone = "([^"]+)", pos = Vector\(([^)]*)\), '
                         r'ang = Angle\(([^)]*)\), scale = ([\d.]+) \}', t, re.S):
        out[m.group(1)] = {"bone": m.group(2), "pos": num(m.group(3)), "ang": list(num(m.group(4))),
                           "scale": float(m.group(5))}
    return out


def entries(only):
    out = []
    for cls, model, att0, _bodyfit in mc.worn_items():
        out.append({"class": cls, "model": model, "kind": "back" if cls in BACK else "head", "att0": att0,
                    "compat": False})
    for it in cs.items():
        kind = {"ValveBiped.Bip01_Head1": "head", "ValveBiped.Bip01_Spine4": "vest"}.get(it["bone"], "back")
        out.append({"class": it["class"], "model": it["model"], "kind": kind, "bone": it["bone"], "compat": True})
    return [e for e in out if not only or any(o in e["class"] for o in only.split(","))]


def digest(a):
    return hashlib.sha1(np.round(np.asarray(a, dtype=np.float64), 2).tobytes()).hexdigest()[:12]


_state = {}


def init_worker(cell=None):
    global CELL
    CELL = cell or CELL
    _state["fits"], _state["compat"], _state["defaults"] = mc.model_fits(), cs.fits(), compat_defaults()


def attach(e, pm):
    if not e["compat"]:
        return mc.attach_for(e["class"], e["att0"], pm, _state["fits"])
    f = _state["compat"].get(e["class"], {}).get(pm)
    if f is None:
        return None  # in game: no fit for this playermodel (it can't wear it)
    return {"bone": e["bone"], "pos": f[0], "ang": f[1], "scale": f[2]}


def render_pm(args):
    pm, ents = args
    try:
        body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
    except Exception as ex:  # noqa: BLE001
        return pm, None, None, {"error": str(ex)}
    try:
        b = fi.Body(pm)
        sig = {"head": digest(b.head_in_eyes()), "torso": digest(b.verts(fi.TORSO))}
    except Exception:  # noqa: BLE001
        sig = {"head": digest(body[0]), "torso": digest(body[0])}
    cells = {}
    for e in ents:
        att = attach(e, pm)
        if att is None:
            cells[e["class"]] = (None, None, "no fit")
            continue
        try:
            item = mc.place_item(e["model"], att, bones)
        except Exception as ex:  # noqa: BLE001
            cells[e["class"]] = (None, None, f"error {ex}")
            continue
        if item is None:
            cells[e["class"]] = (None, None, "bone missing")
            continue
        ip = item[0][sorted({t[j] for t in item[3] for j in range(3)})]
        c = (ip.min(0) + ip.max(0)) / 2
        r = np.linalg.norm(ip.max(0) - ip.min(0)) / 2
        near = body[0][np.linalg.norm(body[0] - c, axis=1) < r * 1.5 + 4]
        scene = mc.merge(body, item)
        pair = Image.new("RGB", (2 * CELL, CELL))
        for k, (yaw, pitch) in enumerate(VIEWS[e["kind"]]):
            img = mr.rasterize(*scene, face + yaw, pitch, np.r_[ip, near], size=CELL)
            bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
            bg.alpha_composite(img)
            pair.paste(bg.convert("RGB"), (k * CELL, 0))
        buf = BytesIO()
        pair.save(buf, "PNG")
        key = sig["head"] if e["kind"] == "head" else sig["torso"]
        fit_key = digest(np.r_[att["pos"], att["ang"], att["scale"]])
        cells[e["class"]] = (buf.getvalue(), key + fit_key, att["scale"])
    return pm, sig, None, cells


def short(pm):
    p = pm.replace("models/", "").replace("player/", "").replace(".mdl", "")
    for a, b in (("group0", "g"), ("rusty/natguard/", "ng/"), ("humans/vaulttec/", "vault/"),
                 ("nada/pms/", "nada/"), ("adamwassim/imperialcommunity/ww1/", "ww1/"), ("hostage/", "")):
        p = p.replace(a, b)
    return p[-24:]


def main():
    args = sys.argv[1:]
    out = Path(args.pop(0))
    models = [l.strip() for l in Path(args.pop(0)).read_text(encoding="utf-8").splitlines() if l.strip()]
    only, jobs = None, 8
    while args:
        a = args.pop(0)
        if a == "--only":
            only = args.pop(0)
        elif a == "--jobs":
            jobs = int(args.pop(0))
        elif a == "--cell":
            global CELL
            CELL = int(args.pop(0))
    out.mkdir(parents=True, exist_ok=True)
    ents = entries(only)
    results = []
    with Pool(jobs, initializer=init_worker, initargs=(CELL,)) as pool:
        for k, res in enumerate(pool.imap_unordered(render_pm, [(pm, ents) for pm in models]), 1):
            results.append(res)
            print(f"{k}/{len(models)} {res[0]}", flush=True)  # progress
    results.sort(key=lambda r: models.index(r[0]))
    index = []
    for e in ents:
        groups = {}  # key -> [pms], first one drawn
        order = []
        missing = []
        for pm, sig, _, cells in results:
            cell = cells.get(e["class"]) if cells else None
            if not cell or cell[0] is None:
                missing.append(f"{short(pm)} ({cell[2] if cell else cells.get('error', '?')})")
                continue
            if cell[1] not in groups:
                groups[cell[1]] = []
                order.append((cell[1], pm, cell))
            groups[cell[1]].append(pm)
        per = COLS * ROWS
        for s in range(0, max(len(order), 1), per):
            chunk = order[s:s + per]
            rows = (len(chunk) + COLS - 1) // COLS
            sheet = Image.new("RGB", (COLS * (2 * CELL + 4), rows * (CELL + 14) + 20), (30, 30, 34))
            d = ImageDraw.Draw(sheet)
            d.text((4, 4), f"{e['class']}  ({len(order)} different, {sum(len(v) for v in groups.values())} playermodels,"
                           f" no fit: {len(missing)})", fill=(240, 220, 120))
            for k, (key, pm, cell) in enumerate(chunk):
                x, y = (k % COLS) * (2 * CELL + 4), 20 + (k // COLS) * (CELL + 14)
                sheet.paste(Image.open(BytesIO(cell[0])), (x, y))
                n = len(groups[key]) - 1
                at_bound = e["compat"] and any(abs(cell[2] - v) < 1e-6 for v in BOUNDS[e["kind"]])
                d.text((x + 2, y + CELL + 1), f"{short(pm)}{f' +{n}' if n else ''}  x{cell[2]:g}",
                       fill=(255, 160, 60) if at_bound else (225, 225, 225))
                index.append(f"{e['class']} [{s // per}] {short(pm)} x{cell[2]:g}: " + ", ".join(groups[key]))
            sheet.save(out / f"{e['class']}_{s // per}.jpg", quality=88)
        if missing:
            index.append(f"{e['class']} no fit: " + ", ".join(missing))
        print(e["class"], len(order), "cells", len(missing), "without fit")
    (out / "index.txt").write_text("\n".join(index) + "\n", encoding="utf-8")
    for d in mr.WORK.parent.glob("advinv_review_*"):
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    main()
