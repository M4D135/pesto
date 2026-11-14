#requires -Version 5.1
[CmdletBinding()]
param([string]$SinkPath = '',[string]$ReportPath = '')

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $SinkPath) { $SinkPath = Join-Path (Split-Path $root -Parent) 'wad/Pesto-AuditSink.ps1' }

if (-not (Test-Path -LiteralPath $SinkPath)) { throw "Fichier introuvable: $SinkPath" }

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($SinkPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ("Erreurs de parsing: " + ($parseErrors | Out-String)) }

$funcAst = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-PestoAuditSinkReceipt'}, $true) | Select-Object -First 1
if (-not $funcAst) { throw 'Fonction Invoke-PestoAuditSinkReceipt introuvable.' }

$sinkSb = [scriptblock]::Create($funcAst.Extent.Text)

$script:LogCalls = @()
$script:EventLogCalls = @()
$script:EventLogThrows = $false
$script:Cases = [Collections.Generic.List[object]]::new()
$script:Pass = 0
$script:Fail = 0

function Write-Log {
    param($Message, $Level = 'INFO', $Err, [string]$Context)
    $script:LogCalls += [pscustomobject]@{ Message = $Message; Level = $Level; Context = $Context }
}

function Write-EventLog {
    [CmdletBinding()]
    param($LogName, $Source, $EntryType, [int]$EventId, $Message, [int]$Category = 0)
    if ($script:EventLogThrows) { throw 'Mock EventLog failure.' }
    $script:EventLogCalls += [pscustomobject]@{
        LogName = $LogName
        Source = $Source
        EntryType = $EntryType
        EventId = $EventId
        Message = $Message
        Category = $Category
    }
}

function Assert-True {
    param($Condition, [string]$Name)
    $script:Cases.Add([pscustomobject]@{Name=$Name;Passed=[bool]$Condition;Error=$(if($Condition){''}else{'Condition non satisfaite.'})})
    if ($Condition) {
        $script:Pass++
        Write-Host "PASS $Name"
    } else {
        $script:Fail++
        Write-Host "FAIL $Name"
    }
}

function Reset-AuditTestState {
    $script:LogCalls = @()
    $script:EventLogCalls = @()
    $script:EventLogThrows = $false
    $script:PestoPolicy = $null
    $script:PestoAuditSinkStatus = $null
}

function New-UtcRoundtrip { return [DateTime]::UtcNow.ToString('o') }
function New-GuidN { return [Guid]::NewGuid().ToString('N') }
function Get-WarnCount { return @($script:LogCalls | Where-Object { $_.Level -eq 'WARN' }).Count }

. $sinkSb

# 1) Désactivé
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $false }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($null -eq $out) 'disabled: no pipeline output'
Assert-True ($script:EventLogCalls.Count -eq 0) 'disabled: no EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'disabled: no WARN'

# 2) Projection centrale fermée
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$op = New-GuidN
$utc = New-UtcRoundtrip
$central = [pscustomobject]@{
    Schema = 2
    OperationId = $op
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = $utc
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($null -eq $out) 'central: no pipeline output'
Assert-True ($script:EventLogCalls.Count -eq 1) 'central: one EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'central: no WARN'
Assert-True ($funcAst.Extent.Text -notmatch 'New-EventLog') 'central: no automatic source creation'
if ($script:EventLogCalls.Count -eq 1) {
    $json = $script:EventLogCalls[0].Message
    $obj = $json | ConvertFrom-Json
    $props = @($obj.PSObject.Properties.Name) | Sort-Object
    Assert-True (($props -join ',') -eq 'Kind,OperationId,Product,ResultCode,Schema,Sequence,State,UpdatedUtc') 'central: closed projection fields'
    Assert-True ($obj.Schema -eq 1) 'central: projection Schema 1'
    Assert-True ($obj.Product -eq 'Pesto') 'central: Product Pesto'
    Assert-True ($obj.OperationId -eq $op) 'central: OperationId preserved'
    Assert-True ($obj.Kind -eq 'Intervention') 'central: Kind Intervention'
    Assert-True ($obj.State -eq 'Verified') 'central: State preserved'
    Assert-True ($obj.ResultCode -eq 0) 'central: ResultCode 0'
    Assert-True ($obj.Sequence -eq 1) 'central: Sequence 1'
    Assert-True (([datetime]$obj.UpdatedUtc).ToUniversalTime() -eq ([datetime]$utc).ToUniversalTime()) 'central: UpdatedUtc preserved'
    Assert-True ($script:EventLogCalls[0].LogName -eq 'Application') 'central: Application log'
    Assert-True ($script:EventLogCalls[0].Source -eq 'Pesto') 'central: Pesto source'
    Assert-True ($script:EventLogCalls[0].EntryType -eq 'Information') 'central: Information entry'
    Assert-True ($script:EventLogCalls[0].EventId -eq 1000) 'central: EventId 1000'
}
Assert-True ($null -ne $script:PestoAuditSinkStatus.LastSuccessUtc) 'central: LastSuccessUtc set'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 0) 'central: no failures'

