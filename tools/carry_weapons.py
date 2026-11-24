"""The long guns of other addons whose carry positions are computed and set offline (dev tool, not in
the .gma): tools/carry_weapons.txt, read by fit_carry.py (positions per playermodel) and so listed in
the fit editor (one item per weapon and carry mode, approved like worn gear).

    python carry_weapons.py scan [folder or .gma ...]
        Reads the weapons (lua/weapons/<class>.lua or <class>/shared.lua) of the given addons, unpacked
        folders or Workshop .gma files (default: the game's addons folder and its Workshop downloads),
        and writes carry_weapons.txt: every long gun (its AdvInvCategory, else held like one: ar2 / smg
        / shotgun / crossbow hold types a primary weapon, rpg a launcher, as the inventory's rule in
        sh_generic.lua) whose world model can be read (MDL_EXTRA_DIRS: other addons' content). The weapon files
        are only read as text: nothing in them is run.
    python carry_weapons.py update
        For carry_editor.bat: scan (the default folders and ADVINV_WEAPON_DIRS, ";" separated), then
        fit_carry.py --current if a listed weapon has no carry positions yet (the first time: a few
        minutes; the positions approved in the editor are kept).
    python carry_weapons.py list
        Shows the list.

carry_weapons.txt (edit it freely; a line starting with # is left out):
    class <TAB> PrimaryWep or RocketLauncher <TAB> world model <TAB> name <TAB> where it was found
The base game's long guns (weapon_ar2...) are always in fit_carry.py and not listed here.
"""
import re
import struct
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
LIST = TOOLS / "carry_weapons.txt"
GAME = TOOLS.parent.parent.parent  # garrysmod/
WORKSHOP = GAME.parent.parent.parent / "workshop" / "content" / "4000"
BUILTIN = {"weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_rpg"}
# held like a long gun
GUN_HOLDS = {"ar2", "smg", "shotgun", "crossbow", "rpg"}

FIELD = {
    "name": r'SWEP\.PrintName\s*=\s*"([^"]*)"',
    "model": r'SWEP\.WorldModel\s*=\s*"([^"]*)"',
    "hold": r'SWEP\.HoldType\s*=\s*"([^"]*)"',
    "normal_hold": r'SWEP\.NormalHoldType\s*=\s*"([^"]*)"',
    "ammo": r'SWEP\.Primary\.Ammo\s*=\s*"([^"]*)"',
    "base": r'SWEP\.Base\s*=\s*"([^"]*)"',
    "category": r'SWEP\.AdvInvCategory\s*=\s*"([^"]*)"',
}


def gma_files(path):
    """{name: bytes} of the lua/weapons files of a Garry's Mod addon package (.gma), read as data."""
    d = Path(path).read_bytes()
    if d[:4] != b"GMAD":
        return {}
    o = 4 + 1 + 8 + 8  # magic, version, steamid, timestamp
    while d[o] != 0:  # required content
        o = d.index(b"\0", o) + 1
    o += 1
    for _ in range(3):  # name, description, author
        o = d.index(b"\0", o) + 1
    o += 4  # addon version
    entries = []
    while True:
        (num,) = struct.unpack_from("<I", d, o)
        o += 4
        if num == 0:
            break
        end = d.index(b"\0", o)
        name = d[o:end].decode("utf-8", "replace").lower()
        o = end + 1
        (size,) = struct.unpack_from("<q", d, o)
        o += 8 + 4  # size, crc
        entries.append((name, size))
    out = {}
    for name, size in entries:
        if name.startswith("lua/weapons/") and name.endswith(".lua"):
            out[name] = d[o:o + size]
        o += size
    return out


def weapon_sources(roots):
    """{class: (lua text, where)} of every weapon found (folder addons and .gma packages)."""
    found = {}

    def add(rel, text, where):
        parts = rel.split("/")  # lua/weapons/<class>.lua or lua/weapons/<class>/<file>.lua
        if len(parts) == 3:
            cls = parts[2][:-4]
        elif len(parts) == 4 and parts[3] in ("shared.lua", "init.lua", "cl_init.lua"):
            cls = parts[2]
        else:
            return
        old = found.get(cls)
        found[cls] = ((old[0] + "\n") if old and old[1] == where else "") + text, where

    for root in roots:
        root = Path(root)
        if root.suffix.lower() == ".gma" and root.is_file():
            try:
                for name, data in gma_files(root).items():
                    add(name, data.decode("utf-8", "replace"), root.name)
            except (ValueError, IndexError, struct.error):
                print(f"{root}: not a readable .gma, left out")
            continue
        for addon in ([root] if (root / "lua" / "weapons").is_dir() else sorted(p for p in root.iterdir() if p.is_dir())
                      if root.is_dir() else []):
            wdir = addon / "lua" / "weapons"
            if wdir.is_dir():
                for f in sorted(wdir.rglob("*.lua")):
                    add(f.relative_to(addon).as_posix().lower(), f.read_text(encoding="utf-8", errors="replace"), addon.name)
            for g in sorted(addon.glob("*.gma")):  # Workshop downloads: <id>/<file>.gma
                try:
                    for name, data in gma_files(g).items():
                        add(name, data.decode("utf-8", "replace"), f"{addon.name}/{g.name}")
                except (ValueError, IndexError, struct.error):
                    print(f"{g}: not a readable .gma, left out")
    return found


