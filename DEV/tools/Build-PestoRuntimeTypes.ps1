#requires -Version 7.4
# Build tool only: runtime assembly targets .NET Framework 4.7.2 / C# 5.
param([string]$Root=(Split-Path $PSScriptRoot -Parent),[string]$ReferenceDirectory='', [switch]$Check)
$ErrorActionPreference='Stop'
if(-not $ReferenceDirectory){$ReferenceDirectory=Join-Path $Root 'vendor/M4D.Admin.Common/.build/net472'}
if(-not(Test-Path (Join-Path $ReferenceDirectory 'mscorlib.dll'))){throw 'Executez vendor/M4D.Admin.Common/tools/bootstrap.py (references Microsoft epinglees).'}
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')
$parse=[Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::Default.WithLanguageVersion([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
$options=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release).WithDeterministic($true)
$refs=[Microsoft.CodeAnalysis.MetadataReference[]]@('mscorlib.dll','System.dll','System.Core.dll'|ForEach-Object{[Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $ReferenceDirectory $_))})
$trees=[Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]]::new()
$trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText('[assembly:System.Reflection.AssemblyVersion("1.0.0.0")][assembly:System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.7.2")]',$parse,'AssemblyInfo.cs',[Text.Encoding]::UTF8))
foreach($relative in @('wad/Pesto-LogWriter.cs','src/Pesto.Runtime/CompactIndex.cs','src/Pesto.Runtime/NativePipe.cs','src/Pesto.Runtime/NativeShell.cs')){
 $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Join-Path $Root $relative)),$parse,$relative,[Text.Encoding]::UTF8))
}
$c=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('Pesto.Runtime',$trees.ToArray(),$refs,$options)
$stream=[IO.MemoryStream]::new()
try{$result=$c.Emit($stream);$issues=@($result.Diagnostics|Where-Object {$_.Severity -in @('Error','Warning')});if(-not $result.Success -or $issues.Count){throw ($issues -join "`n")};$bytes=$stream.ToArray()}finally{$stream.Dispose()}
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
$path=Join-Path $Root 'wad/Pesto.Runtime.dll';$loader=Join-Path $Root 'wad/Pesto-Common.ps1'
$text=[IO.File]::ReadAllText($loader);$pattern="(?m)\`$expected='[0-9a-f]{64}' # PESTO_COMPILED_SHA256";$replacement="`$expected='$sha' # PESTO_COMPILED_SHA256"
if(-not [regex]::IsMatch($text,$pattern)){throw 'Marqueur de liaison des helpers absent.'}
$updated=[regex]::Replace($text,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $replacement})
if($Check){if((Get-FileHash $path -Algorithm SHA256).Hash -ine $sha -or $updated -cne $text){throw 'Helpers perimes.'}}
else{[IO.File]::WriteAllBytes($path,$bytes);[IO.File]::WriteAllText($loader,$updated,[Text.UTF8Encoding]::new($true))}
[pscustomobject]@{Checked=[bool]$Check;Target='net472';Language='CSharp5';SHA256=$sha;Bytes=$bytes.Length}
