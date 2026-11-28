"""Checks the vests of the pack extensions (tools/modelgear_pack.py) on playermodels, offline: the body as
the game draws it (anim0.posed_mesh) and the vest as its fit places it (size, stretch, depth: cl_gear.lua
AdvInv.StretchGear). No game needed. Dev tool, not in the .gma. Reads the extracted addons in MDL_EXTRA_DIRS
(fit_compat.py); when it is empty, every folder under C:/gmod-test/workshop_* (this computer's).

    python vest_check.py report <extension.lua> [--class C] [playermodel ...]
        straps on the shoulders, panels against the body: per vest x body, PASS or what is wrong
    python vest_check.py view <extension.lua> <class> <out.jpg> [--with label=other.lua ...] [playermodel ...]
        close-ups: front, side, back, above and a side cut through the middle (body grey, vest red)
    python vest_check.py sheet <out.jpg> [playermodel ...]
        one vest of every extension on the bodies, front and back
    python vest_check.py bodies <extension.lua> <out.txt>
        every playermodel the extension is fitted to (what a refit runs on)
    python vest_check.py refit [--jobs N (default 5)] [--logs DIR] [pack ...]
        refits the packs' extensions (all with an extension file by default), N at a time, below normal
        priority, on the playermodels each is fitted to now; logs in DIR (default: the system's temp)

Without playermodels: BODIES (slim, deep, female, male). The rules (tools/modelgear_pack.py fit_to_body):
the straps rest on the shoulders, the front and back panels lie against the chest, the belly and the back,
and the body never shows through the vest (but for a few cells: a ponytail, a hood, a collar).
"""
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

if not os.environ.get("MDL_EXTRA_DIRS"):  # (read when mdl_render is imported)
    os.environ["MDL_EXTRA_DIRS"] = os.pathsep.join(str(d) for d in sorted(Path("C:/gmod-test").glob("workshop_*/*"))
                                                    if d.is_dir())
sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import modelgear_pack as mg  # noqa: E402
from modelgear_packs import PACKS  # noqa: E402

ADDONS = Path(__file__).resolve().parents[2]
BODIES = ["models/player/group01/female_02.mdl", "models/player/group01/female_04.mdl", "models/player/alyx.mdl",
          "models/player/mossman.mdl", "models/player/group01/male_07.mdl", "models/player/group03/male_02.mdl",
          "models/player/gman_high.mdl", "models/player/kleiner.mdl", "models/player/odessa.mdl",
          "models/player/breen.mdl"]
# a vest is wrong (report) when, in world units:
FLOAT = 0.4  # its straps or a panel stand that far off the body where they are closest to it
AIR = 0.5  # a gap seen from the side between the vest and the belly or the back
SHOW = 8.0  # the body shows through it over that percentage of a region
try:
    FONT = ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", 16)
except OSError:
    FONT = ImageFont.load_default()


def read_ext(path):
    """An extension's Lua -> (pack key, {class: (slot, stretch_top, depth_center)}, {class: {pm: numbers}})."""
    text = Path(path).read_text(encoding="utf-8")
    key = re.search(r'^    key = "([^"]+)"', text, re.M).group(1)
    head, _, tail = text.partition("\n    fits = {\n")
    items = {}
    for blk in re.split(r"\n        \{ class = ", head)[1:]:
        cls = re.match(r'"([^"]+)"', blk).group(1)
        slot = re.search(r'slot = "([^"]+)"', blk)
        top = re.search(r"stretch_top = ([-\d.]+)", blk)
        xc = re.search(r"depth_center = ([-\d.]+)", blk)
        items[cls] = (slot and slot.group(1), top and float(top.group(1)), xc and float(xc.group(1)))
    models = [m.lower() for m in re.findall(r'^            "([^"]+)",$', tail.split("\n        },")[0], re.M)]
    fits = {}
    for cls, packed in re.findall(r'^            \["([^"]+)"\] = "([^"]*)",$', tail, re.M):
        fits[cls] = {m: [float(x) for x in e.split()] for m, e in zip(models, packed.split("|")) if e}
    return key, items, fits


def gear_of(key, cls):
    """mg.gear_mesh, drawn as the game draws it: some packs' models in their bind pose (bind_positions)."""
    pack = PACKS[key]
    if pack.get("bind_positions"):
        anim0.BIND_POSITIONS.update(m.lower() for m in pack["models"])
    try:
        return mg.gear_mesh(pack, cls)
    finally:
        if pack.get("bind_positions"):
            anim0.BIND_POSITIONS.difference_update(m.lower() for m in pack["models"])


def vests(items):
    """The classes fitted to the body (a vest drawn as one piece: it has a stretch_top)."""
    return [c for c, (slot, top, _xc) in items.items() if slot == "Vest" and top is not None]


