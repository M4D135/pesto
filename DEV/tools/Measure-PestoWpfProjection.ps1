# Measure-PestoWpfProjection.ps1 - Banc de projection WPF (reprise complete contre mise a jour des seules lignes changees)
# Windows PowerShell 5.1 en STA uniquement. Fenêtre hors écran, données fictives, aucun accès AD ni Pesto.
# Les trois stratégies appliquent les mêmes changements aux mêmes lignes : FullRebind réassigne une nouvelle DataView,
# InPlace laisse la DataView notifier la grille, ObservableInPlace passe par Update-PestoGridRows, le helper réellement
# livré et branché sur le registre des interventions, relu dans les sources du moteur et jamais recopié ici.
# LayoutPasses compte les événements LayoutUpdated de la grille. Notifications, SortKept et SelectionKept ne sont
# relevés que pour ObservableInPlace : c'est la seule stratégie à lier une ObservableCollection au tableau.
[CmdletBinding()]
param(
    [int[]]$RowCounts = @(100, 1000, 10000),
    [int[]]$ChangeCounts = @(1, 10, 100),
    [ValidateRange(1, 50)]
    [int]$Iterations = 5,
    [int]$BaseSeed = 42,
    # Une seule cellule de 100 lignes, pour la recette Windows (tests/Run-WpfProjectionBenchTests.ps1).
    [switch]$Smoke,
    # Rapport JSON facultatif, créé (CreateNew) : un fichier existant n'est jamais écrasé.
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    [Console]::Error.WriteLine('Ce banc exige Windows PowerShell 5.1 (WPF).')
    exit 1
}
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    [Console]::Error.WriteLine('Le thread doit être en STA : lancez powershell.exe -STA.')
    exit 1
}

. (Join-Path $PSScriptRoot 'PestoWpfBench.Common.ps1')

