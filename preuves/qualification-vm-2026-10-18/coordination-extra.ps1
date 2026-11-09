#Requires -Version 5.1
<#
.SYNOPSIS
    Actions de coordination ponctuelles sur le registre partagé de noms, via le vrai worker de Pesto.
.DESCRIPTION
    Ce script Windows PowerShell 5.1 charge uniquement l'affectation $script:PestoSharedNameWorker
    du fichier Pesto-Names.source.ps1 (extraction par l'AST, aucun démarrage de Pesto) et l'exécute
    sur un dossier de course préparé (racine UNC, domaine fictif race-harness.invalid).

    - Acqire : réserve le nom pour Owner, écrit le résultat JSON, puis attend la durée réelle du bail
      afin qu'un arrêt forcé du processus soit possible.
    - Observe : liste le registre (Snapshot) puis tente le même nom avec un autre propriétaire.
    - Release : libère seulement le nom propre à Owner (jamais celui d'un autre poste).

    Aucun verrou n'est effacé manuellement, aucune horloge n'est modifiée : tout passe par le worker
    de Pesto (création exclusive par nom, reprise d'une réservation expirée sous verrou exclusif).
.EXAMPLE
    -Mode Acquire  -Root \\srv\partage\course -SourcePath ...\Pesto-Names.source.ps1 -Owner A -Name RACE0001 -ReportPath \\srv\partage\rapports\acq-a.json
    -Mode Observe  -Root \\srv\partage\course -SourcePath ...\Pesto-Names.source.ps1 -Owner B -Name RACE0001 -ReportPath \\srv\partage\rapports\obs-b.json
    -Mode Release  -Root \\srv\partage\course -SourcePath ...\Pesto-Names.source.ps1 -Owner A -Name RACE0001 -ReportPath \\srv\partage\rapports\rel-a.json
.NOTES
    Codes de sortie : 0 = action faite, 1 = refus.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Acquire', 'Observe', 'Release')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [ValidateRange(0,120)][int]$DelaySeconds=0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:RaceDomain = 'race-harness.invalid'
$script:RaceMarkerName = 'race-harness.json'
$script:LeaseMinutes = 5

function Resolve-CoordinationPath {
    param([string]$Path)
    if (-not $Path) { throw 'Chemin vide.' }
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).ProviderPath $Path }
    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Read-CoordinationJson {
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json)
}

function Write-CoordinationNewFile {
    param([string]$Path, [string]$Text)
    # Création exclusive : un rapport existant n'est jamais écrasé.
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

function Get-CoordinationSourcePath {
    param([string]$Path)
    if (-not $Path) { throw 'SourcePath est obligatoire (Pesto-Names.source.ps1).' }
    $full = Resolve-CoordinationPath $Path
    if (-not [IO.File]::Exists($full)) { throw ('Source Pesto introuvable : ' + $full) }
    return $full
}

function Import-CoordinationWorker {
    <# Uniquement l'affectation $script:PestoSharedNameWorker : aucun démarrage de Pesto. #>
    param([string]$Path)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count) { throw ('Syntaxe PowerShell invalide : ' + $Path) }
    $assignment = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:PestoSharedNameWorker' })
    if ($assignment.Count -ne 1) { throw 'Worker de réservation partagé absent ou ambigu dans la source.' }
    $worker = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))
    if ($worker -isnot [scriptblock]) { throw 'Le worker de réservation partagé n''est pas un bloc de script.' }
    return $worker
}

function Assert-CoordinationRoot {
    param([string]$RootPath)
    if ($RootPath -notmatch '^\\\\[^\\/]+\\[^\\/]+') { throw 'Root doit être une racine UNC préparée (\\serveur\partage...).' }
    $marker = Join-Path $RootPath $script:RaceMarkerName
    if (-not [IO.File]::Exists($marker)) { throw 'Marqueur race-harness.json absent : dossier de course non préparé.' }
    if ([string](Read-CoordinationJson $marker).Purpose -cne 'PestoRaceHarness') { throw 'Marqueur race-harness.json invalide.' }
    $registry = Join-Path $RootPath 'pesto-coordination.json'
    if (-not [IO.File]::Exists($registry)) { throw 'Registre de coordination absent.' }
    if ([string](Read-CoordinationJson $registry).Domain -ine $script:RaceDomain) { throw 'Refus : ce dossier porte un registre de production (domaine réel).' }
}

