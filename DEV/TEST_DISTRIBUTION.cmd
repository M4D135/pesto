@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
title Pesto RC18 - Tests de distribution isoles
"%Pesto_PS%" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0wad\maintenance\Test-PestoDistribution.ps1" %*
set "Pesto_RESULT=%ERRORLEVEL%"
echo.
if not "%Pesto_RESULT%"=="0" echo Controle en echec. Lire le rapport avant diffusion.
pause
exit /b %Pesto_RESULT%
