#requires -Version 5.1
param()
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
foreach($f in @('Contracts','Configuration','ManagedPolicy','Policy','Enterprise')){. (Join-Path $root ('wad/Pesto-'+$f+'.ps1'))}
$script:passed=0;$script:failed=0
function Case($name,[scriptblock]$body){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}}
function Assert($v){if(-not$v){throw 'Assertion failed'}}
function Reject([scriptblock]$body){$caught=$false;try{&$body|Out-Null}catch{$caught=$true};Assert $caught}
function Refusal([scriptblock]$body){$message='';try{&$body|Out-Null}catch{$message=[string]$_.Exception.Message};return $message}
$TargetOU='OU=Paris,DC=example,DC=local'
# Approbation de campagne (point 117) : vraies signatures RSA, confiance simulee par Get-PestoCampaignPolicy.
# Aucun appel AD, domaine ou VM ; seuls les fournisseurs crypto de l'hote sont exerces.
# La garde de taille de cle de wad/Pesto-Policy.ps1 lit $key.KeySize. Hors Windows, Get-RSAPublicKey et
# Get-RSAPrivateKey rendent un RSAOpenSsl dont KeySize n'a qu'un setter : la lecture leve une erreur
# write-only et avorte New-PestoCampaignApproval avant toute signature, ce qui tuait les quatorze cas. Le correctif produit
# (mesurer ExportParameters($false).Modulus) est ecrit mais wad/Pesto-Policy.ps1 est un composant scelle dont
# l'empreinte est compilee dans Pesto.exe, et le rebatir exige clang et lld-link, absents de Spark. En
# attendant, la suite n'installe l'adaptateur ci-dessous QUE si l'hote rend KeySize en ecriture seule, le
# retire a la fin, et ne fige aucune taille : le module est mesure a chaque lecture, ce que controlent le cas
# 'Key size is measured from the modulus, never frozen' et Run-CampaignApproval117MutationTests.ps1.
function Test-PestoKeySizeWriteOnly {
    $probeRsa=[Security.Cryptography.RSA]::Create(2048)
    try{
        $probeRequest=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pesto capability probe',$probeRsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $probeCert=$probeRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
        try{
            $probeKey=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($probeCert)
            try{$null=$probeKey.KeySize;return $false}
            catch{return (([string]$_.Exception.Message) -match 'write-only')}
            finally{if($probeKey){$probeKey.Dispose()}}
        }finally{$probeCert.Dispose()}
    }finally{$probeRsa.Dispose()}
}
$script:keySizeMeasuredBy='host KeySize';$script:keySizeAdapted=$false
if(Test-PestoKeySizeWriteOnly){
    Update-TypeData -TypeName 'System.Security.Cryptography.RSAOpenSsl' -MemberType ScriptProperty -MemberName KeySize -Force -Value {[int]($this.ExportParameters($false).Modulus.Length*8)}
    $script:keySizeMeasuredBy='fixture modulus';$script:keySizeAdapted=$true
}
function New-FixtureCertificate([int]$Bits){
    $fixtureRsa=[Security.Cryptography.RSA]::Create($Bits)
    $fixtureRequest=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pesto fixture',$fixtureRsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return $fixtureRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
}
$script:sid='S-1-5-21-111';function Get-PestoOperatorSid {$script:sid};function Get-PestoAutomationMachineId {'fixture-machine'}
$rsa=[Security.Cryptography.RSA]::Create(2048)
$request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pesto fixture',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
$cert=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
$script:policy=[pscustomobject]@{Campaigns=@('C42');Signers=@([pscustomobject]@{CertificateSHA256=(Get-PestoBytesHash $cert.RawData);Sid=$script:sid})}
function Get-PestoCampaignPolicy {$script:policy}
$p=New-PestoPortablePlan -Action Rename -Computer 'PC001' -NewName 'P111301AA765001' -Domain 'example.local' -ConfigStamp ('a'*64) -MachineId 'fixture-machine' -SourceOU $TargetOU -TargetOU $TargetOU -ObjectGuid '11111111-1111-1111-1111-111111111111' -Metadata ([pscustomobject]@{Campaign='C42'})
try{
 $approval=New-PestoCampaignApproval @($p) $cert
 Case 'Self approval refused' {Reject {Assert-PestoCampaignApproval $p $approval}}
 $script:sid='S-1-5-21-222'
 Case 'Independent signed approval' {Assert-PestoCampaignApproval $p $approval}
 Case 'Changed effect refused' {$c=$p.PSObject.Copy();$c.NewName='P111301AA765002';Reject {Assert-PestoCampaignApproval $c $approval}}
 Case 'Changed identity refused' {$c=$p.PSObject.Copy();$c.ObjectGuid='22222222-2222-2222-2222-222222222222';Reject {Assert-PestoCampaignApproval $c $approval}}
 Case 'Changed machine refused' {$c=$p.PSObject.Copy();$c.MachineId='other';Reject {Assert-PestoCampaignApproval $c $approval}}
 Case 'Missing approval refused' {Reject {Assert-PestoCampaignApproval $p $null}}
 Case 'Invalid signature refused' {$c=$approval.PSObject.Copy();$b=[Convert]::FromBase64String($c.Signature);$b[0]=$b[0] -bxor 1;$c.Signature=[Convert]::ToBase64String($b);Reject {Assert-PestoCampaignApproval $p $c}}
 Case 'Expired but correctly signed approval refused' {
    $c=$approval.PSObject.Copy();$payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($c.Payload))|ConvertFrom-Json
    $payload.CreatedUtc=[DateTime]::UtcNow.AddHours(-2).ToString('o');$payload.ExpiresUtc=[DateTime]::UtcNow.AddHours(-1).ToString('o')
    $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 5 -Compress));$c.Payload=[Convert]::ToBase64String($bytes)
    $c.Signature=[Convert]::ToBase64String($rsa.SignData($bytes,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1))
    Reject {Assert-PestoCampaignApproval $p $c}
 }
 Case 'Payload tampering refused before claims are trusted' {$c=$approval.PSObject.Copy();$b=[Convert]::FromBase64String($c.Payload);$b[5]=$b[5] -bxor 1;$c.Payload=[Convert]::ToBase64String($b);Reject {Assert-PestoCampaignApproval $p $c}}
 Case 'Revocation by removing signer' {$old=$script:policy.Signers;$script:policy.Signers=@();try{Reject {Assert-PestoCampaignApproval $p $approval}}finally{$script:policy.Signers=$old}}
 Case 'Execution and exported effect share digest' {$execution=[pscustomobject]@{Renommer=$true;Deplacer=$false;Nom_du_PC=$p.Computer;Nouveau_Nom=$p.NewName;OU_Actuelle=$p.SourceOU;OU_Destination=$p.TargetOU;Objet_GUID=$p.ObjectGuid;TargetOUGuid=$p.TargetOUGuid;Domain=$p.Domain;ConfigStamp=$p.ConfigStamp;Metadata=$p.Metadata};Assert ((Get-PestoCampaignPlanHash $execution) -ceq (Get-PestoCampaignPlanHash $p));Assert-PestoCampaignApproval $execution $approval}
 Case 'Unselected campaign remains optional' {$c=$p.PSObject.Copy();$c.Metadata=[pscustomobject]@{Campaign='Other'};Assert-PestoCampaignApproval $c $null}
 Case 'Wildcard requires campaign for all operations' {$old=$script:policy.Campaigns;$script:policy.Campaigns=@('*');try{$c=$p.PSObject.Copy();$c.Metadata=$null;Reject {Assert-PestoCampaignApproval $c $null}}finally{$script:policy.Campaigns=$old}}
 Case 'Weak approver key refused by the rule, not by a binding error' {
    $weakRsa=[Security.Cryptography.RSA]::Create(1024)
    $weakRequest=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pesto weak fixture',$weakRsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $weakCert=$weakRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
    try{
        $message=Refusal {New-PestoCampaignApproval @($p) $weakCert}
        Assert ($message -ceq 'Cle privee RSA 2048 bits minimum requise.')
        $signers=$script:policy.Signers
        try{
            $script:policy.Signers=@([pscustomobject]@{CertificateSHA256=(Get-PestoBytesHash $weakCert.RawData);Sid='S-1-5-21-333'})
            $payload=[pscustomobject][ordered]@{Schema=1;Purpose='PestoCampaignApproval';Campaign='C42';ApproverSid='S-1-5-21-333';CreatedUtc=[DateTime]::UtcNow.AddMinutes(-1).ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddMinutes(30).ToString('o');PlanHashes=@((Get-PestoCampaignPlanHash $p))}
            $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 5 -Compress))
            $weakKey=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($weakCert)
            try{$signature=$weakKey.SignData($bytes,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$weakKey.Dispose()}
            $weakApproval=[pscustomobject]@{Schema=1;Payload=[Convert]::ToBase64String($bytes);Certificate=[Convert]::ToBase64String($weakCert.RawData);Signature=[Convert]::ToBase64String($signature)}
            # La signature seule serait acceptee : seule la garde de taille de clef peut refuser cet accord.
            $verifier=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($weakCert)
            try{Assert ($verifier.VerifyData($bytes,$signature,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1))}finally{$verifier.Dispose()}
            Reject {Assert-PestoCampaignApproval $p $weakApproval}
        }finally{$script:policy.Signers=$signers}
    }finally{$weakCert.Dispose();$weakRsa.Dispose()}
 }
 Case 'Key size is measured from the modulus, never frozen' {
    # Le mesureur de taille est-il un mesureur ? Les deux clefs sont lues par l'accesseur meme que la garde
    # de wad/Pesto-Policy.ps1 utilise, sur les deux jambes. Une taille figee, trop haute ou trop basse, casse
    # ici : soit les deux clefs donnent la meme valeur, soit la valeur ne suit plus le module.
    $strongCert=New-FixtureCertificate 2048
    $tinyCert=New-FixtureCertificate 1024
    try{
        $strongKey=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($strongCert)
        $strongPrivate=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($strongCert)
        $tinyKey=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($tinyCert)
        try{
            $strongModulus=$strongKey.ExportParameters($false).Modulus
            $tinyModulus=$tinyKey.ExportParameters($false).Modulus
            Assert ($strongKey.KeySize -eq ($strongModulus.Length*8))
            Assert ($strongPrivate.KeySize -eq ($strongModulus.Length*8))
            Assert ($tinyKey.KeySize -eq ($tinyModulus.Length*8))
            Assert ($strongKey.KeySize -eq 2048 -and $tinyKey.KeySize -eq 1024)
            Assert ($strongKey.KeySize -cne $tinyKey.KeySize)
        }finally{$strongKey.Dispose();$strongPrivate.Dispose();$tinyKey.Dispose()}
    }finally{$strongCert.Dispose();$tinyCert.Dispose()}
 }
}finally{$cert.Dispose();$rsa.Dispose();if($script:keySizeAdapted){Remove-TypeData -TypeName 'System.Security.Cryptography.RSAOpenSsl' -ErrorAction SilentlyContinue}}
Write-Host "CampaignApproval117: $script:passed passed, $script:failed failed (host crypto providers, no AD/VM calls; key size measured by $script:keySizeMeasuredBy)."
if($script:failed){exit 1}