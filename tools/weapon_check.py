"""Offline check of the weapons (dev tool, not in the .gma), reproducing lua/advinv/cl_weapons.lua:
  1. inventory icons: each weapon item seen from the side, fitted to its equipment box and container tile;
  2. weapons on the body: loadouts on playermodels (reference pose), with and without a backpack.
Weapon models are posed in their rest frame (first frame of their idle sequence, see anim0.py), like
the game draws them.

    python weapon_check.py <out_dir>
"""
import re
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import mount_check as mc  # noqa: E402

LUA = Path(__file__).resolve().parents[1] / "lua"
SLOT_BOX = {"PrimaryWep": (350, 100), "SecondaryWep": (225, 100), "RocketLauncher": (600, 100)}
BODIES = ["models/player/kleiner.mdl", "models/player/group01/male_07.mdl"]


def lua_vec(s):
    return np.array([float(x) for x in s.split(",")])


def weapon_mounts():
    t = (LUA / "advinv" / "cl_weapons.lua").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'(\w+) = \{ bone = "([^"]+)", pos = Vector\(([^)]*)\), out = Vector\(([^)]*)\), '
                         r'ang = Angle\(([^)]*)\) \}', t):
        out[m.group(1)] = {"bone": m.group(2), "pos": lua_vec(m.group(3)), "out": lua_vec(m.group(4)),
                           "ang": list(lua_vec(m.group(5)))}
    gap = float(re.search(r"C\.WeaponMountGap = C\.WeaponMountGap or ([\d.]+)", t).group(1))
    return out, gap


def weapon_items():
    items = {}
    for p in sorted((LUA / "entities").glob("advinv_hl2_*.lua")):
        t = p.read_text(encoding="utf-8")
        items[p.stem] = (re.search(r'ENT\.Model = "([^"]+)"', t).group(1), re.search(r'ENT\.AdvInvCategory = "(\w+)"', t).group(1))
    return items


_posed = {}


def posed(model):
    if model not in _posed:
        P, N, uv, tris, mats = anim0.posed_mesh(model)
        used = sorted({t[k] for t in tris for k in range(3)})
        _posed[model] = ((P, N, uv, tris, mats), P[used].min(0), P[used].max(0), core(P, tris), muzzle_back(model, P[used]))
    return _posed[model][:3]


def muzzle_back(model, P):
    """Like g.muzzleBack in cl_weapons.lua: the 'muzzle' attachment (rest pose) is on the -X half."""
    import studio  # noqa: E402
    m = studio.Model(mr.vpk_read(model))
    W = anim0.rest_bones(model)
    for a in m.attachments:
        if a["name"].lower() == "muzzle":
            L = np.vstack([a["local"], [0, 0, 0, 1]])
            return (W[a["bone"]] @ L)[0, 3] < (P[:, 0].min() + P[:, 0].max()) / 2
    return False


def core(P, tris):
    """Like coreBand in cl_weapons.lua: area-weighted 5 %..95 % band of the surface on Y and Z."""
    T = np.array([[P[a], P[b], P[c]] for a, b, c, _ in tris])
    area = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1) / 2
    out = {}
    for ax, name in ((1, "y"), (2, "z")):
        v = T[:, :, ax].mean(1)
        o = np.argsort(v, kind="stable")
        cum = np.cumsum(area[o])
        total = cum[-1]
        out[name] = (v[o][np.searchsorted(cum, total * 0.05)], v[o][np.searchsorted(cum, total * 0.95)])
    return out


def icon(model, W, H):
    mesh, mn, mx = posed(model)
    c = (mn + mx) / 2
    scale = min(W * 0.88 / (mx[0] - mn[0]), H * 0.8 / (mx[2] - mn[2]))
    img = mr.ortho(*mesh, W, H, c, scale, yaw=90 if _posed[model][4] else -90, pitch=0)
    bg = Image.new("RGBA", (W, H), (32, 34, 40, 255))
    bg.alpha_composite(img)
    d = ImageDraw.Draw(bg)
    d.rectangle((0, 0, W - 1, H - 1), outline=(120, 120, 120), width=3)
    return bg.convert("RGB")


def hull(model):
    d = mr.vpk_read(model)
    return np.array(struct.unpack_from("<3f", d, 104)), np.array(struct.unpack_from("<3f", d, 116))


