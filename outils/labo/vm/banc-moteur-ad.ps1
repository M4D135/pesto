# Banc moteur sur l'AD réel du labo (Pesto, 07/10/2026) : PDC, liste des services sur l'inventaire réel, nom proposé,
# nom pris par un « technicien n° 1 » puis nom suivant. Vraies fonctions de Pesto extraites de wad\ ; worker de lecture AD
# exécuté tel quel. Mot de passe sur l'entrée standard (jamais en argument ni dans un fichier). Crée une OU de recette et des
# comptes ordinateur désactivés, puis supprime exactement ce qu'il a créé (contrôle par GUID).
param([string]$User='',[string]$Domain='',[string]$Parent='',
      [string]$Lab='Pesto-20261007-recette',[string]$Wad='C:\PestoTest\wad',[string]$Out='C:\PestoTest-run\banc-moteur-ad.txt')
$ErrorActionPreference='Stop'
if(-not $Domain){$Domain=$env:PESTO_LABO_DOMAINE}
if(-not $Domain){throw 'Domaine du labo absent : passer -Domain ou PESTO_LABO_DOMAINE.'}
$netbios=($Domain -split '\.')[0].ToUpper()
if(-not $User){$User=$netbios+'\administrateur'}
if(-not $Parent){$Parent='OU=ADCC-Lab,DC='+(($Domain -split '\.') -join ',DC=')}
$in=[Console]::OpenStandardInput();$buf=New-Object System.Collections.Generic.List[byte]
while(($c=$in.ReadByte()) -ge 0 -and $c -ne 10){if($c -ne 13){$buf.Add([byte]$c)}}
$sec=New-Object Security.SecureString;foreach($ch in [Text.Encoding]::UTF8.GetString($buf.ToArray()).ToCharArray()){$sec.AppendChar($ch)};$buf.Clear();$sec.MakeReadOnly()
$script:cred=New-Object Management.Automation.PSCredential($User,$sec)
$R=[Collections.Generic.List[string]]::new();$created=[Collections.Generic.List[object]]::new();$createdOUs=[Collections.Generic.List[string]]::new()
function Note([string]$t){$R.Add($t);$t}
function Check([string]$n,[bool]$ok,[string]$d=''){Note ($(if($ok){'PASS '}else{'FAIL '})+$n+$(if($d){' :: '+$d}else{''}))}
function Get-FnText([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    return $sb.ToString()
}
try{
    foreach($p in @(@('Pesto-Contracts.ps1',@('ConvertTo-PestoNameParts','New-PestoComputerName','Invoke-PestoReadRetry')),
                    @('Pesto-Operations.ps1',@('Test-PestoComputerName','Test-PestoGeneratedComputerName')),
                    @('Pesto-Core.ps1',@('ConvertTo-PestoRdnValue','Get-SiteTag','Get-AvailableMachines','Get-NameList')),
                    @('Pesto-Directory.ps1',@('Get-ADParams','Find-ADComputerByName','Get-PestoSiteServiceCodes')),
                    @('Pesto-Join.ps1',@('Get-PestoJoinNameCandidates')))){. ([scriptblock]::Create((Get-FnText $p[0] $p[1])))}
    $loader=Get-FnText 'Pesto-Safety.ps1' @('Assert-PestoPlainPath','Import-PestoADModule')
    . ([scriptblock]::Create($loader));Import-PestoADModule -ADModulePath (Join-Path $Wad 'ActiveDirectory.psd1')
    $dirText=[IO.File]::ReadAllText((Join-Path $Wad 'Pesto-Directory.ps1'))
    $i=$dirText.IndexOf('$script:PestoDirectorySnapshotWorker = {');$j=$dirText.IndexOf('{',$i);$depth=0;$end=-1
    for($k=$j;$k -lt $dirText.Length;$k++){if($dirText[$k] -eq '{'){$depth++}elseif($dirText[$k] -eq '}'){$depth--;if($depth -eq 0){$end=$k;break}}}
    $worker=[scriptblock]::Create($dirText.Substring($j+1,$end-$j-1))
    $disc=(Get-ADDomainController -Discover -DomainName $Domain -Writable -Service ADWS -ForceDiscover).HostName[0]
    $adp=@{Server=[string]$disc;Credential=$script:cred}
    Note ('Compte : '+$User+' ; DC découvert : '+$disc+' ; PDC : '+(Get-ADDomain @adp).PDCEmulator)
    # Fixture : OU de recette, ROOT, PREPROD, organisme LAB et deux sites, postes désactivés.
    $labOU="OU=$Lab,$Parent";$root="OU=Postes,$labOU";$sites="OU=SITES,$root";$alpha="OU=ALPHA,$sites";$beta="OU=BETA,$sites"
    if(Get-ADOrganizationalUnit -LDAPFilter "(ou=$Lab)" -SearchBase $Parent -SearchScope OneLevel @adp){throw "OU de recette déjà présente : $labOU. Arrêt sans rien créer."}
    foreach($ou in @(@($Lab,$Parent),@('Postes',$labOU),@('Staging',$root),@('SITES',$root),@('ALPHA',$sites),@('BETA',$sites))){
        New-ADOrganizationalUnit -Name $ou[0] -Path $ou[1] -ProtectedFromAccidentalDeletion $false @adp;$createdOUs.Add(('OU='+$ou[0]+','+$ou[1]))}
    foreach($pc in @(@('P999007AAINF001',$alpha),@('P999007AAINF002',$alpha),@('S999007AARH0001',$alpha),@('P999007BCCPT001',$beta))){
        New-ADComputer -Name $pc[0] -SamAccountName ($pc[0]+'$') -Path $pc[1] -Enabled $false @adp
        $created.Add((Get-ADComputer -Identity ($pc[0]+'$') -Properties ObjectGUID @adp))}
    Note ('Fixture : '+$createdOUs.Count+' OU, '+$created.Count+' postes désactivés sous '+$labOU)
    # 1. Worker réel de lecture AD (login/actualisation), inventaire complet.
    $req=[pscustomobject]@{Domain=$Domain;DC='';Credential=$script:cred;OUSite=@{LAB=$sites};RootOU=$root;ScanOU=$root;LocalComputerName=$env:COMPUTERNAME;
        IncludeLocalHardware=$false;FullInventory=$true;ADLoaderSource=$loader;ADModulePath=(Join-Path $Wad 'ActiveDirectory.psd1')}
    $snap=& $worker $req
    $pdc=([string](Get-ADDomain @adp).PDCEmulator).TrimEnd('.')
    Check 'Worker AD : contrôleur = émulateur PDC' (([string]$snap.DC) -ieq $pdc -and [string]$snap.DCRole -eq 'PDC') ("DC=$($snap.DC) role=$($snap.DCRole)")
    Check 'Worker AD : sites lus sous l''organisme' (((@($snap.Sites['LAB'])|Sort-Object) -join ',') -eq 'ALPHA,BETA') (@($snap.Sites['LAB']) -join ',')
    Check 'Worker AD : inventaire complet (4 postes)' (@($snap.Root).Count -eq 4 -and [bool]$snap.FullInventory) ('Root='+@($snap.Root).Count)
    # 2. Liste des services sur l'inventaire réel.
    $script:PREFIXE='999007';$script:RuntimeTags=$null;$script:PREPRODSITE='765'
    $script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='PREPROD';Tag='PR'},[pscustomobject]@{Site='ALPHA';Tag='AA'},[pscustomobject]@{Site='BETA';Tag='BC'})}
    $inv=@($snap.Root)+@($snap.Names)
    $sA=(Get-PestoSiteServiceCodes -OrganismeOU $sites -Site 'ALPHA' -Computers $inv) -join ','
    $sB=(Get-PestoSiteServiceCodes -OrganismeOU $sites -Site 'BETA' -Computers $inv) -join ','
    Check 'Services d''ALPHA sur l''inventaire réel' ($sA -eq 'INF,RH0') $sA
    Check 'Services de BETA sur l''inventaire réel' ($sB -eq 'CPT') $sB
    # 3. Nom proposé, puis 4. nom pris par un autre poste.
    $script:DC=[string]$snap.DC;$script:DOMAINE=$Domain;$script:PestoPolicy=$null
    $first=@(Get-PestoJoinNameCandidates -Type 'Portable' -Site 'ALPHA' -Service 'INF' -Computers $inv)[0]
    Check 'Nom proposé : premier libre' ($first -eq 'P999007AAINF003') $first
    New-ADComputer -Name $first -SamAccountName ($first+'$') -Path $alpha -Enabled $false @adp
    $created.Add((Get-ADComputer -Identity ($first+'$') -Properties ObjectGUID @adp))
    $seen=Find-ADComputerByName -Name $first
    Check 'Technicien n° 1 : nom vu pris sur le PDC' ([bool]$seen) $(if($seen){$seen.DistinguishedName}else{'absent'})
    $script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);[void]$script:PestoTakenNames.Add($first)
    $next=@(Get-PestoJoinNameCandidates -Type 'Portable' -Site 'ALPHA' -Service 'INF' -Computers $inv)[0]
    Check 'Nom suivant proposé, libre dans l''AD' ($next -eq 'P999007AAINF004' -and -not (Find-ADComputerByName -Name $next)) $next
}catch{Note ('ERREUR : '+$_.Exception.Message)}
finally{
    try{
        foreach($o in @($created)){if($o){$cur=Get-ADComputer -Filter "ObjectGUID -eq '$($o.ObjectGUID)'" @adp;if($cur){Remove-ADComputer -Identity $o.ObjectGUID -Confirm:$false @adp}}}
        for($k=$createdOUs.Count-1;$k -ge 0;$k--){$ou=$createdOUs[$k];$left=@(Get-ADObject -SearchBase $ou -SearchScope OneLevel -Filter * @adp);if(-not $left.Count){Remove-ADOrganizationalUnit -Identity $ou -Confirm:$false @adp}else{Note "OU conservée (non vide) : $ou"}}
        $rest=@(Get-ADOrganizationalUnit -LDAPFilter "(ou=$Lab)" -SearchBase $Parent -SearchScope OneLevel @adp)
        Note ('Nettoyage : '+$created.Count+' postes et '+$createdOUs.Count+' OU créés par ce banc ; OU de recette '+$(if($rest.Count){'ENCORE PRÉSENTE'}else{'absente'}))
    }catch{Note ('Nettoyage incomplet : '+$_.Exception.Message)}
    $script:cred=$null;$sec.Dispose()
    $f=@($R|Where-Object{$_ -like 'FAIL*' -or $_ -like 'ERREUR*'}).Count;Note ('RESULTAT '+@($R|Where-Object{$_ -like 'PASS*'}).Count+' reussis, '+$f+' echecs')
    $R|Out-File -Encoding utf8 $Out
}
