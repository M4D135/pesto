#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Domain)
$ErrorActionPreference='Stop'
$Root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
if($Domain -notmatch '^(?=.{1,253}$)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$'){throw 'Domaine invalide.'}
$dir=Get-Item -LiteralPath $Root -Force -ErrorAction Stop
if(-not $dir.PSIsContainer -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Un dossier approuvé existant et non lié est requis.'}
$parent=$dir
while($parent){if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Chemin lié refusé.'};$parent=$parent.Parent}
$marker=Join-Path $Root 'pesto-coordination.json';$locks=Join-Path $Root 'locks'
if(Test-Path -LiteralPath $marker){throw 'Marqueur déjà présent. Aucun registre existant écrasé.'}
if(Test-Path -LiteralPath $locks){throw 'Le sous-dossier locks existe déjà. Faire examiner le registre, sans supprimer ses verrous.'}
Write-Output ('Préparation du registre pour '+$Domain+'. Aucune création de partage, délégation ni modification ACL.')
if($PSCmdlet.ShouldProcess($Root,'Créer le marqueur et un dossier de verrous vide')){
 [void][IO.Directory]::CreateDirectory($locks)
 $bytes=[Text.Encoding]::UTF8.GetBytes((@{Schema=1;Domain=$Domain;Purpose='PestoCoordination'}|ConvertTo-Json -Compress))
 $stream=[IO.File]::Open($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 Write-Warning 'Faire valider les ACL du partage et NTFS. Configurer le même registre sur TOUS les postes opérateurs ; un poste non configuré ne participe pas à la coordination.'
}
