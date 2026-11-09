#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent;$wad=Join-Path $root 'wad'
# Le harnais de mutations compare des messages d'echec attendus : le formateur d'exception PowerShell replie
# et colore ces messages, ils ne sont donc pas comparables tels quels. L'echec est aussi rendu sur une seule
# ligne non coloree, que le harnais recherche.
trap { Write-Output ('PESTO63-FAIL: '+($_.Exception.Message -replace '\s+',' ')); exit 1 }
. (Join-Path $wad 'Pesto-Common.ps1')
Initialize-PestoRuntimeTypes -Root $wad
$n=0
function Check($ok,$message){if(-not $ok){throw $message};$script:n++}
foreach($name in @('Pesto.Runtime.AsyncAuditWriter','Pesto.Inventory.CompactIndex','Pesto.NativePipe17','Pesto.NativeShell')){
 $type=$name -as [type];Check ($null -ne $type -and $type.Assembly.GetName().Name -ceq 'Pesto.Runtime') ('Wrong helper provenance: '+$name)
}
$a=[Pesto.Inventory.CompactIndex].Assembly;Initialize-PestoRuntimeTypes -Root $wad
Check ([object]::ReferenceEquals($a,[Pesto.Inventory.CompactIndex].Assembly)) 'Repeated load duplicated assembly'
Check ($a.GetCustomAttributesData().Where({$_.AttributeType.Name -eq 'TargetFrameworkAttribute'})[0].ConstructorArguments[0].Value -eq '.NETFramework,Version=v4.7.2') 'Wrong target framework'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoCompiled-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
 $bytes=[IO.File]::ReadAllBytes((Join-Path $wad 'Pesto.Runtime.dll'));$bytes[$bytes.Length-1]=$bytes[$bytes.Length-1] -bxor 1
 [IO.File]::WriteAllBytes((Join-Path $temp 'Pesto.Runtime.dll'),$bytes)
 $refused=$false;try{Initialize-PestoRuntimeTypes -Root $temp}catch{$refused=$true};Check $refused 'Tampered DLL accepted'
 $file=Join-Path $temp 'audit.log';[IO.File]::WriteAllText($file,'');$writer=[Pesto.Runtime.AsyncAuditWriter]::new($file,128)
 try{
  Check ($writer.TryWrite('verified-runtime')) 'Compiled writer rejected data'
  Check ($writer.Flush(2000)) 'Compiled writer did not flush'
  Check ([IO.File]::ReadAllText($file) -eq 'verified-runtime') 'Compiled writer changed data'
 }finally{[void]$writer.Close(2000)}
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}

