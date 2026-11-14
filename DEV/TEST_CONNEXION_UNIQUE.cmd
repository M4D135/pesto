@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
echo Tests RC13 de connexion unique. AD, Entra et renommage simules.
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-SsoTests.ps1"
set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" echo TEST EN ECHEC. Ne pas utiliser le correctif en production.
pause
exit /b %RC%
