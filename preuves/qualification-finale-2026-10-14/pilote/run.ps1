# Lance une étape du pilote et range toute sa sortie dans preuves\<étape>.log (UTF-8).
param([Parameter(Mandatory=$true)][string]$Etape)
$D='C:\PestoFinal_20261014\preuves';[void][IO.Directory]::CreateDirectory($D)
$log="$D\$Etape.log"
try { & "C:\PestoFinal_20261014\pilot\$Etape.ps1" *>&1 | ForEach-Object { "$_" } | Out-File $log -Encoding UTF8; exit 0 }
catch { ($_ | Out-String) | Out-File $log -Append -Encoding UTF8; exit 1 }
