@echo off
rem Launch Seven Kingdoms II (Godot edition).
rem Set GODOT to your Godot 4.3 executable if it is not at the default place.
setlocal
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\tools\godot\Godot_v4.3-stable_win64.exe"
if not exist "%GODOT%" (
  where godot >nul 2>nul && set "GODOT=godot"
)
if not exist "%GODOT%" if not "%GODOT%"=="godot" (
  echo Godot 4.3 not found. Set GODOT to the path of Godot_v4.3-stable_win64.exe.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." %*
