#requires -Version 5.1
# Cohérence du code distribué. Ce manifeste local n'est pas une signature.
function Get-PestoRuntimeFiles {
    # Liste fermée des composants applicatifs. Ne pas ajouter d'outil de développement.
    # BEGIN Pesto_RUNTIME_FILES
    @(
        'Pesto.exe',
        'wad/ActiveDirectory.Format.ps1xml',
        'wad/ActiveDirectory.Types.ps1xml',
        'wad/ActiveDirectory.psd1',
        'wad/ActiveDirectoryPowerShellResources.dll',
        'wad/Pesto-Appearance.ps1',
        'wad/Pesto-Async.ps1',
        'wad/Pesto-AuditSink.ps1',
        'wad/Pesto-Automation.ps1',
        'wad/Pesto-Enterprise.ps1',
        'wad/Pesto-Extensions.ps1',
        'wad/Invoke-PestoExtension.ps1',
        'wad/Pesto-Catalogue.ps1',
        'wad/Pesto-ConfigEditor.ps1',
        'wad/Pesto-Diagnostics.ps1',
        'wad/Pesto-EngineContracts.ps1',
        'wad/Pesto-NameWorkbench.ps1',
        'wad/Pesto-ReceiptTools.ps1',
        'wad/Pesto-Workbench.ps1',
        'wad/Pesto-BatchTools.ps1',
        'wad/Pesto-Collections.ps1',
        'wad/Pesto.Engine.Runtime.ps1',
        'wad/Pesto.Engine.psm1',
        'wad/Pesto.Engine.psd1',
        'wad/Pesto.Engine.build.json',
        'wad/Invoke-Pesto.ps1',
        'wad/Pesto-CliHost.ps1',
        'wad/Invoke-PestoAutoJoin.ps1',
        'wad/Pesto-Authentication.ps1',
        'wad/Pesto-Configuration.ps1',
        'wad/Pesto-Contracts.ps1',
        'wad/Pesto-Common.ps1',
        'wad/common.lock.json',
        'wad/M4D.Admin.Common.Core.dll',
        'wad/M4D.Admin.Common.Query.dll',
        'wad/M4D.Admin.Common.IO.dll',
        'wad/M4D.Admin.Common.Diagnostics.dll',
        'wad/Pesto-JoinRecovery.ps1',
        'wad/Pesto-UXFlow.ps1',
        'wad/Pesto-Policy.ps1',
        'wad/Pesto-ManagedPolicy.ps1',
        'wad/Pesto-Names.ps1',
        'wad/Pesto-LogWriter.cs',
        'wad/Pesto.Runtime.dll',
        'wad/Pesto-Workspace.ps1',
        'wad/Pesto-Review.ps1',
        'wad/Pesto-Tables.ps1',
        'wad/Pesto-Recovery.ps1',
        'wad/Pesto-Core.ps1',
        'wad/Pesto-Direct.ps1',
        'wad/Pesto-Directory.ps1',
        'wad/Pesto-Inspection.ps1',
        'wad/Pesto-Integrity.ps1',
        'wad/Pesto-Join.ps1',
        'wad/Pesto-Join.xaml',
        'wad/Pesto-Journal.ps1',
        'wad/Pesto-Operations.ps1',
        'wad/Pesto-Shell.xaml',
        'wad/Pesto-Safety.ps1',
        'wad/Pesto-Interventions.ps1',
        'wad/Pesto-Preparation.ps1',
        'wad/Pesto-Startup.ps1',
        'wad/Pesto-SuiteUI.ps1',
        'wad/Pesto-Support.ps1',
        'wad/Microsoft.ActiveDirectory.Management.dll',
        'wad/fr-FR/ActiveDirectoryPowerShellResources.dll.mui',
        'wad/Pesto.ico'
    )
    # END Pesto_RUNTIME_FILES
}

