#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot='',
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('PROD','DEV','BOTH')][string]$Channel='BOTH',
    # Publier un wad/cfg.json différent du modèle non configuré : choix délibéré uniquement.
    [switch]$AllowConfig
)
# Création de nouveaux dossiers et archives. Aucune mise à jour de l'installation source.
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path -Parent $PSScriptRoot}
# Chemins relatifs résolus depuis le dossier courant PowerShell, pas celui du processus.
$SourceRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceRoot).TrimEnd('\','/')
$OutputDirectory=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory).TrimEnd('\','/')
if(Test-Path -LiteralPath $OutputDirectory){throw 'La sortie existe déjà. Choisir un nouveau dossier ; aucun écrasement automatique.'}
if($OutputDirectory -ieq $SourceRoot -or $OutputDirectory.StartsWith($SourceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Choisir une sortie en dehors du dossier source.'
}
# Le chemin lexical ne suffit pas : une jonction parente pourrait revenir dans la source.
$destinationAncestor=$OutputDirectory
while($destinationAncestor){
    if(Test-Path -LiteralPath $destinationAncestor){
        $destinationItem=Get-Item -LiteralPath $destinationAncestor -Force -ErrorAction Stop
        if($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Lien ou jonction interdit dans le chemin de sortie.'}
    }
    $destinationAncestor=[IO.Path]::GetDirectoryName($destinationAncestor)
}
. (Join-Path $SourceRoot 'wad/Pesto-Integrity.ps1')
[void](Test-PestoPackage -Root $SourceRoot)
$template=Join-Path $SourceRoot 'tools/cfg.template.json'
$config=Join-Path $SourceRoot 'wad/cfg.json'
if(-not $AllowConfig){
    if(-not (Test-Path -LiteralPath $template -PathType Leaf) -or -not (Test-Path -LiteralPath $config -PathType Leaf)){throw 'Modèle ou wad/cfg.json absent : lancer tools/prepare_dev.py.'}
    $same=[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($template),[byte[]][IO.File]::ReadAllBytes($config))
    if(-not $same){throw 'wad/cfg.json diffère du modèle non configuré : une configuration réelle serait publiée. Utiliser un DEV propre ou -AllowConfig délibérément.'}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$channels=if($Channel -eq 'BOTH'){@('PROD','DEV')}else{@($Channel)}
foreach($kind in $channels){
    $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($rel in @(Get-PestoRuntimeFiles)+@('wad/package.json','wad/cfg.json','wad/support/DEBLOQUER_TOUT.cmd')){[void]$files.Add($rel)}
    if($kind -eq 'DEV'){
        foreach($rel in @('LIRE_MOI.txt','.gitignore','.gitattributes','pytest.ini','README.md','CHANGELOG.md','Pesto.cmd','Pesto_COMPTE_AD.cmd','DEMO.cmd','DEMO_DOMAINE.cmd','APERCU_LOGIN.cmd','ETAT_RENOMMAGE.cmd','TESTER.cmd','VERIFIER_PACK.cmd','TEST_DISTRIBUTION.cmd','FABRIQUER_PACKS.cmd','FABRIQUER_PROD.cmd','wad/cfg.demo.json','wad/cfg.example.json')){[void]$files.Add($rel)}
        if(Test-Path -LiteralPath (Join-Path $SourceRoot 'wad/Pesto.Engine.exports.json') -PathType Leaf){[void]$files.Add('wad/Pesto.Engine.exports.json')}
        foreach($mask in @('TEST*.cmd','VERIFIER*.cmd')){
            foreach($item in Get-ChildItem -LiteralPath $SourceRoot -Filter $mask -File){[void]$files.Add($item.Name)}
        }
        foreach($folder in @('vendor','tools','tests','docs','changes','integrations','.github','wad/maintenance','wad/docs','src')){
            $base=Join-Path $SourceRoot $folder
            if(-not(Test-Path -LiteralPath $base -PathType Container)){continue}
            if((Get-Item -LiteralPath $base -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Dossier lié interdit : '+$folder)}
            foreach($item in Get-ChildItem -LiteralPath $base -Recurse -Force){
                if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Lien interdit : '+$item.FullName)}
                if($item.PSIsContainer){continue}
                $rel=$item.FullName.Substring($SourceRoot.Length+1).Replace('\','/')
                if($rel -match '(^|/)(__pycache__|\.git|\.build|dist|logs|results|historique_rc18)(/|$)'){continue}
                if($item.Name -match '^(windows-|pesto-etat-|pesto_etat_|gp-etat-|gp_etat_)'){continue}
                # Les rapports statiques citent les domaines de la configuration privée.
                if($item.Name -match 'static-report'){continue}
                if($item.Extension -in @('.cs','.py','.ps1','.psm1','.psd1','.admx','.adml','.c','.h','.manifest','.md','.txt','.json','.yml','.yaml','.patch','.rc','.cmd') -or $rel -cmatch '^docs/Pesto-1\.0-Guide-(technicien|administrateur)\.(docx|pdf)$'){[void]$files.Add($rel)}
            }
        }
    }
    $dest=Join-Path $OutputDirectory $kind
    [void][IO.Directory]::CreateDirectory($dest)
    foreach($rel in $files|Sort-Object){
        if($rel -notmatch '^(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$' -or $rel -match '(^|/)\.\.?(/|$)'){throw 'Chemin de distribution invalide.'}
        $item=Get-Item -LiteralPath (Join-Path $SourceRoot $rel) -Force -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ('Fichier absent ou lié : '+$rel)}
        $parent=$item.Directory
        while($parent -and $parent.FullName.Length -gt $SourceRoot.Length){
            if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Jonction interdite dans la source.'}
            $parent=$parent.Parent
        }
        $target=Join-Path $dest $rel
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath $item.FullName -Destination $target -ErrorAction Stop
    }
    [void](Test-PestoPackage -Root $dest)
    if($kind -eq 'PROD'){
        $rootItems=@(Get-ChildItem -LiteralPath $dest -Force|Select-Object -ExpandProperty Name)
        if($rootItems.Count -ne 2 -or 'Pesto.exe' -notin $rootItems -or 'wad' -notin $rootItems){throw 'PROD doit contenir uniquement Pesto.exe et wad (DEBLOQUER_TOUT.cmd est dans wad\support).'}
    }
    $zip=Join-Path $OutputDirectory ('Pesto_1.0_'+$kind+'.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($dest,$zip,[IO.Compression.CompressionLevel]::Optimal,$true)
    Write-Host ('Pack '+$kind+' créé : '+$zip)
}
Write-Host 'Aucune compilation, authentification ou opération AD lancée. Les configurations copiées restent à adapter/valider.'
