from pathlib import Path
from zipfile import ZipFile
import datetime, hashlib, json, os, subprocess, sys
base=Path(r'C:\PestoTest-run\recette-update-20261004')
base.mkdir(exist_ok=False)
evidence=Path(r'C:\PestoTest-preuves\2026-10-04-final')
archive=Path(r'C:\PestoTest-run\Pesto_17_RC23_DEV.zip')
source=Path(r'C:\PestoTest-run\python-549a4aa\DEV')
with ZipFile(archive) as z:z.extractall(base/'rc23')
dest=base/'rc23'/'DEV'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def snapshot(root):return {str(p.relative_to(root)):sha(p) for p in root.rglob('*') if p.is_file()}
old=json.loads((dest/'wad/package.json').read_text(encoding='utf-8-sig'))
assert old['Version']=='17.0-RC23'
for f in old['Files']:assert sha(dest/f['Path'])==f['SHA256'].lower(),f['Path']
local=base/'profil-local';program=base/'donnees-programme'
# Données sentinelles de conservation : elles ne prétendent pas provenir d'une mutation AD réelle.
files={dest/'wad/cfg.json':b'{"Configured":true,"Recette":"Pesto-labo-sentinelle-20261004"}\r\n',dest/'wad/logs/recette.log':b'Journal RC23 conserve\r\n',local/'GP/preferences.json':b'{"Theme":"Dark","Recette":true}',local/'GP/State/recette/history-v1.json':b'{"Schema":1,"Entries":[]}',program/'GP/Join/recette.json':b'{"Schema":1,"Phase":"Verified","Recette":true}',program/'GP/Interventions/recette.json':b'{"Schema":3,"Phase":"Verified","Recette":true}'}
for p,b in files.items():p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
preserved_before={str(p):sha(p) for p in files}
env=dict(os.environ,LOCALAPPDATA=str(local),ProgramData=str(program),PYTHONIOENCODING='utf-8')
cmd=[sys.executable,'-X','utf8',str(source/'tools/update_installation.py'),'--source',str(source),'--destination',str(dest)]
def run(label,args):
 p=subprocess.run(args,env=env,capture_output=True)
 (evidence/(label+'-stdout.txt')).write_bytes(p.stdout);(evidence/(label+'-stderr.txt')).write_bytes(p.stderr)
 if p.returncode:raise RuntimeError(label+' code '+str(p.returncode))
 return json.loads(p.stdout)
before=snapshot(base)
preview=run('5.5-apercu',cmd)
assert snapshot(base)==before,'Apercu modifie les fichiers'
applied=run('5.5-application',cmd+['--apply'])
assert applied['Updated'] and applied['ConfigPreserved'] and applied['Version']=='1.0'
after=json.loads((dest/'wad/package.json').read_text(encoding='utf-8-sig'))
for f in after['Files']:assert sha(dest/f['Path'])==f['SHA256'].lower(),f['Path']
assert all(sha(p)==preserved_before[str(p)] for p in files),'Donnee sentinelle modifiee'
assert not (dest/'.pesto-update.lock').exists()
report={'Date':datetime.datetime.now().astimezone().isoformat(),'Python':sys.version,'ArchiveSHA256':sha(archive),'BeforeVersion':old['Version'],'AfterVersion':after['Version'],'PreviewUnchanged':True,'PreservedSHA256':preserved_before,'RuntimeComponents':len(after['Files']),'ExeSHA256':sha(dest/'Pesto.exe'),'Backup':applied['Backup'],'RealAD':False}
(evidence/'5.5-resultat.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
# 5.6 : interruption réelle d'un processus de mise à jour sur cette copie seulement.
# Point d'injection interne utilisé par les tests ; os._exit évite tout rollback Python.
code="import sys;from pathlib import Path;sys.path.insert(0,sys.argv[1]);from update_installation import apply_update;apply_update(Path(sys.argv[2]),Path(sys.argv[3]),_crash_after=1)"
p=subprocess.run([sys.executable,'-c',code,str(source/'tools'),str(source),str(dest)],env=env,capture_output=True)
assert p.returncode==93,p.returncode
lock=dest/'.pesto-update.lock';lockhash=sha(lock)
check=subprocess.run([str(dest/'Pesto.exe'),'--check','--quiet'],capture_output=True)
assert check.returncode==126,check.returncode
recovery=run('5.6-recuperation-apercu',[sys.executable,str(source/'tools/update_installation.py'),'--destination',str(dest),'--recover'])
assert sha(lock)==lockhash
(evidence/'5.6-resultat.json').write_text(json.dumps({'Date':datetime.datetime.now().astimezone().isoformat(),'CrashExit':p.returncode,'LauncherExit':check.returncode,'LockSHA256':lockhash,'LockPreserved':True,'Destination':str(dest),'Recovery':recovery},indent=2),encoding='utf-8')
print('5.6 PASS : verrou conserve, code 126, recuperation en apercu seulement.')
