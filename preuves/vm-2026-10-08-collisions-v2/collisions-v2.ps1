# Banc de collisions v2 (08/10/2026, question de David : « avec quelle méthode t'as testé la collision avec le partage, mais
# on avait aussi l'option random name et celle de créer l'objet »).
# À lancer dans la session de LABO\tech.pesto sur PESTO-W11-TEST (outils/labo/mac/sess.sh) : Kerberos, aucun mot de passe.
# Plusieurs techniciens (processus séparés) ajoutent chacun un PC au domaine dans le même site, même service, même type.
# Arbitre final : le VRAI AD (DC01). Les comptes créés vont dans OU=Paris de l'OU de recette, sous des séries neuves
# (P111301VA7xx et 8xx, chaque série vérifiée vide avant usage), et sont supprimés par GUID à la fin de chaque tour (contrôle de la série vide ensuite).
# Réglages : hasard (RandomNameChoice 0 ou 5) x registre partagé x réservation AD, plus le registre sans le correctif du
# 08/10 (aucune réservation pendant le traitement). Profils : départ simultané, ou départs étalés sur 6 s ; clic 0,3 à 3 s
# après l'affichage ; lecture de la confirmation 1,5 à 4 s.
param([string]$Wad='C:\PestoTest\wad',[int]$Techs=4,[int]$Rounds=6,[string]$Profiles='Simultané,Décalé',[string]$OnlyModes='',
      [string]$DC='dc01.labo.local',[string]$Domain='labo.local',
      [string]$OU='OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local',
      [string]$LyonOU='OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local',
      [string]$Base='P111301VA',[int]$FirstService=700,[string]$Out='C:\PestoTest-preuves\collisions-v2')
$ErrorActionPreference='Stop'
$runId=(Get-Date).ToString('yyyyMMdd-HHmmss')
[void][IO.Directory]::CreateDirectory($Out)
$txt=Join-Path $Out 'collisions-v2.txt';$jsonPath=Join-Path $Out 'collisions-v2.json';$ledger=Join-Path $Out "grand-livre-$runId.jsonl"
$lines=[Collections.Generic.List[string]]::new()
function Say([string]$t){$lines.Add($t);$t;[IO.File]::WriteAllLines($txt,$lines,[Text.UTF8Encoding]::new($true))}
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath','Import-PestoADModule'))))
Import-PestoADModule -ADModulePath (Join-Path $Wad 'ActiveDirectory.psd1')
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Names.ps1'),[ref]$t,[ref]$e)
$regWorker=[scriptblock]::Create(@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSharedNameWorker'},$true))[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
$techScript=Join-Path $PSScriptRoot 'collision-v2-tech.ps1'
$adp=@{Server=$DC}
$me=[Security.Principal.WindowsIdentity]::GetCurrent().Name

function Sum($items,[string]$p){$t=0;foreach($i in @($items)){$v=$i.$p;if($null -ne $v){$t+=[int]$v}};$t}
function Max($items,[string]$p){$t=0;foreach($i in @($items)){$v=$i.$p;if($null -ne $v -and [int]$v -gt $t){$t=[int]$v}};$t}
function Get-Series([string]$prefix){@(Get-ADComputer -LDAPFilter "(sAMAccountName=$prefix*)" -Properties Description,ObjectGUID @adp)}
function Remove-BenchAccounts([string]$prefix){
    # Seuls les comptes du banc : série du tour, OU de recette, description du banc ou de la réservation Pesto.
    $n=0
    foreach($o in (Get-Series $prefix)){
        $ok=([string]$o.DistinguishedName).EndsWith(',OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local',[StringComparison]::OrdinalIgnoreCase) -and ([string]$o.Description -like 'Réservé par Pesto*' -or [string]$o.Description -like 'Banc collisions Pesto*')
        if($ok){Remove-ADComputer -Identity ([string]$o.ObjectGUID) -Confirm:$false @adp;$n++}else{Say "  ATTENTION : compte non supprimé (hors banc) : $($o.DistinguishedName) « $($o.Description) »"}
    }
    $n
}
function Start-Techs([object[]]$Specs,[int]$TimeoutSec=300){
    $procs=@(foreach($s in $Specs){
        $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$techScript)
        foreach($k in $s.Keys){$a+=@("-$k",('"'+[string]$s[$k]+'"'))}
        Start-Process powershell.exe -ArgumentList $a -PassThru -WindowStyle Hidden -RedirectStandardError ($s.Out+'.err') -RedirectStandardOutput ($s.Out+'.std')
    })
    $procs|Wait-Process -Timeout $TimeoutSec -ErrorAction SilentlyContinue
    foreach($p in $procs){if(-not $p.HasExited){try{$p.Kill()}catch{}}}
    @(foreach($s in $Specs){
        $err='';foreach($x in @($s.Out+'.err',$s.Out+'.std')){if(Test-Path $x){$err+=(([string](Get-Content $x -Raw)) -replace '\s+',' ').Trim();Remove-Item $x}}
        if(Test-Path $s.Out){Get-Content $s.Out -Raw -Encoding UTF8|ConvertFrom-Json;Remove-Item $s.Out}
        else{[pscustomobject]@{Tech=$s.Tech;Error=('aucun résultat : '+$(if($err){$err.Substring(0,[Math]::Min(400,$err.Length))}else{'processus arrêté ?'}))}}
    })
}

