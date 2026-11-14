# Suite UX seule dans la session console, trois passes, pour départager un cas sensible au minutage.
. 'C:\PestoFinal_20261014\pilot\commun.ps1'
$T = "$R\dev\DEV\tests"; Set-Location $T
foreach ($i in 1..3) {
    "=== passe $i"
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "$T\Run-UxTests.ps1" 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notlike 'OK  *' }
    "code=$LASTEXITCODE"
}
