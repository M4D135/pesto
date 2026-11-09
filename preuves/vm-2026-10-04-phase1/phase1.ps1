# Recette phase 1 (1.1 à 1.7) sur C:\PestoTest, session SSH non interactive. Sorties dans C:\PestoTest-preuves\vm-2026-10-04-phase1.
$ErrorActionPreference = 'Continue'
$D = 'C:\PestoTest-preuves\vm-2026-10-04-phase1'; New-Item -ItemType Directory -Force $D | Out-Null
Set-Location C:\PestoTest
$r = New-Object System.Collections.Generic.List[string]
function Note([string]$t) { $r.Add($t); $t }
Note ('date VM : ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss zzz'))
Note ('Pesto.exe SHA-256 : ' + (Get-FileHash .\Pesto.exe -Algorithm SHA256).Hash)
Note ('PowerShell : ' + $PSVersionTable.PSVersion + ' ' + $PSVersionTable.PSEdition)
Note ('compte : ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
# 1.1
& powershell -NoProfile -ExecutionPolicy RemoteSigned -File ..\outils\parse_all.ps1 -Root . *> "$D\1.1-parse_all.txt"
Note ('1.1 code ' + $LASTEXITCODE + ' ; fin : ' + ((Get-Content "$D\1.1-parse_all.txt" | Where-Object { $_.Trim() }) | Select-Object -Last 1))
# 1.2
Remove-Item C:\PestoTest\check.json -ErrorAction SilentlyContinue
$p = Start-Process .\Pesto.exe -ArgumentList '--check-json','C:\PestoTest\check.json' -Wait -PassThru
Copy-Item C:\PestoTest\check.json "$D\1.2-check.json" -ErrorAction SilentlyContinue
$j = Get-Content C:\PestoTest\check.json -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
Note ('1.2 code ' + $p.ExitCode + ' ; Runtime=' + $j.Runtime + ' ComponentCount=' + $j.ComponentCount + ' Syntax=' + $j.Syntax + ' ParsedFiles=' + $j.ParsedFiles + ' EmbeddedScripts=' + $j.EmbeddedScripts + ' AuditWriter=' + $j.AuditWriter)
# 1.3
$p = Start-Process .\Pesto.exe -ArgumentList '--check','--quiet' -Wait -PassThru
Note ('1.3 --check --quiet code ' + $p.ExitCode)
# 1.4
$v = (Get-Item .\Pesto.exe).VersionInfo
Note ('1.4 FileVersionRaw=' + $v.FileVersionRaw + ' ProductVersionRaw=' + $v.ProductVersionRaw + ' FileVersion="' + $v.FileVersion + '" ProductVersion="' + $v.ProductVersion + '" ProductName="' + $v.ProductName + '"')
# 1.5
& powershell -NoProfile -ExecutionPolicy RemoteSigned -File tests\Run-StabilisationTests.ps1 *> "$D\1.5-stabilisation.txt"
Note ('1.5 code ' + $LASTEXITCODE + ' ; fin : ' + ((Get-Content "$D\1.5-stabilisation.txt" | Where-Object { $_.Trim() }) | Select-Object -Last 1))
# 1.6 et 1.7
cmd /c "echo.| TESTER.cmd > ""$D\1.6-TESTER.txt"" 2>&1"
Note ('1.6 code ' + $LASTEXITCODE)
cmd /c "echo.| TEST_RC23.cmd > ""$D\1.7-TEST_RC23.txt"" 2>&1"
Note ('1.7 code ' + $LASTEXITCODE)
$r | Out-File -Encoding utf8 "$D\resume.txt"
