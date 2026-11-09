#requires -Version 5.1
# Observations en lecture seule. Un ancien nom encore visible n'est pas la preuve d'une annulation.

function Get-PestoLocalHealth {
    param([string]$Server='')
    $out=[ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Scope='Appareil local, compte du processus ; pas SSO utilisateur';AzureAdJoined='Unknown';DomainJoined='Unknown';SecureChannel='Unknown';Errors=@()}
    $errors=[Collections.Generic.List[string]]::new();$process=$null
    try {
        $exe=Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
        $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe;$start.Arguments='/status';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new();$process.StartInfo=$start
        if(-not $process.Start()){throw 'Lecture dsregcmd non lancée.'}
        $text=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(120000)){try{$process.Kill()}catch{};throw 'Lecture dsregcmd expirée ; aucun retrait demandé.'}
        if($process.ExitCode -ne 0){throw 'Lecture dsregcmd refusée.'}
        $raw=[string]$text.GetAwaiter().GetResult()
        if($raw.Length -gt 131072){throw 'Réponse de statut trop volumineuse.'}
        foreach($name in @('AzureAdJoined','DomainJoined')){
            $found=[regex]::Matches($raw,'(?im)^\s*'+$name+'\s*:\s*(YES|NO)\s*$')
            if($found.Count -eq 1){$out[$name]=$found[0].Groups[1].Value.ToUpperInvariant()}
        }
        $raw=$null
    } catch {$errors.Add('État Entra local non confirmé.')} finally {if($process){$process.Dispose()}}
    try {
        $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if($cs.PartOfDomain -eq $true -and $cs.DomainRole -in @(1,3)){
            $adArgs=@{ErrorAction='Stop'};if($Server){$adArgs.Server=$Server}
            $ok=Test-ComputerSecureChannel @adArgs
            if($ok -is [bool]){$out.SecureChannel=if($ok){'Conforme'}else{'À vérifier'}}
        }
    }catch{$errors.Add('Canal sécurisé non vérifié ; aucune réparation demandée.')}
    $out.Errors=$errors.ToArray();return [pscustomobject]$out
}

