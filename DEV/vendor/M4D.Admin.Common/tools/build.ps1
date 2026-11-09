#requires -Version 7.4
<#[Build tool only.] Runtime DLLs target .NET Framework 4.7.2 and have no PowerShell dependency.
   Run bootstrap.py once. No network request is made by this compiler or by runtime libraries. #>
param([string]$ReferenceDirectory='', [string]$OutputDirectory='', [switch]$Tests)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
if(-not $ReferenceDirectory){$ReferenceDirectory=Join-Path $root '.build/net472'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
if(-not(Test-Path -LiteralPath (Join-Path $ReferenceDirectory 'mscorlib.dll'))){throw 'Run python3 tools/bootstrap.py before building.'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')
$version=Get-Content -LiteralPath (Join-Path $root 'version.json') -Raw | ConvertFrom-Json
if($version.targetFramework -cne 'net472' -or $version.languageVersion -cne 'CSharp5'){throw 'This builder supports CSharp5/net472 only.'}
$parse=[Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::Default.WithLanguageVersion([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
$options=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary)
$options=$options.WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release).WithDeterministic($true)
$references=@(@('mscorlib.dll','System.dll','System.Core.dll','System.Security.dll','System.Runtime.Serialization.dll','System.Xml.dll') | ForEach-Object {
    [Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $ReferenceDirectory $_))
})
$assemblyInfo='[assembly:System.Reflection.AssemblyVersion("'+$version.assemblyVersion+'")][assembly:System.Reflection.AssemblyFileVersion("'+$version.fileVersion+'")][assembly:System.Reflection.AssemblyInformationalVersion("'+$version.version+'")][assembly:System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.7.2")]'
$built=[Collections.Generic.List[string]]::new()
function Build-Assembly {
    param([string]$Name,[IO.FileInfo[]]$Files,[string[]]$Dependencies)
    $trees=[Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]]::new()
    $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($assemblyInfo,$parse,'AssemblyInfo.cs',[Text.Encoding]::UTF8))
    foreach($file in $Files){
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText($file.FullName),$parse,$relative,[Text.Encoding]::UTF8))
    }
    $moduleReferences=@()
    if($Name -match '\.Wpf$'){ $moduleReferences=@('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll','System.Xaml.dll','UIAutomationTypes.dll','UIAutomationProvider.dll') | ForEach-Object {[Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $ReferenceDirectory $_))} }
    $refs=@($references)+@($moduleReferences)+@($Dependencies | ForEach-Object {[Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($_)})
    $compilation=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create($Name,$trees.ToArray(),[Microsoft.CodeAnalysis.MetadataReference[]]$refs,$options)
    $path=Join-Path $OutputDirectory ($Name+'.dll')
    $stream=[IO.MemoryStream]::new()
    try{
        $result=$compilation.Emit($stream)
        $problems=@($result.Diagnostics | Where-Object {$_.Severity -in @('Error','Warning')})
        if(-not $result.Success -or $problems.Count){throw (($problems | ForEach-Object {$_.ToString()}) -join "`n")}
        [IO.File]::WriteAllBytes($path,$stream.ToArray())
    }finally{$stream.Dispose()}
    $built.Add($path)
    return $path
}
foreach($module in $version.modules){
    $files=@(Get-ChildItem -LiteralPath (Join-Path $root ('src/'+$module)) -Recurse -Filter '*.cs' | Sort-Object FullName)
    if(-not $files.Count){continue}
    $deps=@();$core=Join-Path $OutputDirectory 'M4D.Admin.Common.Core.dll'
    if($module -ne 'Core' -and (Test-Path -LiteralPath $core)){$deps=@($core)}
    [void](Build-Assembly -Name ('M4D.Admin.Common.'+$module) -Files $files -Dependencies $deps)
}
if($Tests){
    $runtime=@($built.ToArray())
    foreach($module in $version.modules){
        if(-not(Test-Path -LiteralPath (Join-Path $root ('tests/'+$module)))){continue}
        $files=@(Get-ChildItem -LiteralPath (Join-Path $root ('tests/'+$module)) -Recurse -Filter '*.cs' | Sort-Object FullName)
        if($files.Count){[void](Build-Assembly -Name ('M4D.Admin.Common.Tests.'+$module) -Files $files -Dependencies $runtime)}
    }
}
$sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -Filter '*.cs' | ForEach-Object {$_.FullName})+@((Join-Path $root 'version.json'),$PSCommandPath)
$sourceLines=@($sources | Sort-Object -CaseSensitive | ForEach-Object {
    [IO.Path]::GetRelativePath($root,$_).Replace('\','/')+"`0"+(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
})
$sourceDigest=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($sourceLines -join "`n")+"`n"))
$compilerPath=Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll'
$manifest=[ordered]@{Schema=1;Version=$version.version;Repository='https://github.com/M4D135/m4d-admin-common';SourceSHA256=[Convert]::ToHexString($sourceDigest).ToLowerInvariant();TargetFramework='net472';LanguageVersion='CSharp5';Builder=[ordered]@{PowerShell=$PSVersionTable.PSVersion.ToString();Roslyn=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation].Assembly.GetName().Version.ToString();CompilerSHA256=(Get-FileHash -LiteralPath $compilerPath -Algorithm SHA256).Hash.ToLowerInvariant();ReferencePackage='Microsoft.NETFramework.ReferenceAssemblies.net472/1.0.3'};Files=@()}
foreach($file in $built){$manifest.Files+=@{Name=[IO.Path]::GetFileName($file);SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();Bytes=(Get-Item -LiteralPath $file).Length}}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding utf8NoBOM
$manifest | ConvertTo-Json -Depth 5
