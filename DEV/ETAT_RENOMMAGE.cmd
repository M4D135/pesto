@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto - Diagnostic lecture seule
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%~dp0tools\Diagnostic-Rename.ps1" (
 echo ERREUR : extraire le dossier tools du correctif.
 pause
 exit /b 1
)
"%Pesto_PS%" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0tools\Diagnostic-Rename.ps1"
set "Pesto_RC=%ERRORLEVEL%"
pause
exit /b %Pesto_RC%
