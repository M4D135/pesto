#requires -Version 5.1
# Pester 5.7.1, définitions isolées. Aucun moteur WPF, AD, Entra ou UAC démarré.
BeforeAll {
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
  foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
 }
 Initialize-PestoCommon -Root (Join-Path $root 'wad')
 # Cette décision pure est définie dans le worker Entra, pas au niveau racine.
 $operations=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad\Pesto-Operations.ps1'),[ref]$tokens,[ref]$errors)
 $entra=@($operations.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-PestoEntraDisposition'},$true))
 if($entra.Count -ne 1){throw 'Décision Entra pure absente ou ambiguë.'}
 . ([scriptblock]::Create($entra[0].Extent.Text))
 function New-TestPlan21 {
  [pscustomobject]@{Nom_du_PC='P111301AA765001';Nouveau_Nom='P111301BB765002';Objet_GUID='11111111-1111-1111-1111-111111111111';OU_Actuelle='OU=AA,DC=test,DC=invalid';OU_Destination='OU=BB,DC=test,DC=invalid';TargetOUGuid='22222222-2222-2222-2222-222222222222';Domain='test.invalid';DC='dc.test.invalid';ConfigStamp=('a'*64);Renommer=$true;Deplacer=$true;Reboot=$false}
 }
 # Un appel non remplacé par un double produit un échec, pas un accès au vrai environnement.
 function Get-ADComputer { throw 'Fixture : aucun accès AD.' }
 function Set-ADObject { throw 'Fixture : aucune mutation AD.' }
 function Add-Computer { throw 'Fixture : aucune jonction.' }
}
Describe 'RC21 : aucune répétition des effets confirmés' {
 BeforeEach {
  $script:SIM=$false;$script:GUI=$false
  $script:ActiveIntervention=[pscustomobject]@{Rename='Confirmed';Move='Confirmed';InitialProtection=$null;LastStage='';UpdatedUtc='';Sequence=0;Timeline=@()}
  Mock Write-PestoIntervention {}
 }
 It 'Refuse de demander à nouveau <Field> confirmé' -ForEach @(@{Field='Rename'},@{Field='Move'}) {
  { Set-PestoEffect -Name $Field -Value 'Requested' } | Should -Throw
  Should -Invoke Write-PestoIntervention -Times 0 -Exactly
 }
 It 'Persiste un effet avant de rendre la main à l’’appelant' {
  $script:ActiveIntervention.Rename='NotRequested'
  Set-PestoEffect -Name Rename -Value Requested
  $script:ActiveIntervention.Rename | Should -BeExactly 'Requested'
  Should -Invoke Write-PestoIntervention -Times 1 -Exactly
 }
 It 'Une panne d’’écriture remonte et interdit une suite normale' {
  $script:ActiveIntervention.Rename='NotRequested'
  Mock Write-PestoIntervention {throw [IO.IOException]::new('disque indisponible')}
  { Set-PestoEffect -Name Rename -Value Requested } | Should -Throw
 }
}
Describe 'RC21 : contrat figé et entrées fermées' {
 It 'Le changement de <Field> invalide la confirmation' -ForEach @(
  @{Field='DC';Value='other.test.invalid'},@{Field='Nouveau_Nom';Value='P111301BB765099'},
  @{Field='TargetOUGuid';Value='33333333-3333-3333-3333-333333333333'},@{Field='Reboot';Value=$true}
 ) {
  $p=New-TestPlan21;$hash=Get-PestoPlanFingerprint $p;$p.$Field=$Value
  {Assert-PestoConfirmedPlan $p $hash ('a'*64)} | Should -Throw
 }
 It 'N’’accepte pas une chaîne false comme autorisation' {
  $p=New-TestPlan21;$p.Reboot='false';{Get-PestoPlanFingerprint $p}|Should -Throw
 }
 It 'Une réponse vide ou textuelle ne prouve pas un succès' {
  Get-PestoOutcome $null | Should -BeExactly 'Uncertain'
  Get-PestoOutcome '20' | Should -BeExactly 'Uncertain'
 }
 It 'Un brouillon contenant un mot de passe est refusé' {
  $d=[pscustomobject]@{Schema=1;Domain='test.invalid';Nom_du_PC='PC-1';Nouveau_Nom='P111301AA765001';Renommer=$true;Deplacer=$false;Password='PESTO_SENTINEL_21'}
  {ConvertTo-PestoDraft $d}|Should -Throw
 }
}
Describe 'RC21 : barrières avant transport' {
 BeforeEach {$script:PestoReadOnly=$false;$script:GUI=$false;$script:SIM=$false;Mock Get-ADComputer {throw 'Lecture AD inattendue.'}}
 It 'Consultation refuse sans chercher la cible dans AD' {
  $script:PestoReadOnly=$true
  {Assert-PestoOperationPolicy (New-TestPlan21) $null}|Should -Throw
  Should -Invoke Get-ADComputer -Times 0 -Exactly
 }
 It 'Une exclusion de nom refuse avant transport' {
  {Assert-PestoOperationPolicy (New-TestPlan21) ([pscustomobject]@{Schema=1;ExcludedNames=@('P111301AA*')})}|Should -Throw
  Should -Invoke Get-ADComputer -Times 0 -Exactly
 }
 It 'La préparation Entra AD seule reste sans retrait' {
  Get-PestoEntraDisposition "AzureAdJoined : NO`nDomainJoined : YES" $true | Should -BeExactly 'Skip'
 }
 It 'Un refus d’’authentification ne boucle pas' {
  Mock Start-Sleep {}
  {Invoke-PestoReadRetry -Attempts 3 -Read {throw [ComponentModel.Win32Exception]::new(1326)}}|Should -Throw
  Should -Invoke Start-Sleep -Times 0 -Exactly
 }
}
Describe 'RC21 : noms et annulation' {
 BeforeEach {
  $request=[pscustomobject]@{Prefix='111301';Computers=@();CachedIndex=$null;Types=@('P');Sites=@('AA');Teams=@('765');ReservedNames=@();OwnReservations=@();QueueReservations=@();PageSize=250;Offset=750;Buffer=5;ShowAll=$true;Status='Tous';Search='';Strategy='FirstGap';Cancellation=$null;Generation=1;Progress=$null;InventoryUtc=''}
 }
 It 'La dernière page ne conserve que 249 lignes sur 999' {
  $r=Invoke-PestoBuildNamesView $request;$r.Rows.Count|Should -Be 249;$r.Total|Should -Be 999;$r.HasNext|Should -BeFalse
 }
 It 'Un calcul déjà remplacé est refusé' {
  $request.Cancellation=[hashtable]::Synchronized(@{Cancelled=$true})
  {Invoke-PestoBuildNamesView $request}|Should -Throw
 }
 It 'La réserve de file n’’est jamais présentée comme libre AD' {
  $request.Offset=0;$request.ReservedNames=@('P111301AA765001');$request.QueueReservations=$request.ReservedNames
  $r=Invoke-PestoBuildNamesView $request;$r.Rows[0].Statut|Should -BeExactly 'Préparé dans la file';$r.Rows[0].InAD|Should -BeFalse;$r.Rows[0].Reserved|Should -BeTrue
 }
}
