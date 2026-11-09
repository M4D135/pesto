#requires -Version 5.1
# Run-AcknowledgementTests.ps1 : Test unitaire de Set-PestoOperationAcknowledgement
# Exécution isolée, sans AD, sans ProgramData réel, sans mutation Windows.
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}

# 1. Extraction AST des sources réelles
$dev=Split-Path $PSScriptRoot -Parent
$defs=@{};$asts=@{}
foreach($file in Get-ChildItem (Join-Path $dev 'wad') -Filter 'Pesto-*.ps1' -File){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
    $asts[$file.Name]=$ast
    foreach($fn in $ast.EndBlock.Statements){if($fn -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$fn.Name]=$fn.Extent.Text}}
}
foreach($definition in $defs.Values){. ([scriptblock]::Create($definition))}
# Chargement des variables de script critiques pour le contexte
foreach($node in $asts['Pesto-Core.ps1'].EndBlock.Statements){if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:PestoWorkerCoreNames'){. ([scriptblock]::Create($node.Extent.Text))}}

# 2. Configuration de l'environnement de test (Isolation)
$script:FixtureRoot=Join-Path $PSScriptRoot ('ack-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:FixtureRoot)
$script:CoordRoot=Join-Path $script:FixtureRoot 'coord';[void][IO.Directory]::CreateDirectory((Join-Path $script:CoordRoot 'locks'))
$script:InterventionRoot=Join-Path $script:FixtureRoot 'interventions';[void][IO.Directory]::CreateDirectory($script:InterventionRoot)
$script:DirectPath=Join-Path $script:FixtureRoot 'direct.json'
$script:JoinPath=Join-Path $script:FixtureRoot 'join.json'

# 3. Doubles explicites (UI, AD, Coordination, State)
$script:SIM=$false;$script:GUI=$false;$script:PestoReadOnly=$false
$script:DOMAINE='example.test';$script:HostMachineId='operator-machine'
$script:Running=$false;$script:PreflightRunning=$false;$script:DirectBusy=$false;$script:JoinBusy=$false
$script:DirectReceipt=$null;$script:JoinReceipt=$null;$script:DirectLocked=$false;$script:JoinLocked=$false
$script:MutationUncertain=$false;$script:QueueOperationIds=@()
$script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{CoordinationRoot=$script:CoordRoot}}

# Redéfinition des chemins pour éviter ProgramData
function Get-PestoInterventionRoot {return $script:InterventionRoot}
function Get-PestoDirectStatePath {return $script:DirectPath}
function Get-PestoJoinStatePath {return $script:JoinPath}

# Doubles de coordination (fichiers locaux dans FixtureRoot)
function Get-PestoCoordinationRoot {param($Policy,$Domain);return $script:CoordRoot}
function Enter-PestoCoordination {param($Plan,$OperationId,$Policy,$ResumeId='');return [pscustomobject]@{Enabled=$false;Keys=@();Owner=$OperationId}}
function Exit-PestoCoordination {param($Receipt,$Policy);$script:CoordinationReleases++}

# Lecteurs, writers et validations de reçus sont les fonctions réelles extraites plus haut.
# Seuls les getters de chemins redirigent le stockage et ses ACL dans FixtureRoot.
# Doubles UI/Log
function Update-QueueButtons {}
function Update-AddButton {}
function Update-PestoSuiteUI {}
function Update-PestoJoinUI {}
function Add-LogLine {}
function Write-AuditLine {}
function Test-PestoQueueWorkerStillActive {return $false}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
function Show-MsgInfo {}
function Show-MsgWarning {}
function Show-MsgError {}
function Show-PestoTextReport {}
# 4. Helpers de fixtures
function New-Plan {
    [pscustomobject]@{Nom_du_PC='OLD-PC';Nouveau_Nom='NEW-PC';Domain='example.test';DC='dc.example.test';Objet_GUID='11111111-1111-1111-1111-111111111111';OU_Actuelle='OU=Old,DC=example,DC=test';OU_Destination='OU=New,DC=example,DC=test';Renommer=$true;Deplacer=$true;Reboot=$false;TargetOUGuid='22222222-2222-2222-2222-222222222222';ConfigStamp='test'}
}
function New-Completed {
    [pscustomobject]@{Schema=2;OperationId=[Guid]::NewGuid().ToString('N');Phase='PendingRestart';ResultCode=[int]20;Plan=(New-Plan);TargetMachineId='operator-machine';LastStage='Result';StartedUtc='2026-01-01T08:00:00Z';UpdatedUtc='2026-01-01T08:30:00Z';VerifiedUtc='';Rename='Confirmed';Move='NotRequested';Entra='NotRequested';Protection='Restored';JoinEvidence=$null;Sequence=0;Timeline=@();ResumeFrom='';ResultMessage='accepted';Coordination=$null;Tasks=@()}
}
function New-JoinReceipt {
    [pscustomobject]@{Schema=1;Version='1.0';OperationId=[Guid]::NewGuid().ToString('N');Phase='PendingRestart';Utc='2026-01-01T08:30:00Z';MachineId='operator-machine';BootUtc='2026-01-01T08:00:00Z';Computer='OLD-PC';NewName='P111301AA765001';Domain='example.test';DC='dc.example.test';OU='OU=Old,DC=example,DC=test';Reference='';Account='';Message='accepted'}
}
function Reset-Fixture {
    Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    [void][IO.Directory]::CreateDirectory($script:FixtureRoot)
    [void][IO.Directory]::CreateDirectory((Join-Path $script:CoordRoot 'locks'))
    [void][IO.Directory]::CreateDirectory($script:InterventionRoot)
    $script:DirectReceipt=$null;$script:JoinReceipt=$null
    $script:DirectLocked=$false;$script:JoinLocked=$false
    $script:PestoReadOnly=$false;$script:SIM=$false;$script:GUI=$false;$script:Running=$false;$script:PreflightRunning=$false;$script:DirectBusy=$false;$script:JoinBusy=$false;$script:CoordinationReleases=0
}

$checks=[Collections.Generic.List[object]]::new()
function Assert {param($Value,[string]$Why='Assertion failed');if(-not $Value){throw $Why}}
function Throws {param([scriptblock]$Action);$thrown=$false;try{& $Action|Out-Null}catch{$thrown=$true};Assert $thrown 'Expected rejection'}
function Case {param($Name,[scriptblock]$Body);Reset-Fixture;try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Location=$_.ScriptStackTrace})}}

