@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto 1.0 - Tests jonction et parcours
set "PESTO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PESTO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-Pesto23Tests.ps1" -Wpf %*
set "RESULT=%ERRORLEVEL%"
echo Recette AD et UAC reelle distincte. Code : %RESULT%
pause
exit /b %RESULT%
