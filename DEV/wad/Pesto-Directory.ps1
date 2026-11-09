#requires -Version 5.1
# Définitions uniquement, chargées dans la portée du moteur.


function Ensure-ADModule {
    param([Parameter(Mandatory=$true)][string]$ADModulePath)
    Import-PestoADModule -ADModulePath $ADModulePath
    return $true
}

function CheckDomainWMI {
    <# $true/$false quand l'état est connu ; $null si CIM est indisponible.
       Une panne de détection ne doit jamais être interprétée comme « hors domaine »
       car cela proposerait à tort une nouvelle jonction. #>
    param([string]$DomainName2Compare)
    $script:DetectedDomain = $null
    if ([string]::IsNullOrWhiteSpace($DomainName2Compare)) { return $null }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $script:DetectedDomain = if ([bool]$cs.PartOfDomain) { "$($cs.Domain)".Trim() } else { $null }
        if ([bool]$cs.PartOfDomain -and -not $script:DetectedDomain) { return $null }
        return ([bool]$cs.PartOfDomain -and $script:DetectedDomain -ieq $DomainName2Compare.Trim())
    } catch {
        Write-Log 'Détection de l''appartenance au domaine impossible via Win32_ComputerSystem.' 'ERROR' $_ 'init'
        return $null
    }
}

function Get-DomainController {
    param([Parameter(Mandatory=$true)][string]$DomainName)
    if(-not(Test-PestoDnsName $DomainName)){throw 'Domaine DNS invalide.'}
    $candidate=Get-ADDomainController -Discover -DomainName $DomainName -Writable -Service ADWS -ForceDiscover -ErrorAction Stop
    $names=@($candidate.HostName)
    if($names.Count -ne 1 -or -not(Test-PestoDnsName ([string]$names[0])) -or ([string]$names[0]).IndexOf('.') -lt 1){
        throw 'Aucun contrôleur inscriptible avec ADWS identifié. Vérifiez DNS, réseau et domaine.'
    }
    return ([string]$names[0]).TrimEnd('.')
}

function Get-ADParams {
    <# Construit la table de paramètres communs aux cmdlets AD (-Server + -Credential).
       CRUCIAL : -Credential n'est ajouté QUE si $script:cred existe. Passer
       -Credential $null à une cmdlet AD déclenche un prompt Windows natif
       (Get-Credential implicite). $script:cred est aussi nul en mode « Compte Windows » :
       dans ce cas l'absence volontaire de -Credential fait utiliser l'identité de la session courante.
       Cette identité doit être un principal du domaine, sinon ADWS ferme la connexion et la
       cmdlet ne rend qu'une panne de contact serveur : d'où l'avertissement posé ici, une seule
       fois, sans modifier la table renvoyée. #>
    $p = @{ Server = $script:DC }
    if ($script:cred) { $p['Credential'] = $script:cred }
    elseif (-not $script:PestoDomainIdentityWarned) {
        $script:PestoDomainIdentityWarned = $true
        $msg = Get-PestoDomainIdentityWarning -Identity (Get-PestoWindowsAuthIdentity) -InDomain ([bool]$script:INDOMAIN)
        if ($msg) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $msg 'WARN' $null 'AD' }
            Write-Warning $msg
        }
    }
    return $p
}

function Find-ADComputerByName {
    <# Recherche le CN ou le sAMAccountName. Une vraie panne AD reste terminante,
       alors que l'absence de résultat renvoie simplement $null. #>
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name.Trim()
    if (-not (Test-PestoComputerName $n)) { throw "Nom d'ordinateur invalide : '$Name'." }
    $adp = Get-ADParams
    # $n est déjà limité à [A-Za-z0-9-], donc aucun échappement LDAP additionnel.
    $ldap = "(|(name=$n)(sAMAccountName=$n`$)(dNSHostName=$n.$($script:DOMAINE)))"
    $found=@(Invoke-PestoReadRetry -Read {Get-ADComputer -LDAPFilter $ldap -ResultSetSize 2 -ErrorAction Stop @adp} -Attempts $(if($script:PestoPolicy){$script:PestoPolicy.ReadAttempts}else{2}))
    if($found.Count -gt 1){throw "Nom AD ambigu (CN / sAMAccountName) : '$n'. Aucune sélection arbitraire."}
    if($found.Count -eq 1){return $found[0]}
    return $null
}

function Get-ComputerOU {
    <# Retourne { Name, OU, DN } pour un ordinateur AD. #>
    param([string]$Identity)
    $id = "$Identity".Trim()
    if (-not (Test-PestoComputerName $id)) { throw "Nom d'ordinateur invalide : '$Identity'." }
    $adp = Get-ADParams
    $pc = Get-ADComputer -Identity $id -Properties DistinguishedName -ErrorAction Stop @adp
    if (-not $pc -or [string]::IsNullOrWhiteSpace("$($pc.DistinguishedName)")) {
        throw "Objet ordinateur '$id' sans DistinguishedName."
    }
    return [PSCustomObject]@{
        Name = $pc.Name
        OU   = Get-PestoParentDN ([string]$pc.DistinguishedName)
        DN   = $pc.DistinguishedName
        ObjectGUID = [string]$pc.ObjectGUID
    }
}