# 5. Tests

Case 'Acquittement registre + direct avec Phase Uncertain/code97/effets conservés' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain';$r.ResultCode=97;$r.Rename='Confirmed';$r.Move='Confirmed'
    Write-PestoIntervention $r
    $d=New-Completed;$d.Schema=1;$d.OperationId=$id;$d.Phase='Uncertain';$d.ResultCode=97;$d|Add-Member NoteProperty OperatorMachineId 'operator-machine'
    Write-PestoDirectReceipt -Path (Get-PestoDirectStatePath) -Receipt $d

    $res=Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test motif'

    Assert ($res.Receipts -contains 'registre des interventions')
    Assert ($res.Receipts -contains 'opération unitaire')

    $newR=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id+'.json'))
    Assert ($newR.Acknowledged)
    Assert ($newR.Phase -eq 'Uncertain') # Phase conservée
    Assert ($newR.ResultCode -eq 97)     # Code conservé
    Assert ($newR.Rename -eq 'Confirmed') # Effets conservés

    $newD=Read-PestoDirectReceipt (Get-PestoDirectStatePath)
    Assert ($newD.Acknowledged)
    Assert ($newD.Phase -eq 'Uncertain')
}

Case 'Lecture sans observation et motif enregistré' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain';$r.ResultCode=97
    Write-PestoIntervention $r

    $res=Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Motif test'
    $newR=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id+'.json'))
    Assert ($newR.Acknowledged.Reason -eq 'Motif test')
    Assert ($null -eq $newR.LastObservation) # Pas d'observation passée
}

Case 'Aucun succès ajouté' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain';$r.ResultCode=97
    Write-PestoIntervention $r

    Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'
    $newR=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id+'.json'))
    Assert ($newR.Phase -ne 'Verified')
    Assert ($newR.Phase -ne 'Failed') # Reste Uncertain
}

Case 'Refus read-only' {
    $script:PestoReadOnly=$true
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain'
    Write-PestoIntervention $r
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}
    $script:PestoReadOnly=$false
}

Case 'Refus simulation' {
    $script:SIM=$true
    $id=[Guid]::NewGuid().ToString('N')
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}
    $script:SIM=$false
}

Case 'Refus worker actif' {
    $script:Running=$true
    $id=[Guid]::NewGuid().ToString('N')
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}
    $script:Running=$false
}

Case 'Refus autre domaine' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain';$r.Plan.Domain='other.test'
    Write-PestoIntervention $r
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}
}

Case 'Refus tâche Started, réussite Finished' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain'
    $r.Tasks=@([pscustomobject]@{Computer='OLD-PC';Name='\Pesto_Test';Phase='Started';Hash='';NativeCode=$null;Utc=''})
    Write-PestoIntervention $r
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}

    $r.Tasks=@([pscustomobject]@{Computer='OLD-PC';Name='\Pesto_Test';Phase='Finished';Hash='';NativeCode=$null;Utc=''})
    Write-PestoIntervention $r
    $res=Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'
    Assert ($res.Receipts -contains 'registre des interventions')
}

Case 'Aucun reçu à acquitter => refus' {
    $id=[Guid]::NewGuid().ToString('N')
    Throws {Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'}
}

Case 'Empreinte phase/code rend acquittement caduc' {
    $id=[Guid]::NewGuid().ToString('N')
    $r=New-Completed;$r.OperationId=$id;$r.Phase='Uncertain';$r.ResultCode=97
    Write-PestoIntervention $r

    # Acquitter
    Set-PestoOperationAcknowledgement -OperationId $id -Reason 'Test'

    # Modifier le reçu (simuler une nouvelle mutation qui change la phase)
    $r2=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id+'.json'))
    $r2.Phase='Partial'
    Write-PestoIntervention $r2

    # Vérifier que l'acquittement est considéré comme invalide par la logique métier (via Test-PestoAcknowledgedReceipt)
    # Dans le contexte de Set-PestoOperationAcknowledgement, si on essaie de réacquitter, il devrait dire "déjà acquitté" ou "non résolu" selon la logique.
    # Ici, on vérifie que Test-PestoAcknowledgedReceipt retourne false car la phase ne correspond plus.
    Assert (-not (Test-PestoAcknowledgedReceipt $r2))
}

