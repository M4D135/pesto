#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109NativeLineTests.ps1 (la ligne remise a djoin.exe par le transport
# du blob secret, point 109). Chaque mutation d'une copie hors sac du moteur scelle doit faire echouer exactement le
# controle de la garde visee (sortie non nulle ET message du cas attendu) et la copie temoin doit passer.
# Le harnais existe deja pour le transport (Run-OfflineJoin109NativeMutationTests.ps1, 94/94) et ses vingt-deux
# mutations ne frappaient aucune des cinq gardes nouvelles : un sondage montre que permuter les deux operands de la
# concatenation, remplacer le blob par le chemin du binaire, deplacer la garde d'injection apres la ligne, ou
# remplacer la concatenation par une chaine interpolable laisse Run-OfflineJoin109NativeTests.ps1 a 20/20. Sont
# frappees ici l'aiguillage des deux chemins sur leurs switchs, l'unicite de chaque interpolation, la forme de la
# concatenation, la remise a l'objet de lancement, l'ordre de la garde, et les quatre refus de la garde d'injection
# joues sur des chemins reellement porteurs de citation, retour chariot et saut de ligne.
# La copie se limite au moteur requis par la suite et a la suite elle-meme : aucun cfg.json operationnel n'est lu,
# aucun djoin, aucune VM, aucun appel reseau.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109NativeLineTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109NativeLineTests.ps1'
$copiedFiles=@('wad/Pesto.Engine.Runtime.ps1')
$hostExe=(Get-Process -Id $PID).Path
$n=0
function Check($ok,$message){if(-not $ok){throw $message};$script:n++}
function Read-Utf8File{
    param([string]$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset=if($hasBom){3}else{0}
    $text=[Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset)
    $nl=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
    return [pscustomobject]@{Text=$text;HasBom=$hasBom;Newline=$nl}
}
function Write-Utf8File{
    param([string]$Path,[pscustomobject]$Doc)
    [IO.File]::WriteAllText($Path,$Doc.Text,[Text.UTF8Encoding]::new($Doc.HasBom))
}
function Replace-Once{
    param([pscustomobject]$Doc,[string]$Literal,[string]$Replacement)
    $found=[regex]::Matches($Doc.Text,[regex]::Escape($Literal))
    Check ($found.Count -eq 1) ('Mutation pattern must match exactly once: '+$Literal)
    $m=$found[0]
    $Doc.Text=$Doc.Text.Substring(0,$m.Index)+$Replacement+$Doc.Text.Substring($m.Index+$m.Length)
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutNativeLine109-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try{
        foreach($f in $copiedFiles){
            $destination=Join-Path $temp $f
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            Copy-Item -LiteralPath (Join-Path $root $f) -Destination $destination
        }
        $suiteCopy=Join-Path $temp $suiteRelative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($suiteCopy))
        Copy-Item -LiteralPath $suiteSource -Destination $suiteCopy
        $tree=@(Get-ChildItem -LiteralPath $temp -Recurse -File|ForEach-Object{$_.FullName.Substring($temp.Length+1).Replace('\','/')})
        Check (@(Compare-Object -ReferenceObject ($copiedFiles+$suiteRelative) -DifferenceObject $tree).Count -eq 0) ($Label+': the copy drifted from the whitelist')
        if($Mutation){& $Mutation $temp $suiteCopy}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        # L'enfant s'etablit dans la copie : un mutant qui ecrirait un fichier le laisserait dans le sac detruit.
        Push-Location $temp
        try{
            $output=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $suiteCopy 2>&1|ForEach-Object{[string]$_})
            $code=$LASTEXITCODE
        }finally{Pop-Location}
        $ErrorActionPreference=$previous
        $text=$output -join "`n"
        $flat=(((($text)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'OfflineJoin109NativeLine: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}
function Mutate-Runtime{
    param([string]$Temp,[string[]]$Pairs)
    $path=Join-Path $Temp 'wad/Pesto.Engine.Runtime.ps1'
    $doc=Read-Utf8File -Path $path
    for($i=0;$i -lt $Pairs.Count;$i+=2){Replace-Once -Doc $doc -Literal ($Pairs[$i] -replace '\{NL\}',$doc.Newline) -Replacement ($Pairs[$i+1] -replace '\{NL\}',$doc.Newline)}
    Write-Utf8File -Path $path -Doc $doc
}
# Les litteraux sont ecrits en here-string simple pour que $Path, $windows et les backticks restent du texte
# literal : une chaine double les interpolerait et le motif ne correspondrait plus jamais au moteur scelle.
$argFull=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$argFull=$argFull.TrimEnd()
$argSwap=@'
$info.Arguments='/requestodj /loadfile "'+$windows+'" /windowspath "'+$Path+'" /localos'
'@
$argSwap=$argSwap.TrimEnd()
$argBlobIsExe=@'
$info.Arguments='/requestodj /loadfile "'+$exe+'" /windowspath "'+$windows+'" /localos'
'@
$argBlobIsExe=$argBlobIsExe.TrimEnd()
$argRootIsPath=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$Path+'" /localos'
'@
$argRootIsPath=$argRootIsPath.TrimEnd()
$argPathTwice=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+$Path+'" /localos'
'@
$argPathTwice=$argPathTwice.TrimEnd()
$argExtraSwitch=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos /nonew'
'@
$argExtraSwitch=$argExtraSwitch.TrimEnd()
$argNoLocalos=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'"'
'@
$argNoLocalos=$argNoLocalos.TrimEnd()
$argBlobUnquoted=@'
$info.Arguments='/requestodj /loadfile '+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$argBlobUnquoted=$argBlobUnquoted.TrimEnd()
$argRootUnquoted=@'
$info.Arguments='/requestodj /loadfile "'+$Path+' /windowspath '+$windows+'" /localos'
'@
$argRootUnquoted=$argRootUnquoted.TrimEnd()
$argLoadRenamed=@'
$info.Arguments='/requestodj /load "'+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$argLoadRenamed=$argLoadRenamed.TrimEnd()
$argOrderSwapped=@'
$info.Arguments='/requestodj /windowspath "'+$windows+'" /loadfile "'+$Path+'" /localos'
'@
$argOrderSwapped=$argOrderSwapped.TrimEnd()
$argExpandable=@'
$info.Arguments="/requestodj /loadfile `"$Path`" /windowspath `"$windows`" /localos"
'@
$argExpandable=$argExpandable.TrimEnd()
$argLocalAssign=@'
$argLine='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$argLocalAssign=$argLocalAssign.TrimEnd()
$guardLine=@'
    if($Path -match '["\r\n]' -or $windows -match '["\r\n]'){throw 'Chemin natif invalide.'}
'@
$guardLine=$guardLine.TrimEnd()
$infoLine=@'
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$infoLine=$infoLine.TrimEnd()
$guardFalse=@'
    if($false){throw 'Chemin natif invalide.'}
'@
$guardFalse=$guardFalse.TrimEnd()
$guardOnlyBlob=@'
    if($Path -match '["\r\n]'){throw 'Chemin natif invalide.'}
'@
$guardOnlyBlob=$guardOnlyBlob.TrimEnd()
$guardOnlyRoot=@'
    if($windows -match '["\r\n]'){throw 'Chemin natif invalide.'}
'@
$guardOnlyRoot=$guardOnlyRoot.TrimEnd()
$guardNoNewlineBlob=@'
    if($Path -match '["]' -or $windows -match '["\r\n]'){throw 'Chemin natif invalide.'}
'@
$guardNoNewlineBlob=$guardNoNewlineBlob.TrimEnd()
$guardNoQuoteRoot=@'
    if($Path -match '["\r\n]' -or $windows -match '[\r\n]'){throw 'Chemin natif invalide.'}
'@
$guardNoQuoteRoot=$guardNoQuoteRoot.TrimEnd()
Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'Blob and system root swapped between /loadfile and /windowspath' -ExpectedFailure @("le blob clair n'est plus l'operand branche sur /loadfile") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argSwap)}
Invoke-Scenario -Label 'Binary path handed to djoin instead of the clear blob' -ExpectedFailure @("le blob clair n'est plus l'operand branche sur /loadfile") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argBlobIsExe)}
Invoke-Scenario -Label 'Blob handed to /windowspath twice instead of the system root' -ExpectedFailure @("la racine systeme n'est plus l'operand branche sur /windowspath") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argRootIsPath)}
Invoke-Scenario -Label 'Blob interpolated twice into the djoin line' -ExpectedFailure @('le blob clair n est plus interpolate exactement une fois dans la ligne djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argPathTwice)}
Invoke-Scenario -Label 'Fifth switch appended to the djoin contract' -ExpectedFailure @('la ligne calculee ne decoupe plus exactement les six champs du contrat djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argExtraSwitch)}
Invoke-Scenario -Label 'djoin /localos switch dropped' -ExpectedFailure @('la ligne calculee ne decoupe plus exactement les six champs du contrat djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argNoLocalos)}
Invoke-Scenario -Label 'Clear blob path handed to djoin unquoted' -ExpectedFailure @('le blob clair ne parait plus cite sous /loadfile') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argBlobUnquoted)}
Invoke-Scenario -Label 'System root handed to djoin unquoted' -ExpectedFailure @('la racine systeme ne parait plus citee sous /windowspath') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argRootUnquoted)}
Invoke-Scenario -Label 'djoin /loadfile switch renamed' -ExpectedFailure @("le premier chemin cite n'est plus celui remis a /loadfile") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argLoadRenamed)}
Invoke-Scenario -Label 'djoin switches emitted in the wrong order' -ExpectedFailure @("la ligne reellement calculee par le produit n'est pas exactement le contrat djoin") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argOrderSwapped)}
Invoke-Scenario -Label 'djoin line built by an interpolable string instead of concatenation' -ExpectedFailure @('la ligne djoin contient un noeud inattendu') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argExpandable)}
Invoke-Scenario -Label 'djoin line no longer handed to the process start info' -ExpectedFailure @('la ligne d arguments du processus natif n est pas affectee') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argLocalAssign)}
Invoke-Scenario -Label 'Injection guard neutered' -ExpectedFailure @('la garde d injection de la ligne de commande n est pas trouvee') -Mutation {param($t,$s) Mutate-Runtime $t @($guardLine,$guardFalse)}
Invoke-Scenario -Label 'Injection guard no longer reads the blob path' -ExpectedFailure @('un chemin de blob portant une citation double atteint la ligne djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($guardLine,$guardOnlyRoot)}
Invoke-Scenario -Label 'Injection guard no longer reads the system root' -ExpectedFailure @('une racine systeme portant une citation double atteint la ligne djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($guardLine,$guardOnlyBlob)}
Invoke-Scenario -Label 'Injection guard no longer refuses carriage return and line feed in the blob' -ExpectedFailure @('un chemin de blob portant un retour chariot atteint la ligne djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($guardLine,$guardNoNewlineBlob)}
Invoke-Scenario -Label 'Injection guard no longer refuses a quote in the system root' -ExpectedFailure @('une racine systeme portant une citation double atteint la ligne djoin') -Mutation {param($t,$s) Mutate-Runtime $t @($guardLine,$guardNoQuoteRoot)}
Invoke-Scenario -Label 'Injection guard moved after the djoin line is built' -ExpectedFailure @("la garde d'injection ne precede plus la construction de la ligne djoin") -Mutation {param($t,$s) Mutate-Runtime $t @(($guardLine+'{NL}'+$infoLine),($infoLine+'{NL}'+$guardLine))}
Write-Output ('OfflineJoin109NativeLineMutations : '+$n+'/'+$n+' PASS')
