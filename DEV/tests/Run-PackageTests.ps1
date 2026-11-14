#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-package-results.json'}
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Tests de package : Windows PowerShell 5.1 x64 requis.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$results=[Collections.Generic.List[object]]::new()
function Assert-True {param($Condition,[string]$Message);if(-not $Condition){throw $Message}}
function Case {
    param([string]$Name,[scriptblock]$Body)
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''}); Write-Host "OK  $Name" }
    catch { $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message}); Write-Host "KO  $Name : $($_.Exception.Message)" }
}
function Parse-Code {
    param([string]$Code)
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Code,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw (($errors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n")}
    return $ast
}
# Aucun moteur lancé ; le support de déblocage est exécuté exclusivement sur les fixtures ci-dessous.
foreach($relative in @('wad\Pesto-Startup.ps1','tests\Run-StartupTests.ps1','wad\Pesto-Core.ps1','tests\Run-EngineTests.ps1','tests\Run-PackageTests.ps1','tests\Run-AsyncTests.ps1','tests\Async-ScopeFixture.ps1','tests\Run-RC4Tests.ps1','tests\Run-PilotageTests.ps1','tests\Run-UxTests.ps1','tests\Run-AllTests.ps1','tests\Run-QueueRemovalTests.ps1','tools\Build-Pesto.ps1','wad\ActiveDirectory.psd1')){
    Case ('Parseur natif : '+$relative) { [void](Parse-Code -Code (Get-Content -LiteralPath (Join-Path $root $relative) -Raw)) }
}
$cmd=[IO.File]::ReadAllText((Join-Path $root 'wad\support\DEBLOQUER_TOUT.cmd'))
$marker=':__PESTO_SUPPORT_POWERSHELL__'
$offset=$cmd.LastIndexOf($marker,[StringComparison]::Ordinal)
if($offset -lt 0){throw 'Bloc PowerShell du support absent.'}
$body=$cmd.Substring($offset+$marker.Length)
Case 'Parseur natif : bloc de déblocage livré' { [void](Parse-Code -Code $body) }
# Le vrai bloc support tourne uniquement dans une fixture neuve. La seule invite reçoit O dans ce processus enfant.
function Invoke-PestoPackageUnblock {
    param([string]$Root)
    $lines=@(& (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:UnblockWrapper -Root $Root -CodePath $script:UnblockBody 2>&1)
    $exitCode=$LASTEXITCODE;$text=($lines -join "`n")
    $match=[regex]::Match($text,'Debloques=(\d+); deja sans marque=(\d+); liens ou hors Pesto ignores=(\d+); erreurs=(\d+)')
    if($exitCode -ne 0 -or -not $match.Success){
        $logs=Join-Path $Root 'wad\logs'
        if(Test-Path -LiteralPath $logs){$last=Get-ChildItem -LiteralPath $logs -Filter 'DEBLOCAGE_Pesto_*.log'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1;if($last){$text+="`n"+[IO.File]::ReadAllText($last.FullName)}}
        throw ('Déblocage refusé : '+$text)
    }
    return [pscustomobject]@{Success=($exitCode -eq 0);Unblocked=[int]$match.Groups[1].Value;AlreadyClear=[int]$match.Groups[2].Value;SkippedLinks=[int]$match.Groups[3].Value;Messages=$lines}
}
. (Join-Path $root 'wad\Pesto-Integrity.ps1')
Case 'DEV : manifeste complet valide, configuration hors empreinte' {
    $p=Test-PestoPackage -Root $root
    Assert-True ($p.Valid -and $p.Version -ceq '1.0') 'Paquet incohérent.'
    Assert-True ((Get-PestoRuntimeFiles) -notcontains 'wad/cfg.json') 'Configuration utilisateur intégrée aux empreintes.'
}
Case 'Lanceur natif x64 graphique et version 1.0' {
    $path=Join-Path $root 'Pesto.exe';$bytes=[IO.File]::ReadAllBytes($path);$pe=[BitConverter]::ToInt32($bytes,60)
    Assert-True ($bytes[0] -eq 77 -and $bytes[1] -eq 90 -and [BitConverter]::ToUInt16($bytes,$pe+4) -eq 0x8664) 'EXE x64 attendu.'
    Assert-True ([BitConverter]::ToUInt16($bytes,$pe+24+68) -eq 2) 'Sous-système graphique attendu.'
    Assert-True (([Diagnostics.FileVersionInfo]::GetVersionInfo($path)).ProductVersion -like '1.0*') 'Version de produit incorrecte.'
}
Case 'Modèle neuf neutre disponible sans configuration obligatoire préremplie' {
    $c=Get-Content -LiteralPath (Join-Path $root 'tools\cfg.template.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-True ($c.Configured -is [bool] -and -not $c.Configured) 'Modèle neutre attendu.'
}

Case 'Ressources dans wad ; aucun dossier mod' {
    foreach($name in @('Pesto-Core.ps1','Pesto-Startup.ps1','cfg.json','cfg.example.json','cfg.demo.json','Pesto.ico',
        'ActiveDirectory.psd1','ActiveDirectory.Format.ps1xml','ActiveDirectory.Types.ps1xml',
        'ActiveDirectoryPowerShellResources.dll','Microsoft.ActiveDirectory.Management.dll','fr-FR\ActiveDirectoryPowerShellResources.dll.mui')){
        Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $root 'wad') $name) -PathType Leaf) ('Ressource absente : '+$name)
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'mod'))) 'Ancien dossier mod encore present.'
}
# Tests de flux NTFS dans un dossier temporaire, jamais sur les fichiers livres.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-package-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $script:UnblockBody=Join-Path $temp 'support-body.ps1'
    [IO.File]::WriteAllText($script:UnblockBody,$body,[Text.UTF8Encoding]::new($true))
    $script:UnblockWrapper=Join-Path $temp 'support-runner.ps1'
    $wrapper=@'
