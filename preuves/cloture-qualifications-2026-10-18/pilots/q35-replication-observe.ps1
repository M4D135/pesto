. 'C:\PestoQual_20261018\pilot\commun.ps1'
Import-Module 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\ActiveDirectory.psd1'
& "$R\tools\Observe-PestoReplication.ps1" -Domain labo.local -ObjectGuid b4797c9c-d790-4797-bf71-424a57acb36e -Server @('dc01.labo.local','LABO-DC02.labo.local') -ExpectedName P111301VA765158 -ExpectedDistinguishedName 'CN=P111301VA765158,OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local' -IntervalSeconds 2 -TimeoutSeconds 180 -ReportPath "$D\q35-replication.json"
Get-Content "$D\q35-replication.json" -Raw
