"""Prepares the data of the fit editor (tools/fit_editor/, dev tool, not in the .gma).

Reads every playermodel and every worn item once (meshes in the reference pose, textures, bones) into
a cache that the editor draws with OpenGL, then writes its index: the items, the playermodels, the
current fit of every pair (lua/advinv/cl_fits_data.lua, cl_fits_compat.lua, after writing the
approved ones into them) and which pairs look the same. Playermodels and items already in the cache
are not read again (unless their .mdl changed): only the first run is long.

Two playermodels are one pair for an item when the region the item sits on (the head for head
items, the torso for the others, in the item's bone frame) and the fit are the same.

Needs MDL_EXTRA_DIRS for the Workshop playermodels and the compatible addons (see fit_compat.py).

    python fit_editor_export.py [--cache DIR] [--jobs N (default 8, at most 8)]
"""
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import zlib
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image

if os.name == "nt":  # below normal priority, the workers too: the computer stays usable meanwhile
    import ctypes
    k32 = ctypes.windll.kernel32
    k32.GetCurrentProcess.restype = ctypes.c_void_p  # a 64-bit handle: the default int would cut it
    k32.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    k32.SetPriorityClass(k32.GetCurrentProcess(), 0x4000)

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import mdl_render as mr  # noqa: E402

# textures are converted per process (fit_items loads a model at import)
mr.WORK = Path(mr.WORK.parent) / f"advinv_fe_{os.getpid()}"
mr.WORK.mkdir(parents=True, exist_ok=True)

import anim0  # noqa: E402
import compat_sheets as cs  # noqa: E402
import fit_items as fi  # noqa: E402
import fit_locks  # noqa: E402
import mount_check as mc  # noqa: E402
import refbody  # noqa: E402

LUA = TOOLS.parent / "lua" / "advinv"
SPINE2, SPINE4 = "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4"
PELVIS = "ValveBiped.Bip01_Pelvis"
BONES = [fi.HEAD, SPINE2, SPINE4, PELVIS]  # (the editor's bone indices: 0 1 2 then 3; the eyes go between)
TEX_MAX = 512
VERSION = 2   # format of the mesh files (2: the pelvis after the eyes)
CACHE = 4     # cache contents: older entries are read again


def digest(a):
    return hashlib.sha1(np.round(np.asarray(a, dtype=np.float64), 2).tobytes()).hexdigest()[:16]


def key(name):
    return hashlib.sha1(name.lower().encode()).hexdigest()[:16]


def save_tex(img, cache):
    """RGBA, at most TEX_MAX pixels a side, zlib; named by its content (shared by the models)."""
    img = img.convert("RGBA")
    if max(img.size) > TEX_MAX:  # colour and alpha apart: Pillow premultiplies RGBA, and a texture whose
        f = TEX_MAX / max(img.size)  # alpha is a mask near 0 would come out black
        size = (max(1, round(img.width * f)), max(1, round(img.height * f)))
        img = Image.merge("RGBA", (*img.convert("RGB").resize(size).split(), img.getchannel("A").resize(size)))
    raw = img.tobytes()
    name = hashlib.sha1(raw + struct.pack("<II", *img.size)).hexdigest() + ".tex"
    path = cache / "tex" / name
    if not path.exists():
        data = zlib.compress(raw, 6)
        tmp = path.with_name(f"{name}.{os.getpid()}.tmp")
        tmp.write_bytes(b"AFET" + struct.pack("<III", img.width, img.height, len(data)) + data)
        try:
            os.replace(tmp, path)
        except OSError:  # written meanwhile by another worker
            tmp.unlink(missing_ok=True)
    return name


