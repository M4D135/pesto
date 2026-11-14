@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PESTO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PESTO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PESTO_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-NamesLoadingTests.ps1" -Wpf %*
set "PESTO_EXIT=%ERRORLEVEL%"
echo Aucun acces AD ni mutation Windows dans ce test.
pause
exit /b %PESTO_EXIT%
