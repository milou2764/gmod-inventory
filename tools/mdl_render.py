"""Rendu de modèles du jeu hors du jeu (outil de développement, non inclus dans le .gma) : sert à
mount_check.py (rasterize) ; peut aussi faire des icônes 128x128 (l'addon n'en livre plus).

Lit le modèle directement dans les VPK du jeu (.mdl + .vvd + .dx90.vtx), convertit ses textures
avec vtf2tga.exe (fourni avec Garry's Mod), le dessine en 3/4 avec numpy, puis le pose sur un sol
de béton en 128x128, comme les icônes d'entités de Garry's Mod.

Prérequis : Python 3, numpy et Pillow (pip install numpy pillow).
Utilisation (depuis ce dossier) :
    python mdl_render.py icon_jobs.json ../materials/entities
Un objet du fichier JSON :
    {"class": "advinv_bucket", "model": "models/props_junk/metalbucket01a.mdl",
     "yaw": 35, "pitch": 30, "rot": [p, y, r]}
yaw/pitch : angle de la caméra ; rot (facultatif) : rotation du modèle avant le rendu.
Le jeu est cherché à partir de l'emplacement du script, ou dans la variable GMOD_ROOT.
Les modèles sont lus dans les VPK du jeu ; pour ceux d'un addon, indiquer son dossier dans
la variable MDL_EXTRA_DIRS (plusieurs dossiers séparés par « ; »).
"""
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vpk  # noqa: E402

# tools -> advanced-inventory -> addons -> garrysmod -> GarrysMod
ROOT = Path(os.environ.get("GMOD_ROOT") or Path(__file__).resolve().parents[4])
BIN = ROOT / "bin"
VPKS = [ROOT / "garrysmod" / "garrysmod_dir.vpk",
        ROOT / "sourceengine" / "hl2_misc_dir.vpk",
        ROOT / "sourceengine" / "hl2_textures_dir.vpk"]
WORK = Path(tempfile.gettempdir()) / "advinv_icon_render"
GROUND = "concrete/concretefloor001a"
RENDER = 512
ICON = 128

_trees = []
# Dossiers d'addons consultés avant les VPK (variable MDL_EXTRA_DIRS, séparateur « ; »).
EXTRA_DIRS = [d for d in os.environ.get("MDL_EXTRA_DIRS", "").split(os.pathsep) if d]


def vpk_read(path):
    path = path.lower().replace("\\", "/")
    for d in EXTRA_DIRS:
        p = Path(d) / path
        if p.exists():
            return p.read_bytes()
    if not _trees:
        for v in VPKS:
            entries, start = vpk.read_tree(str(v))
            _trees.append((v, entries, start))
    for v, entries, start in _trees:
        if path in entries:
            return vpk.read_file(str(v), entries, start, path)
    return None


# ---------------------------------------------------------------- textures

_tex_cache = {}


def vtf_image(texture):
    """materials/<texture>.vtf -> PIL RGBA, via the game's vtf2tga.exe."""
    if texture in _tex_cache:
        return _tex_cache[texture]
    data = vpk_read(f"materials/{texture}.vtf")
    img = None
    if data:
        src = WORK / "tex" / (texture.replace("/", "__") + ".vtf")
        src.parent.mkdir(parents=True, exist_ok=True)
        src.write_bytes(data)
        dst = src.with_suffix(".tga")
        subprocess.run([str(BIN / "vtf2tga.exe"), "-i", str(src), "-o", str(dst)],
                       cwd=str(BIN), capture_output=True, timeout=60)
        if dst.exists():
            img = Image.open(dst).convert("RGBA")
    _tex_cache[texture] = img
    return img


def vmt_info(text):
    def val(key):
        m = re.search(r'"?\$' + key + r'"?\s+"?([^"\r\n]+?)"?\s*$', text, re.I | re.M)
        return m.group(1).strip() if m else None
    return val("basetexture"), val("translucent") == "1", val("alphatest") == "1"


def material(dirs, name):
    for d in dirs:
        path = f"materials/{d}{name}.vmt".replace("\\", "/").replace("//", "/")
        data = vpk_read(path)
        if data is None:
            continue
        text = data.decode("latin-1")
        base, translucent, alphatest = vmt_info(text)
        inc = re.search(r'"?include"?\s+"([^"]+)"', text, re.I)
        if base is None and inc:
            inc_data = vpk_read(inc.group(1))
            if inc_data:
                base, translucent, alphatest = vmt_info(inc_data.decode("latin-1"))
        if base:  # (the game also takes "...\NAME.vtf": backslashes, the extension given)
            base = base.replace("\\", "/").lower()
            base = base[:-4] if base.endswith(".vtf") else base
        img = vtf_image(base) if base else None
        return img, translucent, alphatest
    return None, False, False