def as_fit(n):
    return (np.array(n[:3]), tuple(n[3:6]), n[6], n[7] if len(n) > 7 else 1.0, n[8] if len(n) > 8 else 1.0)


def placed_gear(gear, top, xc, n, tb):
    """The vest's mesh (gear: pos, nrm, uv, tris, mats) placed by the fit numbers n on a body (posed bones tb)."""
    P, N = gear[0].copy(), gear[1].copy()
    st = n[7] if len(n) > 7 else 1.0
    dp = n[8] if len(n) > 8 else 1.0
    if top is not None and st != 1:
        P[:, 2] = top + (P[:, 2] - top) * st
        N = N / np.array([1.0, 1.0, st])
    if xc is not None and dp != 1:
        P[:, 0] = xc + (P[:, 0] - xc) * dp
        N = N / np.array([dp, 1.0, 1.0])
    Tt = tb[mg.BONE["Vest"]][0]
    R = Tt[:3, :3] @ mg.angle_matrix(n[3:6])
    W = (R @ (P * n[6]).T).T + Tt[:3, :3] @ np.array(n[:3]) + Tt[:3, 3]
    N = (R @ N.T).T
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    return W, N


def measure(W, WT, model, k):
    """{region: (cover, gap)} of a placed vest (mg.cover) on model as drawn, and "side": (front, back) air
    seen from the side (mg.side_air)."""
    BP, BT = mg.drawn_mesh(model)
    tb = mg.posed_bones(model)
    sh = sum(tb[u][0][2, 3] for u in mg.UPPERARMS) / 2
    out = {r: mg.cover(W, BP, BT, r, k, sh if r == "straps" else None) for r in ("straps", "back")}
    # the front against the belly (its lower half); the chest above may go into the vest (a bust) but not
    # deeper than mg.BUST_MAX
    out["front"] = mg.cover(W, BP, BT, "front", k, part="low")
    out["chest"] = mg.cover(W, BP, BT, "front", k, part="high")
    out["side"] = mg.side_air(W, WT, BP, BT, k)
    out["k"] = k
    return out


def verdict(m):
    """(PASS | what is wrong, numbers) from measure()."""
    bad, nums = [], []
    for r in ("straps", "front", "back"):
        c, g = m[r]
        if r == "straps" and len(c):  # (a hood the straps go under: mg.strap_support)
            keep = np.isin(c, mg.strap_support(c, m.get("k", 1.0)))
            c, g = c[keep], g[keep]
        if len(c) < 8:
            nums.append(f"{r} -")
            continue
        touch = float(np.percentile(g, 5))  # where it is closest to the body
        show = float((c < 0).mean() * 100)
        nums.append(f"{r} touch {touch:+.2f} show {show:.0f}%")
        if touch > FLOAT:
            bad.append(f"{r} off the body by {touch:.1f}")
        if show > SHOW:
            bad.append(f"body through the {r} ({show:.0f}%)")
    c = m["chest"][0]
    if len(c) >= 8:
        deep = float(-np.percentile(c, 5))  # (how far the chest comes through the front, at its deepest)
        nums.append(f"chest in {max(deep, 0):.1f}")
        if deep > mg.BUST_MAX * m.get("k", 1.0) + 0.3:
            bad.append(f"chest through the front by {deep:.1f}")
    for name, a in zip(("belly", "back"), m["side"]):
        if len(a):
            air = float(a.max())  # the widest gap seen from the side
            nums.append(f"{name} air {air:+.2f}")
            if air > AIR:
                bad.append(f"gap at the {name} {air:.1f}")
    return ("PASS" if not bad else "; ".join(bad)), " | ".join(nums)


def report(path, classes, models):
    key, items, fits = read_ext(path)
    fails = 0
    for cls in classes or vests(items):
        _slot, top, xc = items[cls]
        gear = gear_of(key, cls)
        G, GT = gear[0], np.array([t[:3] for t in gear[3]], dtype=np.int64)
        for m in models:
            n = fits.get(cls, {}).get(m.lower())
            if not n:
                print(f"{cls:48} {m.split('/')[-1]:22} no fit")
                continue
            W, _N = placed_gear((G, np.zeros_like(G)), top, xc, n, mg.posed_bones(m))
            v, nums = verdict(measure(W, GT, m, n[6]))
            fails += v != "PASS"
            print(f"{cls:48} {m.split('/')[-1]:22} {v:10} {nums}")
    print(f"{fails} not right")
    return fails


def _cut(P, tris, axis, val):
    segs = []
    for t in tris:
        a, b, c = P[t[0]], P[t[1]], P[t[2]]
        pts = []
        for p, q in ((a, b), (b, c), (c, a)):
            dp, dq = p[axis] - val, q[axis] - val
            if (dp < 0) != (dq < 0):
                pts.append(p + dp / (dp - dq) * (q - p))
        if len(pts) == 2:
            segs.append(pts)
    return segs