function Get-PestoPostObservation {
    param($Request)
    $result=[ordered]@{ObservedUtc='';ADUtc='';WindowsUtc='';RequestedComputer=[string]$Request.Computer;AD=$null;Windows=$null;Health=$null;JoinDestinationGuid='';Errors=@()}
    $errors=[Collections.Generic.List[string]]::new()
    if(-not(Test-PestoComputerName ([string]$Request.Computer))){throw 'Nom du poste invalide.'}
    $adp=@{Server=[string]$Request.DC;ErrorAction='Stop'}
    if($Request.Credential){$adp.Credential=$Request.Credential}
    try {
        Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
        $id=[Guid]::Empty
        if([Guid]::TryParse([string]$Request.ObjectGuid,[ref]$id) -and $id -ne [Guid]::Empty){
            $objects=@(Get-ADComputer -Identity $id -Properties ObjectGUID,DistinguishedName,Enabled,ProtectedFromAccidentalDeletion @adp)
        }else{
            $literal=ConvertTo-PestoFilterLiteral ([string]$Request.Computer)
            $objects=@(Get-ADComputer -LDAPFilter "(|(name=$literal)(sAMAccountName=$literal`$))" -ResultSetSize 2 -Properties ObjectGUID,DistinguishedName,Enabled,ProtectedFromAccidentalDeletion @adp)
        }
        if($objects.Count -ne 1){throw 'L''objet AD n''est pas identifié de manière unique.'}
        $ad=$objects[0]
        $result.AD=[pscustomobject]@{Name=[string]$ad.Name;Guid=([Guid]$ad.ObjectGUID).ToString('D');DN=[string]$ad.DistinguishedName;OU=(Get-PestoParentDN ([string]$ad.DistinguishedName));Enabled=[bool]$ad.Enabled;Protected=[bool]$ad.ProtectedFromAccidentalDeletion}
        if($Request.JoinTargetOU){
            if(-not(Test-PestoOUPath ([string]$Request.JoinTargetOU))){throw 'Emplacement de jonction invalide.'}
            $dest=@(Get-ADOrganizationalUnit -Identity ([string]$Request.JoinTargetOU) -Properties ObjectGUID @adp)
            if($dest.Count -ne 1){throw 'Destination de jonction non unique.'}
            $result.JoinDestinationGuid=([Guid]$dest[0].ObjectGUID).ToString('D')
        }
        $result.ADUtc=[DateTime]::UtcNow.ToString('o')
    }catch{$errors.Add('AD : '+(Protect-PestoLogText $_.Exception.Message))}
    if($Request.LocalSource -or [string]$Request.Computer -ieq $env:COMPUTERNAME){
        try{
            $local=Get-PestoJoinLocalStatus
            $result.Windows=[pscustomobject]@{ActiveName=$local.ActiveName;ConfiguredName=$local.ConfiguredName;Domain=$local.Domain;PartOfDomain=$local.PartOfDomain;MachineId=$local.MachineId;BootUtc=$local.BootUtc;Transport='Local';DomainRole=$local.DomainRole;QueriedHost=$env:COMPUTERNAME}
            $result.WindowsUtc=[DateTime]::UtcNow.ToString('o')
        }catch{$errors.Add('Windows local : '+(Protect-PestoLogText $_.Exception.Message))}
    }else{
        $targets=@([string]$Request.Computer,[string]$Request.AlternativeComputer)|Where-Object{Test-PestoComputerName $_}|Select-Object -Unique
        foreach($target in $targets){
            $session=$null
            try{
                $options=New-CimSessionOption -PacketPrivacy
                $cp=@{ComputerName=$target;SessionOption=$options;OperationTimeoutSec=12;ErrorAction='Stop'}
                if($Request.Credential){$cp.Credential=$Request.Credential}
                $session=New-CimSession @cp
                $cs=Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $session -OperationTimeoutSec 12 -ErrorAction Stop
                if($Request.RenamePreflight -eq $true){
                    # Renommage distant : WMI/DCOM confirme la cible. Ni WinRM,
                    # ni l'heure de démarrage, ni MachineGuid ne sont prérequis.
                    if(@($cs).Count -ne 1 -or -not (Test-PestoComputerName ([string]$cs.Name)) -or
                       $cs.PartOfDomain -isnot [bool] -or
                       ($cs.DomainRole -isnot [uint16] -and $cs.DomainRole -isnot [uint32] -and $cs.DomainRole -isnot [int]) -or
                       $cs.DomainRole -notin @(0,1,2,3,4,5)){
                        throw 'Identité Windows distante incomplète.'
                    }
                    $values=@{ConfiguredName='';MachineId=''}
                    foreach($spec in @(
                        @('ConfiguredName','SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName','ComputerName'),
                        @('MachineId','SOFTWARE\Microsoft\Cryptography','MachineGuid'))){
                        try{
                            $v=Invoke-CimMethod -CimSession $session -Namespace 'root/default' -ClassName StdRegProv -MethodName GetStringValue -Arguments @{hDefKey=[uint32]2147483650;sSubKeyName=$spec[1];sValueName=$spec[2]} -OperationTimeoutSec 2 -ErrorAction Stop
                            if($null -eq $v -or $v.ReturnValue -ne 0 -or -not $v.sValue){throw 'Valeur indisponible.'}
                            if($spec[0] -eq 'ConfiguredName' -and -not (Test-PestoComputerName ([string]$v.sValue))){throw 'Nom configuré illisible.'}
                            if($spec[0] -eq 'MachineId'){
                                $machine=[Guid]::Empty
                                if(-not [Guid]::TryParse([string]$v.sValue,[ref]$machine) -or $machine -eq [Guid]::Empty){throw 'MachineGuid illisible.'}
                            }
                            $values[$spec[0]]=[string]$v.sValue
                        }catch{$errors.Add('Lecture facultative '+$spec[0]+' : '+(Protect-PestoLogText $_.Exception.Message))}
                    }
                    $result.Windows=[pscustomobject]@{ActiveName=[string]$cs.Name;ConfiguredName=$values.ConfiguredName;
                        Domain=[string]$cs.Domain;PartOfDomain=[bool]$cs.PartOfDomain;MachineId=$values.MachineId;
                        BootUtc='';Transport='WMI / DCOM';DomainRole=[int]$cs.DomainRole;QueriedHost=$target}
                    $result.WindowsUtc=[DateTime]::UtcNow.ToString('o')
                    break
                }
                $os=Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $session -OperationTimeoutSec 12 -ErrorAction Stop
                $values=@{}
                foreach($spec in @(
                    @('ActiveName','SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName','ComputerName'),
                    @('ConfiguredName','SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName','ComputerName'),
                    @('MachineId','SOFTWARE\Microsoft\Cryptography','MachineGuid'))){
                    $v=Invoke-CimMethod -CimSession $session -Namespace 'root/default' -ClassName StdRegProv -MethodName GetStringValue -Arguments @{hDefKey=[uint32]2147483650;sSubKeyName=$spec[1];sValueName=$spec[2]} -OperationTimeoutSec 12 -ErrorAction Stop
                    if($null -eq $v -or ($v.ReturnValue -isnot [uint32] -and $v.ReturnValue -isnot [int]) -or $v.ReturnValue -ne 0 -or -not $v.sValue){throw 'Lecture du registre distant incomplète.'}
                    $values[$spec[0]]=[string]$v.sValue
                }
                if(@($cs).Count -ne 1 -or @($os).Count -ne 1 -or -not $cs.Name -or $cs.PartOfDomain -isnot [bool] -or
                   ($cs.DomainRole -isnot [uint16] -and $cs.DomainRole -isnot [uint32] -and $cs.DomainRole -isnot [int]) -or
                   $cs.DomainRole -notin @(0,1,2,3,4,5) -or -not $os.LastBootUpTime){throw 'Réponse Windows distante incomplète.'}
                $result.Windows=[pscustomobject]@{ActiveName=$values.ActiveName;ConfiguredName=$values.ConfiguredName;Domain=[string]$cs.Domain;PartOfDomain=[bool]$cs.PartOfDomain;MachineId=$values.MachineId;BootUtc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o');Transport='WMI / DCOM';DomainRole=[int]$cs.DomainRole;QueriedHost=$target}
                $result.WindowsUtc=[DateTime]::UtcNow.ToString('o')
                break
            }catch{$errors.Add("Windows distant ($target) : "+(Protect-PestoLogText $_.Exception.Message))}
            finally{if($session){Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue}}
        }
    }
    if($Request.ReadHealth -eq $true -and ($Request.LocalSource -or $Request.Computer -ieq $env:COMPUTERNAME)){$result.Health=Get-PestoLocalHealth -Server $Request.DC}
    $result.ObservedUtc=[DateTime]::UtcNow.ToString('o');$result.Errors=$errors.ToArray()
    return [pscustomobject]$result
}

function Get-PestoObservationDecision {
    param($Plan,$Observation,[string]$TargetMachineId,[int]$PreviousCode=0)
    $decision=[ordered]@{Verified=$false;ResumeMove=$false;PendingRestart=$false;Message='État incomplet ou non conforme au plan. Aucune relance automatique.'}
    if(-not $Plan -or -not $Observation -or -not $Observation.AD){return [pscustomobject]$decision}
    $ad=$Observation.AD;$w=$Observation.Windows
    $guid=[Guid]::Empty;$observedGuid=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$Plan.Objet_GUID,[ref]$guid) -or $guid -eq [Guid]::Empty -or
       -not [Guid]::TryParse([string]$ad.Guid,[ref]$observedGuid) -or $guid -ne $observedGuid){
        $decision.Message='Identité AD non confirmée par le GUID préparé. Vérification manuelle requise.';return [pscustomobject]$decision
    }
    if($Plan.Renommer -and ([string]::IsNullOrWhiteSpace([string]$Plan.Nouveau_Nom) -or [string]$Plan.Nouveau_Nom -ieq [string]$Plan.Nom_du_PC)){
        $decision.Message='Plan de renommage sans nouveau nom distinct. Aucun renommage ne peut être confirmé ; vérification manuelle requise.';return [pscustomobject]$decision
    }
    $expected=if($Plan.Renommer){[string]$Plan.Nouveau_Nom}else{[string]$Plan.Nom_du_PC}
    $expectedOU=if($Plan.Deplacer){[string]$Plan.OU_Destination}else{[string]$Plan.OU_Actuelle}
    if($ad.Name -ine $expected){$decision.Message='L''objet AD n''a pas le nom final attendu. Cela ne prouve pas qu''une commande en cours a été annulée.';return [pscustomobject]$decision}
    if($Plan.PSObject.Properties['InitialProtection'] -and $Plan.InitialProtection -is [bool] -and $ad.Protected -ne $Plan.InitialProtection){$decision.Message='Protection AD différente de l''état initial enregistré. Rétablissement explicite requis.';return [pscustomobject]$decision}
    if($PreviousCode -in @(32,97,98,99) -and $Plan.Deplacer -and -not $Plan.PSObject.Properties['InitialProtection']){$decision.Message='Protection initiale inconnue pour cette ancienne opération. Vérification manuelle requise ; aucun verrou effacé.';return [pscustomobject]$decision}
    $sameWindows=$w -and $TargetMachineId -and $w.MachineId -ieq $TargetMachineId -and $w.PartOfDomain -eq $true -and $w.Domain -ieq $Plan.Domain
    $renameRecorded=$sameWindows -and $w.ConfiguredName -ieq $expected
    if($Plan.Renommer -and $Plan.Deplacer -and $ad.OU -ine $expectedOU -and ($PreviousCode -eq 89 -or $renameRecorded)){
        $decision.ResumeMove=$true
        $decision.Message='Renommage confirmé ou observé. Le déplacement reste à préparer séparément ; aucun renommage ne sera rejoué.'
        return [pscustomobject]$decision
    }
    if($ad.OU -ine $expectedOU){$decision.Message='L''objet AD n''est pas dans l''emplacement attendu. Ne relancez pas l''ensemble du plan.';return [pscustomobject]$decision}
    if(-not $Plan.Renommer){$decision.Verified=$true;$decision.Message='GUID, nom et emplacement AD conformes au déplacement demandé.';return [pscustomobject]$decision}
    if($renameRecorded -and $w.ActiveName -ine $expected){
        $decision.PendingRestart=$true;$decision.Message='Le nouveau nom est inscrit, mais Windows utilise encore l''ancien. Redémarrez selon votre procédure, puis vérifiez à nouveau.';return [pscustomobject]$decision
    }
    if($renameRecorded -and $w.ActiveName -ieq $expected){
        $decision.Verified=$true;$decision.Message='Identité Windows, nom actif, nom configuré et objet AD conformes au plan.';return [pscustomobject]$decision
    }
    $decision.Message='AD est conforme, mais l''identité et le nom actif Windows ne sont pas suffisamment confirmés. Aucune levée de verrou automatique.'
    return [pscustomobject]$decision
}