# ---------------------------------------------------------------- model

def cstr(d, off):
    return d[off:d.index(b"\0", off)].decode("latin-1")


def _bodygroups():
    """playermodel_bodygroups.txt : « modèle bodypart=sous-modèle ... » par ligne (# : commentaire)."""
    out = {}
    f = Path(__file__).resolve().parent / "playermodel_bodygroups.txt"
    if f.exists():
        for line in f.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].split()
            if line:
                out[line[0].lower()] = {int(a): int(b) for a, b in (w.split("=") for w in line[1:])}
    return out


BODYGROUPS = _bodygroups()


def load_model(model):
    base = model[:-4].lower()
    groups = BODYGROUPS.get(base + ".mdl", {})
    mdl, vvd, vtx = vpk_read(base + ".mdl"), vpk_read(base + ".vvd"), vpk_read(base + ".dx90.vtx")
    if not (mdl and vvd and vtx):
        raise SystemExit(f"fichiers du modèle introuvables : {model}")
    i = lambda d, o: struct.unpack_from("<i", d, o)[0]

    # VVD : sommets du LOD 0 (avec la table de correction éventuelle)
    nfix, fixstart, vstart = i(vvd, 48), i(vvd, 52), i(vvd, 56)
    raw = []
    for k in range(i(vvd, 16)):
        o = vstart + k * 48
        raw.append(struct.unpack_from("<3f3f2f", vvd, o + 16))
    if nfix:
        verts = []
        for f in range(nfix):
            lod, src, num = struct.unpack_from("<3i", vvd, fixstart + f * 12)
            if lod >= 0:
                verts.extend(raw[src:src + num])
    else:
        verts = raw
    V = np.array(verts, dtype=np.float64)
    pos, nrm, uv = V[:, 0:3], V[:, 3:6], V[:, 6:8]

    # textures et famille de skins 0
    tex_names = [cstr(mdl, i(mdl, 208) + k * 64 + i(mdl, i(mdl, 208) + k * 64)) for k in range(i(mdl, 204))]
    dirs = [cstr(mdl, i(mdl, i(mdl, 216) + k * 4)).replace("\\", "/").lower() for k in range(i(mdl, 212))]
    nskinref, skinindex = i(mdl, 220), i(mdl, 228)
    skin0 = [struct.unpack_from("<h", mdl, skinindex + k * 2)[0] for k in range(nskinref)]
    mats = [material(dirs, t) for t in tex_names]

    # VTX : triangles du LOD 0, sous-modèle 0 de chaque bodypart (le bodygroup par défaut, comme en jeu ;
    # vide = rien : un bodygroup « blank » par défaut ne montre pas l'équipement des autres sous-modèles),
    # ou celui de playermodel_bodygroups.txt
    def read_tris(sg_size, st_size):
        tris = []
        mdl_bp, vtx_bp = i(mdl, 236), i(vtx, 32)
        for b in range(i(mdl, 232)):
            mb = mdl_bp + b * 16
            xb = vtx_bp + b * 8
            for m in range(i(mdl, mb + 4)):
                if m != groups.get(b, 0):
                    continue
                mm = mb + i(mdl, mb + 12) + m * 148
                if i(mdl, mm + 72) == 0:
                    break  # sous-modèle choisi vide (bodygroup « blank ») : rien de ce bodypart
                model_vert = i(mdl, mm + 84) // 48
                xm = xb + i(vtx, xb + 4) + m * 8
                xl = xm + i(vtx, xm + 4)  # LOD 0
                for s in range(i(mdl, mm + 72)):
                    ms = mm + i(mdl, mm + 76) + s * 116
                    mat_ref, mesh_vert = i(mdl, ms), i(mdl, ms + 12)
                    tex = skin0[mat_ref] if mat_ref < len(skin0) else mat_ref
                    xs = xl + i(vtx, xl + 4) + s * 9
                    for g in range(i(vtx, xs)):
                        xg = xs + i(vtx, xs + 4) + g * sg_size
                        nverts, voff, nidx, ioff, nstrips, soff = struct.unpack_from("<6i", vtx, xg)
                        gverts = [struct.unpack_from("<H", vtx, xg + voff + k * 9 + 4)[0] for k in range(nverts)]
                        gidx = struct.unpack_from(f"<{nidx}H", vtx, xg + ioff)
                        for st in range(nstrips):
                            xst = xg + soff + st * st_size
                            sn, so = struct.unpack_from("<2i", vtx, xst)
                            flags = vtx[xst + 18]
                            idx = gidx[so:so + sn]
                            conv = lambda k: model_vert + mesh_vert + gverts[k]
                            if flags & 2:  # tristrip
                                for k in range(len(idx) - 2):
                                    a, bb, c = idx[k], idx[k + 1], idx[k + 2]
                                    if k % 2:
                                        a, bb = bb, a
                                    tris.append((conv(a), conv(bb), conv(c), tex))
                            else:
                                for k in range(0, len(idx) - 2, 3):
                                    tris.append((conv(idx[k]), conv(idx[k + 1]), conv(idx[k + 2]), tex))
                break  # bodygroup par défaut seulement
        return tris

    # en-têtes des strip groups et strips : 25 et 27 octets, ou 33 et 35 avec le studiomdl récent
    # (numTopologyIndices, topologyOffset en plus) ; la mauvaise taille donne des indices hors limites
    for sizes in ((25, 27), (33, 35)):
        try:
            tris = read_tris(*sizes)
        except (IndexError, struct.error):
            continue
        if tris and max(max(t[:3]) for t in tris) < len(pos):
            return pos, nrm, uv, tris, mats
    raise SystemExit(f"triangles illisibles (.vtx) : {model}")


