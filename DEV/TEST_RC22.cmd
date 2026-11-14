@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\Run-Pesto22Tests.ps1" -Wpf
set "RET=%ERRORLEVEL%"
pause
exit /b %RET%
