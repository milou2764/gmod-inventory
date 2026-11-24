@echo off
rem Fit editor of the Advanced Inventory System (dev tool): reads the playermodels and items once
rem (cached, only new ones afterwards), then opens the editor. Settings: environment variables, or
rem local.bat next to this file (not in git):
rem   ADVINV_PYTHON   Python 3 with numpy and Pillow (default: python)
rem   MDL_EXTRA_DIRS  the extracted Workshop addons, ";" separated (playermodels and compatible gear)
setlocal
if exist "%~dp0local.bat" call "%~dp0local.bat"
if not defined ADVINV_PYTHON set "ADVINV_PYTHON=python"
if not exist "%~dp0fit_editor.exe" goto nobuild
echo Reading the playermodels and items (the first time takes about a minute)...
"%ADVINV_PYTHON%" -I "%~dp0..\fit_editor_export.py"
if errorlevel 1 goto failed
start "" "%~dp0fit_editor.exe" --cache "%TEMP%\advinv_fit_editor" --tools "%~dp0.." --python "%ADVINV_PYTHON%"
exit /b 0
:nobuild
echo fit_editor.exe is missing: build it with tools/fit_editor/build.sh
pause
exit /b 1
:failed
echo The export failed (see above).
pause
exit /b 1
