"""Gear taken from a playermodel addon's own bodygroups, as inventory items: an AIS extension that ships
Lua only. The gear is drawn with the playermodel's own model (its other bodygroups set to their empty
choice, the parts that have none hidden by material), so nothing of the playermodel's author is
redistributed; the playermodel addon must be installed, as for its textures.

For each item of a pack (modelgear_packs.py) it measures, in the pose the game draws the model in
(its first sequence, anim0.py):
  - the bodygroups that show it worn and stored (on the ground, in the inventory: webbing without its
    straps), the others empty; the materials hidden (checked: none of the gear's);
  - the stored gear's centre (the item's origin on the ground) and a convex hull around it (its physics);
  - its fit on every playermodel of a list, transferred from the playermodel it comes from: headgear
    in the eyes frame, by the skull's size, top on the top of the skull; vests and backpacks in their
    spine bone's frame, by the chest's girth (playermodels with that gear in their mesh get none);
  - on the pack's own playermodels, the bodygroups that show it (AdvInv.ModelGear items: no prop).
Writes the extension's Lua (lua/autorun/advinv_ext_<pack>.lua).

    python modelgear_pack.py <pack> <playermodels.txt> <out.lua> [--preview out.jpg]

Needs MDL_EXTRA_DIRS (see fit_compat.py).
"""
import math
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import builtin_gear  # noqa: E402
import fit_compat as fc  # noqa: E402
import fit_items as fi  # noqa: E402
import fit_locks  # noqa: E402

_nz = fit_locks._nz  # (a negative zero without its sign; "-0.004" keeps it)
import mdl_render as mr  # noqa: E402
import refbody  # noqa: E402
from modelgear_packs import PACKS  # noqa: E402

SPINE2, SPINE4, NECK = "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Neck1"
BONE = {"Helmet": fi.HEAD, "Vest": SPINE4, "Rucksack": SPINE2, "Gasmask": fi.HEAD, "NVGs": fi.HEAD, "Radio": fi.HEAD}
HEAD_SLOTS = ("Helmet", "Gasmask", "NVGs", "Radio")  # (fitted by the skull: a gas mask, night vision, a headset)


def bodyparts(model):
    """[(name, [(submodel name, has a mesh)])] of the model, in order."""
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    out = []
    for b in range(i(232)):
        bo = i(236) + b * 16
        subs = []
        for s in range(i(bo + 4)):
            so = bo + i(bo + 12) + s * 148
            subs.append((mr.cstr(d, so).lower(), i(so + 72) > 0))
        out.append((mr.cstr(d, bo + i(bo)).strip(), subs))
    return out


def _pick(names, want):
    """Index of the first name starting with want, else ending with it, else containing it (models of
    one pack may prefix their names: "VN3_Headgear_Pith02", "male_01_helmet1.smd")."""
    want = want.lower()
    low = [n.lower() for n in names]
    for test in (lambda n: n.startswith(want), lambda n: n.endswith(want) or n.endswith(want + ".smd"),
                 lambda n: want in n):
        for k, n in enumerate(low):
            if test(n):
                return k
    return None


def find(parts, part, sub):
    """Index of the bodypart named `part` and of its submodel `sub` (start of their names, else the
    end, else a part of it)."""
    b = _pick([name for name, _ in parts], part)
    if b is None:
        raise SystemExit(f"no bodypart {part}")
    s = _pick([sn for sn, _ in parts[b][1]], sub)
    if s is None:
        raise SystemExit(f"{part}: no submodel {sub}")
    return b, s


def empty_choices(parts):
    return {b: next(s for s, (_, m) in enumerate(subs) if not m) for b, (_, subs) in enumerate(parts)
            if any(not m for _, m in subs)}


def posed(model, sel):
    mr.BODYGROUPS[model.lower()] = dict(sel)
    return anim0.posed_mesh(model)