def place_weapon(model, mount, bones, extra, gap):
    """Like I.DrawMountedWeapons: weapon centre on the surface point, pushed out by half its
    thickness + extra + gap."""
    (P, N, uv, tris, mats), mn, mx = posed(model)
    cy, cz = _posed[model][3]["y"], _posed[model][3]["z"]
    c = (mn + mx) / 2
    R = mr.rot_matrix(*mount["ang"])
    if _posed[model][4]:  # muzzle on -X: turned around its up axis
        R = R @ np.array([[-1, 0, 0], [0, -1, 0], [0, 0, 1.0]])
    if cy[1] - cy[0] > cz[1] - cz[0]:  # the thinner side rests on the body
        R = R @ np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0.0]])  # roll 90 about the barrel
        c[2] = (cz[0] + cz[1]) / 2
        half = (cz[1] - cz[0]) / 2
    else:
        c[1] = (cy[0] + cy[1]) / 2
        half = (cy[1] - cy[0]) / 2
    out = mount["out"] / np.linalg.norm(mount["out"])
    local = mount["pos"] + out * (half + extra + gap) - R @ c
    Bw = bones[mount["bone"]]
    M = Bw[:3, :3] @ R
    t = Bw[:3, :3] @ local + Bw[:3, 3]
    return (P @ M.T + t, N @ M.T, uv, tris, mats), 2 * half + gap


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    mounts, gap = weapon_mounts()
    items = weapon_items()

    # 1. icons: equipment box + container tile (wide when the gun is long)
    rows = []
    for cls, (model, cat) in items.items():
        W, H = SLOT_BOX[cat]
        _, mn, mx = posed(model)
        wide = (mx[0] - mn[0]) / (mx[2] - mn[2]) > 2.2
        tile = icon(model, 184 if wide else 88, 88)
        row = Image.new("RGB", (620 + 200, 110), (24, 25, 28))
        row.paste(icon(model, W, H), (5, 5))
        row.paste(tile, (630, 11))
        ImageDraw.Draw(row).text((10, 8), f"{cls} ({cat})", fill=(255, 220, 90))
        rows.append(row)
    sheet = Image.new("RGB", (820, 110 * len(rows)))
    for k, r in enumerate(rows):
        sheet.paste(r, (0, k * 110))
    sheet.save(out / "icons.png")
    print("icons:", len(rows))

    # 2. loadouts on the body
    sack = {c: (m, a) for c, m, a, _ in mc.worn_items()}
    loadouts = [
        ("AR2 + pistol + RPG", {"PrimaryWep": "advinv_hl2_ar2", "SecondaryWep": "advinv_hl2_pistol",
                                "RocketLauncher": "advinv_hl2_rpg"}, None),
        ("same + jetpack", {"PrimaryWep": "advinv_hl2_ar2", "SecondaryWep": "advinv_hl2_pistol",
                            "RocketLauncher": "advinv_hl2_rpg"}, "advinv_jetpack"),
        ("shotgun + .357 + suitcase", {"PrimaryWep": "advinv_hl2_shotgun", "SecondaryWep": "advinv_hl2_357"}, "advinv_suitcase"),
        ("crossbow", {"PrimaryWep": "advinv_hl2_crossbow"}, None),
    ]
    views = [("back", 180, 10), ("left", 90, 5), ("front-right", -40, 8)]
    S = 300
    for pm in BODIES:
        body, bones, face = mc.load_body(pm), mc.body_bones(pm), mc.facing_yaw(pm)
        sheet = Image.new("RGB", (S * len(views), S * len(loadouts)), (40, 42, 46))
        for row, (title, guns, bag) in enumerate(loadouts):
            scene = body
            extra = 0.0
            if bag:
                m, a = sack[bag]
                scene = mc.merge(scene, mc.place_item(m, a, bones))
                hmn, hmx = hull(m)
                extra = float(np.min(hmx - hmn)) * a.get("scale", 1)
            primary = 0.0
            for cat in ("PrimaryWep", "RocketLauncher", "SecondaryWep"):
                if cat not in guns:
                    continue
                e = 0.0 if cat == "SecondaryWep" else extra + (primary if cat == "RocketLauncher" else 0.0)
                mesh, thick = place_weapon(items[guns[cat]][0], mounts[cat], bones, e, gap)
                scene = mc.merge(scene, mesh)
                if cat == "PrimaryWep":
                    primary = thick
            P = scene[0][sorted({t[k] for t in scene[3] for k in range(3)})]
            fit = P[P[:, 2] > 25]  # from the thighs up
            for col, (vn, yaw, pitch) in enumerate(views):
                img = mr.rasterize(*scene, face + yaw, pitch, fit, size=S)
                bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
                bg.alpha_composite(img)
                sheet.paste(mc.label(bg.convert("RGB"), f"{title} - {vn}"), (col * S, row * S))
        sheet.save(out / f"loadouts_{Path(pm).stem}.png")
        print("loadouts:", Path(pm).stem)


if __name__ == "__main__":
    mr.WORK.mkdir(parents=True, exist_ok=True)
    main()
