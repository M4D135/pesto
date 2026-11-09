# PestoWpfBench.Common.ps1 - Helpers purs pour le benchmark de projection WPF
# Windows PowerShell 5.1 uniquement. Pas de dépendance à Pesto-Core.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PestoBenchData {
    param(
        [Parameter(Mandatory=$true)][int]$RowCount,
        [Parameter(Mandatory=$true)][int]$Seed
    )
    $dt = New-Object System.Data.DataTable
    $dt.Columns.Add('Name', [string]) | Out-Null
    $dt.Columns.Add('Site', [string]) | Out-Null
    $dt.Columns.Add('Status', [string]) | Out-Null
    $dt.Columns.Add('Updated', [datetime]) | Out-Null

    $rng = New-Object System.Random($Seed)
    $sites = @('PARIS', 'LILLE', 'LYON', 'MARSEILLE')
    $statuses = @('OK', 'KO', 'WARN')

    for ($i = 0; $i -lt $RowCount; $i++) {
        $row = $dt.NewRow()
        $row['Name'] = "PC-{0:D5}" -f $i
        $row['Site'] = $sites[$rng.Next(0, $sites.Length)]
        $row['Status'] = $statuses[$rng.Next(0, $statuses.Length)]
        $row['Updated'] = [datetime]::Now.AddMinutes(-$rng.Next(0, 1000))
        $dt.Rows.Add($row)
    }
    # PowerShell énumère une DataTable en sortie de pipeline (ses lignes) : la virgule rend la table elle-même.
    return ,$dt
}

function Get-PestoBenchChanges {
    param(
        [Parameter(Mandatory=$true)][int]$TotalRows,
        [Parameter(Mandatory=$true)][int]$ChangeCount,
        [Parameter(Mandatory=$true)][int]$Seed
    )
    # Jamais plus de changements que de lignes : sinon la boucle de tirage ne se terminerait pas.
    $ChangeCount = [Math]::Max(0, [Math]::Min($ChangeCount, $TotalRows))
    $rng = New-Object System.Random($Seed)
    $indices = @()
    $seen = @{}
    while ($indices.Count -lt $ChangeCount) {
        $idx = $rng.Next(0, $TotalRows)
        if (-not $seen.ContainsKey($idx)) {
            $seen[$idx] = $true
            $indices += $idx
        }
    }
    return $indices
}

function Get-PestoBenchStats {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][double[]]$Samples
    )
    if ($Samples.Count -eq 0) { return @{ Median = 0; P95 = 0; Count = 0 } }
    $sorted = @($Samples | Sort-Object)
    $median = $sorted[[math]::Floor($sorted.Count / 2)]
    $p95Index = [math]::Ceiling($sorted.Count * 0.95) - 1
    if ($p95Index -lt 0) { $p95Index = 0 }
    if ($p95Index -ge $sorted.Count) { $p95Index = $sorted.Count - 1 }
    $p95 = $sorted[$p95Index]
    return @{ Median = $median; P95 = $p95; Count = $sorted.Count }
}

function Get-PestoBenchGridHelperDefinitions {
    <# Le banc doit mesurer le code reellement livre, pas une copie reecrite ici : les helpers de mise a
       jour en place sont relus par analyse syntaxique dans les sources du moteur, comme la suite portable
       Run-Collections120Tests.ps1. Aucune execution de Pesto, aucun chargement de module, aucun AD. #>
    param(
        [Parameter(Mandatory=$true)][string]$Root
    )
    $wanted = [ordered]@{
        'Pesto-Collections.ps1' = @('Get-PestoGridRowId', 'New-PestoGridRowCollection', 'Update-PestoGridRows')
        'Pesto-Contracts.ps1'   = @('Get-PestoStableHash')
    }
    $definitions = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $wanted.Keys) {
        $path = Join-Path (Join-Path $Root 'wad') $file
        if (-not (Test-Path -LiteralPath $path)) { throw ('Source livree absente : ' + $path) }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw ('Source livree invalide : ' + $path) }
        foreach ($name in $wanted[$file]) {
            $definition = $null
            foreach ($statement in $ast.EndBlock.Statements) {
                if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -eq $name) {
                    $definition = $statement
                    break
                }
            }
            if ($null -eq $definition) { throw ('Helper livre absent de la source livree : ' + $name) }
            $definitions.Add($definition.Extent.Text)
        }
    }
    return $definitions.ToArray()
}

function New-PestoBenchObservableRow {
    # Ligne projetee telle que le registre des interventions la construit : RowId est l'identite stable
    # par laquelle le helper livre retrouve une ligne, et une ligne projetee a nouveau est une instance neuve.
    param(
        [string]$RowId,
        [string]$Name,
        [string]$Site,
        [string]$Status,
        [datetime]$Updated
    )
    return [PSCustomObject]@{ RowId = $RowId; Name = $Name; Site = $Site; Status = $Status; Updated = $Updated }
}

function New-PestoBenchObservableRows {
    param(
        [Parameter(Mandatory=$true)][System.Data.DataTable]$Table
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($dataRow in $Table.Rows) {
        $rows.Add((New-PestoBenchObservableRow -RowId ([string]$dataRow['Name']) -Name ([string]$dataRow['Name']) `
            -Site ([string]$dataRow['Site']) -Status ([string]$dataRow['Status']) -Updated $dataRow['Updated']))
    }
    # La virgule rend le tableau lui-meme : PowerShell énumere une collection en sortie de pipeline.
    return ,$rows.ToArray()
}
