#requires -Version 5.1
<#
.SYNOPSIS
Contrôle avant publication d'un scénario administré : champs autorisés, obligatoires, verrouillés.
.DESCRIPTION
Évalue un scénario candidat avec le validateur de l'intégrateur (Pesto.Optional.psm1) puis avec
ConvertTo-PestoScenario, le closure du moteur qui refusera la valeur ScenarioJson à la lecture de la
stratégie ordinateur. Les deux doivent accepter : le validateur intégrateur est plus strict sur les
valeurs, le moteur seul fait autorité sur la forme. Aucune écriture de registre, aucune lecture de
secret, aucun appel réseau, aucune mutation. Sortie fermée : 0 = publiable, 96 = refusé.
  -PlanPath ajoute la jambe réelle du produit : chaque plan candidat est passé à Assert-PestoOperationPolicy,
  la garde que Pesto appelle avant toute lecture AD et avant chaque effet, sur les valeurs que le moteur dérive
  lui-même du nom du poste (Get-PestoPlanScenarioValues), jamais sur des valeurs recopiées. Un plan que le moteur
  accepte alors que le formulaire de l'intégrateur l'aurait refusé est tenu pour un refus : la garde du moteur est
  plus faible que la sienne sur ce plan, et c'est après la GPO que le poste l'apprendrait.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Installation,[string]$ScenarioPath='',[string]$ValuesPath='',
    [string]$PlanPath='',[switch]$FromRegistry,[switch]$AsJson,[string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$messages=[ordered]@{
    Installation='Installation doit être un chemin absolu local.'
    Source='Un seul scénario candidat : -ScenarioPath ou -FromRegistry.'
    Integrity='Intégrité du paquet non confirmée.'
    Engine='Chargement du moteur de stratégie impossible.'
    Module='Chargement du validateur intégrateur impossible.'
    Lecture='Scénario candidat illisible.'
    Plateforme='La stratégie ordinateur exige Windows : aucun scénario n''est déduit hors Windows.'
    Registre='Aucun scénario administré lisible dans la stratégie ordinateur.'
    Plans='Chemin des plans candidats invalide.'
    LecturePlans='Plans candidats illisibles.'
    Identite='Un plan candidat ne doit pas porter d''identité AD.'
    Evaluation='Scénario candidat non évaluable.'
}
# Le texte brut d'une exception peut répéter un contenu candidat ou un chemin : seules ces formes fermées sortent.
$formClosed=@('Champ de scénario inconnu.','Scénario invalide.','Liste de champs requis invalide.','Champ de règle inconnu.','Liste de scénario invalide.','Valeur de scénario invalide.','Un verrou exige une valeur unique.','Verrou hors des valeurs autorisées.','Trop de champs requis.','Champ requis inconnu.')
$engineClosed=@('Scenario invalide.','Champs obligatoires invalides.','Champ obligatoire inconnu.','Liste de scenario invalide.','Valeur de scenario invalide.','Un verrou exige une valeur unique.','Verrou hors des valeurs autorisees.','Objet structuré attendu.')
$valueClosed=@('^Champ obligatoire : (Type|SiteCode|ServiceCode|TargetOU)$','^Valeur hors scénario : (Type|SiteCode|ServiceCode|TargetOU)$','^Champ verrouillé : (Type|SiteCode|ServiceCode|TargetOU)$','^Valeur invalide : (Type|SiteCode|ServiceCode|TargetOU)$')
$planFields=@('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID')
$scenarioFields=@('Type','SiteCode','ServiceCode','TargetOU')
function Close-PestoPlanRefusal {
    # Le nom du scénario candidat est libre : il n'est jamais recopié, seules ces formes sortent.
    param([string]$Text)
    if($Text -like 'Scenario * : champ obligatoire *'){return 'Plan refusé par le moteur : champ obligatoire.'}
    if($Text -like 'Scenario * : valeur interdite pour *'){return 'Plan refusé par le moteur : valeur interdite.'}
    if($Text -like 'Scenario * : champ verrouille *'){return 'Plan refusé par le moteur : champ verrouillé.'}
    return 'Plan refusé par le moteur.'
}
function Get-PestoPlanField {
    param([string]$Text)
    $tail=($Text -split '\s+')[-1]
    if($tail -cin $scenarioFields){return $tail}
    return ''
}
function Close-PestoPreflightError {
    param([string]$Text,[string[]]$Exact,[string[]]$Pattern,[string]$Fallback)
    if($Text -cin $Exact){return $Text}
    foreach($pattern in $Pattern){if($Text -match $pattern){return $Text}}
    if($Text -like 'Champ non admis : *'){return 'Champ non admis.'}
    if($Text -like 'Champ non autorisé : *'){return 'Champ de scénario non autorisé.'}
    if($Text -like 'Champ obligatoire absent : *'){return 'Champ de scénario absent.'}
    return $Fallback
}
$report=[ordered]@{Schema=1;Product='Pesto';Purpose='ManagedScenarioPreflight';
    Scope='Évaluation locale d''un scénario administré candidat ; aucune écriture de registre, aucune lecture AD, aucune mutation'
    Source='';ScenarioAccepted=$false;FormErrors=@();EngineAccepted=$false;EngineError='';
    ValuesChecked=$false;ValuesValid=$false;ValueErrors=@();
    PlansChecked=$false;PlansValid=$false;PlanCount=0;PlanErrors=@();PlanFields=@();Publishable=$false;
    WindowsExecuted=$false;ADExecuted=$false;RegistryWritten=$false;PolicyChanged=$false;
    ExitCode=96;Message=''}
$phase='Installation'
try{
    if(-not[IO.Path]::IsPathRooted($Installation)){throw 'Installation doit être un chemin absolu local.'}
    $phase='Source'
    if([bool]$ScenarioPath -eq [bool]$FromRegistry){throw 'Un seul scénario candidat : -ScenarioPath ou -FromRegistry.'}
    $runtime=Join-Path $Installation 'wad'
    $phase='Integrity'
    . (Join-Path $runtime 'Pesto-Integrity.ps1')
    if(-not(Test-PestoPackage -Root $Installation)){throw 'Intégrité du paquet non confirmée.'}
    $phase='Engine'
    foreach($file in @('Pesto-Contracts.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1')){. (Join-Path $runtime $file)}
    $phase='Module'
    Import-Module (Join-Path $Installation 'integrations/Pesto.Optional.psm1') -Force
    $phase='Lecture'
    if($FromRegistry){
        $phase='Plateforme'
        if([Environment]::OSVersion.Platform -ne 'Win32NT'){throw 'La stratégie ordinateur exige Windows.'}
        $phase='Registre'
        $managed=Get-PestoManagedPolicy
        if($null -eq $managed.Values.PSObject.Properties['Scenario']){throw 'Aucun scénario administré dans la stratégie ordinateur.'}
        $scenario=$managed.Values.Scenario
        $report['Source']='strategie-ordinateur'
    }else{
        if(-not[IO.Path]::IsPathRooted($ScenarioPath)){throw 'Scénario candidat illisible.'}
        $raw=[IO.File]::ReadAllBytes($ScenarioPath)
        if($raw.Length -eq 0 -or $raw.Length -gt 65536){throw 'Scénario candidat illisible.'}
        $scenario=([Text.UTF8Encoding]::new($false).GetString($raw)|ConvertFrom-Json -ErrorAction Stop)
        $report['Source']='fichier'
    }
    $values=[pscustomobject]@{}
    if($ValuesPath){
        if(-not[IO.Path]::IsPathRooted($ValuesPath)){throw 'Scénario candidat illisible.'}
        $rawValues=[IO.File]::ReadAllBytes($ValuesPath)
        if($rawValues.Length -eq 0 -or $rawValues.Length -gt 65536){throw 'Scénario candidat illisible.'}
        $values=([Text.UTF8Encoding]::new($false).GetString($rawValues)|ConvertFrom-Json -ErrorAction Stop)
        $report['ValuesChecked']=$true
    }
    $plans=@()
    if($PlanPath){
        $phase='Plans'
        if(-not[IO.Path]::IsPathRooted($PlanPath)){throw 'Chemin des plans candidats invalide.'}
        $phase='LecturePlans'
        $rawPlans=[IO.File]::ReadAllBytes($PlanPath)
        if($rawPlans.Length -eq 0 -or $rawPlans.Length -gt 65536){throw 'Plans candidats illisibles.'}
        $parsed=([Text.UTF8Encoding]::new($false).GetString($rawPlans)|ConvertFrom-Json -ErrorAction Stop)
        if($null -eq $parsed -or $parsed -is [string] -or $parsed -is [ValueType]){throw 'Plans candidats illisibles.'}
        $plans=@($parsed)
        if($plans.Count -lt 1 -or $plans.Count -gt 200){throw 'Plans candidats illisibles.'}
        # Forme fermée : rien d'autre que ce que la garde du produit lit ne peut entrer, sinon un contenu
        # candidat arbitraire arriverait dans le rapport.
        foreach($plan in $plans){
            if($null -eq $plan -or $plan -is [string] -or $plan -is [ValueType]){throw 'Plans candidats illisibles.'}
            foreach($property in $plan.PSObject.Properties){
                if($property.Name -cnotin $planFields){throw 'Plans candidats illisibles.'}
                if($null -ne $property.Value -and $property.Value -isnot [string]){throw 'Plans candidats illisibles.'}
            }
        }
        # La branche identité de la garde appelle Get-ADComputer : hors Windows elle serait un échec de
        # commande, sur la cible une lecture AD. Aucun des deux n'est le contrôle demandé.
        $phase='Identite'
        foreach($plan in $plans){if($null -ne $plan.PSObject.Properties['Objet_GUID']){throw 'Un plan candidat ne doit pas porter d''identité AD.'}}
        $report['PlansChecked']=$true;$report['PlanCount']=$plans.Count
    }
    $phase='Evaluation'
    $form=$null
    try{$form=Test-PestoScenarioInput $scenario $values}
    catch{$report['FormErrors']=@(Close-PestoPreflightError -Text ([string]$_.Exception.Message) -Exact $formClosed -Pattern @() -Fallback 'Scénario candidat refusé.')}
    # Sans valeurs candidates, les erreurs de valeurs du formulaire ne veulent rien dire : elles seraient
    # toutes « champ obligatoire ». Seule la forme du scénario est jugée dans ce cas.
    if($null -ne $form -and $report['ValuesChecked']){
        $report['ValueErrors']=@($form.Errors|ForEach-Object{Close-PestoPreflightError -Text ([string]$_) -Exact $formClosed -Pattern $valueClosed -Fallback 'Valeur candidate refusée.'})
        $report['ValuesValid']=[bool]$form.Valid
    }
    try{[void](ConvertTo-PestoScenario $scenario);$report['EngineAccepted']=$true}
    catch{$report['EngineError']=Close-PestoPreflightError -Text ([string]$_.Exception.Message) -Exact $engineClosed -Pattern @() -Fallback 'Scénario refusé par le moteur.'}
    $report['ScenarioAccepted']=($null -ne $form -and $report['EngineAccepted'])
    if($report['PlansChecked']){
        $phase='Plans'
        $planErrors=[Collections.Generic.List[string]]::new();$planSeen=[Collections.Generic.List[string]]::new()
        if(-not $report['ScenarioAccepted']){[void]$planErrors.Add('Scénario refusé : plans non évalués.')}
        else{
            # Le scénario candidat est posé comme la stratégie ordinateur le poserait, puis c'est la garde du
            # produit elle qui juge : rien ici ne réimplémente ses règles.
            $merged=Merge-PestoManagedPolicy (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1}) -LocalOnly) ([pscustomobject]@{Values=[pscustomobject]@{Scenario=$scenario}})
            foreach($plan in $plans){
                # Le moteur dérive les champs du nom réel du poste : un fichier de valeurs ne dit rien de cela.
                $derived=Get-PestoPlanScenarioValues $plan
                $refusal=''
                try{[void](Assert-PestoOperationPolicy -Plan $plan -Policy $merged)}catch{$refusal=[string]$_.Exception.Message}
                if($refusal){
                    [void]$planErrors.Add((Close-PestoPlanRefusal -Text $refusal))
                    $field=Get-PestoPlanField -Text $refusal;if($field){[void]$planSeen.Add($field)}
                    continue
                }
                # Le moteur vient d'accepter ce que le formulaire refuse : valeur obligatoire blanche, caractère
                # de contrôle ou longueur. La garde scellée est aveugle ici ; refusée avant publication plutôt
                # qu'apprise par le poste après la GPO.
                $planForm=$null
                try{$planForm=Test-PestoScenarioInput $scenario $derived}
                catch{[void]$planErrors.Add('Garde du moteur affaiblie sur un plan candidat.')}
                if($null -ne $planForm -and -not [bool]$planForm.Valid){
                    [void]$planErrors.Add('Garde du moteur affaiblie sur un plan candidat.')
                    foreach($planError in @($planForm.Errors)){$field=Get-PestoPlanField -Text ([string]$planError);if($field){[void]$planSeen.Add($field)}}
                }
            }
        }
        $report['PlanErrors']=@($planErrors|Select-Object -Unique)
        $report['PlanFields']=@($planSeen|Select-Object -Unique)
        $report['PlansValid']=($report['PlanErrors'].Count -eq 0)
    }
    $report['Publishable']=($report['ScenarioAccepted'] -and (-not $report['ValuesChecked'] -or $report['ValuesValid']) -and (-not $report['PlansChecked'] -or $report['PlansValid']))
    $report['ExitCode']=if($report['Publishable']){0}else{96}
    $report['Message']=if($report['Publishable']){'Scénario publiable.'}else{'Scénario candidat refusé.'}
}catch{
    $message=[string]$messages[$phase];if(-not $message){$message='Échec du contrôle du scénario.'}
    $report['Message']=$message;$report['ExitCode']=96
}
$code=[int]$report['ExitCode']
if($ReportPath){
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 6))
        $stream=[IO.File]::Open([IO.Path]::GetFullPath($ReportPath),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    }catch{$code=96}
}
if($AsJson){
    $json=$report|ConvertTo-Json -Depth 6 -Compress
    [regex]::Replace($json,'[^\x00-\x7F]',[Text.RegularExpressions.MatchEvaluator]{param($m) '\u{0:x4}' -f [int][char]$m.Value[0]})
}else{$report}
exit $code
