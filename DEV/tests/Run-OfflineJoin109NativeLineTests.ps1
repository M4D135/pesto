#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, sous-lot « la ligne remise a djoin est calculee, pas seulement recopiee ».
# Invoke-PestoOfflineNative est le seul instant ou le blob secret, dechiffre a l'appel, quitte le magasin protege
# pour les mains de djoin.exe. Run-OfflineJoin109NativeTests.ps1 ne jugeait cette ligne que par ses chaines
# litterales. Un sondage le montre : permuter les deux operands de la concatenation - envoyer le blob clair sous
# /windowspath et la racine systeme sous /loadfile - laisse cette suite a 20/20, comme d'ailleurs remplacer le blob
# par le chemin du binaire lui-meme. La ligne d'arguments n'avait donc jamais ete calculee par personne : seuls ses
# morceaux de texte etaient controles, et le contrat djoin est justement dans l'aiguillage des deux chemins.
# Cette suite calcule reellement la ligne : l'expression de concatenation est retiree de l'arbre syntaxique scelle
# et executee par le vrai interpreteur PowerShell, avec pour seules entrees les deux chemins que le produit lui
# remet. Le texte juge est celui du produit ; aucune chaine djoin n'est reecrite par la suite, qui ne fournit que
# les chemins. La garde d'injection est de meme jouee pour de vrai, statement complet avec sa condition et son
# throw, sur des chemins portant citation double, retour chariot et saut de ligne.
# Ce que cela atteste : la chaine exacte remise a ProcessStartInfo.Arguments, et le fait qu'un chemin hostile ne
# l'atteint jamais. Ce que cela n'atteste pas : la facon dont djoin.exe decode cette chaine, observable seul sur la
# plateforme cible. Aucun djoin, aucune VM, aucun Windows reel, aucun AD reel, aucun reseau, aucun cfg.json.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad/Pesto.Engine.Runtime.ps1'
. $runtime
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}}
# Le predicat passe a FindAll ne capture aucune variable : GetNewClosure rendait le type compare inutilisable, ce
# qui faisait passer chaque recherche de noeud a zero et transformait un moteur tronque en succes.
function AllNodes($Node){return @($Node.FindAll({param($n)$true},$true))}
function OfKind($Node,[string]$Kind){return @(AllNodes $Node|Where-Object{$_.GetType().Name -eq $Kind})}
function MemberAssignments($Node){return @(OfKind $Node 'AssignmentStatementAst'|Where-Object{$_.Left.GetType().Name -eq 'MemberExpressionAst'})}
function VariableUses($Node,[string]$Name){return @(OfKind $Node 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq $Name})}
function StringLiterals($Node){return @(OfKind $Node 'StringConstantExpressionAst'|Sort-Object{$_.Extent.StartOffset}|ForEach-Object{$_.Value})}
function ConcatOperands($Node){
    # Les feuilles de la concatenation dans l'ordre source : les chaines litterales alternent avec les variables.
    return @(AllNodes $Node|Where-Object{$_.GetType().Name -in @('StringConstantExpressionAst','VariableExpressionAst')}|Sort-Object{$_.Extent.StartOffset})
}
function Split-NativeFields([string]$Line){
    # Decoupe en champs tels que les rendrait un executable Win32 : les blancs entre citations doubles appartiennent
    # au champ. La suite ne juge que le nombre de champs et leur contenu, jamais elle ne construit la ligne.
    $fields=@();$current='';$inQuote=$false
    foreach($c in $Line.ToCharArray()){
        if($c -eq '"'){$inQuote=-not $inQuote;$current+=$c}
        elseif(($c -eq ' ' -or $c -eq "`t") -and -not $inQuote){if($current -ne ''){$fields=@($fields+$current);$current=''}}
        else{$current+=$c}
    }
    if($current -ne ''){$fields=@($fields+$current)}
    return $fields
}
# Le moteur scelle est parse une seule fois : c'est l'analyseur de PowerShell qui juge. Un moteur qui ne se parse
# pas arrete la suite, faute de quoi chaque cas echouerait sur une absence de noeud sans que personne sache que le
# fichier est devenu illisible.
$parseTokens=$null;$parseErrors=$null
$script:tree=[System.Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count){throw ('le moteur scelle ne se parse pas : '+$parseErrors[0].Message)}
$found=@(AllNodes $script:tree|Where-Object{$_.GetType().Name -eq 'FunctionDefinitionAst' -and $_.Name -eq 'Invoke-PestoOfflineNative'})
if($found.Count -ne 1){throw ('le transport natif hors connexion n est pas trouve exactement une fois dans le moteur scelle : '+$found.Count)}
$script:fn=$found[0]
$argAssign=@(MemberAssignments $script:fn|Where-Object{$_.Left.Member.Value -eq 'Arguments'})
if($argAssign.Count -ne 1){throw ('la ligne d arguments du processus natif n est pas affectee exactement une fois : '+$argAssign.Count)}
$script:arguments=$argAssign[0]
$guards=@(OfKind $script:fn 'IfStatementAst'|Where-Object{$_.Extent.Text.Contains('["\r\n]')})
if($guards.Count -ne 1){throw ('la garde d injection de la ligne de commande n est pas trouvee exactement une fois : '+$guards.Count)}
$script:guard=$guards[0]
# Le texte execute est retire du fichier scelle que la suite dot-source deja en entier : aucun nouveau domaine de
# confiance n'est ouvert. La suite ne fournit que les deux chemins, par parametres nommes.
$script:lineBuilder=[ScriptBlock]::Create('param($Path,$windows) '+$script:arguments.Right.Extent.Text)
$script:guardStatement=[ScriptBlock]::Create('param($Path,$windows) '+$script:guard.Extent.Text)
function NativeLine([string]$Blob,[string]$Root){return [string](& $script:lineBuilder -Path $Blob -windows $Root)}
function GuardRefuses([string]$Blob,[string]$Root){
    $threw=$false
    try{& $script:guardStatement -Path $Blob -windows $Root|Out-Null}catch{$threw=$true}
    return $threw
}
$blobReal='C:\ProgramData\GP\OfflineJoin\'+('0'*64)+'.odj.tmp'
$rootReal='C:\Windows'
$blobShapes=@(
    $blobReal,
    'C:\ProgramData\GP\OfflineJoin\a b.odj.tmp',
    'C:\Users\M. Dupont\odj tmp\a&b.odj.tmp',
    'C:\temp\a|b.odj.tmp',
    'C:\temp\a;b.odj.tmp',
    'C:\temp\a$b.odj.tmp',
    'C:\temp\a`b.odj.tmp',
    'C:\temp\a%TEMP%b.odj.tmp',
    'C:\temp\a(b)c.odj.tmp',
    'C:\temp\a^b.odj.tmp',
    'C:\temp\a=b.odj.tmp',
    'C:\temp\café.odj.tmp',
    '\\serveur\partage\odj\a.odj.tmp'
)
$rootShapes=@('C:\Windows','C:\Program Files\Windows NT','C:\Windows\WindowsPowerShell\v1.0','C:\temp\Windows (x86)')
$hostileBlobs=@('C:\temp\a"b.odj.tmp',"C:\temp`ra.odj.tmp","C:\temp`na.odj.tmp")
$hostileRoots=@('C:\Windows"x',"C:\Windows`rx","C:\Windows`nx")