def _unused_gear_mesh(model, sel, hidden):
    """Vertices (posed) and triangles of what the selection shows, the hidden materials left out."""
    P, N, uv, tris, mats = posed(model, sel)
    keep = [t for t in tris if t[3] not in hidden]
    used = sorted({t[k] for t in keep for k in range(3)})
    return P, keep, used


def hull_points(pts, n=56):
    """Support points of the cloud in n directions (a convex polytope inside its hull, a few dozen points)."""
    k = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * k / n)
    th = math.pi * (1 + 5 ** 0.5) * k
    dirs = np.c_[np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)]
    idx = sorted({int(np.argmax(pts @ d)) for d in dirs})
    return pts[idx]


def split_pieces(V, min_gap=2.0, keep=0.3):
    """Pieces apart from each other (webbing's pouches without their straps: nothing holds them together):
    the widest empty slab across the cloud along x, y or z, if wider than min_gap. -> [(normal, dist,
    offset)] for both sides (a clip plane in the model's space, and the move that closes the gap down to
    `keep`), or None."""
    best = None
    for a in range(3):
        xs = np.sort(V[:, a])
        gaps = np.diff(xs)
        k = int(np.argmax(gaps))
        if gaps[k] > min_gap and (best is None or gaps[k] > best[1]):
            best = (a, gaps[k], xs[k], xs[k + 1])
    if best is None:
        return None
    a, gap, lo, hi = best
    mid = (lo + hi) / 2
    n = np.zeros(3)
    n[a] = 1.0
    close = (gap - keep) / 2
    return [(n, mid, -n * close), (-n, -mid, n * close)]


def posed_bones(model):
    """World matrices (posed, as drawn) and the reference ones, by bone name."""
    names = [b["name"] for b in refbody.bones(model)]
    pose = anim0.rest_bones(model)
    ref = [b["world"] for b in refbody.bones(model)]
    return {n: (pose[k], ref[k]) for k, n in enumerate(names)}


def transfer_helmet(src, src_bones, V, target, lift=0.0):
    """Attach on target's head: the gear in the source's eyes frame, scaled by the skull, top on top;
    lift: raised by that much (units on the source's head, scaled like it: a cap worn over the eyes on
    its own model, its brim brought up on the forehead)."""
    hp, hr = src_bones[fi.HEAD]
    eyes_posed = hp @ np.linalg.inv(hr) @ src.eyes
    Ei = np.linalg.inv(eyes_posed)
    hs, ht = fc.skull(src), fc.skull(target)
    k = fc.head_size(ht) / fc.head_size(hs)
    a_s = np.array([(hs[:, 0].min() + hs[:, 0].max()) / 2, (hs[:, 1].min() + hs[:, 1].max()) / 2, hs[:, 2].max()])
    a_t = np.array([(ht[:, 0].min() + ht[:, 0].max()) / 2, (ht[:, 1].min() + ht[:, 1].max()) / 2, ht[:, 2].max()])
    R_e = Ei[:3, :3]
    t_e = k * (Ei[:3, 3] - a_s) + a_t
    t_e[2] += k * lift
    return fi.eyes_to_bone(target, R_e, t_e, round(float(k), 3))


def girth_at(body, t, half=2.0):
    """Width + depth of the torso at the relative height t between the pelvis (0) and the neck (1)."""
    torso = body.verts(fi.TORSO)
    pel, neck = body.world["ValveBiped.Bip01_Pelvis"][2, 3], body.world[NECK][2, 3]
    z = pel + t * (neck - pel)
    c = torso[np.abs(torso[:, 2] - z) <= half]
    if len(c) < 20:
        return None
    return float(np.ptp(np.percentile(c[:, 0], [3, 97])) + np.ptp(np.percentile(c[:, 1], [3, 97])))


