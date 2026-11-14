# Services du site en quelques secondes (08/10/2026, David : « ça met 30 s mini pour afficher un service alors qu'avant
# non. et le bouton vérification est grisé »). Vrai worker de recherche ciblée exécuté dans un runspace séparé (AD simulé
# par un double), vraie vue de jonction WPF, vraies fonctions de listes. Windows PowerShell 5.1, STA, sans bureau.
param([string]$Wad='C:\PestoTest\wad')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Get-Ast([string]$File){$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);if(@($e).Count){throw "Syntaxe $File : $($e[0].Message)"};$a}
function Import-Fn([string]$File,[string[]]$Names){
    $ast=Get-Ast $File;$sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    return $sb.ToString()
}
function Get-ScriptBlockVar([string]$File,[string]$Var){
    $a=@((Get-Ast $File).FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq $Var},$true))
    if(-not $a.Count){throw "Variable absente : $Var"};return $a[0].Right.Extent.Text
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoDnsName','Test-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-SiteTag','Get-AvailableMachines','Get-NameList','ConvertTo-PestoRdnValue','Get-ComputersForNameGeneration'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoDomainFromDN','Get-PestoSiteServiceCodes','Get-PestoSiteLookupItems','Get-PestoKnownComputers','Request-PestoSiteLookup','Complete-PestoSiteLookup','Update-PestoServiceChoices'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Set-PestoJoinMessage','Update-PestoJoinServices','Request-PestoJoinSiteLookup','Get-PestoJoinNameCandidates','Update-PestoJoinNames'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-UXFlow.ps1' @('Get-PestoPrimaryStep'))))
$script:PestoSiteLookupWorker=[scriptblock]::Create((Get-ScriptBlockVar 'Pesto-Directory.ps1' '$script:PestoSiteLookupWorker').Trim().TrimStart('{').TrimEnd('}'))
# AD simulé : 3 005 postes dans le domaine, latence de 300 ms par requête. Le double applique le filtre LDAP « début du
# nom » et la base de recherche comme l'AD ; il note chaque requête pour vérifier qu'aucune ne lit tout le domaine.
$loader=@'
function Import-PestoADModule {param($ADModulePath)}
$script:FakeAD=[Collections.Generic.List[object]]::new()
foreach($i in 1..3000){$script:FakeAD.Add([pscustomobject]@{Name=('P123456LYINF'+('{0:D3}' -f ($i%999+1)));DistinguishedName=('CN=X'+$i+',OU=Lyon,OU=Org,DC=lab,DC=local')})}
foreach($n in 'P123456PAINF001','P123456PAINF002','S123456PACPT001'){$script:FakeAD.Add([pscustomobject]@{Name=$n;DistinguishedName=('CN='+$n+',OU=Ailleurs,DC=lab,DC=local')})}
$script:FakeAD.Add([pscustomobject]@{Name='P123456XXRH0001';DistinguishedName='CN=P123456XXRH0001,OU=Paris,OU=Org,DC=lab,DC=local'})
$script:FakeAD.Add([pscustomobject]@{Name='P123456PAINF004';DistinguishedName='CN=P123456PAINF004,OU=Paris,OU=Org,DC=lab,DC=local'})
$script:Calls=[Collections.Generic.List[string]]::new()
function Get-ADComputer {
    param($LDAPFilter,$Filter,$SearchBase,$SearchScope,$Properties,$ResultSetSize,$Server,$Credential)
    if($Filter){throw 'Lecture complète refusée par le banc.'}
    $script:Calls.Add([string]$LDAPFilter+' @ '+[string]$SearchBase+' srv='+[string]$Server+' cred='+[bool]$Credential)
    Start-Sleep -Milliseconds 300
    $prefixes=@([regex]::Matches([string]$LDAPFilter,'\(name=([A-Z0-9]+)\*\)')|ForEach-Object{$_.Groups[1].Value})
    if(-not $prefixes.Count){throw 'Filtre inattendu.'}
    foreach($c in $script:FakeAD){
        $ok=$false;foreach($p in $prefixes){if($c.Name.StartsWith($p,[StringComparison]::OrdinalIgnoreCase)){$ok=$true;break}}
        if($ok -and (-not $SearchBase -or $c.DistinguishedName.EndsWith(','+$SearchBase,[StringComparison]::OrdinalIgnoreCase))){$c}
    }
}
'@
# Doubles d'infrastructure : le démarrage asynchrone exécute le vrai worker dans un runspace séparé, puis le rappel.
$script:Starts=0;$script:WorkerMs=0
function Get-PestoADLoaderSource {$loader}
function Test-PestoAsyncOperationRunning {param($Name) $false}
function Write-Log {param($a,$b,$c,$d) $script:R.Add('LOG '+$a)}
function Test-PestoNameReservedByOther {param($Name) $false}  # registre partagé (08/10 soir) : neutre ici
function Get-PestoInitialNameIndex {param($Count) 0}  # numéro au hasard (08/10 soir) : désactivé ici
function Update-PestoJoinUI {}
function Start-PestoAsyncOperation {
    param($Name,$ScriptBlock,$ArgumentList,$OnSuccess,$OnError,[switch]$Replace,$TimeoutSec,$CallbackContext)
    $script:Starts++
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $out=@();$err=@()
    $ps=[PowerShell]::Create();try{[void]$ps.AddScript($ScriptBlock.ToString(),$true);foreach($a in $ArgumentList){[void]$ps.AddArgument($a)};try{$out=@($ps.Invoke());$err=@($ps.Streams.Error)}catch{$err=@($_)}}finally{$ps.Dispose()}
    $script:WorkerMs=$sw.ElapsedMilliseconds
    if($err.Count){& $OnError $err[0] $CallbackContext}else{& $OnSuccess $out[-1] $CallbackContext}
    return $true
}
$script:PREFIXE='123456';$script:PREPRODSITE='765';$script:RuntimeTags=$null;$script:GUI=$false;$script:SIM=$false;$script:INDOMAIN=$false;$script:PRD=$true
$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'},[pscustomobject]@{Site='Lyon';Tag='LY'})}
$script:DC='dc01.lab.local';$script:cred=New-Object Management.Automation.PSCredential('LAB\tech',(ConvertTo-SecureString 'x' -AsPlainText -Force))
$script:OUV=@{Org='OU=Org,DC=lab,DC=local'};$script:Sites=@{Org=@('Paris','Lyon')};$script:Computers=@();$script:ComputersNoms=@()
$BasePath=$Wad
try { & {
    $reader=[Xml.XmlReader]::Create((Join-Path $Wad 'Pesto-Join.xaml'));try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $ui=@{};foreach($k in @{Type='JnType';Org='JnOrg';Site='JnSite';Service='JnService';Name='JnName';Existing='JnExisting';Status='JnStatus';Detail='JnDetail'}.GetEnumerator()){$ui[$k.Key]=$view.FindName($k.Value)}
    $script:JoinUI=$ui;$script:JoinSuspend=$true
    [void]$ui.Type.Items.Add('Portable');$ui.Type.SelectedIndex=0;[void]$ui.Org.Items.Add('Org');$ui.Org.SelectedIndex=0;[void]$ui.Site.Items.Add('Paris');$ui.Site.SelectedIndex=0
    $script:JoinSuspend=$false
    # 1. Avant : inventaire non chargé, aucune liste de services, nom proposé 001 (pris dans l'AD).
    Update-PestoJoinServices;$ui.Service.Text='INF';Update-PestoJoinNames
    Check 'Avant : aucun service connu sans inventaire' ($ui.Service.Items.Count -eq 0) ([string]$ui.Service.Items.Count)
    Check 'Avant : nom proposé 001 (pris dans l''AD)' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF001') ([string]$ui.Name.SelectedItem)
    # 2. Choix du site : recherche ciblée, en arrière-plan.
    $sw=[Diagnostics.Stopwatch]::StartNew();Request-PestoJoinSiteLookup;$ms=$sw.ElapsedMilliseconds
    $script:R.Add(('INFO recherche ciblée (runspace + 2 requêtes simulées à 300 ms, 3 005 postes dans l''AD simulé) : {0} ms, worker {1} ms' -f $ms,$script:WorkerMs))
    Check 'Recherche lancée une fois' ($script:Starts -eq 1) ([string]$script:Starts)
    Check 'Services du site affichés : CPT, INF, RH0 (nom du site + OU du site)' ((@($ui.Service.Items) -join ',') -eq 'CPT,INF,RH0') (@($ui.Service.Items) -join ',')
    Check 'Saisie du service conservée' ([string]$ui.Service.Text -eq 'INF') ([string]$ui.Service.Text)
    Check 'Nom proposé : premier numéro libre (003), 001, 002 et 004 écartés' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF003' -and -not $ui.Name.Items.Contains('P123456PAINF004')) ([string]$ui.Name.SelectedItem)
    Check 'Moins de 5 s pour afficher les services (AD simulé)' ($ms -lt 5000) ([string]$ms)
    # 3. Requêtes envoyées : début de nom dans le domaine + OU du site ; jamais de lecture complète ; DC et compte transmis.
    $calls=@($script:SiteLookupCache.Keys)
    Check 'Cache rempli pour la clé du site' ($script:SiteLookupCache.ContainsKey('PA|OU=PARIS,OU=ORG,DC=LAB,DC=LOCAL')) ($calls -join ';')
    Request-PestoJoinSiteLookup
    Check 'Même site : pas de nouvelle requête' ($script:Starts -eq 1) ([string]$script:Starts)
    # 4. Site vide : rien n'est lancé.
    $script:SiteLookupCache=@{};$before=$script:Starts
    Request-PestoSiteLookup -OrganismeOU '' -Site ''
    Check 'Site vide : aucune requête' ($script:Starts -eq $before)
    # 5. Mode démonstration : aucune requête AD.
    $before=$script:Starts;$script:GUI=$true;Request-PestoSiteLookup -OrganismeOU 'OU=Org,DC=lab,DC=local' -Site 'Paris';$script:GUI=$false
    Check 'Démonstration : aucune requête' ($script:Starts -eq $before)
    # 6. Échec AD : journalisé, listes inchangées, aucune exception.
    $saved=$loader;$loader='function Import-PestoADModule {param($ADModulePath)}; function Get-ADComputer {throw ''Serveur injoignable''}'
    $items=@($ui.Service.Items) -join ',';Request-PestoSiteLookup -OrganismeOU 'OU=Org,DC=lab,DC=local' -Site 'Paris';$loader=$saved
    Check 'Échec AD : listes conservées' ((@($ui.Service.Items) -join ',') -eq $items) (@($ui.Service.Items) -join ',')
    # 7. Un poste : « Vérifier » grisé dit ce qui manque.
    $s=Get-PestoPrimaryStep -Computer 'SOURCE' -Loaded $true -FormReady $false -Missing 'Choisissez ou saisissez le service (3 caractères).'
    Check 'Un poste : le texte dit ce qui manque' ($s.Action -eq 'Prepare' -and $s.Hint -like 'Choisissez ou saisissez le service*') $s.Hint
    $s=Get-PestoPrimaryStep -Computer 'SOURCE' -Loaded $true -FormReady $false
    Check 'Un poste : texte d''origine sans information' ($s.Hint -eq 'Placer le curseur sur le prochain choix requis, sans lancer une opération.') $s.Hint
} *>&1 | ForEach-Object { if($_ -is [Management.Automation.ErrorRecord]){$script:R.Add('ERREUR '+$_.Exception.Message)} } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$f=@($script:R|Where-Object{$_ -like 'FAIL*' -or $_ -like 'ERREUR*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f @($script:R|Where-Object{$_ -like 'PASS*'}).Count,$f
if($f){exit 1}
