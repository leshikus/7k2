@echo off
rem Launch the game. Set GODOT to the path of your Godot 4.3 executable if it is not on PATH.
if "%GODOT%"=="" set GODOT=godot
"%GODOT%" --path "%~dp0"