def gear_height(body, zc):
    """Relative height (pelvis 0, neck 1) of the gear as worn: zc, the median height of its vertices
    (where most of it is: a chest rig's pouches, not its shoulder straps)."""
    pel, neck = body.world["ValveBiped.Bip01_Pelvis"][2, 3], body.world[NECK][2, 3]
    return float(np.clip((zc - pel) / (neck - pel), 0.25, 0.8))


def transfer_torso(src, src_bones, bone, target, src_girth, t=None, drop=0.0):
    """Attach on target's spine bone: the gear in the source's bone frame, scaled by the torso's girth
    where it sits (t: its relative height, both bodies measured there; a chest rig on a slim soldier's
    belly isn't sized by a citizen's chest), else by the chest's."""
    bp, _br = src_bones[bone]
    Bi = np.linalg.inv(bp)
    k = fc.chest_girth(target) / src_girth
    if t is not None:
        gs, gt = girth_at(src, t), girth_at(target, t)
        if gs and gt:  # (within 15 % of the chest's ratio: a built-in vest's collar isn't the body)
            k = min(max(gt / gs, 0.85 * k), 1.15 * k)
    k = round(float(k), 3)
    pos = Bi[:3, 3] * k
    if drop:  # lowered by that much (units on the source's body, scaled like it), straight down
        pos = pos + target.world[bone][:3, :3].T @ np.array([0.0, 0.0, -drop * k])
    return pos, fi.matrix_angles(Bi[:3, :3]), k


def lua_vec(v, n=2):
    return "Vector(" + _nz(", ".join(f"{x:.{n}f}" for x in v)) + ")"


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def backpack_depth(G, body, face):
    """How far a worn backpack (vertices G) sticks out behind the soldier's back (body vertices, facing
    yaw face in degrees): weapons carried on the back go over it by that much. Measured straight behind
    him, the back surface taken near his middle (not the arms); a roll worn across the body counts where
    it crosses the back."""
    d = -np.array([math.cos(math.radians(face)), math.sin(math.radians(face)), 0.0])
    zlo, zhi = G[:, 2].min(), G[:, 2].max()
    B = body[(body[:, 2] > zlo) & (body[:, 2] < zhi)]
    lat = np.cross([0.0, 0.0, 1.0], d)
    c = B.mean(0)
    near = B[np.abs((B - c) @ lat) < 6]
    back = G[np.abs((G - c) @ lat) < 6]  # the pack behind his middle
    if not len(back):
        return 0.0, 0.0
    surface = (near @ d).max()
    depth = max(0.0, float((back @ d).max() - surface))
    # its half width behind the back (straps over the shoulders left out): a rifle slung over the
    # shoulder hangs beside it
    behind = G[(G @ d) > surface + 1.0]
    half = float(np.abs((behind - c) @ lat).max()) if len(behind) else 0.0
    return depth, half


def gear_mesh(pack, cls):
    """An item's worn look alone (the fit editor's mesh): the pack's playermodel in its reference pose,
    only the triangles of that item's bodygroups, its vertices renumbered. -> (pos, nrm, uv, tris, mats)"""
    draw = pack["models"][0]
    parts = bodyparts(draw)
    empty = empty_choices(parts)
    base = {b: empty.get(b, 0) for b in range(len(parts))}
    base_tris = {tuple(t) for t in posed(draw, base)[3]}
    it = next(i for i in pack["items"] if i["class"] == cls)
    sel = dict(base)
    for part, sub in it["show"]:
        b, s = find(parts, part, sub)
        sel[b] = s
    P, N, uv, tris, mats = posed(draw, sel)
    keep = [t for t in tris if tuple(t) not in base_tris]
    used = sorted({t[k] for t in keep for k in range(3)})
    new = {v: k for k, v in enumerate(used)}
    return P[used], N[used], uv[used], [(new[t[0]], new[t[1]], new[t[2]], t[3]) for t in keep], mats