function Get-PestoInspectionSource {
    $names=@('Import-PestoADModule','Assert-PestoPlainPath','Test-PestoComputerName','ConvertTo-PestoFilterLiteral','Split-PestoDistinguishedName','Get-PestoParentDN','Test-PestoDnsName','Get-PestoDomainFromDN','Test-PestoOUPath','Protect-PestoLogText','Test-PestoIsAdministrator','Get-PestoJoinLocalStatus','Get-PestoPostObservation','Get-PestoLocalHealth')
    $sb=[Text.StringBuilder]::new()
    foreach($n in $names){$cmd=Get-Command $n -CommandType Function -ErrorAction Stop;[void]$sb.AppendLine("function $n {");[void]$sb.AppendLine($cmd.Definition);[void]$sb.AppendLine('}')}
    return $sb.ToString()
}

$script:PestoInspectionWorker={
    param($Request,$Source)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    . ([scriptblock]::Create($Source))
    Get-PestoPostObservation $Request
}

function Format-PestoOUForDisplay {param([string]$OU) if($OU -eq '(mode GUI)'){'Démonstration : aucune OU lue'}else{$OU}}

function Format-PestoPostObservation {
    param($Observation,$Plan,$Receipt=$null)
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('ÉTAT OBSERVÉ, PAS UNE COMMANDE')
    $lines.Add('Lecture UTC : '+[string]$Observation.ObservedUtc)
    $lines.Add('')
    $ad=$Observation.AD;$w=$Observation.Windows
    $lines.Add('WINDOWS')
    if($w){
        $lines.Add('Nom actif : '+[string]$w.ActiveName)
        $lines.Add('Nom configuré : '+[string]$w.ConfiguredName)
        $lines.Add('Redémarrage pour le nom : '+$(if($w.ActiveName -ine $w.ConfiguredName){'En attente'}else{'Non indiqué par ces deux valeurs'}))
        $lines.Add('Domaine : '+[string]$w.Domain)
        $lines.Add('Dernier démarrage UTC : '+[string]$w.BootUtc)
        $lines.Add('Lecture : '+[string]$w.Transport+' / '+[string]$Observation.WindowsUtc)
    }else{$lines.Add('Non lu. Aucune conclusion sur le nom actif ou le redémarrage.')}
    $lines.Add('');$lines.Add('ACTIVE DIRECTORY')
    if($ad){
        $lines.Add('Nom : '+[string]$ad.Name);$lines.Add('GUID : '+[string]$ad.Guid)
        $lines.Add('Emplacement : '+(Format-PestoOUForDisplay (Format-OUPath ([string]$ad.OU))))
        $lines.Add('DN exact : '+[string]$ad.DN)
        $lines.Add('Protection anti-suppression : '+[string]$ad.Protected)
        $lines.Add('Lecture UTC : '+[string]$Observation.ADUtc)
    }else{$lines.Add('Objet non lu ou non identifié de manière unique.')}
    if($Plan){
        $lines.Add('');$lines.Add('PLAN CONSERVÉ')
        $lines.Add([string]$Plan.Nom_du_PC+' → '+[string]$Plan.Nouveau_Nom)
        if(Test-PestoJoinIntervention $Receipt){$lines.Add('Jonction locale : un ajout, sans file ni nouvelle commande depuis cette fiche.')}else{$lines.Add('Renommer : '+[string]$Plan.Renommer+' ; déplacer : '+[string]$Plan.Deplacer)}
        $lines.Add('OU finale prévue : '+$(if($Plan.Deplacer -or (Test-PestoJoinIntervention $Receipt)){Format-PestoOUForDisplay ([string]$Plan.OU_Destination)}else{Format-PestoOUForDisplay ([string]$Plan.OU_Actuelle)}))
    }
    if(@($Observation.Errors).Count){$lines.Add('');$lines.Add('LECTURES NON ABOUTIES');foreach($e in @($Observation.Errors)){$lines.Add([string]$e)}}
    if($Plan){$lines.Add('');$lines.Add('AVANT / PRÉVU / OBSERVÉ : le plan conservé reste inchangé.');$lines.Add((Get-PestoPostconditionChecklist -Plan $Plan -Observation $Observation -Receipt $Receipt|Format-Table Controle,Etat,@{n='Observe';e={Format-PestoOUForDisplay ([string]$_.Observe)}},@{n='Attendu';e={Format-PestoOUForDisplay ([string]$_.Attendu)}},Source -AutoSize|Out-String -Width 180))}
    return $lines -join "`r`n"
}

