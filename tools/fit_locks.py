"""Fits approved by hand in the fit editor (tools/fit_editor/): final. They are kept in
tools/fit_locks.txt, one per line:

    item class <TAB> playermodel <TAB> x y z pitch yaw roll size <TAB> date <TAB> adjustment made

(the fit on the item's bone, as written in lua/advinv/cl_fits_*.lua). fit_items.py and
fit_compat.py keep them as they are when they run again, whatever their rules give, and

    python fit_locks.py apply

writes them into the game's fit files (the editor runs it after each approval).
"""
import re
import sys
from pathlib import Path

import numpy as np

# A negative zero ("-0.00", "-0.0") written without its sign; only a number that is all zeros
# ("-0.004" keeps its sign: a plain .replace("-0.00", "0.00") turned it into 0.004).
_NEG_ZERO = re.compile(r"(?<![\w.])-(0\.0+)(?![0-9])")  # (not "1-0.00")


def _nz(text):
    return _NEG_ZERO.sub(lambda m: m.group(1), text)


TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))  # builtin_gear.py (run with python -I, the script's folder isn't on the path)
PATH = TOOLS / "fit_locks.txt"
LUA = TOOLS.parent / "lua" / "advinv"
REF = "models/player/group01/male_07.mdl"
HEADER = ("# Fits approved by hand in the fit editor (tools/fit_editor/): final, fit_items.py and fit_compat.py keep them.\n"
          "# item class<TAB>playermodel<TAB>x y z pitch yaw roll size<TAB>date<TAB>adjustment made\n")


def load(path=PATH):
    """{class: {playermodel: (pos, ang, scale)}}; a later line wins."""
    locks = {}
    if not Path(path).exists():
        return locks
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        n = [float(x) for x in f[2].split()]
        locks.setdefault(f[0], {})[f[1].lower()] = (np.array(n[:3]), tuple(n[3:6]), n[6])
    return locks


def get(locks, cls, pm):
    return locks.get(cls, {}).get(pm.lower())


def unadjusted_claude(path=PATH):
    """{(class, playermodel)}: the locks Claude approved without changing the computed fit (only stamped
    with the rules of that day). A vest fitted to the body (modelgear_pack.py: stretch, depth, straps on
    the shoulders) takes its new fit over those; Claude's adjusted ones keep their place and size and get
    the rest; the user's approvals stay final."""
    out, last = set(), {}
    if not Path(path).exists():
        return out
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) < 6:
            continue
        adj = [float(x) for x in re.findall(r"[-+]?\d+(?:\.\d+)?", f[4])]
        last[(f[0], f[1].lower())] = f[5].strip() == "claude" and all(abs(x) < 1e-9 for x in adj)
    return {k for k, v in last.items() if v}


def approvers(path=PATH):
    """{(class, playermodel): "user" | "claude"}: who approved each lock (its last line)."""
    out = {}
    if not Path(path).exists():
        return out
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) >= 6:
            out[(f[0], f[1].lower())] = f[5].strip()
    return out


def _stretched(head, cls):
    """Whether an extension's item (its Lua before the fits) is a vest stretched to the body."""
    k = head.find(f'class = "{cls}",')
    if k < 0:
        return False
    nxt = head.find("\n        { class", k + 1)
    return "stretch_top = " in head[k:nxt if nxt > 0 else len(head)]


# ---------------------------------------------------------------- writing them into the game's files
# (the same formats as fit_compat.py write_fits / write_data and fit_items.py lua)

def _compat_entry(p, a, s):
    return _nz(" ".join([f"{x:.2f}" for x in p] + [f"{x:.1f}" for x in a] + [f"{s:g}"]))


def _vec(p, n=2):
    return _nz(", ".join(f"{x:.{n}f}" for x in p))


def _data_line(cls, p, a, s):
    t = (f"        {cls} = {{ V({p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f}), A({a[0]:.1f}, {a[1]:.1f}, {a[2]:.1f}), {s:g} }},")
    return _nz(t)


def extensions():
    """The AIS extensions next to the inventory (gear taken from a playermodel addon, made by
    tools/modelgear_pack.py): {their Lua file: pack key}."""
    out = {}
    for p in sorted(TOOLS.parent.parent.glob("advinv-ext-*/lua/autorun/*.lua")):
        m = re.search(r'^    key = "([^"]+)"', p.read_text(encoding="utf-8"), re.M)
        if m:
            out[p] = m.group(1)
    return out


def ext_fits(text):
    """An extension's fits: (its playermodels, {class: {playermodel: (pos, ang, scale)}})."""
    tail = text.split("\n    fits = {\n", 1)[1]
    models = [m.lower() for m in re.findall(r'^            "([^"]+)",$', tail.split("\n        },")[0], re.M)]
    fits = {}
    for cls, packed in re.findall(r'^            \["([^"]+)"\] = "([^"]*)",$', tail, re.M):
        per = {}
        for m, e in zip(models, packed.split("|")):
            if e:
                n = [float(x) for x in e.split()]
                per[m] = (np.array(n[:3]), tuple(n[3:6]), n[6])
        fits[cls] = per
    return models, fits


