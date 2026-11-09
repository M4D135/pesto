# Démo réelle de Pesto pour les captures des guides (07/10/2026, accord de David : objets de recette, nettoyage à la fin).
# Lancé par outils/labo/mac/demo-reelle.sh, RÉSERVÉ À DAVID : les mots de passe arrivent par l'entrée standard (ligne 1 :
# compte AD d'administration ; ligne 2 pour -Preparer : mot de passe choisi pour le compte de recette). Jamais en argument,
# jamais dans un fichier, jamais affichés.
# -Preparer : OU de recette « Departement 111301 » sous ADCC-Lab (Postes, Staging, SITES, Paris, Lyon), postes désactivés pour
#             l'inventaire, compte de recette tech.pesto (droits délégués sur cette OU seulement), jonction de ce PC sous
#             P111301VA765003 dans Paris, tech.pesto administrateur local de ce PC, cfg.json réel de C:\PestoDemo.
#             Redémarrage non lancé.
# -Nettoyer : supprime exactement ce que -Preparer a créé (objets listés dans objets.json, recherchés par GUID), compte
#             ordinateur de ce PC compris où qu'il soit sous l'OU de recette. La VM est ensuite remise par son instantané.
param([switch]$Preparer, [switch]$Nettoyer, [switch]$AdminLocal, [switch]$SansJonction, [switch]$Joindre, [string]$User = '', [string]$Domain = '',
      [string]$Parent = '', [string]$Lab = 'Departement 111301', [string]$Tech = 'tech.pesto',
      [string]$NewName = 'P111301VA765003', [string]$Demo = 'C:\PestoDemo', [string]$Wad = 'C:\PestoDemo\wad')
