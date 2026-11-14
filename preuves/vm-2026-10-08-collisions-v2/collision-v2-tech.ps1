# Banc de collisions v2 (08/10/2026) : un « technicien » du parcours « Ajouter au domaine », lancé par collisions-v2.ps1.
# Vrai code de Pesto (fonctions et workers extraits des fichiers livrés), vrai AD du labo (DC01) sous l'identité de la session
# (LABO\tech.pesto, Kerberos, aucun mot de passe). Chaque appel AD ou registre passe par un runspace neuf, comme les
# opérations en arrière-plan de Pesto (le module AD y est rechargé à chaque fois).
# Reproduit ici (pas de fenêtre) : la sélection du nom (garder le nom affiché s'il reste libre, sinon tirage par
# Get-PestoInitialNameIndex), la minuterie de 1 s du registre (réservation après 900 ms de stabilité), l'enchaînement
# contrôle -> réservation AD -> confirmation -> exécution, et la jonction elle-même : création du compte dans l'OU (ce que
# fait Add-Computer), précédée des relectures AD et du verrou du registre comme dans le worker de jonction.
param([string]$Kind='Tour',[string]$Mode,[int]$Random,[int]$Registry,[int]$ADReserve,[int]$OldBusy,[int]$Tech,[string]$GoUtc,
      [int]$StartMs,[int]$ClickMs,[string]$Series,[string]$Name,[string]$OU,[string]$DC,[string]$Domain,[string]$Root,
      [string]$Out,[string]$Wad,[string]$Ledger)
