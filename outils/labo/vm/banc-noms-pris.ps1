# Banc « nom pris par un autre poste » sur l'AD réel du labo (Pesto, 07/10/2026).
# Le mot de passe arrive sur l'entrée standard (jamais en argument ni dans un fichier). Crée une OU de recette et un compte
# ordinateur « technicien n° 1 », vérifie avec les vraies fonctions de recherche de Pesto que le nom est vu pris, puis
# supprime le compte et l'OU créés par ce banc (et rien d'autre).
param([string]$User='',[string]$DC='',[string]$Domain='',
      [string]$Parent='',[string]$OUName='Pesto-20261007-course',[string]$Name='P111301ZZQA9001',
      [string]$Wad='C:\PestoTest\wad',[string]$Out='C:\PestoTest-run\banc-noms-pris.txt')
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
$script:cred=New-Object Management.Automation.PSCredential($User,$sec)
$R=[Collections.Generic.List[string]]::new()
function Note([string]$t){$R.Add($t);$t}
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    $sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    return $sb.ToString()
}
try{
    Import-Module (Join-Path $Wad 'ActiveDirectory.psd1') -ErrorAction Stop
    foreach($pair in @(@('Pesto-Operations.ps1',@('Test-PestoComputerName')),@('Pesto-Directory.ps1',@('Get-ADParams','Find-ADComputerByName')))){. ([scriptblock]::Create((Import-Fn $pair[0] $pair[1])))}
    $retry=@(Get-ChildItem $Wad -Filter 'Pesto-*.ps1'|Where-Object{(Get-Content $_.FullName -Raw) -match '(?m)^function Invoke-PestoReadRetry\b'})[0]
    . ([scriptblock]::Create((Import-Fn $retry.Name @('Invoke-PestoReadRetry'))))
    $script:DC=$DC;$script:DOMAINE=$Domain;$script:PestoPolicy=$null
    $adp=@{Server=$DC;Credential=$script:cred}
    Note ('Compte : '+$User+' ; DC : '+$DC+' ; identité lue : '+(Get-ADDomain @adp).DNSRoot)
    $ou="OU=$OUName,$Parent";$createdOU=$false
    if(-not(Get-ADOrganizationalUnit -LDAPFilter "(ou=$OUName)" -SearchBase $Parent -SearchScope OneLevel @adp)){New-ADOrganizationalUnit -Name $OUName -Path $Parent -ProtectedFromAccidentalDeletion $false @adp;$createdOU=$true}
    Note ("OU de recette : $ou (créée par ce banc : $createdOU)")
    $before=Find-ADComputerByName -Name $Name
    Note ('1. Avant : Find-ADComputerByName '+$Name+' -> '+$(if($before){'PRIS (inattendu) '+$before.DistinguishedName}else{'libre'}))
    if($before){throw 'Nom déjà présent avant le banc : arrêt sans rien créer.'}
    $sw=[Diagnostics.Stopwatch]::StartNew()
    New-ADComputer -Name $Name -SamAccountName ($Name+'$') -Path $ou -Enabled $true @adp
    $created=Get-ADComputer -Identity ($Name+'$') -Properties ObjectGUID @adp
    Note ('2. Technicien n° 1 : compte '+$Name+' créé ('+$created.ObjectGUID+')')
    $after=Find-ADComputerByName -Name $Name;$ms=$sw.ElapsedMilliseconds
    Note ('3. Technicien n° 2, contrôle de Pesto juste après : '+$(if($after){'PRIS, vu en '+$ms+' ms ('+$after.DistinguishedName+')'}else{'NON VU (anomalie)'}))
    $ldap="(|(name=$Name)(sAMAccountName=$Name`$)(dNSHostName=$Name.$Domain))"
    $join=@(Get-ADComputer -LDAPFilter $ldap -SearchBase (Get-ADDomain @adp).DistinguishedName -SearchScope Subtree @adp)
    Note ('4. Filtre du contrôle de jonction (domaine entier) : '+$join.Count+' objet(s) -> '+$(if($join.Count){'Nouveau nom : Bloqué'}else{'OK (anomalie)'}))
    Note ('RESULTAT '+$(if($after -and $join.Count){'PASS : le nom pris par un autre poste est vu par les contrôles de Pesto'}else{'FAIL'}))
}catch{Note ('ERREUR : '+$_.Exception.Message)}
finally{
    try{
        $obj=Get-ADComputer -LDAPFilter "(sAMAccountName=$Name`$)" -SearchBase "OU=$OUName,$Parent" -SearchScope OneLevel @adp -ErrorAction SilentlyContinue
        if($obj -and $created -and $obj.ObjectGUID -eq $created.ObjectGUID){Remove-ADComputer -Identity $obj.ObjectGUID -Confirm:$false @adp;Note ('Nettoyage : compte '+$Name+' supprimé (GUID créé par ce banc)')}
        if($createdOU){$left=@(Get-ADObject -SearchBase "OU=$OUName,$Parent" -SearchScope OneLevel -Filter * @adp);if(-not $left.Count){Remove-ADOrganizationalUnit -Identity "OU=$OUName,$Parent" -Confirm:$false @adp;Note 'Nettoyage : OU de recette supprimée (vide)'}else{Note ('Nettoyage : OU conservée, '+$left.Count+' objet(s) non créés par ce banc')}}
        Note ('Contrôle final : '+$(if(Get-ADComputer -LDAPFilter "(sAMAccountName=$Name`$)" @adp){'compte encore présent'}else{'compte absent'}))
    }catch{Note ('Nettoyage incomplet : '+$_.Exception.Message)}
    $script:cred=$null;$sec.Dispose()
    $R|Out-File -Encoding utf8 $Out
}
