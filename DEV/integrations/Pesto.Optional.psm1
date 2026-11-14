#requires -Version 5.1
# Extensions facultatives et préparateurs. Rien ne s'exécute à l'import.
# Les mutations Pesto restent exclusivement dans son moteur vérifié.

function Test-PestoScenarioInput {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Scenario,[Parameter(Mandatory=$true)]$Values)
    $fields=@('Type','SiteCode','ServiceCode','TargetOU')
    # La forme acceptée ici doit rester un sous-ensemble de ce que ConvertTo-PestoScenario accepte :
    # un scénario que le formulaire admettrait et que le moteur refuserait plus tard n'est pas une garde.
    # Les cinq champs sont exigés et Allowed comme Locked doivent être des objets structurés : omettre l'un
    # des deux ne décrit pas un scénario « sans restriction », c'est un scénario que le moteur refusera à la
    # lecture de ScenarioJson, donc après publication de la GPO et sur tous les postes visés.
    if($Scenario -is [string] -or $Scenario -is [ValueType]){throw 'Scénario invalide.'}
    foreach($name in @('Schema','Name','Required','Allowed','Locked')){
        if($null -eq $Scenario.PSObject.Properties[$name]){throw 'Scénario invalide.'}
    }
    foreach($property in $Scenario.PSObject.Properties){if($property.Name -cnotin @('Schema','Name','Required','Allowed','Locked')){throw 'Champ de scénario inconnu.'}}
    if($Scenario.Schema -ne 1 -or $Scenario.Name -isnot [string] -or $Scenario.Name -notmatch '^[^\x00-\x1f]{1,80}$'){throw 'Scénario invalide.'}
    if($Scenario.Required -is [string]){throw 'Liste de champs requis invalide.'}
    foreach($map in @($Scenario.Allowed,$Scenario.Locked)){
        if($null -eq $map -or $map -is [string] -or $map -is [ValueType]){throw 'Scénario invalide.'}
        foreach($property in $map.PSObject.Properties){
            if($property.Name -cnotin $fields){throw 'Champ de règle inconnu.'}
            $listed=@($property.Value)
            if($listed.Count -lt 1 -or $listed.Count -gt 200){throw 'Liste de scénario invalide.'}
            foreach($item in $listed){if($item -isnot [string] -or -not $item -or $item.Length -gt 4096 -or $item -match '[\x00-\x1f\x7f]'){throw 'Valeur de scénario invalide.'}}
        }
    }
    if($null -ne $Scenario.Locked){
        foreach($property in $Scenario.Locked.PSObject.Properties){
            if($property.Value -isnot [string]){throw 'Un verrou exige une valeur unique.'}
            if($null -ne $Scenario.Allowed -and $null -ne $Scenario.Allowed.PSObject.Properties[$property.Name] -and $property.Value -cnotin @($Scenario.Allowed.($property.Name))){throw 'Verrou hors des valeurs autorisées.'}
        }
    }
    $errors=[Collections.Generic.List[string]]::new()
    foreach($property in $Values.PSObject.Properties){if($property.Name -cnotin $fields){$errors.Add('Champ non admis : '+$property.Name)}}
    if(@($Scenario.Required).Count -gt 4){throw 'Trop de champs requis.'}
    foreach($field in @($Scenario.Required)){
        if($field -cnotin $fields){throw 'Champ requis inconnu.'}
        if([string]::IsNullOrWhiteSpace([string]$Values.$field)){$errors.Add('Champ obligatoire : '+$field)}
    }
    foreach($field in $fields){
        if($null -ne $Values.PSObject.Properties[$field] -and ($Values.$field -isnot [string] -or $Values.$field.Length -gt 4096 -or $Values.$field -match '[\x00-\x1f\x7f]')){$errors.Add('Valeur invalide : '+$field)}
        if($Scenario.Allowed -and $null -ne $Scenario.Allowed.PSObject.Properties[$field]){
            $allowed=@($Scenario.Allowed.$field)
            if($allowed.Count -gt 200 -or @($allowed|Where-Object{$_ -isnot [string]}).Count){throw 'Valeurs autorisées invalides.'}
            if($Values.$field -cnotin $allowed){$errors.Add('Valeur hors scénario : '+$field)}
        }
        if($Scenario.Locked -and $null -ne $Scenario.Locked.PSObject.Properties[$field] -and $Values.$field -cne $Scenario.Locked.$field){$errors.Add('Champ verrouillé : '+$field)}
    }
    [pscustomobject]@{Valid=($errors.Count -eq 0);Errors=$errors.ToArray();Scope='Formulaire uniquement ; droits AD et politique moteur restent obligatoires.'}
}

