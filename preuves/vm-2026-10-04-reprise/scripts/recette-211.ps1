$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
$D='C:\PestoTest-preuves\2026-10-04-reprise'
$code=1
try {
 & {
  Get-Date -Format o
  'Session='+[Environment]::UserName+'; ID='+[Diagnostics.Process]::GetCurrentProcess().SessionId
  Get-FileHash C:\PestoTest\Pesto.exe -Algorithm SHA256 | Format-List
  $p=Start-Process C:\PestoTest\Pesto.exe -ArgumentList '--inconnu' -PassThru
  'PID='+$p.Id
  $w=Wait-Fenetre '^Pesto 1\.0 \| Demarrage$' 90
  if(-not $w -or $w.Current.ProcessId -ne $p.Id){throw 'Boite attendue absente ou mauvais processus'}
  $tree=@(Get-Arbre $w 6)
  $tree
  if(($tree -join "`n") -notmatch 'Code de sortie du lanceur : 120\.'){throw 'Code 120 absent du message'}
  Save-Ecran "$D\2.11-erreur-120.png"
  Send-Touches $w '{ENTER}'
  if(-not $p.WaitForExit(30000)){throw 'Processus encore actif'}
  'ExitCode='+$p.ExitCode
  if($p.ExitCode -ne 120){throw 'Code processus different de 120'}
  'RESULTAT=PASS'
 } | Out-File "$D\2.11-erreur-120.txt" -Encoding utf8
 $code=0
}catch{
 $_ | Out-String | Out-File "$D\2.11-erreur-120.txt" -Encoding utf8 -Append
}
exit $code
