#!/bin/sh
# Builds fit_editor.exe with MSYS2's UCRT64 gcc (pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-zlib).
# Static: the program needs no DLL besides Windows' own.
cd "$(dirname "$0")"
PATH=/c/msys64/ucrt64/bin:$PATH gcc -O2 -Wall -Wextra -municode -mwindows -static -o fit_editor.exe fit_editor.c \
    -lopengl32 -lglu32 -lgdi32 -lshell32 -lcomctl32 -lz
