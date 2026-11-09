$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\ui-common.ps1
function ReceiptHashes { @(Get-ChildItem (Get-PestoInterventionRoot) -Filter '*.json'|Get-FileHash|Select Path,Hash) }
try{
 $w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 20
 if(ById $w LedgerClose){Invoke-Element (ById $w LedgerClose)|Out-Null;Start-Sleep -Milliseconds 300}
 Invoke-Element (ById $w NavRename)|Out-Null;Start-Sleep -Milliseconds 300
 (ById $w CbService).GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('')
 $before=ReceiptHashes
 $adBefore=Get-ADComputer -Identity '568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
 Set-Premier $w
 [Windows.Forms.SendKeys]::SendWait('{ESC}')
 (ById $w TxtPCName).SetFocus()
 [Windows.Forms.SendKeys]::SendWait('{ENTER}')
 Start-Sleep 3
 $end=(Get-Date).AddSeconds(40)
 while(-not (ById $w BtnReadComputer).Current.IsEnabled -and (Get-Date) -lt $end){Start-Sleep -Milliseconds 300}
 if((ById $w SuiteDirectRun).Current.Name -notmatch 'Compléter'){throw 'Compléter attendu après lecture'}
 $afterEnter=ReceiptHashes
 if(($before|ConvertTo-Json -Compress) -cne ($afterEnter|ConvertTo-Json -Compress)){throw 'Entrée a modifié les reçus'}
 Save-Ecran "$D\entree-lecture-seule.png"|Out-Null
 Invoke-Element (ById $w SuiteDirectRun)|Out-Null
 $focus=Get-Focus
 Select-Combo (ById $w CbOrg) 'PestoQualification'
 Select-Combo (ById $w CbSite) 'ALPHA-AA'
 (ById $w CbService).GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('QA1')
 Start-Sleep 2
 Select-Combo (ById $w CbName) 'V999004AAQA1005'
 if((ById $w SuiteDirectRun).Current.Name -notmatch 'Vérifier'){throw 'Vérifier attendu après formulaire'}
 Invoke-Element (ById $w SuiteDirectRun)|Out-Null
 $end=(Get-Date).AddSeconds(40)
 do{Start-Sleep -Milliseconds 400;$panel=ById $w PanelBody;$body=if($panel){$panel.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value}else{''}}while($body -notmatch 'V999004AAQA1005' -and (Get-Date) -lt $end)
 if($body -notmatch 'V999004AAQA1005' -or $body -notmatch 'Renommer uniquement'){throw 'Confirmation finale inattendue'}
 $body|Set-Content "$D\bouton-principal-confirmation.txt" -Encoding UTF8
 Save-Ecran "$D\bouton-principal-confirmation.png"|Out-Null
 Invoke-Element (ById $w PanelCancel)|Out-Null;Start-Sleep -Milliseconds 400
 $after=ReceiptHashes
 $adAfter=Get-ADComputer -Identity '568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
 if(($before|ConvertTo-Json -Compress) -cne ($after|ConvertTo-Json -Compress) -or $adBefore.DistinguishedName -ne $adAfter.DistinguishedName){throw 'Préparation a modifié AD ou reçus'}
 Save-LabResult 'bouton-principal-et-entree' ([pscustomobject]@{Date=(Get-Date -Format o);EnterOnlyRead=$true;FocusAfterComplete=$focus;FinalConfirmationCancelled=$true;Before=$before;After=$after;ADBefore=$adBefore|Select Name,ObjectGUID,DistinguishedName;ADAfter=$adAfter|Select Name,ObjectGUID,DistinguishedName})
}catch{$_|Out-String|Set-Content "$D\bouton-principal-erreur.txt" -Encoding UTF8;exit 1}
