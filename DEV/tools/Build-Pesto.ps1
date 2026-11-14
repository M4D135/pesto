#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory,[string]$PythonPath='')
# Recompilation hors ligne du lanceur natif. Executer depuis Developer PowerShell
# (MSVC + Windows SDK). Aucun PS2EXE, NuGet, telechargement ni script AD execute.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'wad\Pesto-Integrity.ps1')
# Le manifeste précédent ne peut pas valider des sources en cours de recompilation.
# La liste fermée est vérifiée, puis les nouvelles empreintes sont compilées et contrôlées.
$required=@(Get-PestoRuntimeFiles)
foreach($rel in $required){if($rel -ne 'Pesto.exe' -and -not(Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)){throw ('Composant absent : '+$rel)}}
$pythonArgs=@()
if($PythonPath){$python=Get-Command $PythonPath -ErrorAction Stop}else{
    $python=Get-Command python.exe -ErrorAction SilentlyContinue
    if(-not $python){$python=Get-Command py.exe -ErrorAction Stop;$pythonArgs=@('-3')}
}
& $python.Source @pythonArgs (Join-Path $PSScriptRoot 'launcher\generate_binding.py')
if($LASTEXITCODE -ne 0){throw 'Génération des empreintes natives impossible.'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root ('dist\Pesto-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$OutputDirectory=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $OutputDirectory){throw 'Le dossier de sortie existe : aucun ecrasement automatique.'}
$cl=Get-Command cl.exe -ErrorAction SilentlyContinue
$rc=Get-Command rc.exe -ErrorAction SilentlyContinue
$link=Get-Command link.exe -ErrorAction SilentlyContinue
if(-not $cl -or -not $rc -or -not $link){throw 'Ouvrir Developer PowerShell for VS x64 (MSVC et Windows SDK). Le Pesto.exe fourni ne necessite pas ces outils.'}
$src=Join-Path $PSScriptRoot 'launcher'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-build-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tmp)
try {
    $manifest=(Join-Path $src 'Pesto.manifest').Replace('\','\\')
    $icon=(Join-Path $root 'wad\Pesto.ico').Replace('\','\\')
    $resource=@"
1 24 "$manifest"
1 ICON "$icon"
1 VERSIONINFO
 FILEVERSION 1,0,0,0
 PRODUCTVERSION 1,0,0,0
 FILEFLAGSMASK 0x3fL
 FILEFLAGS 0
 FILEOS 0x40004L
 FILETYPE 1
 FILESUBTYPE 0
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904B0"
  BEGIN
   VALUE "FileDescription", "Pesto (launcher)\0"
   VALUE "FileVersion", "1.0.0.0\0"
   VALUE "ProductName", "Pesto\0"
   VALUE "ProductVersion", "1.0\0"
   VALUE "OriginalFilename", "Pesto.exe\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x409, 1200
 END
END
"@
    $resource|Set-Content -LiteralPath (Join-Path $tmp 'Pesto.rc') -Encoding Unicode
    & $rc.Source /nologo /fo (Join-Path $tmp 'Pesto.res') (Join-Path $tmp 'Pesto.rc')
    if($LASTEXITCODE -ne 0){throw 'Echec compilation des ressources.'}
    & $cl.Source /nologo /TC /c /O1 /GS- /Zl /Fo:"$tmp\Pesto.obj" (Join-Path $src 'Pesto-launcher.c')
    if($LASTEXITCODE -ne 0){throw 'Echec compilation C x64.'}
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    & $link.Source /nologo /MACHINE:X64 /ENTRY:PestoEntry /SUBSYSTEM:WINDOWS /NODEFAULTLIB /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /OUT:"$OutputDirectory\Pesto.exe" "$tmp\Pesto.obj" "$tmp\Pesto.res" kernel32.lib user32.lib shell32.lib
    if($LASTEXITCODE -ne 0){throw 'Echec edition de liens.'}
    # Copier uniquement les composants connus du paquet, jamais les états ou journaux.
    foreach($rel in $required){
        if($rel -eq 'Pesto.exe'){continue}
        if($rel -notmatch '^(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$' -or $rel -match '(^|/)\.\.?(/|$)'){throw 'Manifeste invalide.'}
        $target=Join-Path $OutputDirectory $rel
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $target
    }
    Copy-Item -LiteralPath (Join-Path $root 'wad\cfg.json') -Destination (Join-Path $OutputDirectory 'wad')
    [void][IO.Directory]::CreateDirectory((Join-Path $OutputDirectory 'wad\support'))
    Copy-Item -LiteralPath (Join-Path $root 'wad\support\DEBLOQUER_TOUT.cmd') -Destination (Join-Path $OutputDirectory 'wad\support')
    & $python.Source @pythonArgs (Join-Path $PSScriptRoot 'refresh_manifest.py') --root $OutputDirectory
    if($LASTEXITCODE -ne 0){throw 'EXE et composants non concordants.'}
    Write-Host ('EXE compile : '+(Join-Path $OutputDirectory 'Pesto.exe'))
    Write-Warning 'Non signe. Compilation ne vaut pas validation de Windows/WPF/UAC/AD. Conserver Pesto.exe et wad.'
} finally {Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
