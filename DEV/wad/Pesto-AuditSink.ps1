#requires -Version 5.1
# Projection issue du brouillon Spark, relue sur les schémas persistés du moteur.
function Invoke-PestoAuditSinkReceipt {
    param([Parameter(Mandatory=$true)]$Receipt)

    if (-not $script:PestoAuditSinkStatus) {
        $script:PestoAuditSinkStatus = [pscustomobject]@{
            LastSuccessUtc = $null
            LastFailureUtc = $null
            Failures = 0
        }
    }

    function Get-PestoReceiptValue {
        param($Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [System.Collections.IDictionary]) {
            if ($Obj.Contains($Name)) { return $Obj[$Name] }
            return $null
        }
        $prop = $Obj.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
        return $null
    }

    function ConvertTo-PestoStrictInt {
        param($Value)
        if ($Value -is [int]) { return $Value }
        if ($Value -is [long]) {
            if ($Value -lt [Int32]::MinValue -or $Value -gt [Int32]::MaxValue) { return $null }
            return [int]$Value
        }
        return $null
    }

    function Test-PestoClosedString {
        param($Value, [int]$MinLength = 1, [int]$MaxLength = 256)
        if ($Value -isnot [string]) { return $false }
        if ($Value.Length -lt $MinLength -or $Value.Length -gt $MaxLength) { return $false }
        if ($Value -match '[\x00-\x1f]') { return $false }
        return $true
    }

    function Test-PestoUtcRoundtrip {
        param($Value)
        if ($Value -isnot [string]) { return $false }
        if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$') { return $false }
        if ($Value -match '[\x00-\x1f]') { return $false }
        $dt = [DateTime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
        if (-not [DateTime]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) { return $false }
        if ($dt.Kind -ne [System.DateTimeKind]::Utc) { return $false }
        return $true
    }

    function Write-PestoAuditSinkWarn {
        param([string]$Message)
        try { [void](Write-Log -Message $Message -Level 'WARN' -Context 'AuditSink') } catch { }
    }

    function Update-PestoAuditSinkStatus {
        param([bool]$Success)
        if (-not $script:PestoAuditSinkStatus) {
            $script:PestoAuditSinkStatus = [pscustomobject]@{
                LastSuccessUtc = $null
                LastFailureUtc = $null
                Failures = 0
            }
        }
        $now = [DateTime]::UtcNow.ToString('o')
        if ($Success) {
            $script:PestoAuditSinkStatus.LastSuccessUtc = $now
        } else {
            $script:PestoAuditSinkStatus.LastFailureUtc = $now
            if ($script:PestoAuditSinkStatus.Failures -isnot [int]) {
                $script:PestoAuditSinkStatus.Failures = 0
            }
            $script:PestoAuditSinkStatus.Failures = [int][Math]::Min([int]::MaxValue, ([long]$script:PestoAuditSinkStatus.Failures + 1))
        }
    }

    $enabled = $false
    $policyValue = Get-PestoReceiptValue $script:PestoPolicy 'AuditEventLogEnabled'
    if ($policyValue -is [bool]) { $enabled = $policyValue }
    if (-not $enabled) { return }

    # Reconnaître les schémas persistés réels, sans marqueur Kind inventé.
    $schemaRaw = Get-PestoReceiptValue $Receipt 'Schema'
    $schemaInt = ConvertTo-PestoStrictInt $schemaRaw
    $plan = Get-PestoReceiptValue $Receipt 'Plan'
    $kind = $null
    if ($null -ne $plan) {
        $kind = 'Intervention'
        if ($null -ne (Get-PestoReceiptValue $Receipt 'OperatorMachineId')) { $kind = 'Direct' }
        if (($plan -isnot [System.Collections.IDictionary] -and $plan -isnot [pscustomobject]) -or
            ($kind -eq 'Direct' -and $schemaInt -ne 1) -or
            ($kind -eq 'Intervention' -and $schemaInt -notin @(2,3))) {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    } elseif ($null -ne (Get-PestoReceiptValue $Receipt 'MachineId') -and
              $null -ne (Get-PestoReceiptValue $Receipt 'BootUtc') -and
              $null -ne (Get-PestoReceiptValue $Receipt 'Domain')) {
        $kind = 'Join'
        if ($null -ne $schemaRaw -and $schemaInt -ne 1) {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    } else { return } # Réservations : aucun événement opérationnel.

    $opRaw = Get-PestoReceiptValue $Receipt 'OperationId'
    $guid = [Guid]::Empty
    if ($opRaw -isnot [string] -or -not [Guid]::TryParse($opRaw, [ref]$guid) -or $guid -eq [Guid]::Empty) {
        Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
        Update-PestoAuditSinkStatus -Success $false
        return
    }

    $stateRaw = Get-PestoReceiptValue $Receipt 'Phase'
    if (-not (Test-PestoClosedString $stateRaw 1 64) -or $stateRaw -cnotin @('Running','Failed','PendingRestart','Partial','MoveReady','Protection','Uncertain','NotStarted','Verified')) {
        Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
        Update-PestoAuditSinkStatus -Success $false
        return
    }

    $resultRaw = Get-PestoReceiptValue $Receipt 'ResultCode'
    if ($null -eq $resultRaw) {
        $resultCode = $null
        if ($kind -ne 'Join') {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    } else {
        $resultCode = ConvertTo-PestoStrictInt $resultRaw
        if ($null -eq $resultCode) {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    }

    $seqRaw = Get-PestoReceiptValue $Receipt 'Sequence'
    if ($null -eq $seqRaw) {
        $sequence = $null
        if ($kind -eq 'Intervention') {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    } else {
        $sequence = ConvertTo-PestoStrictInt $seqRaw
        if ($null -eq $sequence -or $sequence -lt 0) {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
    }

    $timeFields = switch ($kind) {
        'Direct' { @('ObservedUtc','FinishedUtc','StartedUtc') }
        'Join' { @('Utc') }
        default { @('UpdatedUtc') }
    }
    $updated = $null
    foreach ($field in $timeFields) {
        $value = Get-PestoReceiptValue $Receipt $field
        if ($null -eq $value -or ($value -is [string] -and $value.Length -eq 0)) { continue }
        if (-not (Test-PestoUtcRoundtrip $value)) {
            Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
            Update-PestoAuditSinkStatus -Success $false
            return
        }
        $updated = $value
        break
    }
    if ($null -eq $updated) {
        Write-PestoAuditSinkWarn 'Reçu opérationnel rejeté par l''audit.'
        Update-PestoAuditSinkStatus -Success $false
        return
    }

    $projection = [ordered]@{
        Schema = 1
        Product = 'Pesto'
        OperationId = $guid.ToString('N')
        Kind = $kind
        State = $stateRaw
        ResultCode = $resultCode
        Sequence = $sequence
        UpdatedUtc = $updated
    }

    try {
        $json = $projection | ConvertTo-Json -Compress
        [void](Write-EventLog -LogName 'Application' -Source 'Pesto' -EntryType 'Information' -EventId 1000 -Message $json -ErrorAction Stop)
    } catch {
        Write-PestoAuditSinkWarn 'Échec d''écriture de l''audit EventLog.'
        Update-PestoAuditSinkStatus -Success $false
        return
    }

    Update-PestoAuditSinkStatus -Success $true
}
