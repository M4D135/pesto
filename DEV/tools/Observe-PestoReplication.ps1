#Requires -Version 5.1
<#
.SYNOPSIS
    Observe la réplication Active Directory d'un objet ordinateur sur une liste explicite de DCs.
.DESCRIPTION
    Outil de laboratoire en lecture seule. Ne modifie jamais la configuration de Pesto, ni l'objet, ni les DCs ;
    ne découvre aucun contrôleur et ne change pas celui de Pesto. Seules des lectures Get-AD* sont faites.
    L'objet est lu par GUID sur chaque serveur. Le verdict CONVERGED exige que chaque serveur rende exactement
    le nom et le DN attendus (-ExpectedName, -ExpectedDistinguishedName) : un serveur qui rend encore
    l'ancien nom ou l'ancienne OU est « Stale », jamais convergé.
.PARAMETER Domain
    Nom du domaine AD (consigné dans le rapport).
.PARAMETER ObjectGuid
    GUID de l'objet ordinateur à observer.
.PARAMETER Server
    Liste explicite de 1 à 8 FQDN de DCs, sans doublon.
.PARAMETER ExpectedName
    Nom attendu après l'opération (nouveau nom).
.PARAMETER ExpectedDistinguishedName
    DN attendu après l'opération (nouveau nom dans l'OU cible).
.PARAMETER IntervalSeconds
    Intervalle entre deux tours de lecture (2 à 60 s).
.PARAMETER TimeoutSeconds
    Durée maximale d'observation (1 à 3600 s).
.PARAMETER ReceiptPath
    Reçu JSON facultatif ; seul UpdatedUtc est lu, pour calculer les délais de première vue.
.PARAMETER Credential
    PSCredential facultatif, transmis aux seules lectures AD.
.PARAMETER ReportPath
    Rapport JSON créé (CreateNew) : un fichier existant n'est jamais écrasé.
.NOTES
    Codes de sortie : 0 = CONVERGED ou SINGLE_DC, 3 = INCOMPLETE (délai écoulé), 1 = refus ou erreur.
    Le contrôle « aucune cmdlet d'écriture » est statique (tests/test_spark_h12.py, AST), jamais fait à l'exécution.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [Parameter(Mandatory=$true)]
    [guid]$ObjectGuid,

    [Parameter(Mandatory=$true)]
    [ValidateCount(1, 8)]
    [string[]]$Server,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedDistinguishedName,

    [Parameter(Mandatory=$true)]
    [ValidateRange(2, 60)]
    [int]$IntervalSeconds,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds,

    [Parameter(Mandatory=$false)]
    [string]$ReceiptPath,

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory=$true)]
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Test-ObserveNotFound {
    param($Record)
    if ($Record.CategoryInfo -and $Record.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound) { return $true }
    $type = $Record.Exception.GetType()
    while ($type) {
        if ($type.FullName -eq 'Microsoft.ActiveDirectory.Management.ADObjectNotFoundException') { return $true }
        $type = $type.BaseType
    }
    return $false
}

