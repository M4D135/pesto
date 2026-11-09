#requires -Version 5.1
[CmdletBinding()]
param([string]$Root='',[string]$ReportDirectory)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $Root){$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)}
# Tests sur copies temporaires. Aucun moteur, login, UAC, WPF, réseau ou AD lancé.
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
if(-not $ReportDirectory){$ReportDirectory=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC18-Distribution-'+[Guid]::NewGuid().ToString('N'))}
[void][IO.Directory]::CreateDirectory($ReportDirectory)
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC18-Fixture-'+[Guid]::NewGuid().ToString('N'))
$fixture=Join-Path $workspace 'Pesto'
$results=[Collections.Generic.List[object]]::new()
function Assert-PestoD {param($Value,[string]$Message='Assertion en échec');if(-not $Value){throw $Message}}
function Expect-PestoDFailure {param([scriptblock]$Body);$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Assert-PestoD $failed 'Un échec était attendu.'}
function Case-PestoD {param([string]$Name,[scriptblock]$Body)
    try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('OK '+$Name)}
    catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('KO '+$Name+' : '+$_.Exception.Message)}
}
try {
    foreach($name in @('wad/Pesto-Startup.ps1','wad/Pesto-Integrity.ps1','tools/Update-PackageManifest.ps1','tools/New-PestoDistribution.ps1')){
        $file=Join-Path $Root $name
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)){
            if($name -like 'tools/*'){continue}
            throw ('Composant de test absent : '+$name)
        }
        Case-PestoD ('Parseur PowerShell : '+$name) {
            $tokens=$null;$errors=$null
            [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            Assert-PestoD (@($errors).Count -eq 0) (($errors | ForEach-Object{$_.Message}) -join '; ')
        }
    }
    . (Join-Path $Root 'wad/Pesto-Integrity.ps1')
    $required=@(Get-PestoRuntimeFiles)
    Case-PestoD 'Contrôle applicatif du dossier source' {
        $p=Test-PestoPackage -Root $Root
        Assert-PestoD ($p.Valid -and $p.Version -eq '17.0-RC18' -and $p.Scope -eq 'Runtime' -and $p.FileCount -eq 25)
    }
    Case-PestoD 'Liste fermée sans tests, démos, CMD/BAT ni configuration' {
        Assert-PestoD ($required.Count -eq 25)
        Assert-PestoD (-not($required | Where-Object{$_ -match '(?i)(\.cmd$|\.bat$|/cfg|/maintenance/|^tools/|^tests/|/docs/)'}))
    }
    [void][IO.Directory]::CreateDirectory($fixture)
    foreach($name in $required+@('wad/package.json')){
        $target=Join-Path $fixture $name
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath (Join-Path $Root $name) -Destination $target
    }
    Case-PestoD 'Runtime seul : aucune aide, aucun CMD, aucune configuration pour le contrôle' {
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $fixture 'DEMO.cmd')))
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $fixture 'wad/maintenance')))
        Assert-PestoD (Test-PestoPackage -Root $fixture).Valid
    }
    foreach($name in @('DEMO.cmd','DEMO_DOMAINE.cmd','TESTER.cmd','VERIFIER_PACK.cmd','Pesto.cmd','Pesto_COMPTE_AD.cmd','DEBLOQUER_TOUT.cmd','LIRE_MOI.txt','README.md','wad/cfg.demo.json','wad/cfg.json','wad/maintenance/Test-Pesto16.ps1','tests/local.txt','tools/local.py')){
        Case-PestoD ('Fichier facultatif ajouté, modifié puis retiré : '+$name) {
            $target=Join-Path $fixture $name
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.File]::WriteAllText($target,'FICTIF : jamais exécuté.')
            Assert-PestoD (Test-PestoPackage -Root $fixture).Valid
            [IO.File]::WriteAllText($target,'Autre contenu fictif, sans effet sur le runtime.')
            Assert-PestoD (Test-PestoPackage -Root $fixture).Valid
            [IO.File]::Delete($target)
            Assert-PestoD (Test-PestoPackage -Root $fixture).Valid
        }
    }
    foreach($name in $required){
        Case-PestoD ('Absence refusée : '+$name) {
            $target=Join-Path $fixture $name;$bytes=[IO.File]::ReadAllBytes($target)
            try{[IO.File]::Delete($target);Expect-PestoDFailure {Test-PestoPackage -Root $fixture}}
            finally{[IO.File]::WriteAllBytes($target,$bytes)}
        }
        Case-PestoD ('Modification refusée : '+$name) {
            $target=Join-Path $fixture $name;$bytes=[IO.File]::ReadAllBytes($target)
            try{[IO.File]::WriteAllText($target,'COMPOSANT ALTERE POUR LE TEST');Expect-PestoDFailure {Test-PestoPackage -Root $fixture}}
            finally{[IO.File]::WriteAllBytes($target,$bytes)}
        }
    }
    $manifestPath=Join-Path $fixture 'wad/package.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
    foreach($problem in @('Absent','JSON invalide','Version ancienne','Mauvais périmètre','Dépendance omise','Doublon','Démo ajoutée','Chemin extérieur','Empreinte invalide')){
        Case-PestoD ('Manifeste refusé : '+$problem) {
            try{
                $m=[Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
                switch($problem){
                    'Absent' {[IO.File]::Delete($manifestPath)}
                    'JSON invalide' {[IO.File]::WriteAllText($manifestPath,'{BROKEN')}
                    default {
                        switch($problem){
                            'Version ancienne' {$m.Version='17.0-RC15'}
                            'Mauvais périmètre' {$m.Scope='Development'}
                            'Dépendance omise' {$m.Files=@($m.Files|Select-Object -Skip 1)}
                            'Doublon' {$m.Files[1].Path=$m.Files[0].Path}
                            'Démo ajoutée' {$m.Files[0].Path='DEMO.cmd'}
                            'Chemin extérieur' {$m.Files[0].Path='../outside.txt'}
                            'Empreinte invalide' {$m.Files[0].SHA256='not-a-hash'}
                        }
                        [IO.File]::WriteAllText($manifestPath,($m|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
                    }
                }
                Expect-PestoDFailure {Test-PestoPackage -Root $fixture}
            } finally {[IO.File]::WriteAllBytes($manifestPath,$manifestBytes)}
        }
    }
    Case-PestoD 'Recontrôle après les altérations : fixture intacte' {Assert-PestoD (Test-PestoPackage -Root $fixture).Valid}
    Case-PestoD 'Fabrication PowerShell : PROD sans tests et runtime identique à DEV' {
        $output=Join-Path $workspace 'Export'
        & (Join-Path $Root 'tools/New-PestoDistribution.ps1') -SourceRoot $Root -OutputDirectory $output -Channel BOTH
        $prod=Join-Path $output 'PROD';$dev=Join-Path $output 'DEV'
        Assert-PestoD (Test-PestoPackage -Root $prod).Valid
        Assert-PestoD (Test-PestoPackage -Root $dev).Valid
        $prodRoot=@(Get-ChildItem -LiteralPath $prod -Force|Select-Object -ExpandProperty Name)
        Assert-PestoD ($prodRoot.Count -eq 3 -and 'Pesto.exe' -in $prodRoot -and 'wad' -in $prodRoot -and 'DEBLOQUER_TOUT.cmd' -in $prodRoot)
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $prod 'Pesto.ps1')))
        $cmd=[IO.File]::ReadAllText((Join-Path $prod 'DEBLOQUER_TOUT.cmd'))
        $marker='# Pesto_UNBLOCK_POWERSHELL_START'
        $offset=$cmd.LastIndexOf($marker,[StringComparison]::Ordinal)
        Assert-PestoD ($offset -ge 0) 'Bloc de deblocage absent.'
        $body=$cmd.Substring($offset+$marker.Length)
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
        Assert-PestoD (@($errors).Count -eq 0) 'Syntaxe du deblocage invalide.'
        Assert-PestoD (-not $body.Contains("'Pesto.ps1'")) 'Ancienne dependance Pesto.ps1 dans le deblocage.'
        foreach($channel in @('PROD','DEV')){
            $archive=[IO.Compression.ZipFile]::OpenRead((Join-Path $output ('Pesto_17.0-RC18_'+$channel+'.zip')))
            try {
                foreach($entry in $archive.Entries){
                    $entryName=$entry.FullName.Replace('\','/')
                    Assert-PestoD ($entryName.StartsWith($channel+'/',[StringComparison]::Ordinal)) 'Dossier racine incorrect dans le ZIP.'
                }
            } finally {$archive.Dispose()}
        }
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $prod 'DEMO.cmd')))
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $prod 'TESTER.cmd')))
        Assert-PestoD (-not(Test-Path -LiteralPath (Join-Path $prod 'wad/maintenance')))
        Assert-PestoD (Test-Path -LiteralPath (Join-Path $dev 'DEMO.cmd'))
        Assert-PestoD (Test-Path -LiteralPath (Join-Path $dev 'tools/launcher/Pesto-launcher.c'))
        foreach($rel in $required+@('wad/package.json')){
            $a=(Get-FileHash -LiteralPath (Join-Path $prod $rel) -Algorithm SHA256).Hash
            $b=(Get-FileHash -LiteralPath (Join-Path $dev $rel) -Algorithm SHA256).Hash
            Assert-PestoD ($a -eq $b) ('Composant différent entre PROD et DEV : '+$rel)
        }
        Expect-PestoDFailure {& (Join-Path $Root 'tools/New-PestoDistribution.ps1') -SourceRoot $Root -OutputDirectory $output -Channel PROD}
    }
    Case-PestoD 'Generateur PowerShell utilisable sans fichiers DEV dans sa cible' {
        $generator=Join-Path $Root 'tools/Update-PackageManifest.ps1'
        Assert-PestoD (Test-Path -LiteralPath $generator -PathType Leaf) 'Exécuter ce test depuis le pack DEV.'
        & $generator -Root $fixture
        Assert-PestoD (Test-PestoPackage -Root $fixture).Valid
    }
} finally {
    if(Test-Path -LiteralPath $workspace){Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue}
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=Join-Path $ReportDirectory 'distribution-result.json'
[pscustomobject]@{
    Version='17.0-RC18';PowerShell=[string]$PSVersionTable.PSVersion;Edition=[string]$PSVersionTable.PSEdition
    OS=[Environment]::OSVersion.ToString();Utc=[DateTime]::UtcNow.ToString('o');Checks=$results.ToArray();Failed=$failed
    NoApplicationStarted=$true;NoAD=$true;Note='Test du contrôle de distribution uniquement. Ne valide ni WPF, ni UAC, ni AD.'
}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $report -Encoding UTF8
Write-Host ('Rapport : '+$report)
if($failed){exit 1}else{exit 0}