def side_cut(body, W, gear_tris, y, frame_z, size):
    """A side cross-section at y (body grey, vest red), size x size."""
    img = Image.new("RGB", (size, size), (255, 255, 255))
    d = ImageDraw.Draw(img)
    z0, z1 = frame_z
    sc = size * 0.92 / (z1 - z0)
    xs = body[0][(body[0][:, 2] > z0) & (body[0][:, 2] < z1)][:, 0]
    xc = (xs.min() + xs.max()) / 2 if len(xs) else 0.0
    for P, T, col in ((body[0], body[3], (130, 130, 130)), (W, gear_tris, (220, 30, 30))):
        for p, q in _cut(P, T, 1, y):
            d.line([(size / 2 + (p[0] - xc) * sc, size * 0.04 + (z1 - p[2]) * sc),
                    (size / 2 + (q[0] - xc) * sc, size * 0.04 + (z1 - q[2]) * sc)], fill=col, width=2)
    return img


def view(path, cls, out, others, models, cell=280):
    sets = [("", path)] + others
    exts = [(label, read_ext(p)) for label, p in sets]
    key = exts[0][1][0]
    gear = gear_of(key, cls)
    rows = []
    for m in models:
        body = anim0.posed_mesh(m)
        tb = mg.posed_bones(m)
        neck = tb[mg.NECK][0][:3, 3]
        for label, (_k, items, fits) in exts:
            _slot, top, xc = items[cls]
            n = fits.get(cls, {}).get(m.lower())
            img = Image.new("RGB", (cell * 5, cell + 24), (30, 30, 30))
            d = ImageDraw.Draw(img)
            title = (label + ": " if label else "") + m.split("/")[-1]
            if not n:
                d.text((6, 3), title + "  no fit", font=FONT, fill=(240, 240, 240))
                rows.append(img)
                continue
            W, N = placed_gear(gear, top, xc, n, tb)
            off = len(body[0])
            scene = (np.r_[body[0], W], np.r_[body[1], N], np.r_[body[2], gear[2]],
                     body[3] + [(a + off, b + off, c + off, t + len(body[4])) for a, b, c, t in gear[3]],
                     body[4] + gear[4])
            frame = np.vstack([W, neck + np.array([0, 0, 6.0])])
            for k, (yaw, pitch) in enumerate(((0, 10), (90, 6), (180, 10), (35, 55))):
                im = mr.rasterize(*scene, yaw, pitch, frame, size=cell)
                bg = Image.new("RGBA", im.size, (78, 82, 90, 255))
                bg.alpha_composite(im)
                img.paste(bg.convert("RGB"), (k * cell, 24))
            y_mid = float(np.median(W[:, 1]))
            img.paste(side_cut(body, W, gear[3], y_mid, (W[:, 2].min() - 2, neck[2] + 5), cell), (4 * cell, 24))
            v, _nums = verdict(measure(W, np.array([t[:3] for t in gear[3]], dtype=np.int64), m, n[6]))
            st = n[7] if len(n) > 7 else 1.0
            dp = n[8] if len(n) > 8 else 1.0
            d.text((6, 3), f"{title}  size {n[6]:g} height {st:g} depth {dp:g}  {v}", font=FONT,
                   fill=(140, 230, 140) if v == "PASS" else (250, 160, 90))
            rows.append(img)
    _save(rows, out)


