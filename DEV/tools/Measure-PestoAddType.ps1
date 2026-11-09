<#
.SYNOPSIS
    Inventaire des sites Add-Type de wad/ et mesure de leur compilation à froid (évaluation 63).
.DESCRIPTION
    Inventaire par l'AST de chaque .ps1 de wad/ (sauf le module généré Pesto.Engine.Runtime.ps1) : -TypeDefinition
    nommé ou positionnel (chaînes littérales et here-strings, y compris @"..."@ sans variable), -Path/-LiteralPath
    vers un .cs de wad/, -AssemblyName. Chaque source C# mesurable est compilée -Iterations fois, chaque fois dans un
    nouveau processus PowerShell du même type (powershell.exe sous Windows PowerShell 5.1, sinon le même pwsh) : le
    temps de compilation est mesuré dans l'enfant, le temps total du processus à côté. Les chargements d'assemblys
    (-AssemblyName) sont inventoriés, pas mesurés. Rien n'est modifié dans wad/.
.PARAMETER Root
    Dossier qui contient wad/ (DEV) ou DEV/wad (racine du dépôt).
.PARAMETER Iterations
    Nombre de compilations froides par site (1-10).
.PARAMETER ReportPath
    Rapport JSON créé (CreateNew) : un fichier existant n'est jamais écrasé.
.PARAMETER InventoryOnly
    Inventaire seul, sans compilation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Root,
    [ValidateRange(1,10)]
    [int]$Iterations = 3,
    [Parameter(Mandatory=$true)]
    [string]$ReportPath,
    [switch]$InventoryOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-AddTypePath {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).ProviderPath $Path }
    return [IO.Path]::GetFullPath($Path)
}

function Get-AddTypeHostPath {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return (Join-Path $PSHOME 'powershell.exe') }
    return (Get-Process -Id $PID).Path
}

