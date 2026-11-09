# Banc « série d'un nom pris » sur l'AD réel du labo (Pesto, 08/10/2026).
# Défaut signalé par David : en mise au domaine, Pesto essayait plusieurs noms pris avant de trouver le bon, puis abandonnait.
# Le mot de passe arrive sur l'entrée standard (jamais en argument ni dans un fichier). Crée une OU de recette et quatre
# comptes ordinateurs désactivés (001, 002, 003, 005), exécute les lectures de série du code de Pesto (jonction et
# renommage, extraites telles quelles des fichiers livrés), vérifie que le nom proposé ensuite est 004, puis supprime
# exactement ce que ce banc a créé (par GUID). Mesure aussi la recherche ciblée du site (services en quelques secondes).
param([string]$User='',[string]$DC='',[string]$Domain='',
      [string]$Parent='',[string]$OUName='Pesto-20261008-serie',[string]$Series='P111301ZZQA9',
      [string]$Wad='C:\PestoTest\wad',[string]$Out='C:\PestoTest-run\banc-noms-serie.txt')
$ErrorActionPreference='Stop'
if(-not $Domain){$Domain=$env:PESTO_LABO_DOMAINE}
if(-not $Domain){throw 'Domaine du labo absent : passer -Domain ou PESTO_LABO_DOMAINE.'}
$netbios=($Domain -split '\.')[0].ToUpper()
if(-not $User){$User=$netbios+'\administrateur'}
if(-not $DC){$DC='dc01.'+$Domain}
if(-not $Parent){$Parent='OU=ADCC-Lab,DC='+(($Domain -split '\.') -join ',DC=')}
$in=[Console]::OpenStandardInput();$buf=New-Object System.Collections.Generic.List[byte]
while(($c=$in.ReadByte()) -ge 0 -and $c -ne 10){if($c -ne 13){$buf.Add([byte]$c)}}
$sec=New-Object Security.SecureString;foreach($ch in [Text.Encoding]::UTF8.GetString($buf.ToArray()).ToCharArray()){$sec.AppendChar($ch)};$buf.Clear();$sec.MakeReadOnly()
$cred=New-Object Management.Automation.PSCredential($User,$sec)
$R=[Collections.Generic.List[string]]::new();$created=[Collections.Generic.List[object]]::new();$createdOU=$false;$ok=0;$ko=0
function Note([string]$t){$R.Add($t);$t}
function Check([string]$n,[bool]$v,[string]$d=''){if($v){$script:ok++;Note ('PASS '+$n)}else{$script:ko++;Note ('FAIL '+$n+' :: '+$d)}}
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    return $sb.ToString()
}
function Get-SeriesStatement([string]$File,[string]$Function){
    # Instruction exacte de Pesto : de « $seriesTaken=@(Get-ADComputer » à « Sort-Object -Unique) ».
    $body=Import-Fn $File @($Function)
    $m=[regex]::Match($body,'(?s)\$seriesTaken=@\(Get-ADComputer.*?Sort-Object -Unique\)')
    if(-not $m.Success){throw "Lecture de série absente de $Function"}
    return $m.Value
}
try{
    Import-Module (Join-Path $Wad 'ActiveDirectory.psd1') -ErrorAction Stop
    . ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName'))))
    . ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-AvailableMachines'))))
    $adp=@{Server=$DC;Credential=$cred;ErrorAction='Stop'}
    $domain=Get-ADDomain @adp
    Note ('Compte : '+$User+' ; DC : '+$DC+' ; domaine lu : '+$domain.DNSRoot)
    $pre=@(Get-ADComputer -LDAPFilter "(name=$Series*)" @adp)
    if($pre.Count){throw ("Série déjà utilisée dans l'AD avant le banc ($($pre.Count) objet(s)) : arrêt sans rien créer.")}
    $ou="OU=$OUName,$Parent"
    if(-not(Get-ADOrganizationalUnit -LDAPFilter "(ou=$OUName)" -SearchBase $Parent -SearchScope OneLevel @adp)){New-ADOrganizationalUnit -Name $OUName -Path $Parent -ProtectedFromAccidentalDeletion $false @adp;$createdOU=$true}
    Note ("OU de recette : $ou (créée par ce banc : $createdOU)")
    foreach($n in '001','002','003','005'){
        $nm=$Series+$n
        New-ADComputer -Name $nm -SamAccountName ($nm+'$') -Path $ou -Enabled $false @adp
        $o=Get-ADComputer -Identity ($nm+'$') -Properties ObjectGUID @adp;$created.Add($o)
        Note ('Compte de recette créé : '+$nm+' ('+$o.ObjectGUID+', désactivé)')
    }
    # 1. Jonction : le nom proposé (001, inventaire pas encore chargé) est pris ; lecture de série du worker de jonction.
    $name=$Series+'001';$series=$name.Substring(0,12).ToUpperInvariant();$seriesTaken=@()
    $sw=[Diagnostics.Stopwatch]::StartNew()
    . ([scriptblock]::Create((Get-SeriesStatement 'Pesto-Join.ps1' 'Get-PestoJoinPreflight')))
    Note ('Jonction : série lue en '+$sw.ElapsedMilliseconds+' ms -> '+($seriesTaken -join ', '))
    Check 'Jonction : série complète lue dans le domaine (001, 002, 003, 005)' (($seriesTaken -join ',') -eq (@('001','002','003','005'|ForEach-Object{$Series+$_}) -join ',')) ($seriesTaken -join ',')
    $free=Get-AvailableMachines -computers @($seriesTaken|ForEach-Object{[pscustomobject]@{Name=$_}}) -baseName 'P111301' -site 'ZZ' -equipe 'QA9';$next=[string]$free[0]
    Check 'Jonction : nom proposé ensuite = premier numéro libre (004), en un seul essai' ($next -eq ($Series+'004')) $next
    # 2. Renommage : même lecture dans le contrôle préalable (sans SearchBase : contexte de nommage par défaut).
    $seriesTaken=@()
    . ([scriptblock]::Create((Get-SeriesStatement 'Pesto-Core.ps1' 'Invoke-PestoReadOnlyPreflight')))
    Check 'Renommage : même série lue' (($seriesTaken -join ',') -eq (@('001','002','003','005'|ForEach-Object{$Series+$_}) -join ',')) ($seriesTaken -join ',')
    # 3. Le nom proposé est bien libre dans tout le domaine (filtre exact du contrôle de jonction).
    $fq=$next+'.'+$Domain
    $taken=@(Get-ADComputer -LDAPFilter ('(|(name='+$next+')(sAMAccountName='+$next+'$)(dNSHostName='+$fq+'))') -SearchBase $domain.DistinguishedName -SearchScope Subtree @adp)
    Check 'Nom proposé libre dans tout le domaine' ($taken.Count -eq 0) ([string]$taken.Count)
    # 4. Recherche ciblée du site (08/10, services en quelques secondes) : vrai worker de Pesto, runspace séparé, vrai module AD.
    . ([scriptblock]::Create((Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath','Import-PestoADModule','Get-PestoADLoaderSource'))))
    $wt=$null;$we=$null;$wast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad 'Pesto-Directory.ps1'),[ref]$wt,[ref]$we)
    $wa=@($wast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$script:PestoSiteLookupWorker'},$true))
    if(-not $wa.Count){throw 'Worker de recherche ciblée absent.'}
    $body=$wa[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
    $req=[pscustomobject]@{Key='ZZ|'+$ou;DC=$DC;Credential=$cred;Prefix='111301';Tag='ZZ';SiteOU=$ou;ADLoaderSource=(Get-PestoADLoaderSource);ADModulePath=(Join-Path $Wad 'ActiveDirectory.psd1')}
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $ps=[PowerShell]::Create();try{[void]$ps.AddScript($body,$true);[void]$ps.AddArgument($req);$res=@($ps.Invoke())[-1]}finally{$ps.Dispose()}
    $names=@($res.Items|ForEach-Object{$_.Name}|Sort-Object -Unique)
    Note ('Recherche ciblée : '+$names.Count+' poste(s) en '+$sw.ElapsedMilliseconds+' ms (dont requêtes '+$res.Ms+' ms, module AD compris) -> '+($names -join ', '))
    Check 'Recherche ciblée : les 4 comptes de la série trouvés' ((@($names|Where-Object{$_ -like ($Series+'*')}) -join ',') -eq (@('001','002','003','005'|ForEach-Object{$Series+$_}) -join ',')) ($names -join ',')
    Check 'Recherche ciblée : moins de 10 s' ($sw.ElapsedMilliseconds -lt 10000) ([string]$sw.ElapsedMilliseconds)
}catch{$ko++;Note ('ERREUR : '+$_.Exception.Message)}
finally{
    try{
        foreach($o in $created){Remove-ADComputer -Identity $o.ObjectGUID -Confirm:$false @adp;Note ('Nettoyage : '+$o.Name+' supprimé (GUID créé par ce banc)')}
        if($createdOU){$left=@(Get-ADObject -SearchBase "OU=$OUName,$Parent" -SearchScope OneLevel -Filter * @adp);if(-not $left.Count){Remove-ADOrganizationalUnit -Identity "OU=$OUName,$Parent" -Confirm:$false @adp;Note 'Nettoyage : OU de recette supprimée (vide)'}else{Note 'OU de recette non vide : laissée en place'}}
        Note ('Contrôle final : '+@(Get-ADComputer -LDAPFilter "(name=$Series*)" @adp).Count+' objet(s) de la série dans l''AD')
    }catch{Note ('Nettoyage incomplet : '+$_.Exception.Message)}
    $cred=$null;$sec.Dispose()
    Note ('RESULTAT {0} reussis, {1} echecs' -f $ok,$ko)
    $R|Out-File -Encoding utf8 $Out
}
