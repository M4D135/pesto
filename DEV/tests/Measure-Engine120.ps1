#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$OutputPath,[ValidateRange(1,20)][int]$Iterations=3,[ValidateSet('','AddType','Precompiled')][string]$CompiledHelpersWorker='',[switch]$CompiledHelpersOnly)
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
if(-not $CompiledHelpersWorker -and -not $OutputPath){throw 'OutputPath requis hors mode ouvrier.'}
$rows=[Collections.Generic.List[object]]::new()
function Measure-PestoPrototype {
    param([string]$Name,[int]$Volume,[string]$Temperature,[scriptblock]$Body)
    [GC]::Collect();$before=[GC]::GetTotalMemory($true);$clock=[Diagnostics.Stopwatch]::StartNew()
    $result=& $Body;$clock.Stop();$after=[GC]::GetTotalMemory($false)
    $rows.Add([pscustomobject]@{Name=$Name;Volume=$Volume;Temperature=$Temperature;Milliseconds=$clock.Elapsed.TotalMilliseconds;ManagedDeltaBytes=([long]$after-[long]$before);ResultCount=@($result).Count})
    return ,$result
}
# --- Helpers precompiles (point 63) : les deux modes de livraison des quatre helpers C#. ---
# Le mode AddType compile les quatre sources livrees a froid, site par site, ce que paierait un Add-Type
# au demarrage ; le mode Precompiled passe par le chargeur livre (Initialize-PestoRuntimeTypes : empreinte
# SHA256, identite, provenance) et charge Pesto.Runtime.dll. Les sources sont lues de la racine du depot,
# jamais recopiees ici ; la liste doit rester celle que compile tools/Build-PestoRuntimeTypes.ps1, relue a
# l execution par Run-CompiledHelpers63Tests.ps1 et epinglee par tests/test_spark_t063_native.py. Le worker
# ne charge aucun module Pesto et ne rend qu une ligne JSON : le banc, ou la suite 63, en repond.
$PestoCompiledHelperSources=@('wad/Pesto-LogWriter.cs','src/Pesto.Runtime/CompactIndex.cs','src/Pesto.Runtime/NativePipe.cs','src/Pesto.Runtime/NativeShell.cs')
$PestoCompiledHelperTypes=@('Pesto.Runtime.AsyncAuditWriter','Pesto.Inventory.CompactIndex','Pesto.NativePipe17','Pesto.NativeShell')
function Get-PestoCompiledHelperNativeSurface {
    param([type[]]$Types)
    $found=[Collections.Generic.List[string]]::new()
    foreach($type in $Types){
        foreach($method in $type.GetMethods([Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)){
            foreach($attribute in @($method.GetCustomAttributesData())){
                if($attribute.AttributeType.Name -ceq 'DllImportAttribute'){[void]$found.Add($type.FullName+'|'+[string]$attribute.ConstructorArguments[0].Value+'|'+$method.Name)}
            }
        }
    }
    return $found.ToArray()
}
function Get-PestoCompiledHelperWorkload {
    # Le meme ouvrage des deux cotes : index compact sur 2 000 noms synthetiques de 15 caracteres, lignes
    # debrayees comprises, puis journal d audit borne. Le rendu est canonise puis empreinte : deux modes qui
    # ne rendent pas la meme empreinte ne rendent pas le meme travail, et la comparaison n a plus de sens.
    param([type[]]$Types)
    $indexType=$null;$writerType=$null
    foreach($type in $Types){
        if($type.FullName -ceq 'Pesto.Inventory.CompactIndex'){$indexType=$type}
        if($type.FullName -ceq 'Pesto.Runtime.AsyncAuditWriter'){$writerType=$type}
    }
    if(-not $indexType -or -not $writerType){throw 'Ouvrage de comparaison incomplet : index compact ou ecrivain absent.'}
    $letters='ABCDEFGHIJ'
    $names=[string[]]@(for($i=1;$i -le 2000;$i++){([string]@('P','S','V')[$i%3])+'AB'+('S'+$letters[$i%10]+$letters[($i%7)])+('C'+$letters[($i%5)]+$letters[($i%3)])+$i.ToString('D6')};'  ';'court';'PABDEF0000001';'XABDEFGHI00000')
    $built=$indexType::Build($names,'^(?<Type>[PSV])(?<Prefix>[A-Z]{2})(?<Site>[A-Z]{3})(?<Service>[A-Z]{3})(?<Number>\d{6})$',15,9,6)
    $lines=[Collections.Generic.List[string]]::new()
    foreach($row in $built.Rows){[void]$lines.Add(($row.SourceIndex,$row.Name,$row.Type,$row.Prefix,$row.Site,$row.Service,$row.Number,$row.Base,$row.Series,$row.Label) -join '|')}
    foreach($key in ($built.ByBase.Keys|Sort-Object)){[void]$lines.Add('B='+$key+':'+(($built.ByBase[$key]|Sort-Object) -join ','))}
    foreach($key in ($built.BySite.Keys|Sort-Object)){[void]$lines.Add('S='+$key+':'+(($built.BySite[$key]|Sort-Object) -join ','))}
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoCompiled63-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try{
        $file=Join-Path $temp 'audit.log';[IO.File]::WriteAllText($file,'')
        $audit=[Activator]::CreateInstance($writerType,@([string]$file,[int]10000))
        for($i=0;$i -lt 200;$i++){[void]$audit.TryWrite('ligne-'+$i)}
        $flushed=$audit.Flush(3000);$closed=$audit.Close(3000)
        [void]$lines.Add('audit='+$flushed+'/'+$closed+'/'+$audit.Written+'/'+$audit.Dropped+'/'+$audit.Error)
        [void]$lines.Add('auditSha='+[BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($file)))).Replace('-','').ToLowerInvariant())
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
    return [pscustomobject]@{Rows=$built.Rows.Count;Digest=[BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).Replace('-','').ToLowerInvariant()}
}
if($CompiledHelpersWorker){
    $helperTypes=[Collections.Generic.List[type]]::new()
    $helperAssemblies=[Collections.Generic.List[object]]::new()
    $compileMilliseconds=[ordered]@{}
    $loaderVerified=$false
    $setup=[Diagnostics.Stopwatch]::StartNew()
    if($CompiledHelpersWorker -ceq 'AddType'){
        foreach($source in $PestoCompiledHelperSources){
            $sourcePath=Join-Path $root $source
            if(-not (Test-Path -LiteralPath $sourcePath)){throw ('Shipped helper source missing: '+$source)}
            $compilation=[Diagnostics.Stopwatch]::StartNew()
            $made=@(Add-Type -TypeDefinition ([IO.File]::ReadAllText($sourcePath)) -PassThru)
            $compilation.Stop()
            $compileMilliseconds[$source]=[Math]::Round($compilation.Elapsed.TotalMilliseconds,3)
            if(-not $made){throw ('Compiled helper missing: '+$source)}
            [void]$helperAssemblies.Add($made[0].Assembly)
        }
    }else{
        . (Join-Path $root 'wad/Pesto-Common.ps1')
        Initialize-PestoRuntimeTypes -Root (Join-Path $root 'wad')
        $loaderVerified=$null -ne [AppDomain]::CurrentDomain.GetData('Pesto.Runtime.Verified.v1')
        $loaded=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$_.GetName().Name -ceq 'Pesto.Runtime'})
        if($loaded.Count -ne 1){throw 'Assembly des helpers precompiles absente.'}
        [void]$helperAssemblies.Add($loaded[0])
    }
    foreach($helperName in $PestoCompiledHelperTypes){
        $found=@($helperAssemblies|ForEach-Object{$_.GetType($helperName)})|Where-Object{$null -ne $_}
        if($found.Count -ne 1){throw ('Compiled helper missing: '+$helperName)}
        [void]$helperTypes.Add($found[0])
    }
    $setup.Stop()
    $workload=Get-PestoCompiledHelperWorkload -Types $helperTypes.ToArray()
    [pscustomobject]@{Mode=$CompiledHelpersWorker;SetupMs=[Math]::Round($setup.Elapsed.TotalMilliseconds,3);Sources=$PestoCompiledHelperSources;CompileMilliseconds=$compileMilliseconds;AssemblyNames=@($helperAssemblies|ForEach-Object{$_.GetName().Name});Locations=@($helperAssemblies|ForEach-Object{$_.Location});LoaderVerified=[bool]$loaderVerified;Rows=[int]$workload.Rows;Digest=[string]$workload.Digest;Native=@(Get-PestoCompiledHelperNativeSurface -Types $helperTypes.ToArray())}|ConvertTo-Json -Compress -Depth 5
    return
}
function Measure-PestoCompiledHelpers {
    # Resultat publie de l evaluation 63, joue par le banc lui-meme (mode rapport) et par le mode evaluation
    # seule (-CompiledHelpersOnly). Les deux modes de livraison des quatre helpers C# sont joues $Samples fois
    # chacun sur le meme ouvrage : ce que couterait la compilation C# au demarrage, et ce que coute reellement
    # le chemin livre. La mesure est refusee si les enfants ne rendent pas la meme empreinte, si la surface
    # native derive de la liste a qualifier sur cible, si le cote precompile ne charge plus la DLL livree, ou
    # s il ne passe plus par le chargeur verifie. Les couts sont publies cote a cote, jamais imposes : le
    # consommateur branche de ce bloc est tests/Run-CompiledHelpers63Tests.ps1, qui relit le rapport publié.
    param([int]$Samples=3)
    $compiledExpectedNative=@('Pesto.NativeShell|shell32.dll|SetCurrentProcessExplicitAppUserModelID','Pesto.NativeShell|user32.dll|SendMessage','Pesto.NativeShell|user32.dll|DestroyIcon','Pesto.NativePipe17|kernel32.dll|GetNamedPipeClientProcessId')
    $compiledMeasures=[Collections.Generic.List[object]]::new()
    $extraRows=[Collections.Generic.List[object]]::new()
    $compiledHost=(Get-Process -Id $PID).Path
    foreach($compiledMode in @('AddType','Precompiled')){
        for($compiledSample=0;$compiledSample -lt $Samples;$compiledSample++){
            $compiledTemperature=if($compiledSample -eq 0){'Cold'}else{'Warm'}
            $compiledPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
            $compiledOutput=@(& $compiledHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -OutputPath '' -CompiledHelpersWorker $compiledMode 2>&1|ForEach-Object{[string]$_})
            $compiledExit=$LASTEXITCODE;$ErrorActionPreference=$compiledPreference
            $compiledLine=@(@($compiledOutput|Where-Object{$_ -match '^\{.*\}$'})|Select-Object -Last 1)
            if($compiledExit -ne 0 -or -not $compiledLine){throw ('Le worker des helpers precompiles a echoue ('+$compiledMode+', code '+$compiledExit+') : '+($compiledOutput -join "`n"))}
            $compiledWorker=$compiledLine|ConvertFrom-Json
            if([string]$compiledWorker.Mode -cne $compiledMode){throw ('Le worker des helpers precompiles a repondu '+$compiledWorker.Mode+' au lieu de '+$compiledMode+'.')}
            $compiledDrift=@(Compare-Object -ReferenceObject $compiledExpectedNative -DifferenceObject @($compiledWorker.Native))
            if($compiledDrift.Count){throw ('La surface native des helpers precompiles derive de la liste a qualifier sur cible ('+$compiledMode+') : '+(($compiledDrift|ForEach-Object{$_.SideIndicator+' '+$_.InputObject}) -join '; '))}
            if($compiledMode -ceq 'Precompiled'){
                if(@($compiledWorker.AssemblyNames).Count -ne 1 -or @($compiledWorker.AssemblyNames)[0] -cne 'Pesto.Runtime'){throw 'Le cote precompile ne charge pas l assembly livree Pesto.Runtime.'}
                if(@($compiledWorker.Locations)[0] -cne (Join-Path $root 'wad/Pesto.Runtime.dll')){throw 'Le cote precompile ne charge pas la DLL livree wad/Pesto.Runtime.dll.'}
                if(-not $compiledWorker.LoaderVerified){throw 'Le cote precompile ne passe plus par Initialize-PestoRuntimeTypes.'}
            }else{
                if(@($compiledWorker.AssemblyNames|Sort-Object -Unique).Count -ne 4){throw 'Le cote Add-Type ne compile pas quatre assemblies distinctes.'}
                if(@($compiledWorker.AssemblyNames|Where-Object{$_ -ceq 'Pesto.Runtime'}).Count){throw 'Le cote Add-Type reutiliserait l assembly livree.'}
                if((@($compiledWorker.Sources) -join '|') -cne ($PestoCompiledHelperSources -join '|')){throw 'Le cote Add-Type ne compile plus les quatre sources livrees.'}
            }
            [void]$compiledMeasures.Add([pscustomobject]@{Mode=$compiledMode;Temperature=$compiledTemperature;SetupMs=[Math]::Round([double]$compiledWorker.SetupMs,3);Rows=[int]$compiledWorker.Rows;Assemblies=@($compiledWorker.AssemblyNames).Count;NativeEntries=@($compiledWorker.Native).Count;Digest=[string]$compiledWorker.Digest})
            [void]$extraRows.Add([pscustomobject]@{Name=('CompiledHelpers.'+$compiledMode+'.Setup');Volume=[int]$compiledWorker.Rows;Temperature=$compiledTemperature;Milliseconds=[double]$compiledWorker.SetupMs;ManagedDeltaBytes=$null;ResultCount=1})
        }
    }
    $compiledDigests=@($compiledMeasures|ForEach-Object{$_.Digest}|Sort-Object -Unique)
    if($compiledDigests.Count -ne 1){throw ('Les deux modes de livraison ne rendent pas le meme ouvrage ('+($compiledDigests -join ',')+') : la comparaison ne prouverait rien.')}
    if(@($compiledMeasures|Where-Object{$_.Rows -ne 2000}).Count){throw 'L ouvrage des helpers precompiles ne rend plus 2 000 lignes indexees.'}
    $compiledSummary=@(foreach($group in ($compiledMeasures|Group-Object Mode)){$values=@($group.Group.SetupMs|Sort-Object);[pscustomobject]@{Mode=$group.Group[0].Mode;Samples=$values.Count;Rows=$group.Group[0].Rows;MedianMs=$values[[int][Math]::Floor($values.Count/2)];P95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)];Assemblies=$group.Group[0].Assemblies;NativeEntries=$group.Group[0].NativeEntries;Digest=$group.Group[0].Digest}})
    return [pscustomobject]@{Summary=$compiledSummary;Samples=$compiledMeasures.ToArray();Rows=$extraRows.ToArray()}
}
if($CompiledHelpersOnly){
    # Evaluation 63 seule : le bloc publie des helpers precompiles, sans le reste du banc. C est la voie
    # rejouable des chiffres publies au catalogue ; le rapport n a de valeur que parce que la suite 63 le
    # relit et en asserte la conclusion (chemin livre nettement moins couteux, a ouvrage identique).
    $compiledPair=Measure-PestoCompiledHelpers -Samples $Iterations
    $evaluation=[ordered]@{Schema=1;Section='CompiledHelpers';Utc=[DateTime]::UtcNow.ToString('o');Platform=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();CLR=[Environment]::Version.ToString();RuntimeModuleSHA256=(Get-FileHash (Join-Path $root 'wad/Pesto.Engine.Runtime.ps1')).Hash.ToLowerInvariant();
        Iterations=$Iterations;CompiledHelpers=$compiledPair.Summary;CompiledHelpersSamples=$compiledPair.Samples;
        WindowsADExecuted=$false;UIExecuted=$false;ProductionAlgorithmChanged=$false;
        Limits=@('Cout local, sous un hote non produit, de la compilation a froid des quatre sources C# livrees par Add-Type site par site contre le chargement verifie de Pesto.Runtime.dll par le chargeur livre ; les quatre entrees DllImport ne sont pas executees ici (kernel32, shell32, user32 absents d une machine Linux) et restent a qualifier sur Windows reel.','CompiledHelpers : la comparaison des couts est publiee ; la suite 63 en asserte la conclusion (le chemin livre reste au moins deux fois moins couteux) sans imposer de reglage de performance.')}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($evaluation|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $compiledPair.Summary|Format-Table -AutoSize
    return
}
# Le module n est importe qu hors mode ouvrier : l'ouvrier des helpers precompiles ne charge aucun module
# Pesto, il ne fait que compiler les sources livrees ou charger la DLL verifiee par le chargeur livre.
Import-Module (Join-Path $root 'wad/Pesto.Engine.psd1') -Force
# Prototype de benchmark uniquement, jamais référencé par le runtime distribué.
$cs=@'
using System;
using System.Collections.Generic;
public static class PestoMeasureIndex {
 public static Dictionary<string,int> Index(string[] names) {
  var d=new Dictionary<string,int>(StringComparer.OrdinalIgnoreCase);
  for(int i=0;i<names.Length;i++) d[names[i]]=i; return d;
 }
 public static string[] FullSort(string[] names,int k) {
  var copy=(string[])names.Clone();Array.Sort(copy,StringComparer.Ordinal);
  if(copy.Length>k)Array.Resize(ref copy,k);return copy;
 }
 public static string[] TopK(string[] names,int k) {
  var set=new SortedSet<string>(StringComparer.Ordinal);
  foreach(var n in names) {set.Add(n);if(set.Count>k)set.Remove(set.Max);}
  var result=new string[set.Count];set.CopyTo(result);return result;
 }
}
'@
$compile=[Diagnostics.Stopwatch]::StartNew();Add-Type -TypeDefinition $cs;$compile.Stop()
$rows.Add([pscustomobject]@{Name='AddType.Prototype';Volume=1;Temperature='Cold';Milliseconds=$compile.Elapsed.TotalMilliseconds;ManagedDeltaBytes=$null;ResultCount=1})
foreach($count in @(100,1000,10000)){
    $names=[string[]]@(for($i=$count;$i -gt 0;$i--){'P'+$i.ToString('D10')})
    for($iteration=0;$iteration -lt $Iterations;$iteration++){
        $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
        $psIndex=Measure-PestoPrototype 'Inventory.PowerShellHashtable' $count $temperature {$d=@{};for($n=0;$n -lt $names.Length;$n++){$d[$names[$n]]=$n};$d}
        $csIndex=Measure-PestoPrototype 'Inventory.CSharpDictionary' $count $temperature {[PestoMeasureIndex]::Index($names)}
        if($psIndex.Count -ne $csIndex.Count -or $psIndex[$names[0]] -ne $csIndex[$names[0]]){throw 'Prototype index non équivalent.'}
        $full=Measure-PestoPrototype 'Query.FullSort.Prototype' $count $temperature {[PestoMeasureIndex]::FullSort($names,100)}
        $top=Measure-PestoPrototype 'Query.TopK.Prototype' $count $temperature {[PestoMeasureIndex]::TopK($names,100)}
        if(($full -join '|') -cne ($top -join '|')){throw 'Prototype top-k non équivalent.'}
        foreach($latency in @(0,5)){
            [void](Measure-PestoPrototype ('Latency.Synthetic.'+$latency+'ms') $count $temperature {if($latency){[Threading.Thread]::Sleep($latency)};[PestoMeasureIndex]::Index($names)})
        }
    }
}
$iterationsRunspace=12
[void](Measure-PestoPrototype 'Runspace.Separate' $iterationsRunspace 'Cold' {for($i=0;$i -lt $iterationsRunspace;$i++){$ps=[PowerShell]::Create();try{[void]$ps.AddScript('1+1');$ps.Invoke()}finally{$ps.Dispose()}}})
$pool=[RunspaceFactory]::CreateRunspacePool(1,1);$pool.Open()
try{
    [void](Measure-PestoPrototype 'Runspace.Pool' $iterationsRunspace 'Warm' {for($i=0;$i -lt $iterationsRunspace;$i++){$ps=[PowerShell]::Create();$ps.RunspacePool=$pool;try{[void]$ps.AddScript('1+1',$true);$ps.Invoke()}finally{$ps.Dispose()}}})
    $first=[PowerShell]::Create();$first.RunspacePool=$pool;try{[void]$first.AddScript('$script:PestoSyntheticIdentity="first-session"',$true);[void]$first.Invoke()}finally{$first.Dispose()}
    $second=[PowerShell]::Create();$second.RunspacePool=$pool;try{[void]$second.AddScript('$script:PestoSyntheticIdentity',$true);$leaked=@($second.Invoke()).Count -gt 0}finally{$second.Dispose()}
}finally{$pool.Close();$pool.Dispose()}
# Registre réel validé par Read-PestoIntervention : aucune lecture de ProgramData.
$temp=Join-Path $PSScriptRoot ('.engine-measure-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
    foreach($count in @(100,1000)){
        $folder=Join-Path $temp ([string]$count);[void][IO.Directory]::CreateDirectory($folder);$last=''
        for($i=0;$i -lt $count;$i++){
            $id=[Guid]::NewGuid().ToString('N');$last=Join-Path $folder ($id+'.json')
            $receipt=@{Schema=2;OperationId=$id;Phase='PendingRestart';Entra='NotRequested';Protection='NotChanged';Rename='Confirmed';Move='NotRequested';ResultCode=20;Plan=@{Nom_du_PC=('PC'+$i);Domain='example.test';Renommer=$true;Deplacer=$false};Metadata=@{Ticket='SYNTHETIC-BENCHMARK'}}
            [IO.File]::WriteAllText($last,($receipt|ConvertTo-Json -Depth 8 -Compress))
        }
        $cache=New-PestoInterventionCatalogCache
        $cold=Measure-PestoPrototype 'Receipts.Cache.Cold' $count 'Cold' {Get-PestoInterventionCatalogCached -Root $folder -Cache $cache}
        if($cold.ValidCount -ne $count -or $cold.ParsedFiles -ne $count){throw 'Reçus synthétiques non validés.'}
        $hot=Measure-PestoPrototype 'Receipts.Cache.Hot' $count 'Warm' {Get-PestoInterventionCatalogCached -Root $folder -Cache $cache -MaximumAgeSeconds 30}
        if($hot.CacheHits -ne $count){throw 'Cache non réutilisé.'}
        [IO.File]::AppendAllText($last,' ')
        $changed=Measure-PestoPrototype 'Receipts.Cache.OneChanged' $count 'Warm' {Get-PestoInterventionCatalogCached -Root $folder -Cache $cache -MaximumAgeSeconds 30}
        if($changed.ParsedFiles -ne 1){throw 'Incrément de cache non isolé.'}
    }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}

# Point 64 : la pagination du registre est branchee sur Common.Query (Offset, Limit, tri Updated
# decroissant). Le banc compare le chemin integre au tri complet existant (tri de toutes les lignes
# correspondantes puis prise de page) sur les memes volumes, et refuse la mesure si les deux ne
# rendent pas la meme page : une mesure qui n'assure pas l'egalite des resultats ne prouverait rien.
# La fonction mesuree est relue de la source livree par analyse syntaxique, jamais recopiee ici.
$engineModule=Get-Module Pesto.Engine
& $engineModule {param($Runtime) Initialize-PestoCommon -Root $Runtime} (Join-Path $root 'wad')
$measureInterventionsTokens=$null;$measureInterventionsErrors=$null
$measureInterventionsAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Interventions.ps1'),[ref]$measureInterventionsTokens,[ref]$measureInterventionsErrors)
if($measureInterventionsErrors.Count){throw 'Source livree invalide : wad/Pesto-Interventions.ps1'}
$measureShippedQuery=$null
foreach($measureStatement in $measureInterventionsAst.EndBlock.Statements){if($measureStatement -is [Management.Automation.Language.FunctionDefinitionAst] -and $measureStatement.Name -ceq 'Get-PestoInterventionQuery'){$measureShippedQuery=$measureStatement.Extent.Text;break}}
if(-not $measureShippedQuery){throw 'Get-PestoInterventionQuery absente de la source livree : la pagination du registre ne serait plus branchee.'}
. ([scriptblock]::Create($measureShippedQuery))
function New-PestoMeasureQueryRows {
    # Jeu deterministe : deux dates inconnues, groupes de trois ex-aequo, etats varies pour le filtre.
    param([int]$Count)
    $base=[DateTimeOffset]::new(2026,10,12,10,0,0,[TimeSpan]::Zero)
    $items=[object[]]::new($Count)
    for($i=0;$i -lt $Count;$i++){
        $utc=$null
        if($i -ge 2){$utc=$base.AddMinutes([Math]::Floor(($i-2)/3))}
        $items[$i]=[pscustomobject]@{RowId='q'+$i.ToString('D6');SearchText=('PC-'+$i.ToString('D4')+' nom-'+$i);StatusCode=@('Verified','Failed','PendingRestart','Uncertain')[$i%4];Unresolved=($i%4 -ge 2);OptionalPostCheck=$false;UpdatedUtc=$utc}
    }
    return ,$items
}
function Get-PestoMeasureFullSortPage {
    # Le tri complet existant, rendu independamment de Common.Query : filtre ordinal-ignore-case,
    # tri decroissant stable par LINQ, dates inconnues en dernier, retour a la derniere page.
    param([object[]]$Rows,[string]$State='All',[int]$Offset=0,[int]$PageSize=100)
    $matched=@($Rows|Where-Object{$State -eq 'All' -or ([string]$_.StatusCode).Equals($State,[StringComparison]::OrdinalIgnoreCase)})
    $known=@($matched|Where-Object{$null -ne $_.UpdatedUtc})
    $unknown=@($matched|Where-Object{$null -eq $_.UpdatedUtc})
    $ordered=@([Linq.Enumerable]::OrderByDescending([Collections.Generic.IEnumerable[object]]$known,[Func[object,object]]{param($row)$row.UpdatedUtc}))+@($unknown)
    $effective=$Offset
    if($effective -ge $ordered.Count -and $effective -gt 0){$effective=[Math]::Max(0,([Math]::Ceiling($ordered.Count/$PageSize)-1)*$PageSize)}
    $last=[Math]::Min($ordered.Count,$effective+$PageSize)
    $items=[object[]]::new([Math]::Max(0,$last-$effective));for($i=$effective;$i -lt $last;$i++){$items[$i-$effective]=$ordered[$i]}
    [pscustomobject]@{Items=$items;MatchedCount=$ordered.Count;Offset=$effective}
}
$pagingMeasures=[Collections.Generic.List[object]]::new()
foreach($count in @(100,1000,10000)){
    $queryRows=New-PestoMeasureQueryRows $count
    foreach($iteration in 0..($Iterations-1)){
        $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
        foreach($cell in @(@{Filter='All';Label='';Matched=$count},@{Filter='Failed';Label='.Filtered';Matched=[Math]::Floor($count/4)})){
            $sampledPaging=$rows.Count
            $integrated=Measure-PestoPrototype ('Query.Paging.Integrated'+$cell.Label) $count $temperature {Get-PestoInterventionQuery -Rows $queryRows -State $cell.Filter -Offset 0 -PageSize 100}
            $baseline=Measure-PestoPrototype ('Query.FullSort.Existing'+$cell.Label) $count $temperature {Get-PestoMeasureFullSortPage -Rows $queryRows -State $cell.Filter -Offset 0 -PageSize 100}
            if(((@($integrated.Items)|ForEach-Object{$_.RowId}) -join '|') -cne ((@($baseline.Items)|ForEach-Object{$_.RowId}) -join '|')){throw ('Pagination integree et tri complet existant non equivalents a '+$count+' lignes ('+$cell.Filter+') : la page rendue a change.')}
            if($integrated.MatchedCount -ne $baseline.MatchedCount -or $integrated.MatchedCount -ne $cell.Matched){throw ('Compte de filtre divergent a '+$count+' lignes ('+$cell.Filter+') : integre '+$integrated.MatchedCount+', baseline '+$baseline.MatchedCount+', attendu '+$cell.Matched+'.')}
            [void]$pagingMeasures.Add([pscustomobject]@{Filter=$cell.Filter;Rows=$count;Temperature=$temperature;Milliseconds=[Math]::Round($rows[$sampledPaging].Milliseconds,3);BaselineMilliseconds=[Math]::Round($rows[($sampledPaging+1)].Milliseconds,3);PageItems=@($integrated.Items).Count})
        }
    }
}
$pagingSummary=@(foreach($group in ($pagingMeasures|Group-Object Filter,Rows)){$values=@($group.Group.Milliseconds|Sort-Object);$baselineValues=@($group.Group.BaselineMilliseconds|Sort-Object);[pscustomobject]@{Filter=$group.Group[0].Filter;Rows=$group.Group[0].Rows;Samples=$values.Count;PageItems=$group.Group[0].PageItems;IntegratedMedianMs=$values[[int][Math]::Floor($values.Count/2)];IntegratedP95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)];FullSortMedianMs=$baselineValues[[int][Math]::Floor($baselineValues.Count/2)];FullSortP95Ms=$baselineValues[[Math]::Max(0,[int][Math]::Ceiling($baselineValues.Count*.95)-1)]}})

