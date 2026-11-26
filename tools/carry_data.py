"""Reads and patches lua/advinv/cl_carry_data.lua (written by fit_carry.py): the carry offsets of the
long guns per offset set, weapon class and mode, and which set each playermodel uses.

Carry positions are approved in the fit editor like worn items, under the class "carry:<weapon
class>:<mode>" (CARRY_PREFIX): their fit is the position and angles on the mode's bone (no size).
"""
import re
from pathlib import Path

# A negative zero ("-0.00", "-0.0") written without its sign; only a number that is all zeros
# ("-0.004" keeps its sign: a plain .replace("-0.00", "0.00") turned it into 0.004).
_NEG_ZERO = re.compile(r"(?<![\w.])-(0\.0+)(?![0-9])")  # (not "1-0.00")


def _nz(text):
    return _NEG_ZERO.sub(lambda m: m.group(1), text)


TOOLS = Path(__file__).resolve().parent
PATH = TOOLS.parent / "lua" / "advinv" / "cl_carry_data.lua"
CARRY_PREFIX = "carry:"

_NUM = r"(-?[\d.]+)"
_ENTRY = re.compile(rf'^            (\w+) = \{{ "([^"]+)", V\({_NUM}, {_NUM}, {_NUM}\), A\({_NUM}, {_NUM}, {_NUM}\), (V\([^)]*\)) \}},$')


def gear_class(weapon, mode):
    return f"{CARRY_PREFIX}{weapon}:{mode}"


def split_class(cls):
    """'carry:weapon_ar2:sling_up' -> ('weapon_ar2', 'sling_up'), or None for another item."""
    if not cls.startswith(CARRY_PREFIX):
        return None
    weapon, _, mode = cls[len(CARRY_PREFIX):].partition(":")
    return weapon, mode


def _block(text, name):
    start = text.index(f"AdvInv.{name} = {{\n")
    end = text.index("\n}\n", start)
    return start, end


def read(path=PATH):
    """-> (sets, aliases): sets[set][weapon][mode] = {bone, pos, ang}; aliases[playermodel] = set."""
    text = Path(path).read_text(encoding="utf-8")
    s, e = _block(text, "CarryOffsets")
    sets, cur, weapon = {}, None, None
    for line in text[s:e].splitlines():
        m = re.match(r'^    \["([^"]+)"\] = \{', line)
        if m:
            cur = sets.setdefault(m.group(1), {})
            continue
        m = re.match(r"^        (\w+) = \{$", line)
        if m and cur is not None:
            weapon = cur.setdefault(m.group(1), {})
            continue
        m = _ENTRY.match(line)
        if m and weapon is not None:
            n = [float(x) for x in m.groups()[2:8]]
            weapon[m.group(1)] = {"bone": m.group(2), "pos": n[:3], "ang": n[3:6]}
    s, e = _block(text, "CarryAliases")
    aliases = {m.lower(): v for m, v in re.findall(r'^    \["([^"]+)"\] = "([^"]+)",$', text[s:e], re.M)}
    return sets, aliases


def set_of(aliases, sets, playermodel):
    name = aliases.get(playermodel.lower(), "default")
    return name if name in sets else "default"


def apply_locks(locks, path=PATH):
    """Writes the approved carry positions (fit_locks: class 'carry:...' -> {playermodel: (pos, ang,
    size)}) into the playermodel's set. Returns how many entries changed."""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    sets, aliases = read(path)
    s, e = _block(text, "CarryOffsets")
    lines = text[s:e].split("\n")
    # (set, weapon, mode) -> line index
    where, cur, weapon = {}, None, None
    for k, line in enumerate(lines):
        m = re.match(r'^    \["([^"]+)"\] = \{', line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"^        (\w+) = \{$", line)
        if m:
            weapon = m.group(1)
            continue
        m = _ENTRY.match(line)
        if m:
            where[(cur, weapon, m.group(1))] = k
    changed = 0
    for cls, per in locks.items():
        wm = split_class(cls)
        if not wm:
            continue
        for pm, (p, a, _s) in per.items():
            k = where.get((set_of(aliases, sets, pm), wm[0], wm[1]))
            if k is None:
                continue
            m = _ENTRY.match(lines[k])
            new = _nz(f'            {wm[1]} = {{ "{m.group(2)}", V({p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f}), '
                   f'A({a[0]:.1f}, {a[1]:.1f}, {a[2]:.1f}), {m.group(9)} }},')
            if lines[k] != new:
                lines[k] = new
                changed += 1
    if changed:
        path.write_text(text[:s] + "\n".join(lines) + text[e:], encoding="utf-8", newline="\n")
    return changed