# ---------------------------------------------------------------- rendering

def rot_matrix(p, y, r):
    p, y, r = map(math.radians, (p, y, r))
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return np.array([
        [cp * cy, sr * sp * cy - cr * sy, cr * sp * cy + sr * sy],
        [cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy],
        [-sp, sr * cp, cr * cp],
    ])


def render(job):
    pos, nrm, uv, tris, mats = load_model(job["model"])
    if "rot" in job:
        R = rot_matrix(*job["rot"])
        pos, nrm = pos @ R.T, nrm @ R.T
    used = sorted({t[k] for t in tris for k in range(3)})
    return rasterize(pos, nrm, uv, tris, mats, job.get("yaw", 35), job.get("pitch", 25), pos[used])


def rasterize(pos, nrm, uv, tris, mats, yaw, pitch, fit, size=RENDER):
    """Draws the triangles seen from (yaw, pitch) degrees around the points `fit`, which fill the
    image; triangles too close to the camera are skipped. Returns a size x size RGBA image."""
    RENDER = size  # noqa: N806 (same name as the module constant: the loop below uses it)
    center = (fit.min(0) + fit.max(0)) / 2
    radius = np.linalg.norm(fit.max(0) - fit.min(0)) / 2

    yaw, pitch = math.radians(yaw), math.radians(pitch)
    to_cam = np.array([math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)])
    fwd = -to_cam
    right = np.cross(fwd, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    cam = center + to_cam * radius * 4
    near = radius
    rel = pos - cam
    xc, yc, zc = rel @ right, rel @ up, rel @ fwd
    with np.errstate(divide="ignore", invalid="ignore"):
        px, py = xc / zc, yc / zc
    frel = fit - cam
    fz = frel @ fwd
    fx, fy = (frel @ right) / fz, (frel @ up) / fz
    minx, maxx, miny, maxy = fx.min(), fx.max(), fy.min(), fy.max()
    scale = RENDER * 0.94 / max(maxx - minx, maxy - miny)
    sx = (px - (minx + maxx) / 2) * scale + RENDER / 2
    sy = RENDER / 2 - (py - (miny + maxy) / 2) * scale

    return _fill(sx, sy, zc, near, nrm, uv, tris, mats, to_cam, right, RENDER, RENDER)



_TEX = {}  # id(image) -> (image, uint8 array): the textures are converted once, not at every view


def _tex_array(img):
    hit = _TEX.get(id(img))
    if hit is None or hit[0] is not img:
        if len(_TEX) > 96:  # bounded: a tool going through many playermodels
            _TEX.pop(next(iter(_TEX)))
        hit = _TEX[id(img)] = (img, np.asarray(img))
    return hit[1]


def _fill(sx, sy, zc, near, nrm, uv, tris, mats, to_cam, right, W, H):
    """Triangles already projected (screen sx, sy; depth zc) -> W x H RGBA image."""
    light1 = to_cam + np.array([0.0, 0.0, 0.9]) + right * 0.6
    light1 /= np.linalg.norm(light1)
    light2 = -right * 0.8 + np.array([0.0, 0.0, 0.2])
    light2 /= np.linalg.norm(light2)

    zbuf = np.full((H, W), np.inf)
    rgb = np.zeros((H, W, 3))
    alpha = np.zeros((H, W))
    tex_arrays = [(_tex_array(m[0]) if m[0] else None, m[1], m[2]) for m in mats]

    for i0, i1, i2, t in tris:
        if min(zc[i0], zc[i1], zc[i2]) < near:
            continue
        xs, ys = sx[[i0, i1, i2]], sy[[i0, i1, i2]]
        x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, W - 1)
        y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, H - 1)
        if x0 > x1 or y0 > y1:
            continue
        area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
        if abs(area) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((xs[1] - gx) * (ys[2] - gy) - (xs[2] - gx) * (ys[1] - gy)) / area
        w1 = ((xs[2] - gx) * (ys[0] - gy) - (xs[0] - gx) * (ys[2] - gy)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = zc[[i0, i1, i2]]
        inv = w0 / z[0] + w1 / z[1] + w2 / z[2]
        depth = 1 / inv
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        mask = inside & (depth < sub)
        if not mask.any():
            continue
        b0, b1, b2 = w0 / z[0] / inv, w1 / z[1] / inv, w2 / z[2] / inv
        u = b0 * uv[i0, 0] + b1 * uv[i1, 0] + b2 * uv[i2, 0]
        v = b0 * uv[i0, 1] + b1 * uv[i1, 1] + b2 * uv[i2, 1]
        n = (b0[..., None] * nrm[i0] + b1[..., None] * nrm[i1] + b2[..., None] * nrm[i2])
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        facing = (n @ to_cam) < 0
        n[facing] *= -1  # éclairage double face
        shade = 0.45 + 0.75 * np.clip(n @ light1, 0, 1) + 0.25 * np.clip(n @ light2, 0, 1)
        tex, translucent, alphatest = tex_arrays[t] if t < len(tex_arrays) else (None, False, False)
        if tex is not None:
            h, w = tex.shape[:2]
            tx = np.clip(((u % 1.0) * w).astype(int), 0, w - 1)
            ty = np.clip(((v % 1.0) * h).astype(int), 0, h - 1)
            texel = tex[ty, tx]
            col, ta = texel[..., :3], texel[..., 3] / 255
        else:
            col, ta = np.full(u.shape + (3,), 160.0), np.ones(u.shape)
        if alphatest:
            mask &= ta >= 0.5
        a = ta if translucent else np.ones(u.shape)
        col = np.clip(col * shade[..., None], 0, 255)
        region_rgb = rgb[y0:y1 + 1, x0:x1 + 1]
        region_a = alpha[y0:y1 + 1, x0:x1 + 1]
        region_rgb[mask] = col[mask] * a[mask, None] + region_rgb[mask] * (1 - a[mask, None])
        region_a[mask] = np.maximum(region_a[mask], a[mask])
        sub[mask & (a >= 0.5)] = depth[mask & (a >= 0.5)]

    img = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def ortho(pos, nrm, uv, tris, mats, W, H, center, scale, yaw=-90.0, pitch=0.0):
    """Orthographic view (camera direction from yaw / pitch, degrees) centred on `center`, `scale`
    pixels per unit: what the inventory's weapon icons show."""
    yaw, pitch = math.radians(yaw), math.radians(pitch)
    to_cam = np.array([math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)])
    fwd = -to_cam
    right = np.cross(fwd, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    rel = pos - center
    sx = (rel @ right) * scale + W / 2
    sy = H / 2 - (rel @ up) * scale
    zc = rel @ fwd + 1000.0  # far away: perspective-correct weights become linear
    return _fill(sx, sy, zc, 0.0, nrm, uv, tris, mats, to_cam, right, W, H)

def compose(obj):
    obj = obj.resize((ICON - 16, ICON - 16), Image.LANCZOS)
    ground = vtf_image(GROUND) or Image.new("RGBA", (ICON, ICON), (120, 120, 115, 255))
    bg = ground.convert("RGB").resize((ICON, ICON), Image.LANCZOS).convert("RGBA")
    shadow = Image.new("RGBA", obj.size, (0, 0, 0, 0))
    shadow.putalpha(obj.getchannel("A").point(lambda a: int(a * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))
    bg.alpha_composite(shadow, (8 + 3, 8 + 5))
    bg.alpha_composite(obj, (8, 8))
    return bg.convert("RGB")


def main():
    jobs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for job in jobs:
        obj = render(job)
        obj.save(WORK / (job["class"] + "_rgba.png"))
        compose(obj).save(out / (job["class"] + ".png"))
        print("ok", job["class"])


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    main()
