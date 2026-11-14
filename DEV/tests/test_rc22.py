"""RC22 checks: Python filesystem recovery and source/XAML contract inspection.

No test in this module executes PowerShell, WPF, the EXE or AD.
"""
import hashlib,json,os,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest import mock
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(ROOT/'tests'))
from refresh_manifest import runtime_files,verify_runtime,verify_native_binding,file_hash
import update_installation as update
from ps_lexical import functions,tokens,smart_quote_hazards

class RecoveryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='pesto22-update-');self.base=Path(self.tmp.name).resolve();self.dest=self.base/'installed';self.dest.mkdir()
  for rel in (*runtime_files(ROOT),'wad/package.json'):
   p=self.dest/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
  (self.dest/'wad/cfg.json').write_text('{"private":"preserve"}')
  # Previous-code fixture differs in executable AND script. Rebind the data hashes
  # without invoking Windows. This is an unsigned fixture, not a publisher signature.
  core=self.dest/'wad/Pesto-Core.ps1';old=file_hash(core);core.write_bytes(core.read_bytes()+b'\n# Previous-code fixture only\n');new=file_hash(core)
  exe=self.dest/'Pesto.exe';data=exe.read_bytes()
  self.assertEqual(data.count(bytes.fromhex(old)),1)
  self.assertEqual(data.count(old.encode()),1)
  exe.write_bytes(data.replace(bytes.fromhex(old),bytes.fromhex(new)).replace(old.encode(),new.encode()))
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());
  for entry in m['Files']:entry['SHA256']=file_hash(self.dest/entry['Path'])
  p.write_text(json.dumps(m))
  verify_runtime(self.dest)
  self.before={p:file_hash(self.dest/p) for p in (*runtime_files(ROOT),'wad/package.json')}
 def tearDown(self):self.tmp.cleanup()
 def crash(self,count):
  code='import sys;sys.path.insert(0,sys.argv[1]);from update_installation import apply_update;from pathlib import Path;apply_update(Path(sys.argv[2]),Path(sys.argv[3]),_crash_after=int(sys.argv[4]))'
  r=subprocess.run([sys.executable,'-c',code,str(ROOT/'tools'),str(ROOT),str(self.dest),str(count)],capture_output=True,text=True,timeout=15)
  self.assertEqual(r.returncode,93,r.stderr)
  self.assertTrue((self.dest/'.pesto-update.lock').is_file())
 def crash_stage(self,stage,code):
  src='import sys;sys.path.insert(0,sys.argv[1]);from update_installation import apply_update;from pathlib import Path;apply_update(Path(sys.argv[2]),Path(sys.argv[3]),_crash_stage=sys.argv[4])'
  r=subprocess.run([sys.executable,'-c',src,str(ROOT/'tools'),str(ROOT),str(self.dest),stage],capture_output=True,text=True,timeout=30)
  self.assertEqual(r.returncode,code,r.stderr);self.assertTrue((self.dest/'.pesto-update.lock').is_file())
 def test_interrupted_preparation_is_released_after_verification(self):
  self.crash_stage('preparing',94)
  self.assertEqual(self.before,{p:file_hash(self.dest/p) for p in self.before})
  preview=update.recover_update(self.dest);self.assertEqual(preview['Kind'],'ReleaseInterruptedPreparation');self.assertTrue((self.dest/'.pesto-update.lock').exists())
  self.assertTrue(update.recover_update(self.dest,apply=True)['Recovered']);self.assert_previous()
  self.assertEqual((self.dest/'wad/cfg.json').read_text(),'{"private":"preserve"}')
  update.apply_update(ROOT,self.dest);verify_runtime(self.dest)
 def test_interrupted_preparation_with_modified_code_keeps_fence(self):
  self.crash_stage('preparing',94);(self.dest/'wad/Pesto-Core.ps1').write_text('foreign edit')
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
  self.assertTrue((self.dest/'.pesto-update.lock').exists())
 def test_crash_after_completed_update_keeps_new_code(self):
  self.crash_stage('completed',95)
  preview=update.recover_update(self.dest);self.assertEqual(preview['Kind'],'ReleaseCompletedUpdate')
  self.assertTrue(update.recover_update(self.dest,apply=True)['Recovered'])
  self.assertFalse((self.dest/'.pesto-update.lock').exists());verify_runtime(self.dest)
  self.assertEqual(file_hash(self.dest/'Pesto.exe'),file_hash(ROOT/'Pesto.exe'))
  self.assertEqual((self.dest/'wad/cfg.json').read_text(),'{"private":"preserve"}')
 def assert_previous(self):
  self.assertEqual(self.before,{p:file_hash(self.dest/p) for p in self.before});verify_runtime(self.dest)
  self.assertFalse((self.dest/'.pesto-update.lock').exists())
 def test_process_termination_at_every_copy_boundary(self):
  for count in range(1,len(runtime_files(ROOT))+2):
   with self.subTest(boundary=count):
    self.crash(count)
    preview=update.recover_update(self.dest)
    self.assertFalse(preview['Conflicts']);self.assertTrue((self.dest/'.pesto-update.lock').exists())
    self.assertTrue(update.recover_update(self.dest,apply=True)['Recovered']);self.assert_previous()
 def test_completed_update_uses_new_bytes(self):
  update.apply_update(ROOT,self.dest);verify_runtime(self.dest)
  self.assertEqual(file_hash(self.dest/'Pesto.exe'),file_hash(ROOT/'Pesto.exe'))
  self.assertNotEqual(file_hash(self.dest/'wad/Pesto-Core.ps1'),self.before['wad/Pesto-Core.ps1'])
 def test_crash_recovery_does_not_overwrite_changed_configuration(self):
  self.crash(3);cfg=self.dest/'wad/cfg.json';cfg.write_text('{"changed":"keep me"}')
  update.recover_update(self.dest,apply=True);self.assertEqual(cfg.read_text(),'{"changed":"keep me"}');self.assert_previous()
 def test_conflicting_code_edit_refuses_all_recovery_writes(self):
  self.crash(2);target=self.dest/'wad/Pesto-Core.ps1';target.write_text('foreign edit')
  before={p.relative_to(self.dest).as_posix():file_hash(p) for p in self.dest.rglob('*') if p.is_file()}
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
  self.assertEqual(before,{p.relative_to(self.dest).as_posix():file_hash(p) for p in self.dest.rglob('*') if p.is_file()})
 def test_tampered_backup_refused_and_lock_retained(self):
  self.crash(3);lock=json.loads((self.dest/'.pesto-update.lock').read_text());p=Path(lock['Backup'])/'old/Pesto.exe';p.write_bytes(b'tamper')
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
  self.assertTrue((self.dest/'.pesto-update.lock').exists())
 def test_traversing_journal_refused_even_if_lock_hash_changed(self):
  self.crash(3);lp=self.dest/'.pesto-update.lock';lock=json.loads(lp.read_text());jp=Path(lock['Backup'])/'transaction.json';journal=json.loads(jp.read_text());journal['Records'][0]['Path']='../outside'
  jp.write_text(json.dumps(journal));lock['JournalSHA256']=file_hash(jp);lp.write_text(json.dumps(lock))
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
 def test_external_backup_refused(self):
  self.crash(1);lp=self.dest/'.pesto-update.lock';v=json.loads(lp.read_text());v['Backup']=str(self.base/'not-a-recorded-backup');lp.write_text(json.dumps(v))
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
 def test_linked_destination_refused_without_touching_outside(self):
  self.crash(1);target=self.dest/'wad/Pesto-Core.ps1';target.unlink();external=self.base/'outside';external.write_text('outside');target.symlink_to(external)
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
  self.assertEqual(external.read_text(),'outside')
 def test_incomplete_rollback_keeps_lock_until_explicit_recovery(self):
  replace=update._replace_from
  def fail_rollback(source,target):
   if 'old' in source.parts:raise OSError('backup temporarily unavailable')
   return replace(source,target)
  with mock.patch.object(update,'_replace_from',side_effect=fail_rollback):
   with self.assertRaises(RuntimeError):update.apply_update(ROOT,self.dest,_inject_after=len(runtime_files(ROOT))+1)
  self.assertTrue((self.dest/'.pesto-update.lock').exists())
  update.recover_update(self.dest,apply=True);self.assert_previous()
 def test_exception_after_actual_replace_is_also_rolled_back(self):
  replace=update._replace_from;raised=[False]
  def fail_after_replace(source,target):
   replace(source,target)
   if target.is_relative_to(self.dest) and not raised[0]:raised[0]=True;raise OSError('raised after replace')
  with mock.patch.object(update,'_replace_from',side_effect=fail_after_replace):
   with self.assertRaises(OSError):update.apply_update(ROOT,self.dest)
  self.assert_previous()
 def test_uninitialized_fence_is_not_silently_deleted(self):
  lock=self.dest/'.pesto-update.lock';lock.write_text('{"Schema":1,"Stage":"Preparing"}')
  with self.assertRaises(ValueError):update.recover_update(self.dest,apply=True)
  self.assertTrue(lock.exists())