function Show-PestoPostState {
    param([ValidateSet('Inspect','Direct','Queue','Ledger')][string]$Mode='Inspect',$ReceiptOverride)
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy){Show-MsgInfo 'Attendez la fin de la supervision courante avant de lancer cette vérification.';return}
    if($script:PestoStateUi){[void]$script:PestoStateUi.Window.Activate();return}
    $row=$null;$receipt=$null;$plan=$null;$targetId='';$previousCode=0
    if($Mode -eq 'Ledger'){
        $receipt=$ReceiptOverride
        if(-not $receipt -or $receipt.Plan.Domain -ine $script:DOMAINE){Show-MsgWarning 'Sélectionnez une intervention du domaine courant.';return}
        if(-not $receipt.Plan.Objet_GUID -and -not(Test-PestoJoinIntervention $receipt)){Show-MsgInfo 'Ce reçu ne permet pas une lecture guidée. Vérification manuelle requise.';return}
        $plan=$receipt.Plan|Select-Object *;$targetId=[string]$receipt.TargetMachineId;$previousCode=[int]$receipt.ResultCode
        if($receipt.InitialProtection -is [bool]){$plan|Add-Member -NotePropertyName InitialProtection -NotePropertyValue $receipt.InitialProtection -Force}
    }elseif($Mode -eq 'Direct'){
        $receipt=$script:DirectReceipt
        if(-not $receipt){Show-MsgInfo 'Aucune opération unitaire à vérifier.';return}
        $plan=$receipt.Plan;$targetId=[string]$receipt.TargetMachineId;$previousCode=[int]$receipt.ResultCode
    }elseif($Mode -eq 'Queue'){
        $index=Get-PestoSelectedQueueIndex
        if($index -lt 0){Show-MsgInfo 'Sélectionnez une ligne pour vérifier son état réel. Aucun verrou n''est effacé sans observation.';return}
        $row=$script:table.Rows[$index]
        $plan=[pscustomobject]@{Nom_du_PC=[string]$row.Nom_du_PC;Nouveau_Nom=[string]$row.Nouveau_Nom;OU_Actuelle=[string]$row.OU_Actuelle;OU_Destination=[string]$row.OU_Destination;Objet_GUID=[string]$row.Objet_GUID;Renommer=[bool]$row.Renommer;Deplacer=[bool]$row.Deplacer;Domain=$script:DOMAINE}
        if([string]$row.InitialProtection -in @('True','False')){$plan|Add-Member -NotePropertyName InitialProtection -NotePropertyValue ([string]$row.InitialProtection -eq 'True')}
        $targetId=[string]$row.TargetMachineId
        [void][int]::TryParse([string]$row.Code,[ref]$previousCode)
    }else{
        $computer=([string]$TxtPCName.Text).Trim().ToUpperInvariant()
        if(-not(Test-PestoComputerName $computer)){Show-MsgInfo 'Saisissez un nom de poste valide.';return}
        $id='';if($script:ComputerIndex -and $script:ComputerIndex.ContainsKey($computer)){$id=[string]$script:ComputerIndex[$computer].ObjectGUID}
        $plan=[pscustomobject]@{Nom_du_PC=$computer;Nouveau_Nom=$computer;OU_Actuelle=$script:OU_ACTUELLE;OU_Destination=$script:OU_ACTUELLE;Objet_GUID=$id;Renommer=$false;Deplacer=$false;Domain=$script:DOMAINE}
    }
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · État du poste" Width="840" Height="650" MinWidth="580" MinHeight="400" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
<Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock x:Name="StateTitle" Text="État du poste" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,12"/>
<TextBox x:Name="StateReport" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" MinHeight="80" FontFamily="Consolas" Text="Lecture non lancée." ToolTip="Observations Windows et AD datées. Les valeurs non lues restent inconnues." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Observations Windows et AD datées. Les valeurs non lues restent inconnues." AutomationProperties.Name="Observations du poste"/>
<TextBlock x:Name="StateAdvice" Grid.Row="2" TextWrapping="Wrap" Margin="0,14,0,14" Foreground="{DynamicResource FgMuted}"/>
<WrapPanel Grid.Row="3"><Button x:Name="StateRefresh" Content="Relire l’état" ToolTip="Lectures Windows/AD uniquement. Aucune réparation, aucun renommage ni redémarrage." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Lectures Windows/AD uniquement. Aucune réparation, aucun renommage ni redémarrage."/><Button x:Name="StateRetryLater" Content="Relire dans 30 s" Margin="8,0,0,0" Visibility="Collapsed" IsEnabled="False" ToolTip="Relance une seule lecture Windows/AD après 30 s. Aucune réparation, aucune nouvelle jonction." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Relance une seule lecture Windows/AD après 30 s. Aucune réparation, aucune nouvelle jonction."/><Button x:Name="StateSaveReading" Content="Conserver cette lecture" Margin="8,0,0,0" Visibility="Collapsed" IsEnabled="False" ToolTip="Enregistrer cette observation dans le reçu, sans déclarer la réussite ni lever un verrou." AutomationProperties.Name="Conserver la lecture sans résoudre l’intervention"/><Button x:Name="StateAcknowledge" Content="Acquitter…" Margin="8,0,0,0" Visibility="Collapsed" IsEnabled="False" AutomationProperties.AutomationId="StateAcknowledge" ToolTip="Débloquer ce poste sans valider le résultat : le reçu garde son état réel ; votre compte, l’heure, votre motif et cette lecture sont enregistrés. Aucune commande n’est lancée." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Débloquer ce poste sans valider le résultat : le reçu garde son état réel ; votre compte, l’heure, votre motif et cette lecture sont enregistrés. Aucune commande n’est lancée."/><Button x:Name="StateNext" Content="Suite" Margin="8,0,0,0" IsEnabled="False" Visibility="Collapsed" ToolTip="Appliquer uniquement la suite autorisée par l’observation. Une préparation de déplacement ne lance aucune écriture AD." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Appliquer uniquement la suite autorisée par l’observation. Une préparation de déplacement ne lance aucune écriture AD."/><Button x:Name="StateClose" Content="Fermer" Margin="8,0,0,0" IsCancel="True" ToolTip="Fermer cette fiche sans lancer une mutation." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Fermer cette fiche sans lancer une mutation."/></WrapPanel>
</Grid></Window>
'@
    $window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$window.Resources=$Win.Resources;$window.Owner=$Win;Set-WindowIcon $window
    $window.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-20;$window.MaxWidth=[Windows.SystemParameters]::WorkArea.Width-20
    $script:PestoStateUi=[pscustomobject]@{Window=$window;Title=$window.FindName('StateTitle');Report=$window.FindName('StateReport');Advice=$window.FindName('StateAdvice');Refresh=$window.FindName('StateRefresh');RetryLater=$window.FindName('StateRetryLater');RetryTimer=$null;Next=$window.FindName('StateNext');SaveReading=$window.FindName('StateSaveReading');Acknowledge=$window.FindName('StateAcknowledge');Mode=$Mode;Plan=$plan;Row=$row;Receipt=$receipt;TargetMachineId=$targetId;PreviousCode=$previousCode;Observation=$null;Decision=$null;Generation=0;RowSignature=$(if($row){Get-PestoPlanSignature $row}else{''})}
    foreach($n in @('StateRefresh','StateRetryLater','StateNext','StateSaveReading','StateAcknowledge','StateClose')){$window.FindName($n).Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoStateCommand})}
    $script:PestoStateUi.SaveReading.Visibility=if($Mode -eq 'Ledger' -and -not $script:PestoReadOnly){'Visible'}else{'Collapsed'}
    $window.Add_Closed([EventHandler]${function:Close-PestoStateWindow})
    # Le contenu hébergé ne déclenche pas ContentRendered sur la Window invisible.
    # Démarrer la lecture une seule fois avant la boucle Dispatcher du panneau.
    try{Start-PestoPostStateRead;[void](Show-PestoHostedWindow $window)}
    finally{if($script:PestoStateUi -and $script:PestoStateUi.Window -eq $window){Close-PestoStateWindow $window $null}}
}