# 3) Projection directe
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$op = New-GuidN
$utc = New-UtcRoundtrip
$direct = [pscustomobject]@{
    Schema = 1;OperationId = $op;OperatorMachineId = 'fake-machine';LocalSource = $true
    Phase = 'Verified';ResultCode = 0;StartedUtc = $utc;FinishedUtc = $utc;ObservedUtc = ''
    Plan = [pscustomobject]@{Rename=$true}
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $direct
Assert-True ($script:EventLogCalls.Count -eq 1) 'direct: one EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'direct: no WARN'
if ($script:EventLogCalls.Count -eq 1) {
    $obj = $script:EventLogCalls[0].Message | ConvertFrom-Json
    Assert-True ($obj.Kind -eq 'Direct') 'direct: Kind Direct'
}

# 4) Projection join
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$op = New-GuidN
$utc = New-UtcRoundtrip
$join = [pscustomobject]@{
    Version = '1.0';OperationId = $op;Phase = 'PendingRestart';Utc = $utc
    MachineId = 'fake-machine';BootUtc = $utc;Domain = 'example.test'
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $join
Assert-True ($script:EventLogCalls.Count -eq 1) 'join: one EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'join: no WARN'
if ($script:EventLogCalls.Count -eq 1) {
    $obj = $script:EventLogCalls[0].Message | ConvertFrom-Json
    Assert-True ($obj.Kind -eq 'Join') 'join: Kind Join'
    Assert-True ($null -eq $obj.ResultCode -and $null -eq $obj.Sequence) 'join: missing code and sequence stay unknown'
}

# 5) Réservation non opérationnelle ignorée
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$reservation = [pscustomobject]@{
    Schema = 1
    OperationId = 'bad'
    Phase = 'Reserved'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Reservation = 'x'
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $reservation
Assert-True ($script:EventLogCalls.Count -eq 0) 'nonreceipt: no EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'nonreceipt: no WARN'

# 6) OperationId mal typé -> failclosed
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = 'bad'
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 0) 'malformed OperationId: no EventLog'
Assert-True ((Get-WarnCount) -eq 1) 'malformed OperationId: WARN'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 1) 'malformed OperationId: failure counted'

# 7) Erreur EventLog isolée
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$script:EventLogThrows = $true
$threw = $false
try { $out = Invoke-PestoAuditSinkReceipt -Receipt $central } catch { $threw = $true }
Assert-True (-not $threw) 'error isolated: no exception'
Assert-True ($script:EventLogCalls.Count -eq 0) 'error isolated: no EventLog'
Assert-True ((Get-WarnCount) -eq 1) 'error isolated: WARN'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 1) 'error isolated: failure counted'
Assert-True ($null -ne $script:PestoAuditSinkStatus.LastFailureUtc) 'error isolated: LastFailureUtc set'
Assert-True ($null -eq $script:PestoAuditSinkStatus.LastSuccessUtc) 'error isolated: no LastSuccessUtc'

# 8) Aucune fuite de secret/machine/Plan/ResultMessage
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Secret = 'ZZSECRETZZ'; Objet_GUID = 'ZZMACHINEZZ' }
    Secret = 'ZZSECRETZZ'
    ResultMessage = 'ZZSECRETZZ'
    TargetMachineName = 'ZZMACHINEZZ'
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 1) 'no secrets: one EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'no secrets: no WARN'
if ($script:EventLogCalls.Count -eq 1) {
    $json = $script:EventLogCalls[0].Message
    Assert-True ($json -notlike '*ZZSECRETZZ*') 'no secrets: no secret token'
    Assert-True ($json -notlike '*ZZMACHINEZZ*') 'no secrets: no machine token'
    Assert-True ($json -notlike '*ResultMessage*') 'no secrets: no ResultMessage'
    Assert-True ($json -notlike '*Plan*') 'no secrets: no Plan'
}

# 9) ResultCode mal typé -> failclosed
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 'abc'
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 0) 'malformed ResultCode: no EventLog'
Assert-True ((Get-WarnCount) -eq 1) 'malformed ResultCode: WARN'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 1) 'malformed ResultCode: failure counted'

# 10) UpdatedUtc mal typé -> failclosed
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = 'not-date'
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 0) 'malformed UpdatedUtc: no EventLog'
Assert-True ((Get-WarnCount) -eq 1) 'malformed UpdatedUtc: WARN'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 1) 'malformed UpdatedUtc: failure counted'

# 11) Sequence mal typée -> failclosed
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'Verified'
    ResultCode = 0
    Sequence = 'x'
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 0) 'malformed Sequence: no EventLog'
Assert-True ((Get-WarnCount) -eq 1) 'malformed Sequence: WARN'
Assert-True ($script:PestoAuditSinkStatus.Failures -eq 1) 'malformed Sequence: failure counted'

