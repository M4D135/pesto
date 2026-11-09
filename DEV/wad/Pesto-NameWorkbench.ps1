#requires -Version 5.1
# Outils de lecture : aucun nom n'est réservé ni aucune commande consentie ici.
function Get-PestoCapacityThresholdRows {
    param([object[]]$Rows,[ValidateRange(0,999999)][int]$MaximumFree=999999)
    foreach($row in @($Rows|Where-Object{$_.Libres -le $MaximumFree}|Sort-Object Libres,Site,Service,Type)){
        [pscustomobject]@{Site=$row.Site;Service=$row.Service;Type=$row.Type;Origine=$row.Origine;Libres=$row.Libres;Occupes=$row.Occupes;Prepares=$row.Prepares;Niveau=$(if($row.Libres -eq 0){'Épuisé'}elseif($row.Libres -le 10){'Critique : 10 ou moins'}elseif($row.Libres -le 50){'À anticiper : 50 ou moins'}else{'Disponible dans le cache'})}
    }
}
function Show-PestoReviewTable {
    param([ValidateSet('capacity','conformity')][string]$Kind,$Result)
    if(-not$script:PestoReviewViews){$script:PestoReviewViews=@{}}
    $script:PestoReviewViews[$Kind]=$Result
    if($Kind -eq 'capacity'){
        $old=if($script:PestoCapacityLimit -ge 0 -and $null -ne $script:PestoCapacityLimit){$script:PestoCapacityLimit}else{Get-PestoNameMaximumNumber}
        $limit=Show-PestoPanel -Title 'Filtrer la capacité' -Body 'Nombre maximal de noms libres par combinaison. 10 : critique ; 50 : à anticiper ; seuil maximal : toutes. Les préparations ne sont pas des réservations AD.' -InputLabel 'Noms libres au maximum (0 au maximum de la convention)' -InitialValue ([string]$old) -AcceptText 'Afficher le tableau'
        if(-not$limit.Accepted){return};$number=0;if(-not[int]::TryParse($limit.Text,[ref]$number) -or $number -lt 0 -or $number -gt (Get-PestoNameMaximumNumber)){throw 'Le seuil doit être un entier de 0 au maximum de la convention.'};$script:PestoCapacityLimit=$number
        $rows=@(Get-PestoCapacityThresholdRows $Result.Rows $number);$columns=@(@{Key='Site';Label='Site'},@{Key='Service';Label='Service'},@{Key='Type';Label='Type'},@{Key='Libres';Label='Libres'},@{Key='Occupes';Label='Dans AD'},@{Key='Prepares';Label='Préparés'},@{Key='Niveau';Label='Seuil'},@{Key='Origine';Label='Origine'})
    }else{$rows=@($Result.Rows|Where-Object{$_.Etat -ne 'Conforme au nom et au site'});$columns=@(@{Key='Poste';Label='Poste'},@{Key='Etat';Label='Écart observé'},@{Key='Detail';Label='Explication'},@{Key='OU';Label='OU observée'},@{Key='OUAttendues';Label='OU attendue'})}
    [void](Show-PestoChoiceTable -Title $(if($Kind -eq 'capacity'){'Capacité de nommage'}else{'Anomalies de convention'}) -Description ('Instantané : '+$Result.InventoryUtc+'. '+$rows.Count+' ligne(s) dans cette vue, '+$Result.Count+' analysées. Recherche et tri locaux ; aucune réparation automatique.') -Rows $rows -Columns $columns)
}
function Get-PestoNameExclusionDetails {
    param([string]$Name,$Row,[object[]]$Queue=@(),[string[]]$Personal=@(),[hashtable]$Shared=@{},[string]$InventoryUtc='')
    $lines=[Collections.Generic.List[object]]::new()
    if($Row.InAD){$lines.Add([pscustomobject]@{Origine='Inventaire AD';Etat='Nom occupé dans le périmètre chargé';Date=$(if($Row.SourceUtc){[string]$Row.SourceUtc}elseif($InventoryUtc){$InventoryUtc}else{'Date inconnue'});Limite='Une lecture ciblée plus récente peut être nécessaire.'})}
    if(@($Queue|Where-Object{[string]$_.Nouveau_Nom -ieq $Name}).Count){$lines.Add([pscustomobject]@{Origine='File de cette session';Etat='Nom prévu par une ligne';Date='État courant en mémoire';Limite='Préparation locale, pas réservation AD.'})}
    if($Name -in $Personal){$lines.Add([pscustomobject]@{Origine='Mes choix retenus';Etat='Préparation personnelle';Date='Date de création non enregistrée';Limite='N''empêche pas une attribution par un autre opérateur.'})}
    $entry=$Shared[$Name.ToUpperInvariant()]
    if($entry){$lines.Add([pscustomobject]@{Origine='Coordination configurée';Etat='Nom détenu par un autre opérateur';Date=('Expiration annoncée : '+[string]$entry.ExpiresUtc);Limite='Relire la coordination avant de conclure à sa disponibilité.'})}
    if(-not$lines.Count){$lines.Add([pscustomobject]@{Origine='Projection du filtre';Etat=$(if($Row.Reserved){'Exclusion dont la provenance détaillée est indisponible'}else{'Aucune exclusion dans cette projection'});Date=$(if($Row.SourceUtc){$Row.SourceUtc}else{'Date inconnue'});Limite='Ne prouve ni disponibilité actuelle dans tout le domaine ni réservation.'})}
    return $lines.ToArray()
}
function Get-PestoHardwareSuggestion {
    param([string]$Manufacturer,[string]$Model,[int[]]$Chassis=@())
    $type='';$reason='Informations insuffisantes : choisissez le type manuellement.'
    if(($Manufacturer+' '+$Model) -match '(?i)virtual|vmware|virtualbox|kvm|qemu|hyper-v|parallels'){$type='Virtuel';$reason='Le fabricant ou le modèle déclare une plateforme virtuelle.'}
    elseif(@($Chassis|Where-Object{$_ -in @(8,9,10,11,12,14,18,21,30,31,32)}).Count){$type='Portable';$reason='Le châssis Windows correspond à un équipement mobile.'}
    elseif(@($Chassis|Where-Object{$_ -in @(3,4,5,6,7,13,15,16,17,23,24,35,36)}).Count){$type='Fixe';$reason='Le châssis Windows correspond à un équipement fixe.'}
    [pscustomobject]@{Type=$type;Reason=$reason;Manufacturer=$Manufacturer;Model=$Model}
}
function Invoke-PestoHardwareRead {
    param([string]$Source)
    . ([scriptblock]::Create($Source));$system=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction Stop;$enclosure=Get-CimInstance Win32_SystemEnclosure -OperationTimeoutSec 8 -ErrorAction Stop
    Get-PestoHardwareSuggestion -Manufacturer $system.Manufacturer -Model $system.Model -Chassis @($enclosure.ChassisTypes)
}
function Invoke-PestoNameWorkbench {
    param($Sender,$EventArgs)
    try{
        if($Sender.Name -eq 'NmExclusionDetails'){$row=$NmGrid.SelectedItem;if(-not$row){throw 'Sélectionnez un nom dans le tableau.'};$rows=@(Get-PestoNameExclusionDetails -Name $row.Nom -Row $row -Queue @($script:table.Rows) -Personal @(Read-PestoNameReservations) -Shared $(if($script:SharedNameOthers){$script:SharedNameOthers}else{@{}}) -InventoryUtc $script:InventoryUtc);[void](Show-PestoChoiceTable -Title ('Origine : '+$row.Nom) -Description 'Les dates inconnues sont conservées comme inconnues. Aucune réservation créée.' -Rows $rows -Columns @(@{Key='Origine';Label='Origine'},@{Key='Etat';Label='État observé'},@{Key='Date';Label='Date / validité'},@{Key='Limite';Label='Portée'}));return}
        if($Sender.Name -in @('NmCapacity','NmConformity')){Show-PestoInventoryReview -Kind $(if($Sender.Name -eq 'NmCapacity'){'capacity'}else{'conformity'});return}
        if($Sender.Name -eq 'PrepHardware'){
            if($script:DirectBusy -or $script:Running -or $script:JoinBusy -or $script:CfgRestartRequired -or -not$CbType.IsEnabled){throw 'Lisez un poste et terminez le traitement avant de proposer un type.'}
            if(([string]$TxtPCName.Text).Trim() -ine [Environment]::MachineName){throw 'Cette suggestion utilise uniquement le matériel de ce PC local. Pour un poste distant, choisissez le type manuellement.'}
            if($script:GUI -or $script:SIM){throw 'Le matériel réel n''est pas interrogé en démonstration ou simulation.'}
            $source='function Get-PestoHardwareSuggestion {'+${function:Get-PestoHardwareSuggestion}.ToString()+'}'
            $context=[pscustomobject]@{Computer=[string]$TxtPCName.Text;Type=[string]$CbType.SelectedItem}
            $ok=Start-PestoAsyncOperation -Name 'HardwareSuggestion' -ScriptBlock ${function:Invoke-PestoHardwareRead} -ArgumentList @($source) -TimeoutSec 25 -CallbackContext $context -OnError {param($e,$c) Show-MsgWarning ('Matériel non lu : '+$e.Exception.Message)} -OnSuccess {param($r,$c)
                if($script:DirectBusy -or $script:Running -or $script:JoinBusy -or $script:CfgRestartRequired -or [string]$TxtPCName.Text -cne $c.Computer -or [string]$CbType.SelectedItem -cne $c.Type){return}
                $body=$r.Reason+"`n"+$r.Manufacturer+' '+$r.Model+"`nSuggestion modifiable ; la convention locale reste prioritaire."
                if(-not$r.Type){Show-MsgInfo $body;return}
                if(Confirm-YesNo -Msg $body -Confirm $true -AcceptText ('Proposer '+$r.Type) -SummaryRows @(@{Field='Type';Before=$c.Type;After=$r.Type})){$CbType.SelectedItem=$r.Type;$script:DirectCheckedKey=''}
            };if(-not$ok){throw 'Lecture matérielle non lancée. Réessayez après la lecture en cours.'}
        }
    }catch{Show-MsgWarning $_.Exception.Message}
}
function Initialize-PestoNameWorkbench {
    foreach($name in @('NmCapacity','NmConformity','NmExclusionDetails','PrepHardware')){$button=$Win.FindName($name);if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoNameWorkbench})}}
}
