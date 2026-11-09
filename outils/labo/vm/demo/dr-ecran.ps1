Import-Module C:\PestoTest-run\pilote.psm1
$D = 'C:\PestoTest-preuves\demo-reelle\captures'
& { Save-Ecran "$D\ecran.png"; Get-Fenetres | Format-Table -AutoSize | Out-String -Width 220; Get-Process | Where-Object { $_.Path -like 'C:\PestoDemo*' -or $_.MainWindowTitle -like 'Pesto*' } | ForEach-Object { "$($_.Name) $($_.Id) « $($_.MainWindowTitle) »" } } *> "$D\ecran.txt"
