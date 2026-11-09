. 'C:\PestoQual_20261018\pilot\commun.ps1'
$w=Get-Pesto;Set-Max $w
$rows=@()
foreach($id in @('NavHome','NavHistory','NavLogs','NavSettings','NavNames','NavRename','NavHome')){
 Click-Id $w $id|Out-Null;Start-Sleep -Seconds 2
 $rows+=[pscustomobject]@{Page=$id;Utc=[DateTime]::UtcNow.ToString('o');ProcessId=$w.Current.ProcessId;Text=@(Get-Texte $w)}
 Save-Vue $w ('q98-server-'+$id)
}
[pscustomobject]@{User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Version=$PSVersionTable.PSVersion.ToString();ExeHash=(Get-FileHash 'C:\PestoQual_20261018\server\candidate\PROD\Pesto.exe').Hash;Pages=$rows;Process=Get-Process -Id $w.Current.ProcessId|Select Id,SessionId,Responding;Result='NAVIGATION_COMPLETED'}|ConvertTo-Json -Depth 8|Set-Content "$D\q98-server-gui.json" -Encoding UTF8
'NAVIGATION_COMPLETED'
