#Requires -Version 5.1
<#
.SYNOPSIS
    Banc de course multi-processus et multi-postes pour le registre partagé de noms de Pesto.
.DESCRIPTION
    Chaque participant est un processus PowerShell séparé (powershell.exe sous Windows PowerShell 5.1, sinon le même
    pwsh) qui charge le vrai worker $script:PestoSharedNameWorker de wad/Pesto-Names.ps1 (extrait par l'AST, sans
    démarrer Pesto). Tous les processus de tous les postes tentent de réserver le même nom RACEnnnn au même créneau
    (même -Root partagé, même -StartAtUtc, même -IntervalMs). Une régression du verrouillage de Pesto change donc
    le verdict de -Analyze (ONE_OWNER_PER_ROUND, VIOLATION ou INCOMPLETE).
    Le dossier de course est dédié : marqueur race-harness.json et registre du domaine fictif race-harness.invalid ;
    un registre de production est refusé. Aucun AD, aucune configuration Pesto lue ou modifiée, aucun partage créé.

    Les réservations du banc restent en place jusqu'à expiration naturelle. Une libération à la fin
    de chaque worker permettrait à un poste dont l'horloge retarde de réacquérir les derniers noms,
    créant un faux double propriétaire. Synchroniser les horloges avant la course ; les timestamps
    de tentative et de vérification permettent d'en examiner les limites.