function New-PestoAttributeProposal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Guid]$ObjectGuid,[Parameter(Mandatory=$true)]$Current,[Parameter(Mandatory=$true)]$Requested)
    if($ObjectGuid -eq [Guid]::Empty){throw 'Identité AD requise.'}
    # Les lignes produites doivent rester exactement la forme fermée que le moteur exige de son propre diff
    # (Assert-PestoAttributeChanges) : un aperçu que le plan refuserait n'est pas une évaluation, c'est une
    # revue que l'opérateur approuve et que la remise du fichier ne tiendra pas. Le garde-fou du formulaire
    # ne peut donc être que plus strict que celui du moteur, jamais plus permissif.
    $seen=@{}
    $changes=@(foreach($property in $Requested.PSObject.Properties){
        if($property.Name -cnotin @('description','location','managedBy')){throw ('Attribut non autorisé : '+$property.Name)}
        if($seen.ContainsKey($property.Name)){throw 'Attribut demandé deux fois.'}
        $seen[$property.Name]=$true
        if($property.Value -isnot [string] -or $property.Value.Length -gt 1024 -or $property.Value -match '[\x00-\x1f\x7f]'){throw 'Valeur d’’attribut invalide.'}
        if($property.Name -eq 'managedBy' -and $property.Value -and $property.Value -notmatch '^(CN|OU)=.+,DC='){throw 'managedBy attend un DN validé séparément.'}
        if([string]$Current.($property.Name) -cne $property.Value){[pscustomobject]@{Attribute=$property.Name;Before=[string]$Current.($property.Name);After=$property.Value;ReferenceGuid=''}}
    })
    if($changes.Count -lt 1 -or $changes.Count -gt 3){throw 'Un à trois changements attendus.'}
    [pscustomobject]@{Schema=1;Purpose='PestoAttributeReview';ObjectGuid=$ObjectGuid.ToString('D');Utc=[DateTime]::UtcNow.ToString('o');Changes=$changes;Executable=$false}
}

function New-PestoAuditExport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Result)
    $id=[Guid]::Empty
    if(-not[Guid]::TryParse([string]$Result.OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant opération requis.'}
    if($Result.ExitCode -isnot [int] -and $Result.ExitCode -isnot [long]){throw 'Code de résultat invalide.'}
    if([string]$Result.Mode -cnotin @('Join','UnattendedJoin','Rename','Move','RenameMove','Attributes')){throw 'Mode ou état audit inconnu.'}
    $state=[string]$Result.State
    if($state -ceq 'Prepared'){throw 'Préparation sans identifiant d''opération : rien à auditer.'}
    if($state -cnotin @('NotStarted','Running','PendingRestart','RestartRequested','Verified','Uncertain','Failed','Refused','Partial','Protection','MoveReady')){throw 'Mode ou état audit inconnu.'}
    # Transport libre pour le collecteur de l’’organisation ; aucun envoi automatique.
    [pscustomobject][ordered]@{Schema=1;Product='Pesto';OperationId=$id.ToString('D');Mode=[string]$Result.Mode;State=[string]$Result.State;
        ExitCode=[int]$Result.ExitCode;RestartRequired=[bool]$Result.RestartRequired;ExportedUtc=[DateTime]::UtcNow.ToString('o')}
}

Export-ModuleMember -Function Test-PestoScenarioInput,New-PestoAttributeProposal,New-PestoAuditExport
