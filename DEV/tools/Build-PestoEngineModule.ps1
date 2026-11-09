#requires -Version 5.1
[CmdletBinding()]
param([string]$Root='',[switch]$Check)
if(-not $Root){$Root=Split-Path $PSScriptRoot -Parent}
$ErrorActionPreference='Stop'
$wad=Join-Path $Root 'wad'
$names=@('Core','Startup','Authentication','Integrity','Common','Contracts','Configuration','ManagedPolicy','Policy','Directory','Async','Journal','AuditSink','Operations','Safety','JoinRecovery','Recovery','Preparation','Names','Direct','Join','Inspection','Support','EngineContracts','Diagnostics','Catalogue','Automation','Enterprise','Extensions')
$functions=[ordered]@{};$workers=[ordered]@{};$inputs=@();$coreNames=[Collections.Generic.List[string]]::new()
foreach($name in $names){
    $path=Join-Path $wad ('Pesto-'+$name+'.ps1')
    if(-not(Test-Path -LiteralPath $path)){if($name -in @('Enterprise')){continue};throw ('Source moteur absente : '+$name)}
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Syntaxe moteur invalide : '+$name)}
    $inputs+=[ordered]@{File=[IO.Path]::GetFileName($path);SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    foreach($statement in $ast.EndBlock.Statements){
        if($statement -is [Management.Automation.Language.FunctionDefinitionAst]){$functions[$statement.Name]=$statement;continue}
        if($statement -isnot [Management.Automation.Language.AssignmentStatementAst]){continue}
        if($statement.Left -isnot [Management.Automation.Language.VariableExpressionAst]){continue}
        $variable=$statement.Left.VariablePath.UserPath
        if($variable -eq 'script:PestoWorkerCoreNames'){
            foreach($literal in $statement.Right.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$false)){
                if($literal.Parent -is [Management.Automation.Language.CommandAst]){continue}
                if($literal.Value -match '^[A-Za-z][A-Za-z0-9-]+$' -and -not $coreNames.Contains($literal.Value)){$coreNames.Add($literal.Value)}
            }
        }
        if($variable -in @('script:PestoDirectWorker','script:PestoQueueWorker','script:PestoPreflightWorker')){
            $block=$statement.Right.Find({param($n) $n -is [Management.Automation.Language.ScriptBlockExpressionAst]},$false)
            if(-not $block){throw ('Worker sans ScriptBlock : '+$variable)}
            $workers[$variable]=$statement.Extent.Text
        }
    }
}
foreach($required in @('script:PestoDirectWorker','script:PestoQueueWorker','script:PestoPreflightWorker')){if(-not $workers.Contains($required)){throw ('Worker absent : '+$required)}}
# Fermeture AST : les appels aux fonctions du produit sont résolus, y compris dans les blocs imbriqués.
$dependencies=[ordered]@{};$unresolved=[Collections.Generic.List[string]]::new()
foreach($entry in $functions.GetEnumerator()){
    $calls=@($entry.Value.Body.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()}|Where-Object{$_}|Sort-Object -Unique)
    $dependencies[$entry.Key]=@($calls|Where-Object{$functions.Contains($_)})
}
$bootstrap=@('Write-Log','Add-LogLine','Show-MsgError','Show-MsgWarning','Show-MsgInfo','Confirm-YesNo','Invoke-DoEvents','Wait-Pumped')
$closure=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pending=[Collections.Generic.Queue[string]]::new();foreach($name in $coreNames){$pending.Enqueue($name)}
while($pending.Count){
    $name=$pending.Dequeue();if($name -in $bootstrap){continue};if(-not $closure.Add($name)){continue}
    if(-not $functions.Contains($name)){$unresolved.Add($name);continue}
    foreach($dependency in $dependencies[$name]){if(-not $closure.Contains($dependency)){$pending.Enqueue($dependency)}}
}
if($unresolved.Count){throw ('Dépendances worker absentes : '+($unresolved -join ', '))}
# Les fonctions imbriquées sont autonomes ; aucun appel produit inconnu ne doit passer silencieusement.
foreach($name in $closure){
    $definition=$functions[$name]
    $locals=@($definition.Body.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object Name)
    foreach($call in @($definition.Body.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()})){
        if($call -match '^[A-Za-z]+-Pesto' -and -not $functions.Contains($call) -and $call -notin $locals){throw ('Appel produit non résolu dans '+$name+' : '+$call)}
    }
}
$guiMissing=@($closure|Where-Object{$_ -notin $coreNames})
if($guiMissing.Count){throw ('Compléter PestoWorkerCoreNames pour le worker GUI : '+($guiMissing -join ', '))}

