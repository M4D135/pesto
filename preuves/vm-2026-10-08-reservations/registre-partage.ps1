# Registre partagé des réservations de noms (08/10/2026) : vrai worker de Pesto, vrais fichiers sur un partage SMB
# (\\localhost\C$, partage administratif existant), plusieurs PROCESSUS Windows PowerShell 5.1 en concurrence.
param([string]$Wad='C:\PestoTest\wad',[string]$Root='\\localhost\C$\PestoRegistreTest',[int]$Processes=6)
$ErrorActionPreference='Stop'
$R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){$R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''}))}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Names.ps1'),[ref]$t,[ref]$e)
$a=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSharedNameWorker'},$true))
if(-not $a.Count){throw 'Worker du registre absent.'}
$body=$a[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
$worker=[scriptblock]::Create($body)
function Invoke-Registry([string]$Mode,[string]$Owner,[string]$Name='',[string[]]$Names=@(),[string]$Domain='LAB.LOCAL',[int]$Minutes=15){
    & $worker ([pscustomobject]@{Mode=$Mode;Root=$Root;Domain=$Domain;Owner=$Owner;Station=$env:COMPUTERNAME;User='banc';Minutes=$Minutes;Name=$Name;Names=$Names;Context='Join'})
}
$local=$Root -replace '^\\\\localhost\\C\$','C:'
if(Test-Path $local){Remove-Item $local -Recurse -Force}
try{
    # 1. Préparation d'un dossier absent (parent existant) : marqueur + locks + reservations, aucun partage créé.
    $p=Invoke-Registry Prepare 'admin'
    Check 'Préparer : dossier, marqueur, locks et reservations créés' ($p.State -eq 'OK' -and (Test-Path "$local\pesto-coordination.json") -and (Test-Path "$local\locks") -and (Test-Path "$local\reservations")) ($p|ConvertTo-Json -Compress)
    $bad=$null;try{Invoke-Registry Snapshot 'x' -Domain 'AUTRE.LOCAL'|Out-Null}catch{$bad=$_.Exception.Message}
    Check 'Registre d''un autre domaine refusé' ($bad -like '*autre domaine*') $bad
    # 2. Concurrence réelle : N processus réservent le même nom au même instant ; un seul gagne.
    $go=[DateTime]::UtcNow.AddSeconds(4).ToString('o')
    $script=@"
`$t=`$null;`$e=`$null;`$ast=[Management.Automation.Language.Parser]::ParseFile('$Wad\Pesto-Names.ps1',[ref]`$t,[ref]`$e)
`$a=@(`$ast.FindAll({param(`$x) `$x -is [Management.Automation.Language.AssignmentStatementAst] -and `$x.Left.Extent.Text -eq '`$script:PestoSharedNameWorker'},`$true))
`$w=[scriptblock]::Create(`$a[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
while([DateTime]::UtcNow -lt [DateTime]::Parse('$go').ToUniversalTime()){Start-Sleep -Milliseconds 5}
`$r=& `$w ([pscustomobject]@{Mode='Reserve';Root='$Root';Domain='LAB.LOCAL';Owner=('proc'+`$PID);Station='POSTE-'+`$PID;User='tech';Minutes=15;Name='P123456PAINF005';Names=@();Context='Join'})
`$r.State
"@
    $file=Join-Path $env:TEMP ('reg-'+[Guid]::NewGuid().ToString('N')+'.ps1');[IO.File]::WriteAllText($file,$script,[Text.UTF8Encoding]::new($true))
    $procs=@(1..$Processes|ForEach-Object{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$file) -RedirectStandardOutput (Join-Path $env:TEMP ("reg-out-$_.txt")) -PassThru -WindowStyle Hidden})
    $procs|Wait-Process -Timeout 120
    $states=@(1..$Processes|ForEach-Object{(Get-Content (Join-Path $env:TEMP ("reg-out-$_.txt")) -Raw).Trim()})
    Remove-Item $file -Force
    Check ("Concurrence ($Processes processus, même nom, même instant) : un seul Reserved, les autres Held") ((@($states|Where-Object{$_ -eq 'Reserved'}).Count -eq 1) -and (@($states|Where-Object{$_ -eq 'Held'}).Count -eq ($Processes-1))) ($states -join ',')
    # 3. Un autre poste voit la réservation ; il ne peut pas la retirer ; le détenteur la prolonge puis la retire.
    $snap=Invoke-Registry Snapshot 'autre'
    Check 'Relevé d''un autre poste : nom réservé visible' (@($snap.Others|Where-Object{$_.Name -eq 'P123456PAINF005'}).Count -eq 1) ($snap.Others|ConvertTo-Json -Compress)
    $mine=Invoke-Registry Reserve 'bancA' 'P123456PAINF006'
    Check 'Réservation d''un nom libre' ($mine.State -eq 'Reserved')
    $other=Invoke-Registry Reserve 'bancB' 'P123456PAINF006'
    Check 'Même nom par un autre poste : Held, détenteur indiqué' ($other.State -eq 'Held' -and $other.Holder) ($other|ConvertTo-Json -Compress)
    [void](Invoke-Registry Release 'bancB' -Names @('P123456PAINF006'))
    Check 'Un autre poste ne retire pas la réservation' (Test-Path "$local\reservations\P123456PAINF006.json")
    $renew=Invoke-Registry Reserve 'bancA' 'P123456PAINF006'
    Check 'Le détenteur prolonge (Renewed)' ($renew.State -eq 'Renewed') $renew.State
    [void](Invoke-Registry Release 'bancA' -Names @('P123456PAINF006'))
    Check 'Le détenteur retire sa réservation' (-not (Test-Path "$local\reservations\P123456PAINF006.json"))
    # 4. Réservation expirée (poste arrêté) : reprise par un autre poste.
    $old=[ordered]@{Schema=1;Name='P123456PAINF007';Domain='LAB.LOCAL';Station='ANCIEN';User='x';Owner='ancien';CreatedUtc=[DateTime]::UtcNow.AddHours(-2).ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddHours(-1).ToString('o')}
    [IO.File]::WriteAllText("$local\reservations\P123456PAINF007.json",($old|ConvertTo-Json -Compress))
    $take=Invoke-Registry Reserve 'bancC' 'P123456PAINF007'
    Check 'Réservation expirée reprise' ($take.State -eq 'Reserved') $take.State
    $snap=Invoke-Registry Snapshot 'autre'
    Check 'Expirée non listée, reprise listée' (@($snap.Others|Where-Object{$_.Name -eq 'P123456PAINF007' -and $_.Station -eq $env:COMPUTERNAME}).Count -eq 1)
    # 5. Fichier en cours d'écriture (ouvert en exclusif par un autre poste) : considéré pris, jamais écrasé.
    $lock=[IO.File]::Open("$local\reservations\P123456PAINF008.json",[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$busy=Invoke-Registry Reserve 'bancD' 'P123456PAINF008'}finally{$lock.Dispose()}
    Check 'Fichier verrouillé par un autre poste : Held' ($busy.State -eq 'Held') $busy.State
    # 6. Fichier vide et ancien (poste arrêté pendant l'écriture) : expiré au-delà de la durée.
    $f="$local\reservations\P123456PAINF008.json";[IO.File]::SetLastWriteTimeUtc($f,[DateTime]::UtcNow.AddHours(-3))
    $take=Invoke-Registry Reserve 'bancD' 'P123456PAINF008'
    Check 'Fichier vide ancien : repris' ($take.State -eq 'Reserved') $take.State
    # 7. Test d'écriture.
    $test=Invoke-Registry Test 'admin'
    Check 'Tester : lecture et écriture d''essai' ($test.State -eq 'OK' -and @(Get-ChildItem "$local\reservations" -Filter '_essai*').Count -eq 0)
    # 8. Nom invalide refusé (aucun chemin fabriqué).
    $bad=$null;try{Invoke-Registry Reserve 'x' '..\..\evil'|Out-Null}catch{$bad=$_.Exception.Message}
    Check 'Nom invalide refusé' ($bad -like '*invalide*') $bad
}catch{$R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber)}
finally{if(Test-Path $local){Remove-Item $local -Recurse -Force}}
$R
'RESULTAT {0} reussis, {1} echecs' -f @($R|Where-Object{$_ -like 'PASS*'}).Count,@($R|Where-Object{$_ -notlike 'PASS*'}).Count
