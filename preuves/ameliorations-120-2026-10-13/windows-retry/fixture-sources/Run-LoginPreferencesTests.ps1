#requires -Version 5.1
[CmdletBinding()]
param([string]$WadPath,[string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-login-preferences-results.json'}
# Fonctions de préférence isolées. Aucun chargement du moteur, appel AD ou demande UAC.
# Les composants .ps1 de wad sont lus comme texte puis analysés par le parseur : seules les six fonctions
# testées sont définies, aucun composant n'est exécuté ni dot-sourcé.
# Fonctions de connexion déplacées dans wad\Pesto-Authentication.ps1, Write-PestoAtomicText resté dans
# wad\Pesto-Core.ps1 : chaque fonction est cherchée dans tous les composants et doit y être unique.
$ErrorActionPreference='Stop'
Set-StrictMode -Off
if(-not $WadPath){$WadPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'wad'}
# Chemin relatif résolu par PowerShell : les appels .NET ne suivent pas l'emplacement courant de la session.
$WadPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WadPath)
$load=@('Write-PestoAtomicText','Get-PestoLoginPreferencePath','ConvertFrom-PestoLoginPreference','Get-PestoLoginPreference','Save-PestoLoginPreference','Invoke-PestoLoginForget')
# Doublures définies plus bas : chacune doit remplacer une fonction réelle et unique du moteur.
$doubles=@('Get-PestoStateDirectory','Set-PestoLoginFeedback')

function Get-LiteralExpression {
    # Expression pure d'un noeud du parseur (partie droite d'une affectation).
    param([Management.Automation.Language.Ast]$Node)
    if($Node -is [Management.Automation.Language.PipelineAst]){return $Node.GetPureExpression()}
    if($Node -is [Management.Automation.Language.CommandExpressionAst]){return $Node.Expression}
    return $Node
}
function Read-EngineSources {
    # Lecture comme texte puis analyse par le parseur : aucune instruction du moteur n'est exécutée.
    param([string]$Path)
    if(-not [IO.Directory]::Exists($Path)){throw ('Dossier du moteur introuvable : '+$Path)}
    # Extension vérifiée : un filtre *.ps1 retiendrait aussi les .ps1xml par leur nom court 8.3.
    # L'agrégat CLI généré duplique les modules originaux ; il n'est pas chargé par cette fixture GUI.
    $files=@([IO.Directory]::GetFiles($Path)|Where-Object{[IO.Path]::GetExtension($_) -eq '.ps1' -and [IO.Path]::GetFileName($_) -ine 'Pesto.Engine.Runtime.ps1'}|Sort-Object)
    if($files.Count -lt 1){throw ('Aucun composant .ps1 dans '+$Path)}
    $parsed=[Collections.Generic.List[object]]::new()
    foreach($file in $files){
        $fileName=[IO.Path]::GetFileName($file)
        $text=Get-Content -LiteralPath $file -Raw -Encoding UTF8
        if($null -eq $text){$text=''}
        $fileTokens=$null;$fileErrors=$null
        $fileAst=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$fileTokens,[ref]$fileErrors)
        if($fileErrors.Count){throw ('Source PowerShell invalide ('+$fileName+') : '+(($fileErrors|ForEach-Object{$_.Message}) -join '; '))}
        $parsed.Add([pscustomobject]@{Name=$fileName;Path=$file;Ast=$fileAst})
    }
    return $parsed.ToArray()
}
function Get-EngineFunctionIndex {
    # Toutes les définitions, imbriquées comprises : une copie dans un autre composant est un doublon.
    param([object[]]$Sources)
    $index=@{}
    foreach($src in $Sources){
        foreach($def in $src.Ast.FindAll({param($Candidate) $Candidate -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
            # Une définition préfixée (global:, script:...) remplace aussi la fonction : même clé.
            $key=$def.Name -replace '^(global|script|local|private):',''
            if(-not $index.ContainsKey($key)){$index[$key]=[Collections.Generic.List[object]]::new()}
            $index[$key].Add([pscustomobject]@{File=$src.Name;Path=$src.Path;Line=$def.Extent.StartLineNumber;Definition=$def})
        }
    }
    return $index
}
function Get-UniqueEngineFunction {
    param([hashtable]$Index,[string]$Name)
    $hits=@()
    if($Index.ContainsKey($Name)){$hits=@($Index[$Name].ToArray())}
    if($hits.Count -ne 1){
        $where=@($hits|ForEach-Object{$_.File+':'+$_.Line}) -join ', '
        throw ('Fonction absente ou dupliquee : '+$Name+' ('+$hits.Count+' definition(s) '+$where+')')
    }
    return $hits[0]
}
function Get-EngineVersion {
    # Version du moteur teste : chaine litterale lue par le parseur, sans evaluer le moteur.
    param([object[]]$Sources)
    $nodes=[Collections.Generic.List[object]]::new()
    foreach($src in $Sources){
        foreach($node in $src.Ast.FindAll({
            param($Candidate)
            ($Candidate -is [Management.Automation.Language.AssignmentStatementAst]) -and
            ([string]$Candidate.Operator -eq 'Equals') -and
            ($Candidate.Left -is [Management.Automation.Language.VariableExpressionAst]) -and
            ($Candidate.Left.VariablePath.UserPath -eq 'script:Pesto_VERSION' -or $Candidate.Left.Extent.Text -eq '$script:Pesto_VERSION')
        },$true)){$nodes.Add($node)}
    }
    if($nodes.Count -ne 1){throw ('Affectation $script:Pesto_VERSION introuvable ou ambigue ('+$nodes.Count+').')}
    $value=Get-LiteralExpression $nodes[0].Right
    if(-not($value -is [Management.Automation.Language.StringConstantExpressionAst]) -or -not $value.Value){
        throw 'Version du moteur non litterale : aucune evaluation du moteur.'
    }
    return [string]$value.Value
}

$script:PreferenceTestRoot=$null
function Get-PestoStateDirectory { return $script:PreferenceTestRoot }
function Set-PestoLoginFeedback { param([string]$Message,[switch]$ErrorMessage) throw $Message }
$script:DOMAINE='TEST.INVALID'
$results=[Collections.Generic.List[object]]::new()
$sources=[Collections.Generic.List[object]]::new()
$engineVersion=''
function Assert-Test { param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message} }
function Case {
    param([string]$Name,[scriptblock]$Body)
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name" }
    catch { $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)" }
}
try {
    $engineFiles=@(Read-EngineSources $WadPath)
    $functionIndex=Get-EngineFunctionIndex $engineFiles
    $engineVersion=Get-EngineVersion $engineFiles
    $fileHashes=@{}
    foreach($name in @($load+$doubles)){
        $hit=Get-UniqueEngineFunction $functionIndex $name
        if(-not $fileHashes.ContainsKey($hit.Path)){$fileHashes[$hit.Path]=(Get-FileHash -LiteralPath $hit.Path -Algorithm SHA256).Hash}
        $role=if($load -contains $name){'Testee'}else{'Doublure de test'}
        $sources.Add([pscustomobject]@{Function=$name;Role=$role;File=$hit.File;Line=$hit.Line;SHA256=$fileHashes[$hit.Path]})
    }
    # Definition a la portee du script (jamais dans une fonction) : seules ces fonctions sont chargees.
    foreach($name in $load){
        . ([scriptblock]::Create((Get-UniqueEngineFunction $functionIndex $name).Definition.Extent.Text))
    }
    $script:PreferenceTestRoot=Join-Path ([IO.Path]::GetTempPath()) ('Pesto_login_test_'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:PreferenceTestRoot)
    Case 'Absence de preference : aucune memorisation implicite' {
        $p=Get-PestoLoginPreference
        Assert-Test (-not $p.RememberUser -and $p.UserName -eq '') 'Un identifiant a ete invente.'
        Assert-Test (-not [IO.File]::Exists((Get-PestoLoginPreferencePath))) 'Lecture ayant cree une preference.'
    }
    Case 'Memoriser un identifiant court apres choix explicite' {
        Save-PestoLoginPreference -RememberUser $true -UserName 'test.operateur'
        $p=Get-PestoLoginPreference
        Assert-Test ($p.RememberUser -and $p.UserName -ceq 'test.operateur') 'Identifiant non restaure.'
    }
    Case 'Ecriture successive : mise a jour atomique sans chaine null vide' {
        Save-PestoLoginPreference -RememberUser $true -UserName 'TEST\autre.operateur'
        $p=Get-PestoLoginPreference
        Assert-Test ($p.UserName -ceq 'TEST\autre.operateur') 'Deuxieme ecriture incorrecte.'
    }
    Case 'Liste blanche du fichier : aucun champ de mot de passe' {
        $p=[IO.File]::ReadAllText((Get-PestoLoginPreferencePath)) | ConvertFrom-Json
        $keys=@($p.PSObject.Properties.Name | Sort-Object)
        Assert-Test (($keys -join ',') -eq 'Domain,RememberUser,Schema,UserName') 'Donnees inattendues dans la preference.'
    }
    Case 'UPN memorise tel quel' {
        Save-PestoLoginPreference -RememberUser $true -UserName 'Case.Test@test.invalid'
        Assert-Test ((Get-PestoLoginPreference).UserName -ceq 'Case.Test@test.invalid') 'UPN transforme.'
    }
    Case 'Preference dun autre domaine ignoree' {
        $old=$script:DOMAINE
        try{$script:DOMAINE='OTHER.INVALID';Assert-Test (-not (Get-PestoLoginPreference).RememberUser) 'Identifiant du mauvais domaine recharge.'}
        finally{$script:DOMAINE=$old}
    }
    Case 'Chaine true refusee a la place dun booleen' {
        $p=[pscustomobject]@{Schema=1;Domain='TEST.INVALID';RememberUser='true';UserName='test'}
        Assert-Test (-not (ConvertFrom-PestoLoginPreference $p 'TEST.INVALID').RememberUser) 'Consentement texte accepte.'
    }
    Case 'Schema inconnu ignore' {
        $p=[pscustomobject]@{Schema=2;Domain='TEST.INVALID';RememberUser=$true;UserName='test'}
        Assert-Test (-not (ConvertFrom-PestoLoginPreference $p 'TEST.INVALID').RememberUser) 'Schema non pris en charge accepte.'
    }
    Case 'Nom vide ou trop long refuse sans remplacer la preference' {
        $before=[IO.File]::ReadAllText((Get-PestoLoginPreferencePath))
        foreach($value in @('',('a'*257))){
            $failed=$false
            try{Save-PestoLoginPreference -RememberUser $true -UserName $value}catch{$failed=$true}
            Assert-Test $failed 'Identifiant invalide accepte.'
        }
        Assert-Test ([IO.File]::ReadAllText((Get-PestoLoginPreferencePath)) -ceq $before) 'Ancienne preference ecrasee.'
    }
    Case 'Caracteres de controle refuses' {
        $failed=$false
        try{Save-PestoLoginPreference -RememberUser $true -UserName "test`nother"}catch{$failed=$true}
        Assert-Test $failed 'Caractere de controle accepte.'
    }
    Case 'Decocher oublie immediatement sans nouvelle connexion' {
        $script:PestoLoginUi=[pscustomobject]@{Remember=[pscustomobject]@{IsChecked=$false}}
        Invoke-PestoLoginForget
        Assert-Test (-not [IO.File]::Exists((Get-PestoLoginPreferencePath))) 'Identifiant toujours present.'
    }
    Case 'Cocher seul necrit pas de preference' {
        $script:PestoLoginUi=[pscustomobject]@{Remember=[pscustomobject]@{IsChecked=$true}}
        Invoke-PestoLoginForget
        Assert-Test (-not [IO.File]::Exists((Get-PestoLoginPreferencePath))) 'Identifiant sauve avant authentification.'
    }
    Case 'Preference JSON invalide ignoree' {
        [IO.File]::WriteAllText((Get-PestoLoginPreferencePath),'{malformed')
        Assert-Test (-not (Get-PestoLoginPreference).RememberUser) 'Preference corrompue acceptee.'
    }
    Case 'Fichier de preference trop volumineux ignore' {
        [IO.File]::WriteAllText((Get-PestoLoginPreferencePath),('x'*17000))
        Assert-Test (-not (Get-PestoLoginPreference).RememberUser) 'Fichier non borne accepte.'
    }
    Case 'Oubli idempotent et suppression du fichier corrompu' {
        Save-PestoLoginPreference -RememberUser $false
        Save-PestoLoginPreference -RememberUser $false
        Assert-Test (-not [IO.File]::Exists((Get-PestoLoginPreferencePath))) 'Oubli incomplet.'
    }
} catch {
    # Echec hors d'un controle (lecture des sources, chargement des fonctions) : visible dans le rapport, puis relance.
    $results.Add([pscustomobject]@{Name='Execution interrompue hors controle';Passed=$false;Error=$_.Exception.Message})
    Write-Host "KO  Execution interrompue hors controle : $($_.Exception.Message)"
    throw
} finally {
    $script:PestoLoginUi=$null
    if($script:PreferenceTestRoot -and [IO.Directory]::Exists($script:PreferenceTestRoot)){[IO.Directory]::Delete($script:PreferenceTestRoot,$true)}
    $failed=@($results|Where-Object{-not $_.Passed}).Count
    [pscustomobject]@{Version=$engineVersion;Utc=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Scope='Fonctions de preference isolees ; repertoire temporaire uniquement ; aucun AD/UAC/WPF.';Sources=$sources.ToArray();Count=$results.Count;Failed=$failed;Tests=$results.ToArray()} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if($failed){throw "$failed test(s) de preference en echec. Rapport : $ReportPath"}
Write-Host "Preferences : $($results.Count) tests reussis. Rapport : $ReportPath"
