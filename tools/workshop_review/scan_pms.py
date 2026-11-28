"""Playermodels of the downloaded collection items (their Lua read AS TEXT, never run).

    python -I scan_pms.py <tools> <coll_root> <out.tsv>

For each <coll_root>/<id>/: models registered by player_manager.AddValidModel (any .lua file), else
models/player/**.mdl. Per model: found (its .mdl in that folder), ValveBiped bones (head, spine4,
pelvis, clavicles, thighs), its bodyparts "name:count[:empty]" and the whole id's title.
"""
import json
import re
import struct
import sys
from pathlib import Path

TOOLS, ROOT, OUT = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
NEED = ("ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Pelvis",
        "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Thigh")
ADD = re.compile(r'AddValidModel\s*\(\s*["\']([^"\']+)["\']\s*,\s*["\']([^"\']+\.mdl)["\']', re.I)


def cstr(d, o):
    e = d.index(b"\0", o)
    return d[o:e].decode("latin-1")


def info(path):
    d = path.read_bytes()
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    if d[:4] != b"IDST":
        return None
    nb, bi = i(156), i(160)
    bones = {cstr(d, bi + k * 216 + i(bi + k * 216)) for k in range(nb)}
    parts = []
    for b in range(i(232)):
        bo = i(236) + b * 16
        subs, empty = i(bo + 4), False
        for s in range(subs):
            so = bo + i(bo + 12) + s * 148
            if i(so + 72) == 0:
                empty = True
        parts.append(f"{cstr(d, bo + i(bo)).strip()}:{subs}{':e' if empty else ''}")
    return nb, all(n in bones for n in NEED), parts


rows = []
for folder in sorted(p for p in ROOT.iterdir() if p.is_dir() and not p.name.startswith("_")):
    models = {}
    for lua in folder.rglob("*.lua"):
        try:
            t = lua.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for name, m in ADD.findall(t):
            models.setdefault(m.replace("\\", "/").lower(), name)
    if not models:
        for p in (folder / "models" / "player").rglob("*.mdl") if (folder / "models" / "player").exists() else []:
            models.setdefault(p.relative_to(folder).as_posix().lower(), "")
    if not models and (folder / "models").exists():
        # (no Lua and no models/player: any model that includes the player animations, m_anm/f_anm/z_anm)
        for p in (folder / "models").rglob("*.mdl"):
            try:
                d = p.read_bytes()
            except OSError:
                continue
            if b"m_anm.mdl" in d or b"f_anm.mdl" in d or b"z_anm.mdl" in d:
                models.setdefault(p.relative_to(folder).as_posix().lower(), "")
    for m, name in sorted(models.items()):
        p = folder / m
        if not p.exists():  # (case)
            cand = [q for q in folder.rglob(Path(m).name) if q.as_posix().lower().endswith(m)]
            p = cand[0] if cand else p
        if not p.exists():
            rows.append((folder.name, m, name, "missing", "", "", ""))
            continue
        r = info(p)
        if not r:
            rows.append((folder.name, m, name, "bad", "", "", ""))
            continue
        nb, vb, parts = r
        rows.append((folder.name, m, name, "ok", str(nb), "VB" if vb else "noVB", " ".join(parts)))
with open(OUT, "w", encoding="utf-8") as f:
    for r in rows:
        f.write("\t".join(r) + "\n")
print(len(rows), "models,", sum(1 for r in rows if r[3] == "ok" and r[5] == "VB"), "with ValveBiped")
