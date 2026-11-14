# Pesto 1.0 : jonction locale directe. Ce fichier définit des fonctions ;
# Compatibilité : les clés de stockage/verrous GP sont stables ; ne pas les renommer ni les effacer. Voir docs/RENOMMAGE_PESTO.md (DEV).
# aucune jonction, élévation ni lecture AD n'est lancée au chargement.

function Get-PestoJoinPlanErrors {
    param($Plan)
    $errors=[Collections.Generic.List[string]]::new()
    if($null -eq $Plan){$errors.Add('Complétez le formulaire.');return $errors.ToArray()}
    if($null -ne $Plan.AllowExisting -and $Plan.AllowExisting -isnot [bool]){$errors.Add('Option de compte précréé non typée.')}
    $planPolicy=ConvertTo-PestoPolicy $script:PestoPolicy
    if($Plan.AllowExisting -and -not ($planPolicy.AllowPrecreatedJoin -or ([bool]$Plan.ReservedByPesto -and $planPolicy.ReserveNamesInAD))){$errors.Add('Réutilisation désactivée par la politique.')}

    if(-not(Test-PestoComputerName ([string]$Plan.Computer)) -or $Plan.Computer -ine $env:COMPUTERNAME){$errors.Add('La jonction concerne uniquement ce PC.')}
    if(-not(Test-PestoGeneratedComputerName ([string]$Plan.NewName))){$errors.Add('Choisissez un nom conforme à la convention de nommage.')}
    if(-not(Test-PestoDnsName ([string]$Plan.Domain)) -or ([string]$Plan.Domain).IndexOf('.') -lt 1){$errors.Add('Le domaine cible doit être un nom DNS complet.')}
    if(-not(Test-PestoOUPath ([string]$Plan.TargetOU)) -or -not(Test-PestoOUInConfiguredScope ([string]$Plan.TargetOU))){$errors.Add('L''emplacement AD doit appartenir au périmètre configuré.')}
    else {try{if((Get-PestoDomainFromDN $Plan.TargetOU) -ine $Plan.Domain){$errors.Add('Le domaine de l''OU ne correspond pas au domaine cible.')}}catch{$errors.Add('Le chemin AD est invalide.')}}
    if(-not $Plan.DirectProd -and $Plan.TargetOU -ine $script:OU['PREPROD']){$errors.Add('La configuration impose la zone de préparation.')}
    return $errors.ToArray()
}

function Get-PestoJoinPlanKey {
    param($Plan)
    if(-not $Plan){return ''}
    $text=@($Plan.Computer,$Plan.NewName,$Plan.Domain,$Plan.DC,$Plan.TargetOU,$Plan.DirectProd,$Plan.Account,[string]$Plan.AllowExisting) -join '|'
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}
    finally{$sha.Dispose()}
}

function Get-PestoJoinLocalStatus {
    # L'échec d'une lecture n'est jamais interprété comme un PC hors domaine.
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    if(@($cs).Count -ne 1 -or $cs.PartOfDomain -isnot [bool] -or
        ($cs.DomainRole -isnot [uint16] -and $cs.DomainRole -isnot [uint32] -and $cs.DomainRole -isnot [int]) -or
        $cs.DomainRole -notin @(0,1,2,3,4,5) -or -not $cs.Name){throw 'État local incomplet : aucune jonction autorisée.'}
    $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    if(-not $active -or -not $configured -or -not $machine){throw 'Identité Windows non déterminée.'}
    # LastBootUpTime CIM varie lors d'une correction de l'horloge. L'événement
    # natif de démarrage reste immuable ; ne jamais déduire un reboot de cette dérive.
    $bootEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-General';Id=12} -MaxEvents 1 -ErrorAction Stop)
    if($bootEvents.Count -ne 1 -or $bootEvents[0].Id -ne 12 -or $bootEvents[0].ProviderName -ine 'Microsoft-Windows-Kernel-General'){throw 'Événement de démarrage Windows non déterminé. Aucune jonction autorisée.'}
    [xml]$bootXml=$bootEvents[0].ToXml()
    $startNodes=$bootXml.SelectNodes('/*[local-name()="Event"]/*[local-name()="EventData"]/*[local-name()="Data" and @Name="StartTime"]')
    if($startNodes.Count -ne 1 -or $startNodes[0].InnerText -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$'){throw 'Date de démarrage Windows invalide. Aucune jonction autorisée.'}
    $bootDate=[Xml.XmlConvert]::ToDateTime($startNodes[0].InnerText,[Xml.XmlDateTimeSerializationMode]::RoundtripKind).ToUniversalTime()
    if($bootDate -gt [DateTime]::UtcNow){throw 'Chronologie Windows incohérente : vérifiez l''horloge avant toute jonction.'}
    [pscustomobject]@{
        Manufacturer=[string]$cs.Manufacturer;Model=[string]$cs.Model;CollectedUtc=[DateTime]::UtcNow.ToString('o')
        Computer=([string]$cs.Name).ToUpperInvariant();PartOfDomain=[bool]$cs.PartOfDomain
        Domain=([string]$cs.Domain).Trim();ActiveName=$active;ConfiguredName=$configured
        PendingRename=($active -ine $configured);MachineId=$machine
        BootUtc=$bootDate.ToString('o')
        Admin=(Test-PestoIsAdministrator);SecureChannel=$null;DomainRole=[int]$cs.DomainRole
    }
}

function Get-PestoJoinStatePath {
    # Partagé entre les comptes UAC et les installations Pesto sur CE poste.
    $base=[Environment]::GetFolderPath('CommonApplicationData')
    if(-not $base){throw 'Dossier ProgramData introuvable.'}
    return [IO.Path]::Combine($base,'GP','Join','receipt.json')
}

function Read-PestoJoinReceipt {
    param([string]$Path)
    $ancestor=[IO.Path]::GetDirectoryName($Path)
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){
            if((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Le stockage de jonction traverse un lien ou une jonction.'}
        }
        $next=[IO.Path]::GetDirectoryName($ancestor);if($next -eq $ancestor){break};$ancestor=$next
    }
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 65536){throw 'Le reçu de jonction est invalide. Vérification manuelle nécessaire.'}
    $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    return Assert-PestoJoinReceiptData $r
}

function Write-PestoJoinReceipt {
    param([string]$Path,$Receipt)
    $folder=[IO.Path]::GetDirectoryName($Path)
    # Aucun lien/jonction suivi dans le chemin de stockage des états machine.
    $ancestor=$folder
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){
            $item=Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Le stockage du reçu ne peut pas traverser une jonction ou un lien.'}
        }
        $next=[IO.Path]::GetDirectoryName($ancestor);if($next -eq $ancestor){break};$ancestor=$next
    }
    $created=$false
    if(-not(Test-Path -LiteralPath $folder)){
        [void][IO.Directory]::CreateDirectory($folder)
        $created=$true
    }
    # Identifiants SID indépendants de la langue de Windows. Pas de mot de passe
    # dans le reçu ; seuls SYSTEM et les administrateurs peuvent le modifier.
    # Droits relus à chaque écriture ; réappliqués sauf s'ils sont déjà exactement conformes.
    $needsAcl=$true
    if(-not $created){
        $currentAcl=Get-Acl -LiteralPath $folder -ErrorAction Stop
        $isProtected=$currentAcl.AreAccessRulesProtected
        $rules=$currentAcl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])
        
        $expectedSids=@('S-1-5-18','S-1-5-32-544')
        $foundSids=@()
        $hasExtraRules=$false
        
        foreach($rule in $rules){
            if($rule.AccessControlType -ne 'Allow'){
                $hasExtraRules=$true
                continue
            }
            $sidStr=$rule.IdentityReference.Value
            if($expectedSids -contains $sidStr){
                if($rule.FileSystemRights -eq 'FullControl' -and 
                   $rule.InheritanceFlags -eq 'ContainerInherit, ObjectInherit' -and
                   $rule.PropagationFlags -eq 'None'){
                    $foundSids+=$sidStr
                } else {
                    $hasExtraRules=$true # Mauvais droits sur un SID attendu
                }
            } else {
                $hasExtraRules=$true # Règle en trop
            }
        }
        
        # Conforme si : héritage protégé, les 2 SID distincts présents avec les bons droits, et aucune règle en trop.
        if($isProtected -and (@($foundSids|Select-Object -Unique).Count -eq 2) -and (-not $hasExtraRules)){
            $needsAcl=$false
        }
    }

    if($needsAcl){
        $acl=[Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true,$false)
        foreach($sid in @('S-1-5-18','S-1-5-32-544')){
            $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            [void]$acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $folder -AclObject $acl -ErrorAction Stop
    }
    if(Test-Path -LiteralPath $Path){
        $item=Get-Item -LiteralPath $Path -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Un reçu lié ne peut pas être remplacé.'}
    }
    Write-PestoAtomicText -Path $Path -Text ($Receipt|ConvertTo-Json -Depth 8)
    # Le reçu durable reste autoritaire même si le transport d'audit échoue.
    try { [void](Invoke-PestoAuditSinkReceipt -Receipt $Receipt) } catch {
        try { [void](Write-Log -Message 'Transport d''audit indisponible ; reçu local conservé.' -Level WARN -Context AuditSink) } catch {}
    }
}

function Get-PestoJoinReceiptDecision {
    param($Receipt,$Local,[string]$Domain)
    if(-not $Receipt){return [pscustomobject]@{Blocked=$false;Phase='None';Message='Aucune jonction Pesto en attente.'}}
    [void](Assert-PestoJoinReceiptData $Receipt)
    if(-not $Local -or $Receipt.MachineId -ine $Local.MachineId -or $Receipt.Domain -ine $Domain){throw 'Le reçu ne correspond pas à ce PC et au domaine configuré.'}
    if($Receipt.Phase -eq 'Failed'){return [pscustomobject]@{Blocked=$false;Phase='Failed';Message='La demande précédente a été refusée. Nouvelle vérification complète obligatoire.'}}
    if($Receipt.Phase -eq 'Verified'){return [pscustomobject]@{Blocked=$false;Phase='Verified';Message='Jonction vérifiée précédemment. Cette mention ne remplace pas une nouvelle lecture AD.'}}
    if(Test-PestoAcknowledgedReceipt $Receipt){return [pscustomobject]@{Blocked=$false;Phase='Acknowledged';Message=('Jonction précédente acquittée par '+[string]$Receipt.Acknowledged.By+' ('+[string]$Receipt.Acknowledged.Utc+') : résultat réel conservé, jamais compté comme réussi. Nouvelle vérification complète avant tout ajout.')}}
    $before=[DateTimeOffset]::Parse($Receipt.BootUtc,[Globalization.CultureInfo]::InvariantCulture)
    $boot=[DateTimeOffset]::MinValue
    $later=[DateTimeOffset]::TryParse([string]$Local.BootUtc,[ref]$boot) -and $boot -gt $before -and $boot -gt [DateTimeOffset]::Parse($Receipt.Utc,[Globalization.CultureInfo]::InvariantCulture)
    $isMatch=($Local.PartOfDomain -is [bool] -and $Local.PartOfDomain -and $Local.DomainRole -in @(1,3) -and
        $Local.Domain -ieq $Receipt.Domain -and (Test-PestoComputerName ([string]$Local.Computer)) -and
        $Local.ActiveName -ieq $Local.Computer -and $Local.ConfiguredName -ieq $Local.Computer -and -not $Local.PendingRename)
    if((Test-PestoOptionalPostCheckReceipt $Receipt) -and $isMatch -and $later -and $Local.SecureChannel -is [bool] -and $Local.SecureChannel){
        return [pscustomobject]@{Blocked=$false;Phase='ReadyToObserve';Message='Windows et canal sécurisé concordants après redémarrage. Vérification complémentaire facultative dans Interventions ; reçu conservé sans certification AD.'}
    }
    if($Receipt.Phase -eq 'PendingRestart' -and -not $later){return [pscustomobject]@{Blocked=$true;Phase='PendingRestart';Message='Ajout accepté. Redémarrez explicitement ; la vérification complémentaire reste facultative.'}}
    return [pscustomobject]@{Blocked=$true;Phase='Uncertain';Message='Jonction précédente à vérifier. Aucune nouvelle tentative automatique.'}
}

function Get-PestoJoinReceiptStatus {
    param($Receipt,[string]$Domain)
    # Lecture fraîche, commune au statut UI et au verrou juste avant la prochaine mutation.
    $local=Get-PestoJoinLocalStatus
    $decision=Get-PestoJoinReceiptDecision -Receipt $Receipt -Local $local -Domain $Domain
    if((Test-PestoOptionalPostCheckReceipt $Receipt) -and $local.PartOfDomain -and $local.DomainRole -in @(1,3) -and
        [DateTimeOffset]::Parse($local.BootUtc) -gt [DateTimeOffset]::Parse($Receipt.BootUtc) -and
        [DateTimeOffset]::Parse($local.BootUtc) -gt [DateTimeOffset]::Parse($Receipt.Utc) -and
        (Test-PestoComputerName ([string]$local.Computer)) -and $local.ActiveName -ieq $local.Computer -and
        $local.ConfiguredName -ieq $local.Computer -and $local.Domain -ieq $Receipt.Domain -and -not $local.PendingRename){
        $secure=Test-ComputerSecureChannel -Server $Receipt.DC -ErrorAction Stop
        if($secure -isnot [bool]){throw 'Réponse de canal sécurisé non booléenne.'}
        $local.SecureChannel=$secure
        $decision=Get-PestoJoinReceiptDecision -Receipt $Receipt -Local $local -Domain $Domain
    }
    return [pscustomobject]@{Local=$local;Receipt=$Receipt;Decision=$decision}
}

