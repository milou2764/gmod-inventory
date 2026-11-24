"""Animated Workshop icon from the frames of gear_gif.lua: a square crop around the player, 512 x 512,
one shared palette (no flicker), the first and last states held longer. Steam takes previews under 1 MB.
    python make_gif.py <frames dir> <name> <out.gif> [--x CENTRE_X] [--size 512] [--colors 128]"""
import sys
from pathlib import Path
from PIL import Image

src, name, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
opt = dict(zip(sys.argv[4::2], sys.argv[5::2]))
size, colors = int(opt.get("--size", 512)), int(opt.get("--colors", 128))
frames = sorted(src.glob(f"{name}_*.png"))
ims = [Image.open(f).convert("RGB") for f in frames]
W, H = ims[0].size
cx = int(float(opt.get("--x", 0.5)) * W)
box = (cx - H // 2, 0, cx + H // 2, H)
ims = [i.crop(box).resize((size, size), Image.LANCZOS) for i in ims]
# one palette for all the frames: built from a strip of every frame
strip = Image.new("RGB", (size, size * len(ims)))
for k, i in enumerate(ims):
    strip.paste(i, (0, k * size))
pal = strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
q = [i.quantize(palette=pal, dither=Image.Dither.NONE) for i in ims]
dur = [900] + [650] * (len(q) - 2) + [1500]
q[0].save(out, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=True, disposal=1)
print(out, f"{out.stat().st_size / 1024:.0f} KB", len(q), "frames")
