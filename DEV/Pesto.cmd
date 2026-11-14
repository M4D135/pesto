@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%Pesto_PS%" (
    echo ERREUR : Windows PowerShell x64 introuvable.
    pause
    exit /b 1
)
if not exist "%~dp0wad\Pesto-Core.ps1" (
    echo ERREUR : wad\Pesto-Core.ps1 absent. Extraire tout le dossier Pesto.
    pause
    exit /b 1
)
rem Le lanceur demande l'UAC avant toute connexion AD, sauf -Demo.
rem RemoteSigned ne concerne que ce processus ; les GPO restent prioritaires.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0wad\Pesto-Startup.ps1" %*
set "Pesto_EXIT_CODE=%ERRORLEVEL%"
if "%Pesto_EXIT_CODE%"=="1223" (
    echo Autorisation UAC annulee. Pesto n'a lance aucune action.
    exit /b 1223
)
if not "%Pesto_EXIT_CODE%"=="0" (
    echo.
    echo Pesto a signale une erreur. Consulter le message et wad\logs\Pesto-demarrage.log si present.
    echo Apres extraction, executer wad\support\DEBLOQUER_TOUT.cmd avant de relancer Pesto.
    pause
)
exit /b %Pesto_EXIT_CODE%
