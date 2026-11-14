$ErrorActionPreference='Stop'
$base='C:\PestoTest-run\python-549a4aa'
Rename-Item "$base\python\python314._pth" 'python314._pth-isole-original'
Set-Location "$base\DEV"
$env:PATH="$base\python;"+$env:PATH
$p=Start-Process "$base\python\python.exe" -ArgumentList '-X utf8 C:\PestoTest-run\rejouer-python.py' -RedirectStandardOutput 'C:\PestoTest-preuves\2026-10-04-reprise\python-rejeu-stdout.txt' -RedirectStandardError 'C:\PestoTest-preuves\2026-10-04-reprise\python-rejeu.txt' -Wait -PassThru
"CODE=$($p.ExitCode)" | Out-File 'C:\PestoTest-preuves\2026-10-04-reprise\python-rejeu-code.txt' -Encoding utf8
exit $p.ExitCode
