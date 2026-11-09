@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto 1.0 - Tests Windows isoles
set "PESTO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PESTO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
echo Tests du vrai parseur, des fonctions isolees, du check EXE et de WPF.
echo Aucun appel AD, aucun renommage, aucun retrait Entra, aucune UAC.
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0wad\maintenance\Test-Pesto19.ps1" %*
set "PESTO_EXIT=%ERRORLEVEL%"
if not "%PESTO_EXIT%"=="0" goto finish
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-NamesLoadingTests.ps1" -Wpf
set "PESTO_EXIT=%ERRORLEVEL%"
if not "%PESTO_EXIT%"=="0" goto finish
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-Pesto21Tests.ps1" -Wpf
set "PESTO_EXIT=%ERRORLEVEL%"
if not "%PESTO_EXIT%"=="0" goto finish
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-Pesto22Tests.ps1" -Wpf
set "PESTO_EXIT=%ERRORLEVEL%"
if not "%PESTO_EXIT%"=="0" goto finish
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-Pesto23Tests.ps1" -Wpf
set "PESTO_EXIT=%ERRORLEVEL%"
:finish
if not "%PESTO_EXIT%"=="0" echo ECHEC : ne pas utiliser sur les postes de production.
echo Une recette interactive UAC et domaine sur VM reste necessaire.
pause
exit /b %PESTO_EXIT%
