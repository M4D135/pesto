# L6 / pack PROD : exécution NON élevée depuis C:\Program Files (droits par défaut : utilisateurs en lecture et exécution).
$R = 'C:\Program Files\Pesto-PROD-test'
& {
  'compte : ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name + ' ; eleve : ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  try { [IO.File]::WriteAllText("$R\wad\essai-ecriture.txt", 'x'); 'ECRITURE POSSIBLE dans wad (inattendu)' } catch { 'ecriture refusee dans wad : ' + $_.Exception.GetType().Name }
  $p = Start-Process "$R\Pesto.exe" -ArgumentList '--check','--quiet' -Wait -PassThru; '--check --quiet : code ' + $p.ExitCode
  $j = Join-Path $env:TEMP ('prod-check-' + [guid]::NewGuid().ToString('N') + '.json')
  $p = Start-Process "$R\Pesto.exe" -ArgumentList '--check-json',$j -Wait -PassThru; '--check-json : code ' + $p.ExitCode
  if (Test-Path $j) { Get-Content $j -Raw | ConvertFrom-Json | Select-Object Runtime,ComponentCount,ParsedFiles,EmbeddedScripts,AuditWriter | Format-List | Out-String }
} *> C:\PestoTest-run\prod.txt