$ErrorActionPreference = 'Stop'
if (-not $Domain) { $Domain = $env:PESTO_LABO_DOMAINE }
if (-not $Domain) { throw 'Domaine du labo absent : passer -Domain ou PESTO_LABO_DOMAINE.' }
$netbios = ($Domain -split '\.')[0].ToUpper()
if (-not $User) { $User = $netbios + '\administrateur' }
if (-not $Parent) { $Parent = 'OU=ADCC-Lab,DC=' + (($Domain -split '\.') -join ',DC=') }
if ($AdminLocal) {
    # Après redémarrage, si l'ajout par SID a échoué pendant -Preparer.
    $admins = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    $m = ($User -split '\\')[0] + '\' + $Tech
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        if (-not (Get-LocalGroupMember -Group $admins -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $m })) { Add-LocalGroupMember -Group $admins -Member $m -ErrorAction Stop }
        "$m administrateur local ($admins)."
    } else { 'Hors domaine : compte de recette ajouté aux administrateurs après la jonction.' }
    # Ouverture de session automatique d'un compte à mot de passe : Windows Hello ne doit pas l'imposer (valeur 0, remise à 2 au nettoyage).
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name DevicePasswordLessBuildVersion -Value 0 -Type DWord
    'DevicePasswordLessBuildVersion=0.'; return
}
if (-not $Joindre -and $Preparer -eq $Nettoyer) { throw 'Choisir -Preparer, -Nettoyer, -Joindre ou -AdminLocal.' }
$out = 'C:\PestoTest-preuves\demo-reelle'; New-Item -ItemType Directory -Force $out | Out-Null
$journal = Join-Path $out ('demo-reelle-' + $(if ($Joindre) { 'joindre' } elseif ($Preparer) { 'preparer' } else { 'nettoyer' }) + '.txt')
function Note([string]$t) { Add-Content -LiteralPath $journal -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $t) -Encoding UTF8; $t }
function Read-Line {
    $in = [Console]::OpenStandardInput(); $buf = New-Object System.Collections.Generic.List[byte]
    while (($c = $in.ReadByte()) -ge 0 -and $c -ne 10) { if ($c -ne 13) { $buf.Add([byte]$c) } }
    $s = [Text.Encoding]::UTF8.GetString($buf.ToArray()); $buf.Clear(); $s
}
trap { Note ('ÉCHEC : ' + $_.Exception.Message); break }
Note ('Démarrage ' + $(if ($Joindre) { 'jonction' } elseif ($Preparer) { 'préparation' } else { 'nettoyage' }) + ' avec ' + $User)
$p1 = Read-Line; if (-not $p1) { throw 'Mot de passe d''administration vide : rien fait.' }
$cred = New-Object Management.Automation.PSCredential($User, (ConvertTo-SecureString $p1 -AsPlainText -Force)); $p1 = $null
# Module AD embarqué par Pesto (pas de RSAT sur la VM), chargé par la vraie fonction de Pesto-Safety.ps1, comme le banc moteur.
$t = $null; $e = $null; $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Safety.ps1'), [ref]$t, [ref]$e)
foreach ($n in @('Assert-PestoPlainPath', 'Import-PestoADModule')) {
    $f = @($ast.FindAll({ param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true))
    if (-not $f.Count) { throw "Fonction $n absente de Pesto-Safety.ps1." }
    . ([scriptblock]::Create($f[0].Extent.Text))
}
Import-PestoADModule -ADModulePath (Join-Path $Wad 'ActiveDirectory.psd1')
# Comme le banc moteur : contrôleur découvert (ADWS), puis émulateur PDC lu sur ce contrôleur.
$disc = [string](Get-ADDomainController -Discover -DomainName $Domain -Writable -Service ADWS -ForceDiscover).HostName[0]
$pdc = ([string](Get-ADDomain -Server $disc -Credential $cred).PDCEmulator).TrimEnd('.')
$adp = @{ Server = $pdc; Credential = $cred }
$labOU = "OU=$Lab,$Parent"; $root = "OU=Postes,$labOU"; $sites = "OU=SITES,$root"
$paris = "OU=Paris,$sites"; $lyon = "OU=Lyon,$sites"; $staging = "OU=Staging,$root"
$objFile = Join-Path $out 'objets.json'
Note ("Compte : $User ; émulateur PDC : $pdc ; OU de recette : $labOU")

if ($Joindre) {
    # Après --preparer-sans-jonction : (1) réservation dans l'AD par le VRAI worker de Pesto (création puis retrait du compte
    # réservé, sur l'AD du labo) ; (2) jonction de ce PC dans Paris par le script (le mot de passe ne passe jamais par Pesto).
    if (-not (Test-Path -LiteralPath $objFile)) { throw 'Lancer d''abord --preparer-sans-jonction.' }
    $created = Get-Content -LiteralPath $objFile -Raw | ConvertFrom-Json
    $tj=$null;$ej=$null;$astj=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Join.ps1'),[ref]$tj,[ref]$ej)
    $wa=@($astj.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoJoinADReserveWorker'},$true))
    if (-not $wa.Count) { throw 'Worker de réservation AD absent de Pesto-Join.ps1.' }
    $tw=[scriptblock]::Create($wa[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
    $ta=$null;$ea=$null;$asts=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Safety.ps1'),[ref]$ta,[ref]$ea)
    $src=[Text.StringBuilder]::new();foreach($n in 'Assert-PestoPlainPath','Import-PestoADModule'){[void]$src.AppendLine(@($asts.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true))[0].Extent.Text)}
    $req=[pscustomobject]@{Mode='Reserve';Name='P111301VA765004';OU=$paris;DC=$pdc;Credential=$cred;User=$User;Station=$env:COMPUTERNAME;ADLoaderSource=$src.ToString();ADModulePath=(Join-Path $Wad 'ActiveDirectory.psd1')}
    $r=& $tw $req
    Note ("Réservation AD (worker de Pesto) : $($r.State) $($r.Name) GUID $($r.Guid)")
    $o=Get-ADComputer -Identity ($r.Name+'$') -Properties Description @adp
    Note ("Compte réservé lu dans l'AD : $($o.DistinguishedName) ; description : $($o.Description)")
    $again=& $tw $req
    Note ("Deuxième réservation du même nom : $($again.State) (attendu : Taken)")
    $rel=& $tw ([pscustomobject]@{Mode='Release';Name=$r.Name;Guid=$r.Guid;DC=$pdc;Credential=$cred;ADLoaderSource=$src.ToString();ADModulePath=(Join-Path $Wad 'ActiveDirectory.psd1')})
    $left=@(Get-ADComputer -LDAPFilter ('(sAMAccountName='+$r.Name+'$)') @adp)
    Note ("Retrait de la réservation (worker de Pesto) : $($rel.State) ; compte encore présent : $($left.Count -gt 0)")
    # Jonction de ce PC au domaine, renommé, dans le site Paris.
    Add-Computer -DomainName $Domain -OUPath $paris -NewName $NewName -Credential $cred -Server $pdc -Force
    $j = Get-ADComputer -Identity ($NewName + '$') @adp
    $created | Add-Member -NotePropertyName Joined -NotePropertyValue ([string]$j.ObjectGUID) -Force
    $created | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $objFile -Encoding UTF8
    Note ("Jonction : ce PC -> $NewName dans $paris (redémarrage nécessaire). Ensuite : autologon du compte de recette, --apres-redemarrage.")
    return
}
if ($Preparer) {
    $p2 = Read-Line; if (-not $p2) { throw 'Mot de passe du compte de recette vide : rien fait.' }
    if (Get-ADOrganizationalUnit -LDAPFilter "(ou=$Lab)" -SearchBase $Parent -SearchScope OneLevel @adp) { throw "OU de recette déjà présente : $labOU. Lancer d'abord --nettoyer." }
    $created = [ordered]@{ OUs = @(); Computers = @(); User = $null; Joined = $null }
    foreach ($ou in @(@($Lab, $Parent), @('Postes', $labOU), @('Staging', $root), @('SITES', $root), @('Paris', $sites), @('Lyon', $sites))) {
        New-ADOrganizationalUnit -Name $ou[0] -Path $ou[1] -ProtectedFromAccidentalDeletion $false @adp
        $created.OUs += ('OU=' + $ou[0] + ',' + $ou[1])
    }
    foreach ($pc in @(@('P111301VA765001', $paris), @('P111301VA765002', $paris), @('P111301VAINF001', $paris), @('S111301VA765010', $paris),
                      @('P111301LY765001', $lyon), @('S111301LYRH0001', $lyon))) {
        New-ADComputer -Name $pc[0] -SamAccountName ($pc[0] + '$') -Path $pc[1] -Enabled $false @adp
        $created.Computers += [string](Get-ADComputer -Identity ($pc[0] + '$') @adp).ObjectGUID
    }
    New-ADUser -Name $Tech -SamAccountName $Tech -UserPrincipalName "$Tech@$Domain" -Path $labOU -Enabled $true -PasswordNeverExpires $true `
        -AccountPassword (ConvertTo-SecureString $p2 -AsPlainText -Force) -Description 'Recette Pesto (démo réelle des guides) : à supprimer' @adp
    $p2 = $null
    $u = Get-ADUser -Identity $Tech -Properties SID @adp; $created.User = [string]$u.ObjectGUID
    $created | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $objFile -Encoding UTF8
    Note ("Créés : $($created.OUs.Count) OU, $($created.Computers.Count) postes désactivés, compte $Tech")
    # Droits délégués : contrôle total sur l'OU de recette et ses objets, pour ce compte seulement.
    $dom = ($User -split '\\')[0]
    $entry = New-Object DirectoryServices.DirectoryEntry("LDAP://$pdc/$labOU", $User, $cred.GetNetworkCredential().Password)
    $rule = New-Object DirectoryServices.ActiveDirectoryAccessRule($u.SID, [DirectoryServices.ActiveDirectoryRights]::GenericAll,
        [Security.AccessControl.AccessControlType]::Allow, [DirectoryServices.ActiveDirectorySecurityInheritance]::All)
    $entry.ObjectSecurity.AddAccessRule($rule); $entry.CommitChanges(); $entry.Dispose()
    Note ("Droits : $dom\$Tech, contrôle total sur $labOU (héritage).")
    if ($SansJonction) {
        # Tests visibles du 08/10 au soir : c'est Pesto qui joindra ce PC, dans sa vraie fenêtre.
        Note 'Sans jonction : ce PC reste hors domaine ; Pesto fera la mise au domaine.'
    } else {
    # Jonction de ce PC au domaine, renommé, dans le site Paris.
    Add-Computer -DomainName $Domain -OUPath $paris -NewName $NewName -Credential $cred -Server $pdc -Force
    $j = Get-ADComputer -Identity ($NewName + '$') @adp; $created.Joined = [string]$j.ObjectGUID
    $created | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $objFile -Encoding UTF8
    Note ("Jonction : ce PC -> $NewName dans $paris (redémarrage nécessaire).")
    # Compte de recette administrateur local (lié par SID : la résolution de nom attend le redémarrage).
    $admins = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    try {
        ([ADSI]"WinNT://$env:COMPUTERNAME/$admins,group").Add('WinNT://' + $u.SID.Value)
        Note ("Administrateurs locaux : $dom\$Tech ajouté (SID $($u.SID.Value)).")
    } catch { Note ("Administrateurs locaux : ajout impossible avant redémarrage ($($_.Exception.Message)) ; relancer --admin-local après redémarrage.") }
    }
    # Configuration réelle (aucune simulation) du pack de démonstration réelle.
    $cfg = [ordered]@{
        DEBUG  = [ordered]@{ Simulation = 'false'; HorsDomaine = 'false'; MauvaiseOU = 'false'; BPVerifNomAD = 'false'; ForceADM = 'false'; GUI = 'false' }
        CONF   = @([ordered]@{ Domaine = $Domain; ADM = 'C111301-DEP-AGENCE'; Prefixe = '111301'; PreprodSite = '765'; DirectProd = 'true'; DarkMode = '0'; Buffer = '10'; OUScanNoms = $root; DsregLeaveOnMove = 'false' })
        TAGS   = @([ordered]@{ Site = 'PREPROD'; Tag = 'PR' }, [ordered]@{ Site = 'Paris'; Tag = 'VA' }, [ordered]@{ Site = 'Lyon'; Tag = 'LY' })
        OUBase = @([ordered]@{ Nom = 'ROOT'; OU = $root }, [ordered]@{ Nom = 'PREPROD'; OU = $staging })
        OUSite = @([ordered]@{ Nom = 'Département 111301'; OU = $sites })
    }
    if ($true) {
        # Nouveautés du 08/10 au soir : registre partagé local (deux Pesto côte à côte), réservation AD, reprise RunOnce.
        $reg = 'C:\PestoRegistre'
        foreach ($d in @($reg, "$reg\locks", "$reg\reservations")) { [void][IO.Directory]::CreateDirectory($d) }
        [IO.File]::WriteAllText("$reg\pesto-coordination.json", ([ordered]@{ Schema = 1; Domain = $Domain; Purpose = 'PestoCoordination' } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        $cfg.Configured = $true
        $cfg.POLICY = [ordered]@{ Schema = 1; ExcludedNames = @(); ExcludedOUs = @(); ExcludedGroupGuids = @(); CoordinationRoot = $reg; CoordinationRequired = $false
            AllowPasswordTaskFallback = $false; AllowPrecreatedJoin = $false; AllowOfflineJoin = $false; MaxReaders = 4; ReadAttempts = 2; MaxBatch = 200
            NameReservationMinutes = 15; ReserveNamesInAD = $true; RandomNameChoice = 0 }
        Note "Configuration de test : registre $reg, réservation AD."
    }
    if (Test-Path -LiteralPath (Join-Path $Demo 'wad')) {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Demo 'wad\cfg.json') -Encoding UTF8
        Note ("cfg.json réel écrit dans $Demo\wad (Simulation=false, GUI=false, DirectProd=true).")
    } else { Note ("$Demo absent : cfg.json non écrit.") }
    Note 'PRÉPARATION TERMINÉE. Redémarrer la VM, puis ouverture automatique du compte de recette (autologon.sh --compte).'
} else {
    $created = if (Test-Path -LiteralPath $objFile) { Get-Content -LiteralPath $objFile -Raw | ConvertFrom-Json } else { $null }
    if (-not (Get-ADOrganizationalUnit -LDAPFilter "(ou=$Lab)" -SearchBase $Parent -SearchScope OneLevel @adp)) { Note 'OU de recette absente : rien à nettoyer.'; return }
    # Postes : ceux créés (GUID) et le compte de ce PC (GUID), où qu'ils soient ; puis tout poste restant sous l'OU de recette.
    $guids = @(); if ($created) { $guids += @($created.Computers) + @($created.Joined) | Where-Object { $_ } }
    foreach ($g in $guids) { $c = Get-ADComputer -Filter "ObjectGUID -eq '$g'" @adp; if ($c) { Remove-ADObject -Identity $c.ObjectGUID -Recursive -Confirm:$false @adp; Note ("Poste supprimé : $($c.Name)") } }
    foreach ($c in @(Get-ADComputer -SearchBase $labOU -Filter * @adp)) { Remove-ADObject -Identity $c.ObjectGUID -Recursive -Confirm:$false @adp; Note ("Poste supprimé (sous l'OU de recette) : $($c.Name)") }
    $u = Get-ADUser -Filter "SamAccountName -eq '$Tech'" -SearchBase $labOU @adp
    if ($u) { Remove-ADUser -Identity $u.ObjectGUID -Confirm:$false @adp; Note ("Compte supprimé : $Tech") }
    $left = @(Get-ADObject -SearchBase $labOU -Filter "objectClass -ne 'organizationalUnit'" @adp)
    if ($left.Count) { throw ("Objets inattendus sous $labOU : " + (($left | ForEach-Object { $_.DistinguishedName }) -join ' ; ') + ". OU conservée.") }
    $ous = @(Get-ADOrganizationalUnit -SearchBase $labOU -Filter * @adp | Sort-Object { $_.DistinguishedName.Length } -Descending)
    foreach ($o in $ous) { Remove-ADOrganizationalUnit -Identity $o.ObjectGUID -Confirm:$false @adp }
    Note ("OU supprimées : $($ous.Count). NETTOYAGE AD TERMINÉ. Remettre la VM par son instantané (hors domaine).")
}