try {
    # Validation des serveurs : FQDN explicites, sans doublon (aucune découverte, aucun NetBIOS).
    $uniqueServers = @($Server | Select-Object -Unique)
    if ($uniqueServers.Count -ne @($Server).Count) { throw 'La liste des serveurs contient des doublons.' }
    foreach ($srv in $Server) {
        if ($srv -notmatch '^[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)+$') { throw ("Le serveur '" + $srv + "' n'est pas un FQDN valide.") }
    }
    if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path (Get-Location).ProviderPath $ReportPath }
    if ([IO.File]::Exists($ReportPath) -or [IO.Directory]::Exists($ReportPath)) { throw 'Le fichier de rapport existe déjà : il ne sera pas écrasé.' }

    # Le module n'est importé que si Get-ADComputer n'est pas déjà disponible (RSAT ou doubles de test).
    if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue)) { Import-Module ActiveDirectory -ErrorAction Stop }

    $receiptUpdatedUtc = $null
    if ($ReceiptPath) {
        $receipt = [IO.File]::ReadAllText($ReceiptPath, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
        if ($receipt.PSObject.Properties['UpdatedUtc'] -and $receipt.UpdatedUtc) {
            # pwsh 7 rend déjà un DateTime (ConvertFrom-Json) ; Windows PowerShell 5.1 rend la chaîne ISO.
            if ($receipt.UpdatedUtc -is [DateTime]) { $receiptUpdatedUtc = $receipt.UpdatedUtc.ToUniversalTime() }
            else {
                $receiptUpdatedUtc = [DateTime]::Parse([string]$receipt.UpdatedUtc, [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
            }
        }
    }

    $serverData = [ordered]@{}
    foreach ($srv in $Server) {
        $serverData[$srv] = [pscustomobject]@{
            Server = $srv; Status = 'Unknown'; FirstExpectedUtc = $null; LastReadUtc = $null
            Name = $null; DN = $null; WhenChangedUtc = $null; USNChanged = $null; Metadata = $null
            Timeline = [Collections.Generic.List[object]]::new()
        }
    }

    $startUtc = [DateTime]::UtcNow
    $verdict = 'INCOMPLETE'
    Write-Host ('Observation sur ' + @($Server).Count + ' DC(s), lecture seule.')
    while ($true) {
        $allExpected = $true
        foreach ($srv in $Server) {
            $data = $serverData[$srv]
            $now = [DateTime]::UtcNow
            $data.LastReadUtc = $now.ToString('o')
            $adParams = @{
                Identity = $ObjectGuid
                Server = $srv
                Properties = @('Name', 'DistinguishedName', 'whenChanged', 'uSNChanged')
                ErrorAction = 'Stop'
            }
            if ($Credential) { $adParams['Credential'] = $Credential }
            try {
                $obj = Get-ADComputer @adParams
                $data.Name = [string]$obj.Name
                $data.DN = [string]$obj.DistinguishedName
                if ($obj.whenChanged) { $data.WhenChangedUtc = ([DateTime]$obj.whenChanged).ToUniversalTime().ToString('o') }
                $data.USNChanged = $obj.uSNChanged
                $isExpected = ($data.Name -ieq $ExpectedName -and $data.DN -ieq $ExpectedDistinguishedName)
                if ($isExpected) {
                    $data.Status = 'Expected'
                    if (-not $data.FirstExpectedUtc) { $data.FirstExpectedUtc = $now.ToString('o') }
                } else {
                    # Objet présent mais nom ou OU encore anciens : jamais compté comme convergé.
                    $data.Status = 'Stale'
                    $allExpected = $false
                }
                try {
                    $metaParams = @{ Object = $data.DN; Server = $srv; ErrorAction = 'Stop' }
                    if ($Credential) { $metaParams['Credential'] = $Credential }
                    $data.Metadata = @(Get-ADReplicationAttributeMetadata @metaParams |
                        Where-Object { $_.AttributeName -in @('name', 'cn', 'sAMAccountName', 'dNSHostName') } |
                        ForEach-Object { [pscustomobject]@{ Attribute = [string]$_.AttributeName; Version = $_.Version
                            LastOriginatingChangeUtc = $(if ($_.LastOriginatingChangeTime) { ([DateTime]$_.LastOriginatingChangeTime).ToUniversalTime().ToString('o') } else { $null }) } })
                } catch {
                    $data.Metadata = 'Unknown'
                }
            } catch {
                $allExpected = $false
                if (Test-ObserveNotFound $_) { $data.Status = 'NotFound' } else { $data.Status = ('Error: ' + $_.Exception.Message) }
            }
            $data.Timeline.Add([pscustomobject]@{ Utc = $now.ToString('o'); Status = $(if ($data.Status -like 'Error:*') { 'Error' } else { $data.Status }); Name = $data.Name; DN = $data.DN })
        }

        if ($allExpected) {
            if (@($Server).Count -eq 1) { $verdict = 'SINGLE_DC' } else { $verdict = 'CONVERGED' }
            break
        }
        $elapsed = ([DateTime]::UtcNow - $startUtc).TotalSeconds
        if ($elapsed + $IntervalSeconds -gt $TimeoutSeconds) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }

    $details = foreach ($srv in $Server) {
        $d = $serverData[$srv]
        $delay = $null
        if ($receiptUpdatedUtc -and $d.FirstExpectedUtc) {
            $delay = ([DateTime]::Parse($d.FirstExpectedUtc, [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() - $receiptUpdatedUtc).TotalSeconds
        }
        [pscustomobject]@{
            Server = $srv; Status = $d.Status; FirstExpectedUtc = $d.FirstExpectedUtc; LastReadUtc = $d.LastReadUtc
            Name = $d.Name; DN = $d.DN; WhenChangedUtc = $d.WhenChangedUtc; USNChanged = $d.USNChanged
            DelaySeconds = $delay; Metadata = $d.Metadata; Timeline = $d.Timeline.ToArray()
        }
    }
    $report = [pscustomobject][ordered]@{
        Schema = 1
        StartUtc = $startUtc.ToString('o')
        EndUtc = [DateTime]::UtcNow.ToString('o')
        Domain = $Domain
        ObjectGuid = $ObjectGuid.ToString()
        ExpectedName = $ExpectedName
        ExpectedDistinguishedName = $ExpectedDistinguishedName
        Servers = @($Server)
        Verdict = $verdict
        ReceiptUpdatedUtc = $(if ($receiptUpdatedUtc) { $receiptUpdatedUtc.ToString('o') } else { $null })
        Details = @($details)
    }
    $json = $report | ConvertTo-Json -Depth 8
    $stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }

    Write-Host ('Rapport : ' + $ReportPath)
    Write-Host ('Verdict : ' + $verdict)
    if ($verdict -eq 'INCOMPLETE') { exit 3 }
    exit 0
} catch {
    [Console]::Error.WriteLine('Observation refusée : ' + $_.Exception.Message)
    exit 1
}
