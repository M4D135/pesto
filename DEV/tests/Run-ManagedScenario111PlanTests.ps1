#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 111 : la jambe plans du controle avant publication d'un scenario administre (champs autorises,
# obligatoires, verrouilles). Le point d'entree integrations/Test-PestoManagedScenario.ps1 est joue comme un
# vrai processus enfant sur un paquet reconstruit en dossier temporaire. Les modules du moteur
# (Pesto-Contracts, Pesto-Policy, Pesto-ManagedPolicy) et le validateur integrateur sont les fichiers reels :
# c'est Assert-PestoOperationPolicy, la garde que Pesto appelle avant toute lecture AD et avant chaque effet,
# qui juge les plans, sur les valeurs que le moteur derive lui-meme du nom du poste. Seule l'integrite du
# paquet est doublee, sans quoi rien ne serait jouable hors Windows. Aucun appel AD, registre ou VM.
$root=Split-Path $PSScriptRoot -Parent
$hostExe=(Get-Process -Id $PID).Path
$cases=[Collections.Generic.List[object]]::new()
function Require-Plan {param($Value,[string]$Message);if(-not $Value){throw $Message}}
function Case-Plan {param($Name,[scriptblock]$Body)
    try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('PASS '+$Name)}
    catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
$scenarioObligatoire='{"Schema":1,"Name":"CANARY-Nom-Scenario-111","Required":["Type","ServiceCode","TargetOU"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"765"}}'
$scenarioSouple='{"Schema":1,"Name":"CANARY-Nom-Scenario-Souple","Required":[],"Allowed":{},"Locked":{}}'
function New-PlanJson {param([string]$Nom,[string]$Ou,[string]$Extra='')
    $plan='{"Nom_du_PC":"PC01","Nouveau_Nom":"'+$Nom+'","OU_Actuelle":"","OU_Destination":"'+$Ou+'"'+$Extra+'}'
    return '['+$plan+']'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoPlans111-'+[Guid]::NewGuid().ToString('N'))
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
    $script:entry=Join-Path $integrations 'Test-PestoManagedScenario.ps1'
    function Write-IntegrityStub {param([string]$Body)[IO.File]::WriteAllText((Join-Path $script:wad 'Pesto-Integrity.ps1'),$Body,[Text.UTF8Encoding]::new($false))}
    function Write-JsonFile {param([string]$Name,[string]$Json)
        $path=Join-Path $temp ($Name+'-'+[Guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
        return $path}
    function Invoke-Child {param([string[]]$ChildArguments)
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $lines=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:entry @ChildArguments 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE;$ErrorActionPreference=$previous
        return [pscustomobject]@{Code=$code;Text=($lines -join "`n")}}
    function Invoke-PlanReport {param([string[]]$ChildArguments,[int]$ExpectedExit)
        $run=Invoke-Child -ChildArguments ($ChildArguments+@('-AsJson'))
        Require-Plan ($run.Code -eq $ExpectedExit) ('code '+$run.Code+' attendu pour '+$ExpectedExit+' : '+$run.Text)
        Require-Plan (-not ($run.Text -match '[^\x00-\x7F]')) ('sortie non ASCII : '+$run.Text)
        $value=$run.Text|ConvertFrom-Json
        Require-Plan ($value.ExitCode -eq $ExpectedExit) ('ExitCode du rapport incoherent avec le processus : '+$value.ExitCode)
        Require-Plan ($value.WindowsExecuted -eq $false -and $value.ADExecuted -eq $false -and $value.RegistryWritten -eq $false -and $value.PolicyChanged -eq $false) 'Le controle se declare executeur'
        Require-Plan ($value.Publishable -eq ($ExpectedExit -eq 0)) ('publiable incoherent avec le code de sortie')
        return $value}
    Write-IntegrityStub -Body 'function Test-PestoPackage {param($Root);$true}'
    $installation=@('-Installation',$install)
    $obligatoire=Write-JsonFile -Name 'scenario-obligatoire' -Json $scenarioObligatoire
    $souple=Write-JsonFile -Name 'scenario-souple' -Json $scenarioSouple
    $conforme=Write-JsonFile -Name 'plans-conformes' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local')

    Case-Plan 'Plans conformes acceptes par la garde du produit' {
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$conforme)) -ExpectedExit 0
        Require-Plan ($value.PlansChecked -and $value.PlansValid) 'plans conformes refuses'
        Require-Plan ($value.PlanCount -eq 1 -and $value.PlanErrors.Count -eq 0 -and $value.PlanFields.Count -eq 0) ('resume de plans inattendu : '+($value.PlanErrors -join ' | '))
    }
    Case-Plan 'Deux plans conformes : le nombre est enregistre' {
        $deux=Write-JsonFile -Name 'plans-deux' -Json ((New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local').TrimEnd(']')+',{"Nom_du_PC":"PC02","Nouveau_Nom":"P111302PA765002","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}]')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$deux)) -ExpectedExit 0
        Require-Plan ($value.PlanCount -eq 2 -and $value.PlansValid) ('deux plans conformes non acceptes : '+$value.PlanCount)
    }
    Case-Plan 'Valeur interdite derivee du nom du poste' {
        $path=Write-JsonFile -Name 'plans-type' -Json (New-PlanJson -Nom 'S111301PA765001' -Ou 'OU=Paris,DC=example,DC=local')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Plan refusé par le moteur : valeur interdite.') ('refus attendu : '+($value.PlanErrors -join ' | '))
        Require-Plan (@($value.PlanFields) -contains 'Type') ('champ en defaut non nomme : '+($value.PlanFields -join ' | '))
    }
    Case-Plan 'Verrou du scenario non respecte par le nom du poste' {
        $path=Write-JsonFile -Name 'plans-verrou' -Json (New-PlanJson -Nom 'P111301PA766001' -Ou 'OU=Paris,DC=example,DC=local')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Plan refusé par le moteur : champ verrouillé.') ('verrou non controle : '+($value.PlanErrors -join ' | '))
        Require-Plan (@($value.PlanFields) -contains 'ServiceCode') ('champ verrouille non nomme : '+($value.PlanFields -join ' | '))
    }
    Case-Plan 'Nom ne derivant aucun champ obligatoire' {
        $path=Write-JsonFile -Name 'plans-nom' -Json (New-PlanJson -Nom 'pasunnom' -Ou 'OU=Paris,DC=example,DC=local')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Plan refusé par le moteur : champ obligatoire.') ('obligatoire non controle : '+($value.PlanErrors -join ' | '))
        Require-Plan (@($value.PlanFields) -contains 'Type') ('champ obligatoire non nomme : '+($value.PlanFields -join ' | '))
    }
    Case-Plan 'Champ obligatoire laisse blanc : la garde scellee du moteur laisse passer, la publication est refusee' {
        $path=Write-JsonFile -Name 'plans-blanc' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou '   ')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Garde du moteur affaiblie sur un plan candidat.') ('garde affaiblie non signalee : '+($value.PlanErrors -join ' | '))
        Require-Plan (@($value.PlanFields) -contains 'TargetOU') ('champ en defaut non nomme : '+($value.PlanFields -join ' | '))
    }
    Case-Plan 'Valeur avec caractere de controle : la garde scellee du moteur laisse passer, la publication est refusee' {
        $path=Write-JsonFile -Name 'plans-controle' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou ('OU=Pa'+([string][char]1)+'ris,DC=example,DC=local'))
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Garde du moteur affaiblie sur un plan candidat.') ('caractere de controle non signale : '+($value.PlanErrors -join ' | '))
    }
    Case-Plan 'Valeur depassant la longueur admise : la garde scellee du moteur laisse passer, la publication est refusee' {
        $path=Write-JsonFile -Name 'plans-long' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou ('x'*5000))
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (@($value.PlanErrors) -contains 'Garde du moteur affaiblie sur un plan candidat.') ('longueur non signalee : '+($value.PlanErrors -join ' | '))
    }
    Case-Plan 'Un seul plan fautif suffit a refuser la publication du scenario' {
        $json=(New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local').TrimEnd(']')+',{"Nom_du_PC":"PC02","Nouveau_Nom":"P111302PA765002","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"},{"Nom_du_PC":"PC03","Nouveau_Nom":"S111303PA765003","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}]'
        $path=Write-JsonFile -Name 'plans-trois' -Json $json
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan ($value.PlanCount -eq 3) ('les trois plans n ont pas ete comptes : '+$value.PlanCount)
        Require-Plan (@($value.PlanErrors) -contains 'Plan refusé par le moteur : valeur interdite.') ('plan fautif non releve : '+($value.PlanErrors -join ' | '))
    }
    Case-Plan 'Plan blanc accepte quand rien n est obligatoire : pas de faux refus' {
        $path=Write-JsonFile -Name 'plans-souple' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou '   ')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$souple,'-PlanPath',$path)) -ExpectedExit 0
        Require-Plan ($value.PlansChecked -and $value.PlansValid) 'un plan conforme au scenario a ete refuse'
    }
    Case-Plan 'Sans -PlanPath la jambe formulaire reste seule maitresse' {
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire)) -ExpectedExit 0
        Require-Plan (-not $value.PlansChecked -and $value.PlanCount -eq 0) 'la jambe plans a tourne sans -PlanPath'
    }
    Case-Plan 'Scenario refuse : les plans ne sont pas evaluates' {
        $path=Write-JsonFile -Name 'plans-obligatoire' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local')
        $forme=Write-JsonFile -Name 'scenario-sans-locked' -Json '{"Schema":1,"Name":"CANARY-Nom-Refuse","Required":["Type"],"Allowed":{"Type":["P"]}}'
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$forme,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan (-not $value.EngineAccepted -and -not $value.ScenarioAccepted) 'la forme du scenario n a pas ete refusee'
        Require-Plan (@($value.PlanErrors) -contains 'Scénario refusé : plans non évalués.') ('les plans ont ete jugees malgré un scenario refuse : '+($value.PlanErrors -join ' | '))
    }
    Case-Plan 'Plans illisibles : absent, vide, scalaire, tableau vide, mal forme' {
        $absent=Join-Path $temp 'plans-introuvables.json'
        $vide=Write-JsonFile -Name 'plans-vide' -Json ''
        $scalaire=Write-JsonFile -Name 'plans-scalaire' -Json '42'
        $vide2=Write-JsonFile -Name 'plans-tableau-vide' -Json '[]'
        $malformee=Write-JsonFile -Name 'plans-malformee' -Json '[{"Nom_du_PC":,,,}]'
        foreach($path in @($absent,$vide,$scalaire,$vide2,$malformee)){
            $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
            Require-Plan ($value.Message -ceq 'Plans candidats illisibles.') ('message attendu pour '+$path+' : '+$value.Message)
            Require-Plan (-not $value.PlansChecked) 'la jambe plans se declare verifiee sur un fichier illisible'
        }
    }
    Case-Plan 'Plan trop volumineux et trop de plans refuses' {
        $geant=Write-JsonFile -Name 'plans-geant' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou ('y'*70000))
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$geant)) -ExpectedExit 96
        Require-Plan ($value.Message -ceq 'Plans candidats illisibles.') ('taille non bornee : '+$value.Message)
        $nombreux=Write-JsonFile -Name 'plans-nombreux' -Json ('['+((1..201|ForEach-Object{'{"Nom_du_PC":"PC'+$_+'","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}'}) -join ',')+']')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$nombreux)) -ExpectedExit 96
        Require-Plan ($value.Message -ceq 'Plans candidats illisibles.') ('nombre de plans non borne : '+$value.Message)
    }
    Case-Plan 'Chemin des plans relatif refuse avant lecture' {
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath','plans.json')) -ExpectedExit 96
        Require-Plan ($value.Message -ceq 'Chemin des plans candidats invalide.') ('message ferme attendu : '+$value.Message)
    }
    Case-Plan 'Champ de plan non admis refuse sans fuite du nom' {
        $path=Write-JsonFile -Name 'plans-extra' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local' -Extra ',"Compte":"CANARY_CHAMP_PLAN"')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan ($value.Message -ceq 'Plans candidats illisibles.') ('champ non admis non refuse : '+$value.Message)
        Require-Plan (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains('CANARY_CHAMP_PLAN')) 'le nom du champ candidat fuit dans le rapport'
    }
    Case-Plan 'Identite AD refusee avant tout appel AD' {
        $path=Write-JsonFile -Name 'plans-guid' -Json (New-PlanJson -Nom 'P111301PA765001' -Ou 'OU=Paris,DC=example,DC=local' -Extra ',"Objet_GUID":"11111111-2222-3333-4444-555555555555"')
        $value=Invoke-PlanReport -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path)) -ExpectedExit 96
        Require-Plan ($value.Message -ceq 'Un plan candidat ne doit pas porter d''identité AD.') ('garde d identite absente : '+$value.Message)
        Require-Plan (-not $value.ADExecuted) 'le controle se declare passe par AD'
        Require-Plan (-not ($value|ConvertTo-Json -Depth 6 -Compress).Contains('11111111')) 'l identite du plan fuit dans le rapport'
    }
    Case-Plan 'Le contenu des plans et le nom du scénario ne sortent jamais du rapport' {
        $path=Write-JsonFile -Name 'plans-canary' -Json (New-PlanJson -Nom 'S111301PA765001' -Ou 'OU=CANARY_EMPLACEMENT,DC=example,DC=local')
        $run=Invoke-Child -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$path,'-AsJson'))
        Require-Plan ($run.Code -eq 96) ('le plan fautif a ete publie : '+$run.Text)
        Require-Plan (-not $run.Text.Contains('CANARY-Nom-Scenario-111')) 'le nom du scenario candidat fuit dans le rapport'
        Require-Plan (-not $run.Text.Contains('CANARY_EMPLACEMENT')) 'l emplacement du plan candidat fuit dans le rapport'
        Require-Plan (-not $run.Text.Contains('S111301PA765001')) 'le nom du plan candidat fuit dans le rapport'
    }
    Case-Plan 'Aucune ecriture dans l installation pendant un controle de plans' {
        $before=@(Get-ChildItem -LiteralPath $install -Recurse -File|Sort-Object FullName|ForEach-Object{$_.FullName+';'+$_.Length+';'+$_.LastWriteTimeUtc.Ticks})
        $run=Invoke-Child -ChildArguments ($installation+@('-ScenarioPath',$obligatoire,'-PlanPath',$conforme))
        Require-Plan ($run.Code -eq 0) ('controle temoin echoue : '+$run.Text)
        $after=@(Get-ChildItem -LiteralPath $install -Recurse -File|Sort-Object FullName|ForEach-Object{$_.FullName+';'+$_.Length+';'+$_.LastWriteTimeUtc.Ticks})
        Require-Plan (@(Compare-Object -ReferenceObject $before -DifferenceObject $after).Count -eq 0) 'le controle a modifie l installation'
    }
}finally{
    if([IO.Directory]::Exists($temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
$report=[pscustomobject]@{Schema=1;Suite='ManagedScenario111Plans';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Point d entree reel joue en processus enfant ; garde Assert-PestoOperationPolicy du moteur et validateur integrateur reels, integrite du paquet doublee ; aucun appel AD, registre ou VM';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report|Select-Object Suite,Total,Passed,Failed|Format-Table
if($report.Failed){exit 1}
