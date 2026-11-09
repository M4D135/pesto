#requires -version 5.1
<#
.SYNOPSIS
    Courbe de charge en lecture AD (évaluation 7), bornée et sur demande explicite.
.DESCRIPTION
    Sans -Execute : plan seulement, aucune lecture d'annuaire (seule la découverte Windows du contrôleur).
    Avec -Execute : lectures Get-ADComputer / Get-ADOrganizationalUnit seulement, sur le contrôleur découvert par
    Windows pour le domaine de CONF[0].Domaine (sans forcer le PDC, décision du 08/10), cadence >= 50 ms, 1000 requêtes
    au plus, arrêt anticipé au-delà de 20 % d'erreurs. Aucune écriture AD, aucune configuration Pesto modifiée.
    Le rapport JSON est créé (CreateNew) : un fichier existant n'est jamais écrasé.
.PARAMETER ConfigPath
    cfg.json de Pesto : CONF[0].Domaine et CONF[0].OUScanNoms (DN de l'OU des postes).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,
    [Parameter(Mandatory=$true)]
    [int[]]$Concurrency,
    [Parameter(Mandatory=$true)]
    [int]$RequestsPerLevel,
    [Parameter(Mandatory=$true)]
    [int]$PaceMs,
    [Parameter(Mandatory=$true)]
    [string]$ReportPath,
    [switch]$Execute,
    [System.Management.Automation.PSCredential]$Credential
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# --- Validation des paramètres (avant toute lecture) ---
foreach ($level in $Concurrency) {
    if ($level -lt 1 -or $level -gt 8) { throw 'Chaque niveau de Concurrency doit être entre 1 et 8.' }
}
if ($RequestsPerLevel -lt 1 -or $RequestsPerLevel -gt 200) { throw 'RequestsPerLevel doit être entre 1 et 200.' }
if ($PaceMs -lt 50) { throw 'PaceMs doit être >= 50.' }
$totalRequests = @($Concurrency).Count * $RequestsPerLevel
if ($totalRequests -gt 1000) { throw ('Total des requêtes (' + $totalRequests + ') au-delà du plafond de 1000.') }
if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path (Get-Location).ProviderPath $ReportPath }
if ([IO.File]::Exists($ReportPath) -or [IO.Directory]::Exists($ReportPath)) { throw 'Le rapport existe déjà : il ne sera pas écrasé.' }