Say "Banc de collisions v2 — $runId — identité $me — DC $DC"
Say ("Sources Pesto : "+((Get-ChildItem $Wad -Filter 'Pesto-*.ps1'|Where-Object{$_.Name -in @('Pesto-Names.ps1','Pesto-Join.ps1','Pesto-Core.ps1','Pesto-Policy.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1')}|Sort-Object Name|ForEach-Object{$_.Name+' '+(Get-FileHash $_.FullName).Hash.Substring(0,12)}) -join ', '))
$regBase="\\localhost\C$\PestoCollisionsV2\$runId";$regLocal="C:\PestoCollisionsV2\$runId"
[void][IO.Directory]::CreateDirectory($regLocal)
$script:svc=$FirstService;$script:usedPrefixes=[Collections.Generic.List[string]]::new()
function Next-Prefix{
    # Série neuve : jamais une série déjà présente dans l'AD (aucun compte existant n'est touché).
    do{if($script:svc -gt 999){throw 'Plus de série libre.'};$p="$Base$($script:svc)";$script:svc++}while(@(Get-Series $p).Count)
    $script:usedPrefixes.Add($p);$p
}

# 1. L'arbitre AD seul : même nom au même instant, puis conflit entre deux OU (le refus doit être classé « Taken »).
Say '';Say '== Arbitre AD (vrai worker de réservation de Pesto, 4 processus, même nom, même milliseconde)'
foreach($i in 1..3){
    $prefix=Next-Prefix;$name="$($prefix)001"
    $go=[DateTime]::UtcNow.AddSeconds(12).ToString('o')
    $specs=@(1..$Techs|ForEach-Object{[ordered]@{Kind='MicroAD';Tech=$_;GoUtc=$go;StartMs=0;Name=$name;OU=$OU;DC=$DC;Domain=$Domain;Wad=$Wad;Ledger="$ledger.$_";Out=(Join-Path $env:TEMP "micro-$runId-$i-$_.json")}})
    $r=Start-Techs $specs 120
    $states=@($r|ForEach-Object{if($_.Error){'ERREUR'}else{[string]$_.State}})
    $acc=@(Get-Series $prefix).Count
    Say ("essai {0} : {1} -> {2} ; comptes dans l'AD : {3} ; {4}" -f $i,$name,($states -join ' '),$acc,$(if(@($states|Where-Object{$_ -eq 'Reserved'}).Count -eq 1 -and @($states|Where-Object{$_ -eq 'Taken'}).Count -eq ($Techs-1) -and $acc -eq 1){'OK : un seul gagnant, les autres « Taken »'}else{'ÉCART'}))
    foreach($x in $r){if($x.Error){Say "  erreur tech $($x.Tech) : $($x.Error)"}}
    [void](Remove-BenchAccounts $prefix)
}
$prefix=Next-Prefix;$name="$($prefix)001"
New-ADComputer -Name $name -SamAccountName "$name`$" -Path $LyonOU -Enabled $false -Description 'Banc collisions Pesto 08/10 (conflit entre OU)' @adp
$go=[DateTime]::UtcNow.AddSeconds(12).ToString('o')
$r=Start-Techs @([ordered]@{Kind='MicroAD';Tech=1;GoUtc=$go;StartMs=0;Name=$name;OU=$OU;DC=$DC;Domain=$Domain;Wad=$Wad;Ledger="$ledger.1";Out=(Join-Path $env:TEMP "micro-$runId-ou.json")}) 120
Say ("conflit entre OU : {0} existe dans Lyon, réservation dans Paris -> {1} {2}" -f $name,[string]$r[0].State,$(if($r[0].State -eq 'Taken'){'OK (classé « Taken » : nom suivant proposé)'}else{'ÉCART : '+[string]$r[0].Error}))
[void](Remove-BenchAccounts $prefix)

