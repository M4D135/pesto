@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "Pesto_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "Pesto_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-StartupTests.ps1"
set "Pesto_EXIT_CODE=%ERRORLEVEL%"
echo.
pause
exit /b %Pesto_EXIT_CODE%