function Invoke-PestoStateFirstRead {param($Sender,$EventArgs);Start-PestoPostStateRead}
function Close-PestoStateWindow {
    param($Sender,$EventArgs)
    if(Test-PestoAsyncOperationRunning 'PostState'){Stop-PestoAsyncOperation 'PostState'}
    if($script:PestoStateUi -and $script:PestoStateUi.RetryTimer){try{$script:PestoStateUi.RetryTimer.Stop()}catch{};$script:PestoStateUi.RetryTimer=$null}
    $script:PestoStateUi=$null
}
function Invoke-PestoStateCommand {
    param($Sender,$EventArgs)
    switch($Sender.Name){
        'StateRefresh' {Start-PestoPostStateRead}
        'StateRetryLater' {Start-PestoStateDelayedRead}
        'StateClose' {if($script:PestoStateUi){$script:PestoStateUi.Window.Close()}}
        'StateNext' {Apply-PestoStateNextStep}
        'StateSaveReading' {Save-PestoCurrentStateReading}
        'StateAcknowledge' {Invoke-PestoStateAcknowledge}
    }
}

function Start-PestoPostStateRead {
    $ui=$script:PestoStateUi;if(-not $ui -or (Test-PestoAsyncOperationRunning 'PostState')){return}
    if($ui.RetryTimer){$ui.RetryTimer.Stop();$ui.RetryTimer=$null}
    if($ui.RetryLater){$ui.RetryLater.Visibility='Collapsed';$ui.RetryLater.IsEnabled=$false}
    $ui.Generation++;$ui.Next.IsEnabled=$false;$ui.SaveReading.IsEnabled=$false;$ui.Refresh.IsEnabled=$false
    if($ui.Acknowledge){$ui.Acknowledge.IsEnabled=$false}
    $ui.Advice.Text='Lecture en cours. Cela ne modifie ni le poste ni son objet AD.'
    $p=$ui.Plan
    $localSource=([string]$p.Nom_du_PC -ieq $env:COMPUTERNAME) -or ($ui.Receipt -and [bool]$ui.Receipt.LocalSource)
    if(-not $localSource -and $ui.TargetMachineId -and $script:HostMachineId -ieq $ui.TargetMachineId){$localSource=$true}
    $request=[pscustomobject]@{Computer=$p.Nom_du_PC;AlternativeComputer=$p.Nouveau_Nom;ObjectGuid=$p.Objet_GUID;LocalSource=$localSource;ReadHealth=$true;Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    if(Test-PestoJoinIntervention $ui.Receipt){
        $request.Computer=$p.Nouveau_Nom
        $request|Add-Member -NotePropertyName JoinTargetOU -NotePropertyValue ([string]$p.OU_Destination)
        if($ui.Receipt.JoinEvidence.BoundObjectGuid){$request.ObjectGuid=$ui.Receipt.JoinEvidence.BoundObjectGuid}
    }
    $context=[pscustomobject]@{Window=$ui.Window;Generation=$ui.Generation}
    if($script:GUI){
        $obs=[pscustomobject]@{ObservedUtc=[DateTime]::UtcNow.ToString('o');ADUtc='DÉMO';WindowsUtc='DÉMO';AD=[pscustomobject]@{Name=$p.Nom_du_PC;Guid=$p.Objet_GUID;DN='';OU=$p.OU_Actuelle;Protected=$false};Windows=$null;Errors=@('Démonstration : aucune observation Windows/AD réelle. Aucun verrou ne sera levé.')}
        Complete-PestoPostStateRead -Observation $obs -Context $context;return
    }
    try{
        $started=Start-PestoAsyncOperation -Name 'PostState' -ScriptBlock $script:PestoInspectionWorker -ArgumentList @($request,(Get-PestoInspectionSource)) -TimeoutSec 240 -CallbackContext $context `
            -OnSuccess {param($r,$c) Complete-PestoPostStateRead -Observation $r -Context $c} `
            -OnError {param($e,$c) Complete-PestoPostStateRead -Failure $e -Context $c}
        if(-not $started){throw 'La lecture n''a pas été lancée.'}
    }catch{Complete-PestoPostStateRead -Failure $_ -Context $context}
}

function Complete-PestoPostStateRead {
    param($Observation,$Failure,$Context)
    $ui=$script:PestoStateUi
    if(-not $ui -or $ui.Window -ne $Context.Window -or $ui.Generation -ne $Context.Generation){return}
    $ui.Refresh.IsEnabled=$true
    if($Failure){
        $ui.Observation=$null;Update-PestoStateAcknowledge
        $ui.Advice.Text='Lecture incomplète. Aucun verrou levé, aucune nouvelle action lancée.'+$(if($ui.Acknowledge -and $ui.Acknowledge.IsEnabled){' Vous pouvez acquitter sans lecture : le résultat réel reste conservé.'}else{''})
        $ui.Report.Text=Protect-PestoLogText $Failure.Exception.Message;return
    }
    $ui.Observation=$Observation
    $ui.Report.Text=Format-PestoPostObservation -Observation $Observation -Plan $ui.Plan -Receipt $ui.Receipt
    if($ui.Receipt -and -not $script:GUI -and -not $script:SIM){
        try{$comparison=@(Get-PestoObservationComparison -Receipt $ui.Receipt -Observation $Observation);$ui.Report.Text+="`r`nAVANT / PRÉVU / OBSERVÉ`r`n"+($comparison|Format-List|Out-String -Width 160)}catch{$ui.Advice.Text='Comparaison non disponible : '+$_.Exception.Message}
    }
    $ui.SaveReading.IsEnabled=($ui.Mode -eq 'Ledger' -and -not $script:PestoReadOnly -and $null -ne $Observation.AD -and -not $script:SIM -and -not $script:GUI)
    $ui.Title.Text='État de '+[string]$ui.Plan.Nom_du_PC
    if(Test-PestoJoinIntervention $ui.Receipt){
        $ui.Decision=Get-PestoJoinObservationDecision -Receipt $ui.Receipt -Observation $Observation -LocalMachineId $script:HostMachineId
    }else{$ui.Decision=Get-PestoObservationDecision -Plan $ui.Plan -Observation $Observation -TargetMachineId $ui.TargetMachineId -PreviousCode $ui.PreviousCode}
    $ui.Advice.Text=$ui.Decision.Message
    # Canal sécurisé pas encore prêt : proposer une seule relecture différée, en lecture seule.
    $retry=Get-PestoStateRetryDelay $ui.Decision
    if($ui.RetryLater){$ui.RetryLater.Visibility=if($retry -gt 0){'Visible'}else{'Collapsed'};$ui.RetryLater.IsEnabled=($retry -gt 0)}
    if($ui.Receipt -and $ui.Receipt.Entra -in @('Confirmed','Uncertain','Requested')){
        $ui.Advice.Text+=' État Entra : '+[string]$ui.Receipt.Entra+'. La réinscription doit être vérifiée séparément.'
    }
    $ui.Next.Visibility=if($ui.Mode -ne 'Inspect'){'Visible'}else{'Collapsed'}
    $ui.Next.IsEnabled=(-not $script:GUI -and -not $script:SIM -and -not $script:PestoReadOnly -and ($ui.Decision.Verified -or $ui.Decision.ResumeMove))
    $ui.Next.Content=if($ui.Decision.ResumeMove){'Préparer le déplacement restant'}else{'Consigner la vérification'}
    Update-PestoStateAcknowledge
    if($ui.Acknowledge -and $ui.Acknowledge.IsEnabled -and -not($ui.Decision.Verified -or $ui.Decision.ResumeMove)){
        $ui.Advice.Text+=' Si cet état vous convient, « Acquitter… » débloque le poste sans valider le résultat.'
    }
    if($ui.Mode -eq 'Inspect'){$script:LastPostObservation=$Observation}
}

function Get-PestoStateRetryDelay {
    param($Decision)
    if($null -eq $Decision -or -not $Decision.PSObject.Properties['RetryAfterSec']){return 0}
    $delay=0;if(-not [int]::TryParse([string]$Decision.RetryAfterSec,[ref]$delay)){return 0}
    if($delay -lt 1 -or $delay -gt 300){return 0}
    return $delay
}

function Start-PestoStateDelayedRead {
    <# Une seule relecture Windows/AD différée. Jamais de réparation, de jonction ni de levée de verrou. #>
    $ui=$script:PestoStateUi;if(-not $ui -or -not $ui.RetryLater){return}
    $delay=Get-PestoStateRetryDelay $ui.Decision;if($delay -le 0){return}
    if($ui.RetryTimer){$ui.RetryTimer.Stop()}
    $timer=New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval=[TimeSpan]::FromSeconds($delay)
    $timer.Add_Tick([EventHandler]${function:Invoke-PestoStateDelayedTick})
    $ui.RetryTimer=$timer;$ui.RetryLater.IsEnabled=$false
    $ui.Advice.Text=[string]$ui.Decision.Message+' Relecture programmée dans '+$delay+' s.'
    $timer.Start()
}

function Invoke-PestoStateDelayedTick {
    param($Sender,$EventArgs)
    try{$Sender.Stop()}catch{}
    $ui=$script:PestoStateUi
    if(-not $ui -or -not [object]::ReferenceEquals($ui.RetryTimer,$Sender)){return}
    $ui.RetryTimer=$null
    Start-PestoPostStateRead
}

function Apply-PestoStateNextStep {
    $ui=$script:PestoStateUi
    if(-not $ui -or -not $ui.Decision -or -not $ui.Next.IsEnabled){return}
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or (Test-PestoQueueWorkerStillActive)){Show-MsgWarning 'Une opération est encore active. Aucun verrou n''est levé.';return}
    $time=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$ui.Observation.ObservedUtc,[ref]$time) -or ([DateTimeOffset]::UtcNow-$time).TotalSeconds -gt 120){$ui.Next.IsEnabled=$false;$ui.Advice.Text='Observation trop ancienne : relisez l''état.';return}
    if(-not(Confirm-YesNo -Msg ($ui.Decision.Message+"`n`nConsigner cette observation et préparer uniquement la suite indiquée ? Aucune commande n’est lancée par cette confirmation.") -Confirm $true)){return}
    try{
        if($ui.Mode -eq 'Ledger'){
            $verified=Confirm-PestoInterventionObservation -OperationId $ui.Receipt.OperationId -Observation $ui.Observation
            Sync-PestoInterventionViews -Receipt $verified -Observation $ui.Observation -Decision $ui.Decision
        }elseif($ui.Mode -eq 'Direct'){
            Apply-PestoDirectObservation -Receipt $ui.Receipt -Observation $ui.Observation -Decision $ui.Decision
        }elseif($ui.Mode -eq 'Queue'){
            if($null -eq $ui.Row -or $ui.Row.RowState -eq [Data.DataRowState]::Detached -or (Get-PestoPlanSignature $ui.Row) -ne $ui.RowSignature){throw 'La ligne a changé depuis la lecture. Aucun résultat appliqué.'}
            Apply-PestoQueueObservation -Row $ui.Row -Observation $ui.Observation -Decision $ui.Decision
        }
        $ui.Window.Close()
    }catch{Show-PestoUsefulError -Title 'Vérification non appliquée' -Message $_.Exception.Message -Stage 'Vérification du résultat' -MutationPossible $true}
}