def write_mesh(path, mesh, cache, face=0.0, bones=None, eyes=None, arm=None):
    """AFEM v2: counts, facing yaw, flags + head / Spine2 / Spine4 / eyes / pelvis matrices (row-major
    4x4, reference pose; flags 1 2 4 16 and 8 for the eyes), vertices (pos, normal, uv: 8 floats), triangles (3 vertices, material),
    materials (flags: 1 translucent, 2 alpha test, 4 the arms' triangles; texture file in tex/, 48 bytes)."""
    pos, nrm, uv, tris, mats = mesh
    arm_t = [bool(arm is not None and (arm[t[0]] or arm[t[1]] or arm[t[2]])) for t in tris]
    used = sorted({(t[3], a) for t, a in zip(tris, arm_t)})
    remap = {m: k for k, m in enumerate(used)}
    T = np.array([(t[0], t[1], t[2], remap[(t[3], a)]) for t, a in zip(tris, arm_t)], dtype=np.uint32).reshape(-1, 4)
    flags, mats_out = 0, []
    for m, a in used:
        img, translucent, alphatest = mats[m] if m < len(mats) else (None, False, False)
        tex = save_tex(img, cache) if img is not None else ""
        fl = int(bool(translucent)) | 2 * int(bool(alphatest)) | 4 * int(a)
        mats_out.append(struct.pack("<I", fl) + tex.encode().ljust(48, b"\0"))
    bones = list(bones or []) + [None] * (4 - len(bones or []))
    mat = lambda b: np.asarray(b if b is not None else np.zeros((4, 4)), dtype=np.float32).reshape(16)
    mats_m = []
    for k, b in enumerate(bones[:3]):
        if b is not None:
            flags |= 1 << k
        mats_m.append(mat(b))
    if eyes is not None:
        flags |= 8
    mats_m.append(mat(eyes))
    if bones[3] is not None:
        flags |= 16
    mats_m.append(mat(bones[3]))
    V = np.c_[pos, nrm, uv].astype(np.float32)
    head = b"AFEM" + struct.pack("<IIIIfI", VERSION, len(V), len(T), len(used), float(face), flags)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(head + b"".join(m.tobytes() for m in mats_m) + V.tobytes() + T.tobytes() + b"".join(mats_out))
    os.replace(tmp, path)


def bodygroups(pm):
    """The bodygroups it is drawn with (tools/playermodel_bodygroups.txt): a change reads it again."""
    return " ".join(f"{k}={v}" for k, v in sorted(mr.BODYGROUPS.get(pm.lower(), {}).items()))


def export_pm(args):
    pm, cache = args
    out = cache / f"pm_{key(pm)}.bin"
    meta = out.with_suffix(".json")
    try:
        size = len(mr.vpk_read(pm) or b"")
        if out.exists() and meta.exists():
            m = json.loads(meta.read_text(encoding="utf-8"))
            if m.get("size") == size and m.get("cache") == CACHE and m.get("bg") == bodygroups(pm):
                return pm, out.name, m["sigs"], None
        b = fi.Body(pm)
        sigs = {}
        for bone, region in ((fi.HEAD, [fi.HEAD]), (SPINE2, fi.TORSO), (SPINE4, fi.TORSO)):
            v = b.verts(region) if b.has(bone) else []
            if len(v):
                L = np.linalg.inv(b.world[bone])
                sigs[bone] = digest(v @ L[:3, :3].T + L[:3, 3])
        mesh = mr.load_model(pm)  # the whole playermodel; the arms marked (the editor can hide them)
        names = [x["name"] for x in refbody.bones(pm)]
        B, W = mc.vertex_weights(pm)
        arm = np.array([bool(mc.ARM_BONES.search(names[B[k, int(np.argmax(W[k]))]])) for k in range(len(mesh[0]))])
        write_mesh(out, mesh, cache, mc.facing_yaw(pm), [b.world.get(n) for n in BONES], b.eyes, arm)
        meta.write_text(json.dumps({"size": size, "cache": CACHE, "bg": bodygroups(pm), "sigs": sigs}), encoding="utf-8")
        return pm, out.name, sigs, None
    except Exception as e:  # noqa: BLE001
        return pm, None, {}, str(e)