Case 'Refus démonstration' {
    $script:GUI=$true
    Throws {Set-PestoOperationAcknowledgement -OperationId ([Guid]::NewGuid().ToString('N')) -Reason 'Examen manuel'}
}
Case 'Mutex tenu dans un autre runspace refuse sans écrire' {
    $r=New-Completed;$r.Phase='Uncertain';Write-PestoIntervention $r
    $path=Join-Path (Get-PestoInterventionRoot) ($r.OperationId+'.json');$before=[IO.File]::ReadAllText($path)
    $ready=[Threading.ManualResetEvent]::new($false);$release=[Threading.ManualResetEvent]::new($false);$owner=[PowerShell]::Create()
    try{
        [void]$owner.AddScript({param($Ready,$Release)
            $gate=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1');$held=$false
            try{$held=$gate.WaitOne(0);if(-not $held){throw 'Mutex de test indisponible'};[void]$Ready.Set();[void]$Release.WaitOne(15000)}finally{if($held){$gate.ReleaseMutex()};$gate.Dispose()}
        }).AddArgument($ready).AddArgument($release)
        $handle=$owner.BeginInvoke();Assert ($ready.WaitOne(5000)) 'Mutex de test non acquis'
        Throws {Set-PestoOperationAcknowledgement -OperationId $r.OperationId -Reason 'Examen manuel'}
        Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Écriture malgré mutex occupé'
        [void]$release.Set();[void]$owner.EndInvoke($handle);Assert ($owner.Streams.Error.Count -eq 0)
    }finally{[void]$release.Set();$owner.Dispose();$ready.Dispose();$release.Dispose()}
}

Case 'Ancien reçu valide sans métadonnées de suivi peut être acquitté' {
    $r=New-Completed;$r.Phase='Uncertain';$r.ResultCode=97
    $r.PSObject.Properties.Remove('UpdatedUtc');$r.PSObject.Properties.Remove('LastStage')
    Write-PestoIntervention $r
    [void](Set-PestoOperationAcknowledgement -OperationId $r.OperationId -Reason 'Examen manuel ancien reçu')
    $saved=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($r.OperationId+'.json'))
    Assert (Test-PestoAcknowledgedReceipt $saved);Assert ($saved.Phase -eq 'Uncertain' -and $saved.ResultCode -eq 97)
}
Case 'Reçu unitaire isolé d un autre domaine inchangé' {
    $d=New-Completed;$d.Schema=1;$d.Phase='Uncertain';$d.Plan.Domain='other.test';$d|Add-Member NoteProperty OperatorMachineId 'operator-machine'
    Write-PestoDirectReceipt -Path (Get-PestoDirectStatePath) -Receipt $d
    $before=[IO.File]::ReadAllText((Get-PestoDirectStatePath))
    Throws {Set-PestoOperationAcknowledgement -OperationId $d.OperationId -Reason 'Examen manuel'}
    Assert ([IO.File]::ReadAllText((Get-PestoDirectStatePath)) -ceq $before)
}
Case 'Jonction locale acquittée avec code absent conservé' {
    $j=New-JoinReceipt;$j.Phase='Uncertain';Write-PestoJoinReceipt -Path (Get-PestoJoinStatePath) -Receipt $j
    [void](Set-PestoOperationAcknowledgement -OperationId $j.OperationId -Reason 'Examen manuel jonction')
    $saved=Read-PestoJoinReceipt (Get-PestoJoinStatePath)
    Assert (Test-PestoAcknowledgedReceipt $saved);Assert ($saved.Phase -eq 'Uncertain');Assert ($null -eq $saved.Acknowledged.ResultCode)
}
Case 'Jonction locale autre domaine reste inchangée' {
    $j=New-JoinReceipt;$j.Phase='Uncertain';$j.Domain='other.test';$j.OU='OU=Old,DC=other,DC=test'
    Write-PestoJoinReceipt -Path (Get-PestoJoinStatePath) -Receipt $j
    $before=[IO.File]::ReadAllText((Get-PestoJoinStatePath))
    Throws {Set-PestoOperationAcknowledgement -OperationId $j.OperationId -Reason 'Examen manuel'}
    Assert ([IO.File]::ReadAllText((Get-PestoJoinStatePath)) -ceq $before)
}

# 6. Rapport
$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Passed=($checks.Count-$failed);Failed=$failed;Checks=$checks.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$true;ADExecuted=$false;WPFExecuted=$false;Scope='Windows PowerShell 5.1, vrais contrats/readers/writers, fichiers et ACL temporaires, doubles UI et coordination, aucun AD'}
if($ReportPath){$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 8
Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force
if($failed){exit 1}
