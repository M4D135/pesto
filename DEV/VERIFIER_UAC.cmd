@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Pesto 1.0 - Verification UAC (sonde, sans moteur ni AD)
rem Vraie demande UAC par Pesto.exe et les composants intacts de ce dossier : aucune copie, aucun composant remplace.
rem La sonde PESTO_UAC_PROBE arrete le relais eleve avant la reprise d etat et le moteur. Voir tools\Verify-StartupUac.ps1.
rem Lancer par double-clic depuis une session console NON elevee (pas en SSH, pas en console administrateur).
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tools\Verify-StartupUac.ps1"
set "Pesto_EXIT_CODE=%ERRORLEVEL%"
echo.
if "%Pesto_EXIT_CODE%"=="0" echo Resultat : PASS (UAC demandee par Pesto.exe, relais eleve, aucun moteur charge).
if not "%Pesto_EXIT_CODE%"=="0" echo Resultat : code %Pesto_EXIT_CODE% (1223 = UAC annulee, 2 = invite non vue, 1 = echec). Aucun moteur ni action AD lances par ce test.
pause
exit /b %Pesto_EXIT_CODE%