function Get-PestoStateAckReceipt {
    $ui=$script:PestoStateUi;if(-not $ui){return $null}
    if($ui.Mode -in @('Ledger','Direct')){return $ui.Receipt}
    if($ui.Mode -eq 'Queue' -and $ui.Row -and $ui.Row.RowState -ne [Data.DataRowState]::Detached){
        $id=[Guid]::Empty
        if([Guid]::TryParse([string]$ui.Row.Operation_ID,[ref]$id) -and $id -ne [Guid]::Empty){
            $path=Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')
            if([IO.File]::Exists($path)){return Read-PestoIntervention $path}
        }
    }
    return $null
}

function Update-PestoStateAcknowledge {
    # « Acquitter… » : visible seulement pour un reçu qui bloque encore sa cible (décision du 15/10).
    $ui=$script:PestoStateUi;if(-not $ui -or -not $ui.Acknowledge){return}
    $receipt=$null;try{$receipt=Get-PestoStateAckReceipt}catch{$receipt=$null}
    $show=($ui.Mode -ne 'Inspect' -and -not $script:PestoReadOnly -and -not $script:GUI -and -not $script:SIM -and (Test-PestoAcknowledgementNeeded $receipt))
    $ui.Acknowledge.Visibility=if($show){'Visible'}else{'Collapsed'}
    $ui.Acknowledge.IsEnabled=[bool]$show
}