def export_item(args):
    cls, model, cache, pack = args
    out = cache / f"item_{key(cls)}.bin"
    meta = out.with_suffix(".json")
    try:
        size = len(mr.vpk_read(model) or b"")
        sel = None
        if pack:  # an extension's item: its gear alone, out of the pack's playermodel (worn look)
            import modelgear_packs
            pk = modelgear_packs.PACKS[pack]
            sel = json.dumps(next(i for i in pk["items"] if i["class"] == cls)["show"])
        if out.exists() and meta.exists():
            m = json.loads(meta.read_text(encoding="utf-8"))
            if m.get("size") == size and m.get("model") == model and m.get("cache") == CACHE and m.get("sel") == sel:
                return cls, out.name, None
        if pack:
            import modelgear_pack as mp
            mesh = mp.gear_mesh(pk, cls)
        else:
            mesh = anim0.posed_mesh(model)
        write_mesh(out, mesh, cache)
        meta.write_text(json.dumps({"size": size, "model": model, "cache": CACHE, "sel": sel}), encoding="utf-8")
        return cls, out.name, None
    except Exception as e:  # noqa: BLE001
        return cls, None, str(e)


def short(pm):
    p = pm.replace("models/", "").replace("player/", "").replace(".mdl", "")
    for a, b in (("group0", "g"), ("rusty/natguard/", "natguard/"), ("humans/vaulttec/", "vault/"),
                 ("nada/pms/", "nada/"), ("adamwassim/imperialcommunity/ww1/", "ww1/"), ("hostage/", "")):
        p = p.replace(a, b)
    return p


WEAPON_NAMES = {"weapon_smg1": "SMG", "weapon_ar2": "AR2", "weapon_shotgun": "Shotgun", "weapon_crossbow": "Crossbow",
                "weapon_rpg": "RPG"}
MODE_NAMES = {"sling_up": "sling arms", "sling_down": "back carry",
              "front_hang": "front carry"}


def gears():
    """Items in the editor's order: the compatible addons' (sh_compat_data.lua), the built-in ones, then
    the extensions' (gear taken from a playermodel addon: advinv-ext-*, tools/modelgear_pack.py)."""
    t = (LUA / "sh_compat_data.lua").read_text(encoding="utf-8")
    names = dict(re.findall(r'class = "([^"]+)", model = "[^"]+",\s*name = \{ "((?:[^"\\]|\\.)*)"', t))
    out = [{"class": it["class"], "model": it["model"], "bone": it["bone"], "compat": 1,
            "name": names.get(it["class"], it["class"])} for it in cs.items()]
    ent = TOOLS.parent / "lua" / "entities"
    for cls, model, att, _bf in mc.worn_items():
        src = (ent / f"{cls}.lua").read_text(encoding="utf-8")
        n = re.search(r'ENT\.PrintName\s*=\s*AdvInv\.T\("((?:[^"\\]|\\.)*)"', src)
        out.append({"class": cls, "model": model, "bone": att["bone"] if att else fi.HEAD, "compat": 0,
                    "name": n.group(1) if n else cls})
    import modelgear_pack as mp
    import modelgear_packs
    for path, pk in fit_locks.extensions().items():
        pack = modelgear_packs.PACKS.get(pk)
        if not pack:
            continue
        for it in pack["items"]:
            out.append({"class": it["class"], "model": pack["models"][0], "bone": mp.BONE[it["slot"]], "compat": 2,
                        "name": it["name"][0], "pack": pk, "ext": path})
    # long guns in their carry modes (cl_carry_data.lua, tools/fit_carry.py): one item per weapon and mode
    import carry_data
    import carry_weapons
    import fit_carry
    sets, _aliases = carry_data.read()
    names = dict(WEAPON_NAMES, **{c: n for c, _s, _m, n in carry_weapons.load()})
    for cls, (model, modes) in fit_carry.WEAPONS.items():
        for mode in modes or fit_carry.MODES:
            e = sets.get("default", {}).get(cls, {}).get(mode)
            if e:
                out.append({"class": carry_data.gear_class(cls, mode), "model": model, "bone": e["bone"], "compat": 3,
                            "name": f"{names.get(cls, cls)} - {MODE_NAMES.get(mode, mode)}", "carry": (cls, mode)})
    return out


