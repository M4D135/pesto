#requires -Version 5.1
# Règles pures : aucune lecture réseau, écriture disque ou dépendance WPF au chargement.

function Assert-PestoClosedObject {
    param([Parameter(Mandatory=$true)]$Value,[Parameter(Mandatory=$true)][string[]]$Allowed,[string[]]$Required=@())
    if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){throw 'Objet structuré attendu.'}
    $names=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    foreach($key in $names){if($key -cnotin $Allowed){throw ('Champ non autorisé : '+$key)}}
    foreach($key in $Required){if($key -cnotin $names){throw ('Champ obligatoire absent : '+$key)}}
}

function Get-PestoDefaultNamingConvention {
    <# Format livré par défaut, celui de tous les cfg.json existants : type P/S/V, préfixe 6 chiffres,
       site 2 lettres, service 3 alphanumériques, numéro 3 chiffres, soit 15 caractères (plafond NetBIOS). #>
    return [pscustomobject]@{Schema=1;Id='defaut';Tokens=@('Type','Prefix','Site','Service','Number');
        Widths=@{Prefix=6;Site=2;Service=3;Number=3};Types='PSV'}
}

function Get-PestoNamingResolutionNonce {
    <# Les analyses de nom tournent des centaines de milliers de fois dans les vues de noms. Une
       convention déjà résolue n'est donc revalidée qu'une fois par porteur, reconnu à ce jeton tiré
       au hasard à chaque chargement : un cfg.json ne peut pas le connaître, donc jamais une
       convention non vérifiée ne franchit la porte. #>
    if(-not $script:PestoNamingResolutionNonce){$script:PestoNamingResolutionNonce=[Guid]::NewGuid().ToString('N')}
    return $script:PestoNamingResolutionNonce
}

function Assert-PestoNamingConvention {
    <# Convention administrable mais fermée : les cinq facettes doivent rester présentes et chaque
       jeton a une largeur fixe, donc la position de chacun se déduit du début du nom et l'analyse
       inverse n'admet jamais deux lectures. Le numéro n'est pas obligé d'être en fin de nom. #>
    param($Convention)
    if($null -eq $Convention){return Get-PestoDefaultNamingConvention}
    $nonce=Get-PestoNamingResolutionNonce
    if($Convention -is [pscustomobject] -and $Convention.PSObject.Properties['PestoResolution'] -and
       ([string]$Convention.PestoResolution) -ceq $nonce){return $Convention}
    Assert-PestoClosedObject $Convention @('Schema','Id','Tokens','Widths','Types') @('Schema','Id','Tokens','Widths','Types')
    if(($Convention.Schema -isnot [int] -and $Convention.Schema -isnot [long]) -or $Convention.Schema -ne 1){throw 'Schéma de convention de nommage invalide.'}
    if([string]$Convention.Id -notmatch '^[a-z0-9][a-z0-9._-]{0,31}$'){throw 'Identifiant de convention invalide : minuscules, chiffres, point, tiret et tiret bas, 32 caractères maximum.'}
    $tokens=@($Convention.Tokens)
    $expected=@('Type','Prefix','Site','Service','Number')
    if($tokens.Count -ne $expected.Count){throw 'La convention doit aligner exactement les jetons Type, Prefix, Site, Service et Number.'}
    foreach($token in $expected){if(@($tokens|Where-Object{$_ -ceq $token}).Count -ne 1){throw ('Jeton de nommage attendu exactement une fois : '+$token)}}
    $types=[string]$Convention.Types
    if($types -notmatch '^[PSV]{1,3}$' -or (@($types.ToCharArray()|Sort-Object -Unique).Count -ne $types.Length)){throw 'Types invalides : sous-ensemble sans doublon de P, S et V.'}
    $widths=$Convention.Widths
    $keys=if($widths -is [Collections.IDictionary]){@([string[]]@($widths.Keys))}else{@([string[]]@($widths.PSObject.Properties.Name))}
    foreach($key in @('Prefix','Site','Service','Number')){if($key -cnotin $keys){throw ('Largeur absente dans la convention : '+$key)}}
    foreach($key in $keys){if($key -notin @('Prefix','Site','Service','Number')){throw ('Largeur inconnue dans la convention : '+$key)}}
    $floor=@{Prefix=1;Site=1;Service=1;Number=1};$ceiling=@{Prefix=12;Site=4;Service=6;Number=6}
    $resolved=@{}
    foreach($key in @('Prefix','Site','Service','Number')){
        $value=if($widths -is [Collections.IDictionary]){$widths[$key]}else{$widths.$key}
        if(($value -isnot [int] -and $value -isnot [long]) -or $value -lt $floor[$key] -or $value -gt $ceiling[$key]){
            throw ('Largeur hors bornes pour '+$key+' : '+$floor[$key]+' à '+$ceiling[$key]+' caractères.')}
        $resolved[$key]=[int]$value
    }
    $total=1+$resolved['Prefix']+$resolved['Site']+$resolved['Service']+$resolved['Number']
    if($total -gt 15){throw ('Convention de '+$total+' caractères : un nom d''ordinateur Windows est plafonné à 15. Réduisez une largeur.')}
    return [pscustomobject]@{Schema=1;Id=[string]$Convention.Id;Tokens=$tokens;Widths=$resolved;Types=$types;
        PestoResolution=$nonce}
}

function Set-PestoActiveNamingConvention {
    <# Point unique où la convention du cfg.json devient celle du moteur. Une configuration
       sans NamingConvention garde le format historique : aucun cfg.json existant ne change de sens. #>
    param($Convention)
    $resolved=Assert-PestoNamingConvention $Convention
    $script:PestoNamingConvention=$resolved
    $script:NameInventoryIndex=$null;$script:NameInventorySource=$null;$script:NmUsedSrc=$null;$script:NmUsedIndex=$null
    return $resolved
}

function Get-PestoActiveNamingConvention {
    <# La convention livrée est déjà résolue et mémorisée au premier appel : les vues de noms
       interrogent cette fonction des milliers de fois et ne doivent pas revalider à chaque nom. #>
    $current=$null
    try{$current=$script:PestoNamingConvention}catch{$current=$null}
    if($null -eq $current){$current=Assert-PestoNamingConvention (Get-PestoDefaultNamingConvention);$script:PestoNamingConvention=$current}
    return $current
}

