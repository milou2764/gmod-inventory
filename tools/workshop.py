"""Workshop items of Garry's Mod through the Steamworks API (dev tool, not shipped): what gmpublish
can't do, such as an animated (GIF) icon, the description, screenshots, required items and
visibility. Uses Garry's Mod's own bin/win64/steam_api64.dll and the logged-in Steam client (it
acts as the user: only on their own items).

    python workshop.py update <id> [--preview FILE] [--description FILE] [--image FILE ...]
                                   [--replace-image INDEX FILE ...]
                                   [--visibility public|friends|private|unlisted] [--note TEXT]
    python workshop.py previews <id>                     its screenshots: index, original file name
    python workshop.py depend <id> <required id> ...     the item's "Required items"

The preview (icon) must be under 1 MB; it may be a GIF. Descriptions: Steam BBCode, 8000 characters.
"""
import ctypes as C
import os
import sys
import time
from pathlib import Path

APP = 4000
DLL = Path(os.environ.get("GMOD_DIR", r"C:/Program Files (x86)/Steam/steamapps/common/GarrysMod")) / "bin/win64/steam_api64.dll"
VIS = {"public": 0, "friends": 1, "private": 2, "unlisted": 3}
SUBMIT_RESULT, DEPENDENCY_RESULT, QUERY_RESULT = 3404, 3412, 3401  # k_iSteamUGCCallbacks + 4, + 12, + 1

os.environ["SteamAppId"] = os.environ["SteamGameId"] = str(APP)
api = C.CDLL(str(DLL))


def fn(name, res, *args):
    f = getattr(api, name)
    f.restype, f.argtypes = res, list(args)
    return f


P, U64, S, B = C.c_void_p, C.c_uint64, C.c_char_p, C.c_bool
InitFlat = fn("SteamAPI_InitFlat", C.c_int, C.c_char_p)  # ESteamAPIInitResult, 0 = OK; SteamErrMsg[1024]
Shutdown = fn("SteamAPI_Shutdown", None)
RunCallbacks = fn("SteamAPI_RunCallbacks", None)
UGC = fn("SteamAPI_SteamUGC_v021", P)
Utils = fn("SteamAPI_SteamUtils_v010", P)
StartItemUpdate = fn("SteamAPI_ISteamUGC_StartItemUpdate", U64, P, C.c_uint32, U64)
SetItemPreview = fn("SteamAPI_ISteamUGC_SetItemPreview", B, P, U64, S)
SetItemDescription = fn("SteamAPI_ISteamUGC_SetItemDescription", B, P, U64, S)
SetItemVisibility = fn("SteamAPI_ISteamUGC_SetItemVisibility", B, P, U64, C.c_int)
AddItemPreviewFile = fn("SteamAPI_ISteamUGC_AddItemPreviewFile", B, P, U64, S, C.c_int)
UpdateItemPreviewFile = fn("SteamAPI_ISteamUGC_UpdateItemPreviewFile", B, P, U64, C.c_uint32, S)
CreateQueryUGCDetailsRequest = fn("SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest", U64, P, C.POINTER(U64), C.c_uint32)
SetReturnAdditionalPreviews = fn("SteamAPI_ISteamUGC_SetReturnAdditionalPreviews", B, P, U64, B)
SendQueryUGCRequest = fn("SteamAPI_ISteamUGC_SendQueryUGCRequest", U64, P, U64)
GetQueryUGCNumAdditionalPreviews = fn("SteamAPI_ISteamUGC_GetQueryUGCNumAdditionalPreviews", C.c_uint32, P, U64, C.c_uint32)
GetQueryUGCAdditionalPreview = fn("SteamAPI_ISteamUGC_GetQueryUGCAdditionalPreview", B, P, U64, C.c_uint32, C.c_uint32,
                                  C.c_char_p, C.c_uint32, C.c_char_p, C.c_uint32, C.POINTER(C.c_int))
ReleaseQueryUGCRequest = fn("SteamAPI_ISteamUGC_ReleaseQueryUGCRequest", B, P, U64)
SubmitItemUpdate = fn("SteamAPI_ISteamUGC_SubmitItemUpdate", U64, P, U64, S)
AddDependency = fn("SteamAPI_ISteamUGC_AddDependency", U64, P, U64, U64)
IsAPICallCompleted = fn("SteamAPI_ISteamUtils_IsAPICallCompleted", B, P, U64, C.POINTER(B))
GetAPICallResult = fn("SteamAPI_ISteamUtils_GetAPICallResult", B, P, U64, P, C.c_int, C.c_int, C.POINTER(B))


