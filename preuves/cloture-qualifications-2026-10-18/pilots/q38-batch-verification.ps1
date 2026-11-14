. 'C:\PestoQual_20261018\pilot\commun.ps1'
Import-Module 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\ActiveDirectory.psd1'
$objects=@();foreach($s in 'dc01.labo.local','LABO-DC02.labo.local'){foreach($g in 'b4797c9c-d790-4797-bf71-424a57acb36e','fc6f4538-2fb8-43fa-812b-5c9b07b454a7'){$o=Get-ADComputer -Identity $g -Server $s;$objects+=@{Server=$s;ObjectGuid=[string]$o.ObjectGUID;DN=$o.DistinguishedName;Utc=[datetime]::UtcNow.ToString('o')}}}
$before=(Get-Content "$D\q36-stop-request.json" -Raw|ConvertFrom-Json).BeforeReceipts.Name
$new=@(Get-ChildItem C:\ProgramData\GP\Interventions -Filter '*.json' -File|Where-Object Name -notin $before)
$records=@();foreach($file in $new){Copy-Item $file.FullName (Join-Path $D ('q38-receipt-'+$file.Name));$records+=Get-Content $file.FullName -Raw|ConvertFrom-Json}
@{Utc=[datetime]::UtcNow.ToString('o');Objects=$objects;NewReceiptCount=$new.Count;Receipts=$records;ExeSHA256=(Get-FileHash 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\Pesto.exe').Hash}|ConvertTo-Json -Depth 12|Set-Content "$D\q38-batch-verification.json" -Encoding UTF8
@{NewReceiptCount=$new.Count;TargetLyon=(@($objects|Where-Object {$_.ObjectGuid -eq 'b4797c9c-d790-4797-bf71-424a57acb36e' -and $_.DN -like '*,OU=Lyon,*'}).Count -eq 2);SecondParis=(@($objects|Where-Object {$_.ObjectGuid -eq 'fc6f4538-2fb8-43fa-812b-5c9b07b454a7' -and $_.DN -like '*,OU=Paris,*'}).Count -eq 2)}|ConvertTo-Json
