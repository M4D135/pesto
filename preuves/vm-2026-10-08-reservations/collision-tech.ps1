# Un « technicien » du banc de collisions : propose un nom selon le réglage, confirme, crée le nom dans l'AD simulé.
param([string]$Mode,[int]$Round,[int]$Tech,[string]$GoUtc,[string]$Root,[string]$Series,[string]$Out,[string]$Wad)
$ErrorActionPreference='Stop'
function Import-Fn([string]$File,[string[]]$Names){$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);$sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-AvailableMachines'))))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Names.ps1'),[ref]$t,[ref]$e)
$a=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSharedNameWorker'},$true))
$registry=[scriptblock]::Create($a[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
$ad=Join-Path $Root 'ad'
$owner="tour$Round-tech$Tech-"+[Guid]::NewGuid().ToString('N').Substring(0,6)
$rng=[Random]::new([Environment]::TickCount+$Tech*7919+$Round*104729)
function Get-Free {
    $used=@([IO.Directory]::GetFiles($ad,$Series+'*')|ForEach-Object{[pscustomobject]@{Name=[IO.Path]::GetFileName($_)}})
    $list=Get-AvailableMachines -computers $used -baseName ($Series.Substring(0,7)) -site ($Series.Substring(7,2)) -equipe ($Series.Substring(9,3))
    return ,@($list)
}
function Reserve([string]$n){(& $registry ([pscustomobject]@{Mode='Reserve';Root=(Join-Path $Root 'registre');Domain='LAB.LOCAL';Owner=$owner;Station="POSTE-$Tech";User="tech$Tech";Minutes=15;Name=$n;Names=@();Context='Join'})).State}
function Release([string]$n){[void](& $registry ([pscustomobject]@{Mode='Release';Root=(Join-Path $Root 'registre');Domain='LAB.LOCAL';Owner=$owner;Station="POSTE-$Tech";User="tech$Tech";Minutes=15;Name='';Names=@($n);Context='Join'}))}
function Propose {
    $free=Get-Free
    $start=if($Mode -in @('Hasard','Registre + hasard')){$rng.Next(0,[Math]::Min(5,$free.Count))}else{0}
    if($Mode -in @('Registre','Registre + hasard')){
        for($i=0;$i -lt $free.Count;$i++){$n=$free[($start+$i)%$free.Count];$s=Reserve $n;if($s -in @('Reserved','Renewed')){return $n};$script:held++}
        throw 'Aucun nom réservable.'
    }
    return $free[$start]
}
while([DateTime]::UtcNow -lt [DateTime]::Parse($GoUtc).ToUniversalTime()){Start-Sleep -Milliseconds 2}
$script:held=0;$retries=0;$first=$null;$final=$null;$clock=[Diagnostics.Stopwatch]::StartNew()
while(-not $final){
    $name=Propose
    if(-not $first){$first=$name}
    Start-Sleep -Milliseconds (200+$rng.Next(0,400))   # le technicien relit et confirme
    try{$s=[IO.File]::Open((Join-Path $ad $name),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$s.Dispose();$final=$name}
    catch{if(-not [IO.File]::Exists((Join-Path $ad $name))){throw};$retries++}   # nom pris entre-temps : Pesto propose le suivant
    if($Mode -in @('Registre','Registre + hasard')){Release $name}
    if($retries -gt 20){throw 'Trop d''essais.'}
}
[IO.File]::WriteAllText($Out,([pscustomobject]@{Mode=$Mode;Round=$Round;Tech=$Tech;First=$first;Final=$final;Retries=$retries;HeldSkipped=$script:held;Ms=$clock.ElapsedMilliseconds}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
