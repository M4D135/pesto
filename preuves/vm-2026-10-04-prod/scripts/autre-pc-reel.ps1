[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$ErrorActionPreference='Stop'
function Test-PestoComputerName {
    <# Valide un nom d'hôte Windows/NetBIOS de 1 à 15 caractères. #>
    param([AllowNull()][string]$Name)
    $n = "$Name".Trim()
    if ($n.Length -lt 1 -or $n.Length -gt 15) { return $false }
    return ($n -match '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$')
}


function Test-PestoGeneratedComputerName {
    param([AllowNull()][string]$Name,[string]$Prefix="$script:PREFIXE")
    return ($null -ne (ConvertTo-PestoNameParts -Name $Name -Prefix $Prefix))
}


function Assert-PestoClosedObject {
    param([Parameter(Mandatory=$true)]$Value,[Parameter(Mandatory=$true)][string[]]$Allowed,[string[]]$Required=@())
    if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){throw 'Objet structuré attendu.'}
    $names=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    foreach($key in $names){if($key -cnotin $Allowed){throw ('Champ non autorisé : '+$key)}}
    foreach($key in $Required){if($key -cnotin $names){throw ('Champ obligatoire absent : '+$key)}}
}


function ConvertTo-PestoNameParts {
    <# Convention : P portable, S fixe, V virtuel ; département (6), site (2), service (3), numéro (3).
       -CurrentName admet le numéro historique 000 en lecture ; génération de 001 à 999. #>
    param([AllowNull()][string]$Name,[string]$Prefix='',[switch]$CurrentName)
    if([string]::IsNullOrWhiteSpace($Name)){return $null}
    $types='PSV'
    $m=[regex]::Match($Name.Trim().ToUpperInvariant(),'^(?<Type>['+$types+'])(?<Prefix>[0-9]{6})(?<Site>[A-Z]{2})(?<Service>[A-Z0-9]{3})(?<Number>[0-9]{3})$')
    if(-not $m.Success){return $null}
    $number=[int]$m.Groups['Number'].Value
    if(($number -lt 1 -and -not $CurrentName) -or ($Prefix -and $m.Groups['Prefix'].Value -cne $Prefix)){return $null}
    return [pscustomobject]@{Name=$m.Value;Type=$m.Groups['Type'].Value;Prefix=$m.Groups['Prefix'].Value;
        Site=$m.Groups['Site'].Value;Service=$m.Groups['Service'].Value;Number=$number;
        Base=$m.Value.Substring(0,12);Label=$(switch($m.Groups['Type'].Value){'P'{'Portable'};'S'{'Fixe'};default{'Virtuel'}})}
}


function Test-PestoJoinIntervention {
    param($Receipt)
    if(-not $Receipt -or -not $Receipt.Plan){return $false}
    $p=$Receipt.Plan
    return ($p.Renommer -is [bool] -and $p.Deplacer -is [bool] -and -not $p.Renommer -and -not $p.Deplacer -and
        [string]::IsNullOrWhiteSpace([string]$p.OU_Actuelle) -and -not [string]::IsNullOrWhiteSpace([string]$p.OU_Destination) -and
        (Test-PestoComputerName ([string]$p.Nom_du_PC)) -and (Test-PestoGeneratedComputerName ([string]$p.Nouveau_Nom)))
}


