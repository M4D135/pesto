#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, sous-lot « la protection du blob secret est jouee, pas seulement nommee ».
# Protect-PestoOfflineBytes et Unprotect-PestoOfflineBytes sont les deux seuls instants ou le blob secret change
# d'etat : protege a l'import, dechiffre a l'application, et entre les deux il ne vit que sous cette forme dans le
# magasin ProgramData. Les quatre suites qui jouent deja ce parcours (Entry, Blob, Apply, ExtensionEffects) les
# remplacent toutes par un double local qui xor les octets avec une cle de fixture : aucune ne les execute. Elles ne
# les jugeaient donc que de deux facons : un cas sur l'arbre scelle de Protect seul dans
# Run-OfflineJoin109BlobTests.ps1, et deux controles de texte ($protectSource.Contains('LocalMachine')) dans
# Run-OfflineJoin109EntryTests.ps1. Un sondage de douze reecritures de cette jambe, chacune rejouee contre ces
# quatre suites (copie temoin verte : 48, 68, 51 et 57), est consigne dans la preuve : NEUF laissent les quatre
# suites vertes — ajouter une entropie a la protection, en ajouter a la deprotection, rendre l'un ou l'autre tableau
# sans la virgule qui empeche sa decomposition, ne plus charger System.Security d'un cote ou de l'autre, proteger une
# autre valeur que le materiel, dechiffrer une autre valeur que le secret, et dechiffrer en re-protegeant. Seules les
# deux portees sont vues : proteger pour l'operateur fait rougir BlobTests (67/1) et EntryTests (47/1) ; dechiffrer
# pour l'operateur n'est vu que par EntryTests, et seulement parce que le mot LocalMachine disparait de la
# definition — la encore, c'est une comparaison de chaines qui tient lieu de garde.
# Cette suite juge les deux fonctions dans l'arbre syntaxique scelle parse par le vrai analyseur PowerShell (receveur,
# methode, ordre des trois arguments, portee, entropie, chargement de l'assemblage, virgule de rendu, absence de
# toute publication), et execute reellement ce qui l'est ici : les trois arguments tels que le produit les ecrit, la
# portee qui rend la valeur 1 de l'enumere la ou CurrentUser rend 0, l'entropie qui rend $null, l'argument materiel
# qui se relie bien au parametre, l'enonce Add-Type du produit, et la semantique de la virgule, montee portante par
# l'interprete lui-meme.
# Ce que cela atteste : ce que le produit demande reellement a DPAPI (portee machine, aucune entropie, le materiel
# remis tel quel), que rien ne filtre le secret hors de la fonction, et que les deux moities de la jambe s'accordent,
# sans quoi le secret protege a l'import ne serait jamais dechiffre a l'application.
# Ce que cela n'atteste pas : que DPAPI LocalMachine chiffre reellement, que la cle machine est bien celle du compte
# SYSTEM qui rejouera la jonction, ni ce que le magasin contient vraiment ; rien de tout cela ne s'observe hors de la
# plateforme cible. Aucun DPAPI rejoue, aucun djoin, aucune VM, aucun Windows reel, aucun AD reel, aucun reseau,
# aucun cfg.json operationnel lu.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad/Pesto.Engine.Runtime.ps1'
. $runtime
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
# Equal compare avec -cne : passe a une collection vide, -cne ne rend rien et le test passerait sans rien juger.
# Aucune comparaison de collection n'est donc ecrite sur une collection : elles comparent toutes un compte, qui
# refuse l'absence (0) comme le doublon (2).
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}}
# Le predicat passe a FindAll ne capture aucune variable : GetNewClosure rendait le type compare inutilisable, ce
# qui faisait passer chaque recherche de noeud a zero et transformait un moteur tronque en succes.
function AllNodes($Node){return @($Node.FindAll({param($n)$true},$true))}
function OfKind($Node,[string]$Kind){return @(AllNodes $Node|Where-Object{$_.GetType().Name -eq $Kind})}
function MemberReads($Node,[string]$Name){return @(OfKind $Node 'MemberExpressionAst'|Where-Object{$_.Member.Value -eq $Name})}
function CommandInvokes($Node,[string]$Name){return @(OfKind $Node 'CommandAst'|Where-Object{$_.GetCommandName() -eq $Name})}
function VariableUses($Node,[string]$Name){return @(OfKind $Node 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq $Name})}
function BodyVariableUses($Node,[string]$Name){
    # La declaration du parametre est aussi un VariableExpressionAst : la compter comme un usage annoncerait deux
    # usages la ou le produit n'en fait qu'un, et un parametre supprime du corps passerait pour un usage unique.
    $param=@(OfKind $Node 'ParamBlockAst')
    $limit=if($param.Count){$param[0].Extent.EndOffset}else{-1}
    return @(VariableUses $Node $Name|Where-Object{$_.Extent.StartOffset -ge $limit})
}
function SealedFunction([string]$Name){
    $found=@(AllNodes $script:tree|Where-Object{$_.GetType().Name -eq 'FunctionDefinitionAst' -and $_.Name -eq $Name})
    if($found.Count -ne 1){throw ('la fonction '+$Name+' nest pas trouvee exactement une fois dans le moteur scelle : '+[string]$found.Count)}
    return $found[0]
}
function DpapiCall([string]$Function,[string]$Method){
    # L'appel DPAPI du produit, retire de l'arbre scelle : receveur, methode et arguments sont lus dans les noeuds,
    # jamais dans une sous-chaine de la definition, qui laisserait passer un deuxieme appel ou un receveur change.
    $fn=SealedFunction $Function
    $calls=@(OfKind $fn 'InvokeMemberExpressionAst')
    Equal $calls.Count 1 ($Function+' ne comporte plus un seul appel de methode')
    $call=$calls[0]
    Equal ([string]$call.Member.Value) $Method ($Function+' nappelle plus '+$Method)
    Equal $call.Expression.GetType().Name 'TypeExpressionAst' ($Function+' nappelle plus une methode statique')
    Equal $call.Expression.Extent.Text '[Security.Cryptography.ProtectedData]' ($Function+' ne sadresse plus a ProtectedData')
    Equal $call.Arguments.Count 3 ($Function+' ne passe plus trois arguments a DPAPI')
    return $call
}
function Exec([string]$Text){return & ([ScriptBlock]::Create($Text))}
# Le moteur scelle est parse une seule fois : c'est l'analyseur de PowerShell qui juge, pas une comparaison de
# chaines. Un moteur qui ne se parse pas arrete la suite, faute de quoi chaque cas echouerait sur une absence de
# noeud sans que personne sache que le fichier est devenu illisible.
$parseTokens=$null;$parseErrors=$null
$script:tree=[System.Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count){throw ('le moteur scelle ne se parse pas : '+$parseErrors[0].Message)}
# La disponibilite de DPAPI sur l'hote est mesuree, pas supposee : c'est elle qui decide si les deux derniers cas
# jouent un aller-retour reel ou un refus reel, et elle est enregistree dans le rapport.
# PS 5.1 ne charge pas ce type avant le premier usage du produit.
Add-Type -AssemblyName System.Security
$script:dpapiAvailable=$true;$script:dpapiProbe=''
try{[void]([Security.Cryptography.ProtectedData]::Protect([byte[]]@(1,2,3),$null,[Security.Cryptography.DataProtectionScope]::LocalMachine))}
catch{$script:dpapiAvailable=$false;$script:dpapiProbe=[string]$_.Exception.Message}
# ---------- A. Les deux fonctions, lues dans l'arbre scelle ----------
Case 'Both secret functions exist exactly once in the sealed engine' {
    [void](SealedFunction 'Protect-PestoOfflineBytes')
    [void](SealedFunction 'Unprotect-PestoOfflineBytes')
}
Case 'Protect really calls the static ProtectedData::Protect, exactly once' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    $call=DpapiCall 'Protect-PestoOfflineBytes' 'Protect'
    # L'autre moite de la jambe se lit dans les invocations, pas dans les lectures de membre : ProtectedData::Protect
    # est un InvokeMemberExpressionAst, et compter des MemberExpressionAst laisserait passer un second appel.
    Equal @(OfKind $fn 'InvokeMemberExpressionAst'|Where-Object{$_.Member.Value -eq 'Unprotect'}).Count 0 'la protection dechiffre aussi : elle ne rend plus seulement du materiel protege'
    Assert ($call.Extent.StartOffset -lt $fn.Extent.EndOffset) 'l appel protege est hors de la fonction'
}
Case 'Unprotect really calls the static ProtectedData::Unprotect and never Protect' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    [void](DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect')
    Equal @(OfKind $fn 'InvokeMemberExpressionAst'|Where-Object{$_.Member.Value -eq 'Protect'}).Count 0 'la deprotection re-protege le secret au lieu de le dechiffrer'
}
Case 'Protect hands DPAPI the material, then the entropy, then the scope' {
    $args3=(DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Arguments
    Equal $args3[0].Extent.Text '$Bytes' 'le premier argument de la protection nest plus le materiel remis'
    Equal $args3[1].Extent.Text '$null' 'le deuxieme argument de la protection nest plus l entropie'
    Assert ($args3[0].Extent.StartOffset -lt $args3[1].Extent.StartOffset -and $args3[1].Extent.StartOffset -lt $args3[2].Extent.StartOffset) 'les trois arguments de la protection ne sont plus dans l ordre'
}
Case 'Unprotect hands DPAPI the secret, then the entropy, then the scope' {
    $args3=(DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect').Arguments
    Equal $args3[0].Extent.Text '$Bytes' 'le premier argument de la deprotection nest plus le secret remis'
    Equal $args3[1].Extent.Text '$null' 'le deuxieme argument de la deprotection nest plus l entropie'
    Assert ($args3[0].Extent.StartOffset -lt $args3[1].Extent.StartOffset -and $args3[1].Extent.StartOffset -lt $args3[2].Extent.StartOffset) 'les trois arguments de la deprotection ne sont plus dans l ordre'
}
Case 'Protect protects the material it was handed, not a constant and not nothing' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(BodyVariableUses $fn 'Bytes').Count 1 'le materiel remis n est plus utilise exactement une fois par la protection'
    Assert (-not @(OfKind $fn 'StringConstantExpressionAst'|Where-Object{$_.Value -match '[0-9]'})) 'la protection fabrique une donnee constante'
}
Case 'Unprotect decrypts the secret it was handed, not a constant and not nothing' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    Equal @(BodyVariableUses $fn 'Bytes').Count 1 'le secret remis n est plus utilise exactement une fois par la deprotection'
    Assert (-not @(OfKind $fn 'StringConstantExpressionAst'|Where-Object{$_.Value -match '[0-9]'})) 'la deprotection fabrique une donnee constante'
}
Case 'Protect asks DPAPI for no additional entropy' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(VariableUses $fn 'null').Count 1 'la protection ne passe plus exactement une entropie nulle'
    Equal @(MemberReads $fn 'Entropy').Count 0 'la protection se voit ajouter une entropie'
}
Case 'Unprotect asks DPAPI for no additional entropy' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    Equal @(VariableUses $fn 'null').Count 1 'la deprotection ne passe plus exactement une entropie nulle'
    Equal @(MemberReads $fn 'Entropy').Count 0 'la deprotection se voit ajouter une entropie'
}
Case 'Protect protects for the machine and never for the operator who imports' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(MemberReads $fn 'LocalMachine').Count 1 'le secret n est plus protege pour la machine exactement une fois'
    Equal @(MemberReads $fn 'CurrentUser').Count 0 'le secret est protege pour l operateur : le compte qui rejouera la jonction ne pourrait plus le relire'
    Equal (DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Arguments[2].Extent.Text '[Security.Cryptography.DataProtectionScope]::LocalMachine' 'la portee de la protection a change de forme'
}
Case 'Unprotect decrypts for the machine and never for the operator who applies' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    Equal @(MemberReads $fn 'LocalMachine').Count 1 'le secret n est plus dechiffre pour la machine exactement une fois'
    Equal @(MemberReads $fn 'CurrentUser').Count 0 'le secret est dechiffre pour l operateur : le compte qui rejouera la jonction ne pourrait plus le relire'
    Equal (DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect').Arguments[2].Extent.Text '[Security.Cryptography.DataProtectionScope]::LocalMachine' 'la portee de la deprotection a change de forme'
}
Case 'The two halves of the secret leg agree on scope and entropy' {
    # Un desaccord d un cote seulement est le defaut le plus rentable : l import reussit, l application ne dechiffre
    # jamais, et seule la valeur executee des deux noeuds le montre.
    $pc=(DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Arguments[2]
    $uc=(DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect').Arguments[2]
    $pv=Exec $pc.Extent.Text;$uv=Exec $uc.Extent.Text
    Assert ($null -ne $pv -and $null -ne $uv) 'la portee demandee a DPAPI ne se value plus'
    Equal $pv.GetType().Name $uv.GetType().Name 'les deux moities ne demandent plus le meme type de portee'
    Equal ([int]$pv) ([int]$uv) 'la protection et la deprotection ne visent plus la meme portee'
    $pe=Exec (DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Arguments[1].Extent.Text
    $ue=Exec (DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect').Arguments[1].Extent.Text
    Assert ($null -eq $pe -and $null -eq $ue) 'les deux moities n exigent plus toutes deux l absence d entropie'
}
Case 'Protect loads the assembly it needs before calling DPAPI' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    $loads=@(CommandInvokes $fn 'Add-Type')
    Equal $loads.Count 1 'la protection ne charge plus l assemblage exactement une fois'
    Equal @(OfKind $loads[0] 'CommandParameterAst'|Where-Object{$_.ParameterName -eq 'AssemblyName'}).Count 1 'la protection ne charge plus un assemblage par son nom'
    Equal @(OfKind $loads[0] 'StringConstantExpressionAst'|Where-Object{$_.Value -eq 'System.Security'}).Count 1 'ce n est plus System.Security qui est charge avant la protection'
    Assert ($loads[0].Extent.StartOffset -lt (DpapiCall $fn.Name 'Protect').Extent.StartOffset) 'l assemblage est charge apres l appel a DPAPI'
}
Case 'Unprotect loads the assembly it needs before calling DPAPI' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    $loads=@(CommandInvokes $fn 'Add-Type')
    Equal $loads.Count 1 'la deprotection ne charge plus l assemblage exactement une fois'
    Equal @(OfKind $loads[0] 'CommandParameterAst'|Where-Object{$_.ParameterName -eq 'AssemblyName'}).Count 1 'la deprotection ne charge plus un assemblage par son nom'
    Equal @(OfKind $loads[0] 'StringConstantExpressionAst'|Where-Object{$_.Value -eq 'System.Security'}).Count 1 'ce n est plus System.Security qui est charge avant la deprotection'
    Assert ($loads[0].Extent.StartOffset -lt (DpapiCall $fn.Name 'Unprotect').Extent.StartOffset) 'l assemblage est charge apres l appel a DPAPI'
}
Case 'Protect returns the protected array whole, kept whole by the comma' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(OfKind $fn 'ReturnStatementAst').Count 1 'la protection ne rend plus sa valeur exactement une fois'
    $commas=@(OfKind $fn 'ArrayLiteralAst')
    Equal $commas.Count 1 'le tableau protege nest plus rendu par la virgule qui empeche sa decomposition'
    $call=(DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Extent
    Assert ($commas[0].Extent.StartOffset -le $call.StartOffset -and $commas[0].Extent.EndOffset -ge $call.EndOffset) 'la virgule ne porte plus le resultat de l appel a DPAPI'
}
Case 'Unprotect returns the decrypted array whole, kept whole by the comma' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    Equal @(OfKind $fn 'ReturnStatementAst').Count 1 'la deprotection ne rend plus sa valeur exactement une fois'
    $commas=@(OfKind $fn 'ArrayLiteralAst')
    Equal $commas.Count 1 'le tableau dechiffre nest plus rendu par la virgule qui empeche sa decomposition'
    $call=(DpapiCall 'Unprotect-PestoOfflineBytes' 'Unprotect').Extent
    Assert ($commas[0].Extent.StartOffset -le $call.StartOffset -and $commas[0].Extent.EndOffset -ge $call.EndOffset) 'la virgule ne porte plus le resultat de l appel a DPAPI'
}
Case 'Protect publishes nothing but its return value' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(OfKind $fn 'CommandAst').Count 1 'la protection lance une deuxieme commande : le materiel pourrait filtrer hors de la fonction'
    Equal @(OfKind $fn 'CommandAst'|Where-Object{$_.GetCommandName() -ne 'Add-Type'}).Count 0 'la commande lancee par la protection n est plus Add-Type'
}
Case 'Unprotect publishes nothing but its return value' {
    $fn=SealedFunction 'Unprotect-PestoOfflineBytes'
    Equal @(OfKind $fn 'CommandAst').Count 1 'la deprotection lance une deuxieme commande : le secret pourrait filtrer hors de la fonction'
    Equal @(OfKind $fn 'CommandAst'|Where-Object{$_.GetCommandName() -ne 'Add-Type'}).Count 0 'la commande lancee par la deprotection n est plus Add-Type'
}
Case 'Both secret functions only accept bytes' {
    foreach($name in @('Protect-PestoOfflineBytes','Unprotect-PestoOfflineBytes')){
        $params=@(OfKind (SealedFunction $name) 'ParameterAst')
        Equal $params.Count 1 ($name+' ne declare plus un seul parametre')
        $types=@(OfKind $params[0] 'TypeConstraintAst')
        Equal $types.Count 1 ($name+' ne declare plus exactement une contrainte de type')
        Equal $types[0].Extent.Text '[byte[]]' ($name+' n exige plus des octets : une chaine pourrait lui etre remise')
    }
}
# ---------- B. Ce que le produit calcule vraiment, execute par le vrai interpreteur ----------
Case 'The scope the product writes really evaluates to LocalMachine, and CurrentUser really differs' {
    $node=(DpapiCall 'Protect-PestoOfflineBytes' 'Protect').Arguments[2]
    $scope=Exec $node.Extent.Text
    Assert ($null -ne $scope) 'la portee ecrite par le produit ne se value pas'
    Equal ([int]$scope) 1 'la portee demandee par le produit ne vaut plus LocalMachine'
    Equal ([int](Exec '[Security.Cryptography.DataProtectionScope]::CurrentUser')) 0 'CurrentUser ne vaut plus 0 : la comparaison de portee ne prouverait plus rien'
    Assert ([int]$scope -ne [int](Exec '[Security.Cryptography.DataProtectionScope]::CurrentUser')) 'les deux portees ne sont plus distinctes'
}
Case 'The entropy the product writes really evaluates to nothing' {
    foreach($name in @('Protect-PestoOfflineBytes','Unprotect-PestoOfflineBytes')){
        $node=(DpapiCall $name $(if($name -eq 'Protect-PestoOfflineBytes'){'Protect'}else{'Unprotect'})).Arguments[1]
        Assert ($null -eq (Exec $node.Extent.Text)) ($name+' : l entropie ecrite par le produit ne se value plus a rien')
    }
}
Case 'The material argument really binds the parameter the caller fills' {
    $script:Bytes=[byte[]]@(11,22,33,44)
    foreach($name in @('Protect-PestoOfflineBytes','Unprotect-PestoOfflineBytes')){
        $node=(DpapiCall $name $(if($name -eq 'Protect-PestoOfflineBytes'){'Protect'}else{'Unprotect'})).Arguments[0]
        $bound=@(Exec $node.Extent.Text)
        Equal $bound.Count 4 ($name+' : le premier argument ne rend plus les quatre octets remis')
        Equal (([string]($bound -join ','))) '11,22,33,44' ($name+' : le premier argument ne rend plus les octets remis')
    }
}
Case 'The assembly statement the product writes really loads' {
    foreach($name in @('Protect-PestoOfflineBytes','Unprotect-PestoOfflineBytes')){
        $load=@(CommandInvokes (SealedFunction $name) 'Add-Type')[0]
        Exec $load.Extent.Text
    }
}
Case 'The comma that keeps the array whole is load-bearing, shown by the interpreter' {
    $with=Exec 'return ,([byte[]]@(7))'
    $without=Exec 'return ([byte[]]@(7))'
    Assert ($with -is [byte[]]) 'la forme avec virgule ne rend plus un tableau : la demonstration ne porte plus'
    Assert (-not ($without -is [array])) 'la forme sans virgule rend encore un tableau : la virgule du produit ne protege plus rien'
    Equal ([string]$without) '7' 'la forme sans virgule ne rend plus un octet simple'
}
Case 'DPAPI availability on this host is measured, never assumed' {
    Assert ($script:dpapiAvailable -is [bool]) 'la disponibilite de DPAPI n a pas ete mesuree'
    if($env:OS -eq 'Windows_NT'){Assert $script:dpapiAvailable 'sur Windows DPAPI doit repondre : sans reponse le double de la suite passerait pour le produit'}
    else{Assert (-not $script:dpapiAvailable) ('DPAPI pretend fonctionner hors Windows ('+$script:dpapiProbe+') : les deux derniers cas ne jugeraient plus le refus')}
}
Case 'The sealed protection really protects, or really refuses, but never returns a stand-in' {
    $bytes=[byte[]]@(1,2,3,4,5,6,7,8)
    if($script:dpapiAvailable){
        $sealed=Protect-PestoOfflineBytes -Bytes $bytes
        Assert ($sealed -is [byte[]]) 'la protection scellee ne rend pas un tableau d octets'
        Assert ($sealed.Length -gt 0) 'la protection scellee rend un secret vide'
        Assert (([string]($sealed -join ',')) -ne ([string]($bytes -join ','))) 'la protection scellee rend le materiel clair'
        $back=Unprotect-PestoOfflineBytes -Bytes $sealed
        Assert (([string](@($back) -join ',')) -eq ([string]($bytes -join ','))) 'l aller-retour scelle ne rend plus le materiel d origine'
    }else{
        $returned=$null;$threw=$false
        try{$returned=Protect-PestoOfflineBytes -Bytes $bytes}catch{$threw=$true}
        Assert $threw ('la protection scellee a rendu ['+[string]$returned+'] sur une plateforme sans DPAPI : un faux secret partirait au magasin')
        Assert ($null -eq $returned) 'la protection scellee a rendu une valeur tout en echouant'
        Assert ($script:dpapiProbe -match 'not supported on this platform') ('la protection echoue pour une autre raison que la plateforme : '+$script:dpapiProbe)
    }
}
Case 'The sealed deprotection really refuses a foreign blob instead of inventing plaintext' {
    if($script:dpapiAvailable){
        $returned=$null;$threw=$false
        try{$returned=Unprotect-PestoOfflineBytes -Bytes ([byte[]]@(9,8,7,6))}catch{$threw=$true}
        Assert $threw ('la deprotection scellee a rendu ['+[string]$returned+'] sur un secret qui ne vient pas de DPAPI : une donnee inventee partirait vers djoin')
        Assert ($null -eq $returned) 'la deprotection scellee a rendu une valeur tout en refusant'
    }else{
        $returned=$null;$threw=$false
        try{$returned=Unprotect-PestoOfflineBytes -Bytes ([byte[]]@(9,8,7,6))}catch{$threw=$true}
        Assert $threw ('la deprotection scellee a rendu ['+[string]$returned+'] sur une plateforme sans DPAPI : un faux clair partirait vers djoin')
        Assert ($null -eq $returned) 'la deprotection scellee a rendu une valeur tout en echouant'
        Assert ($script:dpapiProbe -match 'not supported on this platform') ('la deprotection echoue pour une autre raison que la plateforme : '+$script:dpapiProbe)
    }
}
# ---------- C. Les deux sites ou le produit se sert de la jambe ----------
Case 'Import protects the clear material exactly once and never decrypts' {
    $fn=SealedFunction 'Import-PestoOfflineBlob'
    $protect=@(CommandInvokes $fn 'Protect-PestoOfflineBytes')
    Equal $protect.Count 1 'le materiel nest plus protege exactement une fois a l import'
    Equal @(OfKind $protect[0] 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq 'bytes'}).Count 1 'ce n est plus le materiel clair qui est remis a la protection'
    Equal @(CommandInvokes $fn 'Unprotect-PestoOfflineBytes').Count 0 'l import dechiffre : il n a rien a dechiffrer'
}
Case 'Apply decrypts the stored secret exactly once and on the decoded bytes' {
    $fn=SealedFunction 'Invoke-PestoOfflineApply'
    $unprotect=@(CommandInvokes $fn 'Unprotect-PestoOfflineBytes')
    Equal $unprotect.Count 1 'le secret n est plus dechiffre exactement une fois a l application'
    Equal @(OfKind $unprotect[0] 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq 'secret'}).Count 1 'ce n est plus le secret relu du magasin qui est dechiffre'
    Equal @(CommandInvokes $fn 'Protect-PestoOfflineBytes').Count 0 'l application re-protege le secret : il ne serait plus jamais dechiffrable'
}
Case 'Apply confronts the decrypted material with the fingerprint sealed in the plan' {
    $fn=SealedFunction 'Invoke-PestoOfflineApply'
    $hash=@(CommandInvokes $fn 'Get-PestoBytesHash')
    Equal $hash.Count 1 'le materiel dechiffre n est plus confronte exactement une fois a l empreinte du plan'
    Equal @(OfKind $hash[0] 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq 'bytes'}).Count 1 'ce n est plus le materiel dechiffre qui est confronte a l empreinte du plan'
    $unprotect=@(CommandInvokes $fn 'Unprotect-PestoOfflineBytes')[0]
    Assert ($unprotect.Extent.StartOffset -lt $hash[0].Extent.StartOffset) 'l empreinte est calculee avant le dechiffrement : la confrontation ne porte plus sur rien'
}
$report=[pscustomobject]@{Schema=1;Suite='OfflineJoin109Secret';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;DPAPIExecuted=$script:dpapiAvailable;DPAPIProbe=$script:dpapiProbe;DjoinExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Les deux fonctions DPAPI scellees jugees condition par condition dans l arbre syntaxique parse par le vrai analyseur PowerShell ; portee, entropie, argument materiel, enonce Add-Type et semantique de la virgule reellement executes ; DPAPI lui-meme refuse sur cette plateforme, djoin, ACL, magasins et statut du poste non executes'}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Output ('OfflineJoin109Secret: '+$script:passed+' passed, '+$script:failed+' failed. Sealed syntax tree of the two DPAPI functions judged by the real PowerShell parser; scope, entropy, material argument, Add-Type statement and array comma really executed; DPAPI itself refused on this platform; no djoin, no Windows, no VM.')
if($script:failed -gt 0){exit 1}