# Point 59 : l'index compact C# est branche sur le parcours d'inventaire livre (Get-PestoNameInventoryIndex).
# Le banc mesure les trois chemins livres — parcours complet, index compact, table PowerShell de repli —
# sur les memes noms, et refuse la mesure si compact et table ne rendent pas le meme index : une mesure
# qui n'assure pas l'egalite des resultats ne prouverait rien. Aucune copie locale : les trois fonctions
# sont atteintes du module Engine charge, la definition C# etant portee par wad/Pesto-Directory.ps1.
$inventoryCompile=Measure-PestoPrototype 'Inventory.Compact.Compile' 1 'Cold' {& $engineModule {Test-PestoCompactNameIndex|Out-Null}}
if(-not('Pesto.Inventory.CompactIndex' -as [type])){throw 'Index compact indisponible : le parcours livre mesurerait le seul repli PowerShell.'}
$inventoryMeasures=[Collections.Generic.List[object]]::new()
foreach($count in @(1000,10000)){
    # Noms valides de la convention livree : 2 500 bases de quatre numeros, sites et services varies.
    $inventoryComputers=[pscustomobject[]]@(for($i=0;$i -lt $count;$i++){
        $g=$i-$i%4
        [pscustomobject]@{Name=('P'+$g.ToString('D6')+[string][char](65+($g%26))+[string][char](65+([int][Math]::Floor($g/26)%26))+('S'+($g%100).ToString('D2'))+(($i%4)+1).ToString('D3'))}
    })
    $probeCompact=& $engineModule {param($c) Get-PestoNameInventoryIndexCompact $c} ([pscustomobject[]]$inventoryComputers.Clone())
    $probeTable=& $engineModule {param($c) Get-PestoNameInventoryIndexTable $c} ([pscustomobject[]]$inventoryComputers.Clone())
    if($null -eq $probeCompact -or $probeCompact.ByBase.Count -ne $probeTable.ByBase.Count -or $probeCompact.BySite.Count -ne $probeTable.BySite.Count -or $probeCompact.Entries.Count -ne $probeTable.Entries.Count){throw ('Index compact et table livres non equivalents a '+$count+' noms : comptes divergents.')}
    foreach($probeBase in $probeTable.ByBase.Keys){
        if(((@($probeCompact.ByBase[$probeBase])|Sort-Object) -join ',') -cne ((@($probeTable.ByBase[$probeBase])|Sort-Object) -join ',')){throw ('Index compact et table livres non equivalents a '+$count+' noms : numeros divergents pour la base '+$probeBase+'.')}
    }
    foreach($probeSite in $probeTable.BySite.Keys){
        if(((@($probeCompact.BySite[$probeSite])|Sort-Object) -join ',') -cne ((@($probeTable.BySite[$probeSite])|Sort-Object) -join ',')){throw ('Index compact et table livres non equivalents a '+$count+' noms : services divergents pour le site '+$probeSite+'.')}
    }
    foreach($iteration in 0..($Iterations-1)){
        $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
        $sampledPath=$rows.Count
        $path=Measure-PestoPrototype 'Inventory.Shipped.Path' $count $temperature {& $engineModule {param($c) Get-PestoNameInventoryIndex $c} ([pscustomobject[]]$inventoryComputers.Clone())}
        $compact=Measure-PestoPrototype 'Inventory.Shipped.Compact' $count $temperature {& $engineModule {param($c) Get-PestoNameInventoryIndexCompact $c} ([pscustomobject[]]$inventoryComputers.Clone())}
        $table=Measure-PestoPrototype 'Inventory.Shipped.Table' $count $temperature {& $engineModule {param($c) Get-PestoNameInventoryIndexTable $c} ([pscustomobject[]]$inventoryComputers.Clone())}
        # Le parcours livre doit rendre l'index compact, pas son repli : la mesure perdrait son objet.
        if(-not($path.ByBase -is [Collections.Generic.Dictionary[string,Collections.Generic.HashSet[int]]])){throw ('Le parcours livre ne rend pas l index compact a '+$count+' noms : la table PowerShell aurait repris la main.')}
        if($path.ByBase.Count -ne $table.ByBase.Count -or $path.Entries.Count -ne $table.Entries.Count -or $compact.ByBase.Count -ne $table.ByBase.Count){throw ('Parcours, compact et table non equivalents a '+$count+' noms : la mesure compare des index de natures differentes.')}
        [void]$inventoryMeasures.Add([pscustomobject]@{Volume=$count;Temperature=$temperature;PathMilliseconds=[Math]::Round($rows[$sampledPath].Milliseconds,3);CompactMilliseconds=[Math]::Round($rows[($sampledPath+1)].Milliseconds,3);TableMilliseconds=[Math]::Round($rows[($sampledPath+2)].Milliseconds,3);Bases=$table.ByBase.Count;Entries=$table.Entries.Count})
    }
}
$inventorySummary=@(foreach($group in ($inventoryMeasures|Group-Object Volume)){$pathValues=@($group.Group.PathMilliseconds|Sort-Object);$compactValues=@($group.Group.CompactMilliseconds|Sort-Object);$tableValues=@($group.Group.TableMilliseconds|Sort-Object);[pscustomobject]@{Rows=$group.Group[0].Volume;Bases=$group.Group[0].Bases;Entries=$group.Group[0].Entries;Samples=$pathValues.Count;PathMedianMs=$pathValues[[int][Math]::Floor($pathValues.Count/2)];CompactMedianMs=$compactValues[[int][Math]::Floor($compactValues.Count/2)];TableMedianMs=$tableValues[[int][Math]::Floor($tableValues.Count/2)];PathP95Ms=$pathValues[[Math]::Max(0,[int][Math]::Ceiling($pathValues.Count*.95)-1)];TableP95Ms=$tableValues[[Math]::Max(0,[int][Math]::Ceiling($tableValues.Count*.95)-1)]}})