function Get-AddTypeSha256 {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-AddTypeLiteral {
    # Valeur d'une chaîne sans expression imbriquée ; $null si la valeur dépend de l'exécution.
    param($Ast)
    if ($Ast -is [Management.Automation.Language.StringConstantExpressionAst]) { return $Ast.Value }
    if ($Ast -is [Management.Automation.Language.ExpandableStringExpressionAst] -and @($Ast.NestedExpressions).Count -eq 0) { return $Ast.Value }
    return $null
}

function Resolve-AddTypeParameterName {
    param([string]$Name)
    foreach ($known in @('TypeDefinition', 'MemberDefinition', 'AssemblyName', 'LiteralPath', 'Path', 'Name', 'Namespace',
        'UsingNamespace', 'Language', 'ReferencedAssemblies', 'CompilerParameters', 'OutputAssembly', 'OutputType',
        'CodeDomProvider', 'ErrorAction', 'WarningAction', 'PassThru', 'IgnoreWarnings', 'Verbose', 'Debug')) {
        if ($known -like ($Name + '*')) { return $known }
    }
    return $Name
}

function Get-AddTypeInventory {
    param([string]$WadPath)
    $switches = @('PassThru', 'IgnoreWarnings', 'Verbose', 'Debug')
    $files = @(Get-ChildItem -LiteralPath $WadPath -Filter '*.ps1' -File |
        Where-Object { $_.Extension -eq '.ps1' -and $_.Name -ne 'Pesto.Engine.Runtime.ps1' } | Sort-Object Name)
    $sites = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count) { throw ('Syntaxe invalide : ' + $file.Name) }
        $calls = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Add-Type' }, $true))
        foreach ($call in $calls) {
            $elements = @($call.CommandElements)
            $named = @{}
            $positional = [Collections.Generic.List[object]]::new()
            for ($k = 1; $k -lt $elements.Count; $k++) {
                $element = $elements[$k]
                if ($element -is [Management.Automation.Language.CommandParameterAst]) {
                    $name = Resolve-AddTypeParameterName $element.ParameterName
                    if ($element.Argument) { $named[$name] = $element.Argument }
                    elseif ($name -notin $switches -and $k + 1 -lt $elements.Count -and $elements[$k + 1] -isnot [Management.Automation.Language.CommandParameterAst]) {
                        $named[$name] = $elements[$k + 1]; $k++
                    } else { $named[$name] = $null }
                } else { $positional.Add($element) }
            }
            $kind = 'Unknown'; $valueAst = $null
            if ($named.ContainsKey('TypeDefinition')) { $kind = 'TypeDefinition'; $valueAst = $named['TypeDefinition'] }
            elseif ($named.ContainsKey('MemberDefinition')) { $kind = 'MemberDefinition'; $valueAst = $named['MemberDefinition'] }
            elseif ($named.ContainsKey('AssemblyName')) { $kind = 'AssemblyName'; $valueAst = $named['AssemblyName'] }
            elseif ($named.ContainsKey('LiteralPath')) { $kind = 'Path'; $valueAst = $named['LiteralPath'] }
            elseif ($named.ContainsKey('Path')) { $kind = 'Path'; $valueAst = $named['Path'] }
            elseif ($positional.Count) { $kind = 'TypeDefinition'; $valueAst = $positional[0] }

            $function = $call.Parent
            while ($function -and $function -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $function = $function.Parent }
            $context = 'top-level, au chargement du fichier'
            if ($function) { $context = 'à la demande, fonction ' + $function.Name }

            $source = $null; $sourcePath = ''; $sha = ''; $status = 'NOT_MEASURED'; $detail = ''
            switch ($kind) {
                'TypeDefinition' {
                    $source = Get-AddTypeLiteral $valueAst
                    if ($null -eq $source) { $status = 'NON_LITERAL'; $detail = 'Source C# calculée à l''exécution.' }
                    else { $sha = Get-AddTypeSha256 ([Text.UTF8Encoding]::new($false).GetBytes($source)); $status = 'PENDING' }
                }
                'MemberDefinition' { $detail = 'MemberDefinition : non mesuré (enveloppe générée par Add-Type).' }
                'AssemblyName' { $detail = 'Chargement d''assembly : inventorié, non compilé.' }
                'Path' {
                    $names = @($valueAst.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '\.cs$' }, $true) |
                        ForEach-Object { $_.Value })
                    if ($names.Count -eq 1) {
                        $candidate = Join-Path $WadPath ([IO.Path]::GetFileName($names[0]))
                        if ([IO.File]::Exists($candidate)) {
                            $sourcePath = $candidate; $sha = Get-AddTypeSha256 ([IO.File]::ReadAllBytes($candidate)); $status = 'PENDING'
                        } else { $status = 'SOURCE_MISSING'; $detail = 'Fichier .cs absent de wad/ : ' + $names[0] }
                    } else { $status = 'NON_LITERAL'; $detail = 'Chemin de source non résolu statiquement.' }
                }
                default { $detail = 'Forme d''appel Add-Type non reconnue.' }
            }
            $sites.Add([pscustomobject][ordered]@{
                File = $file.Name; Line = $call.Extent.StartLineNumber; Kind = $kind; Context = $context
                Source = $source; SourcePath = $sourcePath; SHA256 = $sha; Status = $status; Detail = $detail
                AverageCompileMs = $null; AverageProcessMs = $null; Failures = 0; Measurements = @()
            })
        }
    }
    return $sites.ToArray()
}