function Get-PestoJoinGuidance {
    param([string]$Message)
    switch -Regex ($Message){
        '(?i)(0xAAC|2732|reuse|r.utilis|account.*exists)' {return 'Un compte ordinateur existe peut-être déjà. Faire vérifier son propriétaire et les règles de réutilisation AD. Pesto ne le supprime pas.'}
        '(?i)(access.*denied|acc.s.*refus|0x5\b)' {return 'Vérifier les droits du compte AD sur l''OU et le jeton administrateur local. Aucun nouvel essai automatique.'}
        '(?i)(DNS|1355|domain.*not|domaine.*introuvable|serveur.*op.rationnel)' {return 'Vérifier le DNS du réseau d''entreprise, la connexion/VPN et le contrôleur de domaine configuré.'}
        '(?i)(RPC|0x800706ba|timed?\s*out|d.lai)' {return 'La communication a été interrompue. Une commande peut avoir été acceptée : examiner l''état local et AD avant toute relance.'}
        default {return 'Lire le détail et le journal. Une vérification préalable ne garantit pas les droits d''écriture au moment de l''ajout.'}
    }
}

function Get-PestoJoinPreflight {
    param($Request)
    if((ConvertTo-PestoPolicy $Request.Policy).IncidentMode){throw 'Mode incident : jonction suspendue. Les diagnostics restent disponibles.'}
    Assert-PestoJoinADReservationResolved -Plan $Request.Plan
    $checks=[Collections.Generic.List[object]]::new()
    $plan=$Request.Plan
    $errors=@(Get-PestoJoinPlanErrors $plan)
    foreach($errorText in $errors){$checks.Add([pscustomobject]@{Check='Formulaire';State='Bloqué';Detail=$errorText})}
    if($errors.Count){return [pscustomobject]@{Valid=$false;Checks=$checks.ToArray();Local=$null;Receipt=$null;Decision=$null;Key=(Get-PestoJoinPlanKey $plan)}}
    $local=Get-PestoJoinLocalStatus
    $receipt=Read-PestoJoinReceipt -Path $Request.StatePath
    $decision=Get-PestoJoinReceiptDecision -Receipt $receipt -Local $local -Domain $plan.Domain
    $checks.Add([pscustomobject]@{Check='Ce PC';State=$(if($local.PartOfDomain){'Bloqué'}else{'OK'});Detail=$(if($local.PartOfDomain){"Déjà membre de $($local.Domain). Aucune sortie de domaine ne sera tentée."}else{"$($local.Computer) est hors domaine."})})
    $checks.Add([pscustomobject]@{Check='Élévation locale';State=$(if($local.Admin){'OK'}else{'Bloqué'});Detail=$(if($local.Admin){'Le processus est administrateur local.'}else{'Relancez Pesto pour autoriser l''UAC avant la connexion.'})})
    $checks.Add([pscustomobject]@{Check='Opération précédente';State=$(if($decision.Blocked -or $local.PendingRename){'Bloqué'}else{'OK'});Detail=$(if($local.PendingRename){'Un changement de nom attend un redémarrage.'}else{$decision.Message})})
    if($null -eq $Request.Credential){$checks.Add([pscustomobject]@{Check='Compte AD';State='Bloqué';Detail='Le mode hors domaine requiert le compte AD saisi à la connexion.'})}
    else{$checks.Add([pscustomobject]@{Check='Compte AD';State='OK';Detail=$Request.Credential.UserName})}
    if(@($checks|Where-Object{$_.State -eq 'Bloqué'}).Count){return [pscustomobject]@{Valid=$false;Checks=$checks.ToArray();Local=$local;Receipt=$receipt;Decision=$decision;Key=(Get-PestoJoinPlanKey $plan)}}
    Set-PestoWorkerStage 'Contrôle du domaine et de l''emplacement' $plan.Domain
    $dc=([string]$plan.DC).Trim().TrimEnd('.')
    if(-not(Test-PestoDnsName $dc) -or $dc.IndexOf('.') -lt 1 -or $dc -ieq $plan.Domain){throw 'Un contrôleur de domaine FQDN explicite est requis.'}
    $adp=@{Server=$dc;Credential=$Request.Credential;ErrorAction='Stop'}
    $domain=Get-ADDomain @adp
    if($domain.DNSRoot -ine $plan.Domain){throw 'Le contrôleur contacté ne correspond pas au domaine du plan.'}
    $checks.Add([pscustomobject]@{Check='Domaine';State='OK';Detail="Lecture AD réussie sur $dc."})
    $clock=Get-PestoJoinClockCheck -DC $dc -Policy (ConvertTo-PestoPolicy $Request.Policy)
    if($clock){$checks.Add($clock)}
    $ou=Get-ADOrganizationalUnit -Identity $plan.TargetOU @adp
    if(-not $ou -or $ou.DistinguishedName -ine $plan.TargetOU){throw 'L''OU demandée n''a pas pu être confirmée.'}
    $destinationId=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$ou.ObjectGUID,[ref]$destinationId) -or $destinationId -eq [Guid]::Empty){throw 'Identité de l''OU de jonction inconnue.'}
    $checks.Add([pscustomobject]@{Check='Emplacement réel';State='OK';Detail=$plan.TargetOU})
    # Plan validé : nom et DNS contiennent uniquement des caractères autorisés.
    $name=[string]$plan.NewName;$fqdn=$name+'.'+$plan.Domain
    $ldap='(|(name='+$name+')(sAMAccountName='+$name+'$)(dNSHostName='+$fqdn+'))'
    $existing=@(Get-ADComputer -LDAPFilter $ldap -SearchBase $domain.DistinguishedName -SearchScope Subtree @adp)
    $existingId='';$existingAllowed=$false
    if($plan.AllowExisting){
        $policy=ConvertTo-PestoPolicy $Request.Policy
        $reservedByPesto=([bool]$plan.ReservedByPesto -and $policy.ReserveNamesInAD)
        if(-not ($policy.AllowPrecreatedJoin -or $reservedByPesto)){throw 'Le parcours précréé n''est pas autorisé.'}
        if($existing.Count -eq 1 -and $existing[0].Name -ieq $name -and (Get-PestoParentDN $existing[0].DistinguishedName) -ieq $plan.TargetOU -and
           (-not $reservedByPesto -or ([Guid]$existing[0].ObjectGUID).ToString('D') -ieq [string]$plan.ReservedGuid)){
            $existingId=([Guid]$existing[0].ObjectGUID).ToString('D');$existingAllowed=$true
        }
        if($reservedByPesto){$checks.Add([pscustomobject]@{Check='Nom réservé dans l''AD';State=$(if($existingAllowed){'OK'}else{'Bloqué'});Detail='Compte créé par Pesto pour cette mise au domaine, identifié par son GUID dans l''OU choisie.'})}
        else{$checks.Add([pscustomobject]@{Check='Compte précréé';State=$(if($existingAllowed){'OK'}else{'Bloqué'});Detail='Un compte exact dans l''OU choisie est obligatoire. Windows validera la politique Netjoin ; aucun propriétaire ni droit ne sera changé.'})}
    }
    $nameBlocked=($existing.Count -gt 0 -and -not $existingAllowed)
    # Nom pris : tous les noms déjà utilisés de la même série selon la convention active dans tout le domaine, en une requête,
    # pour proposer directement le premier numéro réellement libre au lieu d'essayer les suivants un par un.
    $seriesTaken=@()
    if($nameBlocked -and (ConvertTo-PestoNameParts $name)){
        $parts=ConvertTo-PestoNameParts $name;$series=$parts.Base
        $ldapSeries=New-PestoNameLdapPattern -Prefix $parts.Prefix -Site $parts.Site -Service $parts.Service -Type $parts.Type
        # Lecture d'appoint : si elle échoue, le contrôle reste valable et le nom suivant sera vérifié à son tour.
        try{
            $seriesTaken=@(Get-ADComputer -LDAPFilter ('(|(name='+$ldapSeries+')(sAMAccountName='+$ldapSeries+'$)(dNSHostName='+$ldapSeries+'.*))') -SearchBase $domain.DistinguishedName -SearchScope Subtree -Properties DNSHostName,SamAccountName -ResultSetSize 2000 @adp |
                ForEach-Object{foreach($v in @([string]$_.Name,([string]$_.SamAccountName).TrimEnd('$'),(([string]$_.DNSHostName) -split '\.')[0])){if($v){$v.ToUpperInvariant()}}} |
                Where-Object{(Get-PestoNameSeriesBase $_) -ceq $series} | Sort-Object -Unique)
        }catch{$seriesTaken=@()}
    }
    $checks.Add([pscustomobject]@{Check='Nouveau nom';State=$(if($nameBlocked){'Bloqué'}else{'OK'});Detail=$(if($existingAllowed){'Compte précréé identifié par GUID. Autorisation finale laissée à Windows.'}elseif($existing.Count){'Nom déjà utilisé. Aucun objet supprimé.'}else{'Nom absent au moment du contrôle, pas réservé dans AD.'})})
    return [pscustomobject]@{Valid=(@($checks|Where-Object{$_.State -eq 'Bloqué'}).Count -eq 0);Checks=$checks.ToArray();Local=$local;Receipt=$receipt;Decision=$decision;Key=(Get-PestoJoinPlanKey $plan);SeriesTaken=$seriesTaken;TargetOUGuid=$destinationId.ToString('D');ExistingGuid=$existingId}
}

function Invoke-PestoJoinExecuteLocked {
    param($Request)
    # Vérifications fraîches sur un plan figé après confirmation de l'opérateur.
    if($Request.ReadOnly -or $env:PESTO_READONLY_SESSION -eq '1'){throw 'Consultation : jonction interdite.'}
    $check=Get-PestoJoinPreflight -Request $Request
    if(-not $check.Valid){return [pscustomobject]@{Action=(New-ActionResult 96 'Une vérification a changé. Aucun ajout lancé.');Check=$check;Receipt=$null}}
    if(-not $Request.ConfirmedTargetOUGuid -or $check.TargetOUGuid -ine $Request.ConfirmedTargetOUGuid -or
       [string]$check.ExistingGuid -cne [string]$Request.ConfirmedExistingGuid -or $check.Local.MachineId -ine $Request.ConfirmedMachineId){
        throw 'Identité de l''OU, du compte précréé ou du PC modifiée depuis confirmation. Aucun ajout lancé.'
    }
    Assert-PestoWorkerMayContinue
    $plan=$Request.Plan
    $fresh=Get-PestoJoinLocalStatus
    if($fresh.PartOfDomain -or $fresh.PendingRename -or -not $fresh.Admin -or $fresh.Computer -ine $plan.Computer -or $fresh.MachineId -ine $check.Local.MachineId -or $fresh.BootUtc -ne $check.Local.BootUtc){
        return [pscustomobject]@{Action=(New-ActionResult 96 'L''etat Windows a change pendant le controle. Aucun ajout lance.');Check=$check;Receipt=$null}
    }
    $ledgerPlan=[pscustomobject]@{Nom_du_PC=$plan.Computer;Nouveau_Nom=$plan.NewName;OU_Actuelle='';OU_Destination=$plan.TargetOU;Objet_GUID=[string]$check.ExistingGuid;TargetOUGuid=$check.TargetOUGuid;Domain=$plan.Domain;DC=$plan.DC;ConfigStamp=$Request.ConfigStamp;Renommer=$false;Deplacer=$false;Reboot=$false;Metadata=$(if($Request.Metadata){ConvertTo-PestoDeploymentMetadata $Request.Metadata}else{$null})}
    # Politique contrôlée avant tout reçu : un refus ne laisse aucune barrière persistante.
    Assert-PestoOperationPolicy -Plan $ledgerPlan -Policy $Request.Policy
    $receipt=[pscustomobject]@{Schema=1;Version='1.0';OperationId=$Request.OperationId;Phase='Running';Utc=[DateTime]::UtcNow.ToString('o');MachineId=$check.Local.MachineId;BootUtc=$check.Local.BootUtc;Computer=$plan.Computer;NewName=$plan.NewName;Domain=$plan.Domain;OU=$plan.TargetOU;DC=$plan.DC;Account=$plan.Account;Message='Demande préparée, résultat non encore reçu.'}
    if($Request.Metadata){$receipt|Add-Member NoteProperty Metadata (ConvertTo-PestoDeploymentMetadata $Request.Metadata)}
    # Une impossibilité d'enregistrer le reçu bloque AVANT Add-Computer.
    Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $receipt
    try{
        Assert-PestoWorkerMayContinue
        Start-PestoIntervention -Plan $ledgerPlan -OperationId $Request.OperationId
        Set-PestoEffect -Name TargetMachineId -Value $check.Local.MachineId
        Set-PestoInitialJoinObservation -Local $fresh -ExistingGuid ([string]$check.ExistingGuid)
        $script:ExpectedJoinAccountGuid=[string]$check.ExistingGuid
        $joinPolicy=ConvertTo-PestoPolicy $Request.Policy
        $script:AllowPrecreatedJoin=([bool]$plan.AllowExisting -and ($joinPolicy.AllowPrecreatedJoin -or ([bool]$plan.ReservedByPesto -and $joinPolicy.ReserveNamesInAD)))
    }catch{
        # Aucune commande Windows partie : le reçu Running ne doit pas devenir une barrière sans issue.
        $failure=$_
        if(-not($Request.Monitor -and [bool]$Request.Monitor.MutationStarted)){
            $notLaunched='Préparation interrompue avant toute commande Windows : '+$failure.Exception.Message
            if($script:ActiveIntervention){try{[void](Complete-PestoIntervention -Action (New-ActionResult 96 $notLaunched))}catch{};$script:ActiveIntervention=$null}
            $receipt.Phase='Failed';$receipt.Utc=[DateTime]::UtcNow.ToString('o');$receipt.Message=Protect-PestoLogText $notLaunched
            try{Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $receipt}catch{}
        }
        throw
    }
    Assert-PestoCampaignApproval -Plan $ledgerPlan -Approval $Request.Approval
    $action=AddToDomain -DC $plan.DC -DOMAINE $plan.Domain -OU $plan.TargetOU -NEWNAME $plan.NewName -CRED $Request.Credential
    if($action -and $action.ExitCode -is [int]){
        if($action.ExitCode -eq 10){Set-PestoJoinNativeStatus -Status Accepted}
        elseif($action.ExitCode -in @(11,13,96)){Set-PestoJoinNativeStatus -Status Refused}
    }
    $action=Complete-PestoIntervention -Action $action -TimedOut ([bool]$Request.Monitor.TimedOut)
    $script:ActiveIntervention=$null
    if(-not $action -or -not $action.PSObject.Properties['ExitCode']){$action=New-ActionResult 97 'Résultat de jonction absent ou incomplet.'}
    if($Request.Monitor -and ($Request.Monitor.TimedOut -or $Request.Monitor.CancelRequested)){$action=New-ActionResult 97 ('Surveillance arrêtée ; retour Windows tardif : '+$action.ExitMsg+'. Vérifier le poste avant toute reprise.')}
    $receipt.Phase=if($action.ExitCode -eq 10){'PendingRestart'}elseif($action.ExitCode -in @(97,98)){'Uncertain'}else{'Failed'}
    $receipt.Utc=[DateTime]::UtcNow.ToString('o');$receipt.Message=Protect-PestoLogText $action.ExitMsg
    try{Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $receipt}
    catch{
        # Le reçu Running reste une barrière persistante si la fin ne s'enregistre pas.
        return [pscustomobject]@{Action=(New-ActionResult 97 ("Résultat Windows code $($action.ExitCode), mais reçu final non enregistré : $($_.Exception.Message). Vérifier avant toute reprise."));Check=$check;Receipt=$receipt}
    }
    return [pscustomobject]@{Action=$action;Check=$check;Receipt=$receipt}
}