param([string]$Root,[string]$CodePath)
$ErrorActionPreference='Stop'
$env:PESTO_UNBLOCK_DIR=Join-Path $Root 'wad\support'
function Read-Host {param($Prompt);return 'O'}
& ([scriptblock]::Create([IO.File]::ReadAllText($CodePath)))
'@
    [IO.File]::WriteAllText($script:UnblockWrapper,$wrapper,[Text.UTF8Encoding]::new($true))
    $prod=Join-Path $temp 'production'
    Case 'Disposition PROD minimale : EXE et wad, mêmes empreintes que DEV' {
        [void][IO.Directory]::CreateDirectory($prod)
        foreach($relative in @((Get-PestoRuntimeFiles))+@('wad/package.json','wad/cfg.json','wad/support/DEBLOQUER_TOUT.cmd')){
            $target=Join-Path $prod $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.File]::Copy((Join-Path $root $relative),$target,$false)
        }
        Assert-True (((@(Get-ChildItem -LiteralPath $prod -Force).Name|Sort-Object) -join ',') -ceq 'Pesto.exe,wad') 'Racine PROD inattendue.'
        Assert-True (Test-PestoPackage -Root $prod).Valid 'PROD incohérente.'
    }
    Case 'Composant altéré dans la copie PROD refusé' {
        [IO.File]::AppendAllText((Join-Path $prod 'wad\Pesto-Names.ps1'),'# altération de fixture')
        $caught=$false;try{Test-PestoPackage -Root $prod|Out-Null}catch{$caught=$true}
        Assert-True $caught 'Altération acceptée.'
    }
    $fixture=Join-Path $temp "Pesto [test] d'atelier & accent-é!"
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'wad\nested'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'wad\support'))
    $files=@('Pesto.exe','wad\Pesto-Startup.ps1','wad\Pesto-Core.ps1','wad\nested\script [1].ps1','wad\module.dll','wad\cache.txt')
    foreach($file in $files){[IO.File]::WriteAllText((Join-Path $fixture $file),'contenu inerte, jamais execute')}
    $sibling=Join-Path $temp 'hors-Pesto.txt';[IO.File]::WriteAllText($sibling,'hors perimetre')
    $hashes=@{}
    foreach($file in $files){$p=Join-Path $fixture $file;$hashes[$p]=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
    Case 'Refus d''un dossier sans marqueurs Pesto' {
        $caught=$false
        try { [void](Invoke-PestoPackageUnblock -Root $temp) } catch { $caught=$true }
        Assert-True $caught 'Le dossier parent a ete accepte a tort.'
    }
    Case 'Deblocage recursif des flux Zone.Identifier (NTFS requis)' {
        foreach($file in $files){Set-Content -LiteralPath (Join-Path $fixture $file) -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII}
        Set-Content -LiteralPath $sibling -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
        $hidden=Get-Item -LiteralPath (Join-Path $fixture 'wad\cache.txt') -Force
        $hidden.Attributes=$hidden.Attributes -bor [IO.FileAttributes]::Hidden
        $report=Invoke-PestoPackageUnblock -Root $fixture
        Assert-True $report.Success ($report.Messages -join "`n")
        Assert-True ($report.Unblocked -eq $files.Count) 'Nombre de fichiers debloques incorrect.'
        foreach($file in $files){
            $remaining=@(Get-Item -LiteralPath (Join-Path $fixture $file) -Stream * -Force | Where-Object { $_.Stream -eq 'Zone.Identifier' })
            Assert-True ($remaining.Count -eq 0) ('Flux encore present : '+$file)
        }
    }
    Case 'Contenu des fichiers preserve' {
        foreach($p in $hashes.Keys){Assert-True ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -eq $hashes[$p]) ('Contenu modifie : '+$p)}
    }
    Case 'Fichier voisin hors Pesto non touche' {
        $zone=@(Get-Item -LiteralPath $sibling -Stream * -Force | Where-Object { $_.Stream -eq 'Zone.Identifier' })
        Assert-True ($zone.Count -eq 1) 'Le fichier voisin a ete debloque a tort.'
    }
    Case 'Deuxieme execution sans modification supplementaire' {
        $report=Invoke-PestoPackageUnblock -Root $fixture
        Assert-True ($report.Success -and $report.Unblocked -eq 0 -and $report.AlreadyClear -ge $files.Count) 'Deblocage non idempotent.'
    }
    Case 'Jonction ignoree sans toucher la cible externe' {
        $outside=Join-Path $temp 'externe';[void][IO.Directory]::CreateDirectory($outside)
        $external=Join-Path $outside 'fichier.txt';[IO.File]::WriteAllText($external,'hors perimetre via lien')
        Set-Content -LiteralPath $external -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
        $junction=Join-Path $fixture 'wad\vers-externe'
        [void](New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop)
        try {
            $report=Invoke-PestoPackageUnblock -Root $fixture
            Assert-True ($report.Success -and $report.SkippedLinks -eq 1) 'Jonction non ignoree.'
            $zone=@(Get-Item -LiteralPath $external -Stream * | Where-Object { $_.Stream -eq 'Zone.Identifier' })
            Assert-True ($zone.Count -eq 1) 'Cible de la jonction debloquee a tort.'
        } finally { [IO.Directory]::Delete($junction) }
    }
} finally {
    # Les jonctions sont retirees sans -Recurse avant le nettoyage des fixtures.
    $junctionPath=Join-Path $temp "Pesto [test] d'atelier & accent-é!\wad\vers-externe"
    if([IO.Directory]::Exists($junctionPath)){[IO.Directory]::Delete($junctionPath)}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
$failed=@($results | Where-Object { -not $_.Passed }).Count
$report=[ordered]@{Version='1.0';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Scope='Parseur natif, manifeste DEV/PROD, inspection PE sans lancement et support réel sur fixtures NTFS ; aucun moteur WPF, UAC ou accès AD.';
    Total=$results.Count;Passed=($results.Count-$failed);Failed=$failed;Results=$results.ToArray()}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if($failed -gt 0){throw "$failed test(s) de package en echec. Rapport : $ReportPath"}
Write-Host "Tests de package reussis : $($results.Count). Rapport : $ReportPath"