def main():
    args = sys.argv[1:]
    cache, jobs = Path(tempfile.gettempdir()) / "advinv_fit_editor", 8
    while args:
        a = args.pop(0)
        if a == "--cache":
            cache = Path(args.pop(0))
        elif a == "--jobs":
            jobs = max(1, min(8, int(args.pop(0))))
    (cache / "tex").mkdir(parents=True, exist_ok=True)

    print(f"{fit_locks.apply(fit_locks.load())} approved fits written into the game's files", flush=True)
    G = gears()
    compat = cs.fits()
    data = mc.model_fits()
    t = (LUA / "cl_fits_compat.lua").read_text(encoding="utf-8")
    pms = re.findall(r'^    "([^"]+)",$', t.split("local F")[0], re.M)
    pms += [m for m in data if m not in pms]
    ext = {}  # extension file -> {class: {pm: fit}}
    for g in G:
        if g.get("ext") and g["ext"] not in ext:
            ext_models, ext[g["ext"]] = fit_locks.ext_fits(g["ext"].read_text(encoding="utf-8"))
            pms += [m for m in ext_models if m not in pms]
    import carry_data
    carry_sets, carry_aliases = carry_data.read()
    fits = {}  # class -> {pm: (pos, ang, scale)}
    for g in G:
        if g.get("carry"):  # each playermodel takes its offset set's entry (no size: 1)
            cls, mode = g["carry"]
            fits[g["class"]] = {}
            for m in pms:
                e = carry_sets[carry_data.set_of(carry_aliases, carry_sets, m)].get(cls, {}).get(mode)
                if e:
                    fits[g["class"]][m] = (np.array(e["pos"]), tuple(e["ang"]), 1.0)
        elif g.get("ext"):  # (on the pack's own playermodels the item is their bodygroup: no fit)
            import modelgear_packs
            own = {m.lower() for m in modelgear_packs.PACKS[g["pack"]]["models"]}
            fits[g["class"]] = {m: f for m, f in ext[g["ext"]].get(g["class"], {}).items() if m not in own}
        elif g["compat"]:
            fits[g["class"]] = compat.get(g["class"], {})
        else:
            fits[g["class"]] = {m: data[m][g["class"]] for m in pms if g["class"] in data.get(m, {})}
    G = [g for g in G if fits[g["class"]]]

    todo_pm = [(m, cache) for m in pms]
    todo_it = [(g["class"], g["model"], cache, g.get("pack")) for g in G]
    pm_file, sigs, items = {}, {}, {}
    with Pool(jobs) as pool:
        for k, (m, f, s, err) in enumerate(pool.imap_unordered(export_pm, todo_pm), 1):
            print(f"playermodel {k}/{len(todo_pm)} {m}{'  ERROR ' + err if err else ''}", flush=True)
            if f:
                pm_file[m], sigs[m] = f, s
        for k, (c, f, err) in enumerate(pool.imap_unordered(export_item, todo_it), 1):
            print(f"item {k}/{len(todo_it)} {c}{'  ERROR ' + err if err else ''}", flush=True)
            if f:
                items[c] = f

    lines = [f"AFE\t{VERSION}", f"REF\t{fi.REF}"]
    for g in G:
        if g["class"] in items:
            lines.append("\t".join(["GEAR", g["class"], str(g["compat"]), g["bone"], items[g["class"]],
                                    g["name"].replace("\t", " ")]))
    for m in pms:
        if m in pm_file:
            lines.append("\t".join(["PM", m, pm_file[m], short(m)]))
    n = 0
    for g in G:
        if g["class"] not in items:
            continue
        for m in pms:
            f = fits[g["class"]].get(m)
            if f is None or m not in pm_file:
                continue
            p, a, s = f
            vals = [round(float(x), 2) for x in p] + [round(float(x), 1) for x in a] + [round(float(s), 3)]
            if g.get("carry"):  # the playermodels of one offset set: one pair
                region = "set_" + key(carry_data.set_of(carry_aliases, carry_sets, m))
            else:
                region = sigs[m].get(g["bone"]) or key(m)  # unknown region: a pair of its own
            lines.append("\t".join(["FIT", g["class"], m, " ".join(f"{x:g}" for x in vals), region + digest(vals)]))
            n += 1
    (cache / "index.txt").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(G)} items, {len(pm_file)} playermodels, {n} item x playermodel fits -> {cache / 'index.txt'}")
    for d in Path(mr.WORK.parent).glob("advinv_fe_*"):  # the workers' texture folders
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    main()
