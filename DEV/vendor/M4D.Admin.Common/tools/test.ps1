#requires -Version 7.4
# Executes the compiled net472 pure-library tests on this host. No Windows, AD or VM.
param([string]$BundleDirectory='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'dist'}
$manifest=Get-Content -LiteralPath (Join-Path $BundleDirectory 'manifest.json') -Raw | ConvertFrom-Json
$results=@()
foreach($file in $manifest.Files){
    $path=Join-Path $BundleDirectory $file.Name
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256){throw "Hash mismatch: $($file.Name)"}
    if($file.Name -notmatch '\.Wpf\.dll$' -or $IsWindows){[void][Reflection.Assembly]::LoadFrom($path)}
}
foreach($file in $manifest.Files | Where-Object {$_.Name -like 'M4D.Admin.Common.Tests.*.dll'}){
    $assembly=[Reflection.Assembly]::LoadFrom((Join-Path $BundleDirectory $file.Name))
    $entries=@($assembly.GetExportedTypes() | ForEach-Object {$_.GetMethod('Run',[Reflection.BindingFlags]'Public,Static')} | Where-Object {$_ -and $_.GetParameters().Count -eq 0})
    if($entries.Count -ne 1){throw "Expected exactly one public static Run() in $($file.Name)."}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $checks=$entries[0].Invoke($null,$null)
    $watch.Stop()
    $results+=@{Module=$file.Name;Assertions=$checks;ElapsedMilliseconds=$watch.ElapsedMilliseconds;SHA256=$file.SHA256}
}
if(-not $results.Count){throw 'No compiled tests. Build with -Tests first.'}
[ordered]@{Status='PASS';Version=$manifest.Version;Host=$PSVersionTable.OS;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();CompilationTarget=$manifest.TargetFramework;ExecutionLimit='Pure logic on this host; Windows PowerShell 5.1, WPF and AD were not executed.';Results=$results} | ConvertTo-Json -Depth 5
