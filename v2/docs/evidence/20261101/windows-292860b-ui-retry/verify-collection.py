from pathlib import Path
import hashlib,json,zipfile,shutil
scratch=Path(__file__).resolve().parent
receipt=json.loads((scratch/'ui-retry2-collection-local.json').read_text(encoding='utf-8-sig'))
archive=scratch/'ui-retry2-evidence.zip'
assert archive.stat().st_size==receipt['zipBytes']
assert hashlib.file_digest(archive.open('rb'),'sha256').hexdigest()==receipt['zipSha256']
assert receipt['taskRemoved'] is True
with zipfile.ZipFile(archive) as z:
 for f in z.infolist():
  rel=Path(f.filename.replace('\\','/'))
  assert not rel.is_absolute() and '..' not in rel.parts
  if f.is_dir():continue
  p=scratch/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(f))
root=scratch/'ui-retry2-evidence'
read=lambda p: json.loads((root/p).read_text(encoding='utf-8-sig'))
collection=read('collection.json')
for f in collection['files']:
 p=root/f['path'];assert p.stat().st_size==f['bytes']
 assert hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==f['sha256'],str(p)
assert read('ui-retry2-result.json')['success'] is True
summary={'kind':'pesto.isolated-native-update-ui-local-verification','sourceCommit':'292860b934bcdff0f1321b0839158bf38b58816e','fullReleaseQualification':False,'filesVerified':len(collection['files']),'channels':[]}
for channel in ['PROD','DEV']:
 base=f'ui-retry2-{channel}/transaction-evidence'
 proof=read(base+'/ui-proof.json')
 for f in ['success','nativeUpdateInstallFromUiQualified','nativeServiceRollbackQualified','parentClosed','helperLaunched','sourceUnchanged','profileSentinelUnchanged','profileDataPreserved','profileDataRemoved','ownedInstallationRemoved','distinctBuilds','zipAcquisitionQualified']:assert proof[f] is True,(channel,f)
 for f in ['nativeRollbackFromUiQualified','syntheticVersions','adQualification','adExecuted','realUac','ordinaryProfileAccess','uncQualification']:assert proof[f] is False,(channel,f)
 assert proof['channel']==channel
 assert proof['current']['version']=='2.0.8' and proof['current']['sourceCommit']=='aeb00259b3ef094e14c584559b788433aea38901'
 assert proof['target']['version']=='2.0.9' and proof['target']['sourceCommit']==summary['sourceCommit']
 assert proof['current']['executableSha256']=='2aa0b2458115aa6bfd9a364137f4826ea3c16f32cfde4d28a0d84a844659c4bf'
 assert proof['target']['executableSha256']=='9fc18bea30b56811f503e3255cff4486f37706a58c0c76e698ee40199cc32268'
 assert proof['installation']['status']=='completed' and proof['installation']['executableSha256']==proof['target']['executableSha256']
 assert proof['rollback']['status']=='rolledBack' and proof['rollback']['executableSha256']==proof['current']['executableSha256'] and proof['rollback']['healthAttemptCount']==2
 observations=list((root/base).rglob('observation-*.json'));assert len(observations)==2
 for p in observations:
  obs=json.loads(p.read_text(encoding='utf-8-sig'))
  assert obs['success'] is True and obs.get('diagnosticOnly',False) is False
  assert obs['journalReadPolicy']=='owned-dialog-exit-or-attributed-checking-child'
  assert obs['dialogDeadlinePolicy']=='30s-from-owned-dialog-observation-through-helper-exit'
  assert obs['dialogClosed'] and obs['ownedDialogElapsedMilliseconds']<30000 and obs['helperExitCode']==0
 summary['channels'].append({'channel':channel,'uiInstall':'2.0.8 to 2.0.9','serviceRollback':'2.0.9 to 2.0.8','observations':2})
(scratch/'ui-retry2-verified.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
