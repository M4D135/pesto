import unittest,tempfile,json,hashlib,importlib.util,sys,zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('packs',Path(__file__).resolve().parents[2]/'tools/Build-PestoPacks.py')
packs=importlib.util.module_from_spec(spec);spec.loader.exec_module(packs)
class Packaging(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.base=Path(self.temp.name);self.src=self.base/'source';(self.src/'wad/support').mkdir(parents=True)
  self.records=[]
  for path,data in [('Pesto.exe',b'MZfixture'),('wad/Pesto-Core.ps1',b'# fixture core'),('wad/Pesto-Startup.ps1',b'# fixture startup')]:
   p=self.src/path;p.write_bytes(data);self.records.append({'path':path,'sha256':hashlib.sha256(data).hexdigest()})
  self.manifest();(self.src/'wad/cfg.json').write_text('{}');(self.src/'wad/support/DEBLOQUER_TOUT.cmd').write_text('@echo fixture')
 def tearDown(self):self.temp.cleanup()
 def manifest(self):(self.src/'wad/package.json').write_text(json.dumps({'files':self.records}))
 def test_two_roots(self):
  packs.build(self.src,self.base/'out');self.assertEqual({p.name for p in (self.base/'out/PROD').iterdir()},{'Pesto.exe','wad'})
  self.assertTrue((self.base/'out/PROD/wad/support/DEBLOQUER_TOUT.cmd').is_file())
 def test_support_optional(self):
  (self.src/'wad/support/DEBLOQUER_TOUT.cmd').unlink();packs.build(self.src,self.base/'out')
 def test_modified_engine_refused(self):
  (self.src/'wad/Pesto-Core.ps1').write_text('modified')
  with self.assertRaises(ValueError):packs.build(self.src,self.base/'out')
 def test_missing_engine_refused(self):
  (self.src/'wad/Pesto-Core.ps1').unlink()
  with self.assertRaises(ValueError):packs.build(self.src,self.base/'out')
 def test_configuration_not_hashed(self):
  (self.src/'wad/cfg.json').write_text('{"prepared":true}');packs.build(self.src,self.base/'out')
 def test_output_nested_refused(self):
  with self.assertRaises(ValueError):packs.build(self.src,self.src/'out')
 def test_existing_output_refused(self):
  (self.base/'out').mkdir()
  with self.assertRaises(FileExistsError):packs.build(self.src,self.base/'out')
 def test_traversal_refused(self):
  self.records.append({'path':'../escape','sha256':'0'*64});self.manifest()
  with self.assertRaises(ValueError):packs.build(self.src,self.base/'out')
 def test_optional_runtime_dependency_refused(self):
  p=self.src/'wad/support/tool.ps1';p.write_text('fixture');self.records.append({'path':'wad/support/tool.ps1','sha256':packs.digest(p)});self.manifest()
  with self.assertRaises(ValueError):packs.build(self.src,self.base/'out')
 def test_no_log_or_preference_in_dev(self):
  (self.src/'wad/logs').mkdir();(self.src/'wad/logs/secret.log').write_text('fixture');(self.src/'wad/gp.prefs.json').write_text('{}')
  packs.build(self.src,self.base/'out');self.assertFalse((self.base/'out/DEV/wad/logs').exists());self.assertFalse((self.base/'out/DEV/wad/gp.prefs.json').exists())
 def test_extra_unhashed_code_refused(self):
  (self.src/'wad/Pesto-Extra.ps1').write_text('fixture')
  with self.assertRaises(ValueError):packs.build(self.src,self.base/'out')
 def test_archives_no_extra_gp_folder(self):
  packs.build(self.src,self.base/'out')
  for kind in ('PROD','DEV'):
   with zipfile.ZipFile(self.base/'out'/('Pesto_'+kind+'.zip')) as z:
    self.assertTrue(all(p.startswith(kind+'/') for p in z.namelist()));self.assertIsNone(z.testzip())
if __name__=='__main__':unittest.main(verbosity=2)
