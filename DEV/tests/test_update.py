import json,sys,tempfile,unittest,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from refresh_manifest import VERSION, runtime_files,verify_runtime,file_hash
from update_installation import plan_update,apply_update
class UpdateTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name);self.dest=self.base/'installed';self.dest.mkdir()
  for rel in (*runtime_files(ROOT),'wad/package.json'):
   p=self.dest/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
  (self.dest/'wad/cfg.json').write_text('{"PRIVATE-CONFIG":"preserve"}')
  (self.dest/'wad/gp.prefs.json').write_text('PREFERENCE-CANARY')
 def tearDown(self):self.tmp.cleanup()
 def test_preview_changes_nothing(self):
  before={p.relative_to(self.dest).as_posix():file_hash(p) for p in self.dest.rglob('*') if p.is_file()}
  plan=plan_update(ROOT,self.dest);self.assertNotIn('wad/cfg.json',plan['Files'])
  self.assertEqual(before,{p.relative_to(self.dest).as_posix():file_hash(p) for p in self.dest.rglob('*') if p.is_file()})
 def test_update_preserves_config_and_preferences(self):
  result=apply_update(ROOT,self.dest);self.assertTrue(result['Updated']);verify_runtime(self.dest)
  self.assertIn('PRIVATE-CONFIG',(self.dest/'wad/cfg.json').read_text());self.assertEqual((self.dest/'wad/gp.prefs.json').read_text(),'PREFERENCE-CANARY')
  self.assertTrue((Path(result['Backup'])/'update-plan.json').exists())
 def test_rollback_for_each_copy_boundary(self):
  for count in range(1,len(runtime_files(ROOT))+2):
   with self.subTest(after=count):
    with self.assertRaises(OSError):apply_update(ROOT,self.dest,_inject_after=count)
    verify_runtime(self.dest);self.assertFalse((self.dest/'.pesto-update.lock').exists())
    self.assertIn('PRIVATE-CONFIG',(self.dest/'wad/cfg.json').read_text())
 def test_tampered_installed_file_refused(self):
  (self.dest/'wad/Pesto-Core.ps1').write_text('tamper')
  with self.assertRaises(ValueError):apply_update(ROOT,self.dest)
 def test_existing_update_lock_refused(self):
  p=self.dest/'.pesto-update.lock';p.write_text('existing')
  with self.assertRaises(FileExistsError):apply_update(ROOT,self.dest)
  self.assertEqual(p.read_text(),'existing')
 def test_same_or_nested_source_refused(self):
  with self.assertRaises(ValueError):plan_update(ROOT,ROOT)
 def test_linked_configuration_refused(self):
  p=self.dest/'wad/cfg.json';p.unlink();external=self.base/'outside.json';external.write_text('{}');p.symlink_to(external)
  with self.assertRaises(ValueError):apply_update(ROOT,self.dest)
 def test_wrong_schema_refused(self):
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());m['Scope']='Development';p.write_text(json.dumps(m))
  with self.assertRaises(ValueError):apply_update(ROOT,self.dest)
 def test_normal_update_allowed(self):
  result=apply_update(ROOT,self.dest);self.assertTrue(result['Updated'])
 def test_installed_manifest_without_file_version_tolerated(self):
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());m.pop('FileVersion',None);p.write_text(json.dumps(m))
  plan=plan_update(ROOT,self.dest);self.assertEqual(plan['Version'],VERSION)
 def test_downgrade_from_1_99_refused(self):
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());m['Version']='1.99';m.pop('FileVersion',None);p.write_text(json.dumps(m))
  with self.assertRaises(ValueError):plan_update(ROOT,self.dest)
 def test_downgrade_refused(self):
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());m['FileVersion']='1.0.1.0';p.write_text(json.dumps(m))
  with self.assertRaises(ValueError):plan_update(ROOT,self.dest)
  with self.assertRaises(ValueError):apply_update(ROOT,self.dest)
 def test_downgrade_allowed_with_flag(self):
  p=self.dest/'wad/package.json';m=json.loads(p.read_text());m['FileVersion']='1.0.1.0';p.write_text(json.dumps(m))
  plan=plan_update(ROOT,self.dest,allow_downgrade=True);self.assertEqual(plan['Version'],VERSION)
  result=apply_update(ROOT,self.dest,allow_downgrade=True);self.assertTrue(result['Updated'])
if __name__=='__main__':unittest.main(verbosity=2)