# --- Configuration Pesto (lecture seule) ---
$configItem = Get-Item -LiteralPath $ConfigPath -ErrorAction Stop
if ($configItem.PSIsContainer -or $configItem.Length -gt 1MB) { throw 'Configuration absente ou supérieure à 1 Mio.' }
$cfg = [IO.File]::ReadAllText($configItem.FullName, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
if (-not $cfg.PSObject.Properties['CONF'] -or -not @($cfg.CONF).Count) { throw 'CONF absent de la configuration.' }
$conf = @($cfg.CONF)[0]
$domain = ''
if ($conf.PSObject.Properties['Domaine']) { $domain = ([string]$conf.Domaine).Trim().TrimEnd('.') }
if (-not $domain -or $domain -notmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { throw 'CONF[0].Domaine absent ou invalide.' }
$rootOU = (@($domain.Split('.')) | ForEach-Object { 'DC=' + $_ }) -join ','
$scanBase = ''
if ($conf.PSObject.Properties['OUScanNoms']) { $scanBase = ([string]$conf.OUScanNoms).Trim() }
$scanNote = 'CONF[0].OUScanNoms'
if (-not $scanBase) { $scanBase = $rootOU; $scanNote = 'racine du domaine (OUScanNoms absent)' }
if ($scanBase -notmatch '(?i)(^|,)DC=') { throw 'CONF[0].OUScanNoms doit être un DN (OU=...,DC=...).' }

# --- Module AD et contrôleur découvert par Windows (pas de PDC imposé) ---
$adCommand = Get-Command Get-ADComputer -ErrorAction SilentlyContinue
if (-not $adCommand) { Import-Module ActiveDirectory -ErrorAction Stop; $adCommand = Get-Command Get-ADComputer -ErrorAction Stop }
$adModule = $adCommand.Module
$dcObj = Get-ADDomainController -Discover -DomainName $domain -ErrorAction Stop
$dcName = [string](@($dcObj.HostName)[0])
if (-not $dcName) { throw 'Découverte Windows du contrôleur sans nom d''hôte.' }

Write-Host ('Contrôleur découvert par Windows : ' + $dcName)
Write-Host ('Domaine : ' + $domain + ' ; base de recherche : ' + $scanBase + ' (' + $scanNote + ')')
Write-Host ('Niveaux : ' + ($Concurrency -join ', ') + ' ; requêtes par niveau : ' + $RequestsPerLevel + ' ; total : ' + $totalRequests + ' ; cadence : ' + $PaceMs + ' ms')

if (-not $Execute) {
    Write-Host 'PLAN SEULEMENT : aucune lecture AD effectuée (ajoutez -Execute pour mesurer).'
    return
}

$credSplat = @{}
if ($Credential) { $credSplat['Credential'] = $Credential }

# Échantillon de noms pour la classe « Identity » : une lecture initiale bornée sous OUScanNoms.
$sampleNames = @(Get-ADComputer -SearchBase $scanBase -SearchScope Subtree -Filter * -ResultSetSize 10 -Server $dcName -ErrorAction Stop @credSplat |
    ForEach-Object { [string]$_.Name } | Where-Object { $_ })
$classes = @('Search', 'OU')
if ($sampleNames.Count) { $classes = @('Identity', 'Search', 'OU') }

$measureScript = {
    param([string]$Class, [string]$Name, [string]$Server, [string]$ScanBase, [string]$RootDN, $Credential)
    $ErrorActionPreference = 'Stop'
    $cred = @{}
    if ($Credential) { $cred['Credential'] = $Credential }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $ok = $false; $code = 0; $message = ''
    try {
        switch ($Class) {
            'Identity' { [void](Get-ADComputer -Identity $Name -Server $Server -ErrorAction Stop @cred) }
            'Search' { [void](Get-ADComputer -SearchBase $ScanBase -SearchScope OneLevel -Filter * -ResultPageSize 200 -ResultSetSize 200 -Server $Server -ErrorAction Stop @cred) }
            'OU' { [void](Get-ADOrganizationalUnit -SearchBase $RootDN -SearchScope OneLevel -Filter * -ResultSetSize 100 -Server $Server -ErrorAction Stop @cred) }
        }
        $ok = $true
    } catch {
        $code = $_.Exception.HResult; $message = $_.Exception.Message
    }
    $watch.Stop()
    [pscustomobject]@{ Class = $Class; DurationMs = [Math]::Round($watch.Elapsed.TotalMilliseconds, 2); Success = $ok; ErrorCode = $code; Error = $message }
}

# Les runspaces chargent le même module AD que ce processus (RSAT, ou doubles de test).
$iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
if ($adModule) {
    $manifest = Join-Path $adModule.ModuleBase ($adModule.Name + '.psd1')
    if ([IO.File]::Exists($manifest)) { $iss.ImportPSModule([string[]]@($manifest)) } else { $iss.ImportPSModule([string[]]@($adModule.Path)) }
}

function Get-ReadLoadPercentile {
    param([double[]]$Sorted, [double]$Percent)
    if (-not $Sorted.Count) { return $null }
    $index = [int][Math]::Ceiling(($Percent / 100) * $Sorted.Count) - 1
    return $Sorted[[Math]::Max(0, [Math]::Min($Sorted.Count - 1, $index))]
}

$levels = [Collections.Generic.List[object]]::new()
$stopped = ''
$startUtc = [DateTime]::UtcNow
foreach ($level in $Concurrency) {
    Write-Host ('Niveau de concurrence : ' + $level)
    # Le pool borne le parallélisme : pas de sémaphore à libérer, pas d'attente bloquante dans la boucle de cadence.
    $pool = [runspacefactory]::CreateRunspacePool(1, $level, $iss, $Host)
    $pool.Open()
    $handles = [Collections.Generic.List[object]]::new()
    $levelResults = [Collections.Generic.List[object]]::new()
    try {
        for ($i = 0; $i -lt $RequestsPerLevel; $i++) {
            $class = $classes[$i % $classes.Count]
            $name = ''
            if ($class -eq 'Identity') { $name = $sampleNames[$i % $sampleNames.Count] }
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($measureScript).AddArgument($class).AddArgument($name).AddArgument($dcName).AddArgument($scanBase).AddArgument($rootOU).AddArgument($Credential)
            $handles.Add([pscustomobject]@{ PS = $ps; Async = $ps.BeginInvoke() })
            Start-Sleep -Milliseconds $PaceMs
        }
        foreach ($handle in $handles) {
            try {
                foreach ($item in @($handle.PS.EndInvoke($handle.Async))) { $levelResults.Add($item) }
            } catch {
                $levelResults.Add([pscustomobject]@{ Class = 'Runspace'; DurationMs = 0; Success = $false; ErrorCode = $_.Exception.HResult; Error = $_.Exception.Message })
            } finally {
                $handle.PS.Dispose()
            }
        }
    } finally {
        $pool.Close()
        $pool.Dispose()
    }
    $successes = @($levelResults | Where-Object { $_.Success }).Count
    $errorRate = 0
    if ($levelResults.Count) { $errorRate = ($levelResults.Count - $successes) / $levelResults.Count }
    [double[]]$sorted = @($levelResults | Where-Object { $_.Success } | ForEach-Object { [double]$_.DurationMs } | Sort-Object)
    $levels.Add([pscustomobject][ordered]@{
        Level = $level; Requests = $levelResults.Count; Successes = $successes; ErrorRate = $errorRate
        P50Ms = (Get-ReadLoadPercentile $sorted 50); P95Ms = (Get-ReadLoadPercentile $sorted 95)
        MaxMs = $(if ($sorted.Count) { $sorted[$sorted.Count - 1] } else { $null })
        Results = $levelResults.ToArray()
    })
    Write-Host ('  Taux d''erreur : ' + [Math]::Round($errorRate * 100, 1) + ' %')
    if ($errorRate -gt 0.2) {
        $stopped = 'Arrêt anticipé au niveau ' + $level + ' : taux d''erreur > 20 %.'
        Write-Host ('  ' + $stopped)
        break
    }
}

$report = [pscustomobject][ordered]@{
    Schema = 1
    DC = $dcName
    DCSource = 'Get-ADDomainController -Discover -DomainName (Windows)'
    Domain = $domain
    ScanBase = $scanBase
    RootDN = $rootOU
    StartUtc = $startUtc.ToString('o')
    EndUtc = [DateTime]::UtcNow.ToString('o')
    PlannedRequests = $totalRequests
    PaceMs = $PaceMs
    Classes = $classes
    Stopped = $stopped
    Levels = $levels.ToArray()
    Verdict = 'MEASURED_ONLY'
}
$json = $report | ConvertTo-Json -Depth 6
$stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Host ('Rapport écrit : ' + $ReportPath)