function Invoke-PestoJoinExecute {
    param($Request)
    $mutex=$null;$owned=$false
    try {
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){return [pscustomobject]@{Action=(New-ActionResult 96 'Une autre instance traite déjà la jonction de ce PC. Aucun nouvel ajout lancé.');Check=$null;Receipt=$null}}
        Assert-PestoStoredMutationReady -Joining
        return Invoke-PestoJoinExecuteLocked -Request $Request
    } finally {
        if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}
    }
}

function Get-PestoJoinWorkerSource {
    $builder=[Text.StringBuilder]::new()
    [void]$builder.AppendLine((Get-PestoWorkerCoreSource))
    foreach($name in @('New-PestoDiagnosticFinding','Get-PestoClockObservation','Get-PestoJoinClockCheck','Write-PestoAtomicText','Get-PestoJoinPlanErrors','Get-PestoJoinPlanKey','Get-PestoJoinLocalStatus','Read-PestoJoinReceipt','Write-PestoJoinReceipt','Get-PestoJoinReceiptDecision','Get-PestoJoinPreflight','Invoke-PestoJoinExecuteLocked','Invoke-PestoJoinExecute','Get-PestoJoinStatePath','Get-PestoJoinADReservationPath','Get-PestoReservationMachineId','Read-PestoJoinADReservationState','Assert-PestoJoinADReservationResolved')){
        $definition=(Get-Command $name -CommandType Function -ErrorAction Stop).Definition
        [void]$builder.AppendLine("function $name {`r`n$definition`r`n}")
    }
    return $builder.ToString()
}

$script:PestoJoinWorker={
    param($Request,$Source)
    $ErrorActionPreference='Stop';Set-StrictMode -Off
    $script:PestoQueueMonitor=$Request.Monitor
    . ([scriptblock]::Create([string]$Source))
    function Write-Log {param($Message,$Level='INFO',$ErrorRecord,$Context='jonction');Publish-PestoWorkerLog -Text ([string]$Message) -Level $Level -Context $Context}
    function Show-MsgWarning {};function Show-MsgInfo {};function Show-MsgError {}
    $script:SIM=$false;$script:GUI=$false;$script:cred=$Request.Credential
    $script:PestoPolicy=$Request.Policy;$script:PestoReadOnly=[bool]$Request.ReadOnly
    $script:DOMAINE=$Request.Plan.Domain;$script:DC=$Request.Plan.DC;$script:PREFIXE=$Request.Prefix
    $script:OU=$Request.OU;$script:OUV=$Request.OUSite;$script:OU_POSTES=$Request.OU.ROOT
    if($Request.Mode -eq 'Status'){
        Set-PestoWorkerStage 'Lecture de l''état Windows' 'Aucune modification'
        $receipt=Read-PestoJoinReceipt -Path $Request.StatePath
        # Aucun reçu n'est réécrit : la vérification AD consignée reste une action facultative distincte.
        return Get-PestoJoinReceiptStatus -Receipt $receipt -Domain $Request.Plan.Domain
    }
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    if($Request.Mode -eq 'Check'){return Get-PestoJoinPreflight -Request $Request}
    if($Request.Mode -eq 'Execute'){return Invoke-PestoJoinExecute -Request $Request}
    throw 'Mode de worker jonction inconnu.'
}

function New-PestoJoinPlanFromUI {
    $ui=$script:JoinUI
    $target=if($script:PRD -and $ui.Org.SelectedItem -and $ui.Site.SelectedItem){'OU='+(ConvertTo-PestoRdnValue ([string]$ui.Site.SelectedItem))+','+[string]$script:OUV[[string]$ui.Org.SelectedItem]}else{[string]$script:OU['PREPROD']}
    $newName=if($ui.Existing.IsChecked){[string]$ui.Name.Text}else{[string]$ui.Name.SelectedItem}
    # Nom réservé dans l'AD par Pesto pour cette mise au domaine (option POLICY.ReserveNamesInAD) : le compte créé est repris.
    $r=$script:JoinADReservation
    $reserved=([bool]$r -and -not [bool]$ui.Existing.IsChecked -and [string]$r.Name -ieq $newName -and [string]$r.OU -ieq $target -and [string]$r.DC -ieq [string]$script:DC)
    [pscustomobject]@{Computer=$env:COMPUTERNAME;NewName=$newName;AllowExisting=([bool]$ui.Existing.IsChecked -or $reserved);ReservedByPesto=$reserved;ReservedGuid=$(if($reserved){[string]$r.Guid}else{''});Domain=$script:DOMAINE;DC=$script:DC;TargetOU=$target;DirectProd=[bool]$script:PRD;Account=$(if($script:cred){$script:cred.UserName}else{[string]$script:AuthUser})}
}

function New-PestoJoinRequest {
    param([string]$Mode,$Plan)
    [pscustomobject]@{Mode=$Mode;Plan=$Plan;Policy=(ConvertTo-PestoPolicy $script:CFG.POLICY);ReadOnly=[bool]$script:PestoReadOnly;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);OperationId=[Guid]::NewGuid().ToString('N');Credential=$script:cred;Prefix=$script:PREFIXE;OU=$script:OU;OUSite=$script:OUV;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');StatePath=(Get-PestoJoinStatePath);Monitor=(New-PestoQueueMonitor -Computer $env:COMPUTERNAME)}
}

function Set-PestoJoinMessage {
    param([string]$Title,[string]$Detail='', [ValidateSet('info','ok','warn','err')][string]$Kind='info')
    if(-not $script:JoinUI){return}
    $ui=$script:JoinUI;$ui.Status.Text=$Title;$ui.Detail.Text=$Detail
    $key=switch($Kind){'ok'{'OkFg'};'warn'{'WarnFg'};'err'{'ErrFg'};default{'FgAccent'}}
    $ui.Status.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$key)
}
function Show-PestoJoinOutcome {
    if(-not $script:JoinUI){return}
    $title=[string]$script:JoinUI.Status.Text
    $detail=[string]$script:JoinUI.Detail.Text
    Show-PestoOutcome -Title $title -Message $(if($detail){$title+"`n`n"+$detail}else{$title})
}

function Set-PestoJoinBusy {
    param([bool]$Busy)
    $script:JoinBusy=$Busy
    if($script:JoinUI){$script:JoinUI.Fields.IsEnabled=-not $Busy;$script:JoinUI.Progress.Visibility=if($Busy){'Visible'}else{'Collapsed'}}
    if($SetTabs){$SetTabs.IsEnabled=-not $Busy}
    Update-QueueButtons;Update-AddButton;Update-PestoJoinUI
}

function Update-PestoJoinUI {
    if(-not $script:JoinUI){return}
    $ui=$script:JoinUI
    if($ui.ServiceState){$info=$null;$state='';if($script:SiteLookupKey){if($script:SiteLookupInfo){$info=$script:SiteLookupInfo[$script:SiteLookupKey]};if($script:SiteLookupState){$state=[string]$script:SiteLookupState[$script:SiteLookupKey].State}};$ui.ServiceState.Text=Get-PestoSiteReadLabel $info $state}
    $script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
    $ui.Existing.Visibility=if($script:PestoPolicy.AllowPrecreatedJoin){'Visible'}else{'Collapsed'}
    $ui.Name.IsEditable=[bool]$ui.Existing.IsChecked
    $alreadyJoined=($script:INDOMAIN -or ($script:JoinLocal -and $script:JoinLocal.PartOfDomain))
    $recorded=($script:JoinReceipt -and ($alreadyJoined -or $script:JoinLocked -or $script:JoinReceipt.Phase -in @('Running','PendingRestart','Uncertain')))
    # Le nom soumis reste visible dans le champ et l'aperçu, même si une lecture AD tardive l'écarte des noms libres.
    $recordedName=if($recorded){[string]$script:JoinReceipt.NewName}elseif($alreadyJoined){[string]$env:COMPUTERNAME}else{''}
    if($recordedName -and ([string]$ui.Name.SelectedItem -cne $recordedName -or [string]$ui.Name.Text -cne $recordedName)){
        $previousSuspend=$script:JoinSuspend;$script:JoinSuspend=$true
        try{
            if(-not $ui.Name.Items.Contains($recordedName)){[void]$ui.Name.Items.Add($recordedName)}
            $ui.Name.SelectedItem=$recordedName;$ui.Name.Text=$recordedName
        }finally{$script:JoinSuspend=$previousSuspend}
    }
    $plan=New-PestoJoinPlanFromUI
    $errors=@(Get-PestoJoinPlanErrors $plan)
    $blocked=([bool]$script:JoinBusy -or [bool]$script:JoinLocked -or [bool]$recorded -or [bool]$script:DirectBusy -or $script:DirectLocked -or $script:Running -or [bool]$script:PreflightRunning -or [bool]$script:MutationUncertain -or [bool]$script:CfgRestartRequired -or (Test-PestoQueueWorkerStillActive))
    $canUse=(-not $alreadyJoined -and -not $blocked)
    $ui.Fields.IsEnabled=$canUse
    $ui.Existing.IsEnabled=($canUse -and -not $script:PestoReadOnly)
    $nameRead=Get-PestoJoinNameReadState
    $ui.Start.IsEnabled=($canUse -and -not $script:JoinInputPending -and $nameRead.Ready -and $errors.Count -eq 0)
    $ui.Check.IsEnabled=$ui.Start.IsEnabled
    if($script:PestoReadOnly){$ui.Start.IsEnabled=$false}
    $ui.CancelRead.Visibility=if($script:JoinBusy -and ((Test-PestoAsyncOperationRunning 'JoinCheck') -or (Test-PestoAsyncOperationRunning 'JoinStatus'))){'Visible'}else{'Collapsed'}
    $ui.Refresh.IsEnabled=(-not $script:JoinBusy -and -not $script:Running -and -not (Test-PestoAsyncOperationRunning 'DomainJoin'))
    $ui.Restart.Visibility=if($script:JoinReceipt -and $script:JoinReceipt.Phase -eq 'PendingRestart' -and -not ($script:GUI -or $script:SIM)){'Visible'}else{'Collapsed'}
    $ui.Restart.IsEnabled=($ui.Refresh.IsEnabled -and $script:JoinLocal -and $script:JoinReceipt.MachineId -ieq $script:JoinLocal.MachineId -and $script:JoinReceipt.BootUtc -eq $script:JoinLocal.BootUtc)
    if($script:PestoReadOnly){$ui.Restart.IsEnabled=$false}
    $ui.Review.Visibility=if($script:JoinReceipt){'Visible'}else{'Collapsed'}
    $ui.Review.IsEnabled=($ui.Refresh.IsEnabled -and -not $script:PestoReadOnly)
    $ui.Later.Visibility=$ui.Restart.Visibility;$ui.Later.IsEnabled=$ui.Restart.IsEnabled
    # Après jonction, afficher la demande enregistrée plutôt qu'un nouveau brouillon vide.
    $ui.Fields.Visibility=if($alreadyJoined){'Collapsed'}else{'Visible'}
    $displayName=if($recorded){[string]$script:JoinReceipt.NewName}elseif($alreadyJoined){$env:COMPUTERNAME}else{[string]$plan.NewName}
    $displayOU=if($recorded){[string]$script:JoinReceipt.OU}elseif($alreadyJoined){''}else{[string]$plan.TargetOU}
    $ui.NamePreview.Text=if($displayName){$displayName}else{'Choisissez le type et le service'}
    if(-not $recorded -and -not $alreadyJoined){
        if($script:JoinInputPending){$ui.NamePreview.Text='Calcul du nom disponible en cours…'}
        elseif(-not $nameRead.Ready){$ui.NamePreview.Text=$nameRead.Message}
    }
    $ui.NamePreview.ToolTip=if($recorded){"Nom demandé dans le reçu. $(Get-PestoUxNom 'BtnVerifierAD') fournit une nouvelle observation."}else{'Nom proposé ; aucune modification avant confirmation.'}
    $ui.OUPreview.Text=if($displayOU){Format-OUPath $displayOU}else{'Emplacement non lu : ouvrez État du poste.'};$ui.OUPreview.ToolTip=$displayOU
    $ui.Domain.Text=$script:DOMAINE;$ui.Current.Text=$env:COMPUTERNAME
    if($ui.Hardware){$hardware=if($script:JoinLocal){([string]$script:JoinLocal.Manufacturer+' '+[string]$script:JoinLocal.Model).Trim()}else{''};$ui.Hardware.Text=if($hardware){$hardware}else{'Identité matérielle non lue'}; $ui.Hardware.ToolTip=if($script:JoinLocal.CollectedUtc){'Lecture locale : '+[string]$script:JoinLocal.CollectedUtc}else{'Actualiser l’’état local pour relire Windows.'}}
    $ui.Account.Text=if($plan.Account){$plan.Account}else{if($script:GUI){'Démonstration, aucun compte'}else{'Compte AD explicite nécessaire'}}
    $ui.Policy.Text=if($recorded){"Demande enregistrée. Utilisez $(Get-PestoUxNom 'BtnVerifierAD') pour relire son résultat."}elseif($alreadyJoined){"Ce PC est membre du domaine. Utilisez $(Get-PestoUxNom 'BtnVersRenommage') pour préparer une modification."}elseif($script:PRD){'Production directe autorisée par la configuration.'}else{'Zone de préparation imposée par la configuration. Le nom utilise le site PREPROD et son service configuré.'}
    $ui.Start.Content=if($script:SIM -or $script:GUI){'Simuler l''ajout de ce PC'}else{'Ajouter ce PC au domaine'}
    $reason=if($alreadyJoined){"Ce PC est déjà dans le domaine. Utilisez « $(Get-PestoUxNom 'BtnVersRenommage') »."}elseif($script:JoinBusy){'Vérification ou opération en cours.'}elseif($script:JoinLocked){'Un résultat précédent doit être vérifié avant de continuer.'}elseif($script:MutationUncertain){'Le verrou de sécurité global doit être examiné dans la file avant toute mutation.'}elseif($script:CfgRestartRequired){'La configuration a changé : relancez Pesto avant une nouvelle opération.'}elseif($script:DirectBusy -or $script:DirectLocked -or $script:Running -or $script:PreflightRunning){'Attendez la fin du traitement déjà lancé.'}elseif($script:JoinInputPending){'Mise a jour du nom propose...'}elseif($errors.Count){$errors -join ' '}else{'Vérifier les informations, confirmer le récapitulatif puis ajouter ce PC. Aucune file et aucun redémarrage automatique.'}
    $ui.Start.ToolTip=$reason;$ui.Hint.Text=$reason
    if($canUse -and -not $nameRead.Ready){$ui.Start.ToolTip=$nameRead.Message;$ui.Hint.Text=$nameRead.Message}
    $ui.Export.IsEnabled=($null -ne $script:JoinLastCheck -or $null -ne $script:JoinReceipt)
    $ui.Rename.Visibility=if($script:INDOMAIN){'Visible'}else{'Collapsed'}
}