function Assert-PestoJoinEvidence {
    param([Parameter(Mandatory=$true)]$Evidence)
    $names=@('MachineId','BeforeBootUtc','PreparedUtc','NativeStatus','BoundObjectGuid')
    Assert-PestoClosedObject $Evidence $names $names
    foreach($name in $names){if($Evidence.$name -isnot [string] -or $Evidence.$name.Length -gt 512 -or $Evidence.$name -match '[\x00-\x1f\x7f]'){throw 'Métadonnée de jonction invalide.'}}
    if(-not $Evidence.MachineId -or $Evidence.NativeStatus -cnotin @('Unknown','Prepared','Requested','Accepted','Refused')){throw 'État de commande de jonction invalide.'}
    foreach($name in @('BeforeBootUtc','PreparedUtc')){$date=[DateTimeOffset]::MinValue;if($Evidence.$name -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse($Evidence.$name,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Date de jonction non reconnue.'}}
    if($Evidence.BoundObjectGuid){$id=[Guid]::Empty;if(-not [Guid]::TryParse($Evidence.BoundObjectGuid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID lié à la jonction invalide.'}}
    if([DateTimeOffset]::Parse($Evidence.BeforeBootUtc) -gt [DateTimeOffset]::Parse($Evidence.PreparedUtc)){throw 'Chronologie de jonction incohérente.'}
    return $Evidence
}


function Get-PestoJoinObservationDecision {
    param($Receipt,$Observation,[string]$LocalMachineId)
    $d=[ordered]@{Verified=$false;ResumeMove=$false;PendingRestart=$false;Message='Jonction à vérifier. Aucun renommage ni nouvel ajout proposé.';BoundObjectGuid=''}
    if(-not(Test-PestoJoinIntervention $Receipt) -or -not $Receipt.JoinEvidence){$d.Message='Ancienne jonction sans preuve initiale : importer son reçu local avant de la vérifier.';return [pscustomobject]$d}
    $e=Assert-PestoJoinEvidence $Receipt.JoinEvidence;$p=$Receipt.Plan;$w=$Observation.Windows;$ad=$Observation.AD;$health=$Observation.Health
    if(-not $LocalMachineId -or $LocalMachineId -ine $e.MachineId -or $Receipt.TargetMachineId -ine $e.MachineId -or
       -not $w -or $w.MachineId -ine $e.MachineId){$d.Message='Cette jonction doit être vérifiée depuis le PC concerné. Identité locale non confirmée.';return [pscustomobject]$d}
    [void](ConvertTo-PestoObservationSnapshot $Observation)
    if($w.PartOfDomain -isnot [bool] -or -not $w.PartOfDomain -or $w.Domain -ine $p.Domain -or $w.DomainRole -notin @(1,3)){
        $d.Message='Windows ne confirme pas encore le domaine attendu. Aucune nouvelle jonction automatique.';return [pscustomobject]$d
    }
    if($w.ActiveName -ine $p.Nouveau_Nom -or $w.ConfiguredName -ine $p.Nouveau_Nom){$d.PendingRestart=($w.ConfiguredName -ieq $p.Nouveau_Nom);$d.Message='Le nom Windows actif ou configuré diffère du nom demandé. Vérifier le redémarrage.';return [pscustomobject]$d}
    $before=[DateTimeOffset]::Parse($e.BeforeBootUtc,[Globalization.CultureInfo]::InvariantCulture);$boot=[DateTimeOffset]::MinValue
    if([string]$w.BootUtc -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse([string]$w.BootUtc,[ref]$boot) -or $boot -le $before -or $boot -le [DateTimeOffset]::Parse($e.PreparedUtc,[Globalization.CultureInfo]::InvariantCulture)){$d.PendingRestart=$true;$d.Message='Aucun démarrage postérieur au reçu initial n''est confirmé. Redémarrage explicite puis nouvelle lecture.';return [pscustomobject]$d}
    $gid=[Guid]::Empty
    if(-not $ad -or $ad.Name -ine $p.Nouveau_Nom -or $ad.OU -ine $p.OU_Destination -or
       -not [Guid]::TryParse([string]$ad.Guid,[ref]$gid) -or $gid -eq [Guid]::Empty){$d.Message='Nom, emplacement et identité AD de la jonction non confirmés.';return [pscustomobject]$d}
    if($p.TargetOUGuid -and $Observation.JoinDestinationGuid -ine $p.TargetOUGuid){$d.Message='L''identité de l''OU de destination n''est pas confirmée. Aucun verrou levé.';return [pscustomobject]$d}
    if(($p.Objet_GUID -and $p.Objet_GUID -ine $gid.ToString('D')) -or ($e.BoundObjectGuid -and $e.BoundObjectGuid -ine $gid.ToString('D'))){$d.Message='Le compte ordinateur a changé d''identité depuis le reçu. Aucun verrou levé.';return [pscustomobject]$d}
    # Une chaîne non vide telle que "false" n'est pas une preuve du canal sécurisé.
    $secure=$health -and (($health.SecureChannel -is [bool] -and $health.SecureChannel) -or ($health.SecureChannel -is [string] -and $health.SecureChannel -ceq 'Conforme'))
    if(-not $secure){$d.Message='Le canal sécurisé local n''est pas confirmé. Aucune réparation automatique.';return [pscustomobject]$d}
    foreach($dateText in @($Observation.ObservedUtc,$Observation.ADUtc,$Observation.WindowsUtc,$health.Utc)){
        $date=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse([string]$dateText,[ref]$date)){$d.Message='Une date de lecture manque. Relire avant de consigner.';return [pscustomobject]$d}
        $age=([DateTimeOffset]::UtcNow-$date).TotalSeconds
        if($age -lt 0 -or $age -gt 120){$d.Message='Une source de la vérification est ancienne. Relire avant de consigner.';return [pscustomobject]$d}
    }
    $d.Verified=$true;$d.BoundObjectGuid=$gid.ToString('D');$d.Message='Nom actif, domaine, identité du PC, compte AD, emplacement et canal sécurisé confirmés après redémarrage. Entra reste un contrôle distinct.'
    return [pscustomobject]$d
}


$receipt=@'
{"Schema": 3, "Version": "1.0", "OperationId": "2efe6815e02941b9a7c36ef277b8bba3", "Plan": {"Nom_du_PC": "PESTO-W11-TEST", "Nouveau_Nom": "V999004AAQA1001", "OU_Actuelle": "", "OU_Destination": "OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local", "Objet_GUID": "", "Domain": "labo.local", "DC": "dc01.labo.local", "ConfigStamp": "4928F1F81841BD7B338D178B1349BFCFDFCFE9CDB7D003D36DAABDC26C53233E", "TargetOUGuid": "02826a0f-e401-4934-850a-c9872a33b4ce", "Renommer": false, "Deplacer": false, "Reboot": false}, "StartedUtc": "2026-10-04T17:48:03.4863014Z", "UpdatedUtc": "2026-10-04T18:04:42.8597310Z", "Phase": "Verified", "InitialProtection": null, "TargetMachineId": "81387449-2dd8-4bd9-8059-f868a5b8ec68", "TargetOUGuid": "", "Entra": "NotRequested", "Protection": "NotChanged", "Rename": "NotRequested", "Move": "NotRequested", "ResultCode": 10, "ResultMessage": "\"PESTO-W11-TEST\" ajouté au domaine \"labo.local\" → nom \"V999004AAQA1001\" / OU \"OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local\"", "LastStage": "Postconditions observed", "VerifiedUtc": "2026-10-04T18:04:41.8596879Z", "VerifiedBy": "LABO\\pesto-qualif", "ResumeFrom": "", "PlanFingerprint": "5ca869684aca1c21819308c55a4b62f623368b92942c11d0c711434d1fd0743e", "Coordination": {"Enabled": false, "Keys": [], "Owner": "2efe6815e02941b9a7c36ef277b8bba3"}, "Baseline": {"Schema": 1, "CapturedUtc": "2026-10-04T17:48:03.5652640Z", "ADUtc": "", "WindowsUtc": "2026-10-04T17:48:03.5652640Z", "HealthUtc": "", "AD": null, "Windows": {"ActiveName": "PESTO-W11-TEST", "ConfiguredName": "PESTO-W11-TEST", "Domain": "LABO", "PartOfDomain": false, "MachineId": "81387449-2dd8-4bd9-8059-f868a5b8ec68", "BootUtc": "2026-10-04T17:26:26.5000000Z", "DomainRole": 0}, "Health": null}, "JoinEvidence": {"MachineId": "81387449-2dd8-4bd9-8059-f868a5b8ec68", "BeforeBootUtc": "2026-10-04T17:26:26.5000000Z", "PreparedUtc": "2026-10-04T17:48:03.5652640Z", "NativeStatus": "Accepted", "BoundObjectGuid": "568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b"}, "Sequence": 6, "Timeline": [{"Sequence": 1, "Utc": "2026-10-04T17:48:03.5385569Z", "Stage": "TargetMachineId", "State": "81387449-2dd8-4bd9-8059-f868a5b8ec68"}, {"Sequence": 2, "Utc": "2026-10-04T17:48:03.6148986Z", "Stage": "JoinBaseline", "State": "RecordedBeforeCommand"}, {"Sequence": 3, "Utc": "2026-10-04T17:48:03.7280099Z", "Stage": "Join", "State": "Requested"}, {"Sequence": 4, "Utc": "2026-10-04T17:48:07.9090011Z", "Stage": "Join", "State": "Accepted"}, {"Sequence": 5, "Utc": "2026-10-04T17:48:07.9515307Z", "Stage": "Result", "State": "PendingRestart"}, {"Sequence": 6, "Utc": "2026-10-04T18:01:18.8717082Z", "Stage": "Observation", "State": "RecordedNotResolved"}], "LastObservation": {"Schema": 1, "CapturedUtc": "2026-10-04T18:04:41.8596879Z", "ADUtc": "2026-10-04T18:04:41.0491831Z", "WindowsUtc": "2026-10-04T18:04:41.1245010Z", "HealthUtc": "2026-10-04T18:04:41.1245010Z", "AD": {"Name": "V999004AAQA1001", "Guid": "568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b", "OU": "OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local", "Protected": false}, "Windows": {"ActiveName": "V999004AAQA1001", "ConfiguredName": "V999004AAQA1001", "Domain": "labo.local", "PartOfDomain": true, "MachineId": "81387449-2dd8-4bd9-8059-f868a5b8ec68", "BootUtc": "2026-10-04T17:55:26.5000000Z", "DomainRole": 1}, "Health": {"Scope": "Appareil local, compte du processus ; pas SSO utilisateur", "AzureAdJoined": "NO", "DomainJoined": "YES", "SecureChannel": true}}}
'@|ConvertFrom-Json
$observation=@'
{"ObservedUtc": "2026-10-04T17:53:50.8982900Z", "ADUtc": "2026-10-04T17:53:49.1631432Z", "WindowsUtc": "2026-10-04T17:53:49.6329424Z", "RequestedComputer": "V999004AAQA1001", "AD": {"Name": "V999004AAQA1001", "Guid": "568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b", "DN": "CN=V999004AAQA1001,OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local", "OU": "OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local", "Enabled": true, "Protected": false}, "Windows": {"ActiveName": "V999004AAQA1001", "ConfiguredName": "V999004AAQA1001", "Domain": "labo.local", "PartOfDomain": true, "MachineId": "81387449-2dd8-4bd9-8059-f868a5b8ec68", "BootUtc": "2026-10-04T17:51:29.5000000Z", "Transport": "Local", "DomainRole": 1, "QueriedHost": "V999004AAQA1001"}, "Health": {"Utc": "2026-10-04T17:53:49.6329424Z", "Scope": "Appareil local, compte du processus ; pas SSO utilisateur", "AzureAdJoined": "NO", "DomainJoined": "YES", "SecureChannel": "Conforme", "Errors": []}, "JoinDestinationGuid": "02826a0f-e401-4934-850a-c9872a33b4ce", "Errors": []}
'@|ConvertFrom-Json
$machine=Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' MachineGuid
if($machine -eq $receipt.TargetMachineId){throw 'Ce test doit tourner sur un autre PC reel'}
$r=Get-PestoJoinObservationDecision -Receipt $receipt -Observation $observation -LocalMachineId $machine
if($r.Verified -or $r.Message -notmatch 'depuis le PC concerné'){throw 'Refus autre PC non confirme'}
[pscustomobject]@{Date=(Get-Date -Format o);Machine=$env:COMPUTERNAME;MachineGuid=$machine;ReceiptMachine=$receipt.TargetMachineId;Engine=$PSVersionTable.PSVersion.ToString();Decision=$r;ReceiptSource='jonction-verifiee-recus.json';NoWriteToGP=$true;NoADCommand=$true}|ConvertTo-Json -Depth 4
