"""The fitting tools' hot loops in C (tools/fitcore/fitcore.c, built by tools/fitcore/build.sh), loaded with
ctypes. available() is False when the DLL isn't built (or MODELGEAR_C=0): the callers then use their numpy
versions, which give the same results, slower. Dev tool, not in the .gma."""
import ctypes
import os
from pathlib import Path

import numpy as np

_lib = None
_P = ctypes.c_void_p


def _load():
    global _lib
    if _lib is None:
        _lib = False
        dll = Path(__file__).resolve().parent / "fitcore" / "fitcore.dll"
        if os.environ.get("MODELGEAR_C", "1") != "0" and dll.exists():
            try:
                lib = ctypes.CDLL(str(dll))
                lib.surface_below.argtypes = [_P, ctypes.c_int, _P, ctypes.c_int, _P, ctypes.c_int, ctypes.c_double,
                                              ctypes.c_double, _P, _P]
                lib.surface_below.restype = ctypes.c_int
                lib.zcut.argtypes = [_P, _P, ctypes.c_int, ctypes.c_double, _P]
                lib.zcut.restype = ctypes.c_int
                _lib = lib
            except OSError:
                _lib = False
    return _lib


def available():
    return bool(_load())


def _f64(a):
    return np.ascontiguousarray(a, dtype=np.float64)


def _i64(a):
    return np.ascontiguousarray(np.asarray(a, dtype=np.int64).reshape(-1, 3))


def surface_below(BP, BT, pts, below, above):
    """modelgear_pack.surface_below in C: (heights, flatness)."""
    BP, BT, pts = _f64(BP), _i64(BT), _f64(pts).reshape(-1, 3)
    z, flat = np.empty(len(pts)), np.empty(len(pts))
    if _load().surface_below(BP.ctypes.data, len(BP), BT.ctypes.data, len(BT), pts.ctypes.data, len(pts),
                             float(below), float(above), z.ctypes.data, flat.ctypes.data):
        raise MemoryError("fitcore.surface_below")
    return z, flat


def zcut(P, T, z):
    """modelgear_pack.zcut in C."""
    P, T = _f64(P), _i64(T)
    out = np.empty((2 * len(T) + 1, 3))
    n = _load().zcut(P.ctypes.data, T.ctypes.data, len(T), float(z), out.ctypes.data)
    return out[:n]