$source=[Text.StringBuilder]::new();[void]$source.AppendLine('# Généré par Build-PestoEngineModule.ps1. Définitions uniquement ; ne pas éditer.')
foreach($value in $functions.Values){[void]$source.AppendLine($value.Extent.Text)}
[void]$source.AppendLine('$script:PestoWorkerCoreNames=@('+((@($closure|Sort-Object)|ForEach-Object{"'"+$_+"'"})-join ',')+')')
foreach($value in $workers.Values){[void]$source.AppendLine($value)}
$sourceText=$source.ToString().Replace("`r`n","`n").Replace("`n","`r`n")
$utf8=[Text.UTF8Encoding]::new($true);$bytes=$utf8.GetPreamble()+$utf8.GetBytes($sourceText)
$hash=[Security.Cryptography.SHA256]::Create();try{$sourceHash=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
$exports=@('Get-PestoEngineInfo','Get-PestoEngineWorkerScriptBlock','Get-PestoWorkerCoreSource','Get-PestoPreflightSource','Get-PestoDirectSupportSource','Invoke-PestoUnattendedJoin','New-PestoQueueMonitor','ConvertTo-PestoPolicy','Get-PestoExecutionContext','New-PestoEngineError','Get-PestoStateTransitions','Test-PestoStateTransition','ConvertTo-PestoSchemaMigration','Invoke-PestoReadDiagnostics','ConvertFrom-PestoNetSetupLog','Get-PestoDiagnosticActions','New-PestoInterventionCatalogCache','Get-PestoInterventionCatalogCached','Clear-PestoInterventionCatalogCache','Invoke-PestoReadCoalesced','New-PestoReadCoordinator','Save-PestoSchemaMigration')
# Une extension CLI doit déclarer ses exports explicitement, jamais wildcard.
$extension=Join-Path $wad 'Pesto.Engine.exports.json'
if(Test-Path -LiteralPath $extension){foreach($n in @(Get-Content -LiteralPath $extension -Raw|ConvertFrom-Json)){if($n -notmatch '^[A-Za-z]+-Pesto[A-Za-z0-9]+$' -or -not $functions.Contains($n)){throw 'Export CLI inconnu.'};$exports+=@($n)}}
$exports=@($exports|Sort-Object -Unique)
foreach($name in $exports){if(-not $functions.Contains($name)){throw ('Export absent : '+$name)}}
$module=@"
#requires -Version 5.1
# Généré : import sans WPF, réseau, configuration utilisateur ou mutation.
`$runtime=Join-Path `$PSScriptRoot 'Pesto.Engine.Runtime.ps1'
if((Get-FileHash -LiteralPath `$runtime -Algorithm SHA256 -ErrorAction Stop).Hash -ine '$sourceHash'){throw 'Moteur généré altéré. Reconstruire ou réinstaller le pack complet.'}
. `$runtime
Export-ModuleMember -Function @($(($exports|ForEach-Object{"'"+$_+"'"})-join ','))
"@
$manifest=@"
@{
RootModule='Pesto.Engine.psm1'
ModuleVersion='1.0.0'
GUID='aace6a4a-2e4e-43e3-a344-eefc26ea5049'
PowerShellVersion='5.1'
FunctionsToExport=@($(($exports|ForEach-Object{"'"+$_+"'"})-join ','))
CmdletsToExport=@();VariablesToExport=@();AliasesToExport=@()
}
"@
$meta=[ordered]@{Schema=1;Version='1.0';RuntimeSHA256=$sourceHash;Functions=$functions.Count;Workers=@($workers.Keys);WorkerClosure=@($closure|Sort-Object);Dependencies=$dependencies;Sources=$inputs;Exports=$exports}
$outputs=[ordered]@{'Pesto.Engine.Runtime.ps1'=$sourceText;'Pesto.Engine.psm1'=$module;'Pesto.Engine.psd1'=$manifest;'Pesto.Engine.build.json'=($meta|ConvertTo-Json -Depth 10)}
foreach($name in $outputs.Keys){
    $target=Join-Path $wad $name;$text=([string]$outputs[$name]).Replace("`r`n","`n").Replace("`n","`r`n")
    if($Check){if(-not [IO.File]::Exists($target) -or [IO.File]::ReadAllText($target) -cne $text){throw ('Moteur généré périmé : '+$name)}}
    else{[IO.File]::WriteAllText($target,$text,$utf8)}
}
[pscustomobject]@{Checked=[bool]$Check;Functions=$functions.Count;WorkerClosure=$closure.Count;RuntimeSHA256=$sourceHash}
