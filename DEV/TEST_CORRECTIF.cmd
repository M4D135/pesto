@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto - Tests du correctif RC4
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%Pesto_PS%" (
    echo ERREUR : Windows PowerShell x64 introuvable.
    pause
    exit /b 1
)
if not exist "%~dp0tests\Run-RC4Tests.ps1" (
    echo ERREUR : dossier tests incomplet. Extraire tout le correctif.
    pause
    exit /b 1
)
echo Tests isoles : aucun acces Active Directory ni appel aux postes.
echo Verification du correctif Replace et de la regle rename / site.
echo Les fichiers de test sont crees uniquement dans un dossier temporaire.
echo.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-RC4Tests.ps1"
set "Pesto_TEST_EXIT=%ERRORLEVEL%"
echo.
if not "%Pesto_TEST_EXIT%"=="0" (
    echo ECHEC. Consulter les messages et tests\windows-rc4-results.json si cree.
) else (
    echo Tests termines sans echec. Rapport : tests\windows-rc4-results.json
)
pause
exit /b %Pesto_TEST_EXIT%
