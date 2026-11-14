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
# Invariant de securite de l'approbation separee (point 117), joue sur le fournisseur crypto de l'hote, sans
# appel AD, domaine ni VM. La garde de taille de cle de wad/Pesto-Policy.ps1 lit KeySize, que RSAOpenSsl rend
# en ecriture seule hors Windows : Run-CampaignApproval117Tests.ps1 est donc declaree Windows51 et le correctif
# (mesurer ExportParameters($false).Modulus) reste a qualifier. Les cas ci-dessous tiennent dans les deux etats
# et ne laissent jamais passer un accord signe par une cle faible, ce qu'un correctif trop presse ouvrirait.
$script:sid='S-1-5-21-111';function Get-PestoOperatorSid {$script:sid};function Get-PestoAutomationMachineId {'fixture-machine'}
function New-FixtureCertificate([int]$Bits){
    $rsa=[Security.Cryptography.RSA]::Create($Bits)
    $request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pesto fixture',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
}
function New-SelfSignedApproval($Plan,$Certificate,$ApproverSid){
    # Accord bien forme signe par le certificat lui-meme : seule la taille de la cle peut desormais le refuser.
    $payload=[pscustomobject][ordered]@{Schema=1;Purpose='PestoCampaignApproval';Campaign=[string]$Plan.Metadata.Campaign;ApproverSid=$ApproverSid;CreatedUtc=[DateTime]::UtcNow.AddMinutes(-1).ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddMinutes(30).ToString('o');PlanHashes=@((Get-PestoCampaignPlanHash $Plan))}
    $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 5 -Compress))
    $key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    try{$signature=$key.SignData($bytes,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
    return [pscustomobject]@{Schema=1;Payload=[Convert]::ToBase64String($bytes);Certificate=[Convert]::ToBase64String($Certificate.RawData);Signature=[Convert]::ToBase64String($signature)}
}
$weak=New-FixtureCertificate 1024
$script:policy=[pscustomobject]@{Campaigns=@('C42');Signers=@()}
function Get-PestoCampaignPolicy {$script:policy}
$p=New-PestoPortablePlan -Action Rename -Computer 'PC001' -NewName 'P111301AA765001' -Domain 'example.local' -ConfigStamp ('a'*64) -MachineId 'fixture-machine' -SourceOU $TargetOU -TargetOU $TargetOU -ObjectGuid '11111111-1111-1111-1111-111111111111' -Metadata ([pscustomobject]@{Campaign='C42'})
$execution=[pscustomobject]@{Renommer=$true;Deplacer=$false;Nom_du_PC=$p.Computer;Nouveau_Nom=$p.NewName;OU_Actuelle=$p.SourceOU;OU_Destination=$p.TargetOU;Objet_GUID=$p.ObjectGuid;TargetOUGuid=$p.TargetOUGuid;Domain=$p.Domain;ConfigStamp=$p.ConfigStamp;Metadata=$p.Metadata}
try{
 # Les deux premiers cas prouvent que le refus attendu plus bas n'est pas un refus par defaut : la fonction
 # sait accepter (campagne non selectionnee) et sait refuser proprement (certificat non epingle).
 Case 'Unselected campaign is accepted with no approval at all' {
    $c=$p.PSObject.Copy();$c.Metadata=[pscustomobject]@{Campaign='Other'}
    Assert-PestoCampaignApproval $c $null
 }
 Case 'Unpinned approver certificate is refused by name' {
    $message=Refusal {Assert-PestoCampaignApproval $p (New-SelfSignedApproval $p $weak 'S-1-5-21-222')}
    Assert ($message -ceq 'Certificat approbateur non approuve.')
 }
 Case 'The weak-key fixture really is a valid approval of this plan' {
    $approval=New-SelfSignedApproval $p $weak 'S-1-5-21-222'
    $bytes=[Convert]::FromBase64String($approval.Payload);$signature=[Convert]::FromBase64String($approval.Signature)
    $verifier=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($weak)
    try{Assert ($verifier.VerifyData($bytes,$signature,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1))}finally{$verifier.Dispose()}
    $payload=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
    Assert ($payload.Schema -eq 1 -and $payload.Purpose -ceq 'PestoCampaignApproval' -and $payload.Campaign -ceq 'C42')
    Assert ((Get-PestoCampaignPlanHash $p) -in @($payload.PlanHashes))
 }
 Case 'A validly signed 1024-bit approval is never accepted, on either leg' {
    $approval=New-SelfSignedApproval $p $weak 'S-1-5-21-222'
    $signers=$script:policy.Signers
    try{
        $script:policy.Signers=@([pscustomobject]@{CertificateSHA256=(Get-PestoBytesHash $weak.RawData);Sid='S-1-5-21-222'})
        Reject {Assert-PestoCampaignApproval $p $approval}
        Reject {Assert-PestoCampaignApproval $execution $approval}
    }finally{$script:policy.Signers=$signers}
 }
 Case 'A 1024-bit approver never signs an approval at all' {
    Reject {New-PestoCampaignApproval @($p) $weak}
 }
}finally{$weak.Dispose()}
Write-Host "CampaignApproval117WeakKey: $script:passed passed, $script:failed failed (host crypto providers, no AD/VM calls)."
if($script:failed){exit 1}