def wait(utils, call, cb_id, size, timeout=600):
    """Waits for an API call; returns its result struct's bytes."""
    failed = B(False)
    t0 = time.time()
    while not IsAPICallCompleted(utils, call, C.byref(failed)):
        RunCallbacks()
        if time.time() - t0 > timeout:
            raise SystemExit("timed out")
        time.sleep(0.1)
    buf = C.create_string_buffer(size)
    if not GetAPICallResult(utils, call, buf, size, cb_id, C.byref(failed)) or failed.value:
        raise SystemExit("the call failed (no result)")
    return buf.raw


def main(argv):
    if not argv or argv[0] not in ("update", "depend", "previews"):
        print(__doc__)
        return 1
    err = C.create_string_buffer(1024)
    if InitFlat(err) != 0:
        raise SystemExit(f"SteamAPI_InitFlat failed ({err.value.decode(errors='replace')}): is Steam running and logged in?")
    try:
        ugc, utils = UGC(), Utils()
        item = int(argv[1])
        if argv[0] == "previews":
            ids = (U64 * 1)(item)
            q = CreateQueryUGCDetailsRequest(ugc, ids, 1)
            SetReturnAdditionalPreviews(ugc, q, True)
            wait(utils, SendQueryUGCRequest(ugc, q), QUERY_RESULT, 280)  # SteamUGCQueryCompleted_t
            for k in range(GetQueryUGCNumAdditionalPreviews(ugc, q, 0)):
                url, name, kind = C.create_string_buffer(1024), C.create_string_buffer(1024), C.c_int(0)
                GetQueryUGCAdditionalPreview(ugc, q, 0, k, url, 1024, name, 1024, C.byref(kind))
                print(k, name.value.decode(errors="replace") or "-", url.value.decode(errors="replace"))
            ReleaseQueryUGCRequest(ugc, q)
            return 0
        if argv[0] == "depend":
            for child in argv[2:]:
                r = wait(utils, AddDependency(ugc, item, int(child)), DEPENDENCY_RESULT, 24)
                print(f"required item {child}: result {int.from_bytes(r[:4], 'little')} (1 = OK)")
            return 0
        opts, images, replace, k = {}, [], [], 2
        while k < len(argv):
            if argv[k] == "--image":
                images.append(argv[k + 1])
            elif argv[k] == "--replace-image":
                replace.append((int(argv[k + 1]), argv[k + 2]))
                k += 1
            else:
                opts[argv[k]] = argv[k + 1]
            k += 2
        h = StartItemUpdate(ugc, APP, item)
        if "--preview" in opts:
            f = Path(opts["--preview"]).resolve()
            if f.stat().st_size >= 1024 * 1024:
                raise SystemExit(f"{f.name}: the preview must be under 1 MB")
            assert SetItemPreview(ugc, h, str(f).encode())
        if "--description" in opts:
            text = Path(opts["--description"]).read_text(encoding="utf-8")
            if len(text) > 8000:
                raise SystemExit(f"description: {len(text)} characters, at most 8000")
            assert SetItemDescription(ugc, h, text.encode("utf-8"))
        for f in images:
            assert AddItemPreviewFile(ugc, h, str(Path(f).resolve()).encode(), 0)  # k_EItemPreviewType_Image
        for index, f in replace:
            assert UpdateItemPreviewFile(ugc, h, index, str(Path(f).resolve()).encode())
        if "--visibility" in opts:
            assert SetItemVisibility(ugc, h, VIS[opts["--visibility"]])
        r = wait(utils, SubmitItemUpdate(ugc, h, opts.get("--note", "").encode("utf-8") or None), SUBMIT_RESULT, 16)
        res, legal = int.from_bytes(r[:4], "little"), r[4]
        print(f"item {item}: result {res} (1 = OK){', the Workshop legal agreement must be accepted' if legal else ''}")
        return 0 if res == 1 else 2
    finally:
        Shutdown()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
