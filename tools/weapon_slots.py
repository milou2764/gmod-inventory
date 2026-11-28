"""Which inventory slot each weapon of a weapon pack gets (dev tool, not shipped), to find wrong ones.

Reads the packs' weapon files AS TEXT (never runs them): the SWEP fields the inventory's guess uses
(lua/advinv/sh_generic.lua guessCategory: hold type, ammo, magazine, ARC9's menu slot), through each
weapon's base chain, and what the weapon says it is (TFA's Type, ArcCW's Trivia_Class, its menu
category or name). Prints the weapons whose guessed slot disagrees with what they say they are.

    python -I weapon_slots.py FOLDER [FOLDER ...]      (extracted addons: their lua/weapons)
"""
import re
import sys
from pathlib import Path

ASSIGN = re.compile(r'^(\s*)SWEP\.([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)?)\s*=\s*(.+?)\s*$')
STR = re.compile(r'^(["\'])(.*?)\1')
NUM = re.compile(r'^-?\d+(?:\.\d+)?')
SECONDARY_HOLDS = {"pistol", "revolver", "melee", "knife", "fist", "grenade", "slam", "melee2"}


def value(raw):
    raw = raw.split("--")[0].strip().rstrip(",;")
    m = STR.match(raw)
    if m:
        return m.group(2)
    m = NUM.match(raw)
    if m:
        return float(m.group(0))
    if raw in ("true", "false"):
        return raw == "true"
    if raw.startswith("{"):
        return "{"
    return None  # (an expression: not read)


def parse(path):
    """Top-level SWEP fields of a weapon file (an unindented assignment wins over one inside a block)."""
    fields, depth = {}, {}
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = ASSIGN.match(line)
        if m:
            indent, key, raw = len(m.group(1)), m.group(2), m.group(3)
            v = value(raw)
            if v == "{":  # SWEP.Primary = { Ammo = "x", ClipSize = 30 }
                block, level = raw, raw.count("{") - raw.count("}")
                while level > 0 and i + 1 < len(lines):
                    i += 1
                    block += "\n" + lines[i]
                    level += lines[i].count("{") - lines[i].count("}")
                for k, vv in re.findall(r'\b(\w+)\s*=\s*("[^"]*"|\'[^\']*\'|-?\d+(?:\.\d+)?|true|false)', block):
                    sub = key + "." + k
                    if sub not in fields or indent < depth.get(sub, 99):
                        fields[sub], depth[sub] = value(vv), indent
            elif v is not None and (key not in fields or indent < depth.get(key, 99)):
                fields[key], depth[key] = v, indent
        i += 1
    return fields


def weapon_files(root):
    """class -> its files (lua/weapons/<class>.lua, or lua/weapons/<class>/shared.lua and the rest)."""
    out = {}
    for wdir in root.rglob("weapons"):
        if wdir.parent.name != "lua" or not wdir.is_dir():
            continue
        for p in wdir.iterdir():
            if p.is_file() and p.suffix == ".lua":
                out.setdefault(p.stem.lower(), []).append(p)
            elif p.is_dir():
                files = [p / n for n in ("shared.lua", "sh_init.lua", "init.lua", "cl_init.lua") if (p / n).exists()]
                if files:
                    out.setdefault(p.name.lower(), []).extend(files)
    return out


def resolved(cls, table, seen=None):
    seen = seen or set()
    own = table.get(cls)
    if own is None or cls in seen:
        return {}
    seen.add(cls)
    base = own.get("Base")
    merged = dict(resolved(base.lower(), table, seen)) if isinstance(base, str) else {}
    merged.update(own)
    return merged


