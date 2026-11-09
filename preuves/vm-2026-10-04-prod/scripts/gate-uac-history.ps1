$ErrorActionPreference='Stop'
$D='C:\PestoTest-preuves\2026-10-04-prod'
$G=Join-Path $D 'gate-df14ab7f'
[void][IO.Directory]::CreateDirectory($G)
$env:PSModulePath='C:\PestoTest-run\validation-modules;'+$env:PSModulePath
foreach($n in @('names.json','rc21.json','rc22.json','rc23.json')){Copy-Item (Join-Path "$D\gate-d52d0eb" $n) (Join-Path $G $n) -Force}
'Rapports RC21/22/23 et noms réutilisés : sources de ces parcours inchangées. Correctifs limités à Startup : deux files Idle vides et archivage sans fusion des historiques divergents.'|Set-Content "$G\provenance.txt" -Encoding UTF8
& powershell -NoProfile -STA -ExecutionPolicy Bypass -File C:\PestoTest\wad\maintenance\Test-Pesto19.ps1 -ReportDirectory "$G\native" *> "$G\native.txt"
if($LASTEXITCODE -ne 0){throw 'Tests natifs'}
& powershell -NoProfile -STA -ExecutionPolicy Bypass -File C:\PestoTest\tools\Verify-Release.ps1 -ReportDirectory $G *> "$G\verify-release.txt"
if($LASTEXITCODE -ne 0){throw 'Verify-Release'}
& C:\PestoTest-run\python-549a4aa\python\python.exe C:\PestoTest\tools\checks\validate_pesto.py --require-parser *> "$G\validation-complete.txt"
if($LASTEXITCODE -ne 0){throw 'Validation Python et parseur'}
Copy-Item C:\PestoTest\tests\pesto-portable-validation.json "$G\validation-complete.json" -Force
'PASS'|Set-Content "$G\resultat.txt"
