function New-LabMoveRequest($PC,[string]$Destination){
 $dest=Get-ADOrganizationalUnit -Identity $Destination -Server $script:DC -Credential $script:cred
 $r=[pscustomobject]@{
 Telemetry=(New-PestoQueueMonitor -Computer $PC.Name);OperationId=[Guid]::NewGuid().ToString('N');ResumeId=''
 Computer=$PC.Name;NewName=$PC.Name;TargetOU=$Destination;CurrentOU=(Get-PestoParentDN $PC.DistinguishedName)
 Rename=$false;Move=$true;Reboot=$false;ObjectGuid=$PC.ObjectGUID.ToString();TargetOUGuid=$dest.ObjectGUID.ToString()
 ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);PlanFingerprint='';Policy=$script:PestoPolicy;ReadOnly=$false
 DC=$script:DC;Domain=$script:DOMAINE;Credential=$script:cred;Prefix=$script:PREFIXE;SIM=$false;InDomain=$true;PRD=$true
 OU=$script:OU;OUSite=$script:OUV;OUPostes=$script:OU_POSTES;OUScan=$script:OU_SCAN;ClearProtection=$true
 EntraPolicy='Disabled';AllowPasswordTaskFallback=$false;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')
 }
 $r.PlanFingerprint=Get-PestoPlanFingerprint (New-PestoExecutionPlan $r)
 return $r
}
