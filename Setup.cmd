@echo off
REM ===========================================================================
REM  SoulwardenKioku -- one-time setup. Installs the packet-capture engine.
REM  Run this once before your first capture.
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
echo.
pause