function Test-PestoPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Root)
    $separator=[IO.Path]::DirectorySeparatorChar
    $rootPath=[IO.Path]::GetFullPath($Root)
    if($rootPath.Length -gt [IO.Path]::GetPathRoot($rootPath).Length){$rootPath=$rootPath.TrimEnd([char[]]@('\','/'))}
    $rootPrefix=$rootPath.TrimEnd([char[]]@('\','/'))+$separator
    if(Test-Path -LiteralPath (Join-Path $rootPath '.pesto-update.lock') -ErrorAction Stop){throw 'Mise à jour en cours ou interrompue : examiner la reprise avant tout lancement. Aucun verrou effacé.'}
    $manifestPath=Join-Path (Join-Path $rootPath 'wad') 'package.json'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
        throw 'Manifeste applicatif absent (wad/package.json). Recopier tous les composants de la même version.'
    }
    # Contrôle limité aux fichiers explicitement requis, sans parcours récursif du dossier.
    foreach($path in @((Join-Path $rootPath 'wad'),$manifestPath)){
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Lien ou jonction interdit dans le chemin du manifeste.'}
    }
    $manifestItem=Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
    if($manifestItem.Length -gt 262144){throw 'Manifeste applicatif trop volumineux.'}
    $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $required=@(Get-PestoRuntimeFiles)
    if($m.Schema -ne 2 -or $m.Version -ne '1.0' -or $m.Scope -cne 'Runtime' -or @($m.Files).Count -ne $required.Count){
        throw 'Manifeste applicatif incompatible. Utiliser le manifeste livré avec cette version, sans mélanger les fichiers.'
    }
    $expected=@{};foreach($name in $required){$expected[$name]=$true}
    $seen=@{};$fail=[Collections.Generic.List[string]]::new()
    foreach($entry in @($m.Files)){
        $relative=[string]$entry.Path
        if(-not $expected.ContainsKey($relative) -or $seen.ContainsKey($relative)){
            throw ('Composant inattendu ou répété dans le manifeste applicatif : '+$relative)
        }
        if([string]$entry.SHA256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Empreinte du manifeste invalide.'}
        $seen[$relative]=$true
        $path=[IO.Path]::GetFullPath((Join-Path $rootPath $relative.Replace('/',[string]$separator)))
        if(-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Chemin sortant du paquet.'}
        $parent=$path
        while($parent -and $parent.Length -gt $rootPath.Length){
            if(Test-Path -LiteralPath $parent){
                if((Get-Item -LiteralPath $parent -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){
                    throw ('Lien ou jonction interdit pour le composant : '+$relative)
                }
            }
            $parent=[IO.Path]::GetDirectoryName($parent)
        }
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$fail.Add('Absent : '+$relative);continue}
        $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if($actual -ine [string]$entry.SHA256){$fail.Add('Version mélangée ou fichier modifié : '+$relative)}
    }
    foreach($name in $required){
        if(-not $seen.ContainsKey($name)){throw ('Composant essentiel absent du manifeste : '+$name)}
    }
    if($fail.Count){
        throw (($fail -join "`r`n")+"`r`nRéinstaller les composants applicatifs de la même version. Conserver la configuration, les journaux et les états d'opération. Ce contrôle ne lance aucune opération métier.")
    }
    [pscustomobject]@{
        Valid=$true;Version=$m.Version;Scope='Runtime';FileCount=$seen.Count
        Notice='Code cohérent avec le manifeste local. Démos, tests, documentation et outils de fabrication exclus. Configuration et droits AD non validés par ce contrôle.'
    }
}


function Get-PestoEmbeddedScriptSamples {
    # Scripts construits à l'exécution : valeurs témoins inertes, seules les fonctions de construction sont évaluées.
    param([Parameter(Mandatory=$true)][string]$OperationsPath)
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($OperationsPath,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){return @()}
    $wanted=@('New-PestoElevatedHelperScript','New-PestoRenameTaskScript','Invoke-PestoDsregLeaveLocal')
    $definitions=@{}
    foreach($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)){
        if($wanted -contains $f.Name){$definitions[$f.Name]=$f}
    }
    foreach($name in $wanted){if(-not $definitions.ContainsKey($name)){throw ('Fonction de construction absente : '+$name)}}
    # param() doit être la première instruction du bloc : placé après les fonctions, PowerShell
    # l'exécuterait comme une commande « param » introuvable et Pesto refuserait de démarrer.
    $build=[scriptblock]::Create('param($Dsreg)'+"`n"+$definitions['New-PestoElevatedHelperScript'].Extent.Text+"`n"+$definitions['New-PestoRenameTaskScript'].Extent.Text+"`n"+@'
$settings=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"Action":"Join"}'))
[pscustomobject]@{Name='helper élevé (jonction)';Text=(New-PestoElevatedHelperScript -SettingsB64 $settings -DsregFunction '')}
[pscustomobject]@{Name='helper élevé (renommage)';Text=(New-PestoElevatedHelperScript -SettingsB64 $settings -DsregFunction $Dsreg)}
[pscustomobject]@{Name='tâche de renommage';Text=(New-PestoRenameTaskScript -NewLiteral "'PESTO-CHECK01'" -LogLiteral "'C:\ProgramData\Pesto\rename_check.log'")}
'@)
    $dsreg=$definitions['Invoke-PestoDsregLeaveLocal'].Extent.Text
    return @(& $build $dsreg)
}

function Get-PestoDotNetFloorStatus {
    [CmdletBinding()]
    param([Nullable[int]]$Release)
    $supported=$false
    $version='<4.6.2'
    $known=$false
    if($Release){
        $known=$true
        if($Release -ge 533320){$version='4.8.1';$supported=$true}
        elseif($Release -ge 528040){$version='4.8';$supported=$true}
        elseif($Release -ge 461808){$version='4.7.2';$supported=$true}
        elseif($Release -ge 461308){$version='4.7.1';$supported=$false}
        elseif($Release -ge 460798){$version='4.7';$supported=$false}
        elseif($Release -ge 394802){$version='4.6.2';$supported=$false}
        else{$version='<4.6.2';$supported=$false}
    }
    return [pscustomobject]@{Supported=$supported;Version=$version;Known=$known}
}

function Test-PestoRuntimeReady {
    <# Contrôle avant connexion : vrai parseur PowerShell sur chaque script d'exécution
       et sur les scripts embarqués, puis compilation du writer d'audit. Aucun code métier exécuté. #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Root)
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'))
    $fail=[Collections.Generic.List[string]]::new();$parsed=0
    
    $dotNetRelease=$null
    try {
        $key='HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
        if(Test-Path -LiteralPath $key){
            $dotNetRelease=(Get-ItemProperty -LiteralPath $key -Name 'Release' -ErrorAction Stop).Release
        }
    } catch { $dotNetRelease=$null }
    
    $dotNetStatus=Get-PestoDotNetFloorStatus -Release $dotNetRelease
    if($dotNetStatus.Known -and -not $dotNetStatus.Supported){
        throw ('Pesto 1.0 exige .NET Framework 4.7.2 ou plus récent (détecté : '+$dotNetStatus.Version+'). Aucune action effectuée.')
    }
    foreach($relative in @(Get-PestoRuntimeFiles|Where-Object{$_ -match '\.(ps1|psm1|psd1)$'})){
        $path=Join-Path $rootPath $relative.Replace('/',[string][IO.Path]::DirectorySeparatorChar)
        $tokens=$null;$errors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        $parsed++
        foreach($e in @($errors)){$fail.Add(('{0}:{1}:{2} {3}' -f $relative,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message))}
    }
    $embedded=0
    if(-not $fail.Count){
        try{
            foreach($sample in @(Get-PestoEmbeddedScriptSamples -OperationsPath (Join-Path (Join-Path $rootPath 'wad') 'Pesto-Operations.ps1'))){
                $tokens=$null;$errors=$null
                [void][System.Management.Automation.Language.Parser]::ParseInput([string]$sample.Text,[ref]$tokens,[ref]$errors)
                $embedded++
                foreach($e in @($errors)){$fail.Add(('Script embarqué « {0} » ligne {1}:{2} {3}' -f $sample.Name,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message))}
            }
        }catch{$fail.Add('Scripts embarqués non vérifiables : '+$_.Exception.Message)}
        if($embedded -ne 3 -and -not $fail.Count){$fail.Add("Scripts embarqués : 3 attendus, $embedded analysés.")}
    }
    $writer='NOT_RUN'
    if(-not $fail.Count){
        try{
            . (Join-Path (Join-Path $rootPath 'wad') 'Pesto-Common.ps1')
            Initialize-PestoRuntimeTypes -Root (Join-Path $rootPath 'wad')
            $writer='PASS'
        }catch{$writer='FAIL';$fail.Add('Bibliotheque du journal d''audit non verifiee (wad\Pesto.Runtime.dll) : '+$_.Exception.Message)}
    }
    if($fail.Count){
        throw ("Contrôle avant connexion en échec. Pesto ne démarre pas.`r`n"+($fail -join "`r`n")+"`r`nRéinstaller les composants de la même version ; aucun accès AD ni demande UAC n'a eu lieu.")
    }
    [pscustomobject]@{Valid=$true;ParsedFiles=$parsed;EmbeddedScripts=$embedded;AuditWriter=$writer;DotNetStatus=$dotNetStatus}
}
