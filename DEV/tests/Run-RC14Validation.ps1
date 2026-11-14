#requires -Version 5.1
[CmdletBinding()]
param([switch]$IncludeLegacy)
# Validation Windows isolee. Pas d'ouverture de Pesto, d'UAC, de connexion AD,
# de dsregcmd, de jonction, de renommage ni de redemarrage reels.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Lancer avec -STA ou TESTER.cmd.'}
$root=Split-Path $PSScriptRoot -Parent;$fail=[Collections.Generic.List[string]]::new();$report=[Collections.Generic.List[object]]::new()
function Check {param([string]$Name,[scriptblock]$Body);try{& $Body;$report.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK $Name"}catch{$fail.Add($Name);$report.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO $Name : $($_.Exception.Message)"}}
Check 'Tous les scripts passent le parseur PowerShell natif' {
    foreach($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File){
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ($file.FullName+': '+(($errors|ForEach-Object{[string]$_.Extent.StartLineNumber+' '+$_.Message}) -join '; '))}
    }
}
$script:testWindow=$null
Check 'Chargement WPF du shell et de la page de jonction' {
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $text=[IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Core.ps1'))
    $pattern='(?s)\[xml\]\$xaml\s*=\s*@''\r?\n(.*?)\r?\n''@'
    $match=[regex]::Match($text,$pattern)
    if(-not $match.Success){throw 'XAML principal introuvable.'}
    $script:testWindow=[Windows.Markup.XamlReader]::Parse($match.Groups[1].Value)
    $reader=[Xml.XmlReader]::Create((Join-Path $root 'wad\Pesto-Join.xaml'))
    try{$page=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $script:testWindow.FindName('UxJoinHost').Content=$page
    if($script:testWindow.FindName('MainTabs').Items.Count -ne 8){throw 'Nombre de pages inattendu.'}
    foreach($name in @('JnType','JnOrg','JnSite','JnService','JnName','JnReference','JnStart','JnCheck','JnRefresh','JnRestart','JnLater','JnCancelRead','JnExport','JnLog','JnCopy')){
        $c=$page.FindName($name);if(-not $c){throw "Controle absent : $name"}
        if(-not $c.ToolTip){throw "Aide absente : $name"}
        if(-not [Windows.Controls.ToolTipService]::GetShowOnDisabled($c)){throw "Aide sur controle grise absente : $name"}
        [void]$c.ApplyTemplate()
    }
    if($page.FindName('JnRestart').Visibility -ne 'Collapsed'){throw 'Redemarrage visible avant tout resultat.'}
    if($page.FindName('JnChecks').CanUserAddRows -or $page.FindName('JnChecks').CanUserDeleteRows){throw 'Le controle de resultat ne doit pas permettre de creer/supprimer des lignes.'}
    foreach($key in @('Card','BtnRun','FgText','FgMuted','OkFg','WarnFg','ErrFg')){if(-not $script:testWindow.Resources.Contains($key)){throw "Ressource absente : $key"}}
}
if($script:testWindow){$script:testWindow.Close();$script:testWindow=$null}
Check 'EXE natif x64 avec version de produit RC14' {
    $path=Join-Path $root 'Pesto.exe';$bytes=[IO.File]::ReadAllBytes($path)
    if($bytes[0] -ne 77 -or $bytes[1] -ne 90){throw 'Entete MZ absent.'}
    $pe=[BitConverter]::ToInt32($bytes,60)
    if([BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664){throw 'Architecture x64 absente.'}
    if([BitConverter]::ToUInt16($bytes,$pe+24+68) -ne 2){throw 'Sous-systeme graphique absent.'}
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    if($version.FileVersion -ne '17.0.0.14'){throw ('Version incorrecte : '+$version.FileVersion)}
    Write-Host ('Executable inspecte, NON lance : '+$path)
}
foreach($suite in @('Run-JoinTests.ps1','Run-SsoTests.ps1','Run-StartupTests.ps1')){
    Check $suite {
        & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot $suite)
        if($LASTEXITCODE -ne 0){throw "La suite a renvoye $LASTEXITCODE"}
    }
}
if($IncludeLegacy){
    Check 'Suites historiques (compatibilite supplementaire)' {
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -STA -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Run-AllTests.ps1')
        if($LASTEXITCODE -ne 0){throw 'Une suite historique a echoue. Consulter son compte rendu.'}
    }
}
$path=Join-Path $PSScriptRoot 'windows-rc14-validation.json'
[pscustomobject]@{Version='17.0-RC14';Utc=[DateTime]::UtcNow.ToString('o');Failed=$fail.Count;Checks=$report.ToArray();NoRealAD=$true}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Rapport : '+$path)
Write-Warning 'Ces tests ne remplacent pas une recette sur un domaine et des PC de test. Aucune operation AD reelle effectuee.'
if($fail.Count){exit 1}else{exit 0}
