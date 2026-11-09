#requires -Version 5.1
[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Fabrication explicite : jamais exécutée au démarrage de Pesto.
$ErrorActionPreference='Stop'
$Root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
. (Join-Path $Root 'wad/Pesto-Integrity.ps1')
$entries=@(foreach($rel in @(Get-PestoRuntimeFiles)){
    $path=Join-Path $Root $rel
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw ('Composant absent, répertoire ou lien : '+$rel)
    }
    $parent=$item.Directory
    while($parent -and $parent.FullName.Length -gt $Root.TrimEnd('\','/').Length){
        if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Jonction interdite dans le paquet.'}
        $parent=$parent.Parent
    }
    [pscustomobject]@{Path=$rel;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
})
$json=[pscustomobject]@{Schema=2;Version='1.0';Scope='Runtime';Files=$entries} | ConvertTo-Json -Depth 5
$path=Join-Path $Root 'wad/package.json'
if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
    throw 'Le manifeste ne peut pas être un lien.'
}
$temp=Join-Path ([IO.Path]::GetDirectoryName($path)) ('.package-'+[Guid]::NewGuid().ToString('N')+'.tmp')
try {
    [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($path)){
        [IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)
    } else {[IO.File]::Move($temp,$path)}
    $result=Test-PestoPackage -Root $Root
    Write-Host ('Manifeste applicatif : '+$result.FileCount+' composants. Démos, tests, CMD, configurations et états exclus.')
    Write-Host 'Ceci ne signe pas le programme et ne valide pas une opération AD.'
} finally {
    if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
}
