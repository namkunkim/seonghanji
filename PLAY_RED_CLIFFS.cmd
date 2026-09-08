@echo off
setlocal
set "PROJECT_DIR=%~dp0."
start "" "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --path "%PROJECT_DIR%" --windowed --resolution 1600x900 --position 80,60 --script res://tools/play_red_cliffs_direct.gd
endlocal