# Surface native : les entrees DllImport livrees sont la liste exacte a qualifier sur cible.
function Get-NativeSurface{
 param([string[]]$TypeNames)
 $found=[Collections.Generic.List[string]]::new()
 foreach($t in $TypeNames){
  $type=$t -as [type];if(-not $type){throw 'Native helper type missing: '+$t}
  foreach($m in $type.GetMethods([Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)){
   foreach($attr in @($m.GetCustomAttributesData())){
    if($attr.AttributeType.Name -ceq 'DllImportAttribute'){[void]$found.Add($t+'|'+[string]$attr.ConstructorArguments[0].Value+'|'+$m.Name)}
   }
  }
 }
 return $found.ToArray()
}
$expectedNative=@('Pesto.NativeShell|shell32.dll|SetCurrentProcessExplicitAppUserModelID','Pesto.NativeShell|user32.dll|SendMessage','Pesto.NativeShell|user32.dll|DestroyIcon','Pesto.NativePipe17|kernel32.dll|GetNamedPipeClientProcessId')
$observedNative=@(Get-NativeSurface -TypeNames @('Pesto.Runtime.AsyncAuditWriter','Pesto.Inventory.CompactIndex','Pesto.NativePipe17','Pesto.NativeShell'))
$nativeDrift=@(Compare-Object -ReferenceObject $expectedNative -DifferenceObject $observedNative)
Check ($nativeDrift.Count -eq 0) ('Native surface drifted from the on-target qualification list: '+(($nativeDrift|ForEach-Object {$_.SideIndicator+' '+$_.InputObject}) -join '; '))

function Parse-ShippedFile{
 param([string]$Path)
 if(-not (Test-Path -LiteralPath $Path)){throw 'Shipped file missing: '+$Path}
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'Unparsable shipped file: '+$Path}
 return $ast
}
function Find-NativeCalls{
 param($Ast,[string]$TypeName,[string]$MemberName)
 $target=if($MemberName){[regex]::Escape($MemberName)}else{'\w+'}
 $pattern='^\['+[regex]::Escape($TypeName)+'\]::'+$target+'\s*\('
 return @($Ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Extent.Text -match $pattern},$true))
}
# Porte du canal eleve : l'appel natif kernel32 est en defaillance securisante avant tout secret.
function Assert-PipeGateFailClosed{
 param([string]$Path,[string]$Label)
 $ast=Parse-ShippedFile -Path $Path
 $gate=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Test-PestoPipeClient'},$true))
 Check ($gate.Count -eq 1) ('Pipe gate function missing in '+$Label)
 $gateFn=$gate[0]
 Check (@($gateFn.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Initialize-PestoRuntimeTypes'},$true)).Count -eq 1) ('Pipe gate no longer loads the verified library in '+$Label)
 $calls=Find-NativeCalls -Ast $gateFn -TypeName 'Pesto.NativePipe17' -MemberName 'GetNamedPipeClientProcessId'
 Check ($calls.Count -eq 1) ('Native pipe call count changed in '+$Label)
 $node=$calls[0].Parent;$guard=$null
 while($node -and $node -ne $gateFn){if($node -is [Management.Automation.Language.IfStatementAst]){$guard=$node;break};$node=$node.Parent}
 $negated='^if\s*\(\s*-not\s'+[regex]::Escape($calls[0].Extent.Text)+'\s*\)'
 Check ($null -ne $guard -and $guard.Extent.Text -cmatch $negated) ('Native pipe call no longer negated in '+$Label)
 Check (@($guard.FindAll({param($n) $n -is [Management.Automation.Language.ThrowStatementAst]},$true)).Count -ge 1) ('Native pipe failure no longer throws in '+$Label)
 Check (@($gateFn.FindAll({param($n) $n -is [Management.Automation.Language.ThrowStatementAst] -and $n.Extent.Text -cmatch 'Aucun secret transmis'},$true)).Count -ge 1) ('Unexpected-client throw lost in '+$Label)
 $callers=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Test-PestoPipeClient'},$true))
 $caller=$null
 foreach($c in $callers){$f=$c;while($f -and $f -isnot [Management.Automation.Language.FunctionDefinitionAst]){$f=$f.Parent};if($f -and $f.Name -cne 'Test-PestoPipeClient'){$caller=$c;break}}
 Check ($null -ne $caller) ('No elevated-flow pipe gate caller in '+$Label)
 $fn=$caller;while($fn -and $fn -isnot [Management.Automation.Language.FunctionDefinitionAst]){$fn=$fn.Parent}
 $creds=@($fn.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Extent.Text -match 'GetNetworkCredential\s*\('},$true))
 Check ($creds.Count -ge 1 -and $caller.Extent.StartLineNumber -lt $creds[0].Extent.StartLineNumber) ('Pipe gate no longer precedes the secret in '+$Label)
}
# Chemin icone : les appels natifs user32/shell32 restent souples (garde de type, within try).
function Assert-IconPathSoft{
 param([string]$Path,[string]$Label)
 $ast=Parse-ShippedFile -Path $Path
 $calls=Find-NativeCalls -Ast $ast -TypeName 'Pesto.NativeShell' -MemberName ''
 Check ($calls.Count -eq 5) ('NativeShell call count changed in '+$Label)
 foreach($c in $calls){
  $node=$c;$inTry=$false
  while($node){if($node -is [Management.Automation.Language.TryStatementAst]){$inTry=$true;break};$node=$node.Parent}
  Check $inTry ('Unguarded native icon call at line '+$c.Extent.StartLineNumber+' in '+$Label)
 }
 $fn=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Set-WindowIcon'},$true))
 Check ($fn.Count -eq 1) ('Icon function missing in '+$Label)
 Check (@([regex]::Matches($fn[0].Extent.Text,[regex]::Escape("'Pesto.NativeShell' -as [type]"))).Count -ge 2) ('NativeShell type guards missing in '+$Label)
}
Assert-PipeGateFailClosed -Path (Join-Path $wad 'Pesto-Operations.ps1') -Label 'wad/Pesto-Operations.ps1'
Assert-PipeGateFailClosed -Path (Join-Path $wad 'Pesto.Engine.Runtime.ps1') -Label 'module Engine genere'
Assert-IconPathSoft -Path (Join-Path $wad 'Pesto-Core.ps1') -Label 'wad/Pesto-Core.ps1'
Assert-IconPathSoft -Path (Join-Path $wad 'Pesto.Engine.Runtime.ps1') -Label 'module Engine genere'
# Evaluation 63 : tests/Measure-Engine120.ps1 mesure les deux modes de livraison des quatre helpers C# sur
# le meme ouvrage. La suite en est le consommateur branche : elle joue les deux enfants, exige l'egalite des
# resultats, la provenance du cote precompile et la compilation reelle des quatre sources que compile deja
# tools/Build-PestoRuntimeTypes.ps1. Les couts ne sont pas imposes ici : ils sont publies par le banc.
function Invoke-CompiledHelperWorker{
    param([string]$Mode)
    $bench=Join-Path $PSScriptRoot 'Measure-Engine120.ps1'
    if(-not (Test-Path -LiteralPath $bench)){throw 'Compiled-helpers bench missing: tests/Measure-Engine120.ps1'}
    $hostExe=(Get-Process -Id $PID).Path
    $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
    $output=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bench -CompiledHelpersWorker $Mode 2>&1|ForEach-Object{[string]$_})
    $code=$LASTEXITCODE;$ErrorActionPreference=$previous
    $line=@(@($output|Where-Object{$_ -match '^\{.*\}$'})|Select-Object -Last 1)
    Check ($code -eq 0) ('Compiled-helpers worker '+$Mode+' exited '+$code+' : '+(($output) -join "`n"))
    Check ($line) ('Compiled-helpers worker '+$Mode+' rendered no report : '+(($output) -join "`n"))
    return ($line|ConvertFrom-Json)
}
$buildText=[IO.File]::ReadAllText((Join-Path $root 'tools/Build-PestoRuntimeTypes.ps1'))
$buildMatch=[regex]::Match($buildText,'foreach\(\$relative in @\(([^)]*)\)\)')
Check ($buildMatch.Success) 'The helper source list of the build tool is no longer readable'
$buildSources=@([regex]::Matches($buildMatch.Value,"'([^']+)'")|ForEach-Object{$_.Groups[1].Value})
Check ($buildSources.Count -eq 4) 'The build tool no longer compiles exactly four helper sources'
$compiledAddType=Invoke-CompiledHelperWorker -Mode 'AddType'
$compiledPrecompiled=Invoke-CompiledHelperWorker -Mode 'Precompiled'
Check (@($compiledAddType.Sources) -join '|' -ceq ($buildSources -join '|')) 'The Add-Type side no longer compiles the four sources the build tool compiles'
Check (@($compiledAddType.AssemblyNames|Sort-Object -Unique).Count -eq 4) 'The Add-Type side no longer compiles four separate assemblies'
Check (@($compiledAddType.AssemblyNames|Where-Object{$_ -ceq 'Pesto.Runtime'}).Count -eq 0) 'The Add-Type side would reuse the delivered assembly'
Check (@($compiledPrecompiled.AssemblyNames).Count -eq 1 -and @($compiledPrecompiled.AssemblyNames)[0] -ceq 'Pesto.Runtime') 'The precompiled side no longer loads the delivered assembly'
Check (@($compiledPrecompiled.Locations)[0] -ceq (Join-Path $wad 'Pesto.Runtime.dll')) 'The precompiled side no longer loads the delivered DLL'
Check ($compiledPrecompiled.LoaderVerified) 'The precompiled side no longer goes through the verified loader'
Check (-not $compiledAddType.LoaderVerified) 'The Add-Type side would claim the verified loader'
Check (@($compiledAddType.Native).Count -eq 4 -and @($compiledPrecompiled.Native).Count -eq 4) 'Compiled-helpers native surface incomplete'
Check (@(Compare-Object -ReferenceObject $expectedNative -DifferenceObject @($compiledAddType.Native)).Count -eq 0) 'Runtime-compiled sources no longer expose the pinned native surface'
Check (@(Compare-Object -ReferenceObject $expectedNative -DifferenceObject @($compiledPrecompiled.Native)).Count -eq 0) 'The delivered assembly no longer exposes the pinned native surface'
Check ([int]$compiledAddType.Rows -eq 2000 -and [int]$compiledPrecompiled.Rows -eq 2000) 'The compiled-helpers workload no longer indexes 2000 rows on both sides'
Check ([string]$compiledAddType.Digest -ceq [string]$compiledPrecompiled.Digest) 'Precompiled helpers and runtime-compiled sources no longer render the same workload'
# Le bloc publie par le banc est le resultat de l evaluation 63 : la suite en est le consommateur branche.
# Elle rejoue le banc en mode evaluation seule (-CompiledHelpersOnly), relit le rapport JSON et asserte que la
# conclusion publiee au catalogue tient toujours : a ouvrage identique, le chemin livre reste nettement moins
# couteux que la compilation a froid. Le seuil est large (facteur deux) : c est la conclusion de l evaluation,
# pas un reglage de performance. En dessous, l evaluation est a refaire et la suite doit le dire.
function Invoke-CompiledHelpersReport{
    param([int]$Samples=3)
    $bench=Join-Path $PSScriptRoot 'Measure-Engine120.ps1'
    if(-not (Test-Path -LiteralPath $bench)){throw 'Compiled-helpers bench missing: tests/Measure-Engine120.ps1'}
    $reportPath=Join-Path ([IO.Path]::GetTempPath()) ('PestoCompiled63Report-'+[Guid]::NewGuid().ToString('N')+'.json')
    $hostExe=(Get-Process -Id $PID).Path
    $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{
        $output=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bench -CompiledHelpersOnly -Iterations $Samples -OutputPath $reportPath 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE
        Check ($code -eq 0) ('Compiled-helpers evaluation report exited '+$code+' : '+(($output) -join "`n"))
        Check (Test-Path -LiteralPath $reportPath) 'The bench published no compiled-helpers report'
        $text=[IO.File]::ReadAllText($reportPath)
    }finally{Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue}
    return ($text|ConvertFrom-Json)
}
$evaluation=Invoke-CompiledHelpersReport -Samples 3
Check ([string]$evaluation.Section -ceq 'CompiledHelpers') 'The compiled-helpers report is not the evaluation section'
Check ($evaluation.WindowsADExecuted -eq $false) 'The compiled-helpers evaluation would claim native execution'
Check (@($evaluation.CompiledHelpersSamples).Count -eq 6) 'The published block no longer reports the six played samples'
$published=@($evaluation.CompiledHelpers)
Check ((@($published|ForEach-Object{[string]$_.Mode}|Sort-Object) -join ',') -ceq 'AddType,Precompiled') 'The published block no longer compares the two delivery modes'
$publishedByMode=@{};foreach($entry in $published){$publishedByMode[[string]$entry.Mode]=$entry}
$publishedAdd=$publishedByMode['AddType'];$publishedPre=$publishedByMode['Precompiled']
Check ($null -ne $publishedAdd -and $null -ne $publishedPre) 'The published block no longer reports both delivery modes'
Check ([int]$publishedAdd.Samples -eq 3 -and [int]$publishedPre.Samples -eq 3) 'The published block no longer reports three samples per mode'
Check ([int]$publishedAdd.Rows -eq 2000 -and [int]$publishedPre.Rows -eq 2000) 'The published block no longer indexes 2000 rows on both sides'
Check ([int]$publishedAdd.Assemblies -eq 4 -and [int]$publishedPre.Assemblies -eq 1) 'The published block no longer counts one delivered assembly against four compiled ones'
Check ([int]$publishedAdd.NativeEntries -eq 4 -and [int]$publishedPre.NativeEntries -eq 4) 'The published block no longer counts the four native entries on both sides'
Check (([string]$publishedAdd.Digest) -ceq ([string]$publishedPre.Digest) -and ([string]$publishedAdd.Digest) -cmatch '^[0-9a-f]{64}$') 'The published block no longer reports one identical workload digest'
Check ([double]$publishedAdd.P95Ms -ge [double]$publishedAdd.MedianMs -and [double]$publishedPre.P95Ms -ge [double]$publishedPre.MedianMs) 'The published percentiles are incoherent'
Check ([double]$publishedPre.MedianMs -lt [double]$publishedAdd.MedianMs) 'The delivered path is no longer cheaper than cold Add-Type compilation'
Check ([double]$publishedAdd.MedianMs -ge 2*[double]$publishedPre.MedianMs) 'The evaluation result no longer holds: the verified loader is not at least twice as cheap as cold Add-Type'
Write-Output "CompiledHelpers63 : $n/$n PASS"
