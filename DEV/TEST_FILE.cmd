@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto - Tests retrait de file RC8
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%Pesto_PS%" (
    echo ERREUR : Windows PowerShell x64 introuvable.
    pause
    exit /b 1
)
if not exist "%~dp0tests\Run-QueueRemovalTests.ps1" (
    echo ERREUR : extraire le dossier tests complet avec le projet.
    pause
    exit /b 1
)
echo Fonctions de file isolees : aucune execution de Pesto et aucun acces AD.
echo Pas de changement de configuration ou de permissions. Rapports dans tests.
echo.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-QueueRemovalTests.ps1"
set "Pesto_TEST_EXIT=%ERRORLEVEL%"
echo.
if not "%Pesto_TEST_EXIT%"=="0" (
    echo ECHEC : ne pas utiliser cette version en production sans corriger les tests.
) else (
    echo Tests locaux termines. Ils ne remplacent pas une recette AD de preproduction.
)
pause
exit /b %Pesto_TEST_EXIT%