function New-CoordinationRequest {
    param([string]$RequestMode, [string]$RootPath, [string]$OwnerName, [string]$NameValue = '', [string[]]$NamesValue = @())
    return [pscustomobject]@{ Mode = $RequestMode; Root = $RootPath; Domain = $script:RaceDomain; Owner = $OwnerName
        Station = [Environment]::MachineName; User = 'coordination-extra'; Context = 'coordination-extra'
        Minutes = $script:LeaseMinutes; Name = $NameValue; Names = $NamesValue; Credential = $null }
}

function Write-CoordinationReport {
    param([string]$Path, [object]$Result)
    $full = Resolve-CoordinationPath $Path
    $dir = [IO.Path]::GetDirectoryName($full)
    if ($dir -and -not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    Write-CoordinationNewFile $full ($Result | ConvertTo-Json -Depth 6)
    Write-Host ('Rapport : ' + $full)
}

try {
    $rootFull = Resolve-CoordinationPath $Root
    Assert-CoordinationRoot $rootFull
    $source = Get-CoordinationSourcePath $SourcePath
    $worker = Import-CoordinationWorker $source
    if($DelaySeconds){Start-Sleep -Seconds $DelaySeconds}
    $utc = [DateTime]::UtcNow.ToString('o')

    switch ($Mode) {
        'Acquire' {
            $answer = & $worker (New-CoordinationRequest -RequestMode 'Reserve' -RootPath $rootFull -OwnerName $Owner -NameValue $Name)
            $report = [ordered]@{ Schema = 1; Action = 'Acquire'; ProcessId=$PID; Owner = $Owner; Name = $Name; Domain = $script:RaceDomain
                Root = $rootFull; Utc = $utc; LeaseMinutes = $script:LeaseMinutes; State = [string]$answer.State
                Holder = [string]$answer.Holder; HolderExpiresUtc = [string]$answer.HolderExpiresUtc; Connected = [string]$answer.Connected }
            Write-CoordinationReport -Path $ReportPath -Result $report
            # Bail réel : le processus reste vivant pendant la durée du bail, afin d'être arrêté de force.
            $deadline = [DateTime]::UtcNow.AddMinutes($script:LeaseMinutes)
            while ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
        }
        'Observe' {
            $snapshot = & $worker (New-CoordinationRequest -RequestMode 'Snapshot' -RootPath $rootFull -OwnerName $Owner)
            $observerOwner = ($Owner + '-OBS')
            $attempt = & $worker (New-CoordinationRequest -RequestMode 'Reserve' -RootPath $rootFull -OwnerName $observerOwner -NameValue $Name)
            $report = [ordered]@{ Schema = 1; Action = 'Observe'; Owner = $Owner; ObserverOwner = $observerOwner; Name = $Name
                Domain = $script:RaceDomain; Root = $rootFull; Utc = $utc; LeaseMinutes = $script:LeaseMinutes
                OthersCount = [int]$snapshot.Count; Others = @($snapshot.Others)
                AttemptState = [string]$attempt.State; AttemptHolder = [string]$attempt.Holder
                AttemptHolderExpiresUtc = [string]$attempt.HolderExpiresUtc; Connected = [string]$snapshot.Connected }
            Write-CoordinationReport -Path $ReportPath -Result $report
        }
        'Release' {
            $answer = & $worker (New-CoordinationRequest -RequestMode 'Release' -RootPath $rootFull -OwnerName $Owner -NamesValue @($Name))
            $report = [ordered]@{ Schema = 1; Action = 'Release'; Owner = $Owner; Name = $Name; Domain = $script:RaceDomain
                Root = $rootFull; Utc = $utc; State = [string]$answer.State; Released = @($answer.Others); Connected = [string]$answer.Connected }
            Write-CoordinationReport -Path $ReportPath -Result $report
        }
    }
} catch {
    [Console]::Error.WriteLine('Coordination refusée : ' + $_.Exception.Message)
    exit 1
}
exit 0
