#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, sous-lot « le blob secret quitte le magasin protege ». Invoke-PestoOfflineNative est le seul instant
# ou le blob clair, dechiffre a l'appel, est remis a djoin.exe. Les deux suites existantes du point
# (Run-OfflineJoin109EntryTests.ps1, Run-ExtensionEffectsTests.ps1) la remplacent par un double avant de jouer le
# point d'entree : aucune ne l'execute, et leur seule preuve etait un controle de texte sur sa definition
# ($nativeSource.Contains('/requestodj')), qui laisse passer le retrait de /localos, la suppression du garde
# d'injection de la ligne de commande, la publication des sorties natives ou l'abandon du delai : aucune des
# trente-deux mutations du harnais existant ne frappe cette fonction.
# Cette suite juge les gardes sur l'arbre syntaxique du moteur scelle, parse par le vrai analyseur PowerShell, et
# non plus par des sous-chaines : les quatre switches et leur ordre, la citation des deux chemins, l'ordre relatif
# des gardes et du lancement, l'absence de coquille, la redirection des deux sorties natives, le delai qui tue, le
# code rendu et l'unique lancement sont lus dans les noeuds. Les cas joues pour de vrai sont ceux que Spark peut
# jouer : Assert-PestoPlainPath executee sur les formes de chemin que le transport lui remet, et l'echec bruyant
# du transport reel sur une plateforme sans racine Windows. Le contrat effectif de djoin.exe ne s'observe que sur
# la plateforme cible : le rejouer ici contre un faux binaire n'attesterait que du faux binaire.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad/Pesto.Engine.Runtime.ps1'
. $runtime
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}}
function RejectWith([scriptblock]$body,[string]$Needle){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)}
# Le predicat passe a FindAll ne capture aucune variable : GetNewClosure rendait le type compare inutilisable, ce
# qui faisait passer chaque recherche de noeud a zero et transformait un moteur tronque en succes.
function AllNodes($Node){return @($Node.FindAll({param($n)$true},$true))}
function OfKind($Node,[string]$Kind){return @(AllNodes $Node|Where-Object{$_.GetType().Name -eq $Kind})}
function MemberInvokes($Node,[string]$Name){return @(OfKind $Node 'InvokeMemberExpressionAst'|Where-Object{$_.Member.Value -eq $Name})}
function MemberAssignments($Node){return @(OfKind $Node 'AssignmentStatementAst'|Where-Object{$_.Left.GetType().Name -eq 'MemberExpressionAst'})}
function VariableAssignments($Node,[string]$Name){return @(OfKind $Node 'AssignmentStatementAst'|Where-Object{$_.Left.GetType().Name -eq 'VariableExpressionAst' -and $_.Left.VariablePath.UserPath -eq $Name})}
function CommandAsts($Node){return @(OfKind $Node 'CommandAst')}
function CommandNames($Node){return @(CommandAsts $Node|ForEach-Object{$_.GetCommandName()})}
function StringLiterals($Node){return @(OfKind $Node 'StringConstantExpressionAst'|Sort-Object{$_.Extent.StartOffset}|ForEach-Object{$_.Value})}
function CommandArguments($Node){$name=$Node.GetCommandName();return @(StringLiterals $Node|Where-Object{$_ -ne $name})}
function VariableUses($Node,[string]$Name){return @(OfKind $Node 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq $Name})}
function LoopCount($Node){
    $n=0
    foreach($kind in @('WhileStatementAst','ForStatementAst','ForEachStatementAst','DoWhileStatementAst','DoUntilStatementAst')){$n+=(OfKind $Node $kind).Count}
    return $n
}
function MemberAssignment($Node,[string]$Member){
    $found=@(MemberAssignments $Node|Where-Object{$_.Left.Member.Value -eq $Member})
    Equal $found.Count 1 ("le transport ne regle pas une seule fois "+$Member)
    return $found[0]
}
# Le moteur scelle est parse une seule fois : c'est l'analyseur de PowerShell qui juge, pas une comparaison de
# chaines. Un moteur qui ne se parse pas arrete la suite, faute de quoi chaque cas echouerait sur une absence de
# noeud sans que personne sache que le fichier est devenu illisible.
$parseTokens=$null;$parseErrors=$null
$script:tree=[System.Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count){throw ('le moteur scelle ne se parse pas : '+$parseErrors[0].Message)}
$found=@(AllNodes $script:tree|Where-Object{$_.GetType().Name -eq 'FunctionDefinitionAst' -and $_.Name -eq 'Invoke-PestoOfflineNative'})
if($found.Count -ne 1){throw ('le transport natif hors connexion n est pas trouve exactement une fois dans le moteur scelle : '+$found.Count)}
$script:fn=$found[0]
$root=Join-Path $PSScriptRoot ('pesto-offline109ast-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
# ---------- A. Le contrat djoin, lu dans l'arbre syntaxique scelle ----------
Case 'The sealed transport builds the four djoin switches in the contract order' {
    $arguments=MemberAssignment $script:fn 'Arguments'
    $literals=@(StringLiterals $arguments.Right)
    Equal (@($literals) -join '<blob><root>') '/requestodj /loadfile "<blob><root>" /windowspath "<blob><root>" /localos' "la ligne de commande remise a djoin n'est plus exactement les quatre switches du contrat, dans l'ordre"
}
Case 'The blob and the system root are handed to djoin quoted' {
    $arguments=MemberAssignment $script:fn 'Arguments'
    $literals=@(StringLiterals $arguments.Right)
    Equal $literals.Count 3 "la ligne d'arguments n'est plus coupee par exactement les deux chemins cites"
    Assert ($literals[0].EndsWith('"')) 'le chemin du blob clair est remis a djoin sans citation ouvrante : un chemin a espaces se decouperait en plusieurs arguments'
    Assert ($literals[1].StartsWith('"') -and $literals[1].EndsWith('"')) 'la racine systeme est remise a djoin sans etre citee des deux cotes'
    Assert ($literals[2].StartsWith('"')) 'la racine systeme est remise a djoin sans citation fermante'
}
Case 'The native tool is the djoin of the system root, never a bare name' {
    $exeAssignments=@(VariableAssignments $script:fn 'exe')
    Equal $exeAssignments.Count 1 "le nom de l'executable natif n'est plus etabli une seule fois"
    $join=@(CommandAsts $exeAssignments[0].Right|Where-Object{$_.GetCommandName() -eq 'Join-Path'})
    Equal $join.Count 1 "l'executable natif n'est plus construit a partir de la racine systeme"
    Equal (@(CommandArguments $join[0])[0]) 'System32\djoin.exe' "le binaire lance n'est plus le djoin de System32"
    $fileName=MemberAssignment $script:fn 'FileName'
    Equal (@(VariableUses $fileName.Right 'exe').Count) 1 "le nom du binaire n'est plus la variable tenue par la racine systeme"
    Assert ($exeAssignments[0].Extent.StartOffset -lt $fileName.Extent.StartOffset) "le nom du binaire n'est pas derive de la racine systeme avant d'etre affecte"
}
Case 'No machine identity or credential ever reaches the djoin line' {
    $literals=@(StringLiterals $script:fn)
    foreach($needle in @('/machine','/user','/ou','/domain','/netbios','/password','netdom')){
        foreach($literal in $literals){Assert (-not $literal.ToLowerInvariant().Contains($needle)) ('le transport natif vehicule ['+$needle+'] en ligne de commande : une identite ou un secret sortirait du magasin protege')}
    }
    Assert (-not ($script:fn.Extent.Text -match '(?i)(\s|^)/p(\s|$)|(\s|^)/rp(\s|$)')) 'le transport natif vehicule un mot de passe en ligne de commande'
}
Case 'The blob path is link-checked before any process object exists' {
    $guards=@(CommandAsts $script:fn|Where-Object{$_.GetCommandName() -eq 'Assert-PestoPlainPath'})
    Equal $guards.Count 2 'le transport ne relit plus les deux chemins critiques avant de lancer'
    $launch=@(MemberInvokes $script:fn 'new')
    Assert ($launch.Count -ge 1) 'le transport ne cree plus le processus natif : les gardes de chemin n ont plus de sens'
    $onBlob=@($guards|Where-Object{@(VariableUses $_ 'Path').Count -eq 1 -and @(VariableUses $_ 'exe').Count -eq 0})
    Equal $onBlob.Count 1 'le chemin du blob clair a cesse detre relit avant le lancement'
    Assert ($onBlob[0].Extent.StartOffset -lt $launch[0].Extent.StartOffset) 'le blob clair est relit apres la creation du processus : le lien serait suivi avant le refus'
}
Case 'The native executable path is link-checked before any process object exists' {
    $guards=@(CommandAsts $script:fn|Where-Object{$_.GetCommandName() -eq 'Assert-PestoPlainPath'})
    $launch=@(MemberInvokes $script:fn 'new')
    $onExe=@($guards|Where-Object{@(VariableUses $_ 'exe').Count -eq 1})
    Equal $onExe.Count 1 "le chemin de l'executable natif n'est plus relit avant le lancement"
    Assert ($onExe[0].Extent.StartOffset -lt $launch[0].Extent.StartOffset) "le chemin de l'executable natif est relit apres la creation du processus"
}
Case 'The command-line injection guard precedes the argument line' {
    $guards=@(OfKind $script:fn 'BinaryExpressionAst'|Where-Object{$_.Operator -eq 'Imatch' -and (@(StringLiterals $_) -contains '["\r\n]')})
    Equal $guards.Count 2 "le transport ne refuse plus la citation et le retour a la ligne, dans le chemin du blob et dans la racine systeme"
    $arguments=(MemberAssignment $script:fn 'Arguments').Extent.StartOffset
    foreach($guard in $guards){Assert ($guard.Extent.StartOffset -lt $arguments) "une garde d'injection de la ligne de commande s'est deplacee apres sa construction"}
}
Case 'The native tool is launched without a shell and without a window' {
    Equal (MemberAssignment $script:fn 'UseShellExecute').Right.Extent.Text '$false' 'le transport natif relance la coquille : la ligne de commande serait reparseee'
    Equal (MemberAssignment $script:fn 'CreateNoWindow').Right.Extent.Text '$true' 'le transport natif nest plus lance sans fenetre'
}
Case 'Both native streams are redirected rather than inherited' {
    Equal (MemberAssignment $script:fn 'RedirectStandardOutput').Right.Extent.Text '$true' 'la sortie native est heritee au lieu d etre captee : elle pourrait porter des donnees sensibles'
    Equal (MemberAssignment $script:fn 'RedirectStandardError').Right.Extent.Text '$true' "l'erreur native est heritee au lieu d etre captee"
}
Case 'The redirected native output is never published to the caller' {
    $reads=@(MemberInvokes $script:fn 'ReadToEndAsync')
    Equal $reads.Count 2 'les deux sorties natives ne sont plus drainees : un tampon plein bloquerait djoin'
    foreach($forbidden in @('Write-Host','Write-Output','Out-File','Add-Content','Set-Content')){
        Assert (-not ((CommandNames $script:fn) -contains $forbidden)) ('le transport publie les sorties natives via '+$forbidden)
    }
    foreach($name in @('stdout','stderr')){
        Equal (@(VariableUses $script:fn $name).Count) 1 ('la sortie native ['+$name+'] est relue ailleurs que dans son affectation : elle pourrait atteindre l appeler')
    }
}
Case 'The native call is bounded by a deadline that kills the process' {
    $wait=@(MemberInvokes $script:fn 'WaitForExit')
    Equal $wait.Count 1 'le transport ne borne plus l appel natif par un delai'
    Equal $wait[0].Arguments.Count 1 'le delai natif ne porte plus de valeur : une demande bloquee ne serait jamais tranchee'
    $value=$wait[0].Arguments[0]
    Equal $value.GetType().Name 'ConstantExpressionAst' 'le delai natif nest plus une duree constante'
    Assert ([int]$value.Value -ge 1000) ('le delai natif est ramene a '+[string]$value.Value+' ms : un djoin legitime serait tue avant d ecrire')
    Equal (@(MemberInvokes $script:fn 'Kill').Count) 1 'au dela du delai, le processus natif nest plus tue : il continuerait d ecrire le blob clair'
    $messages=@(OfKind $script:fn 'ThrowStatementAst'|ForEach-Object{@(StringLiterals $_)[0]})
    Equal (@($messages|Where-Object{$null -ne $_ -and $_.Contains('aucun rejeu')}).Count) 1 "le depassement du delai n'est plus signale comme incertain et sans rejeu"
}
Case 'The transport returns the exit code as an integer, never the native output' {
    $returns=@(OfKind $script:fn 'ReturnStatementAst')
    Equal $returns.Count 1 'le transport ne rend plus un seul resultat'
    $convert=@(OfKind $returns[0] 'ConvertExpressionAst')
    Equal $convert.Count 1 'le resultat natif nest plus converti en entier'
    Equal $convert[0].Type.Extent.Text '[int]' 'le resultat natif nest plus converti en entier'
    Equal (@(OfKind $convert[0] 'MemberExpressionAst'|Where-Object{$_.Member.Value -eq 'ExitCode'}).Count) 1 "ce n'est plus le code de sortie du processus qui est rendu"
}
Case 'The native process is always disposed' {
    Equal (@(MemberInvokes $script:fn 'Dispose').Count) 1 'le processus natif nest plus libere'
    $try=@(OfKind $script:fn 'TryStatementAst'|Where-Object{$null -ne $_.Finally})
    Equal $try.Count 1 'le transport ne protge plus son appel natif par un bloc finally'
    Equal (@(MemberInvokes $try[0].Finally 'Dispose').Count) 1 'la liberation du processus natif est sortie du finally'
}
Case 'The offline transport never calls the online join or writes the blob' {
    $names=@(CommandNames $script:fn)
    foreach($forbidden in @('Add-Computer','Restart-Computer','Invoke-PestoUnattendedJoin','Invoke-PestoOfflineApply','Invoke-PestoProcess','Remove-Item','Set-Content','Add-Content','Out-File','Copy-Item','Move-Item','New-Item')){
        Assert (-not ($names -contains $forbidden)) ('le transport hors connexion rappelle '+$forbidden+' : la jonction en ligne, le redemarrage ou l ecriture du blob sortent de leur propre parcours')
    }
    # Un acces a une propriete et un appel de methode statique sont deux noeuds distincts de l'arbre : ne juger
    # que l'un des deux laisserait passer [IO.File]::WriteAllBytes($Path,...) dans le transport.
    $names=@('WriteAllText','WriteAllBytes','AppendAllText','AppendAllBytes','Create','OpenWrite')
    $writes=@(OfKind $script:fn 'MemberExpressionAst'|Where-Object{$_.Member.Value -in $names})
    $staticWrites=@(OfKind $script:fn 'InvokeMemberExpressionAst'|Where-Object{$_.Member.Value -in $names})
    Equal ($writes.Count+$staticWrites.Count) 0 'le transport ecrit lui-meme un fichier : le blob clair ne doit exister que sous la garde du magasin protege'
}
Case 'The native call is launched exactly once per transport' {
    Equal (@(MemberInvokes $script:fn 'Start').Count) 1 "l'appel natif n'est plus lance exactement une fois"
    Equal (LoopCount $script:fn) 0 "l'appel natif est encadre par une boucle : la demande de jonction partirait deux fois"
}
Case 'The transport takes only the blob path and no credential parameter' {
    $params=@(OfKind $script:fn 'ParameterAst')
    Equal $params.Count 1 'le transport natif accepte plus de parametres que le seul chemin du blob'
    Equal $params[0].Name.VariablePath.UserPath 'Path' "le parametre du transport natif n'est plus le chemin du blob"
}
# ---------- B. La garde de chemin, jouee pour de vrai sur les formes que le transport lui remet ----------
$plainBlob=Join-Path $root 'a b.odj.tmp'
[IO.File]::WriteAllBytes($plainBlob,[Text.Encoding]::UTF8.GetBytes('ODJ-CLAIR-FIXTURE'))
Case 'A blob path that traverses a link is really refused by the product guard' {
    $outside=Join-Path $root 'outside';[void][IO.Directory]::CreateDirectory($outside)
    $real=Join-Path $outside 'reel.odj.tmp';[IO.File]::WriteAllBytes($real,[Text.Encoding]::UTF8.GetBytes('ODJ-CLAIR-FIXTURE'))
    $link=Join-Path $root ('lien-blob-'+[Guid]::NewGuid().ToString('N')+'.odj.tmp')
    [void](New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop)
    RejectWith {Assert-PestoPlainPath $link} 'Un chemin critique traverse un lien ou une jonction.'
}
Case 'A system root whose System32 is a link is really refused by the product guard' {
    $reel=Join-Path $root 'system32-reel';[void][IO.Directory]::CreateDirectory($reel)
    [IO.File]::WriteAllBytes((Join-Path $reel 'djoin.exe'),[Text.Encoding]::UTF8.GetBytes('fixture-djoin-marker'))
    $sac=Join-Path $root ('racine-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($sac)
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $sac 'System32') -Target $reel -ErrorAction Stop)
    RejectWith {Assert-PestoPlainPath (Join-Path $sac 'System32\djoin.exe')} 'Un chemin critique traverse un lien ou une jonction.'
}
Case 'Plain blob and executable paths really pass the product guard' {
    [void](Assert-PestoPlainPath $plainBlob)
    [void](Assert-PestoPlainPath 'System32\djoin.exe')
}
# ---------- C. Ce que Spark peut vraiment executer : l'echec du transport reel ----------
Case 'The real transport fails loudly rather than reporting a joined machine' {
    $returned=$null;$threw=$false
    try{$returned=Invoke-PestoOfflineNative -Path $plainBlob}catch{$threw=$true}
    Assert $threw ('le transport natif a rendu ['+[string]$returned+'] sur une plateforme sans racine Windows : la demande passerait pour une jonction reussie')
    Assert ($null -eq $returned) 'le transport natif a rendu une valeur tout en echouant'
}
}finally{try{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop}catch{}}
Assert (-not [IO.Directory]::Exists($root)) 'le sac de la suite subsiste : les fixtures claires doivent etre detruites'
if($ReportPath){[IO.File]::WriteAllText($ReportPath,(@{Suite='OfflineJoin109Native';Passed=$script:passed;Failed=$script:failed}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
Write-Output ('OfflineJoin109Native: '+$script:passed+' passed, '+$script:failed+' failed. Sealed syntax tree of the secret hand-off judged by the real PowerShell parser, product path guards really executed; no djoin, no Windows, no VM.')
if($script:failed -gt 0){exit 1}