def main():
    args = sys.argv[1:]
    preview = None
    if "--preview" in args:
        k = args.index("--preview")
        preview = args[k + 1]
        del args[k:k + 2]
    pack = PACKS[args[0]]
    targets = [l.strip() for l in Path(args[1]).read_text(encoding="utf-8").splitlines() if l.strip()]
    out = Path(args[2])
    draw = pack["models"][0]
    parts = bodyparts(draw)
    empty = empty_choices(parts)
    base = {b: empty.get(b, 0) for b in range(len(parts))}
    P0, _N0, _uv0, tris0, _m0 = posed(draw, base)
    base_tris = {tuple(t) for t in tris0}
    body = P0[sorted({t[k] for t in tris0 for k in range(3)})]  # the soldier himself (no gear)
    face = 0.0  # posed as the game animates it, the soldier faces +x (his reference pose faces -y)
    hidden = sorted({t[3] for t in tris0})  # what the empty selection still draws: the parts with no empty choice
    blocked = builtin_gear.builtin()
    items = []
    for it in pack["items"]:
        bgs, stored = {}, {}
        for part, sub in it["show"]:
            b, s = find(parts, part, sub)
            bgs[b] = s
        for part, sub in it.get("stored", it["show"]):
            b, s = find(parts, part, sub)
            stored[b] = s
        sel = {**base, **stored}  # the look on the ground: its centre and hull
        P, _N, _uv, tris, _mats = posed(draw, sel)
        keep = [t for t in tris if tuple(t) not in base_tris]  # the gear's own triangles
        # gear on a material the body also uses (hidden with it): the game draws those triangles apart,
        # read from the installed model (sh_modelgear_items.lua, I.SharedPartsMesh)
        shared_stored = bool({t[3] for t in keep} & set(hidden))
        used = sorted({t[k] for t in keep for k in range(3)})
        pieces = split_pieces(P[used]) if it.get("stored") and not shared_stored else None
        if it.get("stored_cut") is not None:  # stored: only below that fraction of its height (straps cut away)
            z0, z1 = P[used][:, 2].min(), P[used][:, 2].max()
            zc = z0 + it["stored_cut"] * (z1 - z0)
            keep = [t for t in keep if min(P[t[k]][2] for k in range(3)) <= zc]
            used = sorted({v for t in keep for v in t[:3] if P[v][2] <= zc})
            pieces = [(np.array([0.0, 0.0, -1.0]), -zc, np.zeros(3))]  # one piece: the side below the plane
        if pieces:  # drawn in two halves, cut in the gap between them and pushed together
            P = P.copy()
            for normal, dist, off in pieces:
                side = [v for v in used if P[v] @ normal > dist]
                P[side] += off
        V = P[used]
        center = (V.min(0) + V.max(0)) / 2
        hull = hull_points(V - center)
        # the gear as worn (its straps too): its box in the model's space, to frame a character wearing it
        Pw, _Nw, _uvw, trisw, _mw = posed(draw, {**base, **bgs})
        wt = [t for t in trisw if tuple(t) not in base_tris]
        shared_worn = bool({t[3] for t in wt} & set(hidden))
        wv = sorted({t[k] for t in wt for k in range(3)})
        worn_box = (Pw[wv].min(0), Pw[wv].max(0))
        worn_z = float(np.median(Pw[wv][:, 2]))
        back_depth, back_half = backpack_depth(Pw[wv], body, face) if it["slot"] == "Rucksack" else (None, None)
        items.append({**it, "sel": sel, "bgs": bgs, "stored_bgs": stored, "V": V, "P": P, "tris": keep, "center": center,
                      "hull": hull, "pieces": pieces, "worn_box": worn_box, "back_depth": back_depth,
                      "shared": [k for k, s in (("stored", shared_stored), ("worn", shared_worn)) if s],
                      "worn_z": worn_z,
                      "back_half_width": back_half})
        print(f"{it['class']:40} {len(keep):5} triangles, {len(hull):2} hull points, size {np.round(V.max(0) - V.min(0), 1)}"
              f"{'  in 2 pieces' if pieces else ''}{f'  {back_depth:.1f} behind the back, {back_half:.1f} half wide' if back_depth else ''}"
              f"{'  parts on the body material (' + ', '.join(items[-1]['shared']) + ')' if items[-1]['shared'] else ''}")
    if preview:
        write_preview(draw, items, preview)

    # fits: transferred from the pack's playermodel to every target
    mr.BODYGROUPS[draw.lower()] = dict(base)  # the soldier himself, no gear (posed() leaves its last selection)
    src = fi.Body(draw)
    src_bones = posed_bones(draw)
    src_girth = fc.chest_girth(src)
    for it in items:
        it["height"] = gear_height(src, it["worn_z"])
    fits = {it["class"]: {} for it in items}
    for m in targets:
        try:
            body = fi.Body(m)
        except Exception as e:  # noqa: BLE001
            print(f"{m}: skipped ({e})")
            continue
        for it in items:
            if m.lower() in blocked.get(it["slot"], ()):
                continue
            try:
                if it["slot"] in HEAD_SLOTS:
                    if body.eyes is None or not body.has(fi.HEAD) or len(body.verts([fi.HEAD])) <= 20:
                        continue
                    fits[it["class"]][m] = transfer_helmet(src, src_bones, it["V"], body, it.get("lift", 0.0))
                else:
                    bone = BONE[it["slot"]]
                    if not body.has(bone, NECK) or len(body.verts(fi.TORSO)) < 50:
                        continue
                    fits[it["class"]][m] = transfer_torso(src, src_bones, bone, body, src_girth, it["height"],
                                                          it.get("drop", 0.0))
            except Exception as e:  # noqa: BLE001
                print(f"  {it['class']} on {m}: {e}")
    # fits approved in the fit editor are final (tools/fit_locks.txt)
    locks = fit_locks.load()
    for it in items:
        per = fits[it["class"]]
        for m in list(per):
            lk = fit_locks.get(locks, it["class"], m)
            if lk is not None:
                per[m] = lk
    for it in items:
        it["attach"] = fits[it["class"]].get(fi.REF)
    # the pack's own playermodels: the bodygroups that show each item there
    own = {}
    for m in pack["models"]:
        pm_parts = bodyparts(m)
        own[m] = {it["class"]: {find(pm_parts, part, sub)[0]: find(pm_parts, part, sub)[1] for part, sub in it["show"]}
                  for it in items}
    write_lua(pack, draw, base, hidden, items, own, targets, fits, out)