function Get-AllComputersInOU {
    <# Liste tous les ordinateurs d'une OU. -ThrowOnError permet aux chargements
       transactionnels de conserver l'ancien cache en cas de panne AD. #>
    param([string]$ParentOU, [switch]$ThrowOnError)
    if (-not (Test-PestoOUPath $ParentOU)) {
        $err = "SearchBase vide ou invalide : '$ParentOU'."
        Write-Log $err 'ERROR' $null 'AD'
        if ($ThrowOnError) { throw $err }
        return @()
    }
    try {
        $adp = Get-ADParams
        return @(Get-ADComputer -Filter * -SearchBase $ParentOU -SearchScope Subtree `
                 -Properties Name -ErrorAction Stop @adp)
    } catch {
        Write-Log "Scan des ordinateurs impossible (SearchBase '$ParentOU')." 'ERROR' $_ 'AD'
        if ($ThrowOnError) { throw }
        return @()
    }
}

function Update-ComputersNoms {
    <# Met à jour le périmètre de l'onglet Noms. #>
    param([switch]$ThrowOnError)
    if ("$($script:OU_SCAN)" -ieq "$($script:OU['ROOT'])") {
        $script:ComputersNoms = $script:Computers
    } else {
        $script:ComputersNoms = Get-AllComputersInOU -ParentOU $script:OU_SCAN -ThrowOnError:$ThrowOnError
    }
}

function Select-PestoUniqueComputers {
    param([object[]]$Computers)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($computer in @($Computers)){
        if(-not $computer){continue}
        # Garder deux noms observés sur le même GUID : la réplication peut être en cours.
        $name=([string]$computer.Name).Trim()
        $identity=if($computer.ObjectGUID){'G:'+([string]$computer.ObjectGUID)}elseif($computer.DistinguishedName){'D:'+([string]$computer.DistinguishedName)}else{'N:'+$name}
        if($seen.Add($identity+'|'+$name)){$computer}
    }
}

function Test-PestoDNWithinScope {
    param([string]$DistinguishedName,[string[]]$Roots)
    try {
        $p = @(Split-PestoDistinguishedName $DistinguishedName)
        foreach ($root in @($Roots)) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $r = @(Split-PestoDistinguishedName $root)
            if ($p.Count -lt $r.Count) { continue }
            $same=$true; $offset=$p.Count-$r.Count
            for ($i=0;$i -lt $r.Count;$i++) { if ($p[$i+$offset] -ine $r[$i]) { $same=$false; break } }
            if ($same) { return $true }
        }
    } catch { return $false }
    return $false
}

function Select-PestoComputersInScope {
    param([object[]]$Computers,[string]$Root)
    $parts=@(Split-PestoDistinguishedName $Root)
    foreach($computer in @($Computers)){
        if(-not $computer){continue}
        $dn=@(Split-PestoDistinguishedName ([string]$computer.DistinguishedName))
        if($dn.Count -lt $parts.Count){continue}
        $inside=$true;$offset=$dn.Count-$parts.Count
        for($i=0;$i -lt $parts.Count;$i++){if($dn[$offset+$i] -ine $parts[$i]){$inside=$false;break}}
        if($inside){$computer}
    }
}

function Get-PestoDirectoryProjectionSource {
    $builder=[Text.StringBuilder]::new()
    foreach($name in @('Split-PestoDistinguishedName','Test-PestoDNWithinScope','Select-PestoUniqueComputers','Select-PestoComputersInScope','Merge-PestoDirectoryDelta','Test-PestoDirectoryCursor','Read-PestoDirectoryChanges','Get-PestoIncrementalInventory')){
        $definition=(Get-Command $name -CommandType Function -ErrorAction Stop).Definition
        [void]$builder.AppendLine("function $name {`r`n$definition`r`n}")
    }
    return $builder.ToString()
}

function Test-PestoSiteLookupFresh {
    param([string]$Key)
    if(-not $script:SiteLookupCache -or -not $script:SiteLookupCache.ContainsKey($Key) -or -not $script:SiteLookupInfo -or -not $script:SiteLookupInfo.ContainsKey($Key)){return $false}
    $info=$script:SiteLookupInfo[$Key]
    if(-not $info.Complete){return $false}
    $elapsed=([Diagnostics.Stopwatch]::GetTimestamp()-[long]$info.Tick)/[double][Diagnostics.Stopwatch]::Frequency
    return ($elapsed -ge 0 -and $elapsed -lt 120)
}

function Merge-PestoDirectoryDelta {
    param([object[]]$Previous,[object[]]$Changes,[string[]]$Roots,[int]$Maximum=200000)
    $rows=@{}
    foreach($row in @($Previous)){$rows[([Guid]$row.ObjectGUID).ToString('D')]=$row}
    foreach($change in @($Changes)){
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$change.ObjectGUID,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Delta AD sans identite stable.'}
        $key=$id.ToString('D')
        if($change.Deleted -eq $true){$rows.Remove($key);continue}
        if(-not $change.Name -or -not $change.DistinguishedName){throw 'Delta AD incomplet.'}
        if(Test-PestoDNWithinScope ([string]$change.DistinguishedName) $Roots){
            $rows[$key]=[pscustomobject]@{Name=[string]$change.Name;DistinguishedName=[string]$change.DistinguishedName;ObjectGUID=$key}
        }else{$rows.Remove($key)}
        if($rows.Count -gt $Maximum){throw 'Inventaire trop volumineux.'}
    }
    return @($rows.Values)
}
function Test-PestoDirectoryCursor {
    param($State,[string]$DC,[string]$Instance,[string]$Scope,[string]$AuthScope)
    if(-not $State -or $State.Schema -ne 1 -or $State.DC -ine $DC -or $State.Instance -cne $Instance -or
       $State.Scope -cne $Scope -or $State.AuthScope -cne $AuthScope -or $State.Cookie -isnot [byte[]] -or
       $State.Cookie.Length -eq 0 -or $State.Cookie.Length -gt 1MB){return $false}
    try{$age=([DateTime]::UtcNow-[DateTime]::Parse([string]$State.Utc).ToUniversalTime()).TotalMinutes;return ($age -ge 0 -and $age -lt 15)}catch{return $false}
}
function Read-PestoDirectoryChanges {
    param([string]$DC,[string]$NamingContext,$Credential,[byte[]]$Cookie=@(),[int]$Maximum=200000,$Cancellation)
    Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
    $connection=[DirectoryServices.Protocols.LdapConnection]::new([DirectoryServices.Protocols.LdapDirectoryIdentifier]::new($DC,389,$false,$false))
    try{
        $connection.AuthType=[DirectoryServices.Protocols.AuthType]::Negotiate
        if($Credential){$connection.Credential=$Credential.GetNetworkCredential()}
        $connection.SessionOptions.ProtocolVersion=3;$connection.SessionOptions.Signing=$true;$connection.SessionOptions.Sealing=$true
        $connection.Timeout=[TimeSpan]::FromSeconds(30);$connection.Bind()
        $items=[Collections.Generic.List[object]]::new();$clock=[Diagnostics.Stopwatch]::StartNew();$pages=0
        do{
            if($Cancellation -and $Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
            if($clock.Elapsed.TotalSeconds -gt 120 -or ++$pages -gt 2000){throw 'Delta AD hors budget.'}
            # Les OU sont suivies aussi : un deplacement de parent ne notifie pas ses enfants.
            $request=[DirectoryServices.Protocols.SearchRequest]::new($NamingContext,'(|(objectClass=computer)(objectClass=organizationalUnit))',[DirectoryServices.Protocols.SearchScope]::Subtree,[string[]]@('objectGUID','objectClass','name','isDeleted'))
            [void]$request.Controls.Add([DirectoryServices.Protocols.DirSyncRequestControl]::new($Cookie,[DirectoryServices.Protocols.DirectorySynchronizationOptions]::None))
            [void]$request.Controls.Add([DirectoryServices.Protocols.ShowDeletedControl]::new())
            [void]$request.Controls.Add([DirectoryServices.Protocols.ExtendedDNControl]::new([DirectoryServices.Protocols.ExtendedDNFlag]::StandardString))
            $response=[DirectoryServices.Protocols.SearchResponse]$connection.SendRequest($request)
            $sync=@($response.Controls|Where-Object {$_ -is [DirectoryServices.Protocols.DirSyncResponseControl]})
            if($sync.Count -ne 1 -or -not $sync[0].Cookie.Length -or $sync[0].Cookie.Length -gt 1MB){throw 'Curseur DirSync absent ou invalide.'}
            foreach($entry in $response.Entries){
                $guid=[Guid]::Empty;$match=[regex]::Match($entry.DistinguishedName,'^<GUID=([0-9a-fA-F-]{36})>;')
                if($entry.Attributes['objectGUID']){$guid=[Guid]::new([byte[]]$entry.Attributes['objectGUID'][0])}
                elseif($match.Success){$guid=[Guid]$match.Groups[1].Value}else{throw 'GUID absent du delta.'}
                $classes=@();if($entry.Attributes['objectClass']){$classes=@($entry.Attributes['objectClass'].GetValues([string]))}
                # L'objet peut n'emettre que les attributs changes. Le DN suffit pour
                # demander ensuite l'objet complet par GUID au meme DC.
                $deleted=($entry.Attributes['isDeleted'] -and [string]$entry.Attributes['isDeleted'][0] -ieq 'TRUE')
                $items.Add([pscustomobject]@{ObjectGUID=$guid.ToString('D');Deleted=[bool]$deleted;Container=('organizationalUnit' -in $classes);UnknownClass=($classes.Count -eq 0)})
                if($items.Count -gt $Maximum){throw 'Delta AD trop volumineux.'}
            }
            $Cookie=[byte[]]$sync[0].Cookie;$more=[bool]$sync[0].MoreData
        }while($more)
        [pscustomobject]@{Changes=$items.ToArray();Cookie=$Cookie}
    }finally{$connection.Dispose()}
}
function Get-PestoIncrementalInventory {
    param($Request,[string]$DC,[int]$Maximum=200000)
    # Une absence de droits DirSync ou un cookie invalide impose le scan complet
    # existant. Ni permission supplementaire ni vue partielle silencieuse.
    try{
        $adp=@{Server=$DC;ErrorAction='Stop'};if($Request.Credential){$adp.Credential=$Request.Credential}
        $dse=Get-ADRootDSE @adp
        $ntds=Get-ADObject -Identity ([string]$dse.dsServiceName) -Properties invocationId @adp
        $instance=([Guid]$ntds.invocationId).ToString('D');if($instance -eq [Guid]::Empty.ToString('D')){throw 'Instance AD inconnue.'}
        $roots=@([string]$Request.RootOU,[string]$Request.ScanOU)
        $scope=($roots|ForEach-Object{$_.ToUpperInvariant()}) -join '|'
        $state=$Request.SyncState;$valid=Test-PestoDirectoryCursor $state $DC $instance $scope ([string]$Request.AuthScope)
        $cookie=if($valid){[byte[]]$state.Cookie}else{[byte[]]@()}
        $delta=Read-PestoDirectoryChanges -DC $DC -NamingContext ([string]$dse.defaultNamingContext) -Credential $Request.Credential -Cookie $cookie -Maximum $Maximum -Cancellation $Request.Cancellation
        $changes=[Collections.Generic.List[object]]::new()
        foreach($row in @($delta.Changes)){
            if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
            if($row.Container){
                if($valid){throw 'Hierarchie AD modifiee : scan complet requis.'}
                continue
            }
            if($row.Deleted){
                # DirSync ne renvoie pas les attributs inchanges. Une suppression
                # de classe inconnue hors du cache peut concerner une OU parente.
                if($valid -and $row.UnknownClass -and -not @($state.Rows|Where-Object ObjectGUID -EQ $row.ObjectGUID).Count){throw 'Suppression de hierarchie possible : scan complet requis.'}
                $changes.Add($row);continue
            }
            $object=Get-ADObject -Identity ([Guid]$row.ObjectGUID) -Properties Name,objectClass @adp
            if([string]$object.ObjectClass -ne 'computer'){if($valid){throw 'Hierarchie AD modifiee.'};continue}
            $changes.Add([pscustomobject]@{ObjectGUID=[string]$object.ObjectGUID;Name=[string]$object.Name;DistinguishedName=[string]$object.DistinguishedName;Deleted=$false})
        }
        $previous=if($valid){@($state.Rows)}else{@()}
        $rows=@(Merge-PestoDirectoryDelta -Previous $previous -Changes $changes.ToArray() -Roots $roots -Maximum $Maximum)
        $next=[pscustomobject]@{Schema=1;DC=$DC;Instance=$instance;Scope=$scope;AuthScope=[string]$Request.AuthScope;Cookie=[byte[]]$delta.Cookie;Rows=$rows;Utc=[DateTime]::UtcNow.ToString('o')}
        [pscustomobject]@{Root=@(Select-PestoComputersInScope $rows ([string]$Request.RootOU));Names=@(Select-PestoComputersInScope $rows ([string]$Request.ScanOU));State=$next}
    }catch{
        if($_.Exception -is [OperationCanceledException]){throw}
        return $null
    }
}

function New-PestoDirectorySnapshotRequest {
    param([System.Management.Automation.PSCredential]$Credential,[switch]$IncludeLocalHardware,[switch]$FullInventory)
    if(-not $script:PestoDirectoryAuthScope -or -not [object]::ReferenceEquals($script:PestoDirectoryAuthCredential,$Credential)){
        $script:PestoDirectoryAuthScope=[Guid]::NewGuid().ToString('N');$script:PestoDirectoryAuthCredential=$Credential
        $script:PestoDirectorySyncState=$null
    }
    [pscustomobject]@{
        AuthScope=$script:PestoDirectoryAuthScope;SyncState=$script:PestoDirectorySyncState
        Domain=$script:DOMAINE
        DC=$script:DC
        Credential=$Credential
        OUSite=$script:OUV
        RootOU=$script:OU['ROOT']
        ScanOU=$script:OU_SCAN
        LocalComputerName=$env:COMPUTERNAME
        IncludeLocalHardware=[bool]$IncludeLocalHardware
        FullInventory=[bool]$FullInventory
        MaxInventoryRows=200000;Cancellation=[hashtable]::Synchronized(@{Cancelled=$false})
        ADLoaderSource=((Get-PestoADLoaderSource)+(Get-PestoNamingContextSource));ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')
        IdentitySource=(Get-PestoDirectoryIdentitySource)
        ProjectionSource=(Get-PestoDirectoryProjectionSource)
    }
}

function Complete-PestoDirectoryRefresh {
    param([AllowNull()]$Snapshot,[bool]$LockMain,[AllowNull()]$Failure,[string]$RequestId='')
    if($RequestId -and $RequestId -ne $script:NmDirectoryRequestId){return}
    try {
        if($Failure){throw $Failure.Exception}
        if(-not $Snapshot -or -not $Snapshot.DC -or $Snapshot.Complete -isnot [bool] -or -not $Snapshot.Complete){throw 'Snapshot AD absent ou incomplet.'}
        # Fonction nommée liée au script Pesto, et non au module privé GetNewClosure.
        $script:NmNeedsDirectoryRetry=$false
        if($script:InventoryLoaded -and $Snapshot.FullInventory){$script:NmPreviousNames=@($script:ComputersNoms.Name)}
        $script:DC=[string]$Snapshot.DC;$script:Sites=$Snapshot.Sites;$script:SiteMetadata=@($Snapshot.SiteMetadata)
        $script:PestoDirectorySyncState=$Snapshot.SyncState
        $script:InventoryLoaded=[bool]$Snapshot.FullInventory;$script:InventoryUtc=[string]$Snapshot.CollectedUtc
        $script:Computers=@($Snapshot.Root);$script:DirectoryNameSnapshot=@($Snapshot.Names)
        if($Snapshot.FullInventory){$script:AffectedNameSnapshot=@()}
        $script:KnownComputersCache=$null;$script:SiteServiceCache=@{}
        $script:ComputersNoms=@(Select-PestoUniqueComputers (@($script:Computers)+@($script:DirectoryNameSnapshot)+@($script:AffectedNameSnapshot)+@(Get-PestoSiteLookupItems)));$script:NmUsedSrc=$null
        if($Snapshot.LocalComputer){$script:LocalComputerSnapshot=$Snapshot.LocalComputer}
        Update-PestoComputerIndex;Build-NmIndex;Populate-NmFilters;Update-NameGrid
        if($script:InventoryLoaded){Update-PestoServiceChoices}
        $msg=if($script:InventoryLoaded){"Inventaire actualisé : $(@($script:ComputersNoms).Count) noms / $(@($script:Computers).Count) postes."}else{"Sites actualisés. Inventaire des postes chargé à la demande."}
        Add-LogLine $msg 'info';$LblStatus.Text=$msg
    }catch{
        $msg="Rafraîchissement AD échoué : $($_.Exception.Message)"
        Add-LogLine $msg 'err';Write-Log $msg 'ERROR' $_ 'AD';$LblStatus.Text=$msg
        $script:NmViewGeneration=[int]$script:NmViewGeneration+1
        Stop-PestoAsyncOperation 'NamesProjection'
        $script:NmNeedsDirectoryRetry=$true
        Set-PestoNamesViewState -State Error -Title 'Chargement Active Directory interrompu' -Detail ($_.Exception.Message+" Aucun résultat partiel publié. Cliquez sur $(Get-PestoUxNom 'BtnReessayer').")
    }finally{
        if($NmBtnRefresh){$NmBtnRefresh.IsEnabled=-not $script:Running}
        if($NmBtnRetryNames){$NmBtnRetryNames.IsEnabled=-not $script:Running}
        if($LockMain -and -not $script:Running){
            $CbOrg.IsEnabled=$true
            try{Update-PestoServiceChoices;Update-AddButton}catch{}
        }
        Update-QueueButtons;Update-AddButton
    }
}

function Refresh-Names {
    param([switch]$Replace,[switch]$LockMain,[switch]$SitesOnly)
    if($script:GUI){Build-NmIndex;Populate-NmFilters;Update-NameGrid;return $true}
    if(Test-PestoAsyncOperationRunning 'DirectoryRefresh'){
        if(-not $Replace){return $false}
        Stop-PestoAsyncOperation 'DirectoryRefresh'
    }
    # Un ancien calcul ne peut pas publier une liste pendant un nouveau scan.
    $script:NmViewGeneration=[int]$script:NmViewGeneration+1
    Stop-PestoAsyncOperation 'NamesProjection'
    $script:NmDirectoryRequestId=[guid]::NewGuid().ToString('N')
    $context=[pscustomobject]@{LockMain=[bool]$LockMain;RequestId=$script:NmDirectoryRequestId}
    $monitor=[hashtable]::Synchronized(@{State=[pscustomobject]@{Stage='Connexion à Active Directory';Count=0;Unit=''}})
    Set-PestoNamesViewState -State Loading -Monitor $monitor
    if($NmBtnRefresh){$NmBtnRefresh.IsEnabled=$false}
    if($LockMain){
        try{$CbOrg.IsEnabled=$false;$CbSite.IsEnabled=$false;$CbService.IsEnabled=$false;$CbName.IsEnabled=$false;$BtnAdd.IsEnabled=$false}catch{}
    }
    $LblStatus.Text='Actualisation Active Directory…'
    try{
        $request=New-PestoDirectorySnapshotRequest -Credential $script:cred -FullInventory:(-not $SitesOnly)
        $request | Add-Member -NotePropertyName Progress -NotePropertyValue $monitor
        $ok={param($snap,$ctx) Complete-PestoDirectoryRefresh -Snapshot $snap -LockMain $ctx.LockMain -RequestId $ctx.RequestId}
        $err={param($e,$ctx) Complete-PestoDirectoryRefresh -Failure $e -LockMain $ctx.LockMain -RequestId $ctx.RequestId}
        $started=Start-PestoAsyncOperation -Name 'DirectoryRefresh' -ScriptBlock $script:PestoDirectorySnapshotWorker -ArgumentList @($request) -OnSuccess $ok -OnError $err -CallbackContext $context -Replace:$Replace -TimeoutSec 180
        if(-not $started -and $script:NmLoading){
            throw 'Le chargement AD n''a pas pu démarrer.'
        }
        return [bool]$started
    }catch{
        Complete-PestoDirectoryRefresh -Failure $_ -LockMain ([bool]$LockMain) -RequestId $context.RequestId
        return $false
    }
}

function Get-PCType {
    if($script:CachedPCType -in @('Portable','Fixe','Inconnu')){return $script:CachedPCType}
    $result='Inconnu'
    try {
        $systems=@(Get-CimInstance -ClassName Win32_SystemEnclosure -OperationTimeoutSec 8 -ErrorAction Stop)
        $types=@($systems | ForEach-Object { $_.ChassisTypes })
        if(@($types | Where-Object { [int]$_ -in @(8,9,10,11,12,14,18,21,30,31,32) }).Count){$result='Portable'}
        elseif(@($types | Where-Object { [int]$_ -in @(3,4,5,6,7,13,15,16,17,23,24,35,36) }).Count){$result='Fixe'}
    } catch {Write-Log 'Type matériel non déterminé. Choisissez le type de poste explicitement.' 'WARN' $_ 'hardware'}
    $script:CachedPCType=$result
    return $result
}

function Extract-Site {
    <# Noms triés des OUs enfants (= sites) d'une OU parente. #>
    param([string]$OU_Sites, [switch]$ThrowOnError)
    $sites = @{}
    if (-not (Test-PestoOUPath $OU_Sites)) {
        $msg = "OUSite invalide : '$OU_Sites'."
        Write-Log $msg 'ERROR' $null 'AD'
        if ($ThrowOnError) { throw $msg }
        return @()
    }
    try {
        $adp = Get-ADParams
        Get-ADOrganizationalUnit -SearchBase $OU_Sites -SearchScope OneLevel -Filter * `
            -ErrorAction Stop @adp | ForEach-Object { $sites[$_.Name] = $true }
    } catch {
        Write-Log "OUSite illisible : $OU_Sites" 'ERROR' $_ 'AD'
        Add-LogLine "OUSite illisible : $OU_Sites — $($_.Exception.Message)" 'warn'
        if ($ThrowOnError) { throw }
    }
    return @($sites.Keys | Sort-Object)
}

function Extract-Equipe {
    <# Codes équipe extraits uniquement des noms conformes à la convention Pesto. #>
    param([array]$computers)
    $equipes = @{}
    foreach ($c in @($computers)) {
        $n = "$($c.Name)".Trim()
        if (Test-PestoGeneratedComputerName $n) { $equipes[(ConvertTo-PestoNameParts $n).Service] = $true }
    }
    return @($equipes.Keys | Sort-Object)
}

function Get-PestoSiteServiceCodes {
    <# Codes service connus pour un site, lus dans le cache local (aucun appel AD) : noms conformes rangés sous
       l'OU du site de l'organisme choisi, ou portant le code du site dans leur nom. La saisie d'un nouveau code
       reste possible ; une liste vide signifie seulement qu'aucun poste connu ne porte ce site. #>
    param([string]$OrganismeOU,[string]$Site,[array]$Computers)
    $siteName=([string]$Site).Trim()
    if(-not $siteName){return @()}
    $suffix=$null
    if(([string]$OrganismeOU).Trim()){$suffix=(',OU='+(ConvertTo-PestoRdnValue $siteName)+','+([string]$OrganismeOU).Trim()).ToLowerInvariant()}
    $tag=$null
    try{$tag=[string](Get-SiteTag -SiteName $siteName)}catch{$tag=$null}
    if(-not $script:SiteServiceCache -or -not [object]::ReferenceEquals($script:SiteServiceSource,$Computers)){$script:SiteServiceCache=@{};$script:SiteServiceSource=$Computers}
    $cacheKey=$script:PREFIXE+'|'+$suffix+'|'+$tag
    if($script:SiteServiceCache.ContainsKey($cacheKey)){return $script:SiteServiceCache[$cacheKey]}
    $codes=@{}
    $inventory=Get-PestoNameInventoryIndex $Computers
    foreach($entry in $inventory.Entries){
        $parts=$entry.Parts
        if($parts.Prefix -cne [string]$script:PREFIXE){continue}
        $dn=[string]$entry.Computer.DistinguishedName
        $inSiteOU=($suffix -and $dn -and $dn.ToLowerInvariant().EndsWith($suffix))
        $sameTag=($tag -match (Get-PestoFacetPattern Site) -and $parts.Site -ceq $tag)
        if($inSiteOU -or $sameTag){$codes[[string]$parts.Service]=$true}
    }
    $script:SiteServiceCache[$cacheKey]=@($codes.Keys | Sort-Object)
    return $script:SiteServiceCache[$cacheKey]
}

function Get-PestoSiteLookupItems {
    <# Postes lus par les recherches ciblées de site (Request-PestoSiteLookup) pendant la session. #>
    $all=[Collections.Generic.List[object]]::new()
    if($script:SiteLookupCache){foreach($v in @($script:SiteLookupCache.Values)){foreach($c in @($v)){if($c){[void]$all.Add($c)}}}}
    return $all.ToArray()
}

function Get-PestoKnownComputers {
    <# Postes connus localement : inventaire chargé (OU racine, périmètre des noms) et recherches ciblées de site. #>
    if($null -eq $script:KnownComputersCache){$script:KnownComputersCache=@(Select-PestoUniqueComputers (@($script:Computers)+@($script:ComputersNoms)+@(Get-PestoSiteLookupItems)))}
    return ,$script:KnownComputersCache
}

function Request-PestoSiteLookup {
    <# Services et numéros déjà utilisés d'un site, lus dans l'AD par deux requêtes ciblées : noms du site dans tout le
       domaine (début du nom, attribut indexé) et postes de l'OU du site. Quelques secondes, sans attendre l'inventaire
       complet (30 s et plus sur un grand domaine, signalé par David le 08/10). Lecture seule, en arrière-plan ; le
       résultat complète les listes déjà affichées. #>
    param([string]$OrganismeOU,[string]$Site,[switch]$Force)
    if($script:GUI){return}
    $siteName=([string]$Site).Trim()
    if(-not $siteName){return}
    if([string]$script:PREFIXE -notmatch (Get-PestoFacetPattern Prefix) -or -not $script:DC -or (-not $script:INDOMAIN -and -not $script:cred)){
        try{Write-Log ('Lecture ciblée du site non lancée : préfixe, contrôleur ou compte absent ('+$siteName+').') 'WARN' $null 'AD'}catch{}
        return
    }
    $tag='';try{$tag=[string](Get-SiteTag -SiteName $siteName)}catch{$tag=''}
    if($tag -cnotmatch (Get-PestoFacetPattern Site)){$tag=''}
    $siteOU=''
    if($siteName -ine 'PREPROD' -and (Test-PestoOUPath ([string]$OrganismeOU))){$siteOU='OU='+(ConvertTo-PestoRdnValue $siteName)+','+([string]$OrganismeOU).Trim()}
    if(-not $tag -and -not $siteOU){try{Write-Log ('Lecture ciblée du site non lancée : ni code site ni OU de site pour '+$siteName+'.') 'WARN' $null 'AD'}catch{};return}
    $key=([string]$script:DOMAINE+'|'+[string]$script:DC+'|'+[string]$script:PREFIXE+'|'+$tag+'|'+$siteOU).ToUpperInvariant()
    if(-not $script:SiteLookupCache){$script:SiteLookupCache=@{}}
    if(-not $Force -and (Test-PestoSiteLookupFresh $key)){$script:SiteLookupKey=$key;return}
    if($script:SiteLookupKey -eq $key -and (Test-PestoAsyncOperationRunning 'SiteLookup')){return}
    $script:SiteLookupKey=$key
    if(-not $script:SiteLookupState){$script:SiteLookupState=@{}}
    $script:SiteLookupState[$key]=[pscustomobject]@{State='Loading';Error=''}
    try{Write-Log ('Lecture ciblée du site lancée : '+$siteName+$(if($Force){' (actualisation demandée)'}else{''})+'.') 'INFO' $null 'AD'}catch{}
    $request=[pscustomobject]@{Key=$key;DC=[string]$script:DC;Credential=$script:cred;Prefix=[string]$script:PREFIXE;Tag=$tag;SiteOU=$siteOU
        ADLoaderSource=((Get-PestoADLoaderSource)+(Get-PestoNamingContextSource));ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    try{
        $started=Start-PestoAsyncOperation -Name 'SiteLookup' -ScriptBlock $script:PestoSiteLookupWorker -ArgumentList @($request) -Replace -TimeoutSec 60 `
        -CallbackContext ([pscustomobject]@{Key=$key}) -OnSuccess {param($r,$c) Complete-PestoSiteLookup -Result $r -Key $c.Key} `
        -OnError {param($e,$c) Complete-PestoSiteLookup -Failure $e -Key $c.Key}
        if(-not $started -and $script:SiteLookupState[$key].State -eq 'Loading'){Complete-PestoSiteLookup -Failure 'Lecture non démarrée : réessayez après les lectures en cours.' -Key $key}
    }catch{Complete-PestoSiteLookup -Failure $_ -Key $key}
}

function Complete-PestoSiteLookup {
    param($Result,$Failure,[string]$Key)
    if(-not $script:SiteLookupState){$script:SiteLookupState=@{}}
    if($Failure){
        $msg=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
        $script:SiteLookupState[$Key]=[pscustomobject]@{State='Failed';Error=(Protect-PestoLogText $msg)}
        try{Write-Log ('Lecture ciblée du site impossible ; la liste sera complétée par l''inventaire : '+$msg) 'WARN' $null 'AD'}catch{}
        # 19/10/2026 : une lecture lancée au démarrage pouvait échouer sans relance ; une seule relance automatique par site.
        if($Key -eq $script:SiteLookupKey){
            if(-not $script:SiteLookupRetried){$script:SiteLookupRetried=@{}}
            if(-not $script:SiteLookupRetried.ContainsKey($Key)){$script:SiteLookupRetried[$Key]=$true;Start-PestoSiteLookupRetry}
        }
        if($script:JoinUI -and (Get-Command Update-PestoJoinNames -ErrorAction SilentlyContinue)){Update-PestoJoinNames -NoLookup}
        return
    }
    if(-not $Result -or [string]$Result.Key -ne $Key){$script:SiteLookupState[$Key]=[pscustomobject]@{State='Failed';Error='Réponse du site incomplète.'};return}
    $script:SiteLookupState[$Key]=[pscustomobject]@{State='Ready';Error=(@($Result.Issues) -join ' ')}
    if($script:SiteLookupRetried){[void]$script:SiteLookupRetried.Remove($Key)}
    if(-not $script:SiteLookupCache){$script:SiteLookupCache=@{}}
    $script:SiteLookupCache[$Key]=if($Result.Complete){@($Result.Items)}else{@(Select-PestoUniqueComputers (@($script:SiteLookupCache[$Key])+@($Result.Items)))}
    $script:KnownComputersCache=$null;$script:SiteServiceCache=@{}
        $script:ComputersNoms=@(Select-PestoUniqueComputers (@($script:Computers)+@($script:DirectoryNameSnapshot)+@($script:AffectedNameSnapshot)+@(Get-PestoSiteLookupItems)));$script:NmUsedSrc=$null
    if(-not $script:SiteLookupInfo){$script:SiteLookupInfo=@{}}
    $script:SiteLookupInfo[$Key]=[pscustomobject]@{Tick=[Diagnostics.Stopwatch]::GetTimestamp();CollectedUtc=[string]$Result.CollectedUtc;Complete=[bool]$Result.Complete;Issues=@($Result.Issues);DC=[string]$Result.DC}
    if(-not $Result.Complete){Add-LogLine ('Lecture du site incomplète : '+(@($Result.Issues) -join ' ')+' Le candidat sera contrôlé dans AD avant toute opération.') 'warn'}
    try{Write-Log ('Lecture ciblée du site : '+@($Result.Items).Count+' poste(s) en '+[int]$Result.Ms+' ms.') 'INFO' $null 'AD'}catch{}
    # Pendant un traitement, les listes ne bougent pas : le cache sert au prochain calcul, et à l'ouverture de la liste des services.
    if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){$script:ServiceChoicesPending=$true;return}
    $script:ServiceChoicesPending=$false
    Build-NmIndex;Populate-NmFilters;Update-PestoServiceChoices;Update-NameGrid
}

function Update-PestoServiceItems {
    <# Recalcule la liste des services du site choisi depuis les postes connus (aucun appel AD), sans effacer la saisie.
       Renvoie $false si le formulaire n'a pas de site d'organisme choisi. #>
    $site="$($CbSite.SelectedItem)".Trim()
    if(-not($CbService -and $CbService.IsEnabled -and $script:OU_ORGANISME -and $site -and $site -ine 'PREPROD')){return $false}
    $prev=$script:Suspend;$script:Suspend=$true
    try{
        $text=[string]$CbService.Text
        $CbService.Items.Clear()
        foreach($e in @(Get-PestoSiteServiceCodes -OrganismeOU $script:OU_ORGANISME -Site $site -Computers (Get-PestoKnownComputers))){[void]$CbService.Items.Add($e)}
        $CbService.Text=$text
    }finally{$script:Suspend=$prev}
    return $true
}

function Update-PestoServiceChoices {
    <# Après chargement de l'inventaire : complète les listes de services déjà affichées, sans effacer la saisie,
       puis recalcule les noms proposés avec les postes désormais connus. #>
    try{
        if((Update-PestoServiceItems) -and -not $script:Suspend){Update-NameList}
    }catch{Write-Log "Liste des services non actualisée : $($_.Exception.Message)" 'WARN' $_ 'UI'}
    if($script:JoinUI -and (Get-Command Update-PestoJoinServices -CommandType Function -ErrorAction SilentlyContinue)){
        try{Update-PestoJoinServices;Update-PestoJoinNames -NoLookup;Update-PestoJoinUI}
        catch{Write-Log "Liste des services de jonction non actualisée : $($_.Exception.Message)" 'WARN' $_ 'UI'}
    }
}

function Request-PestoFormSiteLookup {
    <# Lecture ciblée du site choisi dans « Un poste » si elle n'est ni récente ni en cours. Jamais pendant un traitement. #>
    if($script:Suspend -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){return}
    $site="$($CbSite.SelectedItem)".Trim()
    if(-not($CbService -and $CbService.IsEnabled -and $script:OU_ORGANISME -and $site -and $site -ine 'PREPROD')){return}
    Request-PestoSiteLookup -OrganismeOU $script:OU_ORGANISME -Site $site
}

function Start-PestoSiteLookupRetry {
    if($script:SiteLookupRetryTimer){$script:SiteLookupRetryTimer.Stop()}
    else{$script:SiteLookupRetryTimer=New-Object Windows.Threading.DispatcherTimer;$script:SiteLookupRetryTimer.Add_Tick([EventHandler]${function:Invoke-PestoSiteLookupRetryTick})}
    $script:SiteLookupRetryTimer.Interval=[TimeSpan]::FromSeconds(3)
    $script:SiteLookupRetryTimer.Start()
}

function Invoke-PestoSiteLookupRetryTick {
    param($Sender,$EventArgs)
    $Sender.Stop()
    try{Request-PestoFormSiteLookup;if($script:JoinUI -and (Get-Command Request-PestoJoinSiteLookup -CommandType Function -ErrorAction SilentlyContinue)){Request-PestoJoinSiteLookup}}
    catch{Write-Log "Relance de la lecture du site impossible : $($_.Exception.Message)" 'WARN' $_ 'AD'}
}

function Invoke-PestoServiceDropDownOpened {
    <# Ouverture de la liste des services d'« Un poste » (19/10/2026, signalé par David) : au chargement d'un poste,
       la liste pouvait rester limitée au service du poste lui-même jusqu'à un aller-retour de site, la lecture ciblée
       du site ayant échoué ou abouti pendant un traitement. La liste est recalculée depuis le cache local et la lecture
       ciblée relancée si elle n'est ni récente ni en cours. Lecture seule, jamais pendant un traitement. #>
    if($script:Suspend -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){return}
    try{
        $pending=[bool]$script:ServiceChoicesPending;$script:ServiceChoicesPending=$false
        if(-not (Update-PestoServiceItems)){return}
        if($pending){Update-NameList}
        Request-PestoFormSiteLookup
    }catch{Write-Log "Liste des services non actualisée : $($_.Exception.Message)" 'WARN' $_ 'UI'}
}

function CheckOU {
    <# Vérifie qu'une OU existe ; renvoie $true/$false. #>
    param([string]$OU)
    if (-not (Test-PestoOUPath $OU)) { return $false }
    try {
        $adp = Get-ADParams
        Get-ADOrganizationalUnit -Identity $OU -ErrorAction Stop @adp | Out-Null
        return $true
    } catch {
        Write-Log "OU introuvable ou inaccessible : '$OU'." 'WARN' $_ 'AD'
        return $false
    }
}

function Get-PestoParentDN {
    param([string]$DistinguishedName)
    $p = @(Split-PestoDistinguishedName $DistinguishedName)
    if ($p.Count -lt 2) { throw 'Objet sans parent dans le DN.' }
    return ($p[1..($p.Count-1)] -join ',')
}

function Get-PestoDomainFromDN {
    param([string]$DistinguishedName)
    $p = @(Split-PestoDistinguishedName $DistinguishedName)
    $labels = New-Object 'System.Collections.Generic.List[string]'; $inDomain=$false
    foreach ($part in $p) {
        if ($part -match '^(?i:DC)=(.+)$') { $inDomain=$true; $labels.Add($Matches[1]) }
        elseif ($inDomain) { throw 'Un composant OU/CN ne peut pas suivre un composant DC.' }
    }
    if (-not $labels.Count) { throw 'Aucun composant DC dans le DN.' }
    $dns = $labels -join '.'
    if (-not (Test-PestoDnsName $dns)) { throw 'Composants DC invalides.' }
    return $dns.ToLowerInvariant()
}

function Split-PestoDistinguishedName {
    <# Sépare les RDN sans couper une virgule échappée. Profil DN AD simple,
       pas un normaliseur RFC 4514 complet : un format non supporté est refusé. #>
    param([AllowNull()][string]$Value)
    $dn = "$Value".Trim()
    if (-not $dn -or $dn -match '[\x00-\x1f\x7f]') { throw 'DN vide ou contenant un caractère de contrôle.' }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $sb = New-Object Text.StringBuilder
    for ($i=0; $i -lt $dn.Length; $i++) {
        $c = $dn[$i]
        if ($c -eq '\') {
            if ($i+1 -ge $dn.Length) { throw 'Échappement DN incomplet.' }
            [void]$sb.Append($c); $i++; [void]$sb.Append($dn[$i]); continue
        }
        if ($c -eq '+') { throw 'RDN multivalué non pris en charge dans les périmètres Pesto.' }
        if ($c -eq ',') {
            if (-not $sb.Length) { throw 'Composant DN vide.' }
            $parts.Add($sb.ToString().TrimStart()); [void]$sb.Clear()
        } else { [void]$sb.Append($c) }
    }
    if (-not $sb.Length) { throw 'Composant DN final vide.' }
    $parts.Add($sb.ToString().TrimStart())
    foreach ($part in $parts) {
        if ($part -notmatch '^(?i:OU|CN|DC)=(?:\\.|[^\\])+$') { throw "Composant DN non pris en charge : '$part'." }
    }
    return $parts.ToArray()
}

function ConvertTo-PestoFilterLiteral {
    param([AllowEmptyString()][string]$Text)
    # RowFilter LIKE possède sa propre grammaire. Échapper caractère par
    # caractère évite de rééchapper les crochets ajoutés à l'étape précédente.
    $sb=[Text.StringBuilder]::new()
    foreach($c in $Text.ToCharArray()) {
        switch($c) {
            "'" {[void]$sb.Append("''")}
            '[' {[void]$sb.Append('[[]')}
            ']' {[void]$sb.Append('[]]')}
            '*' {[void]$sb.Append('[*]')}
            '%' {[void]$sb.Append('[%]')}
            default {[void]$sb.Append($c)}
        }
    }
    return $sb.ToString()
}

$script:PestoDirectorySnapshotWorker = {
    param($Request)
    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'
    $limit=200000
    if($null -ne $Request.MaxInventoryRows){if(($Request.MaxInventoryRows -isnot [int] -and $Request.MaxInventoryRows -isnot [long]) -or $Request.MaxInventoryRows -lt 1 -or $Request.MaxInventoryRows -gt 200000){throw 'Limite de collecte invalide.'};$limit=[int]$Request.MaxInventoryRows}
    if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}

    if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Chargement du module Active Directory';Count=0;Unit=''}}
    $modulePath = [string]$Request.ADModulePath
    $adLoader=[string]$Request.ADLoaderSource
    if(-not $adLoader){throw 'Résolveur AD approuvé absent du worker.'}
    . ([scriptblock]::Create($adLoader))
    $identitySource=[string]$Request.IdentitySource
    if(-not $identitySource){throw 'Résolveur d''identité absent du worker.'}
    . ([scriptblock]::Create($identitySource))
    $projectionSource=[string]$Request.ProjectionSource
    if(-not $projectionSource){throw 'Règles de projection du périmètre absentes du worker.'}
    . ([scriptblock]::Create($projectionSource))
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)

    $domain = ([string]$Request.Domain).Trim()
    $dc = ([string]$Request.DC).Trim()
    if (-not $dc) {
        $located=Get-ADDomainController -DomainName $domain -Discover -Writable -Service ADWS -ForceDiscover -ErrorAction Stop
        $candidates=@($located.HostName)
        if($candidates.Count -ne 1 -or -not $candidates[0]){throw 'Aucun contrôleur inscriptible ADWS confirmé.'}
        $dc=([string]$candidates[0]).TrimEnd('.')
    }

    $adp = @{ Server=$dc }
    # Sans credential explicite, la cmdlet part avec l'identité du processus et le worker
    # ne peut avertir que par son exception : l'hôte ne collecte que Streams.Error.
    $identiteAD = if ($null -ne $Request.Credential) { $null } else { Get-PestoWindowsAuthIdentity }
    if ($null -ne $Request.Credential) { $adp.Credential = $Request.Credential }
    if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Connexion au domaine';Count=0;Unit=''}}
    try { $d = Get-ADDomain @adp -ErrorAction Stop } catch { throw (Add-PestoDomainIdentityCause $_ $identiteAD -HasExplicitCredential:($null -ne $Request.Credential)) }

    # -Server des cmdlets AD accepte le domaine comme localisateur, mais la
    # jonction Add-Computer doit recevoir un VRAI DC en FQDN sur les Windows
    # durcis récents. Si le fallback précédent était seulement le nom de domaine,
    # on fige donc le PDC Emulator retourné par AD pour le reste de la session.
    if (($dc -ieq $domain -or $dc -notmatch '\.') -and $d.PDCEmulator) {
        $dc = ([string]$d.PDCEmulator).TrimEnd('.')
        $adp.Server = $dc
    }

    if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Lecture des sites';Count=0;Unit=''}}
    $sites = @{};$siteMetadata=[Collections.Generic.List[object]]::new()
    foreach ($kv in $Request.OUSite.GetEnumerator()) {
        $base = [string]$kv.Value
        $children=@(Get-ADOrganizationalUnit -SearchBase $base -SearchScope OneLevel -Filter * -Properties ObjectGUID -ErrorAction Stop @adp)
        $sites[[string]$kv.Key]=@($children.Name|Sort-Object)
        foreach($child in $children){$siteMetadata.Add([pscustomobject]@{Org=[string]$kv.Key;Name=[string]$child.Name;DN=[string]$child.DistinguishedName;Guid=[string]$child.ObjectGUID;Root=$base})}
    }

    $root=@();$names=@();$readRoot=0;$readNames=0;$incremental=$null
    if([bool]$Request.FullInventory){$incremental=Get-PestoIncrementalInventory -Request $Request -DC $dc -Maximum $limit}
    if($incremental){$root=@($incremental.Root);$names=@($incremental.Names);$readRoot=$root.Count;$readNames=$names.Count}
    if([bool]$Request.FullInventory -and -not $incremental){
        $readRoot=0;$progressClock=[Diagnostics.Stopwatch]::StartNew()
        if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Inventaire des postes';Count=0;Unit='postes lus'}}
        $root=@(Get-ADComputer -Filter * -SearchBase ([string]$Request.RootOU) -SearchScope Subtree -Properties DistinguishedName,ObjectGUID -ResultPageSize 500 -ResultSetSize ($limit+1) -ErrorAction Stop @adp | ForEach-Object {
            if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
            $readRoot++;if($readRoot -gt $limit){throw 'Inventaire trop volumineux : aucun resultat partiel publie.'}
            if($Request.Progress -and ($readRoot -eq 1 -or $progressClock.ElapsedMilliseconds -ge 100)){$Request.Progress.State=[pscustomobject]@{Stage='Inventaire des postes';Count=$readRoot;Unit='postes lus'};$progressClock.Restart()}
            $_
        })
        $root=@(Select-PestoUniqueComputers $root)
        $names=if(Test-PestoDNWithinScope -DistinguishedName ([string]$Request.ScanOU) -Roots @([string]$Request.RootOU)){
            @(Select-PestoComputersInScope -Computers $root -Root ([string]$Request.ScanOU))
        }else{
            $readNames=0;$progressClock.Restart()
            if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Lecture du périmètre des noms';Count=0;Unit='postes lus'}}
            @(Get-ADComputer -Filter * -SearchBase ([string]$Request.ScanOU) -SearchScope Subtree -Properties DistinguishedName,ObjectGUID -ResultPageSize 500 -ResultSetSize ($limit+1) -ErrorAction Stop @adp | ForEach-Object {
                if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
                $readNames++;if($readNames -gt $limit){throw 'Perimetre de noms trop volumineux : aucun resultat partiel publie.'}
                if($Request.Progress -and ($readNames -eq 1 -or $progressClock.ElapsedMilliseconds -ge 100)){$Request.Progress.State=[pscustomobject]@{Stage='Lecture du périmètre des noms';Count=$readNames;Unit='postes lus'};$progressClock.Restart()}
                $_
            })
        }
    }

    if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
    $names=@(Select-PestoUniqueComputers $names)

    # Le poste local est résolu PENDANT le login. Ainsi la fenêtre principale
    # ne dépend d'aucune seconde requête AD pour devenir utilisable.
    if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Finalisation de la collecte';Count=@($names).Count;Unit='postes dans le périmètre des noms'}}
    $localComputer = $null
    $localName = ([string]$Request.LocalComputerName).Trim()
    if ($localName) {
        try {
            $localComputer = Get-ADComputer -Identity $localName -Properties DistinguishedName -ErrorAction Stop @adp
        } catch {
            # Le snapshot global reste exploitable même si l'objet local est hors
            # du périmètre ou momentanément introuvable. Un repli sera tenté ensuite.
            $localComputer = $null
        }
    }

    # Détection matériel locale hors thread WPF. Le premier Get-CimInstance ne
    # doit jamais figer le loading ni la fenêtre principale.
    $localPCType = $null
    if ([bool]$Request.IncludeLocalHardware) {
        $localPCType = 'Inconnu'
        try {
            $portableIds = @(8,9,10,11,12,14,18,21,30,31,32)
            $chassis = @((Get-CimInstance Win32_SystemEnclosure -OperationTimeoutSec 8 -ErrorAction Stop).ChassisTypes)
            foreach ($c in $chassis) {
                if([int]$c -in @(3,4,5,6,7,13,15,16,17,23,24,35,36)){$localPCType='Fixe'}
                if ([int]$c -in $portableIds) { $localPCType = 'Portable'; break }
            }
            if ($localPCType -ne 'Portable' -and (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) {
                $localPCType = 'Portable'
            }
        } catch { $localPCType = 'Inconnu' }
    }

    if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Inventaire annule.')}
    [pscustomobject]@{
        Complete=$true;RootReceived=$readRoot;NamesReceived=$readNames;MaxInventoryRows=$limit;SyncState=$(if($incremental){$incremental.State}else{$null})
        DC=$dc; Domain=[string]$d.DNSRoot; Netbios=[string]$d.NetBIOSName
        Sites=$sites;SiteMetadata=$siteMetadata.ToArray(); Root=@(if($Request.FullInventory){$root}elseif($localComputer){$localComputer}); Names=$names; LocalComputer=$localComputer
        LocalPCType=$localPCType;FullInventory=[bool]$Request.FullInventory;CollectedUtc=[DateTime]::UtcNow.ToString('o')
        Identity=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
}

$script:PestoSiteLookupWorker = {
    param($Request)
    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $adLoader=[string]$Request.ADLoaderSource
    if(-not $adLoader){throw 'Résolveur AD approuvé absent du worker.'}
    . ([scriptblock]::Create($adLoader))
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    $adp=@{Server=[string]$Request.DC}
    if($null -ne $Request.Credential){$adp.Credential=$Request.Credential}
    $prefix=[string]$Request.Prefix;$tag=[string]$Request.Tag;$siteOU=[string]$Request.SiteOU
    if($prefix -notmatch (Get-PestoFacetPattern Prefix) -or ($tag -and $tag -cnotmatch (Get-PestoFacetPattern Site))){throw 'Préfixe ou code site invalide.'}
    $items=[Collections.Generic.List[object]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $searches=[Collections.Generic.List[object]]::new()
    if($tag){[void]$searches.Add(@{LDAPFilter=('(name='+(New-PestoNameLdapPattern -Prefix $prefix -Site $tag)+')')})}
    if($siteOU){[void]$searches.Add(@{LDAPFilter=('(name='+(New-PestoNameLdapPattern -Prefix $prefix)+')');SearchBase=$siteOU;SearchScope='Subtree'})}
    $issues=[Collections.Generic.List[string]]::new()
    foreach($s in $searches){
        try{
            $found=@(Get-ADComputer @s -Properties DistinguishedName,ObjectGUID -ResultSetSize 5001 @adp)
            if($found.Count -gt 5000){$issues.Add('Limite de 5 000 résultats atteinte pour une recherche ciblée.')}
            foreach($o in $found){
                $dn=[string]$o.DistinguishedName
                if($dn -and $seen.Add($dn)){[void]$items.Add([pscustomobject]@{Name=[string]$o.Name;DistinguishedName=$dn;ObjectGUID=[string]$o.ObjectGUID})}
            }
        }catch{
            if(-not $s.ContainsKey('SearchBase')){throw}
            $issues.Add('OU du site non lue : '+$_.Exception.Message)
        }
    }
    [pscustomobject]@{Key=[string]$Request.Key;Items=$items.ToArray();Ms=[int]$clock.ElapsedMilliseconds;Complete=($issues.Count -eq 0);Issues=$issues.ToArray();CollectedUtc=[DateTime]::UtcNow.ToString('o');DC=[string]$Request.DC}
}

function Test-PestoCompactNameIndex {
    try {Initialize-PestoRuntimeTypes;return [bool]('Pesto.Inventory.CompactIndex' -as [type])}catch{return $false}
}
function Get-PestoNameInventoryIndexTable {
    <# Repli livre : tables PowerShell, analyse facette par facette par ConvertTo-PestoNameParts.
       Ne met pas le cache en place : c'est Get-PestoNameInventoryIndex qui le pose. #>
    param([array]$Computers)
    $bases=@{};$sites=@{};$entries=[Collections.Generic.List[object]]::new()
    foreach($computer in @($Computers)){
        $parts=ConvertTo-PestoNameParts ([string]$computer.Name) -CurrentName
        if(-not $parts){continue}
        if(-not $bases.ContainsKey($parts.Base)){$bases[$parts.Base]=[Collections.Generic.HashSet[int]]::new()}
        [void]$bases[$parts.Base].Add([int]$parts.Number)
        if(-not $sites.ContainsKey($parts.Site)){$sites[$parts.Site]=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
        [void]$sites[$parts.Site].Add([string]$parts.Service)
        $entries.Add([pscustomobject]@{Parts=$parts;Computer=$computer})
    }
    return [pscustomobject]@{ByBase=$bases;BySite=$sites;Entries=$entries.ToArray()}
}
function Get-PestoNameInventoryIndexCompact {
    <# Meme index que la table PowerShell, construit en une passe par Pesto.Inventory.CompactIndex :
       meme normalisation (Trim puis ToUpperInvariant), meme regex portee par la layout active, memes
       comparateurs d'ordinal insensible a la casse. Retourne $null si le type n'est pas charge. #>
    param([array]$Computers)
    if(-not('Pesto.Inventory.CompactIndex' -as [type])){return $null}
    $source=@($Computers)
    $layout=Get-PestoNamingLayout
    $names=[string[]]::new($source.Count)
    for($i=0;$i -lt $source.Count;$i++){$names[$i]=[string]$source[$i].Name}
    $built=[Pesto.Inventory.CompactIndex]::Build($names,[string]$layout.Pattern,[int]$layout.Length,[int]$layout.NumberOffset,[int]$layout.NumberWidth)
    $entries=[Collections.Generic.List[object]]::new()
    foreach($row in $built.Rows){
        $parts=[pscustomobject]@{Name=$row.Name;Type=$row.Type;Prefix=$row.Prefix;Site=$row.Site;Service=$row.Service;
            Number=$row.Number;NumberText=$row.NumberText;Base=$row.Base;Series=$row.Series;Label=$row.Label}
        $entries.Add([pscustomobject]@{Parts=$parts;Computer=$source[$row.SourceIndex]})
    }
    return [pscustomobject]@{ByBase=$built.ByBase;BySite=$built.BySite;Entries=$entries.ToArray()}
}
function Get-PestoNameInventoryIndex {
    param([array]$Computers)
    if($script:NameInventoryIndex -and [object]::ReferenceEquals($script:NameInventorySource,$Computers)){return $script:NameInventoryIndex}
    $index=$null
    if(Test-PestoCompactNameIndex){try{$index=Get-PestoNameInventoryIndexCompact $Computers}catch{$index=$null}}
    if($null -eq $index){$index=Get-PestoNameInventoryIndexTable $Computers}
    $script:NameInventorySource=$Computers;$script:NameInventoryIndex=$index
    return $index
}
function Get-PestoDataAgeText {
    param([string]$Utc,[bool]$Complete=$true,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $stamp=[DateTimeOffset]::MinValue
    if(-not $Utc -or -not [DateTimeOffset]::TryParse($Utc,[ref]$stamp)){return 'Données non chargées'}
    $seconds=[Math]::Max(0,[int]($Now-$stamp).TotalSeconds)
    $age=if($seconds -lt 60){[string]$seconds+' s'}elseif($seconds -lt 3600){[string][int][Math]::Floor($seconds/60)+' min'}else{[string][int][Math]::Floor($seconds/3600)+' h'}
    $state=if(-not $Complete){'lecture incomplète'}elseif($seconds -ge 120){'à actualiser'}else{'récent'}
    return ('Données : '+$age+' · '+$state)
}
function Request-PestoCurrentSiteRefresh {
    param($Sender,$EventArgs)
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning){return}
    if($MainTabs.SelectedIndex -eq 1){
        $site=[string]$NmCmbSite.SelectedItem
        if($site -and $site -ne '(tous)'){Request-PestoSiteLookup -Site $site -OrganismeOU '' -Force}else{[void](Refresh-Names)}
    }elseif($MainTabs.SelectedIndex -eq 7 -and $script:JoinUI){
        $org=[string]$script:JoinUI.Org.SelectedItem;$site=[string]$script:JoinUI.Site.SelectedItem
        Request-PestoSiteLookup -Site $site -OrganismeOU ([string]$script:OUV[$org]) -Force
    }else{Request-PestoSiteLookup -Site ([string]$CbSite.SelectedItem) -OrganismeOU ([string]$script:OU_ORGANISME) -Force}
}
function Request-PestoAffectedRefresh {
    param([string[]]$Names)
    if($script:GUI -or $script:SIM -or -not $script:DC -or (Test-PestoQueueWorkerStillActive)){return}
    $namesToRead=@($Names|Where-Object{Test-PestoComputerName $_}|Sort-Object -Unique)
    if(-not $namesToRead.Count){return}
    $script:SiteLookupInfo=@{} # Tous les caches ciblés deviennent anciens ; aucune disparition implicite de nom connu.
    $request=[pscustomobject]@{Names=$namesToRead;DC=$script:DC;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Source=(Get-PestoWorkerCoreSource)}
    [void](Start-PestoAsyncOperation -Name 'AffectedRefresh' -ScriptBlock {
        param($Request);. ([scriptblock]::Create($Request.Source));Import-PestoADModule $Request.ADModulePath
        $adp=@{Server=$Request.DC;ErrorAction='Stop'};if($Request.Credential){$adp.Credential=$Request.Credential}
        $found=[Collections.Generic.List[object]]::new()
        foreach($name in $Request.Names){if(-not(Test-PestoComputerName $name)){throw 'Nom à actualiser invalide.'};foreach($c in @(Get-ADComputer -LDAPFilter ('(|(name='+$name+')(sAMAccountName='+$name+'$))') -ResultSetSize 3 @adp)){$found.Add($c)}}
        [pscustomobject]@{Items=$found.ToArray();Utc=[DateTime]::UtcNow.ToString('o')}
    } -ArgumentList @($request) -Replace -TimeoutSec 90 `
      -OnSuccess {param($r,$c)
        # Conserver les noms anciens jusqu'à une lecture complète : réplication et redémarrage peuvent être différés.
        $script:AffectedNameSnapshot=@(Select-PestoUniqueComputers (@($script:AffectedNameSnapshot)+@($r.Items)))
        $script:ComputersNoms=@(Select-PestoUniqueComputers (@($script:ComputersNoms)+@($script:AffectedNameSnapshot)));$script:NmUsedSrc=$null;$script:KnownComputersCache=$null
        Build-NmIndex;Populate-NmFilters;Update-PestoServiceChoices;Update-NameGrid
        Add-LogLine ('Lecture ciblée après opération : '+@($r.Items).Count+' objet(s). Les anciens noms restent exclus jusqu''au prochain inventaire complet.') 'info'
      } -OnError {param($e,$c);Add-LogLine ('Actualisation ciblée interrompue : '+(Protect-PestoLogText ([string]$e))+'. Le cache conserve les noms connus ; actualisez avant de préparer un nouveau poste.') 'warn'})
}
