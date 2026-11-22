@echo off
setlocal
set "EXE=%LOCALAPPDATA%\Liucha\Godot\Godot_v4.5.1-stable_win64.exe"
if defined LIUCHA_GODOT set "EXE=%LIUCHA_GODOT%"
if exist "%EXE%" goto run
where godot.exe >nul 2>nul || goto missing
set "EXE=godot.exe"
:run
if not exist "%~dp0.godot\imported\village.png-*.ctex" "%EXE%" --headless --path "%~dp0." --import
start "" "%EXE%" --path "%~dp0."
exit /b
:missing
echo Godot 4.5+ is required. Set LIUCHA_GODOT to the Godot executable.
pause
