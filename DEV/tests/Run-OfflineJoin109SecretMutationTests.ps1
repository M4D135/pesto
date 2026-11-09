#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109SecretTests.ps1 (la protection du blob secret de la jonction hors
# connexion, point 109). Chaque mutation d'une copie hors sac du moteur scelle doit faire echouer exactement le
# controle de la garde visee (sortie non nulle ET message du cas attendu) et la copie temoin doit passer.
# Les quatre suites qui jouent deja ce parcours remplacent toutes les deux fonctions DPAPI par un double local : un
# sondage de leurs reecritures, consigne dans la preuve, montre lesquelles elles laissent vertes. Sont frappees ici
# la portee machine des deux moities, l absence d entropie des deux cotes, l ordre des trois arguments, la methode
# appelee (dechiffrer n est pas re-proteger), le chargement de l assemblage avant l appel, la virgule qui empeche le
# tableau de se decomposer, la nature du materiel remis, le typage du parametre, l absence de toute publication, et
# les sept usages que le produit fait de la jambe a l import et a l application.
# La copie se limite au moteur requis par la suite et a la suite elle-meme : aucun cfg.json operationnel n'est lu,
# aucun DPAPI rejoue, aucun djoin, aucune VM, aucun appel reseau.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109SecretTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109SecretTests.ps1'
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
    $scenarioWatch=[Diagnostics.Stopwatch]::StartNew()
    Write-Host ('--- '+$Label)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutSecret109-'+[Guid]::NewGuid().ToString('N'))
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
        foreach($f in $copiedFiles){Assert-Parsable (Join-Path $temp $f)}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
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
            Check ($flat -match 'OfflineJoin109Secret: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force;Write-Host ('Duree mutation : '+[math]::Round($scenarioWatch.Elapsed.TotalSeconds,3)+'s')}
}
function Assert-Parsable{
    # Un mutant que l'analyseur ne lit plus n'est pas une garde tuee : c'est le harnais qui est casse.
    param([string]$Path)
    $errors=@()
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$errors)
    Check ($errors.Count -eq 0) ('le mutant est illisible par le vrai analyseur PowerShell : '+(($errors|ForEach-Object{$_.Message}) -join ' | '))
}
function Mutate-Runtime{
    param([string]$Temp,[string[]]$Pairs)
    # La virgule lie plus fort que + en PowerShell : une paire mal parenthesee devient quatre elements et un
    # faux mutant. La liste est donc verifiee, et la reecriture doit reellement changer le moteur.
    Check (($Pairs.Count % 2) -eq 0) ('la liste de reecriture ne tombe pas par paires : '+$Pairs.Count+' elements')
    $path=Join-Path $Temp 'wad/Pesto.Engine.Runtime.ps1'
    $doc=Read-Utf8File -Path $path
    $original=$doc.Text
    for($i=0;$i -lt $Pairs.Count;$i+=2){
        Check ($Pairs[$i] -ne $Pairs[$i+1]) ('la reecriture '+$i+' ne change rien : meme texte des deux cotes')
        Replace-Once -Doc $doc -Literal ($Pairs[$i] -replace '\{NL\}',$doc.Newline) -Replacement ($Pairs[$i+1] -replace '\{NL\}',$doc.Newline)
    }
    Check ($doc.Text -ne $original) 'la reecriture appliquee laisse le moteur identique'
    Write-Utf8File -Path $path -Doc $doc
}
$protectCall='ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine'
$unprotectCall='ProtectedData]::Unprotect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine'
$protectHeader='function Protect-PestoOfflineBytes {{NL}    param([byte[]]$Bytes)'
$unprotectHeader='function Unprotect-PestoOfflineBytes {{NL}    param([byte[]]$Bytes)'
$protectReturn='return ,([Security.Cryptography.ProtectedData]::Protect'
$unprotectReturn='return ,([Security.Cryptography.ProtectedData]::Unprotect'
$protectLoad='Add-Type -AssemblyName System.Security{NL}    return ,([Security.Cryptography.ProtectedData]::Protect'
$unprotectLoad='Add-Type -AssemblyName System.Security{NL}    return ,([Security.Cryptography.ProtectedData]::Unprotect'
$importCall='$encrypted=(Protect-PestoOfflineBytes $bytes)'
$applyCall='$bytes=(Unprotect-PestoOfflineBytes $secret)'
$applyPair='$secret=[Convert]::FromBase64String([IO.File]::ReadAllText($paths.Secret));$bytes=(Unprotect-PestoOfflineBytes $secret){NL}        if((Get-PestoBytesHash $bytes) -cne $Id){throw ''Blob decrypte different du plan.''}'
$applyPairSwapped='if((Get-PestoBytesHash $bytes) -cne $Id){throw ''Blob decrypte different du plan.''}{NL}        $secret=[Convert]::FromBase64String([IO.File]::ReadAllText($paths.Secret));$bytes=(Unprotect-PestoOfflineBytes $secret)'
$scope='[Security.Cryptography.DataProtectionScope]::LocalMachine'

