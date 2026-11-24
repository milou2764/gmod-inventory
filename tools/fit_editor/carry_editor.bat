@echo off
rem Weapon carry positions of the Advanced Inventory System (dev tool): double-click it.
rem Finds the long guns of your addons, computes their carry positions if some are new (the first
rem time: a few minutes), prepares the playermodels (cached), then opens the carry editor.
rem Settings: environment variables, or local.bat next to this file (not in git):
rem   ADVINV_PYTHON       Python 3 with numpy and Pillow (default: python)
rem   MDL_EXTRA_DIRS      unpacked addons whose models are needed (playermodels, other addons' weapons), ";" separated
rem   ADVINV_WEAPON_DIRS  more addon folders to look for weapons in, ";" separated
setlocal
title Weapon carry positions
if exist "%~dp0local.bat" call "%~dp0local.bat"
if not defined ADVINV_PYTHON set "ADVINV_PYTHON=python"
if not exist "%~dp0fit_editor.exe" goto nobuild
echo.
echo  Weapon carry positions
echo  ======================
echo.
echo [1/3] Looking for the long guns of your addons...
"%ADVINV_PYTHON%" -I "%~dp0..\carry_weapons.py" update
if errorlevel 1 goto failed
echo.
echo [2/3] Preparing the playermodels and the weapons (only what is new)...
"%ADVINV_PYTHON%" -I "%~dp0..\fit_editor_export.py"
if errorlevel 1 goto failed
echo.
echo [3/3] Opening the editor.
start "" "%~dp0fit_editor.exe" --cache "%TEMP%\advinv_fit_editor" --tools "%~dp0.." --python "%ADVINV_PYTHON%" --carry
exit /b 0
:nobuild
echo fit_editor.exe is missing: build it with tools/fit_editor/build.sh
pause
exit /b 1
:failed
echo.
echo Something went wrong (see above).
pause
exit /b 1