function Get-PestoNamingLayout {
    <# Positions et bornes déduites de la convention active. Les consommateurs lisent ces valeurs
       au lieu de compter les caractères : c'est ce qui rend une convention administrable sûre. #>
    param($Convention)
    $resolved=Assert-PestoNamingConvention $(if($null -eq $Convention){Get-PestoActiveNamingConvention}else{$Convention})
    $key=[string]$resolved.Id+'|'+(@($resolved.Tokens) -join ',')+'|'+$resolved.Widths['Prefix']+'/'+$resolved.Widths['Site']+'/'+
        $resolved.Widths['Service']+'/'+$resolved.Widths['Number']+'|'+$resolved.Types
    if($script:PestoNamingLayouts -and $script:PestoNamingLayouts.ContainsKey($key)){return $script:PestoNamingLayouts[$key]}
    $classes=@{Type='Type';Prefix='Digits';Site='Letters';Service='Alphanumeric';Number='Digits'}
    $atoms=@{Type='['+$resolved.Types+']';Prefix='[0-9]';Site='[A-Z]';Service='[A-Z0-9]';Number='[0-9]'}
    $offsets=@{};$cursor=0;$pattern='^';$series='^'
    foreach($token in $resolved.Tokens){
        $width=if($token -ceq 'Type'){1}else{$resolved.Widths[$token]}
        $offsets[$token]=$cursor
        $pattern+=('(?<{0}>{1}{{{2}}})' -f $token,$atoms[$token],$width)
        $series+=($(if($token -ceq 'Number'){'#{'+$width+'}'}else{$atoms[$token]+'{'+$width+'}'}))
        $cursor+=$width
    }
    $numberWidth=$resolved.Widths['Number']
    $layout=[pscustomobject]@{Convention=$resolved;Classes=$classes;Offsets=$offsets;Length=$cursor;
        NumberOffset=$offsets['Number'];NumberWidth=$numberWidth;BaseLength=$cursor-$numberWidth;
        MaximumNumber=[int][Math]::Pow(10,$numberWidth)-1;Pattern=($pattern+'$');SeriesPattern=($series+'$')}
    if(-not $script:PestoNamingLayouts){$script:PestoNamingLayouts=@{}}
    $script:PestoNamingLayouts[$key]=$layout
    return $layout
}

function Get-PestoNameLength { param($Convention);return (Get-PestoNamingLayout $Convention).Length }
function Get-PestoNameMaximumNumber { param($Convention);return (Get-PestoNamingLayout $Convention).MaximumNumber }

function ConvertTo-PestoNameParts {
    <# Analyse inverse selon la convention active : chaque facette est lue à la position que lui donne
       la largeur configurée, jamais à un offset fixe. -CurrentName admet le numéro historique 000 en
       lecture ; la génération ne produit que des numéros de 1 à MaximumNumber. #>
    param([AllowNull()][string]$Name,[string]$Prefix='',[switch]$CurrentName,$Convention)
    if([string]::IsNullOrWhiteSpace($Name)){return $null}
    $layout=Get-PestoNamingLayout $Convention
    $value=$Name.Trim().ToUpperInvariant()
    if($value.Length -ne $layout.Length){return $null}
    $m=[regex]::Match($value,$layout.Pattern)
    if(-not $m.Success){return $null}
    $number=[int]$m.Groups['Number'].Value
    if(($number -lt 1 -and -not $CurrentName) -or ($Prefix -and $m.Groups['Prefix'].Value -cne $Prefix)){return $null}
    $type=$m.Groups['Type'].Value
    return [pscustomobject]@{Name=$m.Value;Type=$type;Prefix=$m.Groups['Prefix'].Value;
        Site=$m.Groups['Site'].Value;Service=$m.Groups['Service'].Value;Number=$number;
        NumberText=$m.Groups['Number'].Value;
        Base=$value.Remove($layout.NumberOffset,$layout.NumberWidth);
        Series=$value.Remove($layout.NumberOffset,$layout.NumberWidth).Insert($layout.NumberOffset,('#'*[int]$layout.NumberWidth));
        Label=$(if($type -ceq 'P'){'Portable'}elseif($type -ceq 'S'){'Fixe'}else{'Virtuel'})}
}

