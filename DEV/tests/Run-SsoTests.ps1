#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-sso-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis.'}
$root=Split-Path -Parent $PSScriptRoot
# Les fonctions testées ne vivent plus toutes dans Pesto-Core.ps1 : le banc parse tous
# les fichiers de wad/ en un seul dictionnaire. Un seul fichier le faisait mourir au
# chargement sur des fonctions qui existent pourtant. Premier gagnant : les seules
# définitions doublonnées du produit sont des mocks (Write-Log, Show-MsgWarning…),
# redéfinis plus bas par le banc.
$defs=@{}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $root 'wad') -Filter '*.ps1' -File | Sort-Object Name)){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw (($errors|ForEach-Object{"$($file.Name):$($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n")}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}
    }
}
# Jamais d'exécution du moteur. Les fonctions chargées ci-dessous n'effectuent
# des accès système que via les mocks définis avant le premier test.
foreach($name in @('Start-PestoWindowsConnection','Complete-PestoWindowsConnectionSuccess','Complete-PestoWindowsConnectionError','Get-PestoAuthenticationRoute','Get-PestoExplicitCredentialRequirement','Set-PestoAuthenticatedSnapshot','Get-ADParams','New-ActionResult','Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoConfirmedChange','Assert-PestoTargetNameAvailable','RenameComputer','Invoke-PestoWindowsLocalRename',
 'ConvertTo-PestoNameParts','Get-PestoDomainFromDN','Split-PestoDistinguishedName','Test-PestoDnsName','Test-PestoOUPath','Protect-PestoLogText','Get-PestoNativeFailureCode','Get-PestoOutcome','Set-PestoEffect','Set-PestoInitialObservation','ConvertTo-PestoObservationSnapshot','Assert-PestoObservationSnapshot','Assert-PestoClosedObject','Get-PestoDomainIdentityWarning',
 'Get-PestoNamingLayout','Get-PestoFacetPattern','Get-PestoNamingResolutionNonce','Get-PestoDefaultNamingConvention','Assert-PestoNamingConvention','Set-PestoActiveNamingConvention','Get-PestoActiveNamingConvention','Get-PestoNamingFunctionNames')){
    if(-not $defs.ContainsKey($name)){throw "Fonction absente : $name"}
    . ([scriptblock]::Create($defs[$name]))
}
. (Join-Path $root 'wad\Pesto-Startup.ps1')
$cases=[Collections.Generic.List[object]]::new()
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu '$Expected', obtenu '$Actual'."}}
function Assert-True {param($Actual);if($Actual -ne $true){throw 'Condition non satisfaite.'}}
function Assert-Throws {param([scriptblock]$Action);$yes=$false;try{& $Action}catch{$yes=$true};if(-not $yes){throw 'Exception attendue.'}}
function Case {param([string]$Name,[scriptblock]$Action);try{& $Action;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK $Name"}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO $Name : $($_.Exception.Message)"}}
function Get-ADObject {[CmdletBinding()]param($LDAPFilter,$Properties,$ResultSetSize,$Server,$Credential);@()}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
# Porte d'observation prealable a tout renommage (Assert-PestoRenameTarget, Pesto-Safety.ps1) et
# couche « reçu d'intervention ». La porte exige Get-PestoPostObservation : lecture AD reelle sur un
# DC et session CIM, hors portee d'un harnais sans bureau ; le reçu s'ecrit normalement sur disque.
# Remplaces par des enregistreurs, comme Test-PestoIsAdministrator l'est deja dans cette suite.
# Limite mesuree le 11/10/2026 : aucune suite du depot n'exerce le corps reel de cette porte.
function Assert-PestoRenameTarget {[CmdletBinding()]param([string]$ComputerName);$script:GateCalls++;$script:GateSawMutations=$script:Calls.Count;if($script:GateThrows){throw 'MOCK cible non confirmee.'}}
function Write-PestoIntervention {param($Receipt);$script:WrittenInterventions.Add($Receipt)}
function Add-PestoInterventionEvent {param($Receipt,$Stage,$State)}
function Write-PestoJoinReceipt {param($Receipt);$script:WrittenInterventions.Add($Receipt)}
function Get-PestoInterventionRoot {return 'C:\PestoTest-run\harnais-sso'}
function Write-PestoAuditQueued {param($Message,$Level,$Err,$Context)}
function Write-AuditLine {param($Message,$Level,$Err,$Context)}
function Update-PestoComputerIndex {$script:IndexCalls++}
function Get-PestoWindowsAuthIdentity {return [pscustomobject]@{Name='EXAMPLE\operator';Sid='test';IsDomainUser=$script:IsDomainUser;IsAdministrator=$script:IsAdmin}}
function Test-PestoIsAdministrator {return $script:IsAdmin}
function Assert-PestoWorkerMayContinue {param([switch]$Mutation);if($Mutation -and $script:CancelBeforeMutation){throw 'Arret demandé.'}}
function Set-PestoWorkerStage {param($Stage,$Detail)}
function Find-ADComputerByName {param($Name);if($Name -eq $script:SourceName){return [pscustomobject]@{Name=$Name;ObjectGUID=[guid]'33333333-1111-2222-3333-444444444444';DistinguishedName='CN=Test,OU=Machines,DC=example,DC=local'}};if($script:NameTaken){return [pscustomobject]@{Name=$Name}}}
function Get-PestoParentDN {param($DistinguishedName);return 'OU=Machines,DC=example,DC=local'}
function Get-PestoIdentityChangeReason {param($ExpectedGuid,$ActualGuid,$ExpectedOU,$ActualOU);return $script:Drift}
function Test-PestoOUInConfiguredScope {param($OU);return $true}
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$Namespace,$OperationTimeoutSec)
    if($script:ReadFails){throw 'Lecture WMI impossible.'}
    return [pscustomobject]@{Name=$script:ObservedName;Domain=$script:ObservedDomain;PartOfDomain=$script:PartOfDomain;DomainRole=$script:DomainRole}
}
function Invoke-CimMethod {
    [CmdletBinding()]param($Query,$Namespace,$MethodName,$Arguments,$OperationTimeoutSec)
    $script:Calls.Add('cim');$script:NativeArguments=@{}+$PSBoundParameters
    if($script:NativeThrows){throw 'Transport interrupted.'}
    switch($script:NativeResult){
        'empty' {return}
        'missing' {return [pscustomobject]@{Wrong=0}}
        'null' {return [pscustomobject]@{ReturnValue=$null}}
        'string' {return [pscustomobject]@{ReturnValue='0'}}
        'multi' {return @([pscustomobject]@{ReturnValue=[uint32]0},[pscustomobject]@{ReturnValue=[uint32]0})}
        default {return [pscustomobject]@{ReturnValue=[uint32]$script:NativeCode}}
    }
}
function Invoke-PestoDsregLeaveBeforeRename {param($ComputerName);$script:Calls.Add('leave');return New-ActionResult $script:LeaveCode 'Retrait Entra simulé.'}
function Rename-Computer {
    [CmdletBinding()]param($NewName,$ComputerName,$DomainCredential,$LocalCredential,[switch]$Force,[switch]$PassThru)
    $script:Calls.Add('legacy');$script:LegacyArguments=@{}+$PSBoundParameters
    return [pscustomobject]@{HasSucceeded=$true}
}
function Invoke-RenameComputerTaskFallback {throw 'Aucun fallback attendu dans cette suite.'}

