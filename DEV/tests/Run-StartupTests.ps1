#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-startup-results.json'}
# Tests isoles : pas de lancement Pesto, pas de vraie UAC, pas d'AD, pas de dsregcmd.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$results=[Collections.Generic.List[object]]::new()
function Assert-True {param($Value,[string]$Message='Condition non satisfaite');if(-not $Value){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Assert-Throws {param([scriptblock]$Body);$threw=$false;try{& $Body}catch{$threw=$true};if(-not $threw){throw 'Exception attendue.'}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)"}}
foreach($relative in @('wad\Pesto-Startup.ps1','wad\Pesto-Core.ps1','tests\Run-StartupTests.ps1','tools\Verify-StartupUac.ps1')){
    Case ('Parseur natif : '+$relative) {
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
        Assert-True ($errors.Count -eq 0) (($errors|ForEach-Object{$_.Message}) -join '; ')
    }
}
. (Join-Path $root 'wad\Pesto-Startup.ps1')
# Les fonctions ci-dessus n'ont aucun effet lors de leur chargement.
$script:LogMessages=[Collections.Generic.List[string]]::new()
function Write-PestoStartupLog {param($Root,$Message);$script:LogMessages.Add([string]$Message)}
$script:RealStartupProcess=${function:Start-PestoStartupProcess}
function Start-PestoStartupProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $script:NativeLaunches++
    $script:LaunchArgs=@{Verb=$StartInfo.Verb;FilePath=$StartInfo.FileName;ArgumentList=$StartInfo.Arguments;WorkingDirectory=$StartInfo.WorkingDirectory;UseShellExecute=$StartInfo.UseShellExecute}
    if($script:FakeCancellation){throw [ComponentModel.Win32Exception]::new(1223)}
    if($script:FakeDenied){throw [ComponentModel.Win32Exception]::new(5)}
    if($script:FakeNullProcess){return $null}
    $p=[pscustomobject]@{Id=12345;Handle=[IntPtr]1;ExitCode=23;Waited=$false;Refreshed=$false;Disposed=$false}
    $p|Add-Member ScriptMethod WaitForExit {$this.Waited=$true}
    $p|Add-Member ScriptMethod Refresh {$this.Refreshed=$true}
    $p|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    $script:FakeProcess=$p
    return $p
}
$script:NativeLaunches=0;$script:FakeCancellation=$false;$script:FakeDenied=$false;$script:FakeNullProcess=$false
Case 'Mode reel non eleve : UAC avant moteur' {Assert-Equal (Get-PestoStartupRoute $false $false $false) 'Elevate'}
Case 'Deja eleve : aucune nouvelle UAC' {Assert-Equal (Get-PestoStartupRoute $false $true $false) 'Run'}
Case 'Relais eleve : ouverture du moteur autorisee' {Assert-Equal (Get-PestoStartupRoute $false $true $true) 'Run'}
Case 'Relais sans jeton admin : arret, pas de boucle' {Assert-Equal (Get-PestoStartupRoute $false $false $true) 'Refuse'}
Case 'Demo sans droits : aucune UAC' {Assert-Equal (Get-PestoStartupRoute $true $false $false) 'Demo'}
Case 'Etat reel du jeton retourne un bool, pas un nom de compte' {Assert-True ((Test-PestoStartupAdministrator) -is [bool])}
Case 'Chemin avec espaces et apostrophe : reste un argument -File' {
    $entry="C:\Pesto d'atelier [1] & test\Pesto.ps1"
    $line=New-PestoStartupArgumentLine $entry 'C:\Configs\site test.json' 'C:\Users\Test\AppData\Local'
    Assert-True ($line.Contains('-File "'+$entry+'"'))
    Assert-True ($line.Contains('-ConfigPath "C:\Configs\site test.json"'))
    Assert-True (-not $line.Contains('-Command') -and -not $line.Contains('EncodedCommand'))
}
Case 'Antislash final protege dans les arguments' {Assert-Equal (ConvertTo-PestoStartupArgument 'C:\test\') '"C:\test\\"'}
Case 'Caracteres de controle et guillemets refuses' {
    Assert-Throws {ConvertTo-PestoStartupArgument "C:\test`nGP.ps1"}
    Assert-Throws {ConvertTo-PestoStartupArgument 'C:\" -Command secret'}
}
Case 'Lanceur EXE : pas de parametre PowerShell -File' {
    $line=New-PestoStartupArgumentLine 'C:\Pesto\Pesto.exe' '' 'C:\Users\Test\AppData\Local'
    Assert-True ($line.StartsWith('-ElevatedLaunch'))
    Assert-True (-not $line.Contains('-File') -and -not $line.Contains('-NoProfile'))
}
Case 'Pas de nom de compte ou mot de passe dans les arguments de relais' {
    $line=New-PestoStartupArgumentLine 'C:\Pesto\Pesto.ps1' '' 'C:\Users\Test\AppData\Local'
    Assert-True ($line -notmatch '(?i)(Credential|Password|SecureString|EncodedCommand)')
}
Case 'Relais : RunAs explicite, sans Credential, code enfant conserve' {
    $code=Invoke-PestoStartupElevation -EntryPath (Join-Path $root 'Pesto.ps1') -OriginLocalAppData 'C:\Users\Test\AppData\Local' -Root $root
    Assert-Equal $code 23
    Assert-Equal $script:LaunchArgs.Verb 'RunAs'
    Assert-Equal $script:LaunchArgs.UseShellExecute $true
    Assert-Equal $script:LaunchArgs.WorkingDirectory $env:SystemRoot
    Assert-Equal $script:LaunchArgs.FilePath (Join-Path $PSHOME 'powershell.exe')
    Assert-True (-not $script:LaunchArgs.ContainsKey('Credential'))
    Assert-True ($script:FakeProcess.Waited -and $script:FakeProcess.Disposed)
}
Case 'UAC annulee : code 1223, aucune seconde tentative' {
    $before=$script:NativeLaunches;$script:FakeCancellation=$true
    try{Assert-Equal (Invoke-PestoStartupElevation -EntryPath (Join-Path $root 'Pesto.ps1') -Root $root) 1223}
    finally{$script:FakeCancellation=$false}
    Assert-Equal $script:NativeLaunches ($before+1)
}
Case 'Refus Windows autre que annulation : erreur non masquee' {
    $script:FakeDenied=$true
    try{Assert-Throws {Invoke-PestoStartupElevation -EntryPath (Join-Path $root 'Pesto.ps1') -Root $root}}
    finally{$script:FakeDenied=$false}
}
Case 'Processus absent : erreur, pas de faux succes' {
    $script:FakeNullProcess=$true
    try{Assert-Throws {Invoke-PestoStartupElevation -EntryPath (Join-Path $root 'Pesto.ps1') -Root $root}}
    finally{$script:FakeNullProcess=$false}
}
Case 'API native : erreur fichier absent conserve Win32, sans fausse annulation' {
    $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:TEMP ('Pesto-absent-'+[Guid]::NewGuid().ToString('N')+'.exe')))
    $info.UseShellExecute=$true
    # Aucun RunAs ni processus possible : fichier inexistant, pas de vraie UAC dans cette suite.
    $caught=$null
    try{& $script:RealStartupProcess -StartInfo $info}catch{$caught=$_.Exception}
    Assert-True ($null -ne $caught) 'Erreur native absente.'
    Assert-True (-not (Test-PestoStartupCancellation $caught))
    $native=$caught
    while($native -and -not ($native -is [ComponentModel.Win32Exception])){$native=$native.InnerException}
    Assert-True ($null -ne $native) 'Code Win32 perdu.'
    Assert-Equal $native.NativeErrorCode 2
}
Case 'Code Win32 1223 imbrique reconnu' {
    $ex=[Exception]::new('Wrapper',[ComponentModel.Win32Exception]::new(1223))
    Assert-True (Test-PestoStartupCancellation $ex)
    Assert-True (-not(Test-PestoStartupCancellation ([Exception]::new('Autre erreur'))))
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-startup-unit-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $origin=Join-Path $temp 'profil-operateur';$current=Join-Path $temp 'profil-admin'
    [void][IO.Directory]::CreateDirectory($origin);[void][IO.Directory]::CreateDirectory($current)
    $cfg=Join-Path $temp 'cfg.json';$id=Get-PestoStartupStateId $cfg
    $src=Join-Path $origin ('GP\State\'+$id);$dst=Join-Path $current ('GP\State\'+$id)
    [void][IO.Directory]::CreateDirectory($src)
    $active=[Text.Encoding]::UTF8.GetBytes('{"Schema":1,"Phase":"Uncertain","Rows":[]}')
    [IO.File]::WriteAllBytes((Join-Path $src 'queue.json'),$active)
    Case 'Identifiant de reprise identique au moteur pour le meme cfg.json' {
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad\Pesto-Core.ps1'),[ref]$tokens,[ref]$errors)
        $f=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Get-PestoStateDirectory'})[0]
        Assert-True ($f.Extent.Text.Contains("Substring(0,16)"))
        Assert-Equal (Get-PestoStartupStateId $cfg.ToUpperInvariant()) $id
    }
    Case 'Reprise sous un autre compte : file et verrou copies a l identique' {
        Import-PestoStartupState $origin $current $cfg $root
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $dst 'queue.json'))) ([Text.Encoding]::UTF8.GetString($active))
        Assert-True (Test-Path -LiteralPath (Join-Path $src 'queue.json'))
    }
    Case 'Une reprise deja importee ne reimporte pas un ancien verrou' {
        [IO.File]::WriteAllText((Join-Path $dst 'queue.json'),'{"Schema":1,"Phase":"Reviewed","Rows":[]}')
        Import-PestoStartupState $origin $current $cfg $root
        Assert-True ([IO.File]::ReadAllText((Join-Path $dst 'queue.json')).Contains('Reviewed'))
    }
    Case 'Changement de l ancienne file : conflit signale sans ecrasement' {
        [IO.File]::WriteAllText((Join-Path $src 'queue.json'),'{"Schema":1,"Phase":"Active","Rows":[{}]}')
        Assert-Throws {Import-PestoStartupState $origin $current $cfg $root}
        Assert-True ([IO.File]::ReadAllText((Join-Path $dst 'queue.json')).Contains('Reviewed'))
    }
    Case 'Deux files Idle vides entre comptes : dates et noms différents, originaux conservés' {
        $emptyOrigin='{"Schema":1,"Version":"1.0","Domain":"labo.local","Host":"ANCIEN","MachineId":"81387449-2dd8-4bd9-8059-f868a5b8ec68","Mode":"REEL","Phase":"Idle","Utc":"2026-10-04T17:00:00Z","OperationIds":[],"Rows":[]}'
        $emptyCurrent=$emptyOrigin.Replace('ANCIEN','NOUVEAU').Replace('17:00:00','19:00:00')
        [IO.File]::WriteAllText((Join-Path $src 'queue.json'),$emptyOrigin)
        [IO.File]::WriteAllText((Join-Path $dst 'queue.json'),$emptyCurrent)
        Import-PestoStartupState $origin $current $cfg $root
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $src 'queue.json'))) $emptyOrigin
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $dst 'queue.json'))) $emptyCurrent
    }
    Case 'Files vides : identités incompatibles, effets, schéma ou champs inconnus restent refusés' {
        $empty='{"Schema":1,"Domain":"labo.local","MachineId":"81387449-2dd8-4bd9-8059-f868a5b8ec68","Mode":"REEL","Phase":"Idle","OperationIds":[],"Rows":[]}'
        $bytes=[Text.Encoding]::UTF8.GetBytes($empty)
        $invalid=@(
            $empty.Replace('labo.local','autre.local'),
            $empty.Replace('81387449','81387448'),
            $empty.Replace('"Rows":[]','"Rows":[{}]'),
            $empty.Replace('"OperationIds":[]','"OperationIds":["pending"]'),
            $empty.Replace('"OperationIds":[]','"OperationIds":null'),
            $empty.Replace('"Rows":[]','"Rows":null'),
            $empty.Replace('"Schema":1','"Schema":2'),
            $empty.Replace('"Idle"','"Uncertain"'),
            $empty.Replace('"REEL"','"DEMO"'),
            $empty.Replace('"Schema":1','"Lock":true,"Schema":1'),
            '{invalid'
        )
        foreach($other in $invalid){Assert-True (-not(Test-PestoStartupEmptyQueues $bytes ([Text.Encoding]::UTF8.GetBytes($other))))}
    }
    Case 'Historiques divergents : archive exacte, aucune fusion ni résolution de verrou' {
        $history='{"Schema":1,"Domain":"labo.local","Entries":[{"RunId":"11111111-2222-3333-4444-555555555555","Mode":"REEL","Utc":"2026-10-04T17:00:00Z","Total":1,"Ok":1,"Failed":0,"NotStarted":0,"Locked":true}]}'
        $other=$history.Replace('11111111','11111112').Replace('17:00:00','19:00:00').Replace('true','false')
        [IO.File]::WriteAllText((Join-Path $src 'history-v1.json'),$history)
        [IO.File]::WriteAllText((Join-Path $dst 'history-v1.json'),$other)
        $hash=(Read-PestoStartupStateFile (Join-Path $src 'history-v1.json')).Hash
        Import-PestoStartupState $origin $current $cfg $root
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $src 'history-v1.json'))) $history
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $dst 'history-v1.json'))) $other
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $dst ('history-imported-'+$hash+'.json')))) $history
        Import-PestoStartupState $origin $current $cfg $root
        Assert-Equal @(Get-ChildItem $dst -Filter 'history-imported-*.json').Count 1
        Assert-True (($script:LogMessages -join ' ') -match 'aucun verrou resolu')
    }
    Case 'Historique non reconnu : domaine, schema, types ou champs actifs refusés' {
        $history='{"Schema":1,"Domain":"labo.local","Entries":[{"RunId":"11111111-2222-3333-4444-555555555555","Mode":"REEL","Utc":"2026-10-04T17:00:00Z","Total":1,"Ok":1,"Failed":0,"NotStarted":0,"Locked":true}]}'
        $bytes=[Text.Encoding]::UTF8.GetBytes($history)
        $invalid=@($history.Replace('labo.local','autre.local'),$history.Replace('"Schema":1','"Schema":2'),
            $history.Replace('"Schema":1','"Rows":[],"Schema":1'),$history.Replace('"Locked":true','"Locked":"true"'),
            $history.Replace('"Total":1','"Total":-1'),$history.Replace('"Ok":1','"Ok":"1"'),
            $history.Replace('"Mode":"REEL"','"Task":"active","Mode":"REEL"'),
            $history.Replace('2026-10-04T17:00:00Z','invalide'),$history.Replace('11111111-2222-3333-4444-555555555555','invalide'),
            '{"Schema":1,"Domain":"labo.local","Entries":null}')
        foreach($other in $invalid){Assert-True (-not(Test-PestoStartupHistoryPair $bytes ([Text.Encoding]::UTF8.GetBytes($other))))}
    }
    Case 'Archive historique déjà présente mais différente : rien écrasé' {
        $history='{"Schema":1,"Domain":"labo.local","Entries":[]}'
        [IO.File]::WriteAllText((Join-Path $src 'history-v1.json'),$history)
        $hash=(Read-PestoStartupStateFile (Join-Path $src 'history-v1.json')).Hash
        $archive=Join-Path $dst ('history-imported-'+$hash+'.json')
        [IO.File]::WriteAllText($archive,'archive antérieure')
        Assert-Throws {Import-PestoStartupState $origin $current $cfg $root}
        Assert-Equal ([IO.File]::ReadAllText($archive)) 'archive antérieure'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $src 'history-v1.json'))) $history
    }
    Case 'Fichier deja existant : CreateNew refuse de le remplacer' {
        $path=Join-Path $temp 'preserve.txt';[IO.File]::WriteAllText($path,'original')
        Assert-Throws {Write-PestoStartupNewFile $path ([Text.Encoding]::UTF8.GetBytes('nouveau'))}
        Assert-Equal ([IO.File]::ReadAllText($path)) 'original'
    }
    Case 'Fichier de reprise trop volumineux refuse' {
        $path=Join-Path $temp 'taille.txt';[IO.File]::WriteAllText($path,'123456')
        Assert-Throws {Read-PestoStartupStateFile $path -MaxBytes 4}
    }
    Case 'Dossier source absent : aucune creation d une fausse file' {
        $other=Join-Path $temp 'nouvel-admin';[void][IO.Directory]::CreateDirectory($other)
        Import-PestoStartupState (Join-Path $temp 'inexistant') $other $cfg $root
        Assert-True (-not(Test-Path -LiteralPath (Join-Path $other 'Pesto\State')))
    }
    Case 'Reprise depuis une jonction refusee sans lecture de la cible' {
        $target=Join-Path $temp 'cible';[void][IO.Directory]::CreateDirectory($target)
        $link=Join-Path $temp 'jonction'
        [void](New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop)
        try{Assert-Throws {Assert-PestoStartupLocalPath $link}}
        finally{[IO.Directory]::Delete($link)}
    }
    Case 'Chemin de reprise reseau refuse' {Assert-Throws {Assert-PestoStartupLocalPath '\\serveur\partage\Pesto'}}
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }

$failed=@($results|Where-Object{-not $_.Passed}).Count
[pscustomobject]@{Version='1.0';Utc=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();RealUacExecuted=$false;RealADExecuted=$false;Passed=$results.Count-$failed;Failed=$failed;Tests=$results.ToArray()}|
    ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Tests startup : $($results.Count-$failed) OK, $failed echec(s). Rapport : $ReportPath"
if($failed){exit 1};exit 0
