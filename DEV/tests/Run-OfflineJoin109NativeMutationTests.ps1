#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109NativeTests.ps1 (remise du blob secret a djoin.exe, point 109) :
# chaque mutation d'une copie hors sac du moteur scelle doit faire echouer exactement le controle de la garde visee
# (sortie non nulle ET message du cas attendu) et la copie temoin doit passer. Sont frappees ici les gardes que
# ni les trente-deux mutations du harnais d'entree ni aucune des deux suites existantes ne frappaient : les quatre
# switches djoin et leur ordre, la citation des deux chemins, le binaire resolve sous la racine systeme, les deux
# relectures de chemin avant creation du processus, la garde d'injection de la ligne de commande, l'absence de
# coquille et de fenetre, la redirection des deux sorties natives, la non-publication de ces sorties, le delai qui
# tue le processus et son message « aucun rejeu », le code de sortie rendu plutot que la sortie, la liberation du
# processus, l'absence de rappel de la jonction en ligne et d'ecriture du blob, l'unicite du lancement, et le seul
# parametre du transport. La copie se limite au moteur requis par la suite et a la suite elle-meme : aucun
# cfg.json operationnel n'est lu, aucun djoin, aucune VM, aucun appel reseau.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109NativeTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109NativeTests.ps1'
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutNative109-'+[Guid]::NewGuid().ToString('N'))
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
            Check ($flat -match 'OfflineJoin109Native: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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
# Les litteraux de la ligne djoin sont ecrits en here-string simple pour que $Path et $windows restent du texte
# literal : une chaine double les interpolerait et le motif ne correspondrait plus jamais au moteur scelle.
$argFull=@'
$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos'
'@
$argFull=$argFull.TrimEnd()
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
$waitLine=@'
if(-not $process.WaitForExit(120000)){try{$process.Kill()}catch{};throw 'Delai djoin depasse : resultat incertain, aucun rejeu.'}
'@
$waitLine=$waitLine.TrimEnd()
$waitNoTimeout=@'
if(-not $process.WaitForExit()){try{$process.Kill()}catch{};throw 'Delai djoin depasse : resultat incertain, aucun rejeu.'}
'@
$waitNoTimeout=$waitNoTimeout.TrimEnd()
$waitTiny=@'
if(-not $process.WaitForExit(50)){try{$process.Kill()}catch{};throw 'Delai djoin depasse : resultat incertain, aucun rejeu.'}
'@
$waitTiny=$waitTiny.TrimEnd()
$waitNoKill=@'
if(-not $process.WaitForExit(120000)){try{}catch{};throw 'Delai djoin depasse : resultat incertain, aucun rejeu.'}
'@
$waitNoKill=$waitNoKill.TrimEnd()
$waitPlainMessage=@'
if(-not $process.WaitForExit(120000)){try{$process.Kill()}catch{};throw 'Delai djoin depasse.'}
'@
$waitPlainMessage=$waitPlainMessage.TrimEnd()
$returnLine=@'
        return [int]$process.ExitCode{NL}    }finally{$process.Dispose()}
'@
$returnLine=$returnLine.TrimEnd()
$returnNativeOutput=@'
        return $stdout.Result{NL}    }finally{$process.Dispose()}
'@
$returnNativeOutput=$returnNativeOutput.TrimEnd()
$returnPublished=@'
        Write-Host $stdout.Result{NL}        return [int]$process.ExitCode{NL}    }finally{$process.Dispose()}
'@
$returnPublished=$returnPublished.TrimEnd()
$returnEmptyFinally=@'
        return [int]$process.ExitCode{NL}    }finally{}
'@
$returnEmptyFinally=$returnEmptyFinally.TrimEnd()
$returnOnlineJoin=@'
        Add-Computer|Out-Null;return [int]$process.ExitCode{NL}    }finally{$process.Dispose()}
'@
$returnOnlineJoin=$returnOnlineJoin.TrimEnd()
$returnBlobWritten=@'
        [IO.File]::WriteAllBytes($Path,[byte[]]@());return [int]$process.ExitCode{NL}    }finally{$process.Dispose()}