function New-PestoDirectorySnapshotRequest {
    param([switch]$IncludeLocalHardware,[Management.Automation.PSCredential]$Credential)
    $script:SnapshotRequestArgs=@{}+$PSBoundParameters
    return [pscustomobject]@{Domain=$script:DOMAINE;Credential=$Credential}
}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
function Start-PestoAsyncOperation {
    param($Name,$ScriptBlock,$ArgumentList,$TimeoutSec,$CallbackContext,$OnSuccess,$OnError)
    $script:AsyncArgs=@{}+$PSBoundParameters
    return $true
}
function Show-PestoStartupWindow {}
function Set-PestoStartupStage {param($Stage,$Detail)}
function Reset-Connection {
    $script:PestoWindowsConnection=[pscustomobject]@{
        Id='request-1';User='';Result='Pending';Busy=$false
        Identity=[pscustomobject]@{Text=''};Status=[pscustomobject]@{Text=''}
        Progress=[pscustomobject]@{Visibility='Collapsed'}
        Retry=[pscustomobject]@{Visibility='Collapsed';IsEnabled=$true}
        Other=[pscustomobject]@{Visibility='Collapsed';IsEnabled=$true}
        Window=[pscustomobject]@{DialogResult=$false}
    }
    $script:PestoDirectorySnapshotWorker={param($Request)}
    $script:SnapshotRequestArgs=$null;$script:AsyncArgs=$null
}