def _apply_extensions(locks):
    """The locks of extension items, into the extension's Lua (its fits and its attach: the fit on male_07)."""
    changed = 0
    for path in extensions():
        text = path.read_text(encoding="utf-8")
        head, sep, tail = text.partition("\n    fits = {\n")
        if not sep:
            continue
        models = [m.lower() for m in re.findall(r'^            "([^"]+)",$', tail.split("\n        },")[0], re.M)]
        for cls, per in locks.items():
            m = re.search(rf'^            \["{re.escape(cls)}"\] = "([^"]*)",$', tail, re.M)
            if not m:
                continue
            parts = m.group(1).split("|")
            # (a vest fitted to the body, modelgear_pack.py: its stretch, depth and straps on the shoulders.
            # Claude's locks are applied there, with those; only the user's are written as they are)
            stretched = _stretched(head, cls)
            by = approvers() if stretched else {}
            for pm, (p, a, s) in per.items():
                if stretched and by.get((cls, pm)) == "claude":
                    continue
                if pm in models and parts[models.index(pm)]:  # (an empty one can't be worn there)
                    e = _compat_entry(p, a, s)
                    if parts[models.index(pm)] != e:
                        parts[models.index(pm)] = e
                        changed += 1
            tail = tail[:m.start(1)] + "|".join(parts) + tail[m.end(1):]
            if REF in per:
                p, a, s = per[REF]
                head = re.sub(rf'(class = "{re.escape(cls)}",.*?\n          attach = \{{ bone = "[^"]+", )pos = Vector\([^)]*\), '
                              r'ang = Angle\([^)]*\), scale = [\d.]+( \},)',
                              lambda mm: f"{mm.group(1)}pos = Vector({_vec(p)}), ang = Angle({_vec(a, 1)}), scale = {s:g}{mm.group(2)}",
                              head, count=1, flags=re.S)
        new = head + sep + tail
        if new != text:
            path.write_text(new, encoding="utf-8", newline="\n")
    return changed


def apply(locks):
    """Writes every lock into cl_fits_compat.lua, sh_compat_data.lua (the default attach is the fit on
    male_07), cl_fits_data.lua, the extensions' Lua and cl_carry_data.lua (carry positions). Returns the number of fits changed. An item on a
    playermodel with that gear of its own in its mesh (builtin_gear.py) is left out: it can't be worn there."""
    import builtin_gear
    blocked, slots = builtin_gear.builtin(), builtin_gear.item_slots()
    locks = {c: {m: f for m, f in per.items() if not builtin_gear.is_blocked(c, m, blocked, slots)} for c, per in locks.items()}
    changed = 0
    import fits_compat_io
    p_fc, p_sh, p_fd = fits_compat_io.SRC, LUA / "sh_compat_data.lua", LUA / "cl_fits_data.lua"
    fc, sh, fd = (p.read_text(encoding="utf-8") for p in (p_fc, p_sh, p_fd))
    models = [m.lower() for m in re.findall(r'^    "([^"]+)",$', fc.split("local F")[0], re.M)]
    for cls, per in locks.items():
        m = re.search(rf'^    {re.escape(cls)} = "([^"]*)",$', fc, re.M)
        if m:  # an item of a compatible addon
            parts = m.group(1).split("|")
            for pm, (p, a, s) in per.items():
                if pm in models:
                    e = _compat_entry(p, a, s)
                    if parts[models.index(pm)] != e:
                        parts[models.index(pm)] = e
                        changed += 1
            fc = fc[:m.start(1)] + "|".join(parts) + fc[m.end(1):]
            if REF in per:
                p, a, s = per[REF]
                sh = re.sub(rf'(class = "{re.escape(cls)}",.*?attach = \{{ bone = "[^"]+", )pos = Vector\([^)]*\), '
                            r'ang = Angle\([^)]*\), scale = [\d.]+( \} \},)',
                            lambda mm: f"{mm.group(1)}pos = Vector({_vec(p)}), ang = Angle({_vec(a, 1)}), scale = {s:g}{mm.group(2)}",
                            sh, count=1, flags=re.S)
            continue
        for pm, (p, a, s) in per.items():  # a built-in item
            blk = re.search(rf'^    \["{re.escape(pm)}"\] = \{{\n(.*?)^    \}},$', fd, re.M | re.S | re.I)
            if not blk:
                continue
            ln = re.search(rf"^        {re.escape(cls)} = \{{ .*$", blk.group(1), re.M)
            if not ln:
                continue
            new = _data_line(cls, p, a, s)
            if ln.group(0) != new:
                a0 = blk.start(1) + ln.start()
                fd = fd[:a0] + new + fd[a0 + len(ln.group(0)):]
                changed += 1
    for path, text in ((p_fc, fc), (p_sh, sh), (p_fd, fd)):
        if path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8", newline="\n")
            if path == p_fc:
                fits_compat_io.pack()  # (the game's file, packed)
    import carry_data  # carry positions of the long guns ("carry:<weapon>:<mode>") -> cl_carry_data.lua
    return changed + _apply_extensions(locks) + carry_data.apply_locks(locks)


if __name__ == "__main__":
    if sys.argv[1:2] == ["apply"]:
        print(f"{apply(load())} fits written")
    else:
        print(__doc__)