$ErrorActionPreference='Stop'
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    if(@($e).Count){throw "Syntaxe $File : $($e[0].Message)"}
    $sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    $sb.ToString()
}
function Import-Worker([string]$File,[string]$Var){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $a=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq $Var},$true))
    if(-not $a.Count){throw "Worker absent : $Var"}
    $a[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('Assert-PestoClosedObject','Test-PestoPropertyPresent','ConvertTo-PestoNameParts','New-PestoComputerName','Get-PestoStableHash'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-AvailableMachines'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy','Add-PestoShareConnection','Connect-PestoCoordinationShare','Get-PestoCoordinationRoot','Get-PestoCoordinationKeys','Enter-PestoCoordination'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Names.ps1' @('Get-PestoSharedNameSettings','Test-PestoNameReservedByOther','Get-PestoInitialNameIndex'))))
$regWorker=Import-Worker 'Pesto-Names.ps1' '$script:PestoSharedNameWorker'
$adWorker=Import-Worker 'Pesto-Join.ps1' '$script:PestoJoinADReserveWorker'
$loader=Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath','Import-PestoADModule')
$modPath=Join-Path $Wad 'ActiveDirectory.psd1'
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name;$station="POSTE-$Tech";$owner=[Guid]::NewGuid().ToString('N')
$script:GUI=$false;$script:SIM=$false;$script:cred=$null

function Invoke-Fresh([string]$Body,$Arg){
    # Runspace neuf, comme Start-PestoAsyncOperation ; une erreur du worker remonte en exception.
    $ps=[PowerShell]::Create()
    try{[void]$ps.AddScript($Body).AddArgument($Arg);foreach($o in $ps.Invoke()){$o}}finally{$ps.Dispose()}   # résultats énumérés : @(...) côté appelant
}
$adReadBody='param($a) . ([scriptblock]::Create($a.Loader)); Import-PestoADModule -ADModulePath $a.ModPath; @(Get-ADComputer -LDAPFilter $a.Filter -Server $a.DC|ForEach-Object{[string]$_.Name})'
$adCreateBody=@'
param($a)
. ([scriptblock]::Create($a.Loader)); Import-PestoADModule -ADModulePath $a.ModPath
try{New-ADComputer -Name $a.Name -SamAccountName ($a.Name+'$') -Path $a.OU -Enabled $true -Description $a.Desc -Server $a.DC}
catch{$t=[string]$_.Exception.Message;if($_.Exception.GetType().Name -eq 'ADIdentityAlreadyExistsException' -or $t -match 'already (exists|in use)|existe déjà|déjà utilisé'){return [pscustomobject]@{State='Taken';Message=$t}};throw}
$o=Get-ADComputer -Identity ($a.Name+'$') -Server $a.DC
[pscustomobject]@{State='Created';Guid=([Guid]$o.ObjectGUID).ToString('D')}
'@
function Read-AD([string]$Filter){Invoke-Fresh $adReadBody ([pscustomobject]@{Loader=$loader;ModPath=$modPath;Filter=$Filter;DC=$DC})}
function Reserve-AD([string]$N){@(Invoke-Fresh $adWorker ([pscustomobject]@{Mode='Reserve';Name=$N;OU=$OU;DC=$DC;Credential=$null;User=$user;Station=$station;ADLoaderSource=$loader;ADModulePath=$modPath}))[-1]}
function Note-Ledger([string]$N,[string]$G,[string]$K){Add-Content -LiteralPath $Ledger -Value (([pscustomobject]@{Name=$N;Guid=$G;Tech=$Tech;Kind=$K})|ConvertTo-Json -Compress) -Encoding UTF8}
function Wait-Go{$go=[DateTime]::Parse($GoUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal').AddMilliseconds($StartMs);while([DateTime]::UtcNow -lt $go){Start-Sleep -Milliseconds 2}}

if($Kind -eq 'MicroAD'){
    # Arbitre AD seul : même nom réservé par plusieurs processus à la même milliseconde (vrai worker de Pesto).
    [void](Read-AD '(name=PESTO-AUCUN-NOM)')   # préchauffe ce processus ; le worker charge son module dans son runspace
    Wait-Go
    $r=$null;$err=''
    try{$r=Reserve-AD $Name}catch{$err=$_.Exception.Message}
    if($r -and $r.Guid){Note-Ledger $Name ([string]$r.Guid) 'micro'}
    [IO.File]::WriteAllText($Out,([pscustomobject]@{Tech=$Tech;State=[string]$r.State;Guid=[string]$r.Guid;Error=$err}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    return
}

$pol=[ordered]@{Schema=1;RandomNameChoice=$Random;ReserveNamesInAD=[bool]$ADReserve}
if($Registry){$pol['CoordinationRoot']=$Root}
$script:CFG=[pscustomobject]@{POLICY=[pscustomobject]$pol}
$policy=ConvertTo-PestoPolicy $script:CFG.POLICY
$set=Get-PestoSharedNameSettings
if($set.Random -ne $Random -or [bool]$set.ReserveInAD -ne [bool]$ADReserve -or ([bool]$set.Root) -ne [bool]$Registry){throw 'Politique du banc non appliquée par Pesto.'}
$rng=[Random]::new([BitConverter]::ToInt32([Guid]::NewGuid().ToByteArray(),0))
$events=[Collections.Generic.List[object]]::new();$taken=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:SharedNameOthers=@{};$inv=@();$mine=$null
$clock=$null
function Ev([string]$K,[string]$N,[string]$D=''){$events.Add([pscustomobject]@{T=[int]$clock.ElapsedMilliseconds;K=$K;N=$N;D=$D})}
function Select-Name([string]$Keep){
    # Update-PestoJoinNames : candidats (inventaire et noms pris écartés, noms réservés ailleurs écartés), nom affiché gardé
    # s'il reste candidat, sinon Get-PestoInitialNameIndex.
    $known=@(@($inv)+@($taken)|ForEach-Object{[pscustomobject]@{Name=[string]$_}})
    $all=Get-AvailableMachines -computers $known -baseName $Series.Substring(0,7) -site $Series.Substring(7,2) -equipe $Series.Substring(9,3)   # rend ,@(...) : un seul objet tableau
    $list=@($all|Where-Object{-not (Test-PestoNameReservedByOther $_)})
    if($Keep -and $list -contains $Keep){return $Keep}
    if(-not $list.Count){throw 'Aucun nom libre.'}
    return [string]$list[(Get-PestoInitialNameIndex -Count $list.Count)]
}
function Invoke-Registry([string]$M,[string]$N){
    $r=@(Invoke-Fresh $regWorker ([pscustomobject]@{Mode=$M;Root=$Root;Domain=$Domain;Owner=$owner;Station=$station;User=$user;Minutes=15;Name=$N;Names=@($N);Context='Join';Credential=$null}))[-1]
    if($M -eq 'Snapshot'){$map=@{};foreach($o in @($r.Others)){$map[[string]$o.Name]=$o};$script:SharedNameOthers=$map}
    if($M -eq 'Reserve' -and $r.State -eq 'Held'){$script:SharedNameOthers[$N.ToUpperInvariant()]=[pscustomobject]@{Name=$N;Station=[string]$r.Holder;ExpiresUtc=[string]$r.HolderExpiresUtc}}
    return $r
}
function Read-Series{foreach($n in @(Read-AD "(name=$Series*)")){[void]$taken.Add([string]$n)}}

$res=[ordered]@{Mode=$Mode;Tech=$Tech;StartMs=$StartMs;ClickMs=$ClickMs;First='';AtClick='';Displays=@();HeldBefore=0;HeldDuring=0;
    AutoSwitch=0;Confirmations=0;FailAfter=0;FailCodes=@();Final='';Guid='';Ms=0;Error='';Events=$null}
$displays=[Collections.Generic.List[string]]::new();$fails=[Collections.Generic.List[string]]::new()
try{
    Wait-Go
    $clock=[Diagnostics.Stopwatch]::StartNew()
    # 1. Ouverture : recherche ciblée du site (inventaire de la série), premier relevé du registre (premier tick).
    $inv=@(Read-AD "(name=$Series*)")
    if($Registry){[void](Invoke-Registry 'Snapshot' '')}
    $current=Select-Name '';$res.First=$current;$displays.Add($current);Ev 'affiché' $current
    # 2. Avant le clic : minuterie de 1 s du registre (nom vu, puis réservé après 900 ms de stabilité).
    $shown=$clock.ElapsedMilliseconds;$clickAt=$shown+$ClickMs;$seen=$null;$nextTick=$shown+1000
    while($clock.ElapsedMilliseconds -lt $clickAt){
        $wait=[Math]::Min($nextTick,$clickAt)-$clock.ElapsedMilliseconds;if($wait -gt 0){Start-Sleep -Milliseconds $wait}
        if($clock.ElapsedMilliseconds -lt $nextTick){break};$nextTick+=1000
        if(-not $Registry){continue}
        if(Test-PestoNameReservedByOther $current){$current=Select-Name $current;$displays.Add($current);Ev 'autre nom affiché' $current;$seen=$null;continue}
        if(-not $seen -or $seen.N -ne $current){$seen=[pscustomobject]@{N=$current;T=$clock.ElapsedMilliseconds};continue}
        if($clock.ElapsedMilliseconds-$seen.T -lt 900 -or $mine -eq $current){continue}
        $r=Invoke-Registry 'Reserve' $current
        if($r.State -in @('Reserved','Renewed')){$mine=$current;Ev 'réservé registre' $current}
        elseif($r.State -eq 'Held'){$res.HeldBefore++;Ev 'détenu ailleurs' $current $r.Holder;$current=Select-Name $current;$displays.Add($current);Ev 'autre nom affiché' $current;$seen=$null}
    }
    $res.AtClick=$current;Ev 'clic' $current
    # 3. Traitement : contrôle, réservation AD, confirmation, exécution (le nom peut changer sans le technicien).
    $autoNext=0
    while(-not $res.Final){
        if($Registry -and -not $OldBusy -and $mine -ne $current -and -not (Test-PestoNameReservedByOther $current)){
            # Correctif du 08/10 : le registre réserve aussi pendant le traitement.
            $r=Invoke-Registry 'Reserve' $current
            if($r.State -in @('Reserved','Renewed')){$mine=$current;Ev 'réservé registre (traitement)' $current}else{$res.HeldDuring++;Ev 'détenu ailleurs (traitement)' $current $r.Holder}
        }
        # Contrôle (lecture AD) ; nom pris : série relue, nom suivant, nouveau contrôle automatique (5 bascules au plus).
        if(@(Read-AD "(sAMAccountName=$current`$)").Count){
            [void]$taken.Add($current);Read-Series;$autoNext++;$res.AutoSwitch++;Ev 'pris au contrôle' $current
            if($autoNext -gt 5){throw 'Cinq noms de suite pris : abandon.'}
            $current=Select-Name '';$displays.Add($current);Ev 'nom suivant' $current;continue
        }
        $autoNext=0
        if($Registry -and -not $OldBusy -and (Test-PestoNameReservedByOther $current)){
            # Correctif du 08/10 : « détenu ailleurs » reçu pendant le contrôle -> nom suivant avant toute confirmation.
            $autoNext++;$res.AutoSwitch++;Ev 'détenu au registre : nom suivant' $current   # -RegistryHeld : écarté tant que réservé, pas pour la session
            $current=Select-Name '';$displays.Add($current);Ev 'nom suivant' $current;continue
        }
        if($ADReserve){
            $r=Reserve-AD $current
            if($r.State -eq 'Taken'){
                [void]$taken.Add($current);$autoNext++;$res.AutoSwitch++;Ev 'pris à la réservation AD' $current
                if($autoNext -gt 5){throw 'Cinq noms de suite pris : abandon.'}
                $current=Select-Name '';$displays.Add($current);Ev 'nom suivant' $current;continue
            }
            if($r.State -ne 'Reserved' -or -not $r.Guid){throw "Réservation AD incomplète : $($r.State)"}
            Note-Ledger $current ([string]$r.Guid) 'réservation';$res.Guid=[string]$r.Guid;Ev 'réservé AD' $current
            [void](Read-AD "(sAMAccountName=$current`$)")   # contrôle complet sur le compte réservé (Start-PestoJoinCheck -Auto)
        }
        # Confirmation : le technicien lit le récapitulatif.
        $res.Confirmations++;$read=1500+$rng.Next(0,2500);Ev 'confirmation' $current "$read ms";Start-Sleep -Milliseconds $read
        if($ADReserve){$res.Final=$current;Ev 'ajouté (compte réservé)' $current;break}
        # Exécution sans réservation AD : préalable (96), verrou du registre, relecture (13), création du compte (Add-Computer).
        $code=''
        if(@(Read-AD "(sAMAccountName=$current`$)").Count){$code='96 préalable : nom pris'}
        if(-not $code -and $Registry){
            $plan=[pscustomobject]@{Nom_du_PC="BANC-$Tech";Nouveau_Nom=$current;Objet_GUID='';Domain=$Domain}
            try{[void](Enter-PestoCoordination -Plan $plan -OperationId ([Guid]::NewGuid().ToString('N')) -Policy $policy)}catch{$code='96 verrou : '+$_.Exception.Message}
        }
        if(-not $code -and @(Read-AD "(sAMAccountName=$current`$)").Count){$code='13 relecture : nom pris'}
        if(-not $code){
            $c=@(Invoke-Fresh $adCreateBody ([pscustomobject]@{Loader=$loader;ModPath=$modPath;Name=$current;OU=$OU;DC=$DC;Desc="Banc collisions Pesto 08/10 (jonction simulée) $station"}))[-1]
            if($c.State -eq 'Created'){Note-Ledger $current ([string]$c.Guid) 'jonction';$res.Guid=[string]$c.Guid;$res.Final=$current;Ev 'ajouté' $current;break}
            $code='11 jonction : compte déjà existant'
        }
        # Échec après confirmation : Pesto propose un autre nom, revérifié, et redemande la confirmation.
        $res.FailAfter++;$fails.Add($code);Ev 'échec après confirmation' $current $code
        [void]$taken.Add($current);Read-Series;$current=Select-Name '';$displays.Add($current);Ev 'nom suivant' $current
    }
}catch{$res.Error=$_.Exception.Message;if($clock){Ev 'erreur' '' $res.Error}}
$res.Ms=if($clock){[int]$clock.ElapsedMilliseconds}else{0};$res.Displays=$displays.ToArray();$res.FailCodes=$fails.ToArray();$res.Events=$events.ToArray()
[IO.File]::WriteAllText($Out,([pscustomobject]$res|ConvertTo-Json -Compress -Depth 4),[Text.UTF8Encoding]::new($false))
