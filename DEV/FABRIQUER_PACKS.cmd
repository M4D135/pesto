@echo off
setlocal EnableExtensions DisableDelayedExpansion
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0tools\Build-PestoPacks.py" --source "%~dp0."
) else (
  python "%~dp0tools\Build-PestoPacks.py" --source "%~dp0."
)
set "PESTO_BUILD_EXIT=%ERRORLEVEL%"
pause
exit /b %PESTO_BUILD_EXIT%
