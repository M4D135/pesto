. 'C:\PestoQual_20261018\pilot\commun.ps1'
Import-Module 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\ActiveDirectory.psd1'
$guid='b4797c9c-d790-4797-bf71-424a57acb36e';$o=Get-ADComputer -Identity $guid -Server dc01.labo.local
$paris='OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local'
if($o.Name -ne 'P111301VA765158' -or $o.DistinguishedName -ne ('CN=P111301VA765158,'+$paris.Replace('OU=Paris,','OU=Lyon,'))){throw 'Unexpected cleanup target'}
Move-ADObject -Identity $guid -TargetPath $paris -Server dc01.labo.local -Confirm:$false
$rows=@();foreach($s in 'dc01.labo.local','LABO-DC02.labo.local'){$deadline=[datetime]::UtcNow.AddSeconds(35);do{$a=Get-ADComputer -Identity $guid -Server $s;if($a.DistinguishedName -eq ('CN=P111301VA765158,'+$paris)){break};Start-Sleep 2}while([datetime]::UtcNow -lt $deadline);$rows+=@{Server=$s;Guid=[string]$a.ObjectGUID;DN=$a.DistinguishedName;Utc=[datetime]::UtcNow.ToString('o')}}
@{Method='Explicit lab cleanup Move-ADObject; not a Pesto replay';Objects=$rows;Restored=(@($rows|Where-Object DN -notlike '*,OU=Paris,*').Count -eq 0)}|ConvertTo-Json -Depth 4|Set-Content "$D\q40-restore-lab.json" -Encoding UTF8
'Cleanup recorded'
