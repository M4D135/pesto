# Registre partagé depuis un compte Windows LOCAL (cas du poste hors domaine pendant « Ajouter au domaine »), 08/10/2026.
# Lancé par SSH sous PESTO-W11-TEST\labadmin (compte local, aucun droit sur le partage), le mot de passe du compte AD de
# recette arrivant par l'entrée standard (jamais en argument ni dans un fichier). Un partage de test est créé sur cette VM,
# ouvert au seul compte LABO\tech.pesto, puis supprimé. Vrai code de Pesto : worker du registre, verrou d'opération
# (Enter/Exit-PestoCoordination) et Connect-PestoCoordinationShare.
param([string]$User='LABO\tech.pesto',[string]$Wad='C:\PestoTest\wad',[string]$Share='PestoRegHD',[string]$Folder='C:\PestoRegHD')
$ErrorActionPreference='Stop'
$in=[Console]::OpenStandardInput();$buf=New-Object System.Collections.Generic.List[byte]
while(($c=$in.ReadByte()) -ge 0 -and $c -ne 10){if($c -ne 13){$buf.Add([byte]$c)}}
$sec=New-Object Security.SecureString;foreach($ch in [Text.Encoding]::UTF8.GetString($buf.ToArray()).ToCharArray()){$sec.AppendChar($ch)};$buf.Clear();$sec.MakeReadOnly()
$cred=New-Object Management.Automation.PSCredential($User,$sec)
$R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){$R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if($D){' :: '+$D}else{''}));$R[-1]}
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('Assert-PestoClosedObject','Test-PestoPropertyPresent','Get-PestoStableHash'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy','Add-PestoShareConnection','Connect-PestoCoordinationShare','Get-PestoCoordinationRoot','Get-PestoCoordinationKeys','Enter-PestoCoordination','Exit-PestoCoordination'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Names.ps1' @('Get-PestoSharedNameSettings','Close-PestoShareConnections'))))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Names.ps1'),[ref]$t,[ref]$e)
$worker=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSharedNameWorker'},$true))[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
function Invoke-Worker($Req){$ps=[PowerShell]::Create();try{[void]$ps.AddScript($worker).AddArgument($Req);@($ps.Invoke())[-1]}finally{$ps.Dispose()}}
function Drop-Connections{
    # Connexions de cette session retirées, et session SMB du compte AD fermée côté serveur (ici la VM elle-même) :
    # l'accès suivant repart du seul jeton local, sans réutiliser l'authentification précédente.
    & net.exe use * /delete /y 2>&1|Out-Null
    Get-SmbSession -ErrorAction SilentlyContinue|Where-Object{$_.ClientComputerName -eq '127.0.0.1' -and $_.ClientUserName -like '*tech.pesto'}|Close-SmbSession -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
$me=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$root="\\127.0.0.1\$Share\Pesto";$domain='labo.local'
function Req([string]$Mode,[string]$Name,$Credential){[pscustomobject]@{Mode=$Mode;Root=$root;Domain=$domain;Owner='hors-domaine';Station=$env:COMPUTERNAME;User=$User;Minutes=15;Name=$Name;Names=@($Name);Context='Join';Credential=$Credential}}
"Identité du processus : $me (compte local) ; compte AD fourni : $User"
try{
    # Partage de test ouvert au seul compte AD de recette.
    if(Get-SmbShare -Name $Share -ErrorAction SilentlyContinue){Remove-SmbShare -Name $Share -Force}
    if(Test-Path $Folder){Remove-Item $Folder -Recurse -Force}
    [void][IO.Directory]::CreateDirectory($Folder)
    $acl=Get-Acl $Folder;$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($User,'Modify','ContainerInherit,ObjectInherit','None','Allow')));Set-Acl $Folder $acl
    [void](New-SmbShare -Name $Share -Path $Folder -FullAccess $User)
    Drop-Connections
    Check ('Partage de test créé, réservé à '+$User) ([bool](Get-SmbShare -Name $Share))
    Check "Compte local : partage refusé (jeton local seul)" (-not [IO.Directory]::Exists("\\127.0.0.1\$Share"))
    # Avant le correctif : aucun compte AD transmis -> registre inutilisable.
    $msg='';try{[void](Invoke-Worker (Req 'Prepare' '' $null))}catch{$msg=$_.Exception.Message}
    Check 'Sans le compte AD (comportement d''avant) : registre inutilisable' ($msg -ne '') $msg
    # Après : le worker se connecte au partage avec le compte AD.
    $r=Invoke-Worker (Req 'Prepare' '' $cred)
    Check 'Avec le compte AD : registre préparé (marqueur, verrous, réservations)' ($r.State -eq 'OK') ($r|ConvertTo-Json -Compress)
    Check 'Connexion signalée par le worker (pour la fermer à la fin)' ([string]$r.Connected -eq "\\127.0.0.1\$Share") ([string]$r.Connected)
    $r=Invoke-Worker (Req 'Reserve' 'P111301VA799001' $cred)
    Check 'Avec le compte AD : nom réservé' ($r.State -eq 'Reserved') ([string]$r.State)
    $r=Invoke-Worker ([pscustomobject]@{Mode='Reserve';Root=$root;Domain=$domain;Owner='autre-poste';Station='AUTRE';User='x';Minutes=15;Name='P111301VA799001';Names=@();Context='Join';Credential=$cred})
    Check 'Avec le compte AD : un autre poste trouve le nom détenu' ($r.State -eq 'Held') ([string]$r.State)
    $r=Invoke-Worker (Req 'Release' 'P111301VA799001' $cred)
    Check 'Avec le compte AD : réservation libérée' ($r.State -eq 'OK' -and @($r.Others) -contains 'P111301VA799001') ($r|ConvertTo-Json -Compress)
    # Fermeture de Pesto : la connexion ouverte avec le compte AD est fermée (sinon elle durerait jusqu'à la déconnexion).
    $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;CoordinationRoot=$root}};$script:GUI=$false;$script:INDOMAIN=$true;$script:cred=$null
    $script:PestoShareConnections=$null;Add-PestoShareConnection ([string]$r.Connected)
    $before=(& net.exe use 2>&1|Out-String) -match [regex]::Escape("\\127.0.0.1\$Share")
    Close-PestoShareConnections
    $after=(& net.exe use 2>&1|Out-String) -match [regex]::Escape("\\127.0.0.1\$Share")
    Check 'Fermeture de Pesto : connexion au partage supprimée' ($before -and -not $after) ("avant=$before après=$after")
    # Verrou d'opération (worker de jonction) : connexions retirées, puis sans et avec $script:cred.
    Drop-Connections
    $policy=ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;CoordinationRoot=$root})
    $plan=[pscustomobject]@{Nom_du_PC='PCNEUF';Nouveau_Nom='P111301VA799002';Objet_GUID='';Domain=$domain}
    $script:cred=$null;$msg='';try{[void](Enter-PestoCoordination -Plan $plan -OperationId ([Guid]::NewGuid().ToString('N')) -Policy $policy)}catch{$msg=$_.Exception.Message}
    Check 'Verrou sans le compte AD (comportement d''avant) : « Coordination non préparée »' ($msg -like 'Coordination non préparée*') $msg
    $script:cred=$cred;$id=[Guid]::NewGuid().ToString('N')
    $coord=Enter-PestoCoordination -Plan $plan -OperationId $id -Policy $policy
    $locks=@([IO.Directory]::GetFiles("$Folder\Pesto\locks"))
    Check 'Verrou avec le compte AD : pris (fichiers de verrou créés)' ($coord.Enabled -and $locks.Count -eq @($coord.Keys).Count -and $locks.Count -ge 2) ("Enabled=$($coord.Enabled) verrous=$($locks.Count)")
    Exit-PestoCoordination -Receipt ([pscustomobject]@{Coordination=$coord;Phase='Verified';OperationId=$id;Plan=$plan}) -Policy $policy
    Check 'Verrou libéré après vérification' (@([IO.Directory]::GetFiles("$Folder\Pesto\locks")).Count -eq 0)
}catch{Check ('exception : '+$_.Exception.Message) $false}
finally{
    Drop-Connections
    try{Remove-SmbShare -Name $Share -Force -ErrorAction Stop}catch{}
    try{Remove-Item $Folder -Recurse -Force -ErrorAction Stop}catch{}
    $script:cred=$null;$cred=$null;$sec.Dispose()
    Check 'Nettoyage : partage et dossier de test supprimés' (-not (Get-SmbShare -Name $Share -ErrorAction SilentlyContinue) -and -not (Test-Path $Folder))
}
"RESULTAT $(@($R|Where-Object{$_ -like 'PASS*'}).Count) reussis, $(@($R|Where-Object{$_ -like 'FAIL*'}).Count) echecs"
