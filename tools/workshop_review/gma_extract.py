"""Extract only some top folders (default materials/ and models/) of a .gma, untrusted input.
    gma_extract.py <file.gma> <out dir> [prefix ...]
Paths are checked: relative, no "..", only the given prefixes, only plain file names.
"""
import os
import struct
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
prefixes = tuple(p.rstrip("/") + "/" for p in (sys.argv[3:] or ["materials", "models"]))

with open(src, "rb") as f:
    def cstr():
        b = bytearray()
        while True:
            c = f.read(1)
            if not c or c == b"\0":
                return b.decode("utf-8", "replace")
            b += c

    assert f.read(4) == b"GMAD", "not a gma"
    version = f.read(1)[0]
    f.read(16)  # steamid, timestamp
    if version > 1:
        while cstr():
            pass
    name, desc, author = cstr(), cstr(), cstr()
    f.read(4)
    entries = []
    while True:
        num = struct.unpack("<I", f.read(4))[0]
        if num == 0:
            break
        path = cstr()
        size = struct.unpack("<q", f.read(8))[0]
        f.read(4)
        entries.append((path, size))
    kept = skipped = 0
    for path, size in entries:
        p = path.replace("\\", "/").lower()
        ok = p.startswith(prefixes) and ".." not in p.split("/") and not p.startswith("/") and ":" not in p
        if ok:
            dst = (out / p).resolve()
            ok = str(dst).startswith(str(out) + os.sep)
        if ok:
            dst.parent.mkdir(parents=True, exist_ok=True)
            with open(dst, "wb") as o:
                left = size
                while left > 0:
                    chunk = f.read(min(left, 1 << 20))
                    if not chunk:
                        raise IOError("truncated")
                    o.write(chunk)
                    left -= len(chunk)
            kept += 1
        else:
            f.seek(size, 1)
            skipped += 1
    print(f"{src.name}: '{name}' v{version}, {kept} files extracted, {skipped} skipped")
