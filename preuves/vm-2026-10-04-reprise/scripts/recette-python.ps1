$ErrorActionPreference='Stop'
$base='C:\PestoTest-run\python-549a4aa'
if(Test-Path $base){throw 'Destination deja presente'}
New-Item -ItemType Directory $base | Out-Null
Expand-Archive C:\PestoTest-run\python-3.14.7-embed-amd64.zip -DestinationPath "$base\python"
& tar.exe -xf C:\PestoTest-run\pesto-python-549a4aa.tar -C $base
if($LASTEXITCODE -ne 0){throw 'Extraction impossible'}
$proof='C:\PestoTest-preuves\2026-10-04-reprise'
New-Item -ItemType Directory $proof -Force | Out-Null
& {
 Get-Date -Format o
 $PSVersionTable
 Get-FileHash C:\PestoTest-run\python-3.14.7-embed-amd64.zip -Algorithm SHA256
 Get-AuthenticodeSignature "$base\python\python.exe" | Select-Object Status,@{n='Signataire';e={$_.SignerCertificate.Subject}}
 Get-FileHash "$base\DEV\Pesto.exe" -Algorithm SHA256
 & "$base\python\python.exe" --version
} | Out-File "$proof\python-environnement.txt" -Encoding utf8
Set-Location "$base\DEV"
& "$base\python\python.exe" -X utf8 tools\checks\validate_pesto.py --require-parser *> "$proof\1.8-validate.txt"
$code=$LASTEXITCODE
Copy-Item tests\pesto-portable-validation.json "$proof\1.8-rapport.json"
"CODE=$code" | Out-File "$proof\1.8-code.txt" -Encoding utf8
Get-Content "$proof\1.8-code.txt"
exit $code