# 12) Phase observable acceptée telle quelle
Reset-AuditTestState
$script:PestoPolicy = [pscustomobject]@{ AuditEventLogEnabled = $true }
$central = [pscustomobject]@{
    Schema = 2
    OperationId = New-GuidN
    Phase = 'MoveReady'
    ResultCode = 0
    Sequence = 1
    UpdatedUtc = New-UtcRoundtrip
    Plan = [pscustomobject]@{ Objet_GUID = 'x' }
}
$out = Invoke-PestoAuditSinkReceipt -Receipt $central
Assert-True ($script:EventLogCalls.Count -eq 1) 'observable phase: one EventLog'
Assert-True ((Get-WarnCount) -eq 0) 'observable phase: no WARN'
if ($script:EventLogCalls.Count -eq 1) {
    $obj = $script:EventLogCalls[0].Message | ConvertFrom-Json
    Assert-True ($obj.State -eq 'MoveReady') 'observable phase: State preserved'
}


# Le schéma central 3 utilisé pour les jonctions est également exporté.
Reset-AuditTestState
$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled=$true}
$central.Schema=3;$central.Phase='Uncertain'
Invoke-PestoAuditSinkReceipt $central
Assert-True ($script:EventLogCalls.Count -eq 1) 'central schema 3 supported'

# Schémas mal typés et phases libres : pas de projection d'informations libres.
foreach($case in @('Schema','Phase','OperationId')) {
    Reset-AuditTestState;$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled=$true}
    $bad=$central|Select-Object *
    switch($case){'Schema'{$bad.Schema='3'};'Phase'{$bad.Phase='ZZSECRETZZ'};'OperationId'{$bad.OperationId=[Guid]::NewGuid()}}
    Invoke-PestoAuditSinkReceipt $bad
    Assert-True ($script:EventLogCalls.Count -eq 0 -and (Get-WarnCount) -eq 1) ('malformed '+$case+' rejected')
}
Reset-AuditTestState;$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled='true'}
Invoke-PestoAuditSinkReceipt $central
Assert-True ($script:EventLogCalls.Count -eq 0) 'policy string cannot enable sink'

# Timestamps directs : observation prioritaire ; démarrage utilisé seulement si les autres sont vides.
Reset-AuditTestState;$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled=$true}
$direct.ObservedUtc='2026-10-16T10:00:00Z';Invoke-PestoAuditSinkReceipt $direct
$obj=$script:EventLogCalls[0].Message|ConvertFrom-Json
Assert-True (([datetime]$obj.UpdatedUtc).ToUniversalTime() -eq ([datetime]$direct.ObservedUtc).ToUniversalTime()) 'direct observation timestamp preserved'
Assert-True ($null -eq $obj.Sequence) 'direct missing sequence stays unknown'

# Exécuter la fin réelle du writer (ACL Windows déjà couverte séparément), avec doubles d'IO.
$joinPath=Join-Path (Split-Path $root -Parent) 'wad/Pesto-Join.ps1'
$tokens=$null;$errors=$null;$joinAst=[Management.Automation.Language.Parser]::ParseFile($joinPath,[ref]$tokens,[ref]$errors)
$writer=$joinAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-PestoJoinReceipt'},$true)
$tail=@($writer.Body.EndBlock.Statements)[-2..-1]
$writeTail=[scriptblock]::Create('param($Path,$Receipt)'+[Environment]::NewLine+($tail.Extent.Text -join [Environment]::NewLine))
$script:Persisted=$false;$script:PersistThrows=$false
function Write-PestoAtomicText {param($Path,$Text);if($script:PersistThrows){throw 'test storage failure'};$script:Persisted=$true}
Reset-AuditTestState;$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled=$true}
$script:EventLogThrows=$true
$threw=$false;try{& $writeTail 'unused' $central}catch{$threw=$true}
Assert-True ($script:Persisted -and -not $threw -and (Get-WarnCount) -eq 1) 'audit failure preserves durable writer result'
Reset-AuditTestState;$script:PestoPolicy=[pscustomobject]@{AuditEventLogEnabled=$true}
$script:PersistThrows=$true;$threw=$false;try{& $writeTail 'unused' $central}catch{$threw=$true}
Assert-True ($threw -and $script:EventLogCalls.Count -eq 0) 'failed durable write emits no audit event'

$report=[pscustomobject]@{Schema=1;Suite='AuditSink';PowerShell=$PSVersionTable.PSVersion.ToString();
    WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');NativeEventLogExecuted=$false;ADExecuted=$false;WPFExecuted=$false;
    Passed=$script:Pass;Failed=$script:Fail;Cases=$script:Cases.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
Write-Host ("Tests: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
