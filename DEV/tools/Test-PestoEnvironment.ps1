#requires -Version 5.1
[CmdletBinding()]
param([string]$Root=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Inventaire Windows requis ; aucune compatibilité n''est déduite sur un autre système.'}
if(Test-Path -LiteralPath $ReportPath){throw 'Rapport existant : choisir une nouvelle destination.'}
# Read metadata only. Include resource DLLs, MUI and module manifests; never load RSAT.
$components=@(Get-ChildItem -LiteralPath (Join-Path $Root 'wad') -Recurse -File | Where-Object {
 $_.Name -match '^(Microsoft\.ActiveDirectory\.Management\.dll|ActiveDirectory(?:PowerShellResources\.dll(?:\.mui)?|\.(?:psd1|Format\.ps1xml|Types\.ps1xml))|M4D\.Admin\.Common\.[A-Za-z]+\.dll)$'
} | Sort-Object FullName | ForEach-Object {
 if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked component refused.'}
 $signature=Get-AuthenticodeSignature -LiteralPath $_.FullName
 $relative=$_.FullName.Substring(([IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar).Length).Replace('\','/')
 [pscustomobject]@{Name=$relative;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;
 FileVersion=$_.VersionInfo.FileVersion;ProductVersion=$_.VersionInfo.ProductVersion;Signature=[string]$signature.Status;
 Signer=if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{$null};
 SignerThumbprint=if($signature.SignerCertificate){$signature.SignerCertificate.Thumbprint}else{$null};
 TimestampSigner=if($signature.TimeStamperCertificate){$signature.TimeStamperCertificate.Subject}else{$null};
 OriginalPackage='NOT_DOCUMENTED';RedistributionRights='NOT_ATTESTED'}
})
$policies=@();$ci=Join-Path $env:windir 'System32\CiTool.exe'
if(Test-Path -LiteralPath $ci){$policies=@(& $ci -lp -json 2>&1);if($LASTEXITCODE -ne 0){$policies=@('UNAVAILABLE')}}
$dotNetRelease=$null
try {
    $key='HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    if(Test-Path -LiteralPath $key){
        $dotNetRelease=(Get-ItemProperty -LiteralPath $key -Name 'Release' -ErrorAction Stop).Release
    }
} catch { $dotNetRelease=$null }

$dotNetVersion='<4.6.2'
if($dotNetRelease){
    if($dotNetRelease -ge 533320){$dotNetVersion='4.8.1'}
    elseif($dotNetRelease -ge 528040){$dotNetVersion='4.8'}
    elseif($dotNetRelease -ge 461808){$dotNetVersion='4.7.2'}
    elseif($dotNetRelease -ge 461308){$dotNetVersion='4.7.1'}
    elseif($dotNetRelease -ge 460798){$dotNetVersion='4.7'}
    elseif($dotNetRelease -ge 394802){$dotNetVersion='4.6.2'}
}

$report=[ordered]@{Schema=1;PowerShell=$PSVersionTable.PSVersion.ToString();Edition=$PSVersionTable.PSEdition;Culture=[Globalization.CultureInfo]::CurrentCulture.Name;UICulture=[Globalization.CultureInfo]::CurrentUICulture.Name;LanguageMode=[string]$ExecutionContext.SessionState.LanguageMode;Windows=[Environment]::OSVersion.VersionString;ClrVersion=[Environment]::Version.ToString();DotNetRelease=$dotNetRelease;DotNetVersion=$dotNetVersion;Process64Bit=[Environment]::Is64BitProcess;Components=$components;AppControlReadOnly=$policies;ADExecuted=$false;PolicyChanged=$false;Compatibility='Not inferred from this inventory: execute the qualified scenarios under the intended policy.'}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 8))
$stream=[IO.File]::Open($ReportPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
