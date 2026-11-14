@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto - Apercu de saisie local
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%Pesto_PS%" (
    echo ERREUR : Windows PowerShell x64 introuvable.
    pause
    exit /b 1
)
if not exist "%~dp0tests\Run-LoginTests.ps1" (
    echo ERREUR : extraire le dossier tests complet avec le projet.
    pause
    exit /b 1
)
echo Fenetre de test uniquement : saisie fictive, connexion desactivee.
echo Aucun vrai identifiant necessaire. Aucune saisie enregistree.
echo.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-LoginTests.ps1" -Preview
set "Pesto_TEST_EXIT=%ERRORLEVEL%"
echo.
if not "%Pesto_TEST_EXIT%"=="0" (
    echo ECHEC : ne pas utiliser cette version en production sans corriger les tests.
) else (
    echo Apercu termine. Le logiciel normal se lance avec Pesto.cmd.
)
pause
exit /b %Pesto_TEST_EXIT%
