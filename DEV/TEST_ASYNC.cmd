@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto - Tests du correctif asynchrone RC3
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%Pesto_PS%" (
    echo ERREUR : Windows PowerShell x64 introuvable.
    pause
    exit /b 1
)
if not exist "%~dp0tests\Run-AsyncTests.ps1" (
    echo ERREUR : dossier tests incomplet. Extraire tout le correctif.
    pause
    exit /b 1
)
echo Tests isoles : aucun acces AD, aucune operation sur les postes.
echo Les timers WPF et les runspaces sont reels. Pesto lui-meme ne sera pas lance.
echo.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-AsyncTests.ps1"
set "Pesto_TEST_EXIT=%ERRORLEVEL%"
echo.
if not "%Pesto_TEST_EXIT%"=="0" (
    echo ECHEC. Consulter les messages et tests\windows-async-results.json si cree.
) else (
    echo Tests termines sans echec. Rapport : tests\windows-async-results.json
)
pause
exit /b %Pesto_TEST_EXIT%
