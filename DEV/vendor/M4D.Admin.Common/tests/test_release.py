import importlib.util, json, tempfile, unittest, hashlib
from unittest import mock
from pathlib import Path
spec=importlib.util.spec_from_file_location('release',Path(__file__).resolve().parents[1]/'tools/release.py');release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)
class ReleaseTests(unittest.TestCase):
 def test_added_api_is_compatible(self):self.assertTrue(release.check_compatibility({'Core':['A']},{'Core':['A','B']})['compatible'])
 def test_removed_api_refused(self):
  with self.assertRaises(ValueError):release.check_compatibility({'Core':['A']},{'Core':['B']})
 def test_version_order(self):self.assertGreater(release.version('0.2.0'),release.version('0.1.11'))
 def test_ambiguous_version_refused(self):
  for version in ('latest','1.0','0.2.0-preview','../1.0.0'):
   with self.assertRaises(ValueError):release.version(version)
 def test_downgrade_refused(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=root/'source';source.mkdir();(source/'manifest.json').write_text(json.dumps({'Version':'0.1.1'}))
   with self.assertRaises(ValueError):release.bundle(source,root/'out',{'Pesto':['Core']},'0.2.0')
   self.assertFalse((root/'out').exists())
 def test_bundle_contains_only_manifest_owned_runtime_and_locks(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=root/'source';source.mkdir();files=[]
   for name in ('M4D.Admin.Common.Core.dll','M4D.Admin.Common.Tests.Core.dll'):
    data=name.encode();(source/name).write_bytes(data);files.append({'Name':name,'Bytes':len(data),'SHA256':hashlib.sha256(data).hexdigest()})
   manifest={'Schema':1,'Version':'0.2.0','Repository':'fixture','SourceSHA256':'a'*64,'TargetFramework':'net472','LanguageVersion':'CSharp5','Builder':{},'Files':files}
   (source/'manifest.json').write_text(json.dumps(manifest))
   with mock.patch.object(release,'source_digest',return_value='a'*64), mock.patch.object(release.subprocess,'run',side_effect=[mock.Mock(stdout='a'*40),mock.Mock(stdout='')]):
    locks=release.bundle(source,root/'out',{'Pesto':['Core']})
   bundle_manifest=json.loads((root/'out/manifest.json').read_text())
   self.assertEqual(len(bundle_manifest['Files']),1)
   self.assertTrue(all((root/'out'/row['Name']).is_file() for row in bundle_manifest['Files']))
   self.assertFalse((root/'out/M4D.Admin.Common.Tests.Core.dll').exists())
   self.assertFalse(locks['Pesto']['SourceDirty'])
 def test_dirty_source_refused_without_development_switch(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=root/'source';source.mkdir();name='M4D.Admin.Common.Core.dll';(source/name).write_bytes(b'fixture')
   manifest={'Schema':1,'Version':'0.2.0','Repository':'fixture','SourceSHA256':'a'*64,'TargetFramework':'net472','LanguageVersion':'CSharp5','Builder':{},'Files':[{'Name':name,'Bytes':7,'SHA256':hashlib.sha256(b'fixture').hexdigest()}]}
   (source/'manifest.json').write_text(json.dumps(manifest))
   with mock.patch.object(release,'source_digest',return_value='a'*64), mock.patch.object(release.subprocess,'run',side_effect=[mock.Mock(stdout='a'*40),mock.Mock(stdout=' M source.cs')]):
    with self.assertRaises(ValueError):release.bundle(source,root/'out',{'Pesto':['Core']})
   self.assertFalse((root/'out').exists())
 def test_stale_dist_not_attributed_to_current_commit(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=root/'source';source.mkdir();(source/'manifest.json').write_text(json.dumps({'Version':'0.2.0','SourceSHA256':'a'*64}))
   with mock.patch.object(release,'source_digest',return_value='b'*64), mock.patch.object(release.subprocess,'run') as git:
    with self.assertRaisesRegex(ValueError,'Stale dist'):release.bundle(source,root/'out',{'Pesto':['Core']})
    git.assert_not_called()
   self.assertFalse((root/'out').exists())
 def test_source_digest_changes_when_build_or_source_changes(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);(root/'src/Core').mkdir(parents=True);(root/'tools').mkdir();(root/'version.json').write_text('{}');(root/'tools/build.ps1').write_text('build');(root/'src/Core/Test.cs').write_text('one')
   first=release.source_digest(root);(root/'src/Core/Test.cs').write_text('two');self.assertNotEqual(first,release.source_digest(root))
if __name__=='__main__':unittest.main()