function Update-PestoJoinServices {
    <# Services connus du site choisi (cache local) ; la saisie libre d'un nouveau code reste possible. #>
    $ui=$script:JoinUI
    if(-not $ui -or -not $script:PRD){return}
    $prev=$script:JoinSuspend;$script:JoinSuspend=$true
    try{
        $text=[string]$ui.Service.Text
        $ui.Service.Items.Clear()
        $org=[string]$ui.Org.SelectedItem;$site=[string]$ui.Site.SelectedItem
        if($org -and $site){
            $orgOU=if($script:OUV.ContainsKey($org)){[string]$script:OUV[$org]}else{''}
            foreach($code in @(Get-PestoSiteServiceCodes -OrganismeOU $orgOU -Site $site -Computers (Get-PestoKnownComputers))){[void]$ui.Service.Items.Add($code)}
        }
        $ui.Service.Text=$text
    }finally{$script:JoinSuspend=$prev}
}
function Request-PestoJoinSiteLookup {
    <# Services et noms du site choisi, lus par une requête ciblée : la liste s'affiche sans attendre l'inventaire complet. #>
    param([switch]$Force)
    $ui=$script:JoinUI
    if(-not $ui -or $script:INDOMAIN){return}
    $org=[string]$ui.Org.SelectedItem;$site=[string]$ui.Site.SelectedItem
    $orgOU=if($org -and $script:OUV -and $script:OUV.ContainsKey($org)){[string]$script:OUV[$org]}else{''}
    if($site){Request-PestoSiteLookup -OrganismeOU $orgOU -Site $site -Force:$Force}
}
function Get-PestoJoinNameReadState {
    # Une liste vide n'est pas un inventaire AD complet : ne pas annoncer le premier numéro comme libre.
    if($script:GUI -or ($script:JoinUI -and $script:JoinUI.Existing.IsChecked)){
        return [pscustomobject]@{Ready=$true;Message='';Key=''}
    }
    $ui=$script:JoinUI;$site=[string]$ui.Site.SelectedItem;$org=[string]$ui.Org.SelectedItem
    $orgOU=if($script:OUV -and $script:OUV.ContainsKey($org)){[string]$script:OUV[$org]}else{''}
    $tag='';try{$tag=[string](Get-SiteTag -SiteName $site)}catch{}
    if($tag -cnotmatch (Get-PestoFacetPattern Site)){$tag=''}
    $siteOU=''
    if($site -and $site -ine 'PREPROD' -and (Test-PestoOUPath $orgOU)){$siteOU='OU='+(ConvertTo-PestoRdnValue $site)+','+$orgOU.Trim()}
    $key=([string]$script:DOMAINE+'|'+[string]$script:DC+'|'+[string]$script:PREFIXE+'|'+$tag+'|'+$siteOU).ToUpperInvariant()
    $info=if($script:SiteLookupInfo){$script:SiteLookupInfo[$key]}else{$null}
    $state=if($script:SiteLookupState){[string]$script:SiteLookupState[$key].State}else{''}
    $ready=($site -and ($tag -or $siteOU) -and $info -and $info.Complete -and $state -eq 'Ready')
    $message=if(-not $site){'Choisissez le site avant de calculer le nom.'}
        elseif($state -eq 'Failed' -or ($state -eq 'Ready' -and -not $info.Complete)){"Noms disponibles non confirmés. Actualisez l’état du poste pour réessayer."}
        else{'Calcul du nom disponible en cours…'}
    return [pscustomobject]@{Ready=[bool]$ready;Message=$(if($ready){''}else{$message});Key=$key}
}
function Request-PestoJoinInventory {
    <# Hors domaine, le login léger ne charge pas les postes : sans eux, ni liste des services ni noms déjà pris.
       Lecture AD en arrière-plan, comme à l'ouverture de Noms ; aucune modification. #>
    if($script:INDOMAIN -or $script:GUI -or $script:InventoryLoaded -or -not $script:cred){return}
    # Jamais pendant un traitement : le cache des postes ne change pas sous une opération en cours.
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy){return}
    [void](Refresh-Names)
}
function Set-PestoJoinServiceEntry {
    <# Zone éditable de la liste : 3 caractères, majuscules (comme l'ancienne zone de texte). #>
    param($Sender,$EventArgs)
    try{
        $box=$Sender.Template.FindName('PART_EditableTextBox',$Sender)
        if($box){$box.MaxLength=3;$box.CharacterCasing=[Windows.Controls.CharacterCasing]::Upper}
    }catch{}
}
function Get-PestoJoinNameCandidates {
    param([string]$Type,[string]$Site,[string]$Service,[array]$Computers)
    $serviceCode=$Service.Trim().ToUpperInvariant()
    if($Type -notin @('Portable','Fixe','Virtuel') -or -not $Site -or $serviceCode -notmatch (Get-PestoFacetPattern Service)){return}
    $base=$(switch($Type){'Portable'{'P'};'Fixe'{'S'};'Virtuel'{'V'}})+$script:PREFIXE
    # Get-NameList retourne un tableau protege de l'enumeration. L'affectation
    # puis foreach evitent d'ajouter ce tableau comme UN element de ComboBox.
    $candidates=Get-NameList -codeSite $Site -codeService $serviceCode -computers $Computers -baseName $base
    foreach($name in $candidates){
        if($name -isnot [string] -or -not (Test-PestoGeneratedComputerName $name)){continue}
        # Nom trouvé pris dans l'AD pendant cette session (souvent par un autre poste du banc) : jamais reproposé.
        if($script:PestoTakenNames -and $script:PestoTakenNames.Contains($name)){continue}
        # Nom réservé par un autre Pesto dans le registre partagé : jamais proposé tant que la réservation court.
        if(Test-PestoNameReservedByOther $name){continue}
        Write-Output $name
    }
}