# 2. Matrice des réglages.
$modes=[ordered]@{
    'Sans protection'=@{Random=0;Registry=0;ADReserve=0;OldBusy=0}
    'Hasard (5)'=@{Random=5;Registry=0;ADReserve=0;OldBusy=0}
    'Registre (avant correctif)'=@{Random=0;Registry=1;ADReserve=0;OldBusy=1}
    'Registre'=@{Random=0;Registry=1;ADReserve=0;OldBusy=0}
    'Registre + hasard'=@{Random=5;Registry=1;ADReserve=0;OldBusy=0}
    'Réservation AD'=@{Random=0;Registry=0;ADReserve=1;OldBusy=0}
    'Réservation AD + hasard'=@{Random=5;Registry=0;ADReserve=1;OldBusy=0}
    'Registre + réservation AD'=@{Random=0;Registry=1;ADReserve=1;OldBusy=0}
    'Tout (registre, hasard, AD)'=@{Random=5;Registry=1;ADReserve=1;OldBusy=0}
}
if($OnlyModes){$keep=$OnlyModes -split ';';foreach($k in @($modes.Keys)){if($k -notin $keep){$modes.Remove($k)}}}
$rows=[Collections.Generic.List[object]]::new();$rng=[Random]::new()
foreach($profile in ($Profiles -split ',')){
    Say '';Say "== Profil : $profile ($(if($profile -eq 'Simultané'){'tous au même instant'}else{'départs étalés sur 6 s'}), clic 0,3 à 3 s après l'affichage)"
    foreach($mode in $modes.Keys){
        $m=$modes[$mode]
        foreach($round in 1..$Rounds){
            $prefix=Next-Prefix
            $root=''
            if($m.Registry){
                $root="$regBase\$prefix";[void][IO.Directory]::CreateDirectory("$regLocal\$prefix")
                [void](& $regWorker ([pscustomobject]@{Mode='Prepare';Root=$root;Domain=$Domain;Owner='banc';Station='BANC';User=$me;Minutes=15;Name='';Names=@();Context='';Credential=$null}))
            }
            $go=[DateTime]::UtcNow.AddSeconds(12).ToString('o')
            $specs=@(1..$Techs|ForEach-Object{
                $start=if($profile -eq 'Simultané'){0}else{$rng.Next(0,6000)}
                [ordered]@{Kind='Tour';Mode=$mode;Random=$m.Random;Registry=$m.Registry;ADReserve=$m.ADReserve;OldBusy=$m.OldBusy;Tech=$_;GoUtc=$go;StartMs=$start;ClickMs=(300+$rng.Next(0,2700));
                    Series=$prefix;OU=$OU;DC=$DC;Domain=$Domain;Root=$(if($root){$root}else{'aucun'});Wad=$Wad;Ledger="$ledger.$_";Out=(Join-Path $env:TEMP "tour-$runId-$prefix-$_.json")}
            })
            $res=Start-Techs $specs 300
            $acc=@(Get-Series $prefix)
            $finals=@($res|Where-Object{$_.Final}|ForEach-Object{[string]$_.Final})
            $firsts=@($res|ForEach-Object{[string]$_.First});$clicks=@($res|ForEach-Object{[string]$_.AtClick})
            $dupF=@($firsts|Where-Object{$_}|Group-Object|Where-Object{$_.Count -gt 1}).Count -gt 0
            $dupC=@($clicks|Where-Object{$_}|Group-Object|Where-Object{$_.Count -gt 1}).Count -gt 0
            $dupFinal=@($finals|Group-Object|Where-Object{$_.Count -gt 1}).Count
            $orph=@($acc|Where-Object{[string]$_.Name -notin $finals}).Count
            $errs=@($res|Where-Object{$_.Error})
            $row=[pscustomobject]@{Profile=$profile;Mode=$mode;Round=$round;Series=$prefix;
                First=($firsts|ForEach-Object{if($_){$_.Substring(12)}else{'---'}}) -join ' ';AtClick=($clicks|ForEach-Object{if($_){$_.Substring(12)}else{'---'}}) -join ' ';
                Final=(@($res|ForEach-Object{if($_.Final){([string]$_.Final).Substring(12)}else{'---'}}) -join ' ');
                DupFirst=$dupF;DupClick=$dupC;HeldBefore=(Sum $res 'HeldBefore');HeldDuring=(Sum $res 'HeldDuring');
                AutoSwitch=(Sum $res 'AutoSwitch');FailAfter=(Sum $res 'FailAfter');
                MaxConfirm=(Max $res 'Confirmations');DupFinal=$dupFinal;Accounts=$acc.Count;Orphans=$orph;
                Errors=$errs.Count;MeanMs=$(if($finals.Count){[int]((Sum @($res|Where-Object{$_.Final}) 'Ms')/$finals.Count)}else{0});Techs=$res}
            $rows.Add($row)
            Say ('{0,-28} tour {1} : affichés {2,-15} au clic {3,-15} ajoutés {4,-15} | bascules avant confirmation {5,2} | échecs après confirmation {6,2} | doublons {7} | orphelins {8}{9}' -f $mode,$round,$row.First,$row.AtClick,$row.Final,$row.AutoSwitch,$row.FailAfter,$row.DupFinal,$row.Orphans,$(if($errs.Count){' | ERREURS '+(($errs|ForEach-Object{"t$($_.Tech): $($_.Error)"}) -join ' ; ')}else{''}))
            $removed=Remove-BenchAccounts $prefix
            if(@(Get-Series $prefix).Count){Say "  ATTENTION : série $prefix non vide après nettoyage"}
            [IO.File]::WriteAllText($jsonPath,(@($rows)|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
        }
    }
}

# 3. Synthèse.
Say '';Say "== SYNTHÈSE ($Techs techniciens, $Rounds tours par réglage et par profil)"
Say ('{0,-12} {1,-28} {2,13} {3,13} {4,11} {5,11} {6,12} {7,11} {8,9} {9,9} {10,8}' -f 'profil','réglage','même nom aff.','même au clic','détenus av.','bascules','échecs ap.c.','confirm. max','doublons','orphelins','erreurs')
foreach($g in ($rows|Group-Object Profile,Mode)){
    $r=@($g.Group)
    Say ('{0,-12} {1,-28} {2,13} {3,13} {4,11} {5,11} {6,12} {7,11} {8,9} {9,9} {10,8}' -f $r[0].Profile,$r[0].Mode,("$(@($r|Where-Object DupFirst).Count)/$($r.Count)"),("$(@($r|Where-Object DupClick).Count)/$($r.Count)"),
        (Sum $r 'HeldBefore'),(Sum $r 'AutoSwitch'),(Sum $r 'FailAfter'),(Max $r 'MaxConfirm'),(Sum $r 'DupFinal'),(Sum $r 'Orphans'),(Sum $r 'Errors'))
}
$left=0;foreach($p in $script:usedPrefixes){$left+=@(Get-Series $p).Count}
Say '';Say "Comptes restants dans les $($script:usedPrefixes.Count) séries du banc après nettoyage : $left"
Say "Registre du banc : $regLocal (dossier de la VM, effacé avec l'instantané)."
