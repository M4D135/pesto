#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 111 : le controle avant publication d'un scenario administre (champs autorises, obligatoires,
# verrouilles) est joue comme un vrai processus enfant. Le validateur integrateur
# (integrations/Pesto.Optional.psm1) et le closure du moteur (ConvertTo-PestoScenario) sont les fichiers
# reels ; seule l'integrite du paquet est doublee, sans quoi rien ne serait jouable hors Windows.
# Aucun appel AD, registre ou VM : le lecteur de strategie ordinateur est double par un registre vide.
$root=Split-Path $PSScriptRoot -Parent
$hostExe=(Get-Process -Id $PID).Path
$cases=[Collections.Generic.List[object]]::new()
function Require-Preflight {param($Value,[string]$Message);if(-not $Value){throw $Message}}
function Case-Preflight {param($Name,[scriptblock]$Body)
    try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('PASS '+$Name)}
    catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
$scenarioValide='{"Schema":1,"Name":"Portables Paris","Required":["Type","ServiceCode"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"INF"}}'
$valeursConformes='{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local"}'
# Formes que le validateur integrateur acceptait avant l'alignement et que le moteur refuse : publiees
# telles quelles, la valeur ScenarioJson faisait echouer la lecture de la strategie sur tous les postes.
$formesRefuseesParLeMoteur=[ordered]@{
    'Allowed absent'='{"Schema":1,"Name":"A","Required":["Type"],"Locked":{}}'
    'Locked absent'='{"Schema":1,"Name":"A","Required":["Type"],"Allowed":{"Type":["P"]}}'
    'Allowed nul'='{"Schema":1,"Name":"A","Required":[],"Allowed":null,"Locked":{}}'
    'Locked nul'='{"Schema":1,"Name":"A","Required":[],"Allowed":{},"Locked":null}'
    'Required en chaine'='{"Schema":1,"Name":"A","Required":"Type","Allowed":{},"Locked":{}}'
    'Nom numerique'='{"Schema":1,"Name":123,"Required":[],"Allowed":{},"Locked":{}}'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoPreflight111-'+[Guid]::NewGuid().ToString('N'))
try{
    $install=Join-Path $temp 'pack'
    $script:wad=Join-Path $install 'wad'
    $integrations=Join-Path $install 'integrations'
    [void][IO.Directory]::CreateDirectory($script:wad)
    [void][IO.Directory]::CreateDirectory($integrations)
    foreach($relative in @('wad/Pesto-Contracts.ps1','wad/Pesto-Policy.ps1','wad/Pesto-ManagedPolicy.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoManagedScenario.ps1')){
        $destination=Join-Path $install $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    # Seule la feuille de lecture du registre est doublee, jamais les validateurs ni la garde de plateforme.
    [IO.File]::AppendAllText((Join-Path $script:wad 'Pesto-ManagedPolicy.ps1'),"`nfunction Get-PestoManagedPolicy { [pscustomobject]@{Values=[pscustomobject]@{};Configured=`$false} }`n",[Text.UTF8Encoding]::new($false))
    $script:entry=Join-Path $integrations 'Test-PestoManagedScenario.ps1'
    function Write-IntegrityStub {param([string]$Body)[IO.File]::WriteAllText((Join-Path $script:wad 'Pesto-Integrity.ps1'),$Body,[Text.UTF8Encoding]::new($false))}
    function Write-Candidate {param([string]$Name,[string]$Json)
        $path=Join-Path $temp ($Name+'.json')
        [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
        return $path}
    function Invoke-Preflight {param([string[]]$ChildArguments)
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $lines=@(& $script:hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:entry @ChildArguments 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE;$ErrorActionPreference=$previous
        return [pscustomobject]@{Code=$code;Text=($lines -join "`n")}}
    function Invoke-PreflightReport {param([string[]]$ChildArguments,[int]$ExpectedExit)
        $run=Invoke-Preflight -ChildArguments ($ChildArguments+@('-AsJson'))
        Require-Preflight ($run.Code -eq $ExpectedExit) ('code '+$run.Code+' attendu pour '+$ExpectedExit+' : '+$run.Text)
        Require-Preflight (-not ($run.Text -match '[^\x00-\x7F]')) ('sortie non ASCII : '+$run.Text)
        $value=$run.Text|ConvertFrom-Json
        Require-Preflight ($value.ExitCode -eq $ExpectedExit) ('ExitCode du rapport incoherent avec le processus : '+$value.ExitCode)
        Require-Preflight ($value.WindowsExecuted -eq $false -and $value.ADExecuted -eq $false -and $value.RegistryWritten -eq $false -and $value.PolicyChanged -eq $false) 'Le controle se declare executeur'
        return $value}
    Write-IntegrityStub -Body 'function Test-PestoPackage {param($Root);$true}'
    $candidate=Write-Candidate -Name 'valide' -Json $scenarioValide
    $installation=@('-Installation',$install)

    Case-Preflight 'Scenario conforme : publie' {
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate)) -ExpectedExit 0
        Require-Preflight ($value.Publishable -and $value.ScenarioAccepted -and $value.EngineAccepted) 'scenario conforme refuse'
        Require-Preflight ($value.Source -ceq 'fichier') ('origine inattendue : '+$value.Source)
        Require-Preflight ($value.FormErrors.Count -eq 0 -and $value.ValueErrors.Count -eq 0) 'erreurs sur un scenario sans valeurs candidates'
    }
    foreach($name in $formesRefuseesParLeMoteur.Keys){
        Case-Preflight ('Forme refusee par le moteur : '+$name) {
            $path=Write-Candidate -Name ('forme-'+($name -replace '[^A-Za-z0-9]','-')) -Json $formesRefuseesParLeMoteur[$name]
            $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$path)) -ExpectedExit 96
            Require-Preflight (-not $value.Publishable -and -not $value.ScenarioAccepted) ('forme acceptee : '+$name)
            Require-Preflight (-not $value.EngineAccepted) ('le closure du moteur n a pas ete consulte pour '+$name)
        }
    }
    Case-Preflight 'Forme refusee par le moteur : nom avec caractere de controle' {
        $nom='A'+([string][char]1)+'B'
        $path=Write-Candidate -Name 'forme-controle' -Json ('{"Schema":1,"Name":"'+$nom+'","Required":[],"Allowed":{},"Locked":{}}')
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$path)) -ExpectedExit 96
        Require-Preflight (-not $value.Publishable -and -not $value.EngineAccepted) 'nom avec caractere de controle accepte'
    }
    Case-Preflight 'Valeurs candidates conformes' {
        $values=Write-Candidate -Name 'valeurs-conformes' -Json $valeursConformes
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$values)) -ExpectedExit 0
        Require-Preflight ($value.ValuesChecked -and $value.ValuesValid -and $value.ValueErrors.Count -eq 0) 'valeurs conformes refusees'
    }
    Case-Preflight 'Valeur hors des listes autorisees' {
        $values=Write-Candidate -Name 'valeurs-type' -Json '{"Type":"V","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local"}'
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$values)) -ExpectedExit 96
        Require-Preflight ($value.ValuesChecked -and -not $value.ValuesValid) 'valeur interdite acceptee'
        Require-Preflight (@($value.ValueErrors) -contains 'Valeur hors scénario : Type') ('erreur attendue absente : '+($value.ValueErrors -join ' | '))
    }
    Case-Preflight 'Valeur d un champ verrouillee modifiee' {
        $values=Write-Candidate -Name 'valeurs-verrou' -Json '{"Type":"P","SiteCode":"PA","ServiceCode":"inf","TargetOU":"OU=Paris,DC=example,DC=local"}'
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$values)) -ExpectedExit 96
        Require-Preflight (@($value.ValueErrors) -contains 'Champ verrouillé : ServiceCode') ('verrou non controle : '+($value.ValueErrors -join ' | '))
    }
    Case-Preflight 'Champ obligatoire laisse vide' {
        $values=Write-Candidate -Name 'valeurs-vides' -Json '{"Type":"P","SiteCode":"PA","ServiceCode":"   ","TargetOU":"OU=Paris,DC=example,DC=local"}'
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$values)) -ExpectedExit 96
        Require-Preflight (@($value.ValueErrors) -contains 'Champ obligatoire : ServiceCode') ('champ obligatoire non controle : '+($value.ValueErrors -join ' | '))
    }
    Case-Preflight 'Champ non admis dans les valeurs candidates' {
        $values=Write-Candidate -Name 'valeurs-extra' -Json '{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local","Compte":"CANARY_CHAMP"}'
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$values)) -ExpectedExit 96
        Require-Preflight (@($value.ValueErrors) -contains 'Champ non admis.') ('champ non admis non signale : '+($value.ValueErrors -join ' | '))
        Require-Preflight (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains('CANARY_CHAMP')) 'le nom du champ candidat fuit dans le rapport'
    }
    Case-Preflight 'Candidat illisible : absent, vide, trop volumineux, mal forme' {
        $absent=Join-Path $temp 'introuvable.json'
        $vide=Write-Candidate -Name 'vide' -Json ''
        $geant=Write-Candidate -Name 'geant' -Json ('{"Schema":1,"Name":"'+('N'*70000)+'","Required":[],"Allowed":{},"Locked":{}}')
        $malformee=Write-Candidate -Name 'malformee' -Json '{"Schema":1,"Name":"A",,,}'
        foreach($path in @($absent,$vide,$geant,$malformee)){
            $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$path)) -ExpectedExit 96
            Require-Preflight ($value.Message -ceq 'Scénario candidat illisible.') ('message attendu pour '+$path+' : '+$value.Message)
        }
    }
    Case-Preflight 'Installation relative refusee avant tout chargement' {
        $value=Invoke-PreflightReport -ChildArguments (@('-Installation','pack','-ScenarioPath',$candidate)) -ExpectedExit 96
        Require-Preflight ($value.Message -ceq 'Installation doit être un chemin absolu local.') ('message ferme attendu : '+$value.Message)
    }
    Case-Preflight 'Une seule source de scénario : ni l une ni les deux' {
        foreach($arguments in @(@(),@('-ScenarioPath',$candidate,'-FromRegistry'))){
            $value=Invoke-PreflightReport -ChildArguments ($installation+$arguments) -ExpectedExit 96
            Require-Preflight ($value.Message -ceq 'Un seul scénario candidat : -ScenarioPath ou -FromRegistry.') ('message ferme attendu : '+$value.Message)
        }
    }
    Case-Preflight 'Intégrité non confirmée : rien n est évalue' {
        Write-IntegrityStub -Body 'function Test-PestoPackage {param($Root);$false}'
        try{
            $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate)) -ExpectedExit 96
            Require-Preflight ($value.Message -ceq 'Intégrité du paquet non confirmée.') ('message ferme attendu : '+$value.Message)
            Require-Preflight (-not $value.ScenarioAccepted -and -not $value.EngineAccepted) 'un scenario a ete evalue malgre l integrite'
        }finally{Write-IntegrityStub -Body 'function Test-PestoPackage {param($Root);$true}'}
    }
    Case-Preflight 'Defaillance de la dependance : message ferme sans detail brut' {
        $marker='PESTO_PREFLIGHT_CANARY_'+[Guid]::NewGuid().ToString('N')
        Write-IntegrityStub -Body ("throw 'Integrite detruete "+$marker+"'")
        try{
            $value=Invoke-PreflightReport -ChildArguments ($installation+@('-ScenarioPath',$candidate)) -ExpectedExit 96
            Require-Preflight ($value.Message -ceq 'Intégrité du paquet non confirmée.') ('message ferme attendu : '+$value.Message)
            Require-Preflight (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains($marker)) 'le detail brut de la dependance fuit'
        }finally{Write-IntegrityStub -Body 'function Test-PestoPackage {param($Root);$true}'}
    }
    Case-Preflight 'Strategie ordinateur indisponible : refus ferme, jamais un faux publiable' {
        $value=Invoke-PreflightReport -ChildArguments ($installation+@('-FromRegistry')) -ExpectedExit 96
        $expected=if([Environment]::OSVersion.Platform -eq 'Win32NT'){'Aucun scénario administré lisible dans la stratégie ordinateur.'}else{'La stratégie ordinateur exige Windows : aucun scénario n''est déduit hors Windows.'}
        Require-Preflight ($value.Message -ceq $expected) ('message ferme attendu : '+$value.Message)
        Require-Preflight (-not $value.Publishable) 'la strategie indisponible se declare publiable'
    }
    Case-Preflight 'Rapport ecrit une seule fois et jamais ecrase' {
        $reportPath=Join-Path $temp 'rapport.json'
        $first=Invoke-Preflight -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ReportPath',$reportPath))
        Require-Preflight ($first.Code -eq 0) ('premier rapport non ecrit : '+$first.Text)
        Require-Preflight ([IO.File]::Exists($reportPath)) 'rapport absent'
        $before=[IO.File]::ReadAllText($reportPath)
        $second=Invoke-Preflight -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ReportPath',$reportPath))
        Require-Preflight ($second.Code -eq 96) ('le second appel aurait du refuser d ecraser : '+$second.Code)
        Require-Preflight ([IO.File]::ReadAllText($reportPath) -ceq $before) 'le rapport a ete ecrase'
    }
    Case-Preflight 'Aucune ecriture dans l installation pendant un controle' {
        $conformes=Write-Candidate -Name 'valeurs-temoin' -Json $valeursConformes
        $before=@(Get-ChildItem -LiteralPath $install -Recurse -File|Sort-Object FullName|ForEach-Object{$_.FullName+';'+$_.Length+';'+$_.LastWriteTimeUtc.Ticks})
        $run=Invoke-Preflight -ChildArguments ($installation+@('-ScenarioPath',$candidate,'-ValuesPath',$conformes))
        Require-Preflight ($run.Code -eq 0) ('controle temoin echoue : '+$run.Text)
        $after=@(Get-ChildItem -LiteralPath $install -Recurse -File|Sort-Object FullName|ForEach-Object{$_.FullName+';'+$_.Length+';'+$_.LastWriteTimeUtc.Ticks})
        Require-Preflight (@(Compare-Object -ReferenceObject $before -DifferenceObject $after).Count -eq 0) 'le controle a modifie l installation'
    }
}finally{
    if([IO.Directory]::Exists($temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
$report=[pscustomobject]@{Schema=1;Suite='ManagedScenarioPreflight111';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Point d entree reel joue en processus enfant ; validateur integrateur et closure du moteur reels, integrite du paquet doublee ; aucun appel AD, registre ou VM';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report|Select-Object Suite,Total,Passed,Failed|Format-Table
if($report.Failed){exit 1}
