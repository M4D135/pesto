# Banc de collisions (08/10/2026, demande de David : « je veux voir les fois où il y a eu collision ou pas »).
# Par tour, plusieurs techniciens (PROCESSUS Windows séparés) demandent un nom au même instant, le confirment après un court
# délai, puis le créent dans un AD simulé (dossier partagé SMB, création exclusive : un nom ne peut être créé qu'une fois,
# comme sur un contrôleur de domaine). Réglages comparés, même état de départ (001 à 004 et 006 déjà pris) :
#   Sans protection    : premier numéro libre (comportement d'avant).
#   Hasard             : numéro tiré parmi les 5 premiers libres (POLICY.RandomNameChoice = 5).
#   Registre           : réservation dans le registre partagé (vrai worker de Pesto), noms des autres sautés.
#   Registre + hasard  : les deux.
param([string]$Wad='C:\PestoTest\wad',[string]$Root='\\localhost\C$\PestoCollisions',[int]$Techs=4,[int]$Rounds=8,[string]$Report='C:\PestoTest-preuves\collisions.json')
$ErrorActionPreference='Stop'
$local=$Root -replace '^\\\\localhost\\C\$','C:'
if(Test-Path $local){Remove-Item $local -Recurse -Force}
[void][IO.Directory]::CreateDirectory("$local\ad")
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Names.ps1'),[ref]$t,[ref]$e)
$a=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSharedNameWorker'},$true))
$registry=[scriptblock]::Create($a[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
[void](& $registry ([pscustomobject]@{Mode='Prepare';Root=(Join-Path $Root 'registre');Domain='LAB.LOCAL';Owner='banc';Station='BANC';User='banc';Minutes=15;Name='';Names=@();Context=''}))
$modes=[ordered]@{'Sans protection'='P123456PAAAA';'Hasard'='P123456PABBB';'Registre'='P123456PACCC';'Registre + hasard'='P123456PADDD'}
foreach($s in $modes.Values){foreach($n in 1,2,3,4,6){[IO.File]::WriteAllText("$local\ad\$s$('{0:D3}' -f $n)",'')}}
$techScript=Join-Path $PSScriptRoot 'collision-tech.ps1'
$rows=[Collections.Generic.List[object]]::new()
foreach($mode in $modes.Keys){
    foreach($round in 1..$Rounds){
        $go=[DateTime]::UtcNow.AddSeconds(3).ToString('o')
        $outs=@(1..$Techs|ForEach-Object{Join-Path $env:TEMP ("coll-$round-$_-"+[Guid]::NewGuid().ToString('N')+'.json')})
        $procs=@(1..$Techs|ForEach-Object{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$techScript,'-Mode',('"'+$mode+'"'),'-Round',$round,'-Tech',$_,'-GoUtc',$go,'-Root',$Root,'-Series',$modes[$mode],'-Out',$outs[$_-1],'-Wad',$Wad) -PassThru -WindowStyle Hidden})
        $procs|Wait-Process -Timeout 120
        $res=@($outs|ForEach-Object{if(Test-Path $_){Get-Content $_ -Raw|ConvertFrom-Json;Remove-Item $_}})
        $firsts=@($res|ForEach-Object{$_.First})
        $dup=@($firsts|Group-Object|Where-Object{$_.Count -gt 1}|ForEach-Object{$_.Name})
        $row=[pscustomobject]@{Mode=$mode;Round=$round;Proposes=($firsts|ForEach-Object{$_.Substring(12)}) -join ' ';Finals=(@($res|ForEach-Object{$_.Final.Substring(12)}) -join ' ');
            Collision=($dup.Count -gt 0);Doublons=($dup|ForEach-Object{$_.Substring(12)}) -join ' ';Essais=[int](@($res|Measure-Object Retries -Sum).Sum);Sautes=[int](@($res|Measure-Object HeldSkipped -Sum).Sum);Complet=($res.Count -eq $Techs)}
        $rows.Add($row)
        '{0,-18} tour {1,2} : proposés {2,-16} créés {3,-16} collision {4,-3} essais en plus {5}' -f $mode,$round,$row.Proposes,$row.Finals,$(if($row.Collision){'OUI'}else{'non'}),$row.Essais
    }
}
''
'SYNTHÈSE ({0} techniciens, {1} tours par réglage)' -f $Techs,$Rounds
foreach($mode in $modes.Keys){
    $r=@($rows|Where-Object{$_.Mode -eq $mode})
    '{0,-18} : tours avec collision {1}/{2} · essais supplémentaires {3} · noms réservés ailleurs sautés {4} · noms en double créés {5}' -f $mode,@($r|Where-Object{$_.Collision}).Count,$r.Count,[int](@($r|Measure-Object Essais -Sum).Sum),[int](@($r|Measure-Object Sautes -Sum).Sum),@($r|Where-Object{-not $_.Complet}).Count
}
$dups=@(Get-ChildItem "$local\ad").Count
[IO.File]::WriteAllText($Report,($rows|ConvertTo-Json -Depth 3),[Text.UTF8Encoding]::new($false))
Remove-Item $local -Recurse -Force