function Reset-Fakes {
    $script:SourceName='P111301AAINF001';$script:TargetName='P111301AAINF002';$env:COMPUTERNAME=$script:SourceName
    $script:DOMAINE='example.local';$script:PREFIXE='111301';$script:DC='dc.example.local'
    $script:SIM=$false;$script:GUI=$false;$script:INDOMAIN=$true;$script:cred=$null
    $script:IsAdmin=$true;$script:IsDomainUser=$true;$script:IndexCalls=0
    $script:ObservedName=$script:SourceName;$script:ObservedDomain=$script:DOMAINE;$script:PartOfDomain=$true;$script:DomainRole=1
    $script:ReadFails=$false;$script:LeaveCode=20;$script:NativeThrows=$false;$script:NativeResult='success';$script:NativeCode=0
    $script:NameTaken=$false;$script:Drift='';$script:CancelBeforeMutation=$false
    $script:Calls=[Collections.Generic.List[string]]::new();$script:NativeArguments=$null;$script:LegacyArguments=$null
    # Set-PestoEffect refuse toute commande sans reçu d'intervention, et un PSCustomObject
    # n'accepte pas l'ajout d'une propriété par affectation : le reçu du harnais porte donc lui-même
    # chaque propriété que le produit assigne (mesuré le 11/10/2026 sur l'invité).
    $script:ActiveIntervention=[pscustomobject]@{OperationId='11111111111111111111111111111111';Schema=1
        Plan=[pscustomobject]@{Objet_GUID='33333333-1111-2222-3333-444444444444'}
        Phase='Running';Baseline=$null;JoinEvidence=$null;Tasks=@()
        Entra='NotRequested';Rename='NotRequested';Move='NotRequested';Protection='NotChanged'
        ResultCode=0;ResultMessage='';UpdatedUtc='';LastStage=''
        TargetMachineId='';TargetOUGuid='';InitialProtection=$false}
    $script:WrittenInterventions=[Collections.Generic.List[object]]::new()
    $script:GateCalls=0;$script:GateThrows=$false;$script:GateSawMutations=-1
}
$oldComputer=$env:COMPUTERNAME
try {
    Case 'Domaine : connexion Windows par défaut' {Assert-Equal (Get-PestoAuthenticationRoute $true $false $false) 'Windows'}
    Case 'Hors domaine : formulaire explicite conservé' {Assert-Equal (Get-PestoAuthenticationRoute $false $false $false) 'Explicit'}
    Case 'Autre compte : opt-in conservé' {Assert-Equal (Get-PestoAuthenticationRoute $true $true $false) 'Explicit'}
    Case 'Démonstration : pas de connexion AD' {Assert-Equal (Get-PestoAuthenticationRoute $true $false $true) 'Demo'}
    Case 'AskCredential reste absent du lancement UAC par défaut' {Assert-True (-not (New-PestoStartupArgumentLine 'C:\Pesto\Pesto.ps1' '' '').Contains('-AskCredential'))}
    Case 'AskCredential explicite traverse le lancement UAC' {Assert-True (New-PestoStartupArgumentLine 'C:\Pesto\Pesto.ps1' '' '' -AskCredential).Contains('-AskCredential')}
    Case 'AD intégré : le paramètre Credential est absent, pas égal à null' {Reset-Fakes;Assert-True (-not (Get-ADParams).ContainsKey('Credential'))}
    Case 'AD explicite : credential conservé' {Reset-Fakes;$script:cred=[pscredential]::new('EXAMPLE\test',(ConvertTo-SecureString 'FAKE TEST' -AsPlainText -Force));Assert-True ([object]::ReferenceEquals((Get-ADParams).Credential,$script:cred))}
    Case 'File : renommage local sans credential autorisé' {Reset-Fakes;$r=[pscustomobject]@{Renommer=$true;Nom_du_PC=$script:SourceName};Assert-Equal (Get-PestoExplicitCredentialRequirement $true @($r) $script:SourceName) ''}
    Case 'File : déplacement distant sans credential autorisé' {Reset-Fakes;$r=[pscustomobject]@{Renommer=$false;Nom_du_PC='REMOTE'};Assert-Equal (Get-PestoExplicitCredentialRequirement $true @($r) $script:SourceName) ''}
    Case 'File : renommage distant doit être signalé avant exécution' {Reset-Fakes;$r=[pscustomobject]@{Renommer=$true;Nom_du_PC='REMOTE'};Assert-True ([bool](Get-PestoExplicitCredentialRequirement $true @($r) $script:SourceName))}
    Case 'Snapshot : mauvaise identité refusée sans credential affecté' {
        Reset-Fakes;$snap=[pscustomobject]@{Complete=$true;DC=$script:DC;Domain=$script:DOMAINE;Identity='EXAMPLE\other'}
        Assert-Throws {Set-PestoAuthenticatedSnapshot $snap -Mode Windows -User 'EXAMPLE\operator'}
        Assert-Equal $script:IndexCalls 0;Assert-True ($null -eq $script:cred)
    }
    Case 'Snapshot : domaine différent refusé' {Reset-Fakes;$snap=[pscustomobject]@{Complete=$true;DC=$script:DC;Domain='other.local';Identity='EXAMPLE\operator'};Assert-Throws {Set-PestoAuthenticatedSnapshot $snap -Mode Windows -User 'EXAMPLE\operator'}}
    Case 'Snapshot validé : compte du worker conservé, aucun credential' {
        Reset-Fakes;$snap=[pscustomobject]@{Complete=$true;DC=$script:DC;Domain=$script:DOMAINE;Identity='EXAMPLE\operator';Sites=@{};Root=@();Names=@();LocalPCType='Fixe'}
        Set-PestoAuthenticatedSnapshot $snap -Mode Windows -User 'EXAMPLE\operator'
        Assert-Equal $script:AuthMode 'Windows';Assert-Equal $script:AuthUser 'EXAMPLE\operator';Assert-True ($null -eq $script:cred)
    }
    Case 'Renommage local intégré : dsreg puis CIM, sans Rename-Computer' {
        Reset-Fakes;$r=RenameComputer $script:SourceName $script:TargetName
        Assert-Equal $r.ExitCode 20;Assert-Equal ($script:Calls -join ',') 'leave,cim'
        Assert-Equal $script:NativeArguments.MethodName 'Rename'
        Assert-Equal $script:NativeArguments.Arguments.Count 1
        Assert-Equal $script:NativeArguments.Arguments.Name $script:TargetName
        foreach($key in @('ComputerName','CimSession','InputObject','Credential')){Assert-True (-not $script:NativeArguments.ContainsKey($key))}
    }
    Case 'Renommage distant intégré : aucune mutation ni retrait Entra' {Reset-Fakes;$env:COMPUTERNAME='OPERATOR';Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Compte explicite : parcours Rename-Computer conservé' {Reset-Fakes;$script:cred=[pscredential]::new('EXAMPLE\test',(ConvertTo-SecureString 'FAKE TEST' -AsPlainText -Force));Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 20;Assert-Equal ($script:Calls -join ',') 'leave,legacy'}
    Case 'Sans élévation : refus avant dsregcmd' {Reset-Fakes;$script:IsAdmin=$false;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Compte local : refus avant dsregcmd' {Reset-Fakes;$script:IsDomainUser=$false;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Nom déjà pris : aucun appel système' {Reset-Fakes;$script:NameTaken=$true;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 69;Assert-Equal $script:Calls.Count 0}
    Case 'GUID ou OU dérivés : aucun appel système' {Reset-Fakes;$script:Drift='Objet différent';Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 21;Assert-Equal $script:Calls.Count 0}
    Case 'Nom WMI différent : aucun appel de mutation' {Reset-Fakes;$script:ObservedName='OTHER';Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Domaine réel différent : aucune mutation' {Reset-Fakes;$script:ObservedDomain='other.local';Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Contrôleur de domaine exclu' {Reset-Fakes;$script:DomainRole=5;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Lecture WMI impossible : pas de retrait Entra' {Reset-Fakes;$script:ReadFails=$true;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 96;Assert-Equal $script:Calls.Count 0}
    Case 'Echec du retrait Entra : pas de renommage' {Reset-Fakes;$script:LeaveCode=21;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 21;Assert-Equal ($script:Calls -join ',') 'leave'}
    Case 'Retrait Entra incertain : pas de renommage' {Reset-Fakes;$script:LeaveCode=97;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 97;Assert-Equal ($script:Calls -join ',') 'leave'}
    Case 'WMI code 5 : refus sans second essai' {Reset-Fakes;$script:NativeCode=5;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 21;Assert-Equal ($script:Calls -join ',') 'leave,cim'}
    foreach($bad in @('empty','missing','null','string','multi')){
        Case "WMI résultat $bad : incertain, aucun succès inventé" {Reset-Fakes;$script:NativeResult=$bad;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 97}
    }
    Case 'Exception après appel WMI : incertain, sans retry' {Reset-Fakes;$script:NativeThrows=$true;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 97;Assert-Equal ($script:Calls -join ',') 'leave,cim'}
    Case 'Simulation : aucun retrait Entra ni renommage' {Reset-Fakes;$script:SIM=$true;Assert-Equal (RenameComputer $script:SourceName $script:TargetName).ExitCode 20;Assert-Equal $script:Calls.Count 0}

    Case 'Connexion auto : worker sans credential et contexte correspondant au compte élevé' {
        Reset-Fakes;Reset-Connection;Start-PestoWindowsConnection
        Assert-True $script:PestoWindowsConnection.Busy
        Assert-True (-not $script:SnapshotRequestArgs.ContainsKey('Credential'))
        Assert-Equal $script:AsyncArgs.CallbackContext.User 'EXAMPLE\operator'
        Assert-Equal $script:AsyncArgs.Name 'WindowsAuth'
        Assert-Equal $script:AsyncArgs.TimeoutSec 180
    }
    Case 'Connexion auto : identité locale refusée sans ouvrir un second login' {
        Reset-Fakes;Reset-Connection;$script:IsDomainUser=$false;Start-PestoWindowsConnection
        Assert-True ($null -eq $script:AsyncArgs)
        Assert-Equal $script:PestoWindowsConnection.Result 'Pending'
        Assert-Equal $script:PestoWindowsConnection.Other.Visibility 'Visible'
    }
    Case 'Connexion auto : élévation absente refusée avant lecture AD' {
        Reset-Fakes;Reset-Connection;$script:IsAdmin=$false;Start-PestoWindowsConnection
        Assert-True ($null -eq $script:AsyncArgs);Assert-True (-not $script:PestoWindowsConnection.Busy)
    }
    Case 'Connexion auto : résultat périmé ignoré' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Busy=$true
        $snapshot=[pscustomobject]@{Complete=$true;Domain=$script:DOMAINE;DC=$script:DC;Identity='EXAMPLE\operator'}
        Complete-PestoWindowsConnectionSuccess $snapshot ([pscustomobject]@{Id='old';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Pending';Assert-Equal $script:IndexCalls 0
    }
    Case 'Connexion auto : résultat après annulation ignoré' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Result='Cancelled'
        Complete-PestoWindowsConnectionSuccess $null ([pscustomobject]@{Id='request-1';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Cancelled';Assert-Equal $script:IndexCalls 0
    }
    Case 'Connexion auto : lecture confirmée ferme attente sans identifiants Pesto' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Busy=$true
        $snapshot=[pscustomobject]@{Complete=$true;Domain=$script:DOMAINE;DC=$script:DC;Identity='EXAMPLE\operator';Root=@();Names=@();Sites=@{}}
        Complete-PestoWindowsConnectionSuccess $snapshot ([pscustomobject]@{Id='request-1';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Connected'
        Assert-True $script:PestoWindowsConnection.Window.DialogResult
        Assert-True ($null -eq $script:cred);Assert-Equal $script:AuthUser 'EXAMPLE\operator'
    }
    Case 'Connexion auto : échec de validation affiche erreur sans relogin automatique' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Busy=$true
        $snapshot=[pscustomobject]@{Domain=$script:DOMAINE;DC=$script:DC;Identity='EXAMPLE\other'}
        Complete-PestoWindowsConnectionSuccess $snapshot ([pscustomobject]@{Id='request-1';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Pending'
        Assert-True (-not $script:PestoWindowsConnection.Busy)
        Assert-Equal $script:PestoWindowsConnection.Retry.Visibility 'Visible'
    }

    Case 'Connexion auto : snapshot incomplet refusé, aucune connexion déclarée' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Busy=$true
        $snapshot=[pscustomobject]@{Complete=$false;DC=$script:DC;Domain=$script:DOMAINE;Identity='EXAMPLE\operator';Root=@();Names=@();Sites=@{}}
        Complete-PestoWindowsConnectionSuccess $snapshot ([pscustomobject]@{Id='request-1';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Pending'
        Assert-True (-not $script:PestoWindowsConnection.Busy)
        Assert-Equal $script:PestoWindowsConnection.Retry.Visibility 'Visible'
        Assert-True ($null -eq $script:cred);Assert-Equal $script:IndexCalls 0
    }
    Case 'Connexion auto : snapshot sans marqueur Complete refusé comme incomplet' {
        Reset-Fakes;Reset-Connection;$script:PestoWindowsConnection.Busy=$true
        $snapshot=[pscustomobject]@{DC=$script:DC;Domain=$script:DOMAINE;Identity='EXAMPLE\operator';Root=@();Names=@();Sites=@{}}
        Complete-PestoWindowsConnectionSuccess $snapshot ([pscustomobject]@{Id='request-1';User='EXAMPLE\operator'})
        Assert-Equal $script:PestoWindowsConnection.Result 'Pending'
        Assert-True ($null -eq $script:cred);Assert-Equal $script:IndexCalls 0
    }
    Case 'Nouvelle fenêtre : XAML natif valide, sans mot de passe ni maximisation' {
        Add-Type -AssemblyName PresentationFramework
        $match=[regex]::Match($defs['Show-PestoWindowsConnectionWindow'],"(?ms)\[xml\]\`$wxaml=@'\r?\n(.*?)\r?\n'@")
        Assert-True $match.Success
        [xml]$xml=$match.Groups[1].Value
        $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml))
        try{
            Assert-Equal ([string]$w.ResizeMode) 'NoResize'
            Assert-True ($null -ne $w.FindName('WindowsCancel'))
            Assert-True ($null -eq $w.FindName('TxtPwd'))
            Assert-True (-not $xml.OuterXml.Contains('PasswordBox'))
        }finally{$w.Close()}
    }
} finally {
    $env:COMPUTERNAME=$oldComputer
    $failed=@($cases|Where-Object{-not $_.Passed}).Count
    [pscustomobject]@{Version='17.0-RC13';Utc=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Scope='Parseur natif, logique isolée avec AD/CIM/Entra simulés et XAML sans ouverture de session. Pas de mutation réelle.';Total=$cases.Count;Failed=$failed;Tests=$cases.ToArray()} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if($failed){throw "$failed test(s) SSO en échec. Rapport : $ReportPath"}
Write-Host "Tests SSO terminés : $($cases.Count). Rapport : $ReportPath"
