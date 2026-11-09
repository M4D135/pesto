#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop'
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad'
$cases=[Collections.Generic.List[object]]::new()
function Require-Cli {param($Condition,[string]$Message='Assertion refusée');if(-not $Condition){throw $Message}}
function Case-Cli {param([string]$Name,[scriptblock]$Body);try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('PASS '+$Name)}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
function Write-CliFixture {param([string]$Path,[string]$Text);[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($true))}
function Assert-CliPayload {param($Value)
    Require-Cli ($Value.ExitCode -eq 0)
    Require-Cli ($Value.Message -ceq $script:sample.Message) 'Accents, CJK ou paire surrogate altérés'
    Require-Cli ($Value.Path -ceq $script:sample.Path) 'Chemin ou antislash altéré'
    Require-Cli ($Value.Literal -ceq $script:sample.Literal) 'Échappement JSON préexistant altéré'
    Require-Cli ($Value.Special -ceq $script:sample.Special) 'Guillemets ou contrôles altérés'
    Require-Cli ($Value.Nested.PSObject.Properties['clé'].Value -ceq 'été') 'Clé Unicode altérée'
}
function Invoke-CliChild {param([string]$Entry,[int]$ExpectedExit=0,[string]$Extra='')
    $engine=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Desktop'){'powershell.exe'}elseif($env:OS -eq 'Windows_NT'){'pwsh.exe'}else{'pwsh'})
    # Isolated child: OEM output and no PowerShell module-autoload progress on stderr.
    # Errors stay enabled; neither preference is changed in the calling host.
    $command='$ProgressPreference=''SilentlyContinue'';[Console]::OutputEncoding=[Text.Encoding]::GetEncoding(850); & '''+$Entry.Replace("'","''")+''' -AsJson '+$Extra+'; exit $LASTEXITCODE'
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$engine
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start;$buffer=[IO.MemoryStream]::new()
    try{
        [void]$process.Start();$copy=$process.StandardOutput.BaseStream.CopyToAsync($buffer);$errors=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(15000)){try{$process.Kill()}catch{};throw 'Processus CLI factice expiré.'}
        $copy.GetAwaiter().GetResult();$stderr=$errors.GetAwaiter().GetResult()
        Require-Cli ($process.ExitCode -eq $ExpectedExit) ('Code enfant inattendu : '+$process.ExitCode+' '+$stderr+' '+[Text.Encoding]::UTF8.GetString($buffer.ToArray()))
        Require-Cli ([string]::IsNullOrWhiteSpace($stderr)) ('Sortie erreur inattendue : '+$stderr)
        $bytes=$buffer.ToArray();Require-Cli ($bytes.Length -gt 0) 'Stdout vide'
        Require-Cli (@($bytes|Where-Object{$_ -gt 127}).Count -eq 0) 'Stdout dépend encore de la page de codes'
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        return ($json|ConvertFrom-Json)
    }finally{$buffer.Dispose();$process.Dispose()}
}

# Parse actual diagnostic functions without importing the generated module or AD.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtime 'Pesto-Diagnostics.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Source diagnostic invalide.'}
foreach($name in @('New-PestoDiagnosticFinding','Get-PestoTransportRequirements','Invoke-PestoReadDiagnostics')){
    $node=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)|Select-Object -First 1
    if(-not $node){throw ('Fonction absente : '+$name)}
    . ([scriptblock]::Create($node.Extent.Text))
}
function Protect-PestoLogText {param($Text);$Text}
function Test-PestoDnsName {param($Name);$true}
function Test-PestoComputerName {param($Name);$true}
function Get-DomainController {throw 'Aucun DC ne doit être découvert dans ce banc.'}
function Resolve-DnsName {[pscustomobject]@{Type='SRV';NameTarget='dc.example.test';Port=389;Priority=0;Weight=100}}
function Test-PestoDiagnosticEndpoint {param($HostName,$Port);$script:probes.Add([pscustomobject]@{Host=$HostName;Port=$Port});[pscustomobject]@{Host=$HostName;Port=$Port;Reachable=$true}}
foreach($action in @('Join','Rename','Move','Observe')){
    Case-Cli ('Diagnostic '+$action+' : LDAP389 et ADWS9389 distincts sans nouveau transport') {
        $script:probes=[Collections.Generic.List[object]]::new()
        $r=Invoke-PestoReadDiagnostics -Domain example.test -DC dc.example.test -Computer PC001 -Action $action -Checks Network
        $ldap=@($r.Findings|Where-Object Name -eq 'TCP.389');$adws=@($r.Findings|Where-Object Name -eq 'TCP.9389')
        Require-Cli ($ldap.Count -eq 1 -and $ldap[0].Detail -like 'LDAP (TCP/389)*' -and $ldap[0].Detail -notmatch 'ADWS')
        Require-Cli ($adws.Count -eq 1 -and $adws[0].Detail -like 'ADWS (TCP/9389)*')
        Require-Cli ($ldap[0].Data.Host -ceq 'dc.example.test' -and $adws[0].Data.Host -ceq 'dc.example.test')
        $expected=switch($action){'Join'{@(88,389,445,135,9389)}'Rename'{@(389,9389,135,445)}'Move'{@(389,9389)}'Observe'{@(389,9389,135)}}
        Require-Cli (($script:probes.Port -join ',') -ceq ($expected -join ',')) 'Liste ou ordre des sondes changé'
        Require-Cli ($r.ReadOnly -and -not $r.MutationAuthorized)
    }
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('pesto-cli-output-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:sample=[pscustomobject]@{Schema=1;Mode='Fixture';State='Observed';ExitCode=0;MutationStarted=$false;RestartRequired=$false;Message=('Déjà été · 東京 '+[char]::ConvertFromUtf32(0x1F600));Path='C:\été\new';Literal='\u00e9';Special="guillemets`" tab`t ligne`n";Nested=[pscustomobject]@{'clé'='été'}}
try{
    foreach($entryName in @('Invoke-Pesto.ps1','Invoke-PestoAutoJoin.ps1')){
        $folder=Join-Path $temp ([IO.Path]::GetFileNameWithoutExtension($entryName));[void][IO.Directory]::CreateDirectory($folder)
        $entry=Join-Path $folder $entryName;[IO.File]::WriteAllBytes($entry,[IO.File]::ReadAllBytes((Join-Path $runtime $entryName)))
        [IO.File]::WriteAllBytes((Join-Path $folder 'Pesto-CliHost.ps1'),[IO.File]::ReadAllBytes((Join-Path $runtime 'Pesto-CliHost.ps1')))
        Write-CliFixture (Join-Path $folder 'Pesto-Integrity.ps1') 'function Test-PestoPackage {param($Root);$true}'
        Write-CliFixture (Join-Path $folder 'payload.json') ($sample|ConvertTo-Json -Depth 6)
        Write-CliFixture (Join-Path $folder 'Pesto.Engine.psd1') "@{RootModule='Pesto.Engine.psm1';ModuleVersion='1.0.0';FunctionsToExport=@('Invoke-PestoCommand')}"
        Write-CliFixture (Join-Path $folder 'Pesto.Engine.psm1') 'function Invoke-PestoCommand {Get-Content -LiteralPath (Join-Path $PSScriptRoot ''payload.json'') -Raw -Encoding UTF8|ConvertFrom-Json};Export-ModuleMember -Function Invoke-PestoCommand'
        Case-Cli ($entryName+' : retour objet inchangé et aucun encodage global modifié') {
            $encoding=[Console]::OutputEncoding;$output=$OutputEncoding
            $value=& $entry;Assert-CliPayload $value
            Require-Cli ($value -isnot [string])
            Require-Cli ([object]::ReferenceEquals($encoding,[Console]::OutputEncoding))
            Require-Cli ([object]::ReferenceEquals($output,$OutputEncoding))
        }
        Case-Cli ($entryName+' : JSON in-process capturable, ASCII et Unicode réversible') {
            $encoding=[Console]::OutputEncoding;$lines=@(& $entry -AsJson)
            Require-Cli ($lines.Count -eq 1 -and $lines[0] -is [string])
            Require-Cli ($lines[0] -notmatch '[^\x00-\x7F]')
            Assert-CliPayload ($lines[0]|ConvertFrom-Json)
            Require-Cli ([object]::ReferenceEquals($encoding,[Console]::OutputEncoding))
        }
        Case-Cli ($entryName+' : vrai stdout sous OEM850 reste UTF8 valide sans perte') {
            Assert-CliPayload (Invoke-CliChild $entry)
        }
        # Failure before module import exercises the same serializer on the refusal path.
        Write-CliFixture (Join-Path $folder 'Pesto-Integrity.ps1') "throw 'Erreur factice été 東京'"
        Case-Cli ($entryName+' : refus96 JSON ASCII conserve message Unicode') {
            $value=Invoke-CliChild $entry 96
            Require-Cli ($value.ExitCode -eq 96 -and $value.State -eq 'NotStarted')
            Require-Cli ($value.Message -ceq 'Démarrage refusé : Erreur factice été 東京')
            Require-Cli (-not $value.MutationStarted)
        }
    }
    # Adaptateur d'intégration réel : sortie JSON ASCII sur les trois chemins, y compris le refus
    # précoce avant chargement du CliHost (chemin relatif), où seul le repli local sérialise.
    $deploy=Join-Path $temp 'deploy';$deployWad=Join-Path $deploy 'wad';[void][IO.Directory]::CreateDirectory($deployWad)
    $adapter=Join-Path $deploy 'Invoke-PestoDeployment.ps1'
    [IO.File]::WriteAllBytes($adapter,[IO.File]::ReadAllBytes((Join-Path (Split-Path $runtime -Parent) 'integrations/Invoke-PestoDeployment.ps1')))
    [IO.File]::WriteAllBytes((Join-Path $deployWad 'Pesto-CliHost.ps1'),[IO.File]::ReadAllBytes((Join-Path $runtime 'Pesto-CliHost.ps1')))
    Write-CliFixture (Join-Path $deployWad 'Pesto-Integrity.ps1') 'function Test-PestoPackage {param($Root);$true}'
    Write-CliFixture (Join-Path $deployWad 'payload.json') ($sample|ConvertTo-Json -Depth 6)
    Write-CliFixture (Join-Path $deployWad 'Pesto.Engine.psd1') "@{RootModule='Pesto.Engine.psm1';ModuleVersion='1.0.0';FunctionsToExport=@('Invoke-PestoCommand')}"
    Write-CliFixture (Join-Path $deployWad 'Pesto.Engine.psm1') 'function Invoke-PestoCommand {Get-Content -LiteralPath (Join-Path $PSScriptRoot ''payload.json'') -Raw -Encoding UTF8|ConvertFrom-Json};Export-ModuleMember -Function Invoke-PestoCommand'
    $installation="-Installation '"+$deploy.Replace("'","''")+"'"
    Case-Cli 'Invoke-PestoDeployment.ps1 : succès JSON ASCII et Unicode réversible' {
        Assert-CliPayload (Invoke-CliChild $adapter 0 $installation)
    }
    Case-Cli 'Invoke-PestoDeployment.ps1 : refus précoce (chemin relatif) en JSON ASCII valide' {
        $value=Invoke-CliChild $adapter 96 "-Installation 'wad-relatif'"
        Require-Cli ($value.ExitCode -eq 96 -and $value.State -eq 'NotStarted' -and -not $value.MutationStarted)
        Require-Cli ($value.Message -ceq 'Installation doit être un chemin absolu local.') ('Message altéré : '+$value.Message)
    }
    # Une réponse moteur invalide ne doit jamais être sérialisée telle quelle.

    # Actual successful read producers, with only their environment dependencies doubled.
    $tokens=$null;$errors=$null;$enterprise=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtime 'Pesto-Enterprise.ps1'),[ref]$tokens,[ref]$errors)
    Require-Cli (-not $errors.Count)
    $producer=@($enterprise.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in @('Invoke-PestoInspection','Invoke-PestoCommand','New-PestoIntegrationResult')}|ForEach-Object{$_.Extent.Text}) -join "`n"
    $dependencies=@'
function Close-PestoHeadlessAudit {}
function Assert-PestoAutomationPlatform {}
function Read-PestoAutomationJson {[pscustomobject]@{}}
function Test-CfgValid {}
function Get-PestoConfigurationSignature {'fixture'}
function ConvertTo-PestoDeploymentMetadata {[pscustomobject]@{}}
function Initialize-PestoHeadlessContext {$script:DC='dc.example.test';$script:DOMAINE='example.test'}
function Get-PestoPostObservation {[pscustomobject]@{Computer='PC001'}}
function Invoke-PestoReadDiagnostics {[pscustomobject]@{Computer='PC001'}}
Export-ModuleMember -Function Invoke-PestoCommand
'@
    Write-CliFixture (Join-Path $deployWad 'Pesto.Engine.psm1') ($producer+"`n"+$dependencies)
    Case-Cli 'Real Inspect producer is accepted by deployment adapter as read-only Observed0' {
        $value=Invoke-CliChild $adapter 0 ($installation+' -Action Inspect')
        Require-Cli ($value.State -ceq 'Observed' -and $value.ReadOnly -and $value.MutationStarted -is [bool] -and -not $value.MutationStarted -and $value.Observation.Computer -ceq 'PC001')
    }
    $diagnoseEntry=Join-Path $deployWad 'Invoke-Pesto.ps1'
    [IO.File]::WriteAllBytes($diagnoseEntry,[IO.File]::ReadAllBytes((Join-Path $runtime 'Invoke-Pesto.ps1')))
    Case-Cli 'Real Diagnose producer declares no mutation in successful CLI result' {
        $value=Invoke-CliChild $diagnoseEntry 0 '-Action Diagnose'
        Require-Cli ($value.State -ceq 'Observed' -and $value.ReadOnly -and $value.MutationStarted -is [bool] -and -not $value.MutationStarted -and $value.Diagnostic.Computer -ceq 'PC001')
    }
    $engineInvalidMarker='PESTO_ENGINE_INVALID_CANARY_'+[Guid]::NewGuid().ToString('N')
    Write-CliFixture (Join-Path $deployWad 'Pesto.Engine.psm1') ("function Invoke-PestoCommand {[pscustomobject]@{Schema=1;Mode='Inspect';State='';ExitCode='bad';MutationStarted='x';Message='PESTO_ENGINE_INVALID "+$engineInvalidMarker+"'}};Export-ModuleMember -Function Invoke-PestoCommand")
    Case-Cli 'Invoke-PestoDeployment.ps1 : résultat moteur invalide en JSON fermé sans détail brut' {
        $value=Invoke-CliChild $adapter 96 $installation
        Require-Cli ($value.ExitCode -eq 96 -and $value.State -eq 'NotStarted' -and -not $value.MutationStarted)
        Require-Cli ($value.Message -like 'Le moteur*') ('Message inattendu : '+$value.Message)
        Require-Cli (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains($engineInvalidMarker)) 'Détail moteur invalide divulgué'
    }
    # Une erreur de dépendance peut contenir un secret : seule la réponse fermée est rendue.
    $adapterFailureMarker='PESTO_CLI_CANARY_'+[Guid]::NewGuid().ToString('N')
    Write-CliFixture (Join-Path $deployWad 'Pesto-Integrity.ps1') ("throw 'Erreur factice été 東京 "+$adapterFailureMarker+"'")
    Case-Cli 'Invoke-PestoDeployment.ps1 : refus après CliHost en JSON ASCII avec message fermé' {
        $value=Invoke-CliChild $adapter 96 $installation
        Require-Cli ($value.ExitCode -eq 96 -and $value.State -eq 'NotStarted' -and -not $value.MutationStarted)
        Require-Cli ($value.Message -ceq 'Intégrité du paquet non confirmée.') ('Message altéré : '+$value.Message)
        Require-Cli (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains($adapterFailureMarker)) 'Détail brut de dépendance divulgué'
    }
}finally{
    Get-Module|Where-Object{$_.Path -and $_.Path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)}|Remove-Module -Force
    Remove-Item -LiteralPath $temp -Recurse -Force
}
$report=[pscustomobject]@{Schema=1;Suite='CliOutput';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=($env:OS -eq 'Windows_NT');ADExecuted=$false;WPFExecuted=$false;Scope='Scripts CLI réels copiés ; intégrité et moteur remplacés par fixtures ; vrais processus enfants et fonctions diagnostic avec doubles TCP/DNS.';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
if($report.Failed){exit 1}
Write-Host ('CLI output : '+$report.Passed+'/'+$report.Total+' PASS')
