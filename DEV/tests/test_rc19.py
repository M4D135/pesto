"""Portable RC19 checks of actual artifacts. Not execution of PowerShell/AD."""
import hashlib,json,re,sys,tempfile,unittest,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(ROOT/'tests'))
from refresh_manifest import runtime_files,verify_native_binding,write_manifest,verify_runtime
from ps_lexical import functions,tokens
class RC19(unittest.TestCase):
 def test_binding_covers_every_immutable_component(self):
  d=verify_native_binding(ROOT);self.assertEqual(set(d),set(runtime_files(ROOT)) - {'Pesto.exe'})
 def test_manifest_rehash_cannot_hide_changed_runtime_from_exe(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td)
   for rel in (*runtime_files(ROOT),'wad/package.json'):
    p=d/rel;p.parent.mkdir(exist_ok=True,parents=True);shutil.copy2(ROOT/rel,p)
   with (d/'wad/Pesto-Operations.ps1').open('ab') as f:f.write(b'\n# changed source')
   with self.assertRaisesRegex(ValueError,'EXE was built'):write_manifest(d)
 def test_runtime_help_does_not_require_optional_files(self):
  text=(ROOT/'tools/launcher/Pesto-launcher.c').read_text()
  self.assertLess(text.index('W("--help")'),text.index('pesto_verify_runtime()'))
 def test_support_location_only_and_root_policies(self):
  self.assertTrue((ROOT/'wad/support/DEBLOQUER_TOUT.cmd').is_file());self.assertFalse((ROOT/'DEBLOQUER_TOUT.cmd').exists())
  t=(ROOT/'wad/support/DEBLOQUER_TOUT.cmd').read_text();self.assertIn('$support.Parent.Parent',t);self.assertIn('Unblock-File -LiteralPath',t)
  for forbidden in ['Set-ExecutionPolicy','Set-MpPreference','DisableRealtimeMonitoring','Set-Acl']:
   self.assertNotIn(forbidden,t)
 def test_nested_dsreg_logic_serialized_with_remote_helper(self):
  t=(ROOT/'wad/Pesto-Operations.ps1').read_text('utf-8-sig');f=functions(t);body=t[slice(*f['Invoke-PestoDsregLeaveLocal'])]
  self.assertIn('function Get-PestoEntraDisposition',body)
  self.assertLess(body.index("$disposition -eq 'Skip'"),body.index("-Argument '/leave'"))
 def test_no_positive_shutdown_delay_on_mutation_paths(self):
  t=(ROOT/'wad/Pesto-Operations.ps1').read_text('utf-8-sig');f=functions(t);body=t[slice(*f['Request-ComputerReboot'])]
  self.assertIn('-gt 0',body);self.assertNotRegex(body,r'/t\s+(?:[1-9]\d*)')
  self.assertNotRegex((ROOT/'wad/Pesto-Core.ps1').read_text('utf-8-sig'),r'Request-ComputerReboot[^\n]*-Delay\s+[1-9]')
 def test_runtime_source_naming_and_all_functions_unique(self):
  seen={}
  for path in (ROOT/'wad').glob('Pesto-*.ps1'):
   text=path.read_text('utf-8-sig');tokens(text)
   for fn in functions(text):self.assertNotIn(fn,seen,fn);seen[fn]=path.name
  for required in ['Start-PestoIntervention','Complete-PestoIntervention','Set-PestoTaskEvidence','Show-PestoInterventions','ConvertTo-PestoPreparation']:
   self.assertIn(required,seen)
 def test_neutral_configuration_is_explicit(self):
  cfg=json.loads((ROOT/'wad/cfg.json').read_text('utf-8-sig'))
  self.assertIs(cfg.get('Configured'),False);self.assertEqual(cfg['SchemaVersion'],2);self.assertNotIn('Conf',cfg)
 def test_ps_sources_and_cmd_encodings(self):
  for path in (ROOT/'wad').glob('Pesto-*.ps1'):self.assertTrue(path.read_bytes().startswith(b'\xef\xbb\xbf'),path.name)
  for path in (ROOT/'wad/support').glob('*.cmd'):self.assertIn(b'\r\n',path.read_bytes())
 def test_no_name_based_ad_imports(self):
  for path in (ROOT/'wad').glob('Pesto-*.ps1'):
   self.assertNotRegex(path.read_text('utf-8-sig'),r'Import-Module\s+(?:-Name\s+)?[\'\"]?ActiveDirectory(?:[\'\"]|\s)',path.name)
 def test_preparation_has_closed_nonsecret_fields(self):
  text=(ROOT/'wad/Pesto-Preparation.ps1').read_text('utf-8-sig');body=text[slice(*functions(text)['ConvertTo-PestoPreparation'])]
  self.assertIn("@('Schema','Domain','ConfigStamp','Org','Site','Service','Type')",body)
  for value in ['Credential','Reboot','Nom_du_PC','Nouveau_Nom','Password']:self.assertNotIn(value,body)
 def test_runtime_version_consistency(self):
  self.assertEqual(json.loads((ROOT/'wad/package.json').read_text())['Version'],'1.0')
  for path in (ROOT/'wad').glob('Pesto-*.ps1'):
   self.assertNotRegex(path.read_text('utf-8-sig'),r"17\.0-RC(?:16|17|18)(?:['\"]|\b)",path.name)
if __name__=='__main__':unittest.main(verbosity=2)