# Point 61 : le contrat livre est d'abord un contrat de notifications. Il est mesure ici par echantillons
# repetes (medianne, p95), ce que la suite portable ne fait pas : elle ne releve qu'un seul passage.
# Le helper mesure est relu des sources livrees par Get-PestoBenchGridHelperDefinitions, jamais reecrit
# ici, sinon ce banc repondrait d'une copie et non du code charge par le produit.
$helperDefinitions=& ([scriptblock]::Create('. ($args[0]); Get-PestoBenchGridHelperDefinitions -Root $args[1]')) (Join-Path $root 'tools/PestoWpfBench.Common.ps1') $root
foreach($helperDefinition in $helperDefinitions){. ([scriptblock]::Create($helperDefinition))}
# Le fichier commun du banc pose StrictMode Latest dans sa portee ; la propriete facultative
# PestoRowFingerprints du chemin livre exige StrictMode -Off, comme le produit (wad/Invoke-Pesto.ps1).
Set-StrictMode -Off
$script:PestoMeasureGridSource=$null
$script:PestoMeasureGridSort=[Collections.Generic.List[object]]::new()
function New-PestoMeasureGrid {
    # ItemsSource rend la collection elle-meme (operateur virgule) : sans elle le helper ne reconnait
    # plus la source observable et mesurerait le repli sur liaison complete au lieu du chemin en place.
    $grid=[pscustomobject]@{SelectedItem=$null}
    [void]($grid|Add-Member -NotePropertyName Items -NotePropertyValue ([pscustomobject]@{SortDescriptions=$script:PestoMeasureGridSort}) -Force)
    [void]($grid|Add-Member -MemberType ScriptProperty -Name ItemsSource -Value {,$script:PestoMeasureGridSource} -SecondValue {$script:PestoMeasureGridSource=$args[0];$script:PestoMeasureGridSort.Clear()} -Force)
    return $grid
}
function New-PestoMeasureRow {param([int]$Index)
    [pscustomobject]@{RowId=('r'+$Index.ToString('D6'));StatusLabel='En cours';Receipt=[pscustomobject]@{Phase='Running';Tasks=@([pscustomobject]@{Phase='Pending'})}}
}
function New-PestoMeasureRows {param([int]$Count)
    $items=[object[]]::new($Count);for($i=0;$i -lt $Count;$i++){$items[$i]=New-PestoMeasureRow $i}
    return ,$items
}
function New-PestoMeasureProjection {param([object[]]$Rendered,[int]$Changed,[switch]$Fresh)
    # Les deux consommateurs branches n'ont pas le meme profil : le registre rend les instances deja
    # affichees, la page de noms en fabrique de neuves a chaque calcul, et le cout n'est pas le meme.
    $next=[object[]]::new($Rendered.Count)
    for($i=0;$i -lt $Rendered.Count;$i++){$next[$i]=$Rendered[$i]}
    $stride=[Math]::Max(1,[int]($Rendered.Count/[Math]::Max(1,$Changed)))
    for($k=0;$k -lt $Changed;$k++){
        $index=($k*$stride)%$Rendered.Count;$row=$Rendered[$index]
        $next[$index]=[pscustomobject]@{RowId=$row.RowId;StatusLabel=$row.StatusLabel+'.';Receipt=[pscustomobject]@{Phase=$row.Receipt.Phase;Tasks=$row.Receipt.Tasks}}
    }
    if($Fresh){for($i=0;$i -lt $Rendered.Count;$i++){if([object]::ReferenceEquals($next[$i],$Rendered[$i])){$next[$i]=New-PestoMeasureRow ([int]$Rendered[$i].RowId.Substring(1))}}}
    return ,$next
}
$gridMeasures=[Collections.Generic.List[object]]::new()
foreach($volume in @(1000,4000)){
    foreach($changed in @(1,100)){
        foreach($profile in @('ReusedInstances','FreshInstances')){
            $grid=New-PestoMeasureGrid
            [void](Update-PestoGridRows -Grid $grid -Rows (New-PestoMeasureRows $volume) -IdProperty 'RowId')
            foreach($iteration in 0..($Iterations-1)){
                $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
                $next=New-PestoMeasureProjection -Rendered @($grid.ItemsSource) -Changed $changed -Fresh:($profile -ceq 'FreshInstances')
                $sampled=$rows.Count
                $update=Measure-PestoPrototype ('GridRowUpdate.InPlace.'+$profile) $volume $temperature {Update-PestoGridRows -Grid $grid -Rows $next -IdProperty 'RowId'}
                # Une mesure qui ne tient pas le contrat ne mesure rien : le repli sur liaison complete
                # couterait moins cher a chronometrer et rendrait un chiffre sans valeur.
                if($update.Rebound -or $update.Replaced -ne $changed){throw ('Chemin en place non tenu a '+$volume+' lignes et '+$changed+' changement(s) : Rebound='+$update.Rebound+', Replaced='+$update.Replaced+'.')}
                [void]$gridMeasures.Add([pscustomobject]@{Profile=$profile;Rows=$volume;Changed=$changed;Temperature=$temperature;Milliseconds=[Math]::Round($rows[$sampled].Milliseconds,3);Notifications=$update.Replaced;Unchanged=$update.Unchanged})
            }
        }
    }
}
$gridSummary=@(foreach($group in ($gridMeasures|Group-Object Profile,Rows,Changed)){$values=@($group.Group.Milliseconds|Sort-Object);[pscustomobject]@{Profile=$group.Group[0].Profile;Rows=$group.Group[0].Rows;Changed=$group.Group[0].Changed;Samples=$values.Count;Notifications=$group.Group[0].Notifications;MedianMs=$values[[int][Math]::Floor($values.Count/2)];P95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)]}})