'@
$returnBlobWritten=$returnBlobWritten.TrimEnd()
$joinExe=@'
Join-Path $windows 'System32\djoin.exe'
'@
$joinExe=$joinExe.TrimEnd()
$joinExeBare=@'
Join-Path $windows 'djoin.exe'
'@
$joinExeBare=$joinExeBare.TrimEnd()
$startLine=@'
if(-not $process.Start()){throw 'Lancement djoin impossible.'}
'@
$startLine=$startLine.TrimEnd()
$startLoop=@'
while(-not $process.Start()){throw 'Lancement djoin impossible.'}
'@
$startLoop=$startLoop.TrimEnd()
# Les paires motivee/remplacement sont construites en mode expression : ecrites dans l'appel, la concatenation
# par + serait parse en mode argument et les deux motifs s'agglutineraient en un seul.
$pairNativeOutput=@(($waitLine+'{NL}'+$returnLine),($waitLine+'{NL}'+$returnNativeOutput))
$pairOutputPublished=@(($waitLine+'{NL}'+$returnLine),($waitLine+'{NL}'+$returnPublished))

Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'djoin /localos switch dropped' -ExpectedFailure @('la ligne de commande remise a djoin n''est plus exactement les quatre switches') -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argNoLocalos)}
Invoke-Scenario -Label 'Clear blob path handed to djoin unquoted' -ExpectedFailure @('le chemin du blob clair est remis a djoin sans citation ouvrante',"la ligne de commande remise a djoin n'est plus exactement les quatre switches") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argBlobUnquoted)}
Invoke-Scenario -Label 'System root handed to djoin unquoted' -ExpectedFailure @('la racine systeme est remise a djoin sans etre citee des deux cotes',"la ligne de commande remise a djoin n'est plus exactement les quatre switches") -Mutation {param($t,$s) Mutate-Runtime $t @($argFull,$argRootUnquoted)}
Invoke-Scenario -Label 'Native tool no longer resolved under the system root' -ExpectedFailure @("le binaire lance n'est plus le djoin de System32") -Mutation {param($t,$s) Mutate-Runtime $t @($joinExe,$joinExeBare)}
Invoke-Scenario -Label 'Blob path no longer link-checked' -ExpectedFailure @('le transport ne relit plus les deux chemins critiques avant de lancer') -Mutation {param($t,$s) Mutate-Runtime $t @('Assert-PestoPlainPath $Path;Assert-PestoPlainPath $exe','Assert-PestoPlainPath $exe')}
Invoke-Scenario -Label 'Native executable path no longer link-checked' -ExpectedFailure @('le transport ne relit plus les deux chemins critiques avant de lancer') -Mutation {param($t,$s) Mutate-Runtime $t @('Assert-PestoPlainPath $Path;Assert-PestoPlainPath $exe','Assert-PestoPlainPath $Path')}
Invoke-Scenario -Label 'Command-line injection guard neutered' -ExpectedFailure @('le transport ne refuse plus la citation et le retour a la ligne') -Mutation {param($t,$s) Mutate-Runtime $t @('if($Path -match ''["\r\n]'' -or $windows -match ''["\r\n]''){throw ''Chemin natif invalide.''}','if($false){throw ''Chemin natif invalide.''}')}
Invoke-Scenario -Label 'Native tool launched through a shell' -ExpectedFailure @('le transport natif relance la coquille') -Mutation {param($t,$s) Mutate-Runtime $t @('$info.UseShellExecute=$false','$info.UseShellExecute=$true')}
Invoke-Scenario -Label 'Native tool launched with a window' -ExpectedFailure @('le transport natif nest plus lance sans fenetre') -Mutation {param($t,$s) Mutate-Runtime $t @('$info.CreateNoWindow=$true','$info.CreateNoWindow=$false')}
Invoke-Scenario -Label 'Native stdout inherited instead of captured' -ExpectedFailure @('la sortie native est heritee au lieu d etre captee') -Mutation {param($t,$s) Mutate-Runtime $t @('$info.RedirectStandardOutput=$true','$info.RedirectStandardOutput=$false')}
Invoke-Scenario -Label 'Native stderr inherited instead of captured' -ExpectedFailure @("l'erreur native est heritee au lieu d etre captee") -Mutation {param($t,$s) Mutate-Runtime $t @('$info.RedirectStandardError=$true','$info.RedirectStandardError=$false')}
Invoke-Scenario -Label 'Native output returned instead of the exit code' -ExpectedFailure @('le resultat natif nest plus converti en entier','est relue ailleurs que dans son affectation') -Mutation {param($t,$s) Mutate-Runtime $t $pairNativeOutput}
Invoke-Scenario -Label 'Native output published to the caller' -ExpectedFailure @('le transport publie les sorties natives via Write-Host') -Mutation {param($t,$s) Mutate-Runtime $t $pairOutputPublished}
Invoke-Scenario -Label 'Native call no longer bounded by a deadline' -ExpectedFailure @('le delai natif ne porte plus de valeur') -Mutation {param($t,$s) Mutate-Runtime $t @($waitLine,$waitNoTimeout)}
Invoke-Scenario -Label 'Deadline shortened below any real djoin run' -ExpectedFailure @('un djoin legitime serait tue avant d ecrire') -Mutation {param($t,$s) Mutate-Runtime $t @($waitLine,$waitTiny)}
Invoke-Scenario -Label 'Hung native process no longer killed' -ExpectedFailure @('le processus natif nest plus tue') -Mutation {param($t,$s) Mutate-Runtime $t @($waitLine,$waitNoKill)}
Invoke-Scenario -Label 'Deadline overrun no longer reported uncertain' -ExpectedFailure @("le depassement du delai n'est plus signale comme incertain et sans rejeu") -Mutation {param($t,$s) Mutate-Runtime $t @($waitLine,$waitPlainMessage)}
Invoke-Scenario -Label 'Native process no longer disposed' -ExpectedFailure @('le processus natif nest plus libere') -Mutation {param($t,$s) Mutate-Runtime $t @($returnLine,$returnEmptyFinally)}
Invoke-Scenario -Label 'Online join recalled by the offline transport' -ExpectedFailure @('le transport hors connexion rappelle Add-Computer') -Mutation {param($t,$s) Mutate-Runtime $t @($returnLine,$returnOnlineJoin)}
Invoke-Scenario -Label 'Transport writes the clear blob itself' -ExpectedFailure @('le transport ecrit lui-meme un fichier') -Mutation {param($t,$s) Mutate-Runtime $t @($returnLine,$returnBlobWritten)}
Invoke-Scenario -Label 'Native call wrapped in a retry loop' -ExpectedFailure @("l'appel natif est encadre par une boucle") -Mutation {param($t,$s) Mutate-Runtime $t @($startLine,$startLoop)}
Invoke-Scenario -Label 'Transport takes a credential parameter' -ExpectedFailure @('le transport natif accepte plus de parametres que le seul chemin du blob') -Mutation {param($t,$s) Mutate-Runtime $t @('function Invoke-PestoOfflineNative {{NL}    param([string]$Path)','function Invoke-PestoOfflineNative {{NL}    param([string]$Path,[string]$Password)')}
Write-Output ('OfflineJoin109NativeMutations : '+$n+'/'+$n+' PASS')
