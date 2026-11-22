"""Minimal Valve VPK (v1/v2) reader.

usage:
  python vpk.py list <x_dir.vpk> [ext]           -> print paths (optionally filtered by extension)
  python vpk.py extract <x_dir.vpk> <out_dir> <path> [<path> ...]
"""
import os
import struct
import sys


def read_cstr(f):
    out = bytearray()
    while True:
        b = f.read(1)
        if not b or b == b"\0":
            return out.decode("latin-1")
        out += b


def read_tree(dir_path):
    entries = {}
    with open(dir_path, "rb") as f:
        sig, version, tree_size = struct.unpack("<III", f.read(12))
        assert sig == 0x55AA1234, "not a VPK"
        header = 12
        if version == 2:
            f.read(16)
            header = 28
        while True:
            ext = read_cstr(f)
            if not ext:
                break
            while True:
                path = read_cstr(f)
                if not path:
                    break
                while True:
                    name = read_cstr(f)
                    if not name:
                        break
                    crc, preload, arch, off, length, term = struct.unpack("<IHHIIH", f.read(18))
                    pre = f.read(preload)
                    full = (f"{path}/" if path.strip() else "") + f"{name}.{ext}"
                    entries[full.lower()] = (arch, off, length, pre)
    return entries, header + tree_size


def read_file(dir_path, entries, data_start, path):
    arch, off, length, pre = entries[path.lower()]
    if length == 0:
        return pre
    if arch == 0x7FFF:
        src, pos = dir_path, data_start + off
    else:
        src, pos = dir_path.replace("_dir.vpk", f"_{arch:03d}.vpk"), off
    with open(src, "rb") as f:
        f.seek(pos)
        return pre + f.read(length)


def main():
    cmd, vpk = sys.argv[1], sys.argv[2]
    entries, data_start = read_tree(vpk)
    if cmd == "list":
        ext = sys.argv[3].lower() if len(sys.argv) > 3 else None
        for p in sorted(entries):
            if ext is None or p.endswith("." + ext):
                print(p)
    elif cmd == "extract":
        out_root = os.path.realpath(sys.argv[3])
        for p in sys.argv[4:]:
            p = p.lower()
            if p not in entries:
                print(f"absent: {p}")
                continue
            dest = os.path.realpath(os.path.join(out_root, p))
            if not dest.startswith(out_root + os.sep):
                raise SystemExit(f"refusing path outside output dir: {p}")
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as o:
                o.write(read_file(vpk, entries, data_start, p))


if __name__ == "__main__":
    main()