# ---------- A. L'aiguillage des deux chemins, lu dans l'arbre scelle ----------
Case 'The djoin line is handed to the process start info, never to a local' {
    Equal $script:arguments.Left.Member.Value 'Arguments' "ce n'est plus la ligne d'arguments du processus qui est affectee"
    Equal $script:arguments.Left.Expression.GetType().Name 'VariableExpressionAst' "la ligne d'arguments n'est plus portee par l'objet de lancement"
    Equal $script:arguments.Left.Expression.VariablePath.UserPath 'info' "la ligne d'arguments n'est plus portee par l'objet de lancement"
}
Case 'The djoin line is built by concatenating exactly five operands' {
    # La forme d'abord : une chaine interpolable a la place de la concatenation ferait tomber le compte d operands
    # sans dire que ce sont les chemins qui cessent d'etre passes par des variables distinctes.
    foreach($node in @(AllNodes $script:arguments.Right)){
        Assert ($node.GetType().Name -in @('CommandExpressionAst','BinaryExpressionAst','StringConstantExpressionAst','VariableExpressionAst')) ('la ligne djoin contient un noeud inattendu ['+$node.GetType().Name+'] : '+$node.Extent.Text)
    }
    $operands=@(ConcatOperands $script:arguments.Right)
    Equal $operands.Count 5 "la ligne d'arguments n'est plus montee par exactement cinq operands"
    $binaries=@(OfKind $script:arguments.Right 'BinaryExpressionAst')
    Equal $binaries.Count 4 "la ligne d'arguments n'est plus montee par exactement quatre concatenations"
    foreach($binary in $binaries){Equal $binary.Operator.ToString() 'Plus' "un lien de la ligne d'arguments n'est plus une concatenation"}
    for($i=0;$i -lt $operands.Count;$i++){
        $want=if($i % 2 -eq 0){'StringConstantExpressionAst'}else{'VariableExpressionAst'}
        Equal $operands[$i].GetType().Name $want ('l operand ['+$i+'] de la ligne djoin n est plus du type attendu')
    }
}
Case 'The clear blob is the operand of /loadfile and the system root the operand of /windowspath' {
    $operands=@(ConcatOperands $script:arguments.Right)
    Equal $operands[1].VariablePath.UserPath 'Path' "le blob clair n'est plus l'operand branche sur /loadfile : le secret partirait vers un autre switch"
    Equal $operands[3].VariablePath.UserPath 'windows' "la racine systeme n'est plus l'operand branche sur /windowspath"
    $literals=@(StringLiterals $script:arguments.Right)
    Assert ($literals[0].EndsWith('/loadfile "')) "le premier chemin cite n'est plus celui remis a /loadfile"
    Assert ($literals[1].Contains('/windowspath "')) "le second chemin cite n'est plus celui remis a /windowspath"
}
Case 'Each guarded path is interpolated exactly once into the djoin line' {
    Equal (@(VariableUses $script:arguments.Right 'Path').Count) 1 'le blob clair n est plus interpolate exactement une fois dans la ligne djoin'
    Equal (@(VariableUses $script:arguments.Right 'windows').Count) 1 'la racine systeme n est plus interpolate exactement une fois dans la ligne djoin'
    Equal (@(VariableUses $script:arguments.Right 'exe').Count) 0 'le chemin du binaire entre dans la ligne djoin : djoin se chargerait lui-meme'
}
Case 'The injection guard is read before the djoin line is built' {
    Assert ($script:guard.Extent.StartOffset -lt $script:arguments.Extent.StartOffset) "la garde d'injection ne precede plus la construction de la ligne djoin : un chemin hostile serait concatene avant d'etre refuse"
}
# ---------- B. La ligne reellement calculee par l'expression du produit ----------
Case 'The real djoin line is exactly the four contract switches with both paths quoted' {
    $expected='/requestodj /loadfile "'+$blobReal+'" /windowspath "'+$rootReal+'" /localos'
    Equal (NativeLine $blobReal $rootReal) $expected "la ligne reellement calculee par le produit n'est pas exactement le contrat djoin"
}
Case 'The clear blob is handed to /loadfile, never to /windowspath' {
    $line=NativeLine $blobReal $rootReal
    Assert ($line.Contains('/loadfile "'+$blobReal+'"')) 'le blob clair ne parait plus cite sous /loadfile'
    Assert (-not $line.Contains('/windowspath "'+$blobReal+'"')) 'le blob clair est remis a djoin sous /windowspath : djoin chargerait la racine systeme comme blob et le secret partirait ailleurs'
}
Case 'The system root is handed to /windowspath, never to /loadfile' {
    $line=NativeLine $blobReal $rootReal
    Assert ($line.Contains('/windowspath "'+$rootReal+'"')) 'la racine systeme ne parait plus citee sous /windowspath'
    Assert (-not $line.Contains('/loadfile "'+$rootReal+'"')) 'la racine systeme est remise a djoin sous /loadfile : la demande chargerait le systeme comme blob'
}
Case 'The computed djoin line holds exactly the six contract fields' {
    $line=NativeLine $blobReal $rootReal
    $fields=@(Split-NativeFields $line)
    Equal $fields.Count 6 'la ligne calculee ne decoupe plus exactement les six champs du contrat djoin'
    Equal $fields[0] '/requestodj' 'le premier champ n est plus /requestodj'
    Equal $fields[1] '/loadfile' 'le deuxieme champ n est plus /loadfile'
    Equal $fields[2] ('"'+$blobReal+'"') 'le troisieme champ n est plus le blob cite'
    Equal $fields[3] '/windowspath' 'le quatrieme champ n est plus /windowspath'
    Equal $fields[4] ('"'+$rootReal+'"') 'le cinquieme champ n est plus la racine systeme citee'
    Equal $fields[5] '/localos' 'le dernier champ n est plus /localos'
    Equal ([regex]::Matches($line,'"').Count) 4 'les deux chemins ne sont plus cites chacun des deux cotes'
}
Case 'A blob path with spaces stays a single quoted field of the djoin line' {
    $fields=@(Split-NativeFields (NativeLine 'C:\ProgramData\GP\OfflineJoin\a b.odj.tmp' $rootReal))
    Equal $fields.Count 6 'un chemin de blob a espaces se decoupe en plusieurs arguments remis a djoin'
    Equal $fields[2] '"C:\ProgramData\GP\OfflineJoin\a b.odj.tmp"' 'le champ du blob a cesse de porter le chemin cite en entier'
}
Case 'A system root with spaces stays a single quoted field of the djoin line' {
    $fields=@(Split-NativeFields (NativeLine $blobReal 'C:\Program Files\Windows NT'))
    Equal $fields.Count 6 'une racine systeme a espaces se decoupe en plusieurs arguments remis a djoin'
    Equal $fields[4] '"C:\Program Files\Windows NT"' 'le champ de la racine a cesse de porter la racine citee en entier'
}
Case 'No accepted path shape ever opens a seventh field of the djoin line' {
    foreach($blob in $blobShapes){foreach($root in $rootShapes){
        $line=NativeLine $blob $root
        Assert ($line.Contains('"'+$blob+'"')) ('le chemin du blob ['+$blob+'] ne survit pas cite verbatim dans la ligne djoin')
        Assert ($line.Contains('"'+$root+'"')) ('la racine systeme ['+$root+'] ne survit pas citee verbatim dans la ligne djoin')
        Equal (@(Split-NativeFields $line).Count) 6 ('un chemin accepte ouvre un septieme champ remis a djoin : ['+$blob+' | '+$root+']')
    }}
}
Case 'The computed djoin line never carries an identity or a credential switch' {
    foreach($blob in $blobShapes){foreach($root in $rootShapes){
        $line=NativeLine $blob $root
        $flat=$line.ToLowerInvariant()
        foreach($needle in @('/machine','/user','/ou','/domain','/netbios','/password','/lazy')){
            Assert (-not $flat.Contains($needle)) ('la ligne calculee vehicule ['+$needle+'] : une identite ou un secret sortirait du magasin protege')
        }
        Assert (-not ($line -match '(?i)(\s|^)/p(\s|$)|(\s|^)/rp(\s|$)')) 'la ligne calculee vehicule un mot de passe en ligne de commande'
    }}
}
Case 'The computed djoin line depends on nothing but the two paths it is given' {
    $Path='PIEGE-AMBIANT';$windows='RACINE-AMBIANTE'
    $first=NativeLine $blobReal $rootReal
    Equal (NativeLine $blobReal $rootReal) $first 'la ligne calculee change d un appel a l autre : elle depend d un etat ambiant'
    Assert (-not $first.Contains('PIEGE-AMBIANT')) "la ligne djoin herite d'un chemin ambiant au lieu du blob remis a l'appel"
    Assert (-not $first.Contains('RACINE-AMBIANTE')) "la ligne djoin herite d'une racine ambiante au lieu de la racine systeme"
    Assert ((NativeLine 'C:\temp\autre.odj.tmp' $rootReal).Contains('\autre.odj.tmp')) 'deux blobs differents produisent la meme ligne : le blob remis a l appel est ignore'
}
# ---------- C. La garde d'injection, reellement executee statement complet ----------
Case 'A blob path carrying a double quote is really refused before the line is built' {
    Assert (GuardRefuses 'C:\temp\a"b.odj.tmp' $rootReal) 'un chemin de blob portant une citation double atteint la ligne djoin : le champ se fermerait et la suite serait interpretee par djoin'
}
Case 'A blob path carrying a carriage return is really refused' {
    Assert (GuardRefuses "C:\temp`ra.odj.tmp" $rootReal) 'un chemin de blob portant un retour chariot atteint la ligne djoin'
}
Case 'A blob path carrying a line feed is really refused' {
    Assert (GuardRefuses "C:\temp`na.odj.tmp" $rootReal) 'un chemin de blob portant un saut de ligne atteint la ligne djoin'
}
Case 'A system root carrying a double quote is really refused' {
    Assert (GuardRefuses $blobReal 'C:\Windows"x') 'une racine systeme portant une citation double atteint la ligne djoin'
}
Case 'A system root carrying a carriage return is really refused' {
    Assert (GuardRefuses $blobReal "C:\Windows`rx") 'une racine systeme portant un retour chariot atteint la ligne djoin'
}
Case 'A system root carrying a line feed is really refused' {
    Assert (GuardRefuses $blobReal "C:\Windows`nx") 'une racine systeme portant un saut de ligne atteint la ligne djoin'
}
Case 'The guard refusal is the product message, not a harness invention' {
    $message='<aucun refus>'
    try{& $script:guardStatement -Path 'C:\temp\a"b.odj.tmp' -windows $rootReal|Out-Null}catch{$message=[string]$_.Exception.Message}
    Assert ($message.Contains('Chemin natif invalide.')) ("la garde d'injection ne rend plus le message du produit : "+$message)
}
Case 'Plain blob and system root pass the guard without throwing' {
    foreach($blob in $blobShapes){foreach($root in $rootShapes){
        Assert (-not (GuardRefuses $blob $root)) ('un chemin legitime est refuse par la garde : ['+$blob+' | '+$root+']')
    }}
}
Case 'The guard is load-bearing: bypassed, a quoted blob path would wreck the djoin line' {
    $hostile='C:\temp\a"b.odj.tmp'
    Assert (GuardRefuses $hostile $rootReal) 'la garde ne refuse plus le chemin portant citation'
    $fields=@(Split-NativeFields (NativeLine $hostile $rootReal))
    Assert ($fields.Count -ne 6) 'sans la garde, un blob portant une citation rendrait quand meme les six champs du contrat : la garde ne protegerait rien'
    Assert (-not ($fields -contains ('"'+$hostile+'"'))) 'sans la garde, le blob portant citation resterait seul dans son champ : la garde ne protegerait rien'
    Assert (-not ($fields -contains '/localos')) 'sans la garde, /localos ne serait plus rendu a djoin : la citation du blob aurait avale le reste de la ligne'
}
Case 'Every path shape is either refused by the guard or keeps exactly six fields' {
    $blobs=@($blobShapes+$hostileBlobs);$roots=@($rootShapes+$hostileRoots)
    foreach($blob in $blobs){foreach($root in $roots){
        if(-not (GuardRefuses $blob $root)){
            Equal (@(Split-NativeFields (NativeLine $blob $root)).Count) 6 ('un chemin accepte par la garde ouvre un septieme champ : ['+$blob+' | '+$root+']')
        }
    }}
}
if($ReportPath){[IO.File]::WriteAllText($ReportPath,(@{Suite='OfflineJoin109NativeLine';Passed=$script:passed;Failed=$script:failed}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
Write-Output ('OfflineJoin109NativeLine: '+$script:passed+' passed, '+$script:failed+' failed. The djoin command line really computed by the product own concatenation read from the sealed tree, and the injection guard really executed statement and throw included; no djoin, no Windows, no VM.')
if($script:failed -gt 0){exit 1}
