"""RC23 source, packaging and wiring regression tests (Python only).

These tests inspect exact source/PE/XML artifacts; they DO NOT execute PowerShell,
WPF, UAC or AD. Behavioral fixtures are in Run-Pesto23Tests.ps1 for Windows.
"""
from pathlib import Path
import json,re,sys,unittest
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools'),str(ROOT/'tests')]
from refresh_manifest import runtime_files,verify_runtime,verify_native_binding
from package_distribution import distribution_files
from ps_lexical import functions,tokens,smart_quote_hazards

class RC23(unittest.TestCase):
 def text(self,path):return (ROOT/path).read_text('utf-8-sig')
 def fn(self,file,name):
  s=self.text('wad/'+file);return s[slice(*functions(s)[name])]
 def test_01_modules_in_source_loader_and_native_binding(self):
  binding=verify_native_binding(ROOT)
  core=self.text('wad/Pesto-Core.ps1')
  for name in ('JoinRecovery','UXFlow'):
   path=f'wad/Pesto-{name}.ps1'
   self.assertIn(path,runtime_files(ROOT));self.assertIn(path,binding);self.assertIn(f'Pesto-{name}.ps1',core)
 def test_02_new_sources_have_balanced_delimiters_and_safe_quotes(self):
  for rel in ('wad/Pesto-JoinRecovery.ps1','wad/Pesto-UXFlow.ps1','tests/Run-Pesto23Tests.ps1'):
   text=self.text(rel);tokens(text);self.assertEqual(smart_quote_hazards(text),[],rel)
 def test_03_join_reader_is_closed_and_rejects_untyped_input(self):
  s=self.fn('Pesto-JoinRecovery.ps1','Assert-PestoJoinReceiptData')
  for evidence in ('Assert-PestoClosedObject','$Receipt.Schema -isnot [int]','Test-PestoGeneratedComputerName','Get-PestoDomainFromDN','DateTimeOffset','4096','8192'):
   self.assertIn(evidence,s)
  self.assertNotIn('Invoke-Expression',s)
 def test_04_receipt_reader_supports_legacy_but_requires_schema3_evidence(self):
  s=self.fn('Pesto-Safety.ps1','Read-PestoIntervention')
  self.assertIn('@(1,2,3)',s);self.assertIn("elseif($r.Schema -eq 3)",s)
  self.assertIn('$r.JoinEvidence.MachineId -ine $r.TargetMachineId',s)
  self.assertIn('Assert-PestoJoinEvidence',s)
 def test_05_baseline_persisted_before_actual_join(self):
  s=self.fn('Pesto-Join.ps1','Invoke-PestoJoinExecuteLocked')
  self.assertLess(s.index('Set-PestoInitialJoinObservation'),s.index('$action=AddToDomain'))
  s=self.fn('Pesto-JoinRecovery.ps1','Set-PestoInitialJoinObservation')
  self.assertIn('if($r.Baseline -or $r.JoinEvidence)',s);self.assertIn('AD=$null',s)
  self.assertIn('Write-PestoIntervention $r',s)
 def test_06_native_request_recorded_at_commit_boundary(self):
  s=self.fn('Pesto-Operations.ps1','AddToDomain')
  self.assertLess(s.index('Set-PestoJoinNativeStatus -Status Requested'),s.index('$change = @(Add-Computer @ac)'))
  s=self.fn('Pesto-JoinRecovery.ps1','Set-PestoJoinNativeStatus')
  self.assertIn("$Status -eq 'Accepted' -and $r.JoinEvidence.NativeStatus -ne 'Requested'",s)
  self.assertIn("@('Accepted','Refused')",s);self.assertIn('Write-PestoIntervention $r',s)
 def test_07_local_status_is_read_only_and_cannot_release_coordination(self):
  s=self.text('wad/Pesto-Join.ps1');a=s.index("if($Request.Mode -eq 'Status')");b=s.index('Import-PestoADModule',a)
  worker=s[a:b]
  self.assertIn('Read-PestoJoinReceipt -Path $Request.StatePath',worker)
  self.assertIn('return Get-PestoJoinReceiptStatus -Receipt $receipt -Domain $Request.Plan.Domain',worker)
  status=self.fn('Pesto-Join.ps1','Get-PestoJoinReceiptStatus')
  decision=self.fn('Pesto-Join.ps1','Get-PestoJoinReceiptDecision')
  for forbidden in ('Write-PestoJoinReceipt','Write-PestoIntervention','Exit-PestoCoordination',".Phase='Verified'",'-Repair'):
   self.assertNotIn(forbidden,worker+status+decision)
  self.assertIn('$local=Get-PestoJoinLocalStatus',status)
  self.assertIn('Test-ComputerSecureChannel -Server $Receipt.DC -ErrorAction Stop',status)
  self.assertIn('$secure -isnot [bool]',status);self.assertIn('$local.DomainRole -in @(1,3)',status)
  self.assertLess(status.index('$secure -isnot [bool]'),status.index('$local.SecureChannel=$secure'))
  self.assertIn('Get-PestoJoinReceiptDecision -Receipt $Receipt -Local $local -Domain $Domain',status)
 def test_08_completed_join_allows_optional_followup_only_after_coherent_reboot(self):
  s=self.fn('Pesto-Join.ps1','Get-PestoJoinReceiptDecision')
  self.assertIn('Assert-PestoJoinReceiptData',s)
  for guard in ('$Receipt.MachineId -ine $Local.MachineId','$Receipt.Domain -ine $Domain',
                '$boot -gt $before','$boot -gt [DateTimeOffset]::Parse($Receipt.Utc',
                '$Local.PartOfDomain -is [bool]','$Local.DomainRole -in @(1,3)',
                '$Local.Domain -ieq $Receipt.Domain','Test-PestoComputerName ([string]$Local.Computer)',
                '$Local.ActiveName -ieq $Local.Computer','$Local.ConfiguredName -ieq $Local.Computer',
                '-not $Local.PendingRename'):
   self.assertIn(guard,s)
  self.assertIn('if((Test-PestoOptionalPostCheckReceipt $Receipt) -and $isMatch -and $later -and $Local.SecureChannel -is [bool] -and $Local.SecureChannel)',s)
  self.assertIn("Blocked=$false;Phase='ReadyToObserve'",s)
  self.assertIn('reçu conservé sans certification AD',s)
  self.assertIn("Blocked=$true;Phase='PendingRestart'",s)
  self.assertIn("Blocked=$true;Phase='Uncertain'",s)
  self.assertNotIn("$Receipt.Phase=",s)
  classifier=self.fn('Pesto-Policy.ps1','Test-PestoOptionalPostCheckReceipt')
  self.assertIn("$Receipt.Phase -cne 'PendingRestart'",classifier)
  self.assertIn('$Receipt.ResultCode -in @(10,20,77)',classifier)
  self.assertIn('if(-not $accepted){return $false}',classifier)
  self.assertIn("$Receipt.$effect -cnotin @('NotRequested','Confirmed')",classifier)
  self.assertIn("$Receipt.JoinEvidence.NativeStatus -cne 'Accepted'",classifier)
  self.assertIn('Assert-PestoJoinReceiptData $Receipt',classifier)
 def test_09_join_observation_requires_machine_ad_ou_and_secure_channel(self):
  s=self.fn('Pesto-JoinRecovery.ps1','Get-PestoJoinObservationDecision')
  for guard in ('$LocalMachineId -ine $e.MachineId','$w.MachineId -ine $e.MachineId',"$w.DomainRole -notin @(1,3)",'$ad.OU -ine $p.OU_Destination','$Observation.JoinDestinationGuid -ine $p.TargetOUGuid','$e.BoundObjectGuid','$health.SecureChannel -is [bool]',"$health.SecureChannel -ceq 'Conforme'"):
   self.assertIn(guard,s)
 def test_10_all_observation_sources_must_be_fresh_and_boot_later(self):
  s=self.fn('Pesto-JoinRecovery.ps1','Get-PestoJoinObservationDecision')
  self.assertIn('@($Observation.ObservedUtc,$Observation.ADUtc,$Observation.WindowsUtc,$health.Utc)',s)
  self.assertIn('$age -lt 0 -or $age -gt 120',s)
  self.assertIn('$boot -le $before',s);self.assertIn('$boot -le [DateTimeOffset]::Parse($e.PreparedUtc',s)
 def test_11_join_decision_is_pure_and_not_a_retry_authorization(self):
  s=self.fn('Pesto-JoinRecovery.ps1','Get-PestoJoinObservationDecision')
  for forbidden in ('Write-Pesto','Add-Computer','Rename-Computer','Move-ADObject','Exit-PestoCoordination','$p.Objet_GUID=','$e.BoundObjectGuid=','$d.ResumeMove=$true'):
   self.assertNotIn(forbidden,s)
 def test_12_confirm_binds_guid_only_after_fresh_decision(self):
  s=self.fn('Pesto-Safety.ps1','Confirm-PestoInterventionObservation')
  self.assertLess(s.index('Get-PestoJoinObservationDecision'),s.index('$r.JoinEvidence.BoundObjectGuid='))
  self.assertLess(s.index('if(-not $decision.Verified'),s.index('$r.JoinEvidence.BoundObjectGuid='))
  self.assertIn('Get-ItemProperty',s);self.assertIn('$r.Schema=3',s)
  self.assertNotIn('$r.Plan.Objet_GUID=',s)
 def test_13_save_reading_never_resolves_and_preserves_new_schema(self):
  s=self.fn('Pesto-Safety.ps1','Save-PestoUnverifiedObservation')
  for forbidden in ('$r.Phase=','Exit-PestoCoordination','Remove-Item','$r.Plan.Objet_GUID='):
   self.assertNotIn(forbidden,s)
  self.assertIn('if($r.Schema -lt 2)',s);self.assertIn('Test-PestoJoinIntervention',s)
 def test_14_unknown_join_guid_can_open_ledger_observation(self):
  s=self.fn('Pesto-Inspection.ps1','Show-PestoPostState')
  self.assertIn("-and -not(Test-PestoJoinIntervention $receipt)",s)
  self.assertIn('Show-PestoHostedWindow $window',s)
  self.assertIn('try{Start-PestoPostStateRead;',s)
  self.assertNotIn('Add_ContentRendered',s)
  self.assertNotIn('$window.ShowDialog()',s)
  self.assertIn('Close-PestoStateWindow $window $null',s)
  self.assertIn('Invoke-PestoHostedKey',self.text('wad/Pesto-Workspace.ps1'))
  self.assertIn('-not $script:PestoReadOnly',self.fn('Pesto-Inspection.ps1','Complete-PestoPostStateRead'))
 def test_15_observation_uses_target_name_and_exact_destination(self):
  s=self.fn('Pesto-Inspection.ps1','Start-PestoPostStateRead')
  self.assertIn('$request.Computer=$p.Nouveau_Nom',s);self.assertIn('JoinTargetOU',s)
  s=self.fn('Pesto-Inspection.ps1','Get-PestoPostObservation')
  self.assertIn('Get-ADOrganizationalUnit -Identity ([string]$Request.JoinTargetOU)',s)
 def test_16_join_receipt_import_is_selected_local_and_not_destructive(self):
  s=self.fn('Pesto-JoinRecovery.ps1','ConvertFrom-PestoLegacyJoinReceipt')
  self.assertIn('$r.MachineId -ine $MachineId',s);self.assertIn('$r.Domain -ine $Domain',s)
  self.assertIn("Phase='Uncertain'",s);self.assertIn("NativeStatus='Unknown'",s)
  self.assertIn('Baseline=$null',s)
  for f in ('Remove-Item','$r.Account','Exit-PestoCoordination','$r.Phase='):self.assertNotIn(f,s)
 def test_17_legacy_join_import_is_wired_into_existing_import_path(self):
  s=self.fn('Pesto-Recovery.ps1','ConvertFrom-PestoLegacyState')
  self.assertIn('ConvertFrom-PestoLegacyJoinReceipt',s)
  s=self.text('wad/Pesto-Recovery.ps1');self.assertIn('JoinEvidence',s);self.assertIn("'LegacyJoinImported' 'UnverifiedEvidence'",s)
 def test_18_local_join_lock_sync_matches_exact_id_and_target(self):
  s=self.fn('Pesto-Interventions.ps1','Sync-PestoInterventionViews')
  for guard in ('Test-PestoJoinIntervention','$old.OperationId','$Receipt.OperationId','$old.MachineId','$old.NewName','$old.OU'):
   self.assertIn(guard,s)
  self.assertIn('Write-PestoJoinReceipt',s)
 def test_19_join_expected_values_are_not_source_name_or_empty_ou(self):
  for f in ('Get-PestoPostconditionChecklist','Get-PestoObservationComparison'):
   s=self.fn('Pesto-Contracts.ps1',f)
   self.assertIn('Test-PestoJoinIntervention',s);self.assertIn('$joining',s);self.assertRegex(s,r'\$(?:p|Plan)\.Nouveau_Nom');self.assertRegex(s,r'\$(?:p|Plan)\.OU_Destination')
 def test_20_primary_action_recomputes_and_routes_to_existing_safe_path(self):
  s=self.fn('Pesto-UXFlow.ps1','Invoke-PestoPrimaryAction')
  self.assertIn('$step=Get-PestoPrimaryContext',s);self.assertIn('Invoke-PestoUxReadComputer',s)
  self.assertIn('Start-PestoDirectPreflight -Execute',s)
  for f in ('$Sender.Tag','Add-Computer','Rename-Computer','Move-ADObject','Go -Renommer','Confirm $false'):self.assertNotIn(f,s)
 def test_21_primary_busy_consult_resume_and_prepare_are_distinct(self):
  s=self.fn('Pesto-UXFlow.ps1','Get-PestoPrimaryStep')
  self.assertLess(s.index('if($Busy)'),s.index('elseif($Blocked)'))
  self.assertIn('elseif($ReadOnly)',s);self.assertIn("Action='Prepare'",s.replace('$s.',''))
  self.assertIn('déplacer seulement',s)
 def test_22_primary_has_no_enter_default_and_join_review_has_help(self):
  ns={'x':'http://schemas.microsoft.com/winfx/2006/xaml'};attr='{'+ns['x']+'}Name'
  shell=ET.fromstring(self.text('wad/Pesto-Shell.xaml'));b=next(n for n in shell.iter() if n.get(attr)=='SuiteDirectRun')
  self.assertNotEqual(b.get('IsDefault','False'),'True');self.assertGreaterEqual(float(b.get('MinHeight','0')),42)
  join=ET.fromstring(self.text('wad/Pesto-Join.xaml'));b=next(n for n in join.iter() if n.get(attr)=='JnReview')
  self.assertTrue(b.get('ToolTip'));self.assertTrue(b.get('AutomationProperties.Name'))
  self.assertIn("Review='Invoke-PestoJoinReviewClick'",self.text('wad/Pesto-Join.ps1'))
 def test_23_metrics_run_after_endinvoke_and_cannot_change_callback_outcome(self):
  s=self.text('wad/Pesto-Async.ps1')
  tick=self.fn('Pesto-Async.ps1','Invoke-PestoAsyncTimerTick')
  self.assertLess(tick.index('EndInvoke('),tick.index('Add-PestoPerformanceSample -Name'))
  self.assertIn('catch{$script:PestoMetricsDropped=',s)
  self.assertIn('$Timing.WaitMs=',s);self.assertIn('$Timing.WorkMs=',s)
  self.assertIn('finally{if($work)',s)
 def test_24_metrics_bounded_local_redacted_no_business_success_claim(self):
  s=self.fn('Pesto-Names.ps1','Add-PestoPerformanceSample')
  self.assertIn('200',s);self.assertIn('^[A-Za-z]',s)
  self.assertNotIn('Credential',s);self.assertNotIn('ComputerName',s);self.assertNotIn('WriteAllText',s)
  self.assertIn('Returned',s)
  self.assertIn('Get-PestoPerformanceSummary',self.text('wad/Pesto-Workspace.ps1'))
 def test_25_release_gate_runs_target_tests_without_product_dependency(self):
  runtime=set(runtime_files(ROOT));prod=set(distribution_files(ROOT,'PROD'));dev=set(distribution_files(ROOT,'DEV'))
  self.assertNotIn('TEST_RC23.cmd',prod);self.assertIn('TEST_RC23.cmd',dev)
  self.assertNotIn('tests/Run-Pesto23Tests.ps1',runtime)
  self.assertIn('Run-Pesto23Tests.ps1',self.text('TESTER.cmd'));self.assertIn('rc23.json',self.text('tools/Verify-Release.ps1'))
  self.assertEqual({p.split('/')[0] for p in prod},{'Pesto.exe','wad'})
 def test_26_actual_pack_coherent_and_version_central(self):
  verify_runtime(ROOT);self.assertEqual(json.loads(self.text('tools/version.json'))['channel'],'Final')
  self.assertEqual(json.loads(self.text('wad/package.json'))['Version'],'1.0')

if __name__=='__main__':unittest.main(verbosity=2)
