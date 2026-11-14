#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourcePath='',
    [string]$ReportPath=''
)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $SourcePath){$SourcePath=Join-Path $PSScriptRoot '..\wad\Pesto-Core.ps1'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-rc4-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'Tests RC4 : Windows PowerShell 5.1 requis. Lancer TEST_CORRECTIF.cmd.'
}
# JAMAIS de lancement de Pesto, de chargement AD ou d'appel aux postes.
# Parser natif, puis extraction d'une liste blanche de fonctions seulement.
Add-Type -AssemblyName System.Data
# Les fonctions testees ont quitte Pesto-Core.ps1 : le banc indexe tout le repertoire wad/ de la source indiquee.
$tokens=$null
$parseErrors=[Collections.Generic.List[object]]::new()
$wadDir=Split-Path ([IO.Path]::GetFullPath($SourcePath)) -Parent
$defs=@{}
foreach($file in (Get-ChildItem -LiteralPath $wadDir -File | Where-Object{$_.Extension -eq '.ps1'} | Sort-Object Name)){
    $fileErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$fileErrors)
    foreach($e in $fileErrors){$parseErrors.Add([pscustomobject]@{Extent=$e.Extent;Message=$e.Message})}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}
    }
}
if($parseErrors.Count){throw (($parseErrors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"})-join "`n")}
$load=@('New-PestoQueueMonitor','Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence','Receive-PestoQueueEvents','Get-PestoQueueActivityText','Test-PestoQueueWorkerStillActive','Test-PestoDnsName','Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN','Test-PestoDNWithinScope',
    'Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Get-PestoNameSiteCode','Get-PestoSiteContainerDN',
    'Get-PestoRenameMoveDecision','Get-PestoRowPlanText','Write-PestoAtomicText','Protect-PestoLogText','New-ActionResult','New-QueueTable',
    'Save-PestoQueueCheckpoint','Update-PestoQueueRenamePlan','Set-PestoQueueRowResult','Complete-PestoQueueNotStarted',
    'Start-PestoNextQueueTask','Go','GoRenameOnly','GoMoveOnly','GoRenameAndMove','Check-SameOU','ConvertTo-PestoNameParts','Get-PestoOutcome','ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoOUPath','Test-PestoPropertyPresent','Get-PestoADLoaderSource','Assert-PestoPlainPath','Complete-PestoQueueItem','Fail-PestoQueueCallback','Import-PestoADModule','Invalidate-PestoNameInventory','Request-PestoQueuePump','Save-PestoQueueCheckpointSafe','Set-PestoNamesViewState','Stop-PestoNamesLoadTimer','Stop-PestoQueueRemainingForSafety','Update-PestoNamesLoadProgress')
foreach($name in $load){if(-not $defs.ContainsKey($name)){throw "Fonction absente : $name"};. ([scriptblock]::Create($defs[$name]))}
# La fusion reste celle du moteur ; seule la lecture GPO est remplacee pour ne pas lire le registre du pilote.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='fixture'}}
$script:Results=[Collections.Generic.List[object]]::new()
$script:TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('Pesto RC4 tests [local] '+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:TempRoot)
function Assert-True {param($Value,[string]$Message='Condition non satisfaite.');if($Value -ne $true){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]."}}
function Assert-Throws {param([scriptblock]$Body);$caught=$false;try{& $Body}catch{$caught=$true};Assert-True $caught 'Une exception etait attendue.'}
function Case {
    param([string]$Name,[scriptblock]$Body)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{& $Body;$script:Results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error='';Ms=$watch.ElapsedMilliseconds});Write-Host "OK  $Name"}
    catch{$script:Results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Ms=$watch.ElapsedMilliseconds});Write-Host "KO  $Name : $($_.Exception.Message)"}
}
function Write-Log {param($Message,$Level,$Err,$Context)}
function Write-AuditLine {param($Message,$Kind)}
function Add-LogLine {param($Text,$Kind)}
function Sync-Grid {}
function Update-AddButton {}
function Update-RebootOption {}
function Update-ComputersNoms {}
function Confirm-YesNo {param($Msg,$Confirm);return $true}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
function Complete-PestoQueueRun {$script:Finished=$true;$script:FinishedState=$script:QueueRunState}
function Get-PestoWorkerCoreSource {return '# Mock : aucun worker reel'}
function Start-PestoAsyncOperation {
    param($Name,$ScriptBlock,$ArgumentList,$OnSuccess,$OnError,$ApartmentState,$QueueMonitor,$TimeoutSec)
    $script:WorkerStarts++;$script:LastRequest=$ArgumentList[0];return $true
}
function Test-PestoAuditWritable {return $script:AuditWritable}
function Get-PestoStateDirectory {return (Join-Path $script:TempRoot 'state')}
function Get-ComputerOU {
    param($Identity)
    if($script:ReadFails){throw 'MOCK lecture AD impossible.'}
    return [pscustomobject]@{Name=$Identity;OU=$script:FakeOU;DN="CN=$Identity,$($script:FakeOU)"}
}
function Find-ADComputerByName {param($Name);return $null}
function Get-AllComputersInOU {param($ParentOU);return @()}
function Wait-ADComputerVisible {param($Identity,$TimeoutSec);return $script:Visible}
function RenameComputer {
    param($Computername,$NewName)
    $script:Calls.Add('RENAME')
    if($script:RenameEmpty){return $null}
    return New-ActionResult $script:RenameCode 'MOCK renommage'
}
function MoveComputer {
    param($ComputerName,$OU_Destination)
    $script:Calls.Add('MOVE');return New-ActionResult $script:MoveCode 'MOCK deplacement'
}
function GoJoinDomain {
    param($Nom_du_PC,$Nouveau_Nom,$OU_Destination,$Confirm)
    $script:Calls.Add('JOIN');return New-ActionResult 10 'MOCK jonction'
}
function Test-Connection {[CmdletBinding()]param($ComputerName,$Count,[switch]$Quiet);return $true}
function Reset-Fakes {
    $script:SIM=$true;$script:GUI=$false;$script:SimOn=$false;$script:INDOMAIN=$true;$script:PRD=$true
    $script:PREFIXE='111301';$script:DOMAINE='example.local';$script:DC='dc01.example.local'
    $script:OU=@{ROOT='OU=Postes,DC=example,DC=local';PREPROD='OU=PREPROD,OU=Postes,DC=example,DC=local'}
    $script:OUV=@{Sites='OU=Sites,OU=Postes,DC=example,DC=local'}
    $script:FakeOU=$script:OU.PREPROD
    $script:TargetOU='OU=VA,OU=Sites,OU=Postes,DC=example,DC=local'
    $script:SourceName='P111301PR765129';$script:NewName='P111301VA765010'
    $script:RenameCode=20;$script:MoveCode=30;$script:RenameEmpty=$false;$script:ReadFails=$false;$script:Visible=$true
    $script:Calls=[Collections.Generic.List[string]]::new()
    $script:WorkerStarts=0;$script:LastRequest=$null;$script:AuditWritable=$true
    $script:MutationUncertain=$false;$script:Finished=$false;$script:FinishedState=$null
    $script:OK_CODES=@(10,20,30,33,77);$script:NOK_CODES=@(11,13,21,31,32,69,88,89,91,96,97,98,99)
    $script:QueueCurrentTicket=$null;$script:QueueStopRequested=$false
    $script:JsonFile=Join-Path $script:TempRoot 'cfg-test.json';$script:Pesto_VERSION='17.0-RC4'
    $script:BasePath=$script:TempRoot
    $script:LblStatus=[pscustomobject]@{Text=''}
    $script:Progress=[pscustomobject]@{Value=0;Visibility='Visible'}
    $script:PestoQueueWorker={throw 'Ce worker de test ne doit jamais etre execute.'}
}
function Decision {
    param([string]$Old='P111301PR765129',[string]$New='P111301VA765010',
        [string]$Current=$script:FakeOU,[string]$Target=$script:TargetOU,
        [bool]$Rename=$true,[bool]$Move=$false,[bool]$InDomain=$true)
    return Get-PestoRenameMoveDecision -Computer $Old -NewName $New -CurrentOU $Current -TargetOU $Target -Rename $Rename -Move $Move -InDomain $InDomain
}
function New-TestRun {
    param([int]$Count=1)
    $script:table=New-QueueTable
    $items=@(for($i=0;$i -lt $Count;$i++) {
        $r=$script:table.NewRow();$r.Nom_du_PC=$script:SourceName;$r.Nouveau_Nom=$script:NewName
        $r.OU_Actuelle=$script:FakeOU;$r.OU_Destination=$script:TargetOU;$r.Renommer=$true;$r.Deplacer=$true;$r.Traiter=$true
        [void]$script:table.Rows.Add($r)
        [pscustomobject]@{Row=$r;Computer=$r.Nom_du_PC;NewName=$r.Nouveau_Nom;CurrentOU=$r.OU_Actuelle;TargetOU=$r.OU_Destination;Rename=$true;Move=$true;Reboot=$false}
    })
    $script:QueueRunState=[pscustomobject]@{Items=$items;Index=0;Total=$Count;Confirm=$false;Mode='REEL';RunId='TEST';OkCount=0;KoCount=0;CancelCount=0;RestartNeeded=$false}
}
try {
    Case 'Le moteur complet est accepte par le parseur Windows PowerShell' {Assert-Equal $parseErrors.Count 0}
    Case 'Reproduction RC3 : $null devient un chemin de sauvegarde invalide' {
        $old=Join-Path $script:TempRoot 'rc3-old.txt';$tmp=Join-Path $script:TempRoot 'rc3-temp.txt'
        [IO.File]::WriteAllText($old,'ancien');[IO.File]::WriteAllText($tmp,'nouveau')
        Assert-Throws {[IO.File]::Replace($tmp,$old,$null)}
        Assert-Equal ([IO.File]::ReadAllText($old)) 'ancien'
    }
    Case 'RC4 : deux ecritures sans backup sur le meme fichier' {
        $p=Join-Path $script:TempRoot 'sans backup [test].json'
        Write-PestoAtomicText $p 'premier';Write-PestoAtomicText $p 'deuxième'
        Assert-Equal ([IO.File]::ReadAllText($p)) 'deuxième';Assert-Equal ([IO.File]::Exists($p+'.bak')) $false
    }
    Case 'RC4 : 100 remplacements successifs sans backup' {
        $p=Join-Path $script:TempRoot 'cent.json'
        for($i=0;$i -lt 100;$i++){Write-PestoAtomicText $p ([string]$i)}
        Assert-Equal ([IO.File]::ReadAllText($p)) '99'
    }
    Case 'RC4 : backup conserve exactement la version precedente' {
        $p=Join-Path $script:TempRoot 'cfg.json'
        Write-PestoAtomicText $p 'A';Write-PestoAtomicText $p 'B' -Backup;Write-PestoAtomicText $p 'C' -Backup
        Assert-Equal ([IO.File]::ReadAllText($p)) 'C';Assert-Equal ([IO.File]::ReadAllText($p+'.bak')) 'B'
    }
    Case 'RC4 : fichier verrouille, erreur explicite et ancien contenu conserve' {
        $p=Join-Path $script:TempRoot 'verrouille.json';Write-PestoAtomicText $p 'ne pas perdre'
        $lock=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try{Assert-Throws {Write-PestoAtomicText $p 'interdit'}}finally{$lock.Dispose()}
        Assert-Equal ([IO.File]::ReadAllText($p)) 'ne pas perdre'
        Assert-Equal @([IO.Directory]::GetFiles($script:TempRoot,'verrouille.json.*.tmp')).Count 0
    }
    Case 'RC4 : contenu vide accepte' {
        $p=Join-Path $script:TempRoot 'vide.txt';Write-PestoAtomicText $p 'plein';Write-PestoAtomicText $p ''
        Assert-Equal ([IO.File]::ReadAllText($p)) ''
    }
    Case 'RC4 : chemin vide refuse' {Assert-Throws {Write-PestoAtomicText -Path '' -Text 'X'}}
    Case 'RC4 : UTF8 accents preservés et sans BOM de fichier JSON' {
        $p=Join-Path $script:TempRoot 'accentué.json';Write-PestoAtomicText $p '{"nom":"Déplacé"}'
        Assert-Equal ([IO.File]::ReadAllText($p)) '{"nom":"Déplacé"}'
        Assert-Equal ([IO.File]::ReadAllBytes($p)[0]) 123
    }
    Case 'Checkpoint reel : Idle -> Active -> BetweenActions -> Idle sur le meme chemin' {
        Reset-Fakes;$script:SIM=$false;New-TestRun
        foreach($phase in @('Idle','Active','BetweenActions','Idle')) {
            Save-PestoQueueCheckpoint -Phase $phase
            $saved=[IO.File]::ReadAllText((Join-Path (Get-PestoStateDirectory) 'queue.json'))|ConvertFrom-Json
            Assert-Equal $saved.Phase $phase
        }
    }
    Case 'Tag extrait du cas utilisateur : PR et VA' {Reset-Fakes;Assert-Equal (Get-PestoNameSiteCode $script:SourceName) 'PR';Assert-Equal (Get-PestoNameSiteCode $script:NewName) 'VA'}
    Case 'Nom hors convention ne produit pas un faux tag' {Assert-Equal (Get-PestoNameSiteCode 'ancien-serveur') $null}
    Case 'PR -> VA : renommage et deplacement automatiques' {Reset-Fakes;$r=Decision;Assert-True $r.Valid;Assert-True $r.Move;Assert-True $r.SiteChanged}
    Case 'VA -> VA : changer seulement le numero ne deplace pas' {Reset-Fakes;$r=Decision -Old 'P111301VA765129';Assert-True $r.Valid;Assert-Equal $r.Move $false;Assert-Equal $r.SiteChanged $false}
    Case 'VA -> VA : changement de service, meme site, pas de deplacement' {Reset-Fakes;$r=Decision -Old 'P111301VA123129';Assert-Equal $r.Move $false}
    Case 'VA -> VA : Portable vers Fixe ne deplace pas' {Reset-Fakes;$r=Decision -Old 'P111301VA765129' -New 'S111301VA765010';Assert-Equal $r.Move $false}
    Case 'Drapeau Move RC3 ignore quand le site est identique' {Reset-Fakes;$r=Decision -Old 'P111301VA765129' -Move $true;Assert-Equal $r.Move $false}
    Case 'Drapeau Move false n empeche pas le deplacement auto PR -> VA' {Reset-Fakes;$r=Decision -Move $false;Assert-True $r.Move}
    Case 'Site different mais poste deja dans OU cible : aucun deplacement inutile' {Reset-Fakes;$r=Decision -Current $script:TargetOU;Assert-True $r.SiteChanged;Assert-Equal $r.Move $false}
    Case 'Comparaison OU insensible a la casse' {Reset-Fakes;$r=Decision -Current $script:TargetOU.ToLowerInvariant();Assert-Equal $r.Move $false}
    Case 'Changement de site sans cible : refus avant mutation' {Reset-Fakes;$r=Decision -Target '';Assert-Equal $r.Valid $false;Assert-Equal $r.Move $false}
    Case 'Meme site sans OU de destination : renommage seul autorise' {Reset-Fakes;$r=Decision -Old 'P111301VA765129' -Target '';Assert-True $r.Valid;Assert-Equal $r.Move $false}
    Case 'Nom cible invalide refuse' {Reset-Fakes;Assert-Equal (Decision -New 'invalide').Valid $false}
    Case 'Meme nom : pas de faux renommage' {Reset-Fakes;Assert-Equal (Decision -New $script:SourceName).Valid $false}
    Case 'Tag insensible a la casse' {Reset-Fakes;$r=Decision -Old 'p111301va765129' -New 'p111301va765010';Assert-Equal $r.Move $false}
    Case 'Deplacement seul explicite conserve' {Reset-Fakes;$r=Decision -Rename $false -Move $true;Assert-True $r.Move;Assert-Equal $r.Automatic $false}
    Case 'Sans renommage et sans demande, pas de deplacement' {Reset-Fakes;Assert-Equal (Decision -Rename $false -Move $false).Move $false}
    Case 'Jonction locale hors domaine conserve OU obligatoire' {Reset-Fakes;Assert-True (Decision -InDomain $false).Move}
    Case 'Ancien nom libre : meme conteneur de site, sous-OU conservee' {
        Reset-Fakes;$r=Decision -Old 'OLD-PC' -Current ('OU=SousEquipe,'+$script:TargetOU)
        Assert-True $r.Valid;Assert-Equal $r.Move $false
    }
    Case 'Ancien nom libre : autre conteneur de site, deplacement auto' {
        Reset-Fakes;$r=Decision -Old 'OLD-PC' -Current 'OU=PR,OU=Sites,OU=Postes,DC=example,DC=local'
        Assert-True $r.Valid;Assert-True $r.Move
    }
    Case 'Ancien nom libre : PREPROD reconnue par la configuration' {Reset-Fakes;$r=Decision -Old 'OLD-PC';Assert-True $r.Valid;Assert-True $r.Move}
    Case 'Ancien nom libre : site indeterminable, aucune supposition' {Reset-Fakes;Assert-Equal (Decision -Old 'OLD-PC' -Current '').Valid $false}
    Case 'Sous-OU PREPROD reste dans le site PREPROD' {Reset-Fakes;Assert-Equal (Get-PestoSiteContainerDN ('OU=A,'+$script:OU.PREPROD)) $script:OU.PREPROD}
    Case 'Faux suffixe AD ne devient pas un site valide' {Reset-Fakes;Assert-Equal (Get-PestoSiteContainerDN 'OU=VA,OU=FauxSites,OU=Postes,DC=example,DC=local') $null}
    Case 'File RC3 : normalisation avant execution active le move PR -> VA' {
        Reset-Fakes;New-TestRun;$r=$script:table.Rows[0];$r.Deplacer=$false
        [void](Update-PestoQueueRenamePlan $r);Assert-True $r.Deplacer
    }
    Case 'File RC3 : normalisation retire le move inutile VA -> VA' {
        Reset-Fakes;New-TestRun;$r=$script:table.Rows[0];$r.Nom_du_PC='P111301VA765129'
        [void](Update-PestoQueueRenamePlan $r);Assert-Equal $r.Deplacer $false
    }
    Case 'Resultat historique jamais reecrit par normalisation' {
        Reset-Fakes;New-TestRun;$r=$script:table.Rows[0];$r.Statut='OK';$r.Deplacer=$false
        [void](Update-PestoQueueRenamePlan $r);Assert-Equal $r.Deplacer $false
    }
    Case 'UI : case deplacement calculee et verrouillee lors du rename' {
        Reset-Fakes;$script:Suspend=$false;$script:OU_ACTUELLE=$script:FakeOU;$script:OU_FINAL=$script:TargetOU
        $script:TxtPCName=[pscustomobject]@{Text=$script:SourceName};$script:CbName=[pscustomobject]@{SelectedItem=$script:NewName}
        $script:ChkRename=[pscustomobject]@{IsChecked=$true};$script:ChkMove=[pscustomobject]@{IsChecked=$false;IsEnabled=$true;Content='';ToolTip=''}
        Check-SameOU;Assert-True $script:ChkMove.IsChecked;Assert-Equal $script:ChkMove.IsEnabled $false;Assert-Equal $script:Suspend $false
        $script:TxtPCName.Text='P111301VA765129';Check-SameOU;Assert-Equal $script:ChkMove.IsChecked $false
    }
    Case 'Moteur : ordre RENAME puis MOVE et resultat 77' {
        Reset-Fakes;$r=Go $true $true $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 77;Assert-Equal ($script:Calls -join ',') 'RENAME,MOVE'
    }
    Case 'Moteur : renommage refuse, aucun deplacement' {
        Reset-Fakes;$script:RenameCode=21;$r=Go $true $true $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 21;Assert-Equal ($script:Calls -join ',') 'RENAME'
    }
    Case 'Moteur : resultat rename absent, aucun deplacement et code 97' {
        Reset-Fakes;$script:RenameEmpty=$true;$r=Go $true $true $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 97;Assert-Equal ($script:Calls -join ',') 'RENAME'
    }
    Case 'Moteur : move refuse apres rename, code 89 partiel conserve' {
        Reset-Fakes;$script:MoveCode=31;$r=Go $true $true $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 89;Assert-Equal ($script:Calls -join ',') 'RENAME,MOVE'
    }
    Case 'Moteur : meme site ignore ancien flag Move true' {
        Reset-Fakes;$r=Go $true $true 'P111301VA765129' $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 20;Assert-Equal ($script:Calls -join ',') 'RENAME'
    }
    Case 'Moteur : ne rajoute pas une mutation absente du plan confirme' {
        Reset-Fakes;$r=Go $true $false $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 21;Assert-Equal $script:Calls.Count 0
    }
    Case 'Moteur : lecture AD refusee, zero mutation' {
        Reset-Fakes;$script:ReadFails=$true;$r=Go $true $true $script:SourceName $script:NewName $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 21;Assert-Equal $script:Calls.Count 0
    }
    Case 'Moteur : deplacement seul explicite reste fonctionnel' {
        Reset-Fakes;$r=Go $false $true $script:SourceName '' $script:TargetOU $script:FakeOU $false
        Assert-Equal $r.ExitCode 30;Assert-Equal ($script:Calls -join ',') 'MOVE'
    }
    Case 'Moteur : hors domaine la file refuse la jonction, renvoi vers la page' {
        Reset-Fakes;$script:INDOMAIN=$false;$r=Go $true $true 'LOCAL-PC' $script:NewName $script:TargetOU '' $false
        # Contrat de Go (Pesto-Operations.ps1) : hors domaine, aucune commande de la file, le poste passe par la page.
        Assert-Equal $r.ExitCode 96;Assert-Equal ($script:Calls -join ',') '';Assert-True ($r.ExitMsg -match 'Ajouter au domaine')
    }
    Case 'Integration locale : checkpoint existant puis lancement du worker mock' {
        Reset-Fakes;$script:SIM=$false;New-TestRun;Save-PestoQueueCheckpoint -Phase 'Idle'
        Start-PestoNextQueueTask
        Assert-Equal $script:WorkerStarts 1;Assert-Equal $script:LastRequest.Computer 'P111301PR765129'
        Assert-True $script:LastRequest.Rename;Assert-True $script:LastRequest.Move;Assert-Equal $script:LastRequest.Reboot $false
        Assert-Equal $script:MutationUncertain $false
    }
    Case 'Precontrole local refuse : zero worker, zero echec AD, une non lancee' {
        Reset-Fakes;$script:SIM=$false;New-TestRun;$script:AuditWritable=$false
        Start-PestoNextQueueTask
        Assert-Equal $script:WorkerStarts 0;Assert-True $script:Finished
        Assert-Equal $script:FinishedState.CancelCount 1;Assert-Equal $script:FinishedState.KoCount 0
        Assert-Equal $script:table.Rows[0].Statut 'NON LANCÉ';Assert-Equal $script:table.Rows[0].Code '96'
        Assert-Equal $script:MutationUncertain $false
    }
    Case 'Precontrole local refuse : les lignes suivantes restent non lancees' {
        Reset-Fakes;$script:SIM=$false;New-TestRun -Count 3;$script:AuditWritable=$false
        Start-PestoNextQueueTask
        Assert-Equal $script:WorkerStarts 0;Assert-Equal $script:FinishedState.CancelCount 3
        Assert-Equal $script:FinishedState.KoCount 0;Assert-Equal $script:FinishedState.OkCount 0
        Assert-Equal @($script:table.Rows|Where-Object{$_.Statut -eq 'NON LANCÉ'}).Count 3
    }
    Case 'Precontrole local ne leve jamais un verrou preexistant' {
        Reset-Fakes;$script:SIM=$false;New-TestRun;$script:AuditWritable=$false;$script:MutationUncertain=$true
        Start-PestoNextQueueTask;Assert-True $script:MutationUncertain
    }
} finally {
    # Nettoyage limite au dossier temporaire cree par cette suite.
    if([IO.Directory]::Exists($script:TempRoot)){[IO.Directory]::Delete($script:TempRoot,$true)}
}
$failed=@($script:Results|Where-Object{-not $_.Passed})
$report=[ordered]@{Suite='Pesto RC4';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();SourceHash=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash;Total=$script:Results.Count;Passed=$script:Results.Count-$failed.Count;Failed=$failed.Count;Tests=$script:Results.ToArray();Scope='Parser Windows PowerShell + fichiers temporaires reels + fonctions extraites, commandes AD et UI remplacees par des mocks. Aucun test AD/reseau/WPF complet.'}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "`n$($report.Passed)/$($report.Total) tests passes ; $($report.Failed) echecs. Rapport : $ReportPath"
if($failed.Count){exit 1}
exit 0
