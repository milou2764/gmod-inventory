"""Gear that is part of a playermodel's mesh (AdvInv.GearBuiltIn, lua/advinv/sh_modelgear.lua): headgear, a
vest, a backpack, a mask. Nothing of that kind is worn over it, so the fit tools give the items of that slot no fit
on those playermodels (and the fit editor doesn't list those pairs). Only the entries true for every
bodygroup count here: an entry for some bodygroup choices (an armoured body, a helmeted outfit) leaves the
default, bare one wearable.

    blocked = builtin()      {"Helmet": {models}, "Gasmask": {...}, "Vest": {...}, "Rucksack": {...}}
    slots = item_slots()     {item class: slot}
"""
import re
from pathlib import Path

ADDON = Path(__file__).resolve().parent.parent
SLOTS = ("Helmet", "Gasmask", "Vest", "Rucksack")
BASES = {"advinv_base_helmet": "Helmet", "advinv_base_vest": "Vest", "advinv_base_pocketvest": "Vest",
         "advinv_base_rucksack": "Rucksack"}


def builtin():
    t = (ADDON / "lua" / "advinv" / "sh_modelgear.lua").read_text(encoding="utf-8")
    out = {s: set() for s in SLOTS}
    for model, slot in re.findall(r'^builtin\("([^"]+)", "(\w+)"\)$', t, re.M):
        out.setdefault(slot, set()).add(model.lower())
    return out


def item_slots():
    """Slot of every worn item: the compatible addons' (sh_compat_data.lua) and the built-in ones (their base)."""
    t = (ADDON / "lua" / "advinv" / "sh_compat_data.lua").read_text(encoding="utf-8")
    out = dict(re.findall(r'class = "([^"]+)",[^\n]*\n[^\n]*slot = "(\w+)"', t))
    for p in (ADDON / "lua" / "entities").glob("*.lua"):
        m = re.search(r'^ENT\.Base\s*=\s*"([^"]+)"', p.read_text(encoding="utf-8"), re.M)
        if m and m.group(1) in BASES:
            out[p.stem] = BASES[m.group(1)]
    return out


def is_blocked(cls, model, blocked, slots):
    slot = slots.get(cls)
    return slot is not None and model.lower() in blocked.get(slot, ())
