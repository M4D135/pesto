#requires -Version 5.1
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Non-tautologie rejouable du controle avant publication du scenario administre (point 111).
# Chaque mutation d'une copie hors sac du validateur integrateur, du point d'entree ou du closure du moteur
# doit changer le resultat attendu : une garde qui ne tue aucun cas n'est pas une garde.
# Les gardes de forme du scenario sont redondantes avec ConvertTo-PestoScenario : elles sont frappees la
# jambe du moteur decrochee, sinon le moteur masquerait la mutation et la garde passerait pour operative.
# Les gardes de valeurs sont frappees seches : le moteur, lui, ne controle pas les valeurs candidates.
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
$candidats=[ordered]@{
    'valide'='{"Schema":1,"Name":"Portables Paris","Required":["Type","ServiceCode"],"Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"INF"}}'
    'court'='{"Schema":1,"Name":"AB","Required":["Type"],"Allowed":{"Type":["P"]},"Locked":{}}'
    'allowed-absent'='{"Schema":1,"Name":"A","Required":["Type"],"Locked":{}}'
    'locked-absent'='{"Schema":1,"Name":"A","Required":["Type"],"Allowed":{"Type":["P"]}}'
    'allowed-nul'='{"Schema":1,"Name":"A","Required":[],"Allowed":null,"Locked":{}}'
    'locked-nul'='{"Schema":1,"Name":"A","Required":[],"Allowed":{},"Locked":null}'
    'required-chaine'='{"Schema":1,"Name":"A","Required":"Type","Allowed":{},"Locked":{}}'
    'nom-numerique'='{"Schema":1,"Name":123,"Required":[],"Allowed":{},"Locked":{}}'
    'obligatoire-libre'='{"Schema":1,"Name":"Portables Paris","Required":["Type","TargetOU"],"Allowed":{"Type":["P"]},"Locked":{}}'
}
$valeurs=[ordered]@{
    'conformes'='{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local"}'
    'type-interdit'='{"Type":"V","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local"}'
    'verrou-modifie'='{"Type":"P","SiteCode":"PA","ServiceCode":"inf","TargetOU":"OU=Paris,DC=example,DC=local"}'
    'obligatoire-vide'='{"Type":"P","SiteCode":"PA","ServiceCode":"   ","TargetOU":"OU=Paris,DC=example,DC=local"}'
    'blanc'='{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"   "}'
    'champ-extra'='{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=Paris,DC=example,DC=local","Compte":"X"}'
    'targetou-controle'='{"Type":"P","SiteCode":"PA","ServiceCode":"INF","TargetOU":"OU=@CTRL@Paris,DC=example,DC=local"}'
}
function New-Tree{
    param([scriptblock[]]$Mutations,[string]$IntegrityBody)
    if(-not $IntegrityBody){$IntegrityBody='function Test-PestoPackage {param($Root);$true}'}
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoForm111-'+[Guid]::NewGuid().ToString('N'))
    $install=Join-Path $temp 'pack'
    foreach($relative in @('wad/Pesto-Contracts.ps1','wad/Pesto-Policy.ps1','wad/Pesto-ManagedPolicy.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoManagedScenario.ps1')){
        $destination=Join-Path $install $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    [IO.File]::WriteAllText((Join-Path $install 'wad/Pesto-Integrity.ps1'),$IntegrityBody,[Text.UTF8Encoding]::new($false))
    $tree=@(Get-ChildItem -LiteralPath $install -Recurse -File|ForEach-Object{$_.FullName.Substring($install.Length+1).Replace('\','/')})
    Check (@(Compare-Object -ReferenceObject $blanc -DifferenceObject $tree).Count -eq 0) 'la copie a derive de la liste blanche'
    if($Mutations){foreach($mutation in $Mutations){& $mutation $install}}
    # Aucun registre de l'hote : la feuille rend une strategie absente, y compris pour le mutant sans garde.
    [IO.File]::AppendAllText((Join-Path $install 'wad/Pesto-ManagedPolicy.ps1'),"`nfunction Get-PestoManagedPolicy { [pscustomobject]@{Values=[pscustomobject]@{};Configured=`$false} }`n",[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Temp=$temp;Install=$install;Entry=(Join-Path $install 'integrations/Test-PestoManagedScenario.ps1')}
}
function Invoke-Mutation{
    param([string]$Label,[scriptblock[]]$Mutations,[string]$Candidate,[string]$Values,[string]$IntegrityBody,[switch]$FromRegistry,[int]$ExpectedExit,[string]$ExpectedMessage,[object]$ExpectedEngineAccepted)
    $tree=New-Tree -Mutations $Mutations -IntegrityBody $IntegrityBody
    try{
        $arguments=@('-Installation',$tree.Install,'-AsJson')
        if($FromRegistry){
            # Lier seulement la donnee de plateforme, apres la mutation : la comparaison du produit reste reelle.
            # La suppression de sa garde doit toujours changer le message ferme, meme sur un runner Windows.
            $doc=Read-Utf8File -Path $tree.Entry
            $doc.Text=$doc.Text.Replace('[Environment]::OSVersion.Platform',"'Unix'")
            Write-Utf8File -Path $tree.Entry -Doc $doc
            $arguments+=@('-FromRegistry')
        }
        else{
            $path=Join-Path $tree.Temp ($Candidate+'.json')
            [IO.File]::WriteAllText($path,$candidats[$Candidate],[Text.UTF8Encoding]::new($false))
            $arguments+=@('-ScenarioPath',$path)
            if($Values){
                $valuesPath=Join-Path $tree.Temp ($Candidate+'-'+$Values+'.json')
                $valeurs[$Values].Replace('@CTRL@',[string][char]1)|Out-Null;[IO.File]::WriteAllText($valuesPath,$valeurs[$Values].Replace('@CTRL@',[string][char]1),[Text.UTF8Encoding]::new($false))
                $arguments+=@('-ValuesPath',$valuesPath)
            }
        }
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $lines=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tree.Entry @arguments 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE;$ErrorActionPreference=$previous
        $text=$lines -join "`n"
        Check ($code -eq $ExpectedExit) ($Label+': code '+$code+' attendu '+$ExpectedExit+' : '+$text)
        $report=$text|ConvertFrom-Json
        Check ($report.ExitCode -eq $ExpectedExit) ($Label+': rapport incoherent avec le processus : '+$report.ExitCode)
        if($ExpectedMessage){Check ($report.Message -ceq $ExpectedMessage) ($Label+': message attendu '+$ExpectedMessage+' recu '+$report.Message)}
        if($null -ne $ExpectedEngineAccepted){Check ([bool]$report.EngineAccepted -eq [bool]$ExpectedEngineAccepted) ($Label+': jambe du moteur attendue '+[bool]$ExpectedEngineAccepted+' recue '+[bool]$report.EngineAccepted)}
        Check (([bool]$report.Publishable) -eq ($ExpectedExit -eq 0)) ($Label+': publiable incoherent avec le code de sortie')
    }finally{Remove-Item -LiteralPath $tree.Temp -Recurse -Force}
}
$module={param($install) Join-Path $install 'integrations/Pesto.Optional.psm1'}
$entree={param($install) Join-Path $install 'integrations/Test-PestoManagedScenario.ps1'}
$politique={param($install) Join-Path $install 'wad/Pesto-Policy.ps1'}
$mutationChampsObligatoires={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$null -eq \$Scenario\.PSObject\.Properties\[\$name\]\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationCarteNulle={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$null -eq \$map -or \$map -is \[string\] -or \$map -is \[ValueType\]\)' -Replacement 'if($map -is [string] -or $map -is [ValueType])'
    Write-Utf8File -Path $path -Doc $doc}
$mutationRequiredChaine={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$Scenario\.Required -is \[string\]\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationNomLache={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '-or \$Scenario\.Name -isnot \[string\] -or \$Scenario\.Name -notmatch ''\^\[\^\\x00-\\x1f\]\{1,80\}\$''' -Replacement ''
    Write-Utf8File -Path $path -Doc $doc}
$mutationValeurHorsListe={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$Values\.\$field -cnotin \$allowed\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationVerrouInsensible={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$Values\.\$field -cne \$Scenario\.Locked\.\$field' -Replacement '$Values.$field -ne $Scenario.Locked.$field'
    Write-Utf8File -Path $path -Doc $doc}
$mutationObligatoireAveugle={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\[string\]::IsNullOrWhiteSpace\(\[string\]\$Values\.\$field\)' -Replacement '[string]::IsNullOrEmpty([string]$Values.$field)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationChampNonAdmis={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$property\.Name -cnotin \$fields\)\{\$errors\.Add\(''Champ non admis : ''' -Replacement 'if($false){$errors.Add(''Champ non admis : '''
    Write-Utf8File -Path $path -Doc $doc}
$mutationValeurSansControle={param($install)
    $path=& $module $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern ' -or \$Values\.\$field -match ''\[\\x00-\\x1f\\x7f\]''' -Replacement ''
    Write-Utf8File -Path $path -Doc $doc}
$mutationJambeMoteur={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'try\{\[void\]\(ConvertTo-PestoScenario \$scenario\)' -Replacement 'try{[void]($scenario)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationMoteurDurci={param($install)
    $path=& $politique $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$Value\.Name -notmatch ''\^\[\^\\x00-\\x1f\]\{1,80\}\$''\)\{throw ''Scenario invalide\.''\}' -Replacement '$Value.Name -notmatch ''^[^\x00-\x1f]{1,80}$'' -or $Value.Name.Length -lt 3){throw ''Scenario invalide.''}'
    Write-Utf8File -Path $path -Doc $doc}
$mutationIntegrite={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(-not\(Test-PestoPackage -Root \$Installation\)\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}
$mutationPlateforme={param($install)
    $path=& $entree $install;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\[Environment\]::OSVersion\.Platform -ne ''Win32NT''\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc}

Invoke-Mutation -Label 'Temoin scenario conforme' -Candidate 'valide' -Values 'conformes' -ExpectedExit 0
Invoke-Mutation -Label 'Temoin forme refusee par le moteur' -Candidate 'allowed-absent' -ExpectedExit 96 -ExpectedEngineAccepted ([bool]$false)
Invoke-Mutation -Label 'Temoin valeur hors liste' -Candidate 'valide' -Values 'type-interdit' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin verrou modifie' -Candidate 'valide' -Values 'verrou-modifie' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin champ obligatoire vide' -Candidate 'valide' -Values 'obligatoire-vide' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin champ obligatoire libre laisse blanc' -Candidate 'obligatoire-libre' -Values 'blanc' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin champ non admis' -Candidate 'valide' -Values 'champ-extra' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin valeur avec caractere de controle' -Candidate 'valide' -Values 'targetou-controle' -ExpectedExit 96
Invoke-Mutation -Label 'Temoin strategie hors Windows' -FromRegistry -ExpectedExit 96 -ExpectedMessage 'La stratégie ordinateur exige Windows : aucun scénario n''est déduit hors Windows.'
Invoke-Mutation -Label 'Temoin integrite non confirmee' -Candidate 'valide' -IntegrityBody 'function Test-PestoPackage {param($Root);$false}' -ExpectedExit 96 -ExpectedMessage 'Intégrité du paquet non confirmée.'

Invoke-Mutation -Label 'Garde valeur hors liste eteinte' -Mutations @($mutationValeurHorsListe) -Candidate 'valide' -Values 'type-interdit' -ExpectedExit 0
Invoke-Mutation -Label 'Garde verrou rendue insensible a la casse' -Mutations @($mutationVerrouInsensible) -Candidate 'valide' -Values 'verrou-modifie' -ExpectedExit 0
Invoke-Mutation -Label 'Garde champ obligatoire aveugle aux blancs' -Mutations @($mutationObligatoireAveugle) -Candidate 'obligatoire-libre' -Values 'blanc' -ExpectedExit 0
Invoke-Mutation -Label 'Garde champ non admis eteinte' -Mutations @($mutationChampNonAdmis) -Candidate 'valide' -Values 'champ-extra' -ExpectedExit 0
Invoke-Mutation -Label 'Garde caracteres de controle de valeur eteinte' -Mutations @($mutationValeurSansControle) -Candidate 'valide' -Values 'targetou-controle' -ExpectedExit 0

Invoke-Mutation -Label 'Forme : champs obligatoires encore exigés sans la jambe du moteur' -Mutations @($mutationJambeMoteur) -Candidate 'allowed-absent' -ExpectedExit 96
Invoke-Mutation -Label 'Forme : champs obligatoires eteints et jambe du moteur decrochee' -Mutations @($mutationJambeMoteur,$mutationChampsObligatoires,$mutationCarteNulle) -Candidate 'allowed-absent' -ExpectedExit 0
Invoke-Mutation -Label 'Forme : champs obligatoires eteints et jambe du moteur decrochee (Locked)' -Mutations @($mutationJambeMoteur,$mutationChampsObligatoires,$mutationCarteNulle) -Candidate 'locked-absent' -ExpectedExit 0
Invoke-Mutation -Label 'Forme : carte nulle acceptee et jambe du moteur decrochee' -Mutations @($mutationJambeMoteur,$mutationCarteNulle) -Candidate 'allowed-nul' -ExpectedExit 0
Invoke-Mutation -Label 'Forme : carte nulle acceptee et jambe du moteur decrochee (Locked)' -Mutations @($mutationJambeMoteur,$mutationCarteNulle) -Candidate 'locked-nul' -ExpectedExit 0
Invoke-Mutation -Label 'Forme : Required en chaine accepte et jambe du moteur decrochee' -Mutations @($mutationJambeMoteur,$mutationRequiredChaine) -Candidate 'required-chaine' -ExpectedExit 0
Invoke-Mutation -Label 'Forme : Nom non chaine accepte et jambe du moteur decrochee' -Mutations @($mutationJambeMoteur,$mutationNomLache) -Candidate 'nom-numerique' -ExpectedExit 0

Invoke-Mutation -Label 'Moteur durci : la jambe du moteur refuse' -Mutations @($mutationMoteurDurci) -Candidate 'court' -ExpectedExit 96 -ExpectedEngineAccepted ([bool]$false)
Invoke-Mutation -Label 'Moteur durci et jambe decrochee : plus rien ne refuse' -Mutations @($mutationMoteurDurci,$mutationJambeMoteur) -Candidate 'court' -ExpectedExit 0

Invoke-Mutation -Label 'Controle d integrite decroche' -Mutations @($mutationIntegrite) -Candidate 'valide' -IntegrityBody 'function Test-PestoPackage {param($Root);$false}' -ExpectedExit 0
Invoke-Mutation -Label 'Garde de plateforme decrochee hors Windows' -Mutations @($mutationPlateforme) -FromRegistry -ExpectedExit 96 -ExpectedMessage 'Aucun scénario administré lisible dans la stratégie ordinateur.'

Write-Output ('ManagedScenario111FormMutations : '+$n+'/'+$n+' PASS')
