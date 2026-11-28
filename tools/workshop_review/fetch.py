"""Downloads Workshop items into their own folders and extracts them (never runs their Lua).

    python -I fetch.py <ids.txt> <items.json> <out_root>

For each id (in file order): steamcmd anonymous workshop_download_item, else the API file_url (old
items: LZMA .bin); the .gma moved to <out_root>/_dl_<id>/<id>.gma and extracted with gmad into
<out_root>/<id>/. Items already extracted are skipped. One steamcmd run per batch of 6 items.
Progress lines: "done <id> <MB> <files>" / "fail <id> <why>".
"""
import json
import lzma
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ids_file, items_json, out_root = sys.argv[1], sys.argv[2], Path(sys.argv[3])
SCMD = Path(os.environ.get("STEAMCMD_DIR", "C:/gmod-test/steamcmd"))  # (one per parallel downloader)
STEAMCMD = SCMD / "steamcmd.exe"
CONTENT = SCMD / "steamapps/workshop/content/4000"
GMAD = Path("C:/Program Files (x86)/Steam/steamapps/common/GarrysMod/bin/gmad.exe")
details = {d["publishedfileid"]: d for d in json.load(open(items_json, encoding="utf-8"))["response"]["publishedfiledetails"]}
ids = [l.strip() for l in open(ids_file) if l.strip() and not l.startswith("#")]
out_root.mkdir(parents=True, exist_ok=True)


def extract(i, gma):
    dl = out_root / f"_dl_{i}"
    dl.mkdir(exist_ok=True)
    target = dl / f"{i}.gma"
    shutil.move(str(gma), str(target))
    with open(target, "rb") as f:
        head = f.read(4)
    if head != b"GMAD":  # (an old item: LZMA alone)
        raw = target.with_suffix(".bin")
        if raw.exists():  # (left by an interrupted run)
            raw.unlink()
        target.rename(raw)
        dec = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
        with open(raw, "rb") as f, open(target, "wb") as o:
            while True:
                chunk = f.read(1 << 22)
                if not chunk:
                    break
                o.write(dec.decompress(chunk))
        raw.unlink()
    r = subprocess.run([str(GMAD), "extract", "-file", str(target), "-out", str(out_root / i)],
                       capture_output=True, text=True, errors="replace")
    files = sum(len(fs) for _, _, fs in os.walk(out_root / i)) if (out_root / i).exists() else 0
    code = r.returncode
    if code != 0 or files == 0:  # (gmad gives up on archives over 2 GB: our own streaming extractor)
        here = Path(__file__).resolve().parent
        r2 = subprocess.run([sys.executable, "-I", str(here / "gma_extract.py"), str(target), str(out_root / i),
                             "models", "materials", "lua"], capture_output=True, text=True, errors="replace")
        files = sum(len(fs) for _, _, fs in os.walk(out_root / i)) if (out_root / i).exists() else 0
        code = 100 + r2.returncode
    if files > 0:
        target.unlink()  # (the extracted folder is what we use; keeps the disk tidy)
    return code, files


todo = [i for i in ids if not (out_root / i).exists() and details.get(i, {}).get("result") == 1]
print(f"{len(todo)} to fetch", flush=True)
for b in range(0, len(todo), 3):
    batch = todo[b:b + 3]
    # (several connections, no HTTP/2: a single stalled connection held whole batches)
    cmd = [str(STEAMCMD), "+@nClientDownloadEnableHTTP2PlatformWindows", "0",
           "+@fDownloadRateImprovementToAddAnotherConnection", "1.0", "+@cMaxInitialDownloadSources", "8",
           "+login", "anonymous"]
    for i in batch:
        cmd += ["+workshop_download_item", "4000", i]
    cmd += ["+quit"]
    subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    for i in batch:
        try:
            folder = CONTENT / i
            gmas = sorted(folder.glob("*")) if folder.exists() else []
            gmas = [g for g in gmas if g.is_file()]
            if not gmas:
                url = details[i].get("file_url")
                if not url:
                    print(f"fail {i} nothing downloaded", flush=True)
                    continue
                folder.mkdir(parents=True, exist_ok=True)
                tmp = folder / f"{i}.bin"
                urllib.request.urlretrieve(url, tmp)
                gmas = [tmp]
            size = gmas[0].stat().st_size
            code, files = extract(i, gmas[0])
            print(f"done {i} {size / 1e6:.0f} MB {files} files (gmad {code})", flush=True)
        except Exception as ex:  # noqa: BLE001
            print(f"fail {i} {ex}", flush=True)
print("ALL DONE", flush=True)
