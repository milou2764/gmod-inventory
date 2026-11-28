#!/bin/sh
# Builds fitcore.dll (tools/fitcore.py loads it) with MSYS2's UCRT64 gcc, as tools/fit_editor/build.sh.
# Static: the DLL needs nothing besides Windows' own.
cd "$(dirname "$0")"
PATH=/c/msys64/ucrt64/bin:$PATH gcc -O2 -Wall -Wextra -shared -static -o fitcore.dll fitcore.c
