#requires -Version 5.1
# Pester 5.7.1; pure functions only, no real AD, UAC, WMI or files modified.
BeforeAll {
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
 foreach($relative in @('Pesto-Safety.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1')){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad\'+$relative)),[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ($errors.Message -join '; ')}
  $names=@('Get-PestoNativeFailureCode','Test-PestoInterventionConflict','Test-PestoLedgerResume','Get-PestoTaskDefinitionHash','Get-PestoEntraDisposition','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt')
  foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
   if($fn.Name -in $names){. ([scriptblock]::Create($fn.Extent.Text))}
  }
 }
}
Describe 'Native codes independent of language' {
 It 'Preserves Win32 code <Code>' -ForEach @( @{Code=5},@{Code=1314},@{Code=1326},@{Code=2732},@{Code=1722}) {
  Get-PestoNativeFailureCode ([ComponentModel.Win32Exception]::new($Code,'message traduit')) | Should -Be $Code
 }
}
Describe 'Entra decision before any removal' {
 It 'AD only never requests leave, even if permitted' {
  Get-PestoEntraDisposition "AzureAdJoined : NO`nDomainJoined : YES" $true | Should -BeExactly 'Skip'
 }
 It 'Hybrid disabled refuses, instead of silently proceeding' {
  Get-PestoEntraDisposition "AzureAdJoined : YES`nDomainJoined : YES" $false | Should -BeExactly 'Refuse'
 }
 It 'Hybrid approved requests preparation' {
  Get-PestoEntraDisposition "AzureAdJoined : YES`nDomainJoined : YES" $true | Should -BeExactly 'Leave'
 }
 It 'Missing or ambiguous status fails closed' {
  Get-PestoEntraDisposition "AzureAdJoined : YES`nAzureAdJoined : NO`nDomainJoined : YES" $true | Should -BeExactly 'Refuse'
  Get-PestoEntraDisposition '' $true | Should -BeExactly 'Refuse'
 }
}
Describe 'Persistent target conflicts' {
 BeforeEach {
  $plan=[pscustomobject]@{Domain='example.local';Objet_GUID='a';Nom_du_PC='OLD';Nouveau_Nom='NEW'}
  $receipt=[pscustomobject]@{Phase='Uncertain';Plan=$plan}
 }
 It 'Blocks matching unresolved target' { Test-PestoInterventionConflict $receipt $plan | Should -BeTrue }
 It 'Does not conflict after verification' { $receipt.Phase='Verified';Test-PestoInterventionConflict $receipt $plan | Should -BeFalse }
 It 'Does not equate two domains' {
  $other=[pscustomobject]@{Domain='other.local';Objet_GUID='a';Nom_du_PC='OLD';Nouveau_Nom='NEW'}
  Test-PestoInterventionConflict $receipt $other | Should -BeFalse
 }
}
Describe 'Task definition fingerprint' {
 It 'Changes if task contents change' {
  $a=Get-PestoTaskDefinitionHash '<Task>original</Task>'
  $b=Get-PestoTaskDefinitionHash '<Task>modified</Task>'
  $a | Should -Match '^[A-F0-9]{64}$';$a | Should -Not -Be $b
 }
 It 'Rejects absent and oversized content' {
  { Get-PestoTaskDefinitionHash '' } | Should -Throw
  { Get-PestoTaskDefinitionHash ('a'*131073) } | Should -Throw
 }
}
