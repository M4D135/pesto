#requires -Version 5.1
<#
.SYNOPSIS
Contrôle avant remise le diff d'attributs complémentaires présenté à l'opérateur.
.DESCRIPTION
Évalue une demande d'attributs limités (description, location, managedBy) avec l'aperçu de l'intégrateur
(New-PestoAttributeProposal, integrations/Pesto.Optional.psm1) puis avec les gardes du moteur lui-même
(Get-PestoAttributeChanges et Assert-PestoAttributeChanges, wad/Pesto-Extensions.ps1). Les deux jambes doivent
tomber d'accord sur le même diff et être jugées identiquement par la garde du moteur : l'aperçu que l'opérateur
approuve avant de remettre le fichier de plan ne doit rien promettre que le moteur refuse ou réécrive plus tard,
sinon le refus arrive après la remise, sur la cible. Aucune lecture AD, aucun appel réseau, aucune écriture de
registre, aucune mutation : la référence managedBy est épinglée sur un GUID par le moteur au moment du plan,
seule étape autorisée à lire le répertoire. Sortie fermée : 0 = diff exécutable tel quel par le moteur,
96 = refusé.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Installation,[string]$ObjectGuid='',
    [Parameter(Mandatory=$true)][string]$CurrentPath,[Parameter(Mandatory=$true)][string]$RequestPath,
    [switch]$AsJson,[string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$messages=[ordered]@{
    Installation='Installation doit être un chemin absolu local.'
    Identite='Identifiant AD requis.'
    Lecture='Document candidat illisible.'
    Integrity='Intégrité du paquet non confirmée.'
    Engine='Chargement des gardes du moteur impossible.'
    Module='Chargement de l''aperçu intégrateur impossible.'
    Evaluation='Demande d''attributs non évaluable.'
}
# Le texte brut d'une exception peut répéter un nom d'attribut ou une valeur candidate : seules ces formes
# fermées, celles que les gardes émettent elles-mêmes, sortent du contrôle.
$closed=@('Identité AD requise.','Attribut demandé deux fois.','Valeur d’’attribut invalide.',
    'managedBy attend un DN validé séparément.','Un à trois changements attendus.','Objet structuré attendu.',
    'Valeur attribut invalide.','managedBy exige un DN.','Une a trois modifications requises.',
    'Attribut inconnu ou duplique.','Diff attribut invalide.','Diff vide.','Identite managedBy manquante.',
    'Reference inattendue.','Champ obligatoire absent : ReferenceGuid')
function Close-PestoAttributeError {
    param([string]$Text)
    if($Text -cin $closed){return $Text}
    if($Text -like 'Champ non autorisé : *'){return 'Champ non autorisé.'}
    if($Text -like 'Attribut non autorisé : *'){return 'Attribut non autorisé.'}
    return 'Demande d''attributs refusée.'
}
function Get-PestoJsonMemberNames {
    # Windows PowerShell 5.1 conserve les membres homonymes d'un objet JSON, PowerShell 7 ne garde que le
    # dernier : la même demande serait vue comme deux changements par une jambe et comme un doublon illicite
    # par l'autre. Les membres du premier niveau sont donc relevés sur le texte, avant toute désérialisation.
    param([string]$Text)
    $names=[Collections.Generic.List[string]]::new()
    $depth=0;$index=0;$length=$Text.Length
    while($index -lt $length){
        $char=$Text[$index]
        if($char -eq '"'){
            $start=$index+1;$index=$start;$escape=$false
            while($index -lt $length){
                $inner=$Text[$index]
                if($escape){$escape=$false}
                elseif($inner -eq '\'){$escape=$true}
                elseif($inner -eq '"'){break}
                $index++
            }
            $value=$Text.Substring($start,$index-$start);$index++
            $probe=$index
            while($probe -lt $length -and $Text[$probe] -match '\s'){$probe++}
            if($depth -eq 1 -and $probe -lt $length -and $Text[$probe] -eq ':'){$names.Add($value)}
            continue
        }
        if($char -eq '{' -or $char -eq '['){$depth++}
        elseif($char -eq '}' -or $char -eq ']'){$depth--}
        $index++
    }
    return $names
}
function Read-PestoAttributeDocument {
    param([string]$Path)
    if(-not[IO.Path]::IsPathRooted($Path)){throw 'Document candidat illisible.'}
    if(-not[IO.File]::Exists($Path)){throw 'Document candidat illisible.'}
    $raw=[IO.File]::ReadAllBytes($Path)
    if($raw.Length -lt 1 -or $raw.Length -gt 65536){throw 'Document candidat illisible.'}
    $text=[Text.UTF8Encoding]::new($false).GetString($raw)
    if((@(Get-PestoJsonMemberNames $text|Group-Object -CaseSensitive|Where-Object{$_.Count -gt 1})).Count){throw 'Document candidat illisible.'}
    $parsed=($text|ConvertFrom-Json -ErrorAction Stop)
    if($null -eq $parsed -or $parsed -is [string] -or $parsed -is [ValueType] -or $parsed -is [Collections.IEnumerable]){throw 'Document candidat illisible.'}
    return $parsed
}
function Get-PestoAttributeRowKey {
    param($Rows)
    # Clé de comparaison : les valeurs elles-mêmes ne sortent jamais du contrôle, seule leur identité sert
    # à confronter les deux jambes.
    return (@($Rows|ForEach-Object{[string]$_.Attribute+[char]31+[string]$_.Before+[char]31+[string]$_.After+[char]31+[string]$_.ReferenceGuid}) -join [char]30)
}
$report=[ordered]@{Schema=1;Product='Pesto';Purpose='PestoAttributeDiffPreflight';
    Scope='Évaluation locale d''une demande d''attributs ; aucune lecture AD, aucune écriture, aucune mutation'
    ObjectGuid='';PreviewAccepted=$false;PreviewError='';EngineAccepted=$false;EngineError='';
    DiffMatches=$false;Divergence=$false;ChangeCount=0;Attributes=@();Clears=@();ReferencePending=$false;
    Executable=$false;WindowsExecuted=$false;ADExecuted=$false;RegistryWritten=$false;PolicyChanged=$false;
    ExitCode=96;Message=''}
$phase='Installation'
try{
    if(-not[IO.Path]::IsPathRooted($Installation)){throw 'Installation doit être un chemin absolu local.'}
    $runtime=Join-Path $Installation 'wad'
    $phase='Integrity'
    . (Join-Path $runtime 'Pesto-Integrity.ps1')
    if(-not(Test-PestoPackage -Root $Installation)){throw 'Intégrité du paquet non confirmée.'}
    $phase='Engine'
    foreach($file in @('Pesto-Contracts.ps1','Pesto-Extensions.ps1')){. (Join-Path $runtime $file)}
    $phase='Module'
    Import-Module (Join-Path $Installation 'integrations/Pesto.Optional.psm1') -Force
    $phase='Identite'
    $guid=[Guid]::Empty
    if(-not[Guid]::TryParse($ObjectGuid,[ref]$guid) -or $guid -eq [Guid]::Empty){throw 'Identifiant AD requis.'}
    $report['ObjectGuid']=$guid.ToString('D')
    $phase='Lecture'
    $current=Read-PestoAttributeDocument $CurrentPath
    $request=Read-PestoAttributeDocument $RequestPath
    $phase='Evaluation'
    $preview=$null
    try{$preview=New-PestoAttributeProposal -ObjectGuid $guid -Current $current -Requested $request;$report['PreviewAccepted']=$true}
    catch{$report['PreviewError']=Close-PestoAttributeError -Text ([string]$_.Exception.Message)}
    $engineRows=@()
    try{
        # Get-PestoAttributeChanges rend son tableau par « return ,$changes » : l'affecter, c'est déjà le
        # tableau des lignes ; l'entourer de @() le ferait compter pour une seule ligne vectorielle.
        $engineRows=@(Get-PestoAttributeChanges $current $request|ForEach-Object{$_})
        $report['EngineAccepted']=$true
    }
    catch{$report['EngineError']=Close-PestoAttributeError -Text ([string]$_.Exception.Message)}
    if($report['PreviewAccepted'] -and $report['EngineAccepted']){
        $previewRows=@($preview.Changes)
        $report['DiffMatches']=((Get-PestoAttributeRowKey $previewRows) -ceq (Get-PestoAttributeRowKey $engineRows))
        $report['ChangeCount']=$engineRows.Count
        $report['Attributes']=@($engineRows|ForEach-Object{[string]$_.Attribute})
        $report['Clears']=@($engineRows|Where-Object{[string]$_.After -ceq ''}|ForEach-Object{[string]$_.Attribute})
        # C'est la garde du moteur elle qui juge les deux jeux de lignes : rien ici ne réimplémente ses règles.
        $previewRefusal=''
        try{[void](Assert-PestoAttributeChanges $previewRows)}catch{$previewRefusal=[string]$_.Exception.Message}
        $engineRefusal=''
        try{[void](Assert-PestoAttributeChanges $engineRows)}catch{$engineRefusal=[string]$_.Exception.Message}
        # Le moteur épingle lui-même la référence managedBy au moment du plan : son refus sur cette seule
        # ligne est attendu ici, puisqu'aucune lecture AD n'est permise à ce stade.
        $report['ReferencePending']=($engineRefusal -ceq 'Identite managedBy manquante.')
        $report['Divergence']=(-not $report['DiffMatches']) -or ($previewRefusal -cne $engineRefusal)
        if($engineRefusal -and -not $report['ReferencePending']){$report['EngineError']=Close-PestoAttributeError -Text $engineRefusal}
        $report['Executable']=(-not $report['Divergence']) -and (-not $report['EngineError'])
    }
    $report['ExitCode']=if($report['Executable']){0}else{96}
    $report['Message']=if($report['Executable']){'Diff exécutable par le moteur.'}elseif($report['Divergence']){'Aperçu divergent du moteur.'}else{'Diff refusé.'}
}catch{
    $message=[string]$messages[$phase];if(-not $message){$message='Échec du contrôle du diff attributs.'}
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
