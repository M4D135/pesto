$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$vhd='C:\PestoTest-run\pesto-full-20261004.vhd'
if(Test-Path R:\){throw 'Lettre R deja utilisee'}
if(Test-Path $vhd){throw 'Disque recette existe deja'}
$diskpart='C:\PestoTest-run\pesto-full-create.txt'
@(('create vdisk file="'+$vhd+'" maximum=64 type=expandable'),('select vdisk file="'+$vhd+'"'),'attach vdisk','create partition primary','format fs=ntfs label="PESTO_FULL_TEST" quick','assign letter=R')|Set-Content $diskpart -Encoding ASCII
try {
 & diskpart.exe /s $diskpart *> "$LabProof\disque-plein-creation.txt"
 $drive=[IO.DriveInfo]::new('R')
 Assert-Lab ($drive.VolumeLabel -eq 'PESTO_FULL_TEST' -and $drive.TotalSize -lt 70MB) 'Volume recette non confirme'
 [void][IO.Directory]::CreateDirectory('R:\Interventions')
 Write-PestoJoinReceipt -Path R:\Temoin\avant.json -Receipt ([pscustomobject]@{Valeur=('a'*8192)})
 Set-Acl -LiteralPath R:\Interventions -AclObject (Get-Acl R:\Temoin)
 $beforeHash=(Get-FileHash R:\Temoin\avant.json).Hash
 $buffer=New-Object byte[] 4096
 $fill=[IO.File]::Open('R:\remplissage.bin',[IO.FileMode]::CreateNew)
 $diskError=''
 try {while($true){$fill.Write($buffer,0,$buffer.Length);$fill.Flush($true)}}
 catch {$diskError=$_.Exception.ToString()}
 finally {$fill.Dispose()}
 $free=$drive.AvailableFreeSpace
 Assert-Lab ($free -lt 4096 -and $diskError) 'Volume non plein'
 $writeError=''
 try {Write-PestoJoinReceipt -Path R:\Temoin\avant.json -Receipt ([pscustomobject]@{Valeur=('b'*16384)})}
 catch {$writeError=$_.Exception.ToString()}
 Assert-Lab ($writeError -and (Get-FileHash R:\Temoin\avant.json).Hash -eq $beforeHash) 'Ecriture atomique precedente alteree'
 $pc=Get-ADComputer -Identity '8b54de3a-a68c-4662-a8d4-742d29bc5dff' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
 $req=New-LabMoveRequest $pc ('OU=BETA-BB,OU=Computers,'+$script:OU.ROOT)
 # Injection limitee au chemin du registre de recus, sur le vrai volume NTFS plein.
 # Aucune cmdlet AD ni fonction d'ecriture n'est remplacee.
 $source=(Get-PestoWorkerCoreSource)+"`r`nfunction Get-PestoInterventionRoot { return 'R:\Interventions' }`r`n"
 $result=& $script:PestoQueueWorker $req $source
 $after=Get-ADComputer -Identity $pc.ObjectGUID -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
 Save-LabResult 'disque-plein' ([pscustomobject]@{Date=(Get-Date -Format o);Volume='NTFS VHD 64MiB jetable';FreeBytes=$free;FillError=$diskError;AtomicWriteError=$writeError;PreviousHash=$beforeHash;AfterHash=(Get-FileHash R:\Temoin\avant.json).Hash;Result=$result;Before=($pc|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion);After=($after|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion);ReceiptFiles=@(Get-ChildItem R:\Interventions -File|Select Name,Length)})
 Assert-Lab ($result.Action.ExitCode -eq 96 -and $result.Action.ExitMsg -match 'Sauvegarde atomique impossible') ('Refus inattendu '+$result.Action.ExitCode+' '+$result.Action.ExitMsg)
 Assert-Lab ($after.DistinguishedName -eq $pc.DistinguishedName -and $after.ProtectedFromAccidentalDeletion -eq $pc.ProtectedFromAccidentalDeletion) 'AD a change'
 'PASS : disque plein, ancien fichier conserve, code96 avant mutation, AD inchange'
} finally {
 @(('select vdisk file="'+$vhd+'"'),'detach vdisk')|Set-Content C:\PestoTest-run\pesto-full-detach.txt -Encoding ASCII
 & diskpart.exe /s C:\PestoTest-run\pesto-full-detach.txt *> "$LabProof\disque-plein-detachement.txt"
}
