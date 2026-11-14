#requires -Version 5.1
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Non-tautologie rejouable de la jambe plans du controle avant publication du scenario administre (point 111).
# Chaque mutation d'une copie hors sac du point d'entree ou du validateur integrateur doit changer le resultat
# attendu : une garde qui ne tue aucun cas n'est pas une garde. Les deux jambes (garde Assert-PestoOperationPolicy
# du moteur, validateur de l'integrateur) sont redondantes sur les valeurs : chacune est frappee seche quand
# l'autre porte, et en paire quand aucune ne doit rester. Le test differentiel final confronte le verdict publie
# du point d'entree au verdict des deux gardes appelees en direct, sur un corpus croise, avec controle de
# non-vacuite : il prouve que le corpus exerce reellement l'aveuglement de la garde scellee du moteur.
# Aucun appel AD, registre ou VM.
$root=Split-Path $PSScriptRoot -Parent
$hostExe=(Get-Process -Id $PID).Path
$n=0
function Check($ok,$message){if(-not $ok){throw $message};$script:n++}
function Read-Utf8File{
    param([string]$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset=if($hasBom){3}else{0}
    return [pscustomobject]@{Text=[Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset);HasBom=$hasBom}
}
function Write-Utf8File{param([string]$Path,[pscustomobject]$Doc)[IO.File]::WriteAllText($Path,$Doc.Text,[Text.UTF8Encoding]::new($Doc.HasBom))}
function Replace-Once{
    param([pscustomobject]$Doc,[string]$Pattern,[string]$Replacement)
    $found=[regex]::Matches($Doc.Text,$Pattern)
    Check ($found.Count -eq 1) ('le motif de mutation doit correspondre une seule fois : '+$Pattern)
    $m=$found[0]
    $Doc.Text=$Doc.Text.Substring(0,$m.Index)+$Replacement+$Doc.Text.Substring($m.Index+$m.Length)
}
$blanc=@('wad/Pesto-Contracts.ps1','wad/Pesto-Policy.ps1','wad/Pesto-ManagedPolicy.ps1','wad/Pesto-Integrity.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoManagedScenario.ps1')
$planBon='{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}'
$candidats=[ordered]@{
    'obligatoire'='{"Schema":1,"Name":"CANARY-Nom-Scenario-111","Required":["Type","ServiceCode","TargetOU"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"765"}}'
    'sans-locked'='{"Schema":1,"Name":"CANARY-Nom-Refuse","Required":["Type"],"Allowed":{"Type":["P"]}}'
}
$plans=[ordered]@{
    'conformes'='['+$planBon+']'
    'type-interdit'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"S111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}]'
    'obligatoire-blanc'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"   "}]'
    'caractere-controle'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Pa@CTRL@ris,DC=example,DC=local"}]'
    'trop-long'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"@LONG@"}]'
    'champ-extra'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local","Compte":"CANARY_CHAMP_PLAN"}]'
    'objet-guid'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local","Objet_GUID":"11111111-2222-3333-4444-555555555555"}]'
    'geant'='[{"Nom_du_PC":"PC01","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"@ENORME@"}]'
    'gros-volume'=('['+((1..200|ForEach-Object{'{"Nom_du_PC":"PC'+$_+'","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU='+('z'*4000)+',DC=example,DC=local"}'}) -join ',')+']')
    'nombreux'=('['+((1..201|ForEach-Object{'{"Nom_du_PC":"PC'+$_+'","Nouveau_Nom":"P111301PA765001","OU_Actuelle":"","OU_Destination":"OU=Paris,DC=example,DC=local"}'}) -join ',')+']')
}
function New-Tree{
    param([scriptblock[]]$Mutations)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoPlan111-'+[Guid]::NewGuid().ToString('N'))
    $install=Join-Path $temp 'pack'
    foreach($relative in @('wad/Pesto-Contracts.ps1','wad/Pesto-Policy.ps1','wad/Pesto-ManagedPolicy.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoManagedScenario.ps1')){
        $destination=Join-Path $install $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    [IO.File]::WriteAllText((Join-Path $install 'wad/Pesto-Integrity.ps1'),'function Test-PestoPackage {param($Root);$true}',[Text.UTF8Encoding]::new($false))
    $tree=@(Get-ChildItem -LiteralPath $install -Recurse -File|ForEach-Object{$_.FullName.Substring($install.Length+1).Replace('\','/')})
    Check (@(Compare-Object -ReferenceObject $blanc -DifferenceObject $tree).Count -eq 0) 'la copie a derive de la liste blanche'
    if($Mutations){foreach($mutation in $Mutations){& $mutation $install}}
    return [pscustomobject]@{Temp=$temp;Install=$install;Entry=(Join-Path $install 'integrations/Test-PestoManagedScenario.ps1')}
}
function Write-PairFiles{
    param([string]$Temp,[string]$Candidate,[string]$Plan)
    $scenarioPath=Join-Path $Temp ($Candidate+'.json')
    [IO.File]::WriteAllText($scenarioPath,$candidats[$Candidate],[Text.UTF8Encoding]::new($false))
    $body=$plans[$Plan].Replace('@CTRL@',[string][char]1).Replace('@LONG@',('x'*5000)).Replace('@ENORME@',('y'*70000))
    $planPath=Join-Path $Temp ($Candidate+'-'+$Plan+'.json')
    [IO.File]::WriteAllText($planPath,$body,[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Scenario=$scenarioPath;Plan=$planPath;Body=$body}
}
function Invoke-Mutation{
    param([string]$Label,[scriptblock[]]$Mutations,[string]$Candidate,[string]$Plan,[int]$ExpectedExit,
        [string]$ExpectedMessage,[string[]]$ExpectedPlanErrors,[string[]]$ExpectedPlanFields,[string[]]$Forbidden,[switch]$PlansUnchecked)
    $tree=New-Tree -Mutations $Mutations
    try{
        $pair=Write-PairFiles -Temp $tree.Temp -Candidate $Candidate -Plan $Plan
        $arguments=@('-Installation',$tree.Install,'-ScenarioPath',$pair.Scenario,'-PlanPath',$pair.Plan,'-AsJson')
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $lines=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tree.Entry @arguments 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE;$ErrorActionPreference=$previous
        $text=$lines -join "`n"
        Check ($code -eq $ExpectedExit) ($Label+': code '+$code+' attendu '+$ExpectedExit+' : '+$text)
        Check (-not ($text -match '[^\x00-\x7F]')) ($Label+': sortie non ASCII : '+$text)
        $report=$text|ConvertFrom-Json
        Check ($report.ExitCode -eq $ExpectedExit) ($Label+': rapport incoherent avec le processus : '+$report.ExitCode)
        Check (([bool]$report.Publishable) -eq ($ExpectedExit -eq 0)) ($Label+': publiable incoherent avec le code de sortie')
        if($PlansUnchecked){Check (-not [bool]$report.PlansChecked) ($Label+': la jambe plans se declare verifiee sur un fichier de plans rejete')}
        else{Check ([bool]$report.PlansChecked) ($Label+': la jambe plans ne se declare pas verifiee')}
        if($ExpectedMessage){Check ($report.Message -ceq $ExpectedMessage) ($Label+': message attendu '+$ExpectedMessage+' recu '+$report.Message)}
        foreach($expected in @($ExpectedPlanErrors)){if($expected){Check (@($report.PlanErrors) -contains $expected) ($Label+': refus de plan attendu absent : '+$expected+' recu '+($report.PlanErrors -join ' | '))}}
        foreach($field in @($ExpectedPlanFields)){if($field){Check (@($report.PlanFields) -contains $field) ($Label+': champ en defaut attendu absent : '+$field+' recu '+($report.PlanFields -join ' | '))}}
        foreach($banned in @($Forbidden)){if($banned){Check (-not $text.Contains($banned)) ($Label+': contenu candidat fuit dans le rapport : '+$banned)}}
    }finally{Remove-Item -LiteralPath $tree.Temp -Recurse -Force}
}
$entree={param($install) Join-Path $install 'integrations/Test-PestoManagedScenario.ps1'}
$module={param($install) Join-Path $install 'integrations/Pesto.Optional.psm1'}
$apostrophe=[string][char]39
$mutationJambePlans={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'try\{\[void\]\(Assert-PestoOperationPolicy -Plan \$plan -Policy \$merged\)\}catch\{\$refusal=\[string\]\$_.Exception\.Message\}' -Replacement ('try{[void]($plan)}catch{$refusal='+$script:apostrophe+$script:apostrophe+'}')
    Write-Utf8File -Path $path -Doc $doc}
$mutationGardeAffaiblie={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$null -ne \$planForm -and -not \[bool\]\$planForm\.Valid\)\{' -Replacement 'if($false){'
    Write-Utf8File -Path $path -Doc $doc}
$mutationDerivation={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$derived=Get-PestoPlanScenarioValues \$plan' -Replacement ('$derived=[pscustomobject]@{Type='+$script:apostrophe+'P'+$script:apostrophe+';SiteCode='+$script:apostrophe+'PA'+$script:apostrophe+';ServiceCode='+$script:apostrophe+'765'+$script:apostrophe+';TargetOU='+$script:apostrophe+'OU=Paris,DC=example,DC=local'+$script:apostrophe+'}')
    Write-Utf8File -Path $path -Doc $doc}
$mutationFormePlan={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern ('if\(\$property\.Name -cnotin \$planFields\)\{throw '+$script:apostrophe+'Plans candidats illisibles.'+$script:apostrophe+'\}') -Replacement ('if($false){throw '+$script:apostrophe+'Plans candidats illisibles.'+$script:apostrophe+'}')
    Write-Utf8File -Path $path -Doc $doc}
$mutationTaillePlan={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$rawPlans\.Length -eq 0 -or \$rawPlans\.Length -gt 65536\)' -Replacement 'if($rawPlans.Length -eq 0)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationNombrePlans={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$plans\.Count -lt 1 -or \$plans\.Count -gt 200\)' -Replacement 'if($plans.Count -lt 1)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationIdentite={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern ('if\(\$null -ne \$plan\.PSObject\.Properties\['+$script:apostrophe+'Objet_GUID'+$script:apostrophe+'\]\)') -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationValeurHorsListe={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$Values\.\$field -cnotin \$allowed\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationObligatoireAveugle={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\[string\]::IsNullOrWhiteSpace\(\[string\]\$Values\.\$field\)' -Replacement '[string]::IsNullOrEmpty([string]$Values.$field)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationValeurSansControle={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern (' -or \$Values\.\$field -match '+$script:apostrophe+'\[\\x00-\\x1f\\x7f\]'+$script:apostrophe) -Replacement ''
    Write-Utf8File -Path $path -Doc $doc}

Invoke-Mutation -Label 'Temoin plan conforme' -Candidate 'obligatoire' -Plan 'conformes' -ExpectedExit 0
Invoke-Mutation -Label 'Temoin valeur interdite derivee du nom' -Candidate 'obligatoire' -Plan 'type-interdit' -ExpectedExit 96 -ExpectedPlanErrors @('Plan refusé par le moteur : valeur interdite.') -ExpectedPlanFields @('Type') -Forbidden @('CANARY-Nom-Scenario-111','S111301PA765001')
Invoke-Mutation -Label 'Temoin champ obligatoire blanc' -Candidate 'obligatoire' -Plan 'obligatoire-blanc' -ExpectedExit 96 -ExpectedPlanErrors @('Garde du moteur affaiblie sur un plan candidat.') -ExpectedPlanFields @('TargetOU')
Invoke-Mutation -Label 'Temoin caractere de controle' -Candidate 'obligatoire' -Plan 'caractere-controle' -ExpectedExit 96 -ExpectedPlanErrors @('Garde du moteur affaiblie sur un plan candidat.')
Invoke-Mutation -Label 'Temoin valeur trop longue' -Candidate 'obligatoire' -Plan 'trop-long' -ExpectedExit 96 -ExpectedPlanErrors @('Garde du moteur affaiblie sur un plan candidat.')
Invoke-Mutation -Label 'Temoin champ de plan non admis' -Candidate 'obligatoire' -Plan 'champ-extra' -ExpectedExit 96 -ExpectedMessage 'Plans candidats illisibles.' -PlansUnchecked -Forbidden @('CANARY_CHAMP_PLAN')
Invoke-Mutation -Label 'Temoin identite AD refusee' -Candidate 'obligatoire' -Plan 'objet-guid' -ExpectedExit 96 -ExpectedMessage 'Un plan candidat ne doit pas porter d''identité AD.' -PlansUnchecked -Forbidden @('11111111')
Invoke-Mutation -Label 'Temoin fichier de plans trop volumineux' -Candidate 'obligatoire' -Plan 'geant' -ExpectedExit 96 -ExpectedMessage 'Plans candidats illisibles.' -PlansUnchecked
Invoke-Mutation -Label 'Temoin volume de plans refuse avant lecture' -Candidate 'obligatoire' -Plan 'gros-volume' -ExpectedExit 96 -ExpectedMessage 'Plans candidats illisibles.' -PlansUnchecked
Invoke-Mutation -Label 'Temoin trop de plans' -Candidate 'obligatoire' -Plan 'nombreux' -ExpectedExit 96 -ExpectedMessage 'Plans candidats illisibles.' -PlansUnchecked
Invoke-Mutation -Label 'Temoin scenario refuse avant les plans' -Candidate 'sans-locked' -Plan 'conformes' -ExpectedExit 96 -ExpectedPlanErrors @('Scénario refusé : plans non évalués.')

Invoke-Mutation -Label 'Jambe du moteur seule decrochee : le formulaire porte encore' -Mutations @($mutationJambePlans) -Candidate 'obligatoire' -Plan 'type-interdit' -ExpectedExit 96
Invoke-Mutation -Label 'Jambe du moteur et liste autorisee eteintes : plus rien ne refuse' -Mutations @($mutationJambePlans,$mutationValeurHorsListe) -Candidate 'obligatoire' -Plan 'type-interdit' -ExpectedExit 0
Invoke-Mutation -Label 'Derivation du nom seule decrochee : la garde du moteur porte encore' -Mutations @($mutationDerivation) -Candidate 'obligatoire' -Plan 'type-interdit' -ExpectedExit 96
Invoke-Mutation -Label 'Derivation du nom et jambe du moteur eteintes : plus rien ne refuse' -Mutations @($mutationDerivation,$mutationJambePlans) -Candidate 'obligatoire' -Plan 'type-interdit' -ExpectedExit 0
Invoke-Mutation -Label 'Garde du moteur affaiblie eteinte : le plan a valeur obligatoire blanche est publie' -Mutations @($mutationGardeAffaiblie) -Candidate 'obligatoire' -Plan 'obligatoire-blanc' -ExpectedExit 0
Invoke-Mutation -Label 'Obligatoire du formulaire rendu aveugle aux blancs : le trou de la garde scellee redevient publiable' -Mutations @($mutationObligatoireAveugle) -Candidate 'obligatoire' -Plan 'obligatoire-blanc' -ExpectedExit 0
Invoke-Mutation -Label 'Controle des caracteres de controle eteint : le plan fautif est publie' -Mutations @($mutationValeurSansControle) -Candidate 'obligatoire' -Plan 'caractere-controle' -ExpectedExit 0
Invoke-Mutation -Label 'Forme des plans non verifiee : un champ inconnu passe' -Mutations @($mutationFormePlan) -Candidate 'obligatoire' -Plan 'champ-extra' -ExpectedExit 0
Invoke-Mutation -Label 'Taille des plans non bornee : un volume refuse redevient publiable' -Mutations @($mutationTaillePlan) -Candidate 'obligatoire' -Plan 'gros-volume' -ExpectedExit 0
Invoke-Mutation -Label 'Nombre de plans non borne' -Mutations @($mutationNombrePlans) -Candidate 'obligatoire' -Plan 'nombreux' -ExpectedExit 0
Invoke-Mutation -Label 'Garde d identite eteinte : la branche AD de la garde est atteinte' -Mutations @($mutationIdentite) -Candidate 'obligatoire' -Plan 'objet-guid' -ExpectedExit 96 -ExpectedMessage 'Scénario candidat refusé.' -ExpectedPlanErrors @('Plan refusé par le moteur.')

# --- Test differentiel systematique : le verdict publie doit egaler le verdict des deux gardes appelees en direct.
$tree=New-Tree
try{
    foreach($f in @('Pesto-Contracts.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1')){. (Join-Path $tree.Install ('wad/'+$f))}
    Import-Module (Join-Path $tree.Install 'integrations/Pesto.Optional.psm1') -Force
    $noms=@('P111301PA765001','S111301PA765001','V111301PA765001','pasunnom')
    $emplacements=@('OU=Paris,DC=example,DC=local','   ',('OU=Pa'+[string][char]1+'ris,DC=example,DC=local'),('x'*5000),'')
    $corpus=@(
        '{"Schema":1,"Name":"CANARY-CORPUS-1","Required":["Type","ServiceCode","TargetOU"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"765"}}',
        '{"Schema":1,"Name":"CANARY-CORPUS-2","Required":[],"Allowed":{},"Locked":{}}',
        '{"Schema":1,"Name":"CANARY-CORPUS-3","Required":["TargetOU"],"Allowed":{"Type":["P","V"]},"Locked":{}}',
        '{"Schema":1,"Name":"CANARY-CORPUS-4","Required":["Type"],"Allowed":{"Type":["P"],"TargetOU":["OU=Paris,DC=example,DC=local"]},"Locked":{}}',
        '{"Schema":1,"Name":"CANARY-CORPUS-5","Required":[],"Allowed":{},"Locked":{"TargetOU":"OU=Paris,DC=example,DC=local"}}'
    )
    $total=0;$moteurRefuse=0;$divergences=0;$acceptes=0;$divergents=0;$fuites=0
    foreach($json in $corpus){
        $scenario=$json|ConvertFrom-Json
        $merged=Merge-PestoManagedPolicy (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1}) -LocalOnly) ([pscustomobject]@{Values=[pscustomobject]@{Scenario=$scenario}})
        $scenarioPath=Join-Path $tree.Temp ('corpus-scenario-'+[Guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($scenarioPath,$json,[Text.UTF8Encoding]::new($false))
        foreach($nom in $noms){foreach($emplacement in $emplacements){
            $total++
            $plan=[pscustomobject]@{Nom_du_PC='PC01';Nouveau_Nom=$nom;OU_Actuelle='';OU_Destination=$emplacement}
            $moteurOk=$true;try{[void](Assert-PestoOperationPolicy -Plan $plan -Policy $merged)}catch{$moteurOk=$false}
            $formulaireOk=$true
            try{$forme=Test-PestoScenarioInput $scenario (Get-PestoPlanScenarioValues $plan);$formulaireOk=[bool]$forme.Valid}catch{$formulaireOk=$false}
            if(-not $moteurOk){$moteurRefuse++}elseif(-not $formulaireOk){$divergences++}else{$acceptes++}
            $planPath=Join-Path $tree.Temp ('corpus-plan-'+[Guid]::NewGuid().ToString('N')+'.json')
            [IO.File]::WriteAllText($planPath,(ConvertTo-Json @($plan) -Compress),[Text.UTF8Encoding]::new($false))
            $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
            $lines=@(& $tree.Entry -Installation $tree.Install -ScenarioPath $scenarioPath -PlanPath $planPath -AsJson 2>&1|ForEach-Object{[string]$_})
            $code=$LASTEXITCODE;$ErrorActionPreference=$previous
            $text=$lines -join "`n"
            $rapport=$text|ConvertFrom-Json
            $attendu=($moteurOk -and $formulaireOk)
            $attenduCode=96;if($attendu){$attenduCode=0}
            if(($rapport.Publishable -ne $attendu) -or ($rapport.ExitCode -ne $attenduCode)){$divergents++;Write-Host ('DIVERGENT nom='+$nom+' attendu='+$attendu+' recu='+$rapport.Publishable)}
            if($text.Contains('CANARY-CORPUS')){$fuites++}
            Remove-Item -LiteralPath $planPath -Force
        }}
        Remove-Item -LiteralPath $scenarioPath -Force
    }
    Check ($total -eq 100) ('corpus trop restreint : '+$total+' formes examinees')
    Check ($divergents -eq 0) ([string]$divergents+' formes ou le point d entree diverge des gardes appelees en direct')
    Check ($moteurRefuse -ge 40) ('corpus non vacant : seulement '+[string]$moteurRefuse+' formes refusees par la garde du moteur')
    Check ($divergences -ge 15) ('corpus non vacant : seulement '+[string]$divergences+' formes ou le moteur accepte ce que le formulaire refuse')
    Check ($acceptes -ge 15) ('corpus non vacant : seulement '+[string]$acceptes+' formes acceptees par les deux gardes')
    Check ($fuites -eq 0) 'le nom du scénario candidat fuit dans le rapport du corpus'
}finally{Remove-Item -LiteralPath $tree.Temp -Recurse -Force}

Write-Output ('ManagedScenario111PlanMutations : '+$n+'/'+$n+' PASS')