function Invoke-PestoStateAcknowledge {
    $ui=$script:PestoStateUi;if(-not $ui -or -not $ui.Acknowledge.IsEnabled){return}
    $receipt=$null
    try{$receipt=Get-PestoStateAckReceipt}catch{Show-MsgWarning ('Reçu illisible : '+$_.Exception.Message+' Aucun acquittement.');return}
    if(Invoke-PestoAcknowledgeFlow -Receipt $receipt -Observation $ui.Observation){if($script:PestoStateUi){$script:PestoStateUi.Window.Close()}}
}

function Save-PestoCurrentStateReading {
    $ui=$script:PestoStateUi
    if(-not $ui -or -not $ui.SaveReading.IsEnabled){return}
    try{
        $receipt=Save-PestoUnverifiedObservation -OperationId $ui.Receipt.OperationId -ExpectedPlanFingerprint (Get-PestoPlanFingerprint $ui.Receipt.Plan) -Observation $ui.Observation
        $ui.Receipt=$receipt;$ui.SaveReading.IsEnabled=$false
        $ui.Advice.Text='Lecture enregistrée avec ses dates. Le résultat et les verrous restent inchangés ; aucune commande Windows ou AD lancée.'
    }catch{$ui.Advice.Text='Lecture non enregistrée : '+$_.Exception.Message}
}