def sheet(out, models, cell=170):
    rows = []
    bodies = {m: (anim0.posed_mesh(m), mg.posed_bones(m)) for m in models}
    for path in sorted(ADDONS.glob("advinv-ext-*/lua/autorun/*.lua")):
        key, items, fits = read_ext(path)
        if key not in PACKS or not vests(items):
            continue
        cls = vests(items)[0]
        _slot, top, xc = items[cls]
        gear = gear_of(key, cls)
        row = Image.new("RGB", (len(models) * 2 * cell, cell + 40), (30, 30, 30))
        d = ImageDraw.Draw(row)
        d.text((4, 2), cls, font=FONT, fill=(240, 220, 120))
        for c, m in enumerate(models):
            n = fits.get(cls, {}).get(m.lower())
            if not n:
                d.text((c * 2 * cell + 6, cell // 2), f"{m.split('/')[-1]}: no fit", font=FONT, fill=(200, 200, 200))
                continue
            body, tb = bodies[m]
            W, N = placed_gear(gear, top, xc, n, tb)
            off = len(body[0])
            scene = (np.r_[body[0], W], np.r_[body[1], N], np.r_[body[2], gear[2]],
                     body[3] + [(a + off, b + off, cc + off, t + len(body[4])) for a, b, cc, t in gear[3]],
                     body[4] + gear[4])
            frame = np.vstack([W, tb[mg.NECK][0][:3, 3] + np.array([0, 0, 7.0])])
            for k, (yaw, pitch) in enumerate(((30, 10), (205, 10))):
                im = mr.rasterize(*scene, yaw, pitch, frame, size=cell)
                bg = Image.new("RGBA", im.size, (78, 82, 90, 255))
                bg.alpha_composite(im)
                row.paste(bg.convert("RGB"), ((2 * c + k) * cell, 20))
            v, _nums = verdict(measure(W, np.array([t[:3] for t in gear[3]], dtype=np.int64), m, n[6]))
            d.text((c * 2 * cell + 6, cell + 22), f"{m.split('/')[-1][:-4]}: {v}"[:44], font=FONT,
                   fill=(140, 230, 140) if v == "PASS" else (250, 160, 90))
        rows.append(row)
        print(cls, flush=True)
    _save(rows, out)


def ext_files():
    """{pack key: its extension's Lua} for the packs with one (tools/modelgear_packs.py)."""
    out = {}
    for path in sorted(ADDONS.glob("advinv-ext-*/lua/autorun/*.lua")):
        m = re.search(r'^    key = "([^"]+)"', path.read_text(encoding="utf-8"), re.M)
        if m and m.group(1) in PACKS:
            out[m.group(1)] = path
    return out


def bodies(path, out):
    text = Path(path).read_text(encoding="utf-8")
    tail = text.split("\n    fits = {\n", 1)[1]
    models = re.findall(r'^            "([^"]+)",$', tail.split("\n        },")[0], re.M)
    Path(out).write_text("\n".join(models) + "\n", encoding="utf-8")
    print(f"{len(models)} playermodels -> {out}")


def refit(packs, jobs, logs):
    """modelgear_pack.py for each pack, jobs at a time (they inherit this process's below normal priority)."""
    import subprocess
    import tempfile
    import time
    files = ext_files()
    packs = packs or sorted(files)
    logs = Path(logs or tempfile.gettempdir()) / "advinv_refit"
    logs.mkdir(parents=True, exist_ok=True)
    todo, running, failed = list(packs), {}, []
    while todo or running:
        while todo and len(running) < jobs:
            p = todo.pop(0)
            if p not in files:
                print(f"{p}: no extension file, skipped", flush=True)
                continue
            lst = logs / f"{p}_bodies.txt"
            bodies(files[p], lst)
            log = open(logs / f"{p}.log", "w", encoding="utf-8")
            running[p] = (subprocess.Popen([sys.executable, str(Path(__file__).with_name("modelgear_pack.py")), p,
                                            str(lst), str(files[p])], stdout=log, stderr=subprocess.STDOUT,
                                           cwd=str(Path(__file__).parent)), log)
        for p, (proc, log) in list(running.items()):
            if proc.poll() is not None:
                log.close()
                print(f"pack {p} done: {proc.returncode}", flush=True)
                if proc.returncode:
                    failed.append(p)
                del running[p]
        time.sleep(5)
    print(f"ALL DONE, {len(failed)} failed {failed} (logs in {logs})", flush=True)
    return 1 if failed else 0


def _save(rows, out):
    img = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)), (30, 30, 30))
    y = 0
    for r in rows:
        img.paste(r, (0, y))
        y += r.height
    img.save(out, quality=86)
    print(out)


def main(argv):
    if not argv or argv[0] not in ("report", "view", "sheet", "bodies", "refit"):
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]
    others = []
    while "--with" in rest:
        k = rest.index("--with")
        others.append(tuple(rest[k + 1].split("=", 1)))
        del rest[k:k + 2]
    opt = {}
    for name in ("--jobs", "--logs"):
        if name in rest:
            k = rest.index(name)
            opt[name] = rest[k + 1]
            del rest[k:k + 2]
    if cmd == "bodies":
        bodies(rest[0], rest[1])
        return 0
    if cmd == "refit":
        return refit(rest, int(opt.get("--jobs", 5)), opt.get("--logs"))
    cls = None
    if "--class" in rest:
        k = rest.index("--class")
        cls = rest[k + 1]
        del rest[k:k + 2]
    if cmd == "report":
        return 1 if report(rest[0], [cls] if cls else None, rest[1:] or BODIES) else 0
    if cmd == "view":
        view(rest[0], rest[1], rest[2], others, rest[3:] or BODIES)
    else:
        sheet(rest[0], rest[1:] or BODIES)
    return 0


if __name__ == "__main__":
    if os.name == "nt":  # below normal priority: the computer stays usable meanwhile
        import ctypes
        k32 = ctypes.windll.kernel32
        k32.GetCurrentProcess.restype = ctypes.c_void_p
        k32.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        k32.SetPriorityClass(k32.GetCurrentProcess(), 0x4000)
    sys.exit(main(sys.argv[1:]))