# Le banc mesure le chemin livre : les helpers de mise a jour en place sont relus par analyse syntaxique dans
# les sources du moteur, comme la suite portable Run-Collections120Tests.ps1. Aucune copie locale, aucun
# chargement de module, aucune execution de Pesto.
foreach ($deliveredDefinition in @(Get-PestoBenchGridHelperDefinitions -Root (Split-Path $PSScriptRoot -Parent))) {
    . ([ScriptBlock]::Create($deliveredDefinition))
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Invoke-DispatcherIdle {
    param([System.Windows.Threading.Dispatcher]$Dispatcher)
    $Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
}

function New-BenchView {
    param([System.Data.DataTable]$Table)
    $view = New-Object System.Data.DataView($Table)
    $view.Sort = 'Name ASC'
    $view.RowFilter = "Status = 'OK' OR Status = 'WARN'"
    return ,$view
}

function Invoke-BenchCell {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('FullRebind', 'InPlace', 'ObservableInPlace')][string]$Strategy,
        [int]$RowCount,
        [bool]$Virtualization,
        [int]$ChangeCount,
        [int]$Seed,
        [int]$Iterations
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $table = New-PestoBenchData -RowCount $RowCount -Seed $Seed

    $win = New-Object System.Windows.Window
    $win.Title = 'Banc projection Pesto'
    $win.Left = -32000
    $win.Top = -32000
    $win.Width = 800
    $win.Height = 600
    $win.ShowActivated = $false
    $win.ShowInTaskbar = $false

    $grid = New-Object System.Windows.Controls.DataGrid
    $rows = $null
    if ($Strategy -eq 'ObservableInPlace') {
        # Le produit ne pré-affecte jamais ItemsSource : la premiere liaison est deja publiee par le helper
        # livre, qui y pose aussi le cache d'empreintes. Le tri est porte par la vue, comme dans le produit ;
        # le filtre, lui, s'exerce en amont dans la requete du consommateur, jamais dans la vue.
        $rows = New-PestoBenchObservableRows -Table $table
        Set-StrictMode -Off
        try { [void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId') }
        finally { Set-StrictMode -Version Latest }
        $sortDescription = New-Object System.ComponentModel.SortDescription -ArgumentList @('Name', [System.ComponentModel.ListSortDirection]::Ascending)
        $grid.Items.SortDescriptions.Add($sortDescription)
    } else {
        $grid.ItemsSource = (New-BenchView $table)
    }
    $grid.EnableRowVirtualization = $Virtualization
    $grid.AutoGenerateColumns = $false
    foreach ($column in @('Name', 'Site', 'Status')) {
        $textColumn = New-Object System.Windows.Controls.DataGridTextColumn
        $textColumn.Header = $column
        $textColumn.Binding = New-Object System.Windows.Data.Binding($column)
        $grid.Columns.Add($textColumn)
    }
    $win.Content = $grid
    $win.Show()
    try {
        $dispatcher = $win.Dispatcher
        Invoke-DispatcherIdle -Dispatcher $dispatcher
        $statuses = @('OK', 'KO', 'WARN')
        for ($iter = 0; $iter -lt $Iterations; $iter++) {
            $changeIndices = @(Get-PestoBenchChanges -TotalRows $RowCount -ChangeCount $ChangeCount -Seed ($Seed + $iter + 1))
            # UIElement.LayoutUpdated est un simple événement CLR, sans champ d'événement routé : add_/remove_.
            # Le compteur est un [ref] capturé par GetNewClosure : un $c++ dans le gestionnaire modifierait une copie locale.
            $notifications = [ref]0
            $collection = $null
            $notifyHandler = $null
            $sortBefore = $null
            $selectedId = $null
            if ($Strategy -eq 'ObservableInPlace') {
                # Seule la strategie livree lie une ObservableCollection : les notifications publiees, le tri
                # porte par la vue et la selection n'ont de sens que pour elle. La selection est placee avant
                # le comptage des passes de mise en page, sinon cette strategie serait penalisee d'office.
                $collection = $grid.ItemsSource
                $notifyHandler = [System.Collections.Specialized.NotifyCollectionChangedEventHandler]{ param($src, $evt) $notifications.Value++ }.GetNewClosure()
                $collection.add_CollectionChanged($notifyHandler)
                $sortBefore = @(foreach ($entry in $grid.Items.SortDescriptions) { [string]$entry.PropertyName + '|' + [string]$entry.Direction })
                $grid.SelectedItem = $collection[0]
                $selectedId = [string]$collection[0].RowId
            }
            $count = [ref]0
            $handler = [System.EventHandler]{ param($src, $evt) $count.Value++ }.GetNewClosure()
            $grid.add_LayoutUpdated($handler)
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                if ($Strategy -eq 'ObservableInPlace') {
                    # Le consommateur livre reprojetait deja ses lignes : une ligne touchée devient une instance
                    # neuve, les autres gardent l'instance rendue, exactement comme Get-PestoInterventionQuery
                    # rend les recus qu'il n'a pas relus.
                    foreach ($idx in $changeIndices) {
                        $rows[$idx] = New-PestoBenchObservableRow -RowId $rows[$idx].RowId -Name $rows[$idx].Name `
                            -Site $rows[$idx].Site -Status $statuses[($iter + $idx) % $statuses.Count] -Updated ([datetime]::Now)
                    }
                    # Le produit tourne avec Set-StrictMode -Off (wad/Invoke-Pesto.ps1) : le helper livre doit etre
                    # exerce dans le meme etat, la propriete facultative PestoRowFingerprints en depend.
                    Set-StrictMode -Off
                    try { [void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId') }
                    finally { Set-StrictMode -Version Latest }
                } else {
                    foreach ($idx in $changeIndices) {
                        $row = $table.Rows[$idx]
                        $row['Status'] = $statuses[($iter + $idx) % $statuses.Count]
                        $row['Updated'] = [datetime]::Now
                    }
                    if ($Strategy -eq 'FullRebind') { $grid.ItemsSource = (New-BenchView $table) }
                }
                Invoke-DispatcherIdle -Dispatcher $dispatcher
                $watch.Stop()
            } finally {
                $grid.remove_LayoutUpdated($handler)
                if ($null -ne $notifyHandler) { $collection.remove_CollectionChanged($notifyHandler) }
            }
            $sortKept = $null
            $selectionKept = $null
            if ($Strategy -eq 'ObservableInPlace') {
                $sortAfter = @(foreach ($entry in $grid.Items.SortDescriptions) { [string]$entry.PropertyName + '|' + [string]$entry.Direction })
                $sortKept = (($sortBefore -join ';') -ceq ($sortAfter -join ';'))
                $selectionKept = ($null -ne $grid.SelectedItem -and [string]$grid.SelectedItem.RowId -ceq $selectedId)
            }
            $results.Add([PSCustomObject]@{
                Iteration = $iter
                ElapsedMs = [Math]::Round($watch.Elapsed.TotalMilliseconds, 3)
                LayoutPasses = $count.Value
                Notifications = $notifications.Value
                SortKept = $sortKept
                SelectionKept = $selectionKept
            })
        }
    } finally {
        $win.Close()
    }
    return $results.ToArray()
}

if ($Smoke) {
    $RowCounts = @(100); $ChangeCounts = @(10); $Iterations = 2
    $virtualizationValues = @($true)
} else {
    $virtualizationValues = @($true, $false)
}
$strategies = @('FullRebind', 'InPlace', 'ObservableInPlace')
$report = [System.Collections.Generic.List[object]]::new()

foreach ($rowCount in $RowCounts) {
    foreach ($virtual in $virtualizationValues) {
        foreach ($changeCount in $ChangeCounts) {
            foreach ($strategy in $strategies) {
                $runs = @(Invoke-BenchCell -Strategy $strategy -RowCount $rowCount -Virtualization $virtual -ChangeCount $changeCount -Seed $BaseSeed -Iterations $Iterations)
                $stats = Get-PestoBenchStats -Samples @($runs | ForEach-Object { [double]$_.ElapsedMs })
                $report.Add([PSCustomObject][ordered]@{
                    Rows = $rowCount
                    Virtualization = $virtual
                    Changes = [Math]::Min($changeCount, $rowCount)
                    Strategy = $strategy
                    MedianMs = $stats.Median
                    P95Ms = $stats.P95
                    LayoutPasses = @($runs | ForEach-Object { $_.LayoutPasses })
                    Notifications = @($runs | ForEach-Object { $_.Notifications })
                    SortKept = $(if ($null -eq $runs[0].SortKept) { $null } else { @($runs | Where-Object { -not $_.SortKept }).Count -eq 0 })
                    SelectionKept = $(if ($null -eq $runs[0].SelectionKept) { $null } else { @($runs | Where-Object { -not $_.SelectionKept }).Count -eq 0 })
                    Samples = @($runs | ForEach-Object { $_.ElapsedMs })
                })
            }
        }
    }
}

$report | Format-Table Rows, Virtualization, Changes, Strategy, MedianMs, P95Ms, Notifications -AutoSize | Out-Host
if ($ReportPath) {
    if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path (Get-Location).ProviderPath $ReportPath }
    $json = [PSCustomObject][ordered]@{
        Schema = 1; Verdict = 'MEASURED_ONLY'; Machine = [Environment]::MachineName
        PowerShell = $PSVersionTable.PSVersion.ToString(); Iterations = $Iterations; Cells = $report.ToArray()
    } | ConvertTo-Json -Depth 5
    $stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}
$report.ToArray()
Write-Host 'Verdict : MEASURED_ONLY'
