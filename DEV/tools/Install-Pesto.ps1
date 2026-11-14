#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceDirectory='',
    [Parameter(Mandatory)][string]$Destination,
    [string]$ConfigPath=''
)
$ErrorActionPreference='Stop'
if(-not $SourceDirectory){$SourceDirectory=Split-Path $PSScriptRoot -Parent}
$source=[IO.Path]::GetFullPath($SourceDirectory).TrimEnd([char[]]@('/','\'))
$target=[IO.Path]::GetFullPath($Destination).TrimEnd([char[]]@('/','\'))
function Assert-PlainInstallPath {
    param([string]$Path)
    $current=$Path
    while($current){
        if(Test-Path -LiteralPath $current){
            if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation refusée : lien ou jonction dans un chemin.'}
        }
        $next=[IO.Path]::GetDirectoryName($current);if($next -eq $current){break};$current=$next
    }
}
Assert-PlainInstallPath $source;Assert-PlainInstallPath $target
if(Test-Path -LiteralPath $target){throw 'La destination existe. Utilisez la mise à jour ou choisissez un nouveau dossier.'}
if($target -ieq $source -or $target.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'La destination doit être située hors des sources.'}
$parent=[IO.Path]::GetDirectoryName($target)
if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Le dossier parent doit exister. Ses droits ne seront pas modifiés.'}
# Import only the two manifest checker definitions. Do not start Pesto.
$tokens=$null;$errors=$null
$integrity=Join-Path $source 'wad/Pesto-Integrity.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($integrity,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Le contrôle de cohérence du paquet est invalide.'}
foreach($name in @('Get-PestoRuntimeFiles','Test-PestoPackage')){
    $node=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name})
    if($node.Count -ne 1){throw ('Contrôle manquant : '+$name)}
    Set-Item -Path ('Function:'+ $name) -Value $node[0].Body.GetScriptBlock()
}
$proof=Test-PestoPackage -Root $source
if(-not $ConfigPath){$ConfigPath=Join-Path $source 'wad/cfg.json'}
$ConfigPath=[IO.Path]::GetFullPath($ConfigPath);Assert-PlainInstallPath $ConfigPath
if((Get-Item -LiteralPath $ConfigPath).Length -gt 1MB){throw 'Le fichier de configuration dépasse 1 Mio.'}
$config=[IO.File]::ReadAllText($ConfigPath,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop
if($null -eq $config -or $config -is [array] -or $config -is [string] -or $config -is [ValueType]){throw 'Objet JSON de configuration attendu.'}
$temp=Join-Path $parent ('.pesto-install-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try{
    foreach($relative in @((Get-PestoRuntimeFiles))+@('wad/package.json','wad/support/DEBLOQUER_TOUT.cmd')){
        $origin=Join-Path $source $relative;Assert-PlainInstallPath $origin
        $path=Join-Path $temp $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::Copy($origin,$path,$false)
    }
    [IO.File]::Copy($ConfigPath,(Join-Path $temp 'wad/cfg.json'),$false)
    [void](Test-PestoPackage -Root $temp)
    Assert-PlainInstallPath $parent
    # Same-parent rename retains inherited rights and refuses an existing target.
    [IO.Directory]::Move($temp,$target)
    [pscustomobject]@{Installed=$true;Destination=$target;RuntimeFiles=$proof.FileCount;Version=$proof.Version;Configuration='Copiée sans modification';ParentPermissions='Inchangées';WindowsExecuted=$false;ADExecuted=$false}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