function Measure-AddTypeCold {
    param($Site, [int]$Count, [string]$HostPath, [string]$WorkDir)
    $runs = [Collections.Generic.List[object]]::new()
    $csPath = $Site.SourcePath
    if (-not $csPath) {
        $csPath = Join-Path $WorkDir ('site-' + [Guid]::NewGuid().ToString('N') + '.cs')
        [IO.File]::WriteAllText($csPath, $Site.Source, [Text.UTF8Encoding]::new($false))
    }
    $script = Join-Path $WorkDir ('mesure-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $body = '$ErrorActionPreference=''Stop''' + "`r`n" +
        '$w=[Diagnostics.Stopwatch]::StartNew()' + "`r`n" +
        'Add-Type -TypeDefinition ([IO.File]::ReadAllText(''' + $csPath.Replace("'", "''") + ''',[Text.Encoding]::UTF8))' + "`r`n" +
        '$w.Stop();[Console]::Out.WriteLine(''PESTO_ADDTYPE_MS=''+$w.Elapsed.TotalMilliseconds.ToString([Globalization.CultureInfo]::InvariantCulture))' + "`r`n"
    [IO.File]::WriteAllText($script, $body, [Text.UTF8Encoding]::new($true))
    for ($i = 1; $i -le $Count; $i++) {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $HostPath
        $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $script + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $process = [Diagnostics.Process]::Start($psi)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(120000)) { try { $process.Kill() } catch {}; [void]$process.WaitForExit(5000) }
            $watch.Stop()
            $compile = $null
            $match = [regex]::Match([string]$stdout.Result, 'PESTO_ADDTYPE_MS=([0-9.]+)')
            if ($match.Success) { $compile = [Math]::Round([double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture), 2) }
            $ok = ($process.HasExited -and $process.ExitCode -eq 0 -and $null -ne $compile)
            $errorText = ''
            if (-not $ok) { $errorText = ([string]$stderr.Result).Trim(); if ($errorText.Length -gt 400) { $errorText = $errorText.Substring(0, 400) } }
            $runs.Add([pscustomobject]@{ Iteration = $i; Status = $(if ($ok) { 'OK' } else { 'COMPILE_FAILED' }); CompileMs = $compile
                ProcessMs = [Math]::Round($watch.Elapsed.TotalMilliseconds, 2); Error = $errorText })
        } finally { $process.Dispose() }
    }
    $okRuns = @($runs | Where-Object { $_.Status -eq 'OK' })
    $Site.Measurements = $runs.ToArray()
    $Site.Failures = @($runs | Where-Object { $_.Status -ne 'OK' }).Count
    if ($okRuns.Count) {
        $Site.AverageCompileMs = [Math]::Round((@($okRuns | ForEach-Object { [double]$_.CompileMs }) | Measure-Object -Average).Average, 2)
        $Site.AverageProcessMs = [Math]::Round((@($okRuns | ForEach-Object { [double]$_.ProcessMs }) | Measure-Object -Average).Average, 2)
    }
    if ($Site.Failures -eq 0) { $Site.Status = 'OK' } elseif ($okRuns.Count) { $Site.Status = 'PARTIAL_FAIL' } else { $Site.Status = 'COMPILE_FAILED' }
}

$rootFull = Resolve-AddTypePath $Root
$wadPath = Join-Path $rootFull 'wad'
if (-not [IO.Directory]::Exists($wadPath)) { $wadPath = Join-Path (Join-Path $rootFull 'DEV') 'wad' }
if (-not [IO.Directory]::Exists($wadPath)) { throw ('Dossier wad introuvable sous ' + $rootFull) }
$ReportPath = Resolve-AddTypePath $ReportPath
if ([IO.File]::Exists($ReportPath) -or [IO.Directory]::Exists($ReportPath)) { throw 'Le rapport existe déjà : il ne sera pas écrasé.' }

Write-Host ('Inventaire des sites Add-Type dans ' + $wadPath)
$sites = @(Get-AddTypeInventory -WadPath $wadPath)
Write-Host ('Sites trouvés : ' + $sites.Count)

$hostPath = Get-AddTypeHostPath
if (-not $InventoryOnly) {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('PestoAddType-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($work)
    try {
        foreach ($site in $sites) {
            if ($site.Status -ne 'PENDING') { continue }
            Write-Host ('Mesure de ' + $site.File + ':' + $site.Line + ' ...')
            Measure-AddTypeCold -Site $site -Count $Iterations -HostPath $hostPath -WorkDir $work
        }
    } finally { try { [IO.Directory]::Delete($work, $true) } catch {} }
} else {
    foreach ($site in $sites) { if ($site.Status -eq 'PENDING') { $site.Status = 'NOT_MEASURED' } }
}

$startupSum = 0.0
foreach ($site in $sites) {
    if ($site.Context -like 'top-level*' -and $site.Status -eq 'OK') { $startupSum += [double]$site.AverageCompileMs }
}
$verdict = 'MEASURED_ONLY'
if ($InventoryOnly) { $verdict = 'INVENTORY_ONLY' }
$report = [pscustomobject][ordered]@{
    Schema = 1
    Timestamp = [DateTime]::UtcNow.ToString('o')
    Machine = [Environment]::MachineName
    PowerShell = ($PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion.ToString())
    Host = $hostPath
    WadPath = $wadPath
    Iterations = $Iterations
    Verdict = $verdict
    StartupColdCompileSumMs = [Math]::Round($startupSum, 2)
    Sites = @($sites | ForEach-Object {
        [pscustomobject][ordered]@{ File = $_.File; Line = $_.Line; Kind = $_.Kind; Context = $_.Context; SourcePath = $_.SourcePath
            SHA256 = $_.SHA256; Status = $_.Status; Detail = $_.Detail; AverageCompileMs = $_.AverageCompileMs
            AverageProcessMs = $_.AverageProcessMs; Failures = $_.Failures; Measurements = @($_.Measurements) } })
}
$json = $report | ConvertTo-Json -Depth 6
$stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Host ('Rapport écrit : ' + $ReportPath)
Write-Host ('Compilation froide cumulée des sites chargés au démarrage : ' + $report.StartupColdCompileSumMs + ' ms')
