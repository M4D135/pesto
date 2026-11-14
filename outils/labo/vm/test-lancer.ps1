# Regression reelle du pilote de labo, sur la VM Pesto uniquement, sans AD ni UAC.
param([string]$Lanceur='', [string]$Compte='PESTO-W11-TEST\labadmin', [string]$CompteAbsent='', [Parameter(Mandatory=$true)][string]$Preuves)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PESTO-W11-TEST'){throw 'VM Pesto exclusivement'}
if(-not $Lanceur){$Lanceur=Join-Path $PSScriptRoot 'lancer.ps1'}
New-Item -ItemType Directory $Preuves | Out-Null
$results=[Collections.Generic.List[object]]::new()
$engine=Join-Path $PSHOME 'powershell.exe'
$utf8=[Text.UTF8Encoding]::new($true)
function Quote([string]$Text){return "'"+$Text.Replace("'","''")+"'"}
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Run([string]$Name,[string]$Command){
 $entry=Join-Path $Preuves ($Name+'.ps1')
 [IO.File]::WriteAllText($entry,('& '+(Quote $Lanceur)+' '+$Command+"`r`nexit `$LASTEXITCODE`r`n"),$utf8)
 $stdout=Join-Path $Preuves ($Name+'-stdout.txt');$stderr=Join-Path $Preuves ($Name+'-stderr.txt')
 $process=Start-Process $engine -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$entry+'"') -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
 return [pscustomobject]@{Code=$process.ExitCode;Text=((Get-Content $stdout -Raw)+(Get-Content $stderr -Raw))}
}
function Case([string]$Name,[scriptblock]$Body){
 try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Detail=''});"PASS $Name"}
 catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Detail=$_.Exception.Message});"FAIL $Name : $($_.Exception.Message)"}
}
$account=' -Compte '+(Quote $Compte)
if($CompteAbsent){
 Case 'absence-session' {
  $r=Run 'absence-session' ('-Exe cmd.exe -Arguments ''/c exit 7'' -Attendre -Delai 2 -Compte '+(Quote $CompteAbsent))
  Assert ($r.Code -ne 0) 'Faux succes sans session'
  Assert ($r.Text -match 'Delai depasse') 'Absence de diagnostic du delai'
 }
}
Case 'fin-0' {$r=Run 'fin-0' ('-Exe cmd.exe -Arguments ''/c exit 0'' -Attendre -Delai 30'+$account);Assert ($r.Code -eq 0 -and $r.Text -match 'resultat=0') 'Fin reussie non reconnue'}
Case 'fin-7' {$r=Run 'fin-7' ('-Exe cmd.exe -Arguments ''/c exit 7'' -Attendre -Delai 30'+$account);Assert ($r.Code -ne 0 -and $r.Text -match 'resultat=7') 'Echec enfant perdu'}
Case 'executable-absent' {$r=Run 'executable-absent' ('-Exe C:\PestoTest-run\absent-'+[guid]::NewGuid().ToString('N')+'.exe -Attendre -Delai 30'+$account);Assert ($r.Code -ne 0 -and $r.Text -match 'resultat=2147942402') 'Erreur de creation du processus perdue'}
Case 'delai-en-cours' {
 $r=Run 'delai-en-cours' ('-Exe powershell.exe -Arguments ''-NoProfile -Command Start-Sleep -Seconds 20'' -Attendre -Delai 3'+$account)
 Assert ($r.Code -ne 0 -and $r.Text -match 'tache conservee') 'Delai annonce comme succes ou tache perdue'
 $taskName=[regex]::Match($r.Text,'PestoPilote-[0-9a-f]+').Value
 Assert ([bool]$taskName) 'Nom de tache absent'
 $task=Get-ScheduledTask -TaskName $taskName
 Assert ($task.State -eq 'Running') 'Test arrete au delai'
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while((Get-ScheduledTask -TaskName $taskName).State -eq 'Running' -and $watch.Elapsed.TotalSeconds -lt 40){Start-Sleep -Milliseconds 500}
 Assert ((Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult -eq 0) 'Test ne termine pas normalement apres le delai'
 Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Case 'sans-attendre' {
 $r=Run 'sans-attendre' ('-Exe cmd.exe -Arguments ''/c exit 0'' -Delai 30'+$account)
 Assert ($r.Code -eq 0) 'Demarrage ou fin rapide non constate'
}
$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Preuves 'resultats.json') -Encoding UTF8
$failed=@($results | Where-Object {-not $_.Passed}).Count
"Total=$($results.Count) Echecs=$failed"
if($failed){exit 1}