class SourceContracts(unittest.TestCase):
 def text(self,path):return (ROOT/path).read_text('utf-8-sig')
 def body(self,path,name):
  s=self.text('wad/'+path);a,b=functions(s)[name];return s[a:b]
 def test_smart_quotes_in_current_runtime_and_test_sources_are_escaped(self):
  for folder,pattern in [('wad','Pesto-*.ps1'),('tests','*.ps1'),('tools','*.ps1')]:
   for p in (ROOT/folder).glob(pattern):self.assertEqual(smart_quote_hazards(p.read_text('utf-8-sig')),[],p.name)
 def test_smart_quote_lint_detects_matching_literal_delimiters(self):
  self.assertEqual(len(smart_quote_hazards("Write-Output 'l’identité'")),1)
  self.assertEqual(len(smart_quote_hazards('Write-Output "dire “non”"')),2)
 def test_smart_quote_lint_preserves_escaped_and_literal_heredocs(self):
  self.assertFalse(smart_quote_hazards("Write-Output 'l’’identité'"))
  self.assertFalse(smart_quote_hazards('Write-Output "dire `“non`”"'))
  self.assertFalse(smart_quote_hazards("@'\n l’identité \n'@"))
  self.assertFalse(smart_quote_hazards("# l’identité\n$x=1"))
 def test_smart_quote_lint_checks_nested_expressions(self):
  self.assertEqual(len(smart_quote_hazards('"$(Write-Output \'l’identité\')"')),1)
 def test_all_current_powershell_balanced_including_new_helpers(self):
  for p in (ROOT/'wad').glob('Pesto-*.ps1'):tokens(p.read_text('utf-8-sig'))
  tokens(self.text('tests/Run-Pesto22Tests.ps1'))
 def test_actual_xml_templates_parse_in_new_panels(self):
  import re
  for p in ('wad/Pesto-Workspace.ps1','wad/Pesto-Inspection.ps1','wad/Pesto-Interventions.ps1'):
   for match in re.finditer(r"\[xml\]\$\w+\s*=\s*@'\n(.*?)\n'@",self.text(p),re.S):ET.fromstring(match.group(1))
 def test_results_preserve_confirmed_move_and_unknown_outcome(self):
  s=self.body('Pesto-Safety.ps1','Complete-PestoIntervention');self.assertIn("$r.Move -in @('Requested','Confirmed')",s)
  s=self.body('Pesto-Contracts.ps1','Get-PestoOutcome');self.assertTrue(s.rstrip().endswith("return 'Uncertain'\n}"))
 def test_observation_recording_never_resolves_receipt(self):
  s=self.body('Pesto-Safety.ps1','Save-PestoUnverifiedObservation')
  for forbidden in ("$r.Phase=",'Exit-PestoCoordination','Remove-Item','Rename-Computer','Move-ADObject'):self.assertNotIn(forbidden,s)
  self.assertIn('ExpectedPlanFingerprint',s);self.assertIn('snapshot.AD.Guid',s)
 def test_baseline_recorded_before_rename_effects(self):
  s=self.body('Pesto-Safety.ps1','Assert-PestoRenameTarget')
  self.assertLess(s.index('Set-PestoInitialObservation'),s.index('Set-PestoEffect -Name TargetMachineId'))
  s=self.body('Pesto-Operations.ps1','MoveComputer')
  self.assertLess(s.index('Set-PestoInitialObservation'),s.index('Set-ADObject'))
  self.assertNotIn('$script:ActiveIntervention.Plan.Objet_GUID=',s)
 def test_snapshot_contract_never_serializes_full_request(self):
  s=self.body('Pesto-Contracts.ps1','ConvertTo-PestoObservationSnapshot')
  self.assertNotIn('ConvertTo-Json',s);self.assertNotIn('Credential=',s);self.assertNotIn('Errors=',s)
 def test_palette_search_is_local_and_does_not_launch_on_typing(self):
  s=self.body('Pesto-Contracts.ps1','Find-PestoCommands')
  self.assertNotIn('Get-AD',s);self.assertNotIn('Invoke-PestoWorkspaceAction',s)
  self.assertIn('-SearchChoices',self.body('Pesto-Workspace.ps1','Show-PestoWorkspace'))
 def test_readonly_reviews_are_wired_to_worker_and_manifest(self):
  self.assertIn('wad/Pesto-Review.ps1',runtime_files(ROOT));self.assertIn('Pesto-Review.ps1',self.text('wad/Pesto-Core.ps1'))
  s=self.body('Pesto-Review.ps1','Start-PestoInventoryReview');self.assertIn('Start-PestoAsyncOperation',s)
  for n in ('Get-PestoCapacityRows','Get-PestoConformityRows'):
   s=self.body('Pesto-Review.ps1',n)
   for verb in ('Get-ADComputer','Move-ADObject','Set-ADObject','Add-Computer','Start-Process'):self.assertNotIn(verb,s)
 def test_observed_ou_metadata_not_reconstructed_from_labels(self):
  s=self.text('wad/Pesto-Directory.ps1');self.assertIn('DN=[string]$child.DistinguishedName',s)
  self.assertIn('Guid=[string]$child.ObjectGUID',s)
  self.assertIn('$target=$candidates[0].DN',self.body('Pesto-Review.ps1','Get-PestoConformityRows'))
 def test_table_settings_are_not_written_at_initialization(self):
  s=self.body('Pesto-Tables.ps1','Apply-PestoSavedTables');self.assertNotIn('Set-PestoAppearanceValue',s)
  s=self.body('Pesto-Tables.ps1','ConvertTo-PestoTablePreferences');self.assertNotIn("'Reboot'",s);self.assertNotIn("'SelectedItem'",s)
 def test_native_fence_before_hashes_and_powershell(self):
  s=self.text('tools/launcher/Pesto-launcher.c');self.assertLess(s.index('GetFileAttributesW(logpath)'),s.index('pesto_verify_runtime()'))
  self.assertLess(s.index('GetFileAttributesW(logpath)'),s.index('if(!CreateProcessW'))
 def test_new_features_have_native_binding(self):
  self.assertIn('wad/Pesto-Review.ps1',verify_native_binding(ROOT));self.assertIn('wad/Pesto-Tables.ps1',verify_native_binding(ROOT))

if __name__=='__main__':unittest.main(verbosity=2)
