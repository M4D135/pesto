@echo off
setlocal
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
echo Tests locaux du login compact Pesto 1.0. Aucun appel AD ni operation sur les postes.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-LoginTests.ps1"
if errorlevel 1 goto failed
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-LoginPreferencesTests.ps1"
if errorlevel 1 goto failed
echo Tests termines.
pause
exit /b 0
:failed
echo Un test a echoue. Consultez les details ci-dessus avant utilisation.
pause
exit /b 1