function Test-PestoJoinNameTaken {
    <# Vrai si l'AD a trouvé le nouveau nom déjà utilisé : contrôle « Nouveau nom » bloqué, ou refus 13 juste avant Add-Computer. #>
    param($Check,[int]$Code=0,[string]$Message='')
    if($Code -eq 13 -and $Message -like 'Compte déjà présent*'){return $true}
    if(-not $Check -or -not $Check.PSObject.Properties['Checks']){return $false}
    return (@($Check.Checks|Where-Object{[string]$_.Check -eq 'Nouveau nom' -and [string]$_.State -eq 'Bloqué'}).Count -gt 0)
}
function Add-PestoTakenNames {
    <# Noms trouvés pris dans l'AD (nom contrôlé et, s'il est pris, toute sa série) : jamais reproposés pendant la session. #>
    param([object[]]$Names)
    if(-not $script:PestoTakenNames){$script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    foreach($n in @($Names)){if($n -is [string] -and (Test-PestoGeneratedComputerName $n)){[void]$script:PestoTakenNames.Add($n)}}
}
function Select-PestoJoinNextName {
    <# Le nom est écarté pour la session, le nom libre suivant est sélectionné et annoncé ; il sera revérifié dans l'AD et
       le technicien confirme toujours avant l'ajout. Jamais d'ajout sous un nom non confirmé ; au plus 5 bascules d'affilée. #>
    param([string]$TakenName,[string]$Reason,[switch]$RegistryHeld)
    $ui=$script:JoinUI
    if(-not $ui -or -not $TakenName -or [bool]$ui.Existing.IsChecked){return $false}
    if(-not $script:PestoTakenNames){$script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    # Réservé au registre seulement : écarté tant que la réservation dure (Test-PestoNameReservedByOther), pas pour la session.
    if(-not $RegistryHeld){[void]$script:PestoTakenNames.Add($TakenName)}
    $script:JoinAutoNext=[int]$script:JoinAutoNext+1
    if($script:JoinAutoNext -gt 5){Set-PestoJoinMessage 'Plusieurs noms déjà pris' "$TakenName $Reason Cinq noms de suite étaient pris : actualisez l'inventaire (Noms disponibles) puis choisissez un nom." 'warn';return $false}
    Update-PestoJoinNames
    $next=[string]$ui.Name.SelectedItem
    if(-not $next -or $next -ieq $TakenName){return $false}
    $how=if((Get-PestoSharedNameSettings).Random){'numéro tiré au hasard parmi tous les libres de la série'}else{'premier numéro libre de la série dans l''AD'}
    $title=if($RegistryHeld){'Nom réservé par un autre poste : nom suivant proposé'}else{'Nom déjà pris : nom suivant proposé'}
    Set-PestoJoinMessage $title "$TakenName $Reason`nNom suivant proposé : $next, $how. Il est revérifié ; confirmez ensuite l'ajout." 'warn'
    Add-LogLine ("JONCTION : $TakenName "+$(if($RegistryHeld){'réservé par un autre poste (registre partagé)'}else{'déjà utilisé dans l''AD'})+" ; nom suivant proposé : $next.") 'warn'
    return $true
}
function Request-PestoJoinAutoNextCheck {
    param([bool]$Execute)
    # Relance hors du rappel en cours : un minuteur à un coup, comme la saisie.
    $script:JoinAutoNextExecute=$Execute
    if(-not $script:JoinAutoNextTimer){
        $script:JoinAutoNextTimer=[Windows.Threading.DispatcherTimer]::new();$script:JoinAutoNextTimer.Interval=[TimeSpan]::FromMilliseconds(150)
        $script:JoinAutoNextTimer.Add_Tick([EventHandler]${function:Invoke-PestoJoinAutoNextTick})
    }
    $script:JoinAutoNextTimer.Stop();$script:JoinAutoNextTimer.Start()
}
function Invoke-PestoJoinAutoNextTick {
    param($Sender,$EventArgs)
    $script:JoinAutoNextTimer.Stop()
    Start-PestoJoinCheck -ExecuteAfterCheck:([bool]$script:JoinAutoNextExecute) -Auto
}

function Update-PestoJoinNames {
    param([switch]$NoLookup)
    if(-not $script:JoinUI){return}
    # Le rafraîchissement des noms libres ne doit jamais remplacer le nom d'une opération soumise.
    # Un ancien reçu résolu n'empêche pas un nouveau brouillon si le poste est revenu en groupe de travail.
    if($script:JoinBusy -or $script:JoinLocked -or $script:INDOMAIN -or
       ($script:JoinLocal -and $script:JoinLocal.PartOfDomain) -or
       ($script:JoinReceipt -and $script:JoinReceipt.Phase -in @('Running','PendingRestart','Uncertain'))){Update-PestoJoinUI;return}
    if($script:JoinUI.Existing.IsChecked){Update-PestoJoinUI;return}
    if(-not $NoLookup){Request-PestoJoinSiteLookup}
    $nameRead=Get-PestoJoinNameReadState
    $ui=$script:JoinUI;$previousSuspend=$script:JoinSuspend;$script:JoinSuspend=$true
    try{
        $old=[string]$ui.Name.SelectedItem;$ui.Name.Items.Clear()
        $type=[string]$ui.Type.SelectedItem;$site=[string]$ui.Site.SelectedItem;$service=([string]$ui.Service.Text).Trim().ToUpperInvariant()
        if(-not $nameRead.Ready){$ui.Name.SelectedIndex=-1;$ui.Name.Text=''}
        elseif($type -in @('Portable','Fixe','Virtuel') -and $site -and $service -match (Get-PestoFacetPattern Service)){
            foreach($name in @(Get-PestoJoinNameCandidates -Type $type -Site $site -Service $service -Computers (Get-ComputersForNameGeneration))){[void]$ui.Name.Items.Add($name)}
            if($old -and $ui.Name.Items.Contains($old)){$ui.Name.SelectedItem=$old}elseif($ui.Name.Items.Count){$ui.Name.SelectedIndex=(Get-PestoInitialNameIndex $ui.Name.Items.Count)}
        }
    }finally{$script:JoinSuspend=$previousSuspend}
    Update-PestoJoinUI
}

function Invoke-PestoJoinInputTick {
    param($Sender,$EventArgs)
    $script:JoinInputTimer.Stop();$script:JoinInputPending=$false;Update-PestoJoinNames
}
function Invoke-PestoJoinInputChanged {
    param($Sender,$EventArgs)
    if($script:JoinSuspend -or $script:JoinBusy){return}
    $ui=$script:JoinUI;$script:JoinGeneration++;$script:JoinLastCheck=$null
    $ui.Checks.ItemsSource=$null
    if($Sender.Name -eq 'JnOrg'){
        $script:JoinSuspend=$true
        try{$ui.Site.Items.Clear();foreach($s in @($script:Sites[[string]$ui.Org.SelectedItem])){[void]$ui.Site.Items.Add($s)};if($ui.Site.Items.Count){$ui.Site.SelectedIndex=0}}
        finally{$script:JoinSuspend=$false}
    }
    if($Sender.Name -in @('JnOrg','JnSite')){Update-PestoJoinServices;Request-PestoJoinSiteLookup}
    if($Sender.Name -in @('JnName')){Update-PestoJoinUI}
    else{$script:JoinInputPending=$true;$script:JoinInputTimer.Stop();$script:JoinInputTimer.Start();Update-PestoJoinUI}
    Set-PestoJoinMessage 'Brouillon à vérifier' 'Le contrôle précédent est invalidé dès qu''un champ change.'
}

function Start-PestoJoinCheck {
    param([switch]$ExecuteAfterCheck,[switch]$Auto)
    if($script:JoinInputPending -or ($script:JoinLocal -and $script:JoinLocal.PartOfDomain) -or $script:JoinBusy -or $script:JoinLocked -or $script:DirectBusy -or $script:DirectLocked -or $script:Running -or $script:PreflightRunning -or $script:MutationUncertain -or $script:CfgRestartRequired -or $script:INDOMAIN){return}
    if(Test-PestoQueueWorkerStillActive){return}
    if(-not (Get-PestoJoinNameReadState).Ready){Update-PestoJoinNames;return}
    $plan=New-PestoJoinPlanFromUI;$errors=@(Get-PestoJoinPlanErrors $plan)
    if($errors.Count){Set-PestoJoinMessage 'Formulaire incomplet' ($errors -join "`n") 'warn';return}
    # Un clic du technicien repart de zéro ; seules les relances automatiques s'additionnent.
    if(-not $Auto){$script:JoinAutoNext=0;$script:JoinAutoRecheck=0}
    $script:JoinLastCheck=$null;$script:JoinUI.Checks.ItemsSource=$null
    if($script:SIM -or $script:GUI){
        $simCheck=[pscustomobject]@{Valid=$true;Key=(Get-PestoJoinPlanKey $plan);Local=$null;Receipt=$null;Decision=$null;Checks=@([pscustomobject]@{Check='Démonstration';State='Simulé';Detail='Aucune lecture AD, aucune commande Windows et aucun reçu réel.'})}
        $ctx=[pscustomobject]@{Plan=$plan;Execute=$ExecuteAfterCheck.IsPresent;Generation=$script:JoinGeneration}
        Complete-PestoJoinCheck -Result $simCheck -Context $ctx
        return
    }
    try{
        $req=New-PestoJoinRequest -Mode Check -Plan $plan
        $ctx=[pscustomobject]@{Plan=$plan;Execute=$ExecuteAfterCheck.IsPresent;Generation=$script:JoinGeneration}
        $script:JoinActiveRequest=$req;Set-PestoJoinBusy $true
        Set-PestoJoinMessage 'Vérification en cours' 'État local, compte, domaine, emplacement et disponibilité du nom. Aucune écriture AD.'
        $ok=Start-PestoAsyncOperation -Name 'JoinCheck' -ScriptBlock $script:PestoJoinWorker -ArgumentList @($req,(Get-PestoJoinWorkerSource)) -CallbackContext $ctx -QueueMonitor $req.Monitor -TimeoutSec 90 -OnSuccess {param($r,$c) Complete-PestoJoinCheck -Result $r -Context $c} -OnError {param($e,$c) Complete-PestoJoinReadError -Failure $e}
        if(-not $ok){Set-PestoJoinBusy $false}
    }catch{Complete-PestoJoinReadError -Failure $_}
}

function Complete-PestoJoinCheck {
    param($Result,$Context)
    Set-PestoJoinBusy $false
    if(-not $Result -or -not $Result.PSObject.Properties['Valid']){Complete-PestoJoinReadError -Failure 'Résultat de contrôle incomplet.';return}
    if($Context.Generation -ne $script:JoinGeneration){Set-PestoJoinMessage 'Contrôle périmé' 'Le formulaire a changé. Relancez la vérification.' 'warn';return}
    if($Result.Key -ne (Get-PestoJoinPlanKey (New-PestoJoinPlanFromUI))){
        # Aucune saisie depuis le lancement : la liste des noms a été recalculée (inventaire arrivé pendant le contrôle).
        # Avant, l'enchaînement s'arrêtait ici et il fallait relancer. Le nom contrôlé, s'il est pris, et sa série sont
        # écartés ; le nom désormais proposé est vérifié à son tour et la confirmation reste obligatoire.
        if(Test-PestoJoinNameTaken $Result){Add-PestoTakenNames (@([string]$Context.Plan.NewName)+@($Result.SeriesTaken));Update-PestoJoinNames}
        $script:JoinAutoRecheck=[int]$script:JoinAutoRecheck+1
        if($script:JoinAutoRecheck -le 3){Set-PestoJoinMessage 'Liste des noms actualisée' ('Inventaire chargé pendant la vérification. Vérifiez le nom proposé puis cliquez de nouveau sur Ajouter.');Request-PestoJoinAutoNextCheck -Execute $false;return}
        Set-PestoJoinMessage 'Contrôle périmé' 'Le formulaire a changé. Relancez la vérification.' 'warn';return
    }
    $script:JoinLastCheck=$Result;$script:JoinLocal=$Result.Local;$script:JoinReceipt=$Result.Receipt
    $script:JoinUI.Checks.ItemsSource=@($Result.Checks)
    if($Result.Decision){$script:JoinLocked=([bool]$script:JoinADReservationNeedsReview -or [bool]$Result.Decision.Blocked)}
    if(-not $Result.Valid){
        if(Test-PestoJoinNameTaken $Result){Add-PestoTakenNames @($Result.SeriesTaken)}
        if((Test-PestoJoinNameTaken $Result) -and (Select-PestoJoinNextName -TakenName ([string]$Context.Plan.NewName) -Reason 'est déjà utilisé dans l''AD (sans doute par un autre poste).')){Request-PestoJoinAutoNextCheck -Execute $false;return}
        Set-PestoJoinMessage 'Ajout non lancé' 'Corrigez les points indiqués ci-dessous. Aucun objet AD n''a été modifié.' 'warn';Update-PestoJoinUI;return
    }
    $script:JoinAutoNext=0;$script:JoinAutoRecheck=0
    Set-PestoJoinMessage 'Vérifications préalables réussies' 'Les droits d''écriture seront évalués par Windows au moment de l''ajout.' 'ok'
    Update-PestoJoinUI
    if(-not $Context.Execute){return}
    $p=$Context.Plan;$mode=if($script:GUI -or $script:SIM){'SIMULATION'}else{'AJOUT RÉEL'}
    # Le registre partagé a répondu pendant le contrôle que ce nom est réservé par un autre poste (techniciens partis au même
    # moment) : nom suivant, revérifié, AVANT la réservation AD et la confirmation, plutôt qu'un échec après confirmation.
    if(-not [bool]$p.AllowExisting -and -not [bool]$p.ReservedByPesto -and (Test-PestoNameReservedByOther ([string]$p.NewName)) -and
       (Select-PestoJoinNextName -TakenName ([string]$p.NewName) -Reason 'est réservé par un autre poste dans le registre partagé.' -RegistryHeld)){Request-PestoJoinAutoNextCheck -Execute $false;return}
    if(-not $script:GUI -and -not $script:SIM -and -not [bool]$p.AllowExisting -and (Get-PestoSharedNameSettings).ReserveInAD){
        Start-PestoJoinADReservation -Plan $p;return
    }
    $reservedLine=if([bool]$p.ReservedByPesto){"`nNom réservé dans l'AD : compte créé par Pesto, repris par la jonction."}else{''}
    $summary="$mode`n`nCe PC : $($p.Computer)`nNouveau nom : $($p.NewName)`nDomaine : $($p.Domain)`nEmplacement : $(Format-OUPath $p.TargetOU)$reservedLine`n`nAucun retrait Entra. Aucun redémarrage automatique.`n`nConfirmer l’ajout ?"
    # Le formulaire reste gelé pendant la confirmation modale.
    Set-PestoJoinBusy $true
    try{$confirmed=Confirm-YesNo -Msg $summary -Confirm $true -AcceptText 'Ajouter ce poste au domaine' -SummaryRows @([pscustomobject]@{Field='Nom';Before=$p.Computer;After=$p.NewName},[pscustomobject]@{Field='Domaine';Before='Hors domaine';After=$p.Domain},[pscustomobject]@{Field='Emplacement';Before='';After=$p.TargetOU})}
    finally{Set-PestoJoinBusy $false}
    if(-not $confirmed){
        if([bool]$p.ReservedByPesto){Stop-PestoJoinADReservation -Reason 'ajout annulé avant lancement'}
        Set-PestoJoinMessage 'Ajout annulé avant lancement' $(if([bool]$p.ReservedByPesto){'Le brouillon est conservé. Aucune jonction lancée ; la réservation du nom dans l''AD est retirée.'}else{'Le brouillon est conservé. Aucune opération lancée.'});return
    }
    if((Get-PestoJoinPlanKey $p) -ne (Get-PestoJoinPlanKey (New-PestoJoinPlanFromUI))){Set-PestoJoinMessage 'Le plan a changé' 'Vérifiez de nouveau le formulaire.' 'warn';return}
    if($script:SIM -or $script:GUI){
        Set-PestoJoinMessage 'Simulation terminée' 'Aucune jonction réelle, aucune modification de nom, aucun redémarrage.' 'ok'
        Add-LogLine "SIMULATION JONCTION : $($p.Computer) -> $($p.NewName) ; domaine $($p.Domain) ; OU $($p.TargetOU)" 'info'
        Show-PestoJoinOutcome
        return
    }
    try{
        if(-not(Test-PestoAuditWritable)){throw 'Le journal d''audit est inaccessible.'}
        $req=New-PestoJoinRequest -Mode Execute -Plan $p
        $req|Add-Member -NotePropertyName ConfirmedTargetOUGuid -NotePropertyValue ([string]$Result.TargetOUGuid)
        $req|Add-Member -NotePropertyName ConfirmedExistingGuid -NotePropertyValue ([string]$Result.ExistingGuid)
        $req|Add-Member -NotePropertyName ConfirmedMachineId -NotePropertyValue ([string]$Result.Local.MachineId)
        $script:JoinActiveRequest=$req
        Set-PestoJoinBusy $true;Set-PestoJoinMessage 'Ajout au domaine en cours' 'Les contrôles critiques sont relus avant Add-Computer. Ne relancez pas la demande.'
        Write-Log "JONCTION DIRECTE début : opération $($req.OperationId), $($p.Computer) -> $($p.NewName), domaine $($p.Domain), OU $($p.TargetOU)." 'INFO' $null 'join'
        $ok=Start-PestoAsyncOperation -Name 'DomainJoin' -ScriptBlock $script:PestoJoinWorker -ArgumentList @($req,(Get-PestoJoinWorkerSource)) -CallbackContext $req -QueueMonitor $req.Monitor -ApartmentState STA -TimeoutSec 300 -OnSuccess {param($r,$c) Complete-PestoJoinExecution -Result $r -Request $c} -OnError {param($e,$c) Complete-PestoJoinExecutionError -Failure $e -Request $c}
        if(-not $ok){Set-PestoJoinBusy $false}
    }catch{Complete-PestoJoinExecutionError -Failure $_ -Request $script:JoinActiveRequest}
}

function Complete-PestoJoinReadError {
    param($Failure)
    Set-PestoJoinBusy $false
    $message=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
    Set-PestoJoinMessage 'Vérification impossible' ($message+"`n"+(Get-PestoJoinGuidance $message)) 'warn'
    Write-Log ('Contrôle de jonction : '+$message) 'WARN' $null 'join'
    Update-PestoJoinNames -NoLookup
}

function Save-PestoJoinHistory {
    param($Request,[int]$Code)
    $state=[pscustomobject]@{RunId=$Request.OperationId;Mode='JONCTION RÉELLE';Total=1;OkCount=$(if($Code -eq 10){1}else{0});KoCount=$(if($Code -ne 10 -and $Code -ne 96){1}else{0});CancelCount=$(if($Code -eq 96){1}else{0})}
    try{Save-PestoRunHistory -State $state}catch{Write-Log 'Synthèse de jonction non enregistrée ; le reçu machine et l''audit restent prioritaires.' 'WARN' $_ 'join'}
}

function Complete-PestoJoinExecution {
    param($Result,$Request)
    if(-not $Result -or -not $Result.Action -or $Result.Action.ExitCode -isnot [int]){Complete-PestoJoinExecutionError -Failure 'Résultat de jonction absent ou non typé.' -Request $Request;return}
    $action=$Result.Action;$code=$action.ExitCode
    $script:JoinReceipt=$Result.Receipt
    if($code -in @(10,97,98,99)){Invalidate-PestoNameInventory}
    if($Result.Check){$script:JoinLocal=$Result.Check.Local;$script:JoinLastCheck=$Result.Check;$script:JoinUI.Checks.ItemsSource=@($Result.Check.Checks)}
    $script:JoinLocked=($code -in @(10,97,98))
    # Réservation AD : consommée par une jonction acceptée ; gardée si le résultat est incertain ; retirée sinon.
    if($script:JoinADReservation -and [bool]$Request.Plan.ReservedByPesto){
        if($code -eq 10){
            $reservation=$script:JoinADReservation;$reservation.State='Consumed';$reservation.NeedsReview=$false
            try{Write-PestoJoinReceipt -Path (Get-PestoJoinADReservationPath) -Receipt $reservation}catch{Write-Log 'Réservation consommée : reçu non actualisé, conserver la preuve de jonction.' 'WARN' $_ 'join'}
            $script:JoinADReservation=$null
        }
        elseif($code -notin @(97,98)){Stop-PestoJoinADReservation -Reason ('ajout non abouti, code '+$code)}
    }
    if($code -eq 10){Set-PestoJoinMessage 'Ajout accepté · redémarrage nécessaire' 'Le nouveau nom et le domaine ne sont pas annoncés comme pleinement actifs avant redémarrage et vérification.' 'ok'}
    elseif($code -eq 96){Set-PestoJoinMessage 'Ajout non lancé' $action.ExitMsg 'warn'}
    elseif($code -in @(97,98)){Set-PestoJoinMessage 'Résultat à vérifier' ($action.ExitMsg+"`nNe relancez pas la jonction.") 'err'}
    else{Set-PestoJoinMessage 'Ajout refusé' ($action.ExitMsg+"`n"+(Get-PestoJoinGuidance $action.ExitMsg)) 'err'}
    Set-PestoJoinBusy $false
    Request-PestoAffectedRefresh -Names @($Request.Plan.CurrentName,$Request.Plan.NewName)
    Write-Log ("JONCTION DIRECTE fin : opération $($Request.OperationId), code $code : $($action.ExitMsg)") 'INFO' $null 'join'
    Save-PestoJoinHistory -Request $Request -Code $code
    if(($code -eq 96 -or $code -eq 13) -and (Test-PestoJoinNameTaken -Check $Result.Check -Code $code -Message ([string]$action.ExitMsg))){
        if($Result.Check -and $Result.Check.PSObject.Properties['SeriesTaken']){Add-PestoTakenNames @($Result.Check.SeriesTaken)}
        if(Select-PestoJoinNextName -TakenName ([string]$Request.Plan.NewName) -Reason 'a été pris entre-temps (sans doute par un autre poste). Aucun ajout lancé.'){Request-PestoJoinAutoNextCheck -Execute $false;return}
    }
    Show-PestoJoinOutcome
}

function Complete-PestoJoinExecutionError {
    param($Failure,$Request)
    $message=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
    $started=($Request -and $Request.Monitor -and [bool]$Request.Monitor.MutationStarted)
    $active=Test-PestoAsyncOperationRunning 'DomainJoin'
    $script:JoinLocked=($started -or $active)
    if($script:JoinLocked){
        Set-PestoJoinMessage 'Résultat à vérifier' ($message+"`nUne commande Windows peut encore terminer. Aucune relance ni interruption forcée.") 'err'
        try{
            $receipt=Read-PestoJoinReceipt -Path $Request.StatePath
            if($receipt -and $receipt.OperationId -eq $Request.OperationId){$receipt.Phase='Uncertain';$receipt.Message=$message;Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $receipt;$script:JoinReceipt=$receipt}
        }catch{Write-Log 'Le reçu non terminé reste à vérifier.' 'WARN' $_ 'join'}
    }else{Set-PestoJoinMessage 'Ajout non lancé' $message 'err'}
    Set-PestoJoinBusy $false
    Request-PestoAffectedRefresh -Names @($Request.Plan.CurrentName,$Request.Plan.NewName)
    Write-Log ('Jonction interrompue : '+$message) 'ERROR' $null 'join'
    if($Request){Save-PestoJoinHistory -Request $Request -Code $(if($script:JoinLocked){97}else{96})}
    Show-PestoJoinOutcome
}

function Start-PestoJoinStatus {
    param([switch]$ReviewReservation)
    if(-not $script:JoinUI -or $script:JoinBusy -or $script:DirectBusy -or $script:DirectLocked -or $script:Running -or (Test-PestoAsyncOperationRunning 'DomainJoin')){return}
    if($script:JoinADReservationNeedsReview){
        if($ReviewReservation){Start-PestoJoinADReservationInspection}
        else{Set-PestoJoinMessage 'Réservation AD conservée' 'Cliquez sur Vérifier l’’état pour examiner le reçu avant toute reprise. Aucune jonction ni suppression automatique.' 'warn';Update-PestoJoinUI}
        return
    }
    if($script:GUI -or $script:SIM){Set-PestoJoinMessage 'Démonstration' 'Aucune lecture Windows ou AD réelle depuis cette page.';Update-PestoJoinUI;return}
    try{
        $req=New-PestoJoinRequest -Mode Status -Plan (New-PestoJoinPlanFromUI);$script:JoinActiveRequest=$req
        Set-PestoJoinBusy $true;Set-PestoJoinMessage 'Lecture de l''état de ce PC' 'Aucune réparation ni réinscription automatique.'
        $started=Start-PestoAsyncOperation -Name 'JoinStatus' -ScriptBlock $script:PestoJoinWorker -ArgumentList @($req,(Get-PestoJoinWorkerSource)) -TimeoutSec 60 -QueueMonitor $req.Monitor -OnSuccess {param($r) Complete-PestoJoinStatus $r} -OnError {param($e) Complete-PestoJoinReadError $e}
        if(-not $started){Set-PestoJoinBusy $false}
    }catch{Complete-PestoJoinReadError $_}
}
function Complete-PestoJoinStatus {
    param($Result)
    Set-PestoJoinBusy $false
    if(-not $Result -or -not $Result.Local -or -not $Result.Decision){Complete-PestoJoinReadError 'Lecture de l''état local incomplète.';return}
    $script:JoinLocal=$Result.Local;$script:JoinReceipt=$Result.Receipt;$script:JoinLocked=([bool]$script:JoinADReservationNeedsReview -or [bool]$Result.Decision.Blocked)
    $script:JoinUI.LocalState.Text=if($Result.Local.PartOfDomain){"Membre de $($Result.Local.Domain)"}else{'Groupe de travail · hors domaine'}
    if($Result.Decision.Phase -eq 'Verified'){Set-PestoJoinMessage 'Dernière jonction vérifiée précédemment' $Result.Decision.Message 'ok'}
    elseif($Result.Decision.Phase -eq 'ReadyToObserve'){Set-PestoJoinMessage 'Commande acceptée · vérification facultative' $Result.Decision.Message 'ok'}
    elseif($Result.Decision.Phase -eq 'Acknowledged'){Set-PestoJoinMessage 'Jonction précédente acquittée' $Result.Decision.Message 'warn'}
    elseif($Result.Decision.Blocked){Set-PestoJoinMessage 'Une opération attend une vérification' $Result.Decision.Message 'warn'}
    elseif($Result.Local.PartOfDomain){Set-PestoJoinMessage 'Ce PC appartient déjà à un domaine' "Cette page ne sort jamais une machine de son domaine. Utilisez $(Get-PestoUxNom 'BtnVersRenommage')."}
    else{Set-PestoJoinMessage 'Prêt à préparer l''ajout' 'Choisissez le nom. Le bouton principal vérifiera le plan avant confirmation.'}
    Update-PestoJoinNames -NoLookup
}
function Invoke-PestoJoinPulse {
    param($Sender,$EventArgs)
    if(-not $script:JoinUI){return}
    if($script:JoinBusy -and $script:JoinActiveRequest){$script:JoinUI.Activity.Text=Get-PestoQueueActivityText $script:JoinActiveRequest.Monitor}
    else{$script:JoinUI.Activity.Text=''}
    try{Test-PestoJoinADReservationStale}catch{Write-Log ('Réservation AD : '+$_.Exception.Message) 'WARN' $_ 'join'}
    Update-PestoJoinUI
}
function Invoke-PestoJoinCancelReadClick {
    param($Sender,$EventArgs)
    if(Test-PestoAsyncOperationRunning 'DomainJoin'){return}
    foreach($name in @('JoinCheck','JoinStatus')){if(Test-PestoAsyncOperationRunning $name){Stop-PestoAsyncOperation $name}}
    $script:JoinGeneration++;$script:JoinLastCheck=$null
    Set-PestoJoinBusy $false
    Set-PestoJoinMessage 'Lecture annulee' 'Aucun ajout au domaine lancé. Les verrous et reçus existants sont conservés.'
    Update-PestoJoinNames -NoLookup
}
function Invoke-PestoJoinCheckClick {param($Sender,$EventArgs);Start-PestoJoinCheck}
function Invoke-PestoJoinStartClick {param($Sender,$EventArgs);if($script:PestoReadOnly){Show-MsgInfo 'Consultation : jonction interdite.';return};Start-PestoJoinCheck -ExecuteAfterCheck}
function Invoke-PestoJoinStatusClick {param($Sender,$EventArgs);Request-PestoJoinSiteLookup -Force;Update-PestoJoinNames -NoLookup;Start-PestoJoinStatus -ReviewReservation}
function Invoke-PestoJoinLogClick {param($Sender,$EventArgs);Set-PestoUxPage 'Log'}
function Invoke-PestoJoinRenameClick {param($Sender,$EventArgs);Set-PestoUxPage 'Rename'}
function Invoke-PestoJoinLaterClick {param($Sender,$EventArgs);Set-PestoJoinMessage 'Redémarrage reporté' 'Le reçu est conservé. Redémarrez ce PC quand il est disponible ; le contrôle complémentaire reste facultatif.' 'warn'}
function Invoke-PestoJoinCopyClick {
    param($Sender,$EventArgs)
    $name=[string]$script:JoinUI.NamePreview.Text
    if(Test-PestoGeneratedComputerName $name){try{[Windows.Clipboard]::SetText($name)}catch{Set-PestoJoinMessage 'Copie impossible' $_.Exception.Message 'warn'}}
}
function Invoke-PestoJoinRestartClick {
    param($Sender,$EventArgs)
    if($script:PestoReadOnly){throw 'Consultation : redémarrage interdit.'}
    if($script:JoinBusy -or $script:DirectBusy -or $script:DirectLocked -or $script:Running -or (Test-PestoQueueWorkerStillActive) -or -not $script:JoinReceipt -or $script:JoinReceipt.Phase -ne 'PendingRestart'){return}
    if(-not(Confirm-YesNo -Msg 'Redémarrer ce PC maintenant ? Enregistrez votre travail. Aucun redémarrage forcé.' -Confirm $true)){return}
    try{
        $receipt=Read-PestoJoinReceipt -Path (Get-PestoJoinStatePath)
        if(-not $receipt -or $receipt.Phase -ne 'PendingRestart' -or $receipt.OperationId -ne $script:JoinReceipt.OperationId){throw 'Le reçu a changé. Vérifiez de nouveau l''état du PC avant de redémarrer.'}
        if($script:SIM -or $script:GUI -or -not(Test-PestoIsAdministrator)){throw 'Redémarrage réel non autorisé dans cet état.'}
        # Pas de -Force : les applications peuvent demander d'enregistrer le travail.
        Restart-Computer -ErrorAction Stop
        Write-Log 'Redémarrage local explicitement demandé après jonction confirmée.' 'INFO' $null 'join'
    }catch{Set-PestoJoinMessage 'Redémarrage non lancé' $_.Exception.Message 'warn'}
}
function Invoke-PestoJoinExportClick {
    param($Sender,$EventArgs)
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Rapport texte (*.txt)|*.txt';$dialog.FileName='Pesto_jonction_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.txt'
    if(-not $dialog.ShowDialog($Win)){return}
    try{
        $lines=[Collections.Generic.List[string]]::new();$lines.Add('Pesto '+$script:Pesto_VERSION+' | Jonction locale');$lines.Add([DateTime]::Now.ToString('s'))
        $lines.Add($script:JoinUI.Status.Text);$lines.Add($script:JoinUI.Detail.Text)
        if($script:JoinReceipt){$r=$script:JoinReceipt;foreach($key in @('OperationId','Phase','Computer','NewName','Domain','OU','Message')){$lines.Add($key+' : '+[string]$r.$key)}}
        if($script:JoinLastCheck){foreach($row in @($script:JoinLastCheck.Checks)){$lines.Add($row.Check+' | '+$row.State+' | '+$row.Detail)}}
        $lines.Add('Diffusion interne : contient des noms de poste et chemins AD. Aucun mot de passe exporté.')
        [IO.File]::WriteAllLines($dialog.FileName,$lines.ToArray(),[Text.UTF8Encoding]::new($true))
        Set-PestoJoinMessage $script:JoinUI.Status.Text ('Rapport enregistré : '+$dialog.FileName)
    }catch{Show-MsgError $_.Exception.Message 'Rapport de jonction'}
}

function Initialize-PestoJoinUI {
    if($script:JoinUI){return}
    $path=Join-Path $BasePath 'Pesto-Join.xaml'
    $reader=[Xml.XmlReader]::Create($path)
    try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $Win.FindName('UxJoinHost').Content=$view
    $script:JoinUI=@{View=$view}
    $names=@{Review='JnReview';Existing='JnExisting';CancelRead='JnCancelRead';Fields='JnFields';Type='JnType';Org='JnOrg';Site='JnSite';Service='JnService';ServiceState='JnServiceState';Name='JnName';Start='JnStart';Check='JnCheck';Refresh='JnRefresh';Restart='JnRestart';Later='JnLater';Export='JnExport';Log='JnLog';Rename='JnRename';Copy='JnCopy';Progress='JnProgress';Status='JnStatus';Detail='JnDetail';Activity='JnActivity';Checks='JnChecks';Hint='JnHint';Current='JnCurrent';Hardware='JnHardware';Domain='JnDomain';Account='JnAccount';Policy='JnPolicy';NamePreview='JnNamePreview';OUPreview='JnOUPreview';LocalState='JnLocalState'}
    foreach($key in $names.Keys){$c=$view.FindName($names[$key]);if(-not $c){throw "Contrôle jonction absent : $($names[$key])"};$script:JoinUI[$key]=$c}
    $view.FindName('JnOtherName').Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoOtherNameClick})
    $script:JoinGeneration=0;$script:JoinLocked=$false;$script:JoinBusy=$false;$script:JoinSuspend=$true
    $script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$script:JoinAutoNext=0;$script:JoinAutoRecheck=0
    $ui=$script:JoinUI
    foreach($value in @('Portable','Fixe','Virtuel')){[void]$ui.Type.Items.Add($value)}
    $type=if($script:CachedPCType -in @('Portable','Fixe','Virtuel')){$script:CachedPCType}else{$null};$ui.Type.SelectedItem=$type
    if($script:PRD){foreach($org in @($script:OUV.Keys|Sort-Object)){[void]$ui.Org.Items.Add($org)}}
    else{
        [void]$ui.Org.Items.Add('PREPROD');$ui.Org.SelectedIndex=0;$ui.Org.IsEnabled=$false
        [void]$ui.Site.Items.Add('PREPROD');$ui.Site.SelectedIndex=0;$ui.Site.IsEnabled=$false
        [void]$ui.Service.Items.Add([string]$script:PREPRODSITE);$ui.Service.Text=$script:PREPRODSITE;$ui.Service.IsEnabled=$false
    }
    $ui.LocalState.Text=if($script:INDOMAIN){'Déjà membre du domaine'}else{'Hors domaine · vérification avant ajout'}
    $script:JoinSuspend=$false
    $script:JoinInputTimer=[Windows.Threading.DispatcherTimer]::new();$script:JoinInputTimer.Interval=[TimeSpan]::FromMilliseconds(180)
    $script:JoinInputTimer.Add_Tick([EventHandler]${function:Invoke-PestoJoinInputTick})
    foreach($control in @($ui.Type,$ui.Org,$ui.Site,$ui.Name)){$control.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoJoinInputChanged})}
    $ui.Service.AddHandler([Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $ui.Service.Add_Loaded([Windows.RoutedEventHandler]${function:Set-PestoJoinServiceEntry})
    $ui.Existing.Add_Checked([Windows.RoutedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $ui.Existing.Add_Unchecked([Windows.RoutedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $ui.Name.AddHandler([Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $handlers=@{Review='Invoke-PestoJoinReviewClick';CancelRead='Invoke-PestoJoinCancelReadClick';Start='Invoke-PestoJoinStartClick';Check='Invoke-PestoJoinCheckClick';Refresh='Invoke-PestoJoinStatusClick';Log='Invoke-PestoJoinLogClick';Restart='Invoke-PestoJoinRestartClick';Later='Invoke-PestoJoinLaterClick';Rename='Invoke-PestoJoinRenameClick';Copy='Invoke-PestoJoinCopyClick';Export='Invoke-PestoJoinExportClick'}
    foreach($key in $handlers.Keys){$ui[$key].Add_Click([Windows.RoutedEventHandler](Get-Command $handlers[$key] -CommandType Function).ScriptBlock)}
    $script:JoinPulseTimer=[Windows.Threading.DispatcherTimer]::new();$script:JoinPulseTimer.Interval=[TimeSpan]::FromSeconds(1)
    $script:JoinPulseTimer.Add_Tick([EventHandler]${function:Invoke-PestoJoinPulse});$script:JoinPulseTimer.Start()
    Update-PestoJoinServices;Update-PestoJoinNames;Restore-PestoJoinADReservation;Update-PestoJoinUI
    if(-not $script:INDOMAIN){Set-PestoUxPage 'Join'}
}
function Stop-PestoJoinUI {
    foreach($timer in @($script:JoinInputTimer,$script:JoinPulseTimer,$script:JoinAutoNextTimer)){if($timer){$timer.Stop()}}
}

function Invoke-PestoJoinReviewClick {
    param($Sender,$EventArgs)
    if($script:JoinBusy -or $script:DirectBusy -or $script:Running -or -not $script:JoinReceipt){return}
    try{
        $id=([Guid]$script:JoinReceipt.OperationId).ToString('N')
        $path=Join-Path (Get-PestoInterventionRoot) ($id+'.json')
        if(-not [IO.File]::Exists($path)){Show-MsgInfo 'Importez le reçu local de jonction dans Interventions pour préserver son historique avant vérification.';Show-PestoInterventions;return}
        $r=Read-PestoIntervention $path
        if(-not $r.JoinEvidence){Show-MsgInfo 'Ce reçu ancien manque de preuve de démarrage. Importez le fichier local Join/receipt.json depuis Interventions, puis vérifiez.';Show-PestoInterventions;return}
        Show-PestoPostState -Mode Ledger -ReceiptOverride $r
    }catch{Show-PestoUsefulError -Title 'Vérification de jonction indisponible' -Message $_.Exception.Message -Stage 'Lecture du reçu' -MutationPossible $false}
}

###############################################################################
#  Réservation du nom dans l'AD à la mise au domaine (option POLICY.ReserveNamesInAD)
#  Après un contrôle réussi et avant la confirmation, Pesto crée le compte
#  ordinateur dans l'OU cible, sur le contrôleur du plan : la création est
#  atomique sur ce contrôleur et les autres Pesto le voient pris. La jonction
#  reprend ensuite ce compte (même créateur, identifié par GUID). Annulation ou
#  refus : Pesto retire ce compte s'il n'a jamais servi (ni nom DNS ni SPN) ;
#  un résultat incertain le garde.
###############################################################################

function Get-PestoJoinADReservationPath {
    return [IO.Path]::Combine([IO.Path]::GetDirectoryName((Get-PestoJoinStatePath)),'ad-reservation.json')
}
function Get-PestoReservationMachineId {
    $id=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $parsed=[Guid]::Empty
    if(-not [Guid]::TryParse($id,[ref]$parsed) -or $parsed -eq [Guid]::Empty){throw 'Identité de la machine indisponible pour la réservation.'}
    return $parsed.ToString('D')
}
function Read-PestoJoinADReservationState {
    param([string]$Path='')
    if(-not $Path){$Path=Get-PestoJoinADReservationPath}
    Assert-PestoPlainPath $Path
    if(-not [IO.File]::Exists($Path)){return $null}
    $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($f.Length -gt 16384){throw 'Reçu de réservation trop volumineux.'}
    $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    $id=[Guid]::Empty;$machine=[Guid]::Empty;$guid=[Guid]::Empty
    if($r.Schema -ne 1 -or -not [Guid]::TryParse([string]$r.OperationId,[ref]$id) -or $id -eq [Guid]::Empty -or
       -not [Guid]::TryParse([string]$r.MachineId,[ref]$machine) -or $machine -eq [Guid]::Empty -or
       $r.Mode -notin @('Reserve','Release','Inspect') -or $r.State -notin @('Pending','Reserved','Released','Gone','Taken','Kept','Failed','Uncertain','Consumed') -or
       $r.Name -notmatch '^[A-Za-z0-9-]{1,15}$' -or -not(Test-PestoDnsName ([string]$r.Domain)) -or
       -not(Test-PestoDnsName ([string]$r.DC)) -or -not(Test-PestoOUPath ([string]$r.OU)) -or $r.NeedsReview -isnot [bool]){throw 'Reçu de réservation invalide. Vérification administrative requise.'}
    if($r.Guid -and (-not [Guid]::TryParse([string]$r.Guid,[ref]$guid) -or $guid -eq [Guid]::Empty)){throw 'GUID de réservation invalide.'}
    return $r
}
function Assert-PestoJoinADReservationResolved {
    param($Plan)
    $r=Read-PestoJoinADReservationState
    if(-not $r -or $r.State -in @('Released','Gone','Taken','Consumed') -or ($r.State -eq 'Failed' -and -not $r.NeedsReview)){return}
    if($r.MachineId -ine (Get-PestoReservationMachineId) -or $r.Domain -ine $Plan.Domain -or $r.DC -ine $Plan.DC){throw 'Une réservation conservée concerne une autre machine ou un autre domaine/contrôleur. Aucune reprise automatique.'}
    if($r.NeedsReview -or $r.State -ne 'Reserved' -or -not $Plan.ReservedByPesto -or $r.Guid -ine $Plan.ReservedGuid -or $r.Name -ine $Plan.NewName -or $r.OU -ine $Plan.TargetOU){throw ('Réservation AD conservée pour '+$r.Name+' : utilisez Vérifier l’’état pour la relire avant de poursuivre. Reçu : '+(Get-PestoJoinADReservationPath))}
}
function Get-PestoJoinADReservationWorkerSource {
    $source=Get-PestoADLoaderSource
    foreach($n in @('Write-PestoAtomicText','Write-PestoJoinReceipt','Invoke-PestoAuditSinkReceipt','Get-PestoJoinStatePath','Get-PestoJoinADReservationPath','Read-PestoJoinADReservationState','Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','Protect-PestoLogText')){
        $source+="`nfunction $n {`n"+(Get-Command $n -CommandType Function -ErrorAction Stop).Definition+"`n}"
    }
    return $source
}

$script:PestoJoinADReserveWorker = {
    param($Request)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    . ([scriptblock]::Create([string]$Request.Source))
    $mutex=$null;$owned=$false;$record=$null;$written=$false;$mutation=$false
    function Save-ReservationResult {
        param([string]$State,[string]$Message='')
        $record.Outcome=$State;$record.State=$State;$record.Message=Protect-PestoLogText $Message
        $record.NeedsReview=($State -in @('Uncertain','Kept') -or ($State -eq 'Failed' -and $Request.Mode -ne 'Reserve'))
        if($Request.Monitor.CancelRequested -or $Request.Monitor.TimedOut){$record.State='Uncertain';$record.NeedsReview=$true}
        $record.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $record
        return $record
    }
    function Assert-ReservationMayContinue {
        param([switch]$Mutation)
        [Threading.Monitor]::Enter($Request.Monitor.SyncRoot)
        try{
            if($Request.Monitor.CancelRequested){throw [OperationCanceledException]::new('Surveillance arrêtée : aucune nouvelle écriture AD autorisée.')}
            if($Mutation){$Request.Monitor.MutationStarted=$true}
        }finally{[Threading.Monitor]::Exit($Request.Monitor.SyncRoot)}
    }
    try{
        if($Request.ReadOnly -or $env:PESTO_READONLY_SESSION -eq '1'){throw 'Consultation : réservation interdite.'}
        if($Request.Mode -notin @('Reserve','Release','Inspect') -or -not $Request.Monitor){throw 'Contrat de réservation incomplet.'}
        $operation=[Guid]::Empty;$machine=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$Request.OperationId,[ref]$operation) -or $operation -eq [Guid]::Empty -or
           -not [Guid]::TryParse([string]$Request.MachineId,[ref]$machine) -or $machine -eq [Guid]::Empty -or
           $Request.Name -notmatch '^[A-Za-z0-9-]{1,15}$' -or -not(Test-PestoDnsName $Request.Domain) -or
           -not(Test-PestoDnsName $Request.DC) -or $Request.DC -eq $Request.Domain -or -not(Test-PestoOUPath $Request.OU) -or
           (Get-PestoDomainFromDN $Request.OU) -ine $Request.Domain){throw 'Identité ou périmètre de réservation invalide.'}
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une autre mutation Pesto est active.'}
        $previous=Read-PestoJoinADReservationState -Path $Request.StatePath
        if($previous -and $previous.State -notin @('Released','Gone','Taken','Consumed') -and -not($previous.State -eq 'Failed' -and -not $previous.NeedsReview)){
            if($Request.Mode -eq 'Reserve'){throw 'Une réservation précédente est conservée. Relisez-la avant de créer un autre compte.'}
            if($previous.OperationId -cne $Request.OperationId -or $previous.MachineId -ine $Request.MachineId -or $previous.Domain -ine $Request.Domain -or $previous.DC -ine $Request.DC){throw 'La réservation conservée ne correspond pas à cette demande.'}
        }
        $record=[pscustomobject]@{Schema=1;OperationId=[string]$Request.OperationId;MachineId=[string]$Request.MachineId;Mode=[string]$Request.Mode;
            Name=[string]$Request.Name;Guid=[string]$Request.Guid;OU=[string]$Request.OU;DC=[string]$Request.DC;Domain=[string]$Request.Domain;
            State='Pending';Outcome='';NeedsReview=$true;Message='Demande enregistrée avant opération.';UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
        Write-PestoJoinReceipt -Path $Request.StatePath -Receipt $record;$written=$true
        Assert-ReservationMayContinue
        Import-PestoADModule -ADModulePath $Request.ADModulePath
        $adp=@{Server=[string]$Request.DC;ErrorAction='Stop'};if($Request.Credential){$adp.Credential=$Request.Credential}
        $domain=Get-ADDomain @adp
        if($domain.DNSRoot -ine $Request.Domain){throw 'Le contrôleur ne correspond pas au domaine de la réservation.'}
        $marker='Réservé par Pesto ['+[string]$Request.OperationId+']'
        if($Request.Mode -eq 'Reserve'){
            Assert-ReservationMayContinue -Mutation;$mutation=$true
            try{$o=New-ADComputer -Name $Request.Name -SamAccountName ($Request.Name+'$') -Path $Request.OU -Enabled $true -Description $marker -PassThru @adp}
            catch{
                if($_.Exception.GetType().Name -eq 'ADIdentityAlreadyExistsException'){return Save-ReservationResult 'Taken' 'Ce nom existe déjà. Aucun compte existant repris.'}
                throw
            }
            $id=[Guid]::Empty
            if(@($o).Count -ne 1 -or -not [Guid]::TryParse([string]$o.ObjectGUID,[ref]$id) -or $id -eq [Guid]::Empty -or $o.Name -ine $Request.Name -or [string]$o.DistinguishedName -ine ('CN='+$Request.Name+','+$Request.OU)){throw 'Création demandée, mais GUID ou destination de résultat non confirmé.'}
            $record.Guid=$id.ToString('D')
            return Save-ReservationResult 'Reserved' 'Compte créé ; aucune jonction lancée.'
        }
        $identity=if($Request.Guid){[string]$Request.Guid}else{[string]$Request.Name+'$'}
        try{$o=Get-ADComputer -Identity $identity -Properties ObjectGUID,Description,DNSHostName,ServicePrincipalName,DistinguishedName @adp}
        catch{
            if($_.Exception.GetType().Name -eq 'ADIdentityNotFoundException'){return Save-ReservationResult 'Gone' 'Absence confirmée sur le contrôleur du reçu.'}
            throw
        }
        $id=[Guid]::Empty
        if(@($o).Count -ne 1 -or -not [Guid]::TryParse([string]$o.ObjectGUID,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identité de la réservation non confirmée.'}
        if($Request.Guid -and $id.ToString('D') -ine $Request.Guid){throw 'GUID différent de celui conservé.'}
        $record.Guid=$id.ToString('D')
        if([string]$o.Name -ine $Request.Name -or [string]$o.Description -cne $marker -or [string]$o.DistinguishedName -ine ('CN='+$Request.Name+','+$Request.OU) -or [string]$o.DNSHostName -or @($o.ServicePrincipalName).Count){
            return Save-ReservationResult 'Kept' 'Objet utilisé, déplacé ou modifié depuis la réservation ; aucun retrait automatique.'
        }
        if($Request.Mode -eq 'Inspect'){return Save-ReservationResult 'Reserved' 'Réservation relue par GUID et marqueur exact ; aucune écriture AD.'}
        Assert-ReservationMayContinue -Mutation;$mutation=$true
        Remove-ADComputer -Identity $id -Confirm:$false @adp
        return Save-ReservationResult 'Released' 'Compte réservé retiré.'
    }catch{
        $message=Protect-PestoLogText $_.Exception.Message
        if($written){
            $state=if($mutation -or $Request.Monitor.CancelRequested -or $Request.Monitor.TimedOut){'Uncertain'}else{'Failed'}
            try{return Save-ReservationResult $state $message}catch{throw 'Le résultat de réservation ne peut pas être enregistré. Le reçu en attente doit être vérifié avant toute reprise.'}
        }
        throw
    }finally{if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}}
}

function New-PestoJoinADReservationRequest {
    param([string]$Mode,$Plan,$Existing)
    $machine=Get-PestoReservationMachineId
    if($Existing -and ($Existing.MachineId -ine $machine -or $Existing.Domain -ine $script:DOMAINE -or $Existing.DC -ine $script:DC)){throw 'Réservation d’’une autre machine ou d’’un autre domaine/contrôleur. Aucune reprise automatique.'}
    [pscustomobject]@{Mode=$Mode;OperationId=$(if($Existing){$Existing.OperationId}else{[Guid]::NewGuid().ToString('D')});MachineId=$machine;
        Name=$(if($Existing){$Existing.Name}else{$Plan.NewName});Guid=$(if($Existing){$Existing.Guid}else{''});OU=$(if($Existing){$Existing.OU}else{$Plan.TargetOU});
        Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:cred;ReadOnly=[bool]$script:PestoReadOnly;
        Source=(Get-PestoJoinADReservationWorkerSource);StatePath=(Get-PestoJoinADReservationPath);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Monitor=(New-PestoQueueMonitor $env:COMPUTERNAME)}
}
function Start-PestoJoinADReservationOperation {
    param($Request,$Plan,[string]$Reason='')
    $name='JoinAD'+$Request.Mode
    $context=[pscustomobject]@{Request=$Request;Plan=$Plan;Reason=$Reason;Generation=$script:JoinGeneration}
    Set-PestoJoinBusy $true
    $ok=Start-PestoAsyncOperation -Name $name -ScriptBlock $script:PestoJoinADReserveWorker -ArgumentList @($Request) -TimeoutSec 60 -QueueMonitor $Request.Monitor -CallbackContext $context `
        -OnSuccess {param($r,$c)Complete-PestoJoinADReservation -Result $r -Context $c} `
        -OnError {param($e,$c)Complete-PestoJoinADReservation -Failure $e -Context $c} `
        -OnLateResult {param($r,$c)Complete-PestoJoinADReservation -Result $r.Result -Failure $r.Failure -Context $c -Late}
    if(-not $ok){Set-PestoJoinBusy $false}
}
function Start-PestoJoinADReservation {
    param($Plan)
    $req=New-PestoJoinADReservationRequest -Mode Reserve -Plan $Plan
    Set-PestoJoinMessage 'Réservation du nom dans l’’AD' ('Création du compte '+$Plan.NewName+' avant votre confirmation.')
    Start-PestoJoinADReservationOperation -Request $req -Plan $Plan
}
function Complete-PestoJoinADReservation {
    param($Result,$Failure,$Context,[switch]$Late)
    $active=Test-PestoAsyncOperationRunning ('JoinAD'+$Context.Request.Mode)
    Set-PestoJoinBusy $active
    $uncertain=($Late -or $Failure -or -not $Result -or $Result.NeedsReview -or $Result.State -in @('Pending','Uncertain','Kept') -or $Context.Generation -ne $script:JoinGeneration)
    if($Result -and $Result.OperationId -cne $Context.Request.OperationId){$uncertain=$true;$Result=$null}
    if($Result -and $Result.Guid){$script:JoinADReservation=$Result}
    if($uncertain){
        $script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true
        if($Late -and $Result){
            $Result.State='Uncertain';$Result.NeedsReview=$true
            try{Write-PestoJoinReceipt -Path $Context.Request.StatePath -Receipt $Result}catch{Write-Log 'Le reçu de réservation doit rester à vérifier.' 'WARN' $_ 'join'}
        }
        $detail=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}elseif($Failure){[string]$Failure}elseif($Result){[string]$Result.Message}else{'Résultat absent.'}
        Set-PestoJoinMessage 'Réservation AD à vérifier' ($detail+"`nAucune jonction ni suppression automatique. Relisez l’’état pour examiner la réservation. Reçu : "+$Context.Request.StatePath) 'warn'
        Update-PestoJoinUI;return
    }
    if($Result.State -eq 'Failed'){
        Set-PestoJoinMessage 'Réservation non lancée' $Result.Message 'warn';Update-PestoJoinUI;return
    }
    if($Result.State -in @('Released','Gone')){
        $script:JoinADReservation=$null;$script:JoinADReservationNeedsReview=$false
        $script:JoinLocked=if($script:JoinReceipt){[bool](Get-PestoJoinReceiptDecision -Receipt $script:JoinReceipt -Local $script:JoinLocal -Domain $script:DOMAINE).Blocked}else{$false}
        Set-PestoJoinMessage 'Réservation relue' $Result.Message;Update-PestoJoinUI;return
    }
    if($Result.State -eq 'Taken'){
        Add-PestoTakenNames @([string]$Context.Request.Name)
        if(Select-PestoJoinNextName -TakenName $Context.Request.Name -Reason 'est déjà utilisé dans l’’AD.'){Request-PestoJoinAutoNextCheck -Execute $false};return
    }
    if($Result.State -ne 'Reserved' -or -not $Result.Guid){throw 'Retour de réservation incomplet.'}
    $script:JoinADReservation=$Result;$script:JoinADReservationRestored=($Context.Request.Mode -eq 'Inspect')
    $script:JoinADReservationNeedsReview=$false
    if($Context.Request.Mode -eq 'Reserve'){Start-PestoJoinCheck -ExecuteAfterCheck -Auto;return}
    # Inspection explicite seulement : proposer le même compte, sans lancer la jonction.
    $script:JoinLocked=if($script:JoinReceipt){[bool](Get-PestoJoinReceiptDecision -Receipt $script:JoinReceipt -Local $script:JoinLocal -Domain $script:DOMAINE).Blocked}else{$false}
    $script:JoinSuspend=$true
    try{
        $ui=$script:JoinUI;$parts=ConvertTo-PestoNameParts $Result.Name $script:PREFIXE
        if(-not $parts){throw 'Nom conservé incompatible avec la configuration actuelle.'}
        if($script:PRD){
            $siteMatches=@(foreach($org in $script:OUV.Keys){foreach($site in @($script:Sites[$org])){if(('OU='+(ConvertTo-PestoRdnValue $site)+','+$script:OUV[$org]) -ieq $Result.OU){[pscustomobject]@{Org=$org;Site=$site}}}})
            if($siteMatches.Count -ne 1){throw 'Emplacement conservé absent ou ambigu dans la configuration actuelle.'}
            $ui.Org.SelectedItem=$siteMatches[0].Org;$ui.Site.Items.Clear();foreach($site in @($script:Sites[$siteMatches[0].Org])){[void]$ui.Site.Items.Add($site)};$ui.Site.SelectedItem=$siteMatches[0].Site
        }elseif($Result.OU -ine $script:OU.PREPROD){throw 'La réservation n’’est pas dans la préproduction configurée.'}
        $ui.Type.SelectedItem=$parts.Label;$ui.Service.Text=$parts.Service;$ui.Existing.IsChecked=$false
        if(-not $ui.Name.Items.Contains($Result.Name)){[void]$ui.Name.Items.Add($Result.Name)};$ui.Name.SelectedItem=$Result.Name
        $script:JoinGeneration++;$script:JoinLastCheck=$null
        Set-PestoJoinMessage 'Réservation relue et proposée' ($Result.Name+' conservé. Vérifiez le formulaire puis confirmez séparément l’’ajout ; aucune jonction lancée.')
    }catch{$script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true;Set-PestoJoinMessage 'Réservation conservée' $_.Exception.Message 'warn'}
    finally{$script:JoinSuspend=$false;Update-PestoJoinUI}
}
function Restore-PestoJoinADReservation {
    if($script:GUI -or $script:SIM){return}
    try{
        $r=Read-PestoJoinADReservationState
        if(-not $r -or $r.State -in @('Released','Gone','Taken','Consumed') -or ($r.State -eq 'Failed' -and -not $r.NeedsReview)){return}
        $script:JoinADReservation=$r;$script:JoinADReservationNeedsReview=$true;$script:JoinADReservationRestored=$true;$script:JoinLocked=$true
        Set-PestoJoinMessage 'Réservation AD conservée' ($r.Name+' — relisez l’’état avant toute reprise. Reçu : '+(Get-PestoJoinADReservationPath)) 'warn'
    }catch{$script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true;Set-PestoJoinMessage 'Reçu de réservation à vérifier' $_.Exception.Message 'warn'}
}
function Start-PestoJoinADReservationInspection {
    if(Test-PestoQueueWorkerStillActive){return}
    try{
        $r=Read-PestoJoinADReservationState
        if(-not $r){throw 'Reçu absent : aucune levée automatique du verrou.'}
        $req=New-PestoJoinADReservationRequest -Mode Inspect -Existing $r
        Set-PestoJoinMessage 'Lecture de la réservation AD' 'Contrôle du GUID et du marqueur sur le contrôleur du reçu. Aucune écriture AD.'
        Start-PestoJoinADReservationOperation -Request $req
    }catch{Set-PestoJoinMessage 'Réservation non résolue' $_.Exception.Message 'warn'}
}
function Stop-PestoJoinADReservation {
    param([string]$Reason='')
    if($script:JoinADReservationNeedsReview -or (Test-PestoQueueWorkerStillActive)){return}
    $r=$script:JoinADReservation;if(-not $r){return}
    $req=New-PestoJoinADReservationRequest -Mode Release -Existing $r
    Set-PestoJoinMessage 'Retrait du compte réservé' 'Le GUID et le marqueur exact seront relus avant le retrait.'
    Start-PestoJoinADReservationOperation -Request $req -Reason $Reason
}
function Stop-PestoJoinADReservationAtClose {
    # Aucune écriture AD à la fermeture : le reçu permet une inspection explicite
    # au lancement suivant, sans abandonner une suppression après un délai arbitraire.
    if($script:JoinADReservation){Write-Log ('Réservation AD conservée : '+$script:JoinADReservation.Name+'. Relire l’’état au prochain lancement. Reçu : '+(Get-PestoJoinADReservationPath)) 'INFO' $null 'join'}
}
function Test-PestoJoinADReservationStale {
    if($script:JoinADReservationRestored -or $script:JoinADReservationNeedsReview -or -not $script:JoinADReservation -or -not $script:JoinUI -or $script:JoinBusy -or (Test-PestoQueueWorkerStillActive)){return}
    if(-not [bool](New-PestoJoinPlanFromUI).ReservedByPesto){Stop-PestoJoinADReservation -Reason 'formulaire modifié'}
}
