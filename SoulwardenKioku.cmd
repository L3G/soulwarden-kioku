@echo off
REM ===========================================================================
REM  SoulwardenKioku -- New World network capture.
REM  Double-click this to record one play session.
REM ===========================================================================
setlocal
set "HERE=%~dp0"
echo.
echo   SoulwardenKioku -- New World network capture
echo   ----------------------------------
echo   Give this session a short label, e.g.  char-create  /  msq-windsward
echo.
set "LABEL="
set /p "LABEL=  Session label: "
if "%LABEL%"=="" set "LABEL=session"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%scripts\capture.ps1" -Label "%LABEL%"
echo.
pause