Invoke-Scenario -Label 'Witness' -Mutation $null

Invoke-Scenario -Label 'The blob is protected for the operator instead of the machine' -ExpectedFailure @('le secret n est plus protege pour la machine exactement une fois') -Mutation {param($t,$s);Mutate-Runtime $t @($protectCall,'ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser')}
Invoke-Scenario -Label 'The blob is decrypted for the operator instead of the machine' -ExpectedFailure @('le secret n est plus dechiffre pour la machine exactement une fois') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectCall,'ProtectedData]::Unprotect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser')}
Invoke-Scenario -Label 'Protection asks DPAPI for additional entropy' -ExpectedFailure @('le deuxieme argument de la protection nest plus l entropie') -Mutation {param($t,$s);Mutate-Runtime $t @('ProtectedData]::Protect($Bytes,$null,','ProtectedData]::Protect($Bytes,[byte[]]@(1,2,3),')}
Invoke-Scenario -Label 'Deprotection asks DPAPI for additional entropy' -ExpectedFailure @('le deuxieme argument de la deprotection nest plus l entropie') -Mutation {param($t,$s);Mutate-Runtime $t @('ProtectedData]::Unprotect($Bytes,$null,','ProtectedData]::Unprotect($Bytes,[byte[]]@(1,2,3),')}
Invoke-Scenario -Label 'Deprotection reads its scope from another type name' -ExpectedFailure @('la portee de la deprotection a change de forme') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectCall,'ProtectedData]::Unprotect($Bytes,$null,[System.Security.Cryptography.DataProtectionScope]::LocalMachine')}
Invoke-Scenario -Label 'Protection entropy moved after the scope' -ExpectedFailure @('le deuxieme argument de la protection nest plus l entropie') -Mutation {param($t,$s);Mutate-Runtime $t @($protectCall, ('ProtectedData]::Protect($Bytes,'+$scope+',$null'))}
Invoke-Scenario -Label 'Deprotection entropy moved after the scope' -ExpectedFailure @('le deuxieme argument de la deprotection nest plus l entropie') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectCall, ('ProtectedData]::Unprotect($Bytes,'+$scope+',$null'))}
Invoke-Scenario -Label 'Protected array handed back without the comma' -ExpectedFailure @('le tableau protege nest plus rendu par la virgule') -Mutation {param($t,$s);Mutate-Runtime $t @($protectReturn,'return ([Security.Cryptography.ProtectedData]::Protect')}
Invoke-Scenario -Label 'Decrypted array handed back without the comma' -ExpectedFailure @('le tableau dechiffre nest plus rendu par la virgule') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectReturn,'return ([Security.Cryptography.ProtectedData]::Unprotect')}
Invoke-Scenario -Label 'Deprotection re-protects the secret instead of decrypting it' -ExpectedFailure @('nappelle plus Unprotect') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectCall,'ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine')}
Invoke-Scenario -Label 'Protection also decrypts inside itself' -ExpectedFailure @('ne comporte plus un seul appel de methode') -Mutation {param($t,$s);Mutate-Runtime $t @($protectReturn, ('[void]([Security.Cryptography.ProtectedData]::Unprotect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)){NL}    '+$protectReturn))}
Invoke-Scenario -Label 'Protection stops loading System.Security' -ExpectedFailure @('la protection ne charge plus l assemblage exactement une fois') -Mutation {param($t,$s);Mutate-Runtime $t @($protectLoad,'return ,([Security.Cryptography.ProtectedData]::Protect')}
Invoke-Scenario -Label 'Deprotection stops loading System.Security' -ExpectedFailure @('la deprotection ne charge plus l assemblage exactement une fois') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectLoad,'return ,([Security.Cryptography.ProtectedData]::Unprotect')}
Invoke-Scenario -Label 'System.Security loaded only after the DPAPI call' -ExpectedFailure @('l assemblage est charge apres l appel a DPAPI') -Mutation {param($t,$s);Mutate-Runtime $t @($protectLoad,'return ,([Security.Cryptography.ProtectedData]::Protect','::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)){NL}}','::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)){NL}    Add-Type -AssemblyName System.Security{NL}}')}
Invoke-Scenario -Label 'Protection protects a constant instead of the material handed to it' -ExpectedFailure @('le premier argument de la protection nest plus le materiel remis') -Mutation {param($t,$s);Mutate-Runtime $t @('ProtectedData]::Protect($Bytes,$null,','ProtectedData]::Protect([byte[]]@(1,2,3),$null,')}
Invoke-Scenario -Label 'Deprotection decrypts a constant instead of the secret handed to it' -ExpectedFailure @('le premier argument de la deprotection nest plus le secret remis') -Mutation {param($t,$s);Mutate-Runtime $t @('ProtectedData]::Unprotect($Bytes,$null,','ProtectedData]::Unprotect([byte[]]@(1,2,3),$null,')}
Invoke-Scenario -Label 'Protection accepts text instead of bytes' -ExpectedFailure @('Protect-PestoOfflineBytes n exige plus des octets') -Mutation {param($t,$s);Mutate-Runtime $t @($protectHeader,'function Protect-PestoOfflineBytes {{NL}    param([string]$Bytes)')}
Invoke-Scenario -Label 'Deprotection accepts text instead of bytes' -ExpectedFailure @('Unprotect-PestoOfflineBytes n exige plus des octets') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectHeader,'function Unprotect-PestoOfflineBytes {{NL}    param([string]$Bytes)')}
Invoke-Scenario -Label 'Protection publishes the material to the host' -ExpectedFailure @('la protection lance une deuxieme commande') -Mutation {param($t,$s);Mutate-Runtime $t @($protectReturn, ('Write-Host $Bytes{NL}    '+$protectReturn))}
Invoke-Scenario -Label 'Deprotection publishes the secret to the host' -ExpectedFailure @('la deprotection lance une deuxieme commande') -Mutation {param($t,$s);Mutate-Runtime $t @($unprotectReturn, ('Write-Host $Bytes{NL}    '+$unprotectReturn))}
Invoke-Scenario -Label 'Import protects the material twice' -ExpectedFailure @('le materiel nest plus protege exactement une fois a l import') -Mutation {param($t,$s);Mutate-Runtime $t @($importCall, ($importCall+';[void](Protect-PestoOfflineBytes $bytes)'))}
Invoke-Scenario -Label 'Import decrypts while importing' -ExpectedFailure @('l import dechiffre : il n a rien a dechiffrer') -Mutation {param($t,$s);Mutate-Runtime $t @($importCall, ($importCall+';[void](Unprotect-PestoOfflineBytes $bytes)'))}
Invoke-Scenario -Label 'Import protects something other than the clear material' -ExpectedFailure @('ce n est plus le materiel clair qui est remis a la protection') -Mutation {param($t,$s);Mutate-Runtime $t @($importCall,'$encrypted=(Protect-PestoOfflineBytes ([byte[]]@(1,2,3)))')}
Invoke-Scenario -Label 'Apply decrypts the secret twice' -ExpectedFailure @('le secret n est plus dechiffre exactement une fois a l application') -Mutation {param($t,$s);Mutate-Runtime $t @($applyCall, ($applyCall+';[void](Unprotect-PestoOfflineBytes $secret)'))}
Invoke-Scenario -Label 'Apply re-protects the secret it just decrypted' -ExpectedFailure @('l application re-protege le secret') -Mutation {param($t,$s);Mutate-Runtime $t @($applyCall, ($applyCall+';[void](Protect-PestoOfflineBytes $secret)'))}
Invoke-Scenario -Label 'Apply decrypts the wrong buffer' -ExpectedFailure @('ce n est plus le secret relu du magasin qui est dechiffre') -Mutation {param($t,$s);Mutate-Runtime $t @($applyCall,'$bytes=(Unprotect-PestoOfflineBytes $bytes)')}
Invoke-Scenario -Label 'Apply fingerprints the material before decrypting it' -ExpectedFailure @('l empreinte est calculee avant le dechiffrement') -Mutation {param($t,$s);Mutate-Runtime $t @($applyPair,$applyPairSwapped)}
Write-Output ('OfflineJoin109SecretMutations : '+$n+'/'+$n+' PASS')
