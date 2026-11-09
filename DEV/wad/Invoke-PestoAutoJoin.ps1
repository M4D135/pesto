#requires -Version 5.1
<#
.SYNOPSIS
Prépare ou exécute une jonction locale depuis une task sequence Windows PowerShell 5.1 x64 élevée.
.DESCRIPTION
POLICY.UnattendedJoinEnabled=true et -Execute sont tous deux requis pour agir.
Sans -Execute : lectures Windows/AD seulement, aucun reçu ni réservation créé.
Credential est un objet PSCredential fourni en mémoire, jamais un mot de passe texte.
Sortie objet (ou -AsJson), code 0 préparation, 3010 accepté/redémarrage requis, 96 refus avant lancement,
97 résultat incertain, autres codes du moteur = refus confirmé. Aucun redémarrage automatique.
.EXAMPLE
$result = & .\wad\Invoke-PestoAutoJoin.ps1 -Credential $credentialDuCoffre -Type P -SiteCode PR -ServiceCode 765 -Execute
# Le moteur retourne un objet technique. La task sequence traite explicitement $result.ExitCode.
#>
[CmdletBinding()]
param([string]$ConfigPath='',$Credential,[string]$Type,[string]$SiteCode,[string]$ServiceCode,
    [string]$TargetOU='',[switch]$Execute,[switch]$AsJson
)
$ErrorActionPreference='Stop'
Set-StrictMode -Off
. (Join-Path $PSScriptRoot 'Pesto-CliHost.ps1')
$result=$null
try{
    Initialize-PestoCliProcess
    # Ce contrôle de cohérence est identique au runtime. Ce n’est pas une signature éditeur.
    . (Join-Path $PSScriptRoot 'Pesto-Integrity.ps1')
    [void](Test-PestoPackage -Root (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $PSScriptRoot 'Pesto.Engine.psd1') -ErrorAction Stop
    if(-not $ConfigPath){$ConfigPath=Join-Path $PSScriptRoot 'cfg.json'}
    $result=Invoke-PestoCommand -Action Join -RuntimeRoot $PSScriptRoot -ConfigPath $ConfigPath -Credential $Credential `
        -Type $Type -SiteCode $SiteCode -ServiceCode $ServiceCode -TargetOU $TargetOU -Execute:$Execute
}catch{
    $result=[pscustomobject]@{Schema=1;Mode='UnattendedJoin';State='NotStarted';ExitCode=96;EngineCode=$null;
        RestartRequired=$false;MutationStarted=$false;OperationId='';Utc=[DateTime]::UtcNow.ToString('o');
        Message=('Démarrage refusé : '+$_.Exception.Message);Plan=$null;CandidateCount=0;Checks=@();Metadata=$null}
}finally{$Credential=$null}
if($AsJson){ConvertTo-PestoCliJson $result 6}else{$result}
exit ([int]$result.ExitCode)
