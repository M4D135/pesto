@echo off
setlocal EnableExtensions DisableDelayedExpansion
if not exist "%~dp0Pesto.exe" (
 echo Pesto.exe absent. Extraire tout le pack.
 pause
 exit /b 1
)
start "" /wait "%~dp0Pesto.exe" -Demo
exit /b %ERRORLEVEL%
