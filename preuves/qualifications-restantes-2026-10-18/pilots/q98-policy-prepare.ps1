. 'C:\PestoQual_20261018\pilot\commun.ps1'

$ErrorActionPreference='Stop'
$dir='C:\PestoQualPersonal_20261018\policy98-new'
if(Test-Path $dir){throw 'Evidence directory already exists'};[void][IO.Directory]::CreateDirectory($dir)
Start-Transcript "$dir\prepare.log"
try {
 Import-Module ConfigCI
 Write-Output 'Generating deny rules'
 $rules=New-CIPolicyRule -Level Hash -DriverFilePath 'C:\PestoQualPersonal_20261018\candidate-fix\PROD\Pesto.exe' -Deny
 Write-Output ('Rules '+@($rules).Count)
 Merge-CIPolicy -PolicyPaths "C:\PestoQualPersonal_20261018\policy92\AllowAll-template.xml" -OutputFilePath "$dir\audit.xml" -Rules $rules|Out-Null
 Set-CIPolicyIdInfo -FilePath "$dir\audit.xml" -PolicyName 'Pesto qualification 98 temporary deny exact build' -ResetPolicyID|Out-Null
 foreach($option in @(0,3,6,16)){Set-RuleOption -FilePath "$dir\audit.xml" -Option $option}
 Set-RuleOption -FilePath "$dir\audit.xml" -Option 11 -Delete
 [xml]$xml=Get-Content "$dir\audit.xml"
 $id=[string]$xml.SiPolicy.PolicyID
 if(@($xml.SiPolicy.FileRules.Allow|Where-Object {$_.FileName -eq '*'}).Count -ne 2){throw 'Missing kernel/user AllowAll guard'}
 Copy-Item "$dir\audit.xml" "$dir\enforced.xml"
 Set-RuleOption -FilePath "$dir\enforced.xml" -Option 3 -Delete
 Set-CIPolicyVersion -FilePath "$dir\enforced.xml" -Version '10.0.0.1'
 ConvertFrom-CIPolicy -XmlFilePath "$dir\audit.xml" -BinaryFilePath "$dir\audit.cip"|Out-Null
 ConvertFrom-CIPolicy -XmlFilePath "$dir\enforced.xml" -BinaryFilePath "$dir\enforced.cip"|Out-Null
 [pscustomobject]@{PolicyId=$id;TargetHash=(Get-FileHash 'C:\PestoQualPersonal_20261018\candidate-fix\PROD\Pesto.exe').Hash;Deployed=$false;AllowAllKernelAndUser=$true}|ConvertTo-Json|Set-Content "$dir\prepared.json" -Encoding UTF8
 Get-Content "$dir\prepared.json"
} catch { $_|Out-String|Set-Content "$dir\prepare-error.txt";throw } finally {Stop-Transcript}