def write_preview(draw, items, path):
    import mount_check as mc  # noqa: E402
    from PIL import Image, ImageDraw
    face = mc.facing_yaw(draw)
    S = 220
    sheet = Image.new("RGB", (S * 2 * 3, (S + 20) * ((len(items) + 2) // 3)), (24, 24, 26))
    d = ImageDraw.Draw(sheet)
    for k, it in enumerate(items):
        _P, N, uv, tris, mats = posed(draw, it["sel"])
        P = it["P"]  # (moved pieces included)
        scene = (P, N, uv, it["tris"], mats)
        x, y = (k % 3) * 2 * S, (k // 3) * (S + 20)
        for v, yaw in enumerate((35, 200)):
            img = mr.rasterize(*scene, face + yaw, 15, it["V"], size=S)
            bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
            bg.alpha_composite(img)
            sheet.paste(bg.convert("RGB"), (x + v * S, y))
        d.text((x + 4, y + S + 3), f"{it['class']}  {it['name'][0]}", fill=(240, 220, 120))
    sheet.save(path, quality=90)


def write_lua(pack, draw, base, hidden, items, own, targets, fits, out):
    L = [f"-- {pack['title']}: its gear as Advanced Inventory System items. Generated by",
         "-- advanced-inventory/tools/modelgear_pack.py (do not edit by hand). The gear is drawn with the",
         "-- playermodel addon's own model (Workshop " + pack["wid"] + "): nothing of it is shipped here.",
         "AdvInv = AdvInv or {}",
         "AdvInv.ModelGearPacks = AdvInv.ModelGearPacks or {}",
         "local pack = {",
         f"    key = {lua_str(pack['key'])}, title = {lua_str(pack['title'])}, wid = \"{pack['wid']}\",",
         f"    author = {lua_str(pack['author'])},",
         f"    category = {{ {lua_str(pack['category'][0])}, {lua_str(pack['category'][1])} }},",
         f"    model = {lua_str(draw.lower())},",
         "    blank = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(base.items())) + " },",
         "    hide = { " + ", ".join(str(h) for h in hidden) + " },",
         "    items = {"]
    for it in items:
        a = it["attach"]
        L.append(f"        {{ class = {lua_str(it['class'])}, slot = \"{it['slot']}\", name = {{ {lua_str(it['name'][0])}, {lua_str(it['name'][1])} }},")
        L.append(f"          mass = {it['mass']}, armor = {it.get('armor', 0)}, load = {it.get('load', 0)},")
        L.append("          bodygroups = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(it["bgs"].items())) + " },")
        if it["stored_bgs"] != it["bgs"]:
            L.append("          stored = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(it["stored_bgs"].items())) + " },")
        if it["pieces"]:  # { normal, distance, move }: a clip plane in the model's space, and its side's move
            L.append("          pieces = { " + ", ".join(f"{{ {lua_vec(n, 0)}, {d:.3f}, {lua_vec(o, 3)} }}" for n, d, o in it["pieces"]) + " },")
        L.append(f"          origin = {lua_vec(it['center'], 3)},")
        L.append("          hull = { " + ", ".join(lua_vec(h, 2) for h in it["hull"]) + " },")
        L.append(f"          worn_box = {{ {lua_vec(it['worn_box'][0], 1)}, {lua_vec(it['worn_box'][1], 1)} }},")
        if it.get("rigged"):  # bonemerged on the wearer (parts on the legs follow them): no rigid fit
            L.append("          rigged = true,")
        if it["shared"]:  # looks with parts on a material of the hidden body: drawn apart by the game
            L.append("          shared = { " + ", ".join(f"{k} = true" for k in it["shared"]) + " },")
        if it["back_depth"]:  # (a backpack: weapons carried on the back go over it by that much)
            L.append(f"          back_depth = {it['back_depth']:.1f}, back_half_width = {it['back_half_width']:.1f},")
        if a is not None:
            L.append(f"          attach = {{ bone = \"{BONE[it['slot']]}\", pos = {lua_vec(a[0])}, ang = Angle({a[1][0]:.1f}, {a[1][1]:.1f}, {a[1][2]:.1f}), scale = {a[2]:g} }},")
        L.append("          on = {")
        for m, per in own.items():
            L.append(f"              [{lua_str(m.lower())}] = {{ " + ", ".join(f"[{b}] = {v}" for b, v in sorted(per[it['class']].items())) + " },")
        L.append("          } },")
    L.append("    },")
    L.append("    fits = {")
    L.append("        models = {")
    L += [f"            {lua_str(m.lower())}," for m in targets]
    L.append("        },")
    L.append("        items = {")
    for it in items:
        parts = []
        for m in targets:
            f = fits[it["class"]].get(m)
            if f is None:
                parts.append("")
                continue
            p, ang, s = f
            parts.append(_nz(" ".join([f"{x:.2f}" for x in p] + [f"{x:.1f}" for x in ang] + [f"{s:g}"])))
        L.append(f"            [{lua_str(it['class'])}] = \"{'|'.join(parts)}\",")
    L.append("        },")
    L.append("    },")
    L.append("}")
    L.append("if AdvInv.AddModelGearPack then AdvInv.AddModelGearPack(pack) else table.insert(AdvInv.ModelGearPacks, pack) end")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"-> {out} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
