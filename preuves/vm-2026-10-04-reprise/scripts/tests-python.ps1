$ErrorActionPreference='Stop'
Set-Location C:\PestoTest-run\python-549a4aa\DEV
$env:PATH='C:\PestoTest-run\python-549a4aa\python;'+$env:PATH
$p=Start-Process 'C:\PestoTest-run\python-549a4aa\python\python.exe' -ArgumentList '-X utf8 -m unittest discover -v -s tests -p test_*.py' -RedirectStandardOutput 'C:\PestoTest-preuves\2026-10-04-reprise\python-tests-stdout.txt' -RedirectStandardError 'C:\PestoTest-preuves\2026-10-04-reprise\python-tests.txt' -Wait -PassThru
$code=$p.ExitCode
"CODE=$code" | Out-File C:\PestoTest-preuves\2026-10-04-reprise\python-tests-code.txt -Encoding utf8
Get-Content C:\PestoTest-preuves\2026-10-04-reprise\python-tests-code.txt
exit $code