def guess(f):
    """The inventory's guess (sh_generic.lua guessCategory)."""
    if f.get("AdvInvCategory"):
        return f["AdvInvCategory"]
    if f.get("EFTSUPPLYHUD"):
        return "SecondaryWep"
    hold = str(f.get("HoldType") or f.get("NormalHoldType") or f.get("HoldtypeActive")
               or f.get("RaisedHoldType") or f.get("HoldType_Aim") or f.get("HoldType_Hipfire") or "").lower()
    arc9 = bool(f.get("ARC9")) or str(f.get("Base") or "").lower().startswith("arc9")  # (base not in the pack)
    tacrp = bool(f.get("ArcticTacRP"))
    ammo = str((f.get("Ammo") if (arc9 or tacrp) and f.get("Ammo") else f.get("Primary.Ammo")) or "").lower()
    clip = f.get("ClipSize") if (arc9 or tacrp) and isinstance(f.get("ClipSize"), float) else f.get("Primary.ClipSize")
    clip = clip if isinstance(clip, float) else -1
    if any(w in ammo for w in ("rpg", "rocket", "missile", "warhead")) or re.search(r"[po]g-?7", ammo)             or (hold == "rpg" and clip < 1):
        return "RocketLauncher"
    if tacrp:  # (its type, then its menu slot: 0-1 sidearms, 2-3 long guns)
        if "launcher" in str(f.get("SubCatType") or "").lower():
            return "RocketLauncher"
        if isinstance(f.get("Slot"), float):
            if f["Slot"] <= 1:
                return "SecondaryWep"
            if f["Slot"] <= 3:
                return "PrimaryWep"
    # (NC SWEPs and others: SubCatType "1Pistol", "4Assault Rifle"...; ARC9: Class, before its menu slot)
    sub = str(f.get("SubCatType") or (f.get("Class") if arc9 and isinstance(f.get("Class"), str) else "") or "").lower()
    if "launcher" in sub:
        return "RocketLauncher"
    if any(w in sub for w in ("pistol", "revolver", "magnum", "akimbo", "melee", "knife")):
        return "SecondaryWep"
    if any(w in sub for w in ("rifle", "shotgun", "submachine", "smg", "machine gun", "sniper", "marksman",
                              "carbine", "sporter", "battle")):
        return "PrimaryWep"
    if arc9 and isinstance(f.get("Slot"), float):
        return "SecondaryWep" if f["Slot"] <= 1 else "PrimaryWep"
    return "SecondaryWep" if hold in SECONDARY_HOLDS else "PrimaryWep"


KIND = [  # (words, expected slot): what a weapon says it is
    (("rocket", "rpg", "missile", "bazooka", "at4", "law", "panzer", "stinger", "javelin", "smaw", "m202", "rpg-7"), "RocketLauncher"),
    (("pistol", "revolver", "handgun", "sidearm", "deagle", "desert eagle", "glock", "magnum", "colt python",
      "knife", "melee", "machete", "bat", "crowbar", "fists", "hatchet", "axe", "katana", "sword"), "SecondaryWep"),
    (("rifle", "smg", "submachine", "sub-machine", "shotgun", "sniper", "carbine", "machine gun", "lmg", "mg", "dmr",
      "assault", "battle rifle", "pdw", "launcher"), "PrimaryWep"),
]


def expected(f, cls):
    texts = [str(f.get(k) or "") for k in ("Type", "Trivia_Class", "SubCatType", "SubCategory", "Category", "PrintName")]
    for t in texts:
        low = t.lower()
        if not low:
            continue
        for words, slot in KIND:
            if any(re.search(r"(?<![a-z])" + re.escape(w) + r"(?![a-z])", low) for w in words):
                if slot == "PrimaryWep" and "grenade" in low and "launcher" in low:
                    return slot, t
                return slot, t
    return None, ""


def main():
    roots = [Path(a) for a in sys.argv[1:]]
    table, origin = {}, {}
    for r in roots:
        for cls, files in weapon_files(r).items():
            f = {}
            for p in files:
                for k, v in parse(p).items():
                    f.setdefault(k, v)
            table[cls] = f
            origin[cls] = r.name
    bases = {str(f.get("Base")).lower() for f in table.values() if isinstance(f.get("Base"), str)}
    bad, counted = [], 0
    for cls in sorted(table):
        f = resolved(cls, table)
        if cls in bases or not (f.get("Spawnable") or f.get("AdminSpawnable") or f.get("PrintName")):
            continue  # (a base)
        counted += 1
        g = guess(f)
        e, why = expected(f, cls)
        if e and e != g:
            bad.append((origin[cls], cls, g, e, why, f.get("HoldType") or f.get("NormalHoldType") or f.get("HoldtypeActive") or f.get("RaisedHoldType") or f.get("HoldType_Aim") or f.get("HoldType_Hipfire"),
                        f.get("Primary.Ammo") or f.get("Ammo"), f.get("Primary.ClipSize") or f.get("ClipSize"), f.get("Slot")))
    print(f"{counted} weapons, {len(bad)} where the guess disagrees with what the weapon says it is")
    for o, cls, g, e, why, hold, ammo, clip, slot in bad:
        print(f"  {o:12} {cls:40} guess {g:14} says {e:14} ({why[:40]}) hold={hold} ammo={ammo} clip={clip} slot={slot}")


if __name__ == "__main__":
    main()