# Point 72 : admission et reprises des lectures transitoires bornees. La suite portable ne releve
# qu'un passage et ne chronometre rien : ce banc mesure ce qui reste invisible, a savoir le cout d une
# attente de creneau sous surcharge, le plafond d admission reellement tenu, le cout cumule du backoff
# a la borne haute de politique et le refus borne a 30 secondes. Les morceaux mesures sont relus de la
# source livree par analyse syntaxique et rejoues tels quels, jamais recopies ici : le banc repond du
# code charge par le produit. Toute divergence de contrat est une erreur de mesure, pas un resultat.
$readAdmissionTokens=$null;$readAdmissionErrors=$null
$readAdmissionAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Async.ps1'),[ref]$readAdmissionTokens,[ref]$readAdmissionErrors)
if($readAdmissionErrors.Count){throw 'Source livree invalide : wad/Pesto-Async.ps1'}
$readAdmissionStart=$null
foreach($readStatement in $readAdmissionAst.EndBlock.Statements){if($readStatement -is [Management.Automation.Language.FunctionDefinitionAst] -and $readStatement.Name -ceq 'Start-PestoAsyncOperation'){$readAdmissionStart=$readStatement;break}}
if(-not $readAdmissionStart){throw 'Start-PestoAsyncOperation absente de la source livree : plus aucune admission de lecture a mesurer.'}
$readAdmissionBlock=$null;$readWrapper=$null
foreach($readIf in $readAdmissionStart.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst]},$true)){
    if($readIf.Extent.Text.StartsWith('if(-not $mutation)')){$readAdmissionBlock=$readIf.Extent.Text}
}
foreach($readAssign in $readAdmissionStart.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
    if($readAssign.Left.Extent.Text -ceq '$wrapper'){$readWrapperText=$readAssign.Right.Extent.Text.Trim();$readWrapper=[scriptblock]::Create($readWrapperText.Substring(1,$readWrapperText.Length-2))}
}
if(-not($readAdmissionBlock -and $readWrapper)){throw 'Admission et wrapper de lecture livres introuvables : la mesure n aurait plus de cible.'}
function Get-PestoMeasureShippedFunctionText {
    param([string]$FileName,[string[]]$Names)
    $path=Join-Path (Join-Path $root 'wad') $FileName
    $tokens=$null;$parseErrors=$null
    $parsed=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw ('Source livree invalide : '+$FileName)}
    foreach($name in $Names){
        $found=$null
        foreach($statement in $parsed.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq $name){$found=$statement;break}}
        if(-not $found){throw ('Definition livree absente : '+$FileName+' :: '+$name)}
        $found.Extent.Text
    }
}
$readRetryDefinitions=@(Get-PestoMeasureShippedFunctionText -FileName 'Pesto-Contracts.ps1' -Names @('Get-PestoReadFailure','Get-PestoNativeGuidance','Invoke-PestoReadRetry'))
$readRetryDefinitions+=@(Get-PestoMeasureShippedFunctionText -FileName 'Pesto-Safety.ps1' -Names @('Get-PestoNativeFailureCode'))
function Get-PestoMeasureGatePlan {
    # Les creneaux sont fabriques par le bloc d admission livre lui-meme, dans la portee du module
    # Engine charge : c est le partage livre qui est mesure, pas une reecriture du calcul.
    param([int]$MaxReaders)
    & $engineModule {param($Text,$Policy)
        $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;MaxReaders=$Policy}}
        $script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
        $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
        $mutation=$false;$Name='Probe';$CallbackContext=$null
        . ([scriptblock]::Create($Text))
        [pscustomobject]@{Background=$script:PestoBackgroundGate;Interactive=$script:PestoInteractiveGate;Shared=[object]::ReferenceEquals($script:PestoBackgroundGate,$script:PestoInteractiveGate)}
    } $readAdmissionBlock $MaxReaders
}
function New-PestoMeasureReadWorker {
    # Le corps de lecture ne fait que se compter lui-meme : c est le creneau livre qui doit tenir la
    # concurrence, et un pic au-dessus des creneaux est une erreur de mesure, pas un chiffre.
    param([int]$WorkMilliseconds)
    'param($S);$c=[Diagnostics.Stopwatch]::StartNew();[Threading.Monitor]::Enter($S.SyncRoot);try{$S.InFlight++;$S.Runs++;if($S.InFlight -gt $S.Peak){$S.Peak=$S.InFlight}}finally{[Threading.Monitor]::Exit($S.SyncRoot)};[Threading.Thread]::Sleep('+[string]$WorkMilliseconds+');[Threading.Monitor]::Enter($S.SyncRoot);try{$S.InFlight--}finally{[Threading.Monitor]::Exit($S.SyncRoot)};''lu'''
}
$readAdmissionMeasures=[Collections.Generic.List[object]]::new()
# Vague de surcharge : trois fois plus de lectures que de creneaux, passees par le wrapper livre.
foreach($policy in @(1,4,8)){
    $slots=[Math]::Max(1,$policy-1)
    $gates=Get-PestoMeasureGatePlan $policy
    if($gates.Background.CurrentCount -ne $slots){throw ('MaxReaders='+$policy+' : '+$slots+' creneaux de fond attendus, obtenu '+$gates.Background.CurrentCount+'.')}
    if($gates.Interactive.CurrentCount -ne 1){throw ('MaxReaders='+$policy+' : un creneau interactif attendu, obtenu '+$gates.Interactive.CurrentCount+'.')}
    if($gates.Shared -ne ($policy -eq 1)){throw ('MaxReaders='+$policy+' : partage du creneau interactif attendu a '+($policy -eq 1)+', obtenu '+$gates.Shared+'.')}
    $wave=12
    $readBody=New-PestoMeasureReadWorker -WorkMilliseconds 40
    foreach($iteration in 0..($Iterations-1)){
        $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
        $sampled=$rows.Count
        $state=[hashtable]::Synchronized(@{InFlight=0;Peak=0;Runs=0})
        $timings=[Collections.Generic.List[object]]::new()
        $read=Measure-PestoPrototype ('ReadGate.Overload.'+$policy) $wave $temperature {
            $workers=@()
            foreach($n in 1..$wave){$ps=[PowerShell]::Create();$timing=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'});[void]$ps.AddScript($readWrapper.ToString(),$true).AddArgument($readBody).AddArgument(@($state)).AddArgument($gates.Background).AddArgument($timing);$workers+=@{PS=$ps;Handle=$ps.BeginInvoke();Timing=$timing}}
            $read=@(foreach($worker in $workers){$worker.PS.EndInvoke($worker.Handle)})
            foreach($worker in $workers){$worker.PS.Dispose()}
            foreach($worker in $workers){[void]$timings.Add($worker.Timing)}
            $read
        }
        if((@($read|Where-Object{$_ -eq 'lu'}).Count) -ne $wave){throw ('MaxReaders='+$policy+' : les '+$wave+' lectures attendues ne sont pas toutes passees.')}
        if($state.Peak -gt $slots){throw ('MaxReaders='+$policy+' : concurrence livree au-dessus des creneaux : '+$state.Peak+' en cours pour '+$slots+'.')}
        if($gates.Background.CurrentCount -ne $slots){throw ('MaxReaders='+$policy+' : un creneau est reste retenu apres la surcharge : '+$gates.Background.CurrentCount+' libres sur '+$slots+'.')}
        if(@($timings|Where-Object{$_.Phase -ne 'Ended'}).Count){throw ('MaxReaders='+$policy+' : le wrapper livre ne clot pas la phase de toutes ses lectures.')}
        $waits=@($timings|ForEach-Object{$_.WaitMs}|Sort-Object)
        [void]$readAdmissionMeasures.Add([pscustomobject]@{Kind='Overload';Case='MaxReaders='+$policy;Volume=$wave;Temperature=$temperature;Slots=$slots;Peak=$state.Peak;Runs=$state.Runs;WaitMedianMs=$waits[[int][Math]::Floor($waits.Count/2)];WaitMaxMs=$waits[-1];Milliseconds=[Math]::Round($rows[$sampled].Milliseconds,3)})
    }
}
# Plafond d admission : le refus doit etre immediat et ne jamais enregistrer de worker de plus.
foreach($iteration in 0..($Iterations-1)){
    $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
    $sampled=$rows.Count
    $cap=Measure-PestoPrototype 'ReadAdmission.Cap' 13 $temperature {
        & $engineModule {param($Text)
            $script:CFG=$null;$script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
            $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
            $onError={param($a);$script:AdmissionRefus=$a}
            $admitted=0;$refused=0
            foreach($n in 1..13){
                $script:AdmissionRefus=$null;$mutation=$false;$Name=('Read'+$n);$CallbackContext=$null
                . ([scriptblock]::Create($Text))
                if($null -eq $script:AdmissionRefus){$admitted++;$script:PestoAsyncTimerOperations[$Name]=[pscustomobject]@{Name=$Name;Completed=$false}}else{$refused++}
            }
            [pscustomobject]@{Admitted=$admitted;Refused=$refused;Registered=$script:PestoAsyncTimerOperations.Count}
        } $readAdmissionBlock
    }
    if($cap.Admitted -ne 12 -or $cap.Refused -ne 1 -or $cap.Registered -ne 12){throw ('Plafond d admission livre non tenu : '+$cap.Admitted+' admises, '+$cap.Refused+' refusees, '+$cap.Registered+' workers enregistres.')}
    [void]$readAdmissionMeasures.Add([pscustomobject]@{Kind='AdmissionCap';Case='13 lectures';Volume=13;Temperature=$temperature;Slots=12;Peak=$cap.Admitted;Runs=$cap.Registered;WaitMedianMs=0;WaitMaxMs=0;Milliseconds=[Math]::Round($rows[$sampled].Milliseconds,3)})
}
# Cout cumule des reprises a la borne haute de politique : tentatives et delai sont bornes par le
# contrat, le plafond de 4000 ms par sommeil doit donc rester atteint sans jamais etre depasse.
foreach($retry in @(@{Attempts=1;DelayMs=200;Bound=0},@{Attempts=2;DelayMs=200;Bound=200},@{Attempts=3;DelayMs=200;Bound=600},@{Attempts=3;DelayMs=2000;Bound=6000})){
    $sampled=$rows.Count
    $case=[string]$retry.Attempts+'x'+[string]$retry.DelayMs
    $outcome=Measure-PestoPrototype ('ReadRetry.'+$case) $retry.Attempts 'Warm' {
        & $engineModule {param($Attempts,$Delay)
            $state=@{Tries=0};$failed=$false
            try{[void](Invoke-PestoReadRetry -Attempts $Attempts -DelayMs $Delay -Read {$state.Tries++;throw [ComponentModel.Win32Exception]::new(1722)})}catch{$failed=$true}
            [pscustomobject]@{Tries=$state.Tries;Failed=$failed}
        } $retry.Attempts $retry.DelayMs
    }
    if($outcome.Tries -ne $retry.Attempts -or -not $outcome.Failed){throw ('Reprise '+$case+' hors contrat : '+$outcome.Tries+' tentatives, echec '+$outcome.Failed+'.')}
    $cost=$rows[$sampled].Milliseconds
    if($cost -lt $retry.Bound){throw ('Reprise '+$case+' moins chere que sa borne de backoff : '+[int]$cost+' ms pour '+$retry.Bound+' ms attendus.')}
    if($cost -gt ($retry.Bound+1500)){throw ('Reprise '+$case+' au-dela de la borne livree : '+[int]$cost+' ms pour '+$retry.Bound+' ms au plus.')}
    [void]$readAdmissionMeasures.Add([pscustomobject]@{Kind='Retry';Case=$case;Volume=$retry.Attempts;Temperature='Warm';Slots=1;Peak=1;Runs=$outcome.Tries;WaitMedianMs=0;WaitMaxMs=0;Milliseconds=[Math]::Round($cost,3)})
}
# Attente bornee : le creneau reste occupe, la lecture doit etre refusee a 30 secondes sans demarrer
# son worker et sans relacher un creneau quelle n a jamais pris.
$held=[Threading.SemaphoreSlim]::new(1,1)
[void]$held.Wait()
$heldTiming=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'})
$heldWorker=[PowerShell]::Create()
try{
    [void]$heldWorker.AddScript($readWrapper.ToString(),$true).AddArgument('''ne doit pas demarrer''').AddArgument(@()).AddArgument($held).AddArgument($heldTiming)
    $sampled=$rows.Count
    $refusal=Measure-PestoPrototype 'ReadGate.BoundedWait' 1 'Cold' {
        $message=''
        try{[void]$heldWorker.Invoke()}catch{$message=[string]$_.Exception.Message}
        if(-not $message){$message=[string](@($heldWorker.Streams.Error)|Select-Object -First 1)}
        $message
    }
    $cost=$rows[$sampled].Milliseconds
    if($heldTiming.Phase -ne 'Ended'){throw 'Le wrapper livre ne clot pas sa phase apres le refus borne.'}
    if($heldTiming.WorkMs -ne 0){throw ('La lecture refusee a quand meme execute son worker : '+[string]$heldTiming.WorkMs+' ms de travail.')}
    if($held.CurrentCount -ne 0){throw 'Le wrapper livre a relache un creneau quil navait pas obtenu.'}
    if($refusal -notlike '*Cr*neau de lecture indisponible apr*30 secondes*'){throw ('Refus borne attendu apres 30 secondes, obtenu ['+$refusal+']')}
    if($cost -lt 30000 -or $cost -gt 31500){throw ('Attente bornee hors contrat : '+[int]$cost+' ms pour 30 000 ms attendus.')}
    [void]$readAdmissionMeasures.Add([pscustomobject]@{Kind='BoundedWait';Case='30 s';Volume=1;Temperature='Cold';Slots=0;Peak=0;Runs=0;WaitMedianMs=$heldTiming.WaitMs;WaitMaxMs=$heldTiming.WaitMs;Milliseconds=[Math]::Round($cost,3)})
}finally{
    $heldWorker.Dispose();[void]$held.Release();$held.Dispose()
}
$readAdmissionSummary=@(foreach($group in ($readAdmissionMeasures|Group-Object Kind,Case)){$values=@($group.Group.Milliseconds|Sort-Object);$waits=@($group.Group.WaitMaxMs|Sort-Object);[pscustomobject]@{Kind=$group.Group[0].Kind;Case=$group.Group[0].Case;Volume=$group.Group[0].Volume;Samples=$values.Count;Slots=$group.Group[0].Slots;Peak=[int](($group.Group.Peak|Measure-Object -Maximum).Maximum);Runs=$group.Group[0].Runs;MedianMs=$values[[int][Math]::Floor($values.Count/2)];P95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)];MaxWaitMs=$waits[-1]}})
# --- Pool de lectures (point 56) : ouverture, emprunt, nettoyage et changement d identite, mesures separement. ---
# Le pool est branche sur Start-PestoAsyncOperation. Le contrat mesure n est pas qu il soit plus rapide : c est
# qu un seul runspace serve reellement les lectures successives, que le lease revienne toujours au pool, qu aucun
# cout ne s accumule a force de reutiliser le meme runspace, et qu un changement de compte ou de DC retire le pool
# au lieu de recycler ses runspaces. Le frais et l emprunte sont publies cote a cote par lecture : le jugement de
# cout reste consigne au catalogue, la mesure ne le transforme pas en seuil que le produit ne tient pas.
$readPoolMeasures=[Collections.Generic.List[object]]::new()
$readPoolWork='param($Marker);$c=[Diagnostics.Stopwatch]::StartNew();while($c.Elapsed.TotalMilliseconds -lt 5){};''lu'''
foreach($iteration in 0..($Iterations-1)){
    $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
    $sampled=$rows.Count
    $fresh=Measure-PestoPrototype 'ReadPool.FreshRunspace' 16 $temperature {
        & $engineModule {param($Work)
            $done=0
            foreach($n in 1..16){
                $rs=[runspacefactory]::CreateRunspace([Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
                $rs.ApartmentState=[Threading.ApartmentState]::MTA;$rs.ThreadOptions=[Management.Automation.Runspaces.PSThreadOptions]::ReuseThread;$rs.Open()
                $ps=[PowerShell]::Create();$ps.Runspace=$rs;[void]$ps.AddScript($Work).AddArgument('neuf');$done+=@($ps.Invoke()).Count;$ps.Dispose();$rs.Dispose()
            }
            $done
        } $readPoolWork
    }
    $freshCost=$rows[$sampled].Milliseconds
    if($fresh -ne 16){throw ('Seize lectures attendues hors pool, obtenu '+$fresh+'.')}
    $pool=& $engineModule {New-PestoReadRunspacePool -Maximum 4}
    try{
        $sampled=$rows.Count
        $opened=Measure-PestoPrototype 'ReadPool.FirstLease' 1 $temperature {
            & $engineModule {param($Pool,$Work)
                $lease=Enter-PestoReadRunspace $Pool
                $ps=[PowerShell]::Create();$ps.Runspace=$lease.Slot.Runspace;[void]$ps.AddScript($Work).AddArgument('premier');$done=@($ps.Invoke()).Count;$ps.Dispose()
                Exit-PestoReadRunspace $lease
                [pscustomobject]@{Done=$done;Idle=$Pool.Idle.Count;Count=$Pool.Count}
            } $pool $readPoolWork
        }
        $openedCost=$rows[$sampled].Milliseconds
        if($opened.Done -ne 1){throw ('Une lecture attendue sur le premier creneau, obtenu '+$opened.Done+'.')}
        if($opened.Idle -ne 1 -or $opened.Count -ne 1){throw ('Le premier runspace n est pas rendu au pool : '+$opened.Idle+' libre, pool a '+$opened.Count+'.')}
        [void]$readPoolMeasures.Add([pscustomobject]@{Kind='FirstLease';Case='ouverture et releve de l etat initial';Volume=1;Temperature=$temperature;Runspaces=1;Idle=$opened.Idle;FreshMs=[Math]::Round($freshCost/16,3);PooledMs=[Math]::Round($openedCost,3)})
        foreach($round in @('First','Second')){
            $sampled=$rows.Count
            $reused=Measure-PestoPrototype ('ReadPool.ReusedRunspace.'+$round) 8 $temperature {
                & $engineModule {param($Pool,$Work,$Round)
                    $done=0;$runspaces=[Collections.Generic.HashSet[object]]::new()
                    foreach($n in 1..8){
                        $lease=Enter-PestoReadRunspace $Pool
                        [void]$runspaces.Add($lease.Slot.Runspace)
                        $ps=[PowerShell]::Create();$ps.Runspace=$lease.Slot.Runspace;[void]$ps.AddScript($Work).AddArgument($Round);$done+=@($ps.Invoke()).Count;$ps.Dispose()
                        Exit-PestoReadRunspace $lease
                    }
                    [pscustomobject]@{Done=$done;Runspaces=$runspaces.Count;Idle=$Pool.Idle.Count;Count=$Pool.Count}
                } $pool $readPoolWork $round
            }
            $cost=$rows[$sampled].Milliseconds
            if($reused.Done -ne 8){throw ('Huit lectures attendues au travers du pool, obtenu '+$reused.Done+'.')}
            if($reused.Runspaces -ne 1){throw ('Les huit lectures de la passe '+$round+' auraient du partager un seul runspace, '+$reused.Runspaces+' ont ete ouverts.')}
            if($reused.Idle -ne 1 -or $reused.Count -ne 1){throw ('Un runspace emprunte n est pas revenu au pool : '+$reused.Idle+' libre, pool a '+$reused.Count+'.')}
            [void]$readPoolMeasures.Add([pscustomobject]@{Kind='Reuse';Case='passe '+$round+' - 8 lectures, Maximum=4';Volume=8;Temperature=$temperature;Runspaces=$reused.Runspaces;Idle=$reused.Idle;FreshMs=[Math]::Round($freshCost/16,3);PooledMs=[Math]::Round($cost/8,3);RoundCostMs=[Math]::Round($cost,3)})
            if($round -eq 'Second'){
                $first=[double]((@($readPoolMeasures|Where-Object{$_.Kind -eq 'Reuse' -and $_.Case -like 'passe First*'})|Select-Object -Last 1).RoundCostMs)
                if($cost -gt ($first*1.5+100)){throw ('Le cout par lecture s accumule a force de reutiliser le meme runspace : '+[int]$cost+' ms a la seconde passe contre '+[int]$first+' ms a la premiere.')}
            }
        }
    }finally{& $engineModule {param($Pool)Close-PestoReadRunspacePool $Pool} $pool}
}
# Changement d identite : le pool doit etre retire et refait, jamais recycle entre deux comptes ou deux DC.
foreach($iteration in 0..($Iterations-1)){
    $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
    $sampled=$rows.Count
    $switch=Measure-PestoPrototype 'ReadPool.IdentitySwitch' 1 $temperature {
        & $engineModule {param($Work)
            $a=[pscredential]::new('EXAMPLE\a',(ConvertTo-SecureString 'fake-a' -AsPlainText -Force))
            $b=[pscredential]::new('EXAMPLE\b',(ConvertTo-SecureString 'fake-b' -AsPlainText -Force))
            $p1=Get-PestoSessionReadPool $a 'example.test' 'dc.example.test'
            $lease=Enter-PestoReadRunspace $p1
            $ps=[PowerShell]::Create();$ps.Runspace=$lease.Slot.Runspace;[void]$ps.AddScript($Work).AddArgument('compte-a');[void]$ps.Invoke();$ps.Dispose()
            Exit-PestoReadRunspace $lease
            $p2=Get-PestoSessionReadPool $b 'example.test' 'dc.example.test'
            $next=Enter-PestoReadRunspace $p2
            $ps=[PowerShell]::Create();$ps.Runspace=$next.Slot.Runspace;[void]$ps.AddScript($Work).AddArgument('compte-b');$seen=@($ps.Invoke());$ps.Dispose()
            Exit-PestoReadRunspace $next
            $sameRunspace=[object]::ReferenceEquals($lease.Slot.Runspace,$next.Slot.Runspace)
            Close-PestoReadRunspacePool $p2
            [pscustomobject]@{Retired=[bool]$p1.Retired;KeptCredential=[bool]$p1.Credential;ScopeChanged=($p1.Scope -ne $p2.Scope);SameRunspace=$sameRunspace;Read=@($seen).Count}
        } $readPoolWork
    }
    if(-not $switch.Retired -or $switch.KeptCredential){throw 'Le changement de credential ne retire pas l ancien pool de lectures.'}
    if(-not $switch.ScopeChanged){throw 'Le changement de credential recyclerait l identite du pool precedent.'}
    if($switch.SameRunspace){throw 'Un runspace de lecture aurait surv vec au changement de compte.'}
    if($switch.Read -ne 1){throw 'La lecture suivant le changement de compte n a pas abouti.'}
    [void]$readPoolMeasures.Add([pscustomobject]@{Kind='IdentitySwitch';Case='compte et DC changes';Volume=1;Temperature=$temperature;Runspaces=1;Idle=0;FreshMs=0;PooledMs=[Math]::Round($rows[$sampled].Milliseconds,3)})
}
# Concurrence : le plafond de creneaux est la seule valeur que le pool tient vraiment, et les mesures
# sequentielles ci-dessus ne le prouvent pas. Une vague de lecteurs, reveilles au meme instant par une
# barriere, emprunte le pool du module charge ; chacun compte lui-meme le runspace qu on lui prete. Un
# runspace prete a deux lecteurs en meme temps, ou un pic au-dessus du plafond, est une erreur de mesure,
# jamais un chiffre. Le chronometrage de la vague demarre a l ouverture de la barriere : l ouverture des
# workers et l import du module, identiques des deux cotes, restent hors du chiffre publie.
$readPoolConcurrencyMeasures=[Collections.Generic.List[object]]::new()
$readPoolWave=8
$readPoolCeiling=3
$readPoolParallelReader={
    param($RootPath,$Pool,$Shared,$Work,$Index)
    $module=Get-Module Pesto.Engine
    if(-not $module){Import-Module (Join-Path $RootPath 'wad/Pesto.Engine.psd1') -Force;$module=Get-Module Pesto.Engine}
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Ready=$Shared.Ready+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $Shared.Go -and $clock.ElapsedMilliseconds -lt 20000){[Threading.Thread]::Sleep(1)}
    $wait=[Diagnostics.Stopwatch]::StartNew();$lease=$null
    while($null -eq $lease){
        try{$lease=& $module {param($P)Enter-PestoReadRunspace $P} $Pool}
        catch{
            if($_.Exception.Message -notlike 'Pool de lectures sature*'){throw}
            [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Refused=$Shared.Refused+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
            if($wait.ElapsedMilliseconds -gt 30000){throw 'Un lecteur de la vague attend un creneau depuis trop longtemps.'}
            [Threading.Thread]::Sleep(2)
        }
    }
    $waited=$wait.ElapsedMilliseconds;$key=$lease.Slot.Runspace.InstanceId.ToString()
    [Threading.Monitor]::Enter($Shared.SyncRoot)
    try{
        if($waited -gt $Shared.MaxWaitMs){$Shared.MaxWaitMs=$waited}
        if(-not $Shared.PerRunspace.ContainsKey($key)){$Shared.PerRunspace[$key]=0}
        $Shared.PerRunspace[$key]=$Shared.PerRunspace[$key]+1
        if($Shared.PerRunspace[$key] -gt $Shared.PeakInFlight){$Shared.PeakInFlight=$Shared.PerRunspace[$key]}
        if($Shared.PerRunspace.Count -gt $Shared.PeakRunspaces){$Shared.PeakRunspaces=$Shared.PerRunspace.Count}
    }finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $ps=[PowerShell]::Create();$ps.Runspace=$lease.Slot.Runspace
    [void]$ps.AddScript($Work).AddArgument('vague-'+$Index)
    $seen=@($ps.Invoke());if($ps.HadErrors){throw ('La lecture empruntee de la vague a echoue : '+($ps.Streams.Error|Out-String))}
    $ps.Dispose()
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.PerRunspace[$key]=$Shared.PerRunspace[$key]-1;$Shared.Done=$Shared.Done+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    & $module {param($L)Exit-PestoReadRunspace $L} $lease
    'lu'
}.ToString()
$readPoolFreshReader={
    param($RootPath,$Pool,$Shared,$Work,$Index)
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Ready=$Shared.Ready+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $Shared.Go -and $clock.ElapsedMilliseconds -lt 20000){[Threading.Thread]::Sleep(1)}
    $rs=[runspacefactory]::CreateRunspace([Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
    $rs.ApartmentState=[Threading.ApartmentState]::MTA;$rs.ThreadOptions=[Management.Automation.Runspaces.PSThreadOptions]::ReuseThread;$rs.Open()
    $ps=[PowerShell]::Create();$ps.Runspace=$rs;[void]$ps.AddScript($Work).AddArgument('vague-neuve-'+$Index)
    $seen=@($ps.Invoke());$ps.Dispose();$rs.Dispose()
    if($seen.Count -ne 1){throw 'Une lecture hors pool de la vague de comparaison na pas abouti.'}
    'lu'
}.ToString()
function Start-PestoMeasureReaderWave {
    param([string]$Worker,[hashtable]$Pool,[hashtable]$Shared,[int]$Count)
    $workers=@()
    foreach($n in 1..$Count){
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript($Worker,$true).AddArgument($root).AddArgument($Pool).AddArgument($Shared).AddArgument($readPoolWork).AddArgument($n)
        $workers+=@(@{PS=$ps;Handle=$ps.BeginInvoke()})
    }
    return $workers
}
function Wait-PestoMeasureReaderWave {
    # Le chiffre publie part a l ouverture de la barriere et s arrete au dernier join : il ne compte ni
    # la creation des workers ni l import du module, qui sont les memes des deux cotes de la comparaison.
    param([hashtable]$Shared,[object[]]$Workers,[int]$Count,[int]$TimeoutMs=60000)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($Shared.Ready -lt $Count -and $clock.ElapsedMilliseconds -lt $TimeoutMs){[Threading.Thread]::Sleep(2)}
    if($Shared.Ready -lt $Count){throw ('Reveil de la vague incomplet : '+$Shared.Ready+' lecteurs sur '+$Count+'.')}
    $barrier=[Diagnostics.Stopwatch]::StartNew()
    $Shared.Go=$true
    $read=@(foreach($worker in $Workers){$worker.PS.EndInvoke($worker.Handle)})
    $waveMs=$barrier.ElapsedMilliseconds
    return [pscustomobject]@{Read=@($read|Where-Object{$_ -eq 'lu'}).Count;WaveMs=$waveMs}
}
foreach($iteration in 0..($Iterations-1)){
    $temperature=if($iteration -eq 0){'Cold'}else{'Warm'}
    $pool=& $engineModule {param($Max)New-PestoReadRunspacePool -Maximum $Max} $readPoolCeiling
    try{
        $shared=[hashtable]::Synchronized(@{Ready=0;Go=$false;Done=0;Refused=0;PeakInFlight=0;PeakRunspaces=0;MaxWaitMs=0L;PerRunspace=@{}})
        $sampled=$rows.Count
        $wave=Measure-PestoPrototype 'ReadPool.ConcurrencyWave' $readPoolWave $temperature {
            $workers=Start-PestoMeasureReaderWave -Worker $readPoolParallelReader -Pool $pool -Shared $shared -Count $readPoolWave
            $result=Wait-PestoMeasureReaderWave -Shared $shared -Workers $workers -Count $readPoolWave
            foreach($worker in $workers){$worker.PS.Dispose()}
            [pscustomobject]@{Read=$result.Read;WaveMs=$result.WaveMs;Done=$shared.Done;Refused=$shared.Refused;PeakInFlight=$shared.PeakInFlight;PeakRunspaces=$shared.PeakRunspaces;WaitMaxMs=$shared.MaxWaitMs;Idle=$pool.Idle.Count;PoolCount=$pool.Count}
        }
        if($wave.Read -ne $readPoolWave -or $wave.Done -ne $readPoolWave){throw ('Les '+$readPoolWave+' lectures empruntees de la vague ne sont pas toutes passees : '+$wave.Read+' rendues, '+$wave.Done+' comptees.')}
        if($wave.PeakInFlight -ne 1){throw ('Un runspace emprunte aurait servi deux lecteurs en meme temps : '+$wave.PeakInFlight+' lectures simultanees sur le meme runspace.')}
        if($wave.PeakRunspaces -gt $readPoolCeiling){throw ('La vague a depasse le plafond du pool : '+$wave.PeakRunspaces+' runspaces en cours pour '+$readPoolCeiling+' creneaux.')}
        if($wave.PeakRunspaces -lt 2){throw ('La vague n a jamais emprunte deux runspaces a la fois : pic '+$wave.PeakRunspaces+' pour '+$readPoolWave+' lecteurs.')}
        if($wave.Refused -lt 1){throw ('La vague de '+$readPoolWave+' lecteurs sur '+$readPoolCeiling+' creneaux n a rencontre aucun refus : elle etait sequentielle, pas concurrente.')}
        if($wave.Idle -ne $wave.PoolCount){throw ('Un lease de la vague n est jamais revenu au pool : '+$wave.PoolCount+' runspaces, '+$wave.Idle+' libres.')}
        [void]$readPoolConcurrencyMeasures.Add([pscustomobject]@{Kind='Concurrency';Case='vague de '+$readPoolWave+' lecteurs, Maximum='+$readPoolCeiling;Volume=$readPoolWave;Temperature=$temperature;Ceiling=$readPoolCeiling;PeakRunspaces=$wave.PeakRunspaces;PeakInFlight=$wave.PeakInFlight;Refused=$wave.Refused;WaitMaxMs=$wave.WaitMaxMs;Milliseconds=[Math]::Round($wave.WaveMs,3)})
    }finally{& $engineModule {param($P)Close-PestoReadRunspacePool $P} $pool}
    $freshShared=[hashtable]::Synchronized(@{Ready=0;Go=$false})
    $sampled=$rows.Count
    $fresh=Measure-PestoPrototype 'ReadPool.ConcurrencyWaveFresh' $readPoolWave $temperature {
        $workers=Start-PestoMeasureReaderWave -Worker $readPoolFreshReader -Pool $null -Shared $freshShared -Count $readPoolWave
        $result=Wait-PestoMeasureReaderWave -Shared $freshShared -Workers $workers -Count $readPoolWave
        foreach($worker in $workers){$worker.PS.Dispose()}
        $result
    }
    if($fresh.Read -ne $readPoolWave){throw ('Les '+$readPoolWave+' lectures hors pool de la vague de comparaison ne sont pas toutes passees : '+$fresh.Read+'.')}
    [void]$readPoolConcurrencyMeasures.Add([pscustomobject]@{Kind='ConcurrencyFresh';Case='vague de '+$readPoolWave+' runspaces neufs, comparaison';Volume=$readPoolWave;Temperature=$temperature;Ceiling=$readPoolWave;PeakRunspaces=$readPoolWave;PeakInFlight=1;Refused=0;WaitMaxMs=0L;Milliseconds=[Math]::Round($fresh.WaveMs,3)})
}
$readPoolConcurrencySummary=@(foreach($group in ($readPoolConcurrencyMeasures|Group-Object Kind)){$values=@($group.Group.Milliseconds|Sort-Object);$peaks=@($group.Group.PeakRunspaces|Sort-Object);$waits=@($group.Group.WaitMaxMs|Sort-Object);$refused=@($group.Group.Refused|Sort-Object);[pscustomobject]@{Kind=$group.Group[0].Kind;Case=$group.Group[0].Case;Volume=$group.Group[0].Volume;Samples=$values.Count;Ceiling=$group.Group[0].Ceiling;WaveMedianMs=$values[[int][Math]::Floor($values.Count/2)];WaveP95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)];PerReadMedianMs=[Math]::Round($values[[int][Math]::Floor($values.Count/2)]/$group.Group[0].Volume,3);PeakRunspaces=$peaks[-1];PeakInFlight=[int](($group.Group.PeakInFlight|Measure-Object -Maximum).Maximum);RefusedMedian=$refused[[int][Math]::Floor($refused.Count/2)];WaitMedianMs=$waits[[int][Math]::Floor($waits.Count/2)]}})
$readPoolSummary=@(foreach($group in ($readPoolMeasures|Group-Object Kind,Case)){$fresh=@($group.Group.FreshMs|Sort-Object);$pooled=@($group.Group.PooledMs|Sort-Object);[pscustomobject]@{Kind=$group.Group[0].Kind;Case=$group.Group[0].Case;Volume=$group.Group[0].Volume;Samples=$pooled.Count;Runspaces=$group.Group[0].Runspaces;Idle=$group.Group[0].Idle;FreshMedianMs=$fresh[[int][Math]::Floor($fresh.Count/2)];PooledMedianMs=$pooled[[int][Math]::Floor($pooled.Count/2)];PooledP95Ms=$pooled[[Math]::Max(0,[int][Math]::Ceiling($pooled.Count*.95)-1)]}})
# Comparaison publiee, jamais imposee : par lecture, le frais paie l ouverture complete du runspace, l emprunte
# paie le nettoyage livre (modules, fonctions, alias, lecteurs, puis reset des variables). Le gain du pool n est
# pas un contrat du produit ; ce que la mesure refuse, ci-dessus, c est un runspace qui ne revient pas, un deuxieme
# runspace qui s ouvre, une accumulation a l usage ou un runspace qui survit a un changement de compte.
$readPoolReuses=@($readPoolMeasures|Where-Object Kind -eq 'Reuse')
$readPoolFreshPerRead=@($readPoolReuses|ForEach-Object{$_.FreshMs}|Sort-Object)
$readPoolPooledPerRead=@($readPoolReuses|ForEach-Object{$_.PooledMs}|Sort-Object)
$readPoolMedianFresh=$readPoolFreshPerRead[[int][Math]::Floor($readPoolFreshPerRead.Count/2)]
$readPoolMedianPooled=$readPoolPooledPerRead[[int][Math]::Floor($readPoolPooledPerRead.Count/2)]
$readPoolComparison=[pscustomobject]@{Samples=$readPoolReuses.Count;FreshMedianPerReadMs=$readPoolMedianFresh;PooledMedianPerReadMs=$readPoolMedianPooled;PoolCheaperThanFresh=($readPoolMedianPooled -lt $readPoolMedianFresh)}

# --- Helpers precompiles (point 63) : Add-Type a froid contre chargement verifie, sur le meme ouvrage. ---
# Le bloc publie est produit par Measure-PestoCompiledHelpers (defini avec les ouvriers) : le meme code joue
# dans le rapport complet et dans le mode evaluation seule. Consommateur branche : la suite 63 relit ce bloc
# et en asserte la conclusion ; les couts restent publies, pas imposes.
$compiledPair=Measure-PestoCompiledHelpers -Samples $Iterations
foreach($compiledRow in $compiledPair.Rows){[void]$rows.Add($compiledRow)}
$compiledSummary=$compiledPair.Summary
$compiledSamples=$compiledPair.Samples

$summary=@(foreach($group in $rows|Group-Object Name,Volume){$values=@($group.Group.Milliseconds|Sort-Object);[pscustomobject]@{Name=$group.Group[0].Name;Volume=$group.Group[0].Volume;Samples=$values.Count;MedianMs=$values[[int][Math]::Floor($values.Count/2)];P95Ms=$values[[Math]::Max(0,[int][Math]::Ceiling($values.Count*.95)-1)]}})
$report=[ordered]@{Schema=1;Utc=[DateTime]::UtcNow.ToString('o');Platform=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();CLR=[Environment]::Version.ToString();RuntimeModuleSHA256=(Get-FileHash (Join-Path $root 'wad/Pesto.Engine.Runtime.ps1')).Hash.ToLowerInvariant();
    Dataset='Synthetic unique names, deterministic descending order';Iterations=$Iterations;Measurements=$rows.ToArray();Summary=$summary;GridRowUpdate=$gridSummary;GridRowSamples=$gridMeasures.ToArray();QueryPaging=$pagingSummary;QueryPagingSamples=$pagingMeasures.ToArray();InventoryIndex=$inventorySummary;InventoryIndexSamples=$inventoryMeasures.ToArray();ReadAdmission=$readAdmissionSummary;ReadAdmissionSamples=$readAdmissionMeasures.ToArray();ReadPool=$readPoolSummary;ReadPoolSamples=$readPoolMeasures.ToArray();ReadPoolComparison=$readPoolComparison;ReadPoolConcurrency=$readPoolConcurrencySummary;ReadPoolConcurrencySamples=$readPoolConcurrencyMeasures.ToArray();CompiledHelpers=$compiledSummary;CompiledHelpersSamples=$compiledSamples;
    PoolScriptScopePersisted=[bool]$leaked;WindowsADExecuted=$false;UIExecuted=$false;ProductionAlgorithmChanged=$false;
    Limits=@('Temps locaux incluant frontière PowerShell/.NET ; aucune extrapolation réseau AD.','Delta mémoire approximatif du GC, pas mémoire maximale de travail.','Top-k ne couvre pas les filtres/valeurs inconnues/tri stable Common.Query.','Limiter le pool à une seule session (credential, domaine, DC) : il est retiré au changement d identité et son nettoyage compare fonctions et alias initiaux avant toute réutilisation.','PowerShell7 est un hôte de prototype, pas la cible Windows5.1 certifiée.','GridRowUpdate : coût du helper seul, grille factice, aucun rendu WPF ; le frame time et les passes de mise en page restent à qualifier sous PowerShell 5.1 en STA par tools/Measure-PestoWpfProjection.ps1.','QueryPaging : le chemin intégré (Get-PestoInterventionQuery relu des sources livrées, vraies DLL Common.Query) paie la conversion des lignes en QueryRecord que la baseline tri complet ne paie pas ; comparaison d identités triées, hors rendu WPF.','InventoryIndex : parcours d inventaire livré et ses deux chemins internes sur noms synthétiques de 15 caractères ; la conversion des objets AD réels, le reseau et le typage des objets Get-ADComputer restent hors mesure locale.','ReadAdmission : creneaux, plafond d admission et attente bornee mesures sur SemaphoreSlim et runspaces reels, corps de lecture synthetique ; le DispatcherTimer WPF du produit, l appel Get-ADComputer reel et le reseau restent hors mesure locale.','ReadAdmission : la reprise dort dans le creneau et le backoff reste impute au lecteur qui le detient ; a MaxReaders=1 une seule lecture lente peut affamer les autres lectures jusqu au refus borne a 30 secondes, contrat livre et non reglage a compenser automatiquement.','ReadPool : cout local de l emprunt, du nettoyage et du changement d identite sur runspaces reels, corps de lecture synthetique et maximum borne ; le DispatcherTimer WPF du produit, l appel Get-ADComputer reel et le reseau restent hors mesure locale.','ReadPool.ConcurrencyWave : vague de huit lecteurs reveilles au meme instant sur un pool a trois creneaux, corps de lecture synthetique, creneau compte par runspace et chronometrage pris a l ouverture de la barriere ; le plafond de concurrence est mesure sur runspaces reels empruntes par de vrais workers paralleles, le DispatcherTimer WPF du produit, l appel Get-ADComputer reel et le reseau restent hors mesure locale.','CompiledHelpers : cout local, sous un hote non produit, de la compilation a froid des quatre sources C# livrees par Add-Type site par site contre le chargement verifie de Pesto.Runtime.dll par le chargeur livre ; les quatre entrees DllImport ne sont pas executees ici (kernel32, shell32, user32 absents d une machine Linux) et restent a qualifier sur Windows reel, et la comparaison des couts est publiee sans etre imposee.')}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$summary|Format-Table -AutoSize
$gridSummary|Format-Table -AutoSize
$pagingSummary|Format-Table -AutoSize
$inventorySummary|Format-Table -AutoSize
$readAdmissionSummary|Format-Table -AutoSize
$readPoolSummary|Format-Table -AutoSize
$compiledSummary|Format-Table -AutoSize
$readPoolComparison|Format-List
