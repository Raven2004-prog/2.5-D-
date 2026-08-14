@echo off
setlocal
set "GAME_DIR=%~dp0"
set "GODOT_EXE=%GAME_DIR%..\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

if not exist "%GODOT_EXE%" (
  echo Godot 4.7.1 was not found beside the AshAtGreyfen folder.
  echo Expected: %GODOT_EXE%
  pause
  exit /b 1
)

start "Ash Witness - The Same Rain" "%GODOT_EXE%" --path "%GAME_DIR%"
endlocal
