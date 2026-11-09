@echo off
setlocal
cd /d "%~dp0"
echo Fabrication de Pesto.exe + dossier wad dans un nouveau dossier.
echo Le cfg.json du dossier wad fourni sera inclus.
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0tools\Build-PestoProduction.py" %*
) else (
  python "%~dp0tools\Build-PestoProduction.py" %*
)
set "PESTO_BUILD_RESULT=%errorlevel%"
echo.
if not "%PESTO_BUILD_RESULT%"=="0" echo ECHEC : lire le message ci-dessus. Aucun ancien PROD remplace.
pause
exit /b %PESTO_BUILD_RESULT%
