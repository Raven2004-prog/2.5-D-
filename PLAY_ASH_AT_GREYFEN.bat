@echo off
setlocal
set "GAME_DIR=%~dp0"
set "STANDALONE_EXE=%GAME_DIR%builds\windows\Ash Witness - The Same Rain.exe"
set "GODOT_EXE=%GAME_DIR%..\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

if exist "%STANDALONE_EXE%" (
  start "Ash Witness - The Same Rain" "%STANDALONE_EXE%"
  exit /b 0
)

if not exist "%GODOT_EXE%" (
  echo Godot 4.7.1 was not found beside the AshAtGreyfen folder.
  echo Expected: %GODOT_EXE%
  pause
  exit /b 1
)

start "Ash Witness - The Same Rain" "%GODOT_EXE%" --path "%GAME_DIR%."
endlocal