.EXAMPLE
    Une fois : Measure-PestoCoordinationRace.ps1 -Prepare -Root \\srv\banc\course
    Sur chaque poste, même départ : -Run -Root \\srv\banc\course -Operator A -Rounds 50 -StartAtUtc 2026-10-15T10:00:00Z `
        -IntervalMs 1000 -Processes 4 -ReportPath \\srv\banc\rapports
    Ensuite : -Analyze -ReportPath \\srv\banc\rapports
.NOTES
    -SourcePath (facultatif) désigne un autre Pesto-Names.ps1, par exemple pour vérifier que le banc détecte une
    régression volontaire. Codes de sortie : 0 = action faite, 1 = refus, 2 = course lancée mais un processus a échoué.
#>
[CmdletBinding(DefaultParameterSetName='Analyze')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Prepare')]
    [switch]$Prepare,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [switch]$Run,

    [Parameter(Mandatory=$true, ParameterSetName='Analyze')]
    [switch]$Analyze,

    # Usage interne : un processus participant lancé par -Run.
    [Parameter(Mandatory=$true, ParameterSetName='Worker')]
    [string]$WorkerSpec,

    [Parameter(Mandatory=$true, ParameterSetName='Prepare')]
    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [Parameter(ParameterSetName='Analyze')]
    [string]$Root,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [ValidatePattern('^[A-Z0-9]{1,16}$')]
    [string]$Operator,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [ValidateRange(1, 200)]
    [int]$Rounds,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [DateTime]$StartAtUtc,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [ValidateRange(500, 60000)]
    [int]$IntervalMs,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [ValidateRange(1, 8)]
    [int]$Processes,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [Parameter(Mandatory=$true, ParameterSetName='Analyze')]
    [string]$ReportPath,

    [Parameter(ParameterSetName='Prepare')]
    [Parameter(ParameterSetName='Run')]
    [string]$SourcePath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:RaceDomain = 'race-harness.invalid'
$script:RaceMarkerName = 'race-harness.json'

function Resolve-RacePath {
    param([string]$Path)
    if (-not $Path) { throw 'Chemin vide.' }
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).ProviderPath $Path }
    $full = [IO.Path]::GetFullPath($Path)
    $trimmed = $full.TrimEnd([char[]]@('\', '/'))
    if ($trimmed.Length -lt 3) { throw 'Une racine de lecteur ou de volume ne peut pas servir de dossier de course.' }
    return $trimmed
}

function Write-RaceNewFile {
    param([string]$Path, [string]$Text)
    # Création exclusive : un fichier existant n'est jamais écrasé.
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

function Read-RaceJson {
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json)
}

function Get-RaceSourcePath {
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'wad') 'Pesto-Names.ps1' }
    $full = Resolve-RacePath $Path
    if (-not [IO.File]::Exists($full)) { throw ('Source Pesto introuvable : ' + $full) }
    return $full
}

function Import-RaceWorker {
    # Uniquement l'affectation $script:PestoSharedNameWorker du fichier source : aucun démarrage de Pesto.
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

function New-RaceRequest {
    param([string]$Mode, [string]$RootPath, [string]$Owner, [string]$Name = '', [string[]]$Names = @())
    return [pscustomobject]@{ Mode = $Mode; Root = $RootPath; Domain = $script:RaceDomain; Owner = $Owner
        Station = [Environment]::MachineName; User = 'race-harness'; Context = 'race-harness'; Minutes = 5
        Name = $Name; Names = $Names; Credential = $null }
}

function Assert-RaceRoot {
    param([string]$RootPath)
    $marker = Join-Path $RootPath $script:RaceMarkerName
    if (-not [IO.File]::Exists($marker)) { throw 'Le marqueur race-harness.json est absent : exécutez -Prepare sur un dossier vide dédié au banc.' }
    if ([string](Read-RaceJson $marker).Purpose -cne 'PestoRaceHarness') { throw 'Marqueur race-harness.json invalide.' }
    $registry = Join-Path $RootPath 'pesto-coordination.json'
    if (-not [IO.File]::Exists($registry)) { throw 'Registre de course absent : exécutez -Prepare.' }
    if ([string](Read-RaceJson $registry).Domain -ine $script:RaceDomain) { throw 'Refus : ce dossier porte un registre de production (domaine réel).' }
}

function Get-RaceHostPath {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return (Join-Path $PSHOME 'powershell.exe') }
    return (Get-Process -Id $PID).Path
}

function Get-RaceSha256 {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

try {
    switch ($PSCmdlet.ParameterSetName) {
        'Prepare' {
            $rootFull = Resolve-RacePath $Root
            if ([IO.Directory]::Exists($rootFull)) {
                if (@([IO.Directory]::GetFileSystemEntries($rootFull)).Count) { throw 'Le dossier racine doit être vide pour la préparation (dossier dédié au banc).' }
            } else {
                $parent = [IO.Path]::GetDirectoryName($rootFull)
                if (-not $parent -or -not [IO.Directory]::Exists($parent)) { throw 'Le dossier parent n''existe pas : aucun partage ni arborescence créés.' }
                [void][IO.Directory]::CreateDirectory($rootFull)
            }
            $worker = Import-RaceWorker (Get-RaceSourcePath $SourcePath)
            $marker = [ordered]@{ Schema = 1; Purpose = 'PestoRaceHarness'; Domain = $script:RaceDomain; CreatedUtc = [DateTime]::UtcNow.ToString('o') }
            Write-RaceNewFile (Join-Path $rootFull $script:RaceMarkerName) ($marker | ConvertTo-Json -Compress)
            # Le registre est préparé par le worker de Pesto lui-même, pour le domaine fictif du banc.
            $prepared = & $worker (New-RaceRequest -Mode 'Prepare' -RootPath $rootFull -Owner 'prepare')
            if ([string]$prepared.State -cne 'OK') { throw 'Préparation du registre de course refusée par le worker de Pesto.' }
            Write-Host ('Harnais préparé : ' + $rootFull)
        }
        'Run' {
            $rootFull = Resolve-RacePath $Root
            Assert-RaceRoot $rootFull
            $runStartUtc = [DateTime]::UtcNow
            $source = Get-RaceSourcePath $SourcePath
            [void](Import-RaceWorker $source)
            $start = $StartAtUtc
            if ($start.Kind -eq [DateTimeKind]::Local) { $start = $start.ToUniversalTime() }
            elseif ($start.Kind -eq [DateTimeKind]::Unspecified) { $start = [DateTime]::SpecifyKind($start, [DateTimeKind]::Utc) }
            $nowUtc = [DateTime]::UtcNow
            if ($start -le $nowUtc.AddSeconds(2) -or $start -gt $nowUtc.AddHours(24)) { throw 'StartAtUtc doit être dans plus de 2 secondes et moins de 24 heures (UTC).' }
            $operatorName = $Operator.ToUpperInvariant()
            $reportDir = Resolve-RacePath $ReportPath
            if (-not [IO.Directory]::Exists($reportDir)) { [void][IO.Directory]::CreateDirectory($reportDir) }
            $reportFile = Join-Path $reportDir ('report_' + $operatorName + '.json')
            if ([IO.File]::Exists($reportFile)) { throw ('Rapport déjà présent, jamais écrasé : ' + $reportFile) }
            $hostPath = Get-RaceHostPath
            $work = Join-Path ([IO.Path]::GetTempPath()) ('PestoRace-' + [Guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($work)
            $participants = [Collections.Generic.List[object]]::new()
            $all = [Collections.Generic.List[object]]::new()
            $failed = 0
            $verifyEndUtc = $null
            try {
                for ($i = 1; $i -le $Processes; $i++) {
                    $spec = [ordered]@{ Root = $rootFull; Operator = $operatorName; Process = $i; Rounds = $Rounds
                        StartTicksUtc = $start.Ticks; IntervalMs = $IntervalMs; SourcePath = $source
                        OutputPath = (Join-Path $work ('result-' + $i + '.json')) }
                    $specPath = Join-Path $work ('worker-' + $i + '.json')
                    Write-RaceNewFile $specPath ($spec | ConvertTo-Json -Compress)
                    $psi = [Diagnostics.ProcessStartInfo]::new()
                    $psi.FileName = $hostPath
                    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $PSCommandPath + '" -WorkerSpec "' + $specPath + '"'
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $participants.Add([pscustomobject]@{ Index = $i; Output = $spec.OutputPath; Process = [Diagnostics.Process]::Start($psi) })
                }
                $deadline = $start.AddMilliseconds(($Rounds + 2) * $IntervalMs).AddSeconds(120)
                foreach ($participant in $participants) {
                    $wait = [int][Math]::Max(1000, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
                    $exited = $participant.Process.WaitForExit($wait)
                    if (-not $exited) { try { $participant.Process.Kill() } catch {} }
                    $records = $null
                    if ($exited -and $participant.Process.ExitCode -eq 0 -and [IO.File]::Exists($participant.Output)) {
                        $doc = Read-RaceJson $participant.Output
                        $records = @($doc.Results)
                        # Fin de vérification réelle déclarée par le processus (horloge du poste) : conservée pour
                        # diagnostiquer les décalages entre opérateurs.
                        if ($doc.PSObject.Properties['VerifyEndUtc'] -and [string]$doc.VerifyEndUtc) {
                            $candidate = if ($doc.VerifyEndUtc -is [DateTime]) { $doc.VerifyEndUtc.ToUniversalTime() } else { [DateTime]::Parse([string]$doc.VerifyEndUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
                            if (-not $verifyEndUtc -or $candidate -gt $verifyEndUtc) { $verifyEndUtc = $candidate }
                        }
                    }
                    if ($null -eq $records) {
                        # Processus sans résultat : chaque créneau compte en erreur, jamais en succès.
                        $failed++
                        $records = for ($r = 1; $r -le $Rounds; $r++) {
                            [pscustomobject]@{ Round = $r; Operator = $operatorName; Process = $participant.Index
                                Owner = ($operatorName + '-' + $participant.Index); Name = ('RACE{0:D4}' -f $r); Outcome = 'Error'
                                State = ''; DurationMs = 0; OwnerVerified = $null; Error = 'Processus participant sans résultat.'
                                SlotUtc = ''; AttemptUtc = '' }
                        }
                    }
                    foreach ($record in @($records)) { $all.Add($record) }
                    $participant.Process.Dispose()
                }
            } finally {
                try { [IO.Directory]::Delete($work, $true) } catch {}
            }
            $report = [ordered]@{ Schema = 1; Operator = $operatorName; Machine = [Environment]::MachineName; Processes = $Processes
                Rounds = $Rounds; StartAtUtc = $start.ToString('o'); IntervalMs = $IntervalMs; Root = $rootFull
                LeasePolicy = 'HoldUntilExpiry'; RunStartUtc = $runStartUtc.ToString('o')
                VerifyEndUtc = $(if ($verifyEndUtc) { $verifyEndUtc.ToString('o') } else { '' })
                SourcePath = $source; SourceSha256 = (Get-RaceSha256 $source); Host = $hostPath; Results = $all.ToArray() }
            Write-RaceNewFile $reportFile ($report | ConvertTo-Json -Depth 6)
            Write-Host ('Rapport : ' + $reportFile)
            if ($failed) { exit 2 }
        }
        'Worker' {
            $spec = Read-RaceJson $WorkerSpec
            $worker = Import-RaceWorker ([string]$spec.SourcePath)
            $rootFull = [string]$spec.Root
            Assert-RaceRoot $rootFull
            $owner = [string]$spec.Operator + '-' + [string]$spec.Process
            # Instant de départ transmis en ticks UTC : pwsh 7 convertit les dates ISO de ConvertFrom-Json, pas Windows PowerShell 5.1.
            $start = [DateTime]::new([long]$spec.StartTicksUtc, [DateTimeKind]::Utc)
            $interval = [int]$spec.IntervalMs
            $results = [Collections.Generic.List[object]]::new()
            $owned = [Collections.Generic.List[string]]::new()
            for ($r = 1; $r -le [int]$spec.Rounds; $r++) {
                $slot = $start.AddMilliseconds(($r - 1) * $interval)
                while ([DateTime]::UtcNow -lt $slot) { Start-Sleep -Milliseconds 5 }
                $name = 'RACE{0:D4}' -f $r
                # Horodatages UTC réels : créneau prévu (absolu, comparable entre postes) et instant effectif de
                # la tentative sur l'horloge locale. L'écart entre les deux, comparé d'un rapport à l'autre,
                # révèle la dérive d'horloge entre opérateurs.
                $record = [pscustomobject]@{ Round = $r; Operator = [string]$spec.Operator; Process = [int]$spec.Process; Owner = $owner
                    Name = $name; Outcome = 'Error'; State = ''; DurationMs = 0; OwnerVerified = $null; Error = ''
                    SlotUtc = $slot.ToString('o'); AttemptUtc = '' }
                if ([DateTime]::UtcNow -ge $slot.AddMilliseconds($interval)) {
                    $record.Outcome = 'Late'; $record.Error = 'Créneau manqué : aucune tentative.'
                } else {
                    $record.AttemptUtc = [DateTime]::UtcNow.ToString('o')
                    $watch = [Diagnostics.Stopwatch]::StartNew()
                    try {
                        $answer = & $worker (New-RaceRequest -Mode 'Reserve' -RootPath $rootFull -Owner $owner -Name $name)
                        $record.State = [string]$answer.State
                        switch ([string]$answer.State) {
                            'Reserved' { $record.Outcome = 'Owner'; $owned.Add($name) }
                            'Renewed' { $record.Outcome = 'Renewed'; $owned.Add($name) }
                            'Held' { $record.Outcome = 'Other' }
                            default { $record.Outcome = 'Error'; $record.Error = 'État inattendu : ' + [string]$answer.State }
                        }
                    } catch {
                        $record.Outcome = 'Error'; $record.Error = $_.Exception.Message
                    }
                    $watch.Stop()
                    $record.DurationMs = [Math]::Round($watch.Elapsed.TotalMilliseconds, 2)
                }
                $results.Add($record)
            }
            # Après le dernier créneau et un intervalle de marge, relire chaque réservation obtenue : un autre participant
            # qui l'aurait écrasée pendant qu'elle était active est une violation, même avec un seul « Owner » déclaré.
            $end = $start.AddMilliseconds(([int]$spec.Rounds + 1) * $interval)
            while ([DateTime]::UtcNow -lt $end) { Start-Sleep -Milliseconds 20 }
            foreach ($record in $results) {
                if ($record.Outcome -notin @('Owner', 'Renewed')) { continue }
                $path = Join-Path (Join-Path $rootFull 'reservations') ($record.Name + '.json')
                try { $record.OwnerVerified = ([string](Read-RaceJson $path).Owner -ceq $owner) }
                catch { $record.OwnerVerified = $false; $record.Error = 'Relecture impossible : ' + $_.Exception.Message }
            }
            $verifyEndUtc = [DateTime]::UtcNow
            # Ne pas libérer avant la fin des autres postes, dont les horloges peuvent différer.
            # Le dossier est réservé au banc ; ses baux expirent naturellement après cinq minutes.
            $released = @()
            $output = [ordered]@{ Owner = $owner; Results = $results.ToArray(); Released = $released
                VerifyScheduledUtc = $end.ToString('o'); VerifyEndUtc = $verifyEndUtc.ToString('o') }
            Write-RaceNewFile ([string]$spec.OutputPath) ($output | ConvertTo-Json -Depth 5)
        }
        'Analyze' {
            $dir = Resolve-RacePath $ReportPath
            if (-not [IO.Directory]::Exists($dir)) { throw 'Dossier de rapports introuvable.' }
            $files = @(Get-ChildItem -LiteralPath $dir -Filter 'report_*.json' -File | Where-Object { $_.Extension -eq '.json' })
            if (-not $files.Count) { throw 'Aucun rapport trouvé.' }
            $records = [Collections.Generic.List[object]]::new()
            $operators = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $perRound = 0
            foreach ($file in $files) {
                $doc = Read-RaceJson $file.FullName
                if (-not $doc.PSObject.Properties['Schema'] -or [int]$doc.Schema -ne 1 -or -not $doc.PSObject.Properties['Results']) { throw ('Rapport illisible : ' + $file.Name) }
                if (-not $operators.Add([string]$doc.Operator)) { throw ('Opérateur présent dans deux rapports : ' + [string]$doc.Operator) }
                $perRound += [int]$doc.Processes
                foreach ($record in @($doc.Results)) { $records.Add($record) }
            }
            $violations = 0; $incomplete = 0
            $groups = @($records | Group-Object -Property Round)
            foreach ($group in $groups) {
                $holders = @($group.Group | Where-Object { $_.Outcome -in @('Owner', 'Renewed') })
                $overwritten = @($holders | Where-Object { $_.OwnerVerified -ne $true })
                $problems = @($group.Group | Where-Object { $_.Outcome -in @('Error', 'Late') })
                if ($holders.Count -gt 1 -or $overwritten.Count) { $violations++ }
                elseif ($holders.Count -eq 0 -or $problems.Count -or @($group.Group).Count -ne $perRound) { $incomplete++ }
            }
            $verdict = 'INCOMPLETE'
            if ($violations -gt 0) { $verdict = 'VIOLATION' }
            elseif ($incomplete -eq 0 -and $groups.Count -gt 0) { $verdict = 'ONE_OWNER_PER_ROUND' }
            [pscustomobject][ordered]@{ Verdict = $verdict; TotalRounds = $groups.Count; Violations = $violations
                Incomplete = $incomplete; Reports = $files.Count; ParticipantsPerRound = $perRound }
        }
    }
} catch {
    [Console]::Error.WriteLine('Banc de course refusé : ' + $_.Exception.Message)
    exit 1
}
exit 0