def fields(text):
    out = {}
    for k, rx in FIELD.items():
        m = re.search(rx, text)
        if m:
            out[k] = m.group(1)
    return out


def scan(roots):
    sys.path.insert(0, str(TOOLS))
    import mdl_render as mr
    src = weapon_sources(roots)
    info = {cls: fields(text) for cls, (text, _) in src.items()}

    def get(cls, key, depth=0):  # a field, from the weapon or its bases
        v = info.get(cls, {}).get(key)
        if v is None and depth < 8 and info.get(cls, {}).get("base") in info:
            return get(info[cls]["base"], key, depth + 1)
        return v

    bases = {f.get("base") for f in info.values()}
    rows, skipped = [], []
    for cls in sorted(info):
        if cls in BUILTIN or cls in bases or cls.endswith("_base"):
            continue
        model = (get(cls, "model") or "").lower().replace("\\", "/")
        hold = (get(cls, "hold") or get(cls, "normal_hold") or "").lower()
        ammo = (get(cls, "ammo") or "").lower()
        cat = get(cls, "category")
        if not cat:
            if hold not in GUN_HOLDS:  # (tools, hands, a gas mask... are weapons held otherwise)
                continue
            cat = "RocketLauncher" if hold == "rpg" or ammo == "rpg_round" else "PrimaryWep"
        if cat not in ("PrimaryWep", "RocketLauncher"):
            continue
        if not model or not mr.vpk_read(model):
            skipped.append(f"{cls} ({model or 'no world model'})")
            continue
        name = (get(cls, "name") or cls).replace("\t", " ")
        rows.append((cls, cat, model, name, src[cls][1]))
    lines = ["# Long guns of other addons: carry positions computed by fit_carry.py, set in the fit editor.",
             "# class\tslot\tworld model\tname\twhere it was found  (a line starting with # is left out)"]
    lines += ["\t".join(r) for r in rows]
    LIST.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(rows)} long guns -> {LIST}")
    for r in rows:
        print(f"  {r[0]:28} {r[1]:15} {r[3]}  ({r[2]}, {r[4]})")
    if skipped:
        print(f"left out, world model not found (add its folder to MDL_EXTRA_DIRS): {', '.join(skipped)}")


def load(path=LIST):
    """[(class, slot, model, name)] of carry_weapons.txt."""
    out = []
    if Path(path).exists():
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if line.strip() and not line.startswith("#"):
                f = line.split("\t")
                if len(f) >= 3:
                    out.append((f[0], f[1], f[2], f[3] if len(f) > 3 else f[0]))
    return out


def update():
    import os
    import subprocess
    roots = [GAME / "addons", WORKSHOP] + [Path(d) for d in os.environ.get("ADVINV_WEAPON_DIRS", "").split(";") if d.strip()]
    scan([r for r in roots if r.exists()])
    sys.path.insert(0, str(TOOLS))
    import carry_data
    sets, _aliases = carry_data.read()
    have = set(sets.get("default", {}))
    missing = [c for c, *_ in load() if c not in have]
    if missing:
        print(f"Carry positions to compute for: {', '.join(missing)} (on every playermodel: a few minutes)...", flush=True)
        r = subprocess.run([sys.executable, "-I", str(TOOLS / "fit_carry.py"), "--current"], cwd=str(TOOLS))
        if r.returncode:
            sys.exit(r.returncode)
    else:
        print("Every weapon already has its carry positions.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["scan"]:
        scan(args[1:] or [GAME / "addons", WORKSHOP])
    elif args[:1] == ["update"]:
        update()
    elif args[:1] == ["list"]:
        for row in load():
            print("\t".join(row))
    else:
        print(__doc__)