function New-PestoComputerName {
    <# Génération : un seul chemin, celui de la convention active. Les jetons sont posés dans l'ordre
       configuré, ce qui autorise un numéro ailleurs qu'en fin de nom. #>
    param([string]$Type,[string]$Prefix,[string]$Site,[string]$Service,[int]$Number,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    $resolved=$layout.Convention
    if($Type -notmatch ('^['+$resolved.Types+']$')){throw 'Convention de nommage invalide.'}
    if($Prefix -notmatch ('^[0-9]{'+$resolved.Widths['Prefix']+'}$') -or
       $Site -notmatch ('^[A-Za-z]{'+$resolved.Widths['Site']+'}$') -or
       $Service -notmatch ('^[A-Za-z0-9]{'+$resolved.Widths['Service']+'}$') -or
       $Number -lt 1 -or $Number -gt $layout.MaximumNumber){throw 'Convention de nommage invalide.'}
    $builder=[Text.StringBuilder]::new()
    foreach($token in $resolved.Tokens){
        if($token -ceq 'Type'){[void]$builder.Append($Type.ToUpperInvariant())}
        elseif($token -ceq 'Prefix'){[void]$builder.Append($Prefix)}
        elseif($token -ceq 'Site'){[void]$builder.Append($Site.ToUpperInvariant())}
        elseif($token -ceq 'Service'){[void]$builder.Append($Service.ToUpperInvariant())}
        else{[void]$builder.Append($Number.ToString('D'+[int]$layout.NumberWidth))}
    }
    return $builder.ToString()
}

function New-PestoNameSeries {
    <# Série (nom sans son numéro) construite facettes par facettes, dans l'ordre configuré.
       Remplace les « $type$prefixe$site$service » concaténés à la main, qui imposaient le
       numéro en fin de nom et une base de 12 caractères. #>
    param([string]$Type,[string]$Prefix,[string]$Site,[string]$Service,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    $resolved=$layout.Convention
    if($Type -notmatch ('^['+$resolved.Types+']$') -or
       $Prefix -notmatch ('^[0-9]{'+$resolved.Widths['Prefix']+'}$') -or
       $Site -notmatch ('^[A-Za-z]{'+$resolved.Widths['Site']+'}$') -or
       $Service -notmatch ('^[A-Za-z0-9]{'+$resolved.Widths['Service']+'}$')){throw 'Convention de nommage invalide.'}
    $builder=[Text.StringBuilder]::new()
    foreach($token in $resolved.Tokens){
        if($token -ceq 'Number'){continue}
        elseif($token -ceq 'Type'){[void]$builder.Append($Type.ToUpperInvariant())}
        elseif($token -ceq 'Prefix'){[void]$builder.Append($Prefix)}
        elseif($token -ceq 'Site'){[void]$builder.Append($Site.ToUpperInvariant())}
        else{[void]$builder.Append($Service.ToUpperInvariant())}
    }
    return $builder.ToString()
}

function Format-PestoNameNumber {
    <# Écriture du numéro selon la largeur configurée : le seul endroit où le remplissage est décidé. #>
    param([int]$Number,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    if($Number -lt 0 -or $Number -gt $layout.MaximumNumber){throw 'Numéro hors plage pour la convention de nommage active.'}
    return $Number.ToString('D'+[int]$layout.NumberWidth)
}

function New-PestoNameFromSeries {
    <# Reconstruit un nom complet depuis une série et un numéro : remplace les
       « base + numéro » concaténés à la main, qui supposaient le numéro en fin de nom. #>
    param([AllowNull()][string]$Base,[AllowNull()][int]$Number,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    if([string]::IsNullOrWhiteSpace($Base) -or $Base.Length -ne $layout.BaseLength){throw 'Série de noms invalide.'}
    if($Number -lt 1 -or $Number -gt $layout.MaximumNumber){throw 'Numéro hors plage pour la convention de nommage active.'}
    $offset=[int]$layout.NumberOffset
    return $Base.Substring(0,$offset)+$Number.ToString('D'+[int]$layout.NumberWidth)+$Base.Substring($offset)
}

function Get-PestoNameSeriesBase {
    <# Série d'un nom complet : les caractères du numéro retirés, dans l'ordre configuré. #>
    param([AllowNull()][string]$Name,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -ne $layout.Length){return ''}
    $value=$Name.ToUpperInvariant()
    return $value.Remove([int]$layout.NumberOffset,[int]$layout.NumberWidth)
}

function Get-PestoNameNumber {
    <# Numéro d'un nom complet, -1 quand le nom n'est pas de la convention. #>
    param([AllowNull()][string]$Name,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -ne $layout.Length){return -1}
    $number=0
    if([int]::TryParse($Name.Substring([int]$layout.NumberOffset,[int]$layout.NumberWidth),[ref]$number) -and $number -ge 0 -and $number -le $layout.MaximumNumber){return $number}
    return -1
}

function Test-PestoNameSeries {
    param([AllowNull()][string]$Base,$Convention)
    $layout=Get-PestoNamingLayout $Convention
    if([string]::IsNullOrWhiteSpace($Base) -or $Base.Length -ne $layout.BaseLength){return $false}
    try{return [bool](ConvertTo-PestoNameParts -Name (New-PestoNameFromSeries -Base $Base -Number 1 -Convention $layout.Convention) -Convention $layout.Convention)}catch{return $false}
}

function Get-PestoNamingFunctionNames {
    <# Une seule liste pour tous les workers : une source embarquée qui oublierait une dépendance
       casserait le parsing de noms à distance, pas seulement l'affichage local. #>
    return @('Get-PestoNamingResolutionNonce','Get-PestoDefaultNamingConvention','Assert-PestoNamingConvention',
        'Set-PestoActiveNamingConvention','Get-PestoActiveNamingConvention','Get-PestoNamingLayout',
        'Get-PestoNameLength','Get-PestoNameMaximumNumber','ConvertTo-PestoNameParts','New-PestoComputerName',
        'New-PestoNameSeries','Format-PestoNameNumber','New-PestoNameFromSeries','Get-PestoNameSeriesBase',
        'Get-PestoNameNumber','Test-PestoNameSeries','Get-PestoNamingFunctionNames','Get-PestoFacetPattern','New-PestoNameLdapPattern')
}

function Get-PestoOutcome {
    param($Code,[bool]$Committed=$false,[bool]$PartialEffect=$false,[bool]$TimedOut=$false)
    if($Code -isnot [int] -or $TimedOut){return 'Uncertain'}
    if($Code -eq 96){if($Committed -or $PartialEffect){return 'Uncertain'};return 'NotStarted'}
    if($Code -in @(32,97,98,99)){return 'Uncertain'}
    if($Code -eq 89 -or ($PartialEffect -and $Code -notin @(10,20,30,33,77))){return 'Partial'}
    if($Code -in @(10,20,77)){return 'PendingRestart'}
    if($Code -in @(30,33)){return 'Verified'}
    if($Code -eq 40){return 'RestartRequested'}
    # Un entier inconnu n'est jamais assimilé à un refus certain de Windows.
    if($Code -in @(11,13,21,31,41,69,88)){return 'Refused'}
    return 'Uncertain'
}

function Get-PestoStatePresentation {
    param([string]$State,$Code=$null)
    # Les codes restent techniques ; les libellés et prochaines actions sont communs aux vues.
    $known=@{
        NotStarted=@('○ Non lancé','Aucune écriture engagée. Corrigez le contrôle puis préparez à nouveau.','neutral')
        Failed=@('⛔ Refus confirmé','Corrigez la cause indiquée avant de préparer une nouvelle opération.','error')
        Refused=@('⛔ Refus confirmé','Corrigez la cause indiquée avant de préparer une nouvelle opération.','error')
        Running=@('◷ Issue à vérifier','Relisez le reçu et l''état du poste. Une opération peut encore travailler.','warning')
        PendingRestart=@('↻ Redémarrage puis contrôle','Redémarrez si nécessaire, puis vérifiez l''état du poste avant toute reprise.','warning')
        AcceptedOptional=@('↻ Commande acceptée · contrôle facultatif','Redémarrez si nécessaire avant une nouvelle modification de ce poste. Le reçu est conservé ; consigner une vérification reste facultatif.','neutral')
        RestartRequested=@('↻ Redémarrage demandé','Attendez le retour du poste puis vérifiez son état.','warning')
        Partial=@('△ Effet partiel','Vérifiez les effets acquis ; reprenez uniquement l''étape restante proposée.','warning')
        MoveReady=@('→ Déplacement à préparer','Le renommage est confirmé. Préparez et confirmez le déplacement restant.','warning')
        Uncertain=@('? Résultat incertain','Vérifiez l''état du poste et les tâches avant toute reprise. Aucun succès supposé.','warning')
        Verified=@('✓ Windows / AD vérifié','Contrôlez séparément l''inscription Entra si elle est concernée.','success')
        Protection=@('! Protection AD à rétablir','Vérifiez et rétablissez la protection anti-suppression avant toute reprise.','error')
        Unreadable=@('! Reçu illisible','Faites contrôler le reçu par le support. Aucun verrou supprimé.','error')
    }
    $v=if($known.ContainsKey($State)){$known[$State]}else{@('? État non reconnu','Consultez les détails et faites vérifier le résultat.','warning')}
    if($Code -is [int] -and $Code -eq 96 -and $State -in @('Failed','NotStarted')){$v=$known.NotStarted}
    [pscustomobject]@{Label=$v[0];Action=$v[1];Severity=$v[2]}
}

function Get-PestoEffectLabel {
    param([string]$State)
    $labels=@{NotRequested='Non demandé';Requested='Demandé, à vérifier';Skipped='Non nécessaire';Confirmed='Confirmé';Uncertain='Incertain';Refused='Refusé';NotChanged='Inchangée';Prepared='Préparé';Lowering='Retrait en cours';Lowered='Retirée';Restoring='Rétablissement en cours';Restored='Rétablie';Initial='État initial';RecordedNotResolved='Lu, non résolu';Registered='Enregistrée';StartRequested='Lancement demandé';Started='Démarrée';Finished='Terminée';Deleted='Supprimée'}
    if($labels.ContainsKey($State)){return $labels[$State]}
    if($State -in @('Running','Failed','NotStarted','PendingRestart','Partial','MoveReady','Uncertain','Verified')){return (Get-PestoStatePresentation $State).Label}
    return 'État technique à consulter'
}

function Get-PestoStageLabel {
    param([string]$Stage)
    $head=($Stage -split ':',2)[0].Trim()
    $labels=@{Prepared='Préparation';Rename='Renommage';Move='Déplacement';Entra='Inscription Entra';Protection='Protection AD';Result='Résultat';Observation='Observation';Task='Tâche Windows';Join='Jonction au domaine'}
    if($labels.ContainsKey($head)){
        $label=$labels[$head];$parts=$Stage -split ':',2
        if($parts.Count -eq 2 -and $head -ne 'Task'){$label+=' : '+(Get-PestoEffectLabel $parts[1].Trim())}
        return $label
    }
    if($Stage -eq 'Postconditions observed'){return 'État du poste vérifié'}
    if($Stage -eq 'Acknowledged'){return 'Acquittée sans vérification'}
    if($Stage -like 'Move confirmed by *'){return 'Déplacement confirmé par un reçu lié'}
    return 'Détails dans le reçu'
}

function Get-PestoStableHash {
    param([Parameter(Mandatory=$true)]$Value)
    function Convert-CanonicalInner {
        param($InputValue)
        if($null -eq $InputValue -or $InputValue -is [string] -or $InputValue -is [ValueType]){return $InputValue}
        if($InputValue -is [Collections.IDictionary]){
            $r=[ordered]@{};$keys=[string[]]@($InputValue.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal);foreach($key in $keys){$r[[string]$key]=Convert-CanonicalInner $InputValue[$key]};return $r
        }
        if($InputValue -is [Collections.IEnumerable]){return ,@(foreach($i in $InputValue){Convert-CanonicalInner $i})}
        $r=[ordered]@{};$keys=[string[]]@($InputValue.PSObject.Properties.Name);[Array]::Sort($keys,[StringComparer]::Ordinal);foreach($key in $keys){$r[$key]=Convert-CanonicalInner $InputValue.$key};return $r
    }
    $text=ConvertTo-Json -InputObject (Convert-CanonicalInner $Value) -Compress -Depth 16
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

function Get-PestoPlanFingerprint {
    param([Parameter(Mandatory=$true)]$Plan)
    # Le contrat est volontairement fermé : les identifiants ne font jamais partie du plan exportable.
    $names=@('Nom_du_PC','Nouveau_Nom','Objet_GUID','OU_Actuelle','OU_Destination','TargetOUGuid','Domain','DC','ConfigStamp','Renommer','Deplacer','Reboot')
    $value=[ordered]@{}
    foreach($n in $names){
        $v=$Plan.$n
        if($n -in @('Renommer','Deplacer','Reboot')){
            if($null -ne $v -and $v -isnot [bool]){throw ('Booléen invalide dans le plan : '+$n)}
            $value[$n]=[bool]$v
        }else{$value[$n]=[string]$v}
    }
    return Get-PestoStableHash $value
}

function Assert-PestoConfirmedPlan {
    param($Plan,[string]$Fingerprint,[string]$ConfigurationStamp)
    if($Fingerprint -notmatch '^[a-f0-9]{64}$' -or (Get-PestoPlanFingerprint $Plan) -cne $Fingerprint){throw 'Le plan a changé depuis sa confirmation. Refaire le contrôle.'}
    if($ConfigurationStamp -and $Plan.ConfigStamp -cne $ConfigurationStamp){throw 'La politique a changé depuis le contrôle.'}
}

function ConvertTo-PestoDraft {
    param([Parameter(Mandatory=$true)]$Value)
    $allowed=@('Schema','Domain','ConfigStamp','Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID','TargetOUGuid','Renommer','Deplacer','Org','Site','Service','Type')
    Assert-PestoClosedObject $Value $allowed @('Schema','Domain','Nom_du_PC','Nouveau_Nom','Renommer','Deplacer')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1 -or $Value.Renommer -isnot [bool] -or $Value.Deplacer -isnot [bool]){throw 'Types de brouillon invalides.'}
    if([string]$Value.Domain -notmatch '^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z0-9-]+$'){throw 'Domaine du brouillon invalide.'}
    if([string]$Value.Nom_du_PC -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$'){throw 'Nom source invalide.'}
    if($Value.Renommer -and -not(ConvertTo-PestoNameParts ([string]$Value.Nouveau_Nom))){throw 'Nouveau nom non conforme.'}
    $result=[ordered]@{}
    foreach($n in $allowed){
        if($n -eq 'Schema'){$result[$n]=1;continue}
        if($n -in @('Renommer','Deplacer')){$result[$n]=[bool]$Value.$n;continue}
        $t=[string]$Value.$n
        $limit=if($n -match '^OU_'){4096}else{256}
        if($t.Length -gt $limit -or $t -match '[\x00-\x1f\x7f]'){throw ('Champ de brouillon invalide : '+$n)}
        if($n -in @('Objet_GUID','TargetOUGuid') -and $t){$g=[Guid]::Empty;if(-not [Guid]::TryParse($t,[ref]$g) -or $g -eq [Guid]::Empty){throw 'GUID de brouillon invalide.'}}
        $result[$n]=$t
    }
    # Aucun état Checked, Reboot ou Authorised n'est importable.
    return [pscustomobject]$result
}

function Get-PestoReadFailure {
    param($ErrorRecord)
    $code=Get-PestoNativeFailureCode $ErrorRecord
    $category=if($code -in @(5,1326,1385)){'Access'}elseif($code -in @(53,64,121,1460,1722,1726)){'TransientNetwork'}elseif($code -eq 1355){'DomainDiscovery'}else{'Other'}
    [pscustomobject]@{Code=$code;Category=$category;Retryable=($category -eq 'TransientNetwork');Action=$(if($null -ne $code){Get-PestoNativeGuidance $code 'lecture'}else{'Relire le détail ; aucune reprise automatique de cette erreur inconnue.'})}
}
function Invoke-PestoReadRetry {
    param([Parameter(Mandatory=$true)][scriptblock]$Read,[ValidateRange(1,3)][int]$Attempts=2,[ValidateRange(0,2000)][int]$DelayMs=200,$Cancellation=$null)
    for($i=1;$i -le $Attempts;$i++){
        if($Cancellation -and $Cancellation.Cancelled){throw [OperationCanceledException]::new('Lecture remplacée.')}
        try{
            # Une tentative peut émettre des objets avant son erreur. Ne publier
            # qu'une lecture complète, sinon la reprise mélangerait deux états AD.
            $result=@(& $Read)
            if($Cancellation -and $Cancellation.Cancelled){throw [OperationCanceledException]::new('Lecture remplacée.')}
            return $result
        }catch{
            $failure=Get-PestoReadFailure $_
            if($i -ge $Attempts -or -not $failure.Retryable){throw}
            $remaining=[int][Math]::Min(4000,$DelayMs*[Math]::Pow(2,$i-1))
            while($remaining -gt 0){
                if($Cancellation -and $Cancellation.Cancelled){throw [OperationCanceledException]::new('Reprise de lecture annulée.')}
                $slice=[Math]::Min(50,$remaining);Start-Sleep -Milliseconds $slice;$remaining-=$slice
            }
        }
    }
}
function Get-PestoPreflightBudget {
    param([ValidateRange(1,200)][int]$Count)
    return [int][Math]::Min(1800,[Math]::Max(120,30+15*$Count))
}

function Get-PestoNativeGuidance {
    param([long]$Code,[string]$Stage='')
    $messages=@{
        5='Accès refusé. Vérifier la délégation du compte pour cette action ; ne pas relancer en boucle.'
        53='Chemin réseau introuvable. Vérifier DNS et le transport attendu.'
        64='Connexion réseau interrompue. Relire les effets avant une autre tentative.'
        1326='Authentification refusée. Corriger le compte volontairement ; pas de nouvel essai automatique.'
        1355='Domaine ou contrôleur introuvable. Vérifier DNS et la découverte du contrôleur.'
        1722='RPC indisponible. Vérifier le transport cible et le pare-feu, sans activer de service automatiquement.'
        1460='Délai dépassé. Une commande déjà engagée peut encore travailler.'
        2732='Réutilisation du compte ordinateur refusée par Netjoin. Examiner NetSetup.log et la politique autorisée ; ne pas supprimer le compte.'
    }
    if($messages.ContainsKey([int]$Code)){return $messages[[int]$Code]}
    return ('Vérifier l''étape '+$Stage+' et le résultat observé. Code natif : '+$Code+'. Aucune réparation automatique.')
}

function Get-PestoPostconditionChecklist {
    param($Plan,$Observation,$Receipt)
    $windows=$Observation.Windows;$ad=$Observation.AD
    $joining=Test-PestoJoinIntervention $Receipt
    $expected=if($Plan.Renommer -or $joining){$Plan.Nouveau_Nom}else{$Plan.Nom_du_PC}
    $expectedGuid=if($Receipt.JoinEvidence.BoundObjectGuid){$Receipt.JoinEvidence.BoundObjectGuid}else{$Plan.Objet_GUID}
    $items=[Collections.Generic.List[object]]::new()
    foreach($test in @(
        @('Nom actif',[bool]$windows,[bool]($windows -and $windows.ActiveName -ieq $expected),[string]$windows.ActiveName,[string]$expected,'Windows'),
        @('Domaine Windows',[bool]$windows,[bool]($windows -and $windows.PartOfDomain -and $windows.Domain -ieq $Plan.Domain),[string]$windows.Domain,[string]$Plan.Domain,'Windows'),
        @('Identité AD',[bool]$ad,[bool]($ad -and $ad.Guid -ieq $expectedGuid),[string]$ad.Guid,[string]$expectedGuid,'AD'),
        @('Emplacement AD',[bool]$ad,[bool]($ad -and $ad.OU -ieq $(if($Plan.Deplacer -or $joining){$Plan.OU_Destination}else{$Plan.OU_Actuelle})),[string]$ad.OU,[string]$(if($Plan.Deplacer -or $joining){$Plan.OU_Destination}else{$Plan.OU_Actuelle}),'AD')
    )){
        $state=if(-not $test[1]){'Inconnu'}elseif($test[2]){'Conforme'}else{'À vérifier'}
        $items.Add([pscustomobject]@{Controle=$test[0];Etat=$state;Observe=$test[3];Attendu=$test[4];Source=$test[5];Utc=$(if($test[5] -eq 'AD'){[string]$Observation.ADUtc}else{[string]$Observation.WindowsUtc})})
    }
    $health=$Observation.Health
    $items.Add([pscustomobject]@{Controle='Jointure Entra de l''appareil';Etat=$(if($health){$health.AzureAdJoined}else{'Non vérifié'});Observe=$(if($health){$health.AzureAdJoined}else{[string]$Receipt.Entra});Attendu='À contrôler séparément si retrait';Source='Appareil local, pas SSO utilisateur';Utc=[string]$health.Utc})
    $items.Add([pscustomobject]@{Controle='Canal sécurisé';Etat=$(if($health){$health.SecureChannel}else{'Non vérifié'});Observe='';Attendu='Lecture dédiée après redémarrage';Source='Windows local';Utc=[string]$health.Utc})
    return $items.ToArray()
}

function Compare-PestoInterventions {
    param($Before,$After)
    $fields=@('Version','Plan.Domain','Plan.DC','Plan.Nom_du_PC','Plan.Nouveau_Nom','Plan.OU_Destination','Entra','Rename','Move','Protection','Phase','ResultCode')
    foreach($field in $fields){
        $a=$Before;$b=$After;foreach($part in $field.Split('.')){$a=$a.$part;$b=$b.$part}
        if([string]$a -cne [string]$b){[pscustomobject]@{Champ=$field;Premiere=[string]$a;Seconde=[string]$b;Conclusion='Différence observée, pas une preuve de causalité'}}
    }
}


function New-PestoExecutionPlan {
    param($Request)
    foreach($flag in @('Rename','Move','Reboot')){if($Request.$flag -isnot [bool]){throw ('Type de commande invalide : '+$flag)}}
    if(-not $Request.Rename -and -not $Request.Move){throw 'Aucune opération définie.'}
    return [pscustomobject]@{PSTypeName='Pesto.ExecutionPlan';Metadata=$(if($Request.Metadata){ConvertTo-PestoDeploymentMetadata $Request.Metadata}else{$null});Nom_du_PC=[string]$Request.Computer;Nouveau_Nom=[string]$Request.NewName;
        OU_Actuelle=[string]$Request.CurrentOU;OU_Destination=[string]$Request.TargetOU;
        Objet_GUID=[string]$Request.ObjectGuid;TargetOUGuid=[string]$Request.TargetOUGuid;
        Domain=[string]$Request.Domain;DC=[string]$Request.DC;ConfigStamp=[string]$Request.ConfigStamp;
        Renommer=[bool]$Request.Rename;Deplacer=[bool]$Request.Move;Reboot=[bool]$Request.Reboot}
}

function Test-PestoFreshCheck {
    param($Row,[string]$Signature,[int]$MaximumAgeSeconds=120)
    if($Row.Precontrole -notin @('VÉRIFIÉ','AVERTISSEMENT','DÉMO') -or [string]$Row.Controle_Signature -cne $Signature){return $false}
    $date=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Row.Controle_Utc,[ref]$date)){return $false}
    $age=([DateTimeOffset]::UtcNow-$date).TotalSeconds
    if($age -lt 0 -or $age -gt $MaximumAgeSeconds){return $false}
    if($Row.Deplacer -and $Row.Precontrole -ne 'DÉMO'){
        $id=[Guid]::Empty;if(-not [Guid]::TryParse([string]$Row.TargetOUGuid,[ref]$id) -or $id -eq [Guid]::Empty){return $false}
    }
    return $true
}


function Test-PestoPropertyPresent {
    param($Value,[string]$Name)
    if($null -eq $Value){return $false}
    if($Value -is [Collections.IDictionary]){return $Value.Contains($Name)}
    return $null -ne $Value.PSObject.Properties[$Name]
}


function ConvertTo-PestoSearchText {
    param([AllowNull()][string]$Text)
    if(-not $Text){return ''}
    if($Text.Length -gt 4096){$Text=$Text.Substring(0,4096)}
    $output=[Text.StringBuilder]::new()
    foreach($ch in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()){
        if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$output.Append($ch)}
    }
    return $output.ToString().Normalize([Text.NormalizationForm]::FormC).ToUpperInvariant()
}

function Find-PestoCommands {
    param([object[]]$Commands,[AllowNull()][string]$Query)
    if(@($Commands).Count -gt 100){throw 'Trop de commandes dans la palette.'}
    if($Query.Length -gt 128){throw 'Recherche trop longue.'}
    $words=@((ConvertTo-PestoSearchText $Query) -split '\s+'|Where-Object{$_})
    foreach($command in $Commands){
        $haystack=ConvertTo-PestoSearchText ([string]$command.Label+' '+[string]$command.Detail)
        $isMatch=$true
        foreach($word in $words){if($haystack.IndexOf($word,[StringComparison]::Ordinal) -lt 0){$isMatch=$false;break}}
        if($isMatch){$command}
    }
}

function ConvertTo-PestoObservationSnapshot {
    param([Parameter(Mandatory=$true)]$Observation)
    # Liste blanche : aucune exception, credential ou sortie native brute conservée.
    $result=[ordered]@{Schema=1;CapturedUtc=[string]$Observation.ObservedUtc;ADUtc=[string]$Observation.ADUtc;WindowsUtc=[string]$Observation.WindowsUtc;HealthUtc='';AD=$null;Windows=$null;Health=$null}
    if($Observation.AD){
        $result.AD=[pscustomobject]@{Name=$Observation.AD.Name;Guid=$Observation.AD.Guid;OU=$Observation.AD.OU;Protected=$Observation.AD.Protected}
    }
    if($Observation.Windows){
        $w=$Observation.Windows
        $result.Windows=[pscustomobject]@{ActiveName=$w.ActiveName;ConfiguredName=$w.ConfiguredName;Domain=$w.Domain;PartOfDomain=$w.PartOfDomain;MachineId=$w.MachineId;BootUtc=$w.BootUtc;DomainRole=$w.DomainRole}
    }
    if($Observation.Health){
        $h=$Observation.Health;$result.HealthUtc=[string]$h.Utc
        $result.Health=[pscustomobject]@{Scope=[string]$h.Scope;AzureAdJoined=$h.AzureAdJoined;DomainJoined=$h.DomainJoined;SecureChannel=$(if($h.SecureChannel -is [bool]){$h.SecureChannel}elseif($h.SecureChannel -ceq 'Conforme'){$true}elseif($h.SecureChannel -ceq 'À vérifier'){$false}else{$null})}
    }
    return Assert-PestoObservationSnapshot ([pscustomobject]$result)
}

function Assert-PestoObservationSnapshot {
    param([Parameter(Mandatory=$true)]$Snapshot)
    Assert-PestoClosedObject $Snapshot @('Schema','CapturedUtc','ADUtc','WindowsUtc','HealthUtc','AD','Windows','Health') @('Schema','CapturedUtc','ADUtc','WindowsUtc','HealthUtc','AD','Windows','Health')
    if($Snapshot.Schema -isnot [int] -or $Snapshot.Schema -ne 1){throw 'Schéma de lecture invalide.'}
    foreach($name in @('CapturedUtc','ADUtc','WindowsUtc','HealthUtc')){
        $value=$Snapshot.$name
        if($value -isnot [string] -or $value.Length -gt 64){throw 'Date de lecture invalide.'}
        if($value){
            $date=[DateTimeOffset]::MinValue
            if($value -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Date de lecture non interprétable.'}
        }elseif($name -eq 'CapturedUtc'){throw 'Lecture non datée.'}
    }
    $schemas=@{AD=@('Name','Guid','OU','Protected');Windows=@('ActiveName','ConfiguredName','Domain','PartOfDomain','MachineId','BootUtc','DomainRole');Health=@('Scope','AzureAdJoined','DomainJoined','SecureChannel')}
    foreach($section in @('AD','Windows','Health')){
        $part=$Snapshot.$section;if($null -eq $part){continue}
        Assert-PestoClosedObject $part $schemas[$section] $schemas[$section]
        foreach($key in $schemas[$section]){
            $value=$part.$key
            if($null -eq $value){continue}
            if($key -in @('Protected','PartOfDomain','SecureChannel')){
                if($value -isnot [bool]){throw ('Booléen de lecture invalide : '+$key)}
            }elseif($key -eq 'DomainRole'){
                if(($value -isnot [int] -and $value -isnot [long] -and $value -isnot [uint32]) -or $value -lt 0 -or $value -gt 5){throw 'Rôle Windows invalide.'}
            }elseif($key -in @('AzureAdJoined','DomainJoined')){
                if($value -isnot [string] -or $value -notin @('YES','NO','Unknown','')){throw 'État appareil non interprétable.'}
            }elseif($value -isnot [string] -or $value.Length -gt 4096 -or $value -match '[\x00-\x1f\x7f]'){throw ('Texte de lecture invalide : '+$key)}
        }
        if($section -eq 'AD' -and $part.Guid){$g=[Guid]::Empty;if(-not [Guid]::TryParse([string]$part.Guid,[ref]$g) -or $g -eq [Guid]::Empty){throw 'GUID observé invalide.'}}
    }
    return $Snapshot
}

function Get-PestoAcknowledgementText {
    param($Receipt)
    # Texte commun aux vues : l'acquittement n'est jamais présenté comme une réussite.
    $a=$Receipt.Acknowledged
    $when=[string]$a.Utc;$date=[DateTimeOffset]::MinValue
    if([DateTimeOffset]::TryParse($when,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){$when=$date.ToLocalTime().ToString('dd/MM/yyyy HH:mm')}
    $code=if($Receipt.PSObject.Properties['ResultCode'] -and $null -ne $Receipt.ResultCode){', code '+[string]$Receipt.ResultCode}else{''}
    return ('Acquittée le '+$when+' par '+[string]$a.By+' : '+[string]$a.Reason+'. Résultat réel conservé ('+(Get-PestoStatePresentation ([string]$Receipt.Phase)).Label+$code+'), jamais compté comme réussi. Une nouvelle opération repart d''une lecture complète du poste.')
}

function Assert-PestoAcknowledgement {
    <# Acquittement explicite d'un résultat non résolu (décision de David du 15/10) : qui, quand, pourquoi, sur quelle
       lecture. Phase et ResultCode recopient ceux du reçu acquitté ; ils ne qualifient jamais le résultat. #>
    param([Parameter(Mandatory=$true)]$Value)
    Assert-PestoClosedObject $Value @('Schema','Utc','By','Reason','Phase','ResultCode','Observation') @('Schema','Utc','By','Reason','Phase','ResultCode','Observation')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1){throw 'Schéma d''acquittement invalide.'}
    $date=[DateTimeOffset]::MinValue
    if($Value.Utc -isnot [string] -or $Value.Utc.Length -gt 64 -or $Value.Utc -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or
        -not [DateTimeOffset]::TryParse($Value.Utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Date d''acquittement invalide.'}
    if($Value.By -isnot [string] -or [string]::IsNullOrWhiteSpace($Value.By) -or $Value.By.Length -gt 256 -or $Value.By -match '[\x00-\x1f\x7f]'){throw 'Auteur d''acquittement invalide.'}
    if($Value.Reason -isnot [string] -or $Value.Reason.Trim().Length -lt 3 -or $Value.Reason.Length -gt 500 -or $Value.Reason -match '[\x00-\x1f\x7f]'){throw 'Motif d''acquittement invalide (3 à 500 caractères, une ligne).'}
    # Seules les phases non résolues s'acquittent : Verified, Failed et NotStarted ne bloquent déjà plus.
    if($Value.Phase -isnot [string] -or $Value.Phase -cnotin @('Running','PendingRestart','Partial','MoveReady','Protection','Uncertain')){throw 'Phase acquittée invalide.'}
    if($null -ne $Value.ResultCode -and (($Value.ResultCode -isnot [int] -and $Value.ResultCode -isnot [long]) -or $Value.ResultCode -lt [int]::MinValue -or $Value.ResultCode -gt [int]::MaxValue)){throw 'Code acquitté invalide.'}
    if($null -ne $Value.Observation){[void](Assert-PestoObservationSnapshot $Value.Observation)}
    return $Value
}

function Get-PestoObservationComparison {
    param([Parameter(Mandatory=$true)]$Receipt,$Observation=$null)
    $before=$Receipt.Baseline
    if($before){[void](Assert-PestoObservationSnapshot $before)}
    $after=if($Observation){ConvertTo-PestoObservationSnapshot $Observation}else{$Receipt.LastObservation}
    if($after){[void](Assert-PestoObservationSnapshot $after)}
    $p=$Receipt.Plan
    $joining=Test-PestoJoinIntervention $Receipt
    $expectedGuid=if($Receipt.JoinEvidence.BoundObjectGuid){$Receipt.JoinEvidence.BoundObjectGuid}else{$p.Objet_GUID}
    $expectedName=if($p.Renommer -or $joining){[string]$p.Nouveau_Nom}else{[string]$p.Nom_du_PC}
    $expectedOU=if($p.Deplacer -or $joining){[string]$p.OU_Destination}else{[string]$p.OU_Actuelle}
    $specs=@(
        @('Nom Windows actif','Windows','ActiveName',$expectedName,'WindowsUtc'),
        @('Nom Windows configuré','Windows','ConfiguredName',$expectedName,'WindowsUtc'),
        @('Domaine Windows','Windows','Domain',[string]$p.Domain,'WindowsUtc'),
        @('Identité Windows','Windows','MachineId',[string]$Receipt.TargetMachineId,'WindowsUtc'),
        @('Nom AD','AD','Name',$expectedName,'ADUtc'),
        @('GUID AD','AD','Guid',[string]$expectedGuid,'ADUtc'),
        @('Emplacement AD','AD','OU',$expectedOU,'ADUtc'),
        @('Protection AD','AD','Protected',$Receipt.InitialProtection,'ADUtc'),
        @('Inscription Entra','Health','AzureAdJoined',$null,'HealthUtc'),
        @('Canal sécurisé','Health','SecureChannel',$true,'HealthUtc')
    )
    foreach($entry in $specs){
        $old=$null;$actual=$null;$oldDate='';$newDate=''
        if($before){$section=$before.($entry[1]);if($section){$old=$section.($entry[2])};$oldDate=[string]$before.($entry[4])}
        if($after){$section=$after.($entry[1]);if($section){$actual=$section.($entry[2])};$newDate=[string]$after.($entry[4])}
        $wanted=$entry[3]
        $known=($null -ne $actual -and [string]$actual -ne '' -and [string]$actual -ne 'Unknown')
        $expectedKnown=($null -ne $wanted -and [string]$wanted -ne '')
        $state=if(-not $known){'Non lu'}elseif(-not $expectedKnown){'Information'}elseif([string]$actual -ieq [string]$wanted){'Concordant'}else{'Écart'}
        [pscustomobject]@{Champ=$entry[0];Avant=$(if($null -eq $old -or [string]$old -eq ''){'Non enregistré'}else{[string]$old});Prevu=$(if($expectedKnown){[string]$wanted}else{'À vérifier séparément'});Observe=$(if($known){[string]$actual}else{'Inconnu'});Etat=$state;AvantUtc=$oldDate;ObserveUtc=$newDate}
    }
}

function Get-PestoNamingContextSource {
    # Capture sans marqueur interne de resolution : chaque runspace revalide le contrat.
    $c=Get-PestoActiveNamingConvention
    $public=[pscustomobject]@{Schema=1;Id=$c.Id;Tokens=$c.Tokens;Widths=$c.Widths;Types=$c.Types}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($public|ConvertTo-Json -Depth 5 -Compress)))
    $sb=[Text.StringBuilder]::new()
    foreach($n in @(@('Assert-PestoClosedObject')+@(Get-PestoNamingFunctionNames)|Select-Object -Unique)){
        [void]$sb.AppendLine(('function '+$n+' {'+(Get-Command $n -CommandType Function).Definition+'}'))
    }
    [void]$sb.AppendLine("[void](Set-PestoActiveNamingConvention ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded'))|ConvertFrom-Json))")
    return $sb.ToString()
}

function Get-PestoFacetPattern {
    param([ValidateSet('Prefix','Site','Service','Number','Type')][string]$Facet,$Convention)
    $c=(Get-PestoNamingLayout $Convention).Convention
    if($Facet -eq 'Type'){return ('^['+$c.Types+']$')}
    $class=switch($Facet){'Site'{'[A-Za-z]'};'Service'{'[A-Za-z0-9]'};default{'[0-9]'}}
    return '^'+$class+'{'+$c.Widths[$Facet]+'}$'
}
function New-PestoNameLdapPattern {
    param([string]$Prefix,[string]$Site='',[string]$Service='',[string]$Type='')
    $c=Get-PestoActiveNamingConvention;$parts=@{Prefix=$Prefix;Site=$Site;Service=$Service;Type=$Type;Number=''}
    foreach($f in @('Prefix','Site','Service','Type')){if($parts[$f] -and $parts[$f] -notmatch (Get-PestoFacetPattern $f)){throw 'Facette LDAP invalide.'}}
    return (@(foreach($f in $c.Tokens){if($parts[$f]){$parts[$f]}else{'*'}}) -join '')
}
