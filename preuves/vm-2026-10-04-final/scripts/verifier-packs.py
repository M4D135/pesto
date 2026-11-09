from pathlib import Path
from zipfile import ZipFile
import json,hashlib,subprocess,datetime
base=Path(r'C:\PestoTest-run\packs-finaux-20261004');base.mkdir(exist_ok=False)
proof=Path(r'C:\PestoTest-preuves\2026-10-04-final')
results=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for channel in ('PROD','DEV'):
 archive=Path(r'C:\PestoTest-run')/('Pesto_'+channel+'.zip')
 dest=base/channel
 with ZipFile(archive) as z:z.extractall(dest)
 exe=dest/'Pesto.exe'
 if not exe.is_file():
  found=list(dest.rglob('Pesto.exe'));assert len(found)==1;exe=found[0];dest=exe.parent
 if channel=='PROD':assert sorted(p.name for p in dest.iterdir())==['Pesto.exe','wad']
 cfg=json.loads((dest/'wad/cfg.json').read_text(encoding='utf-8-sig'));assert cfg['Configured'] is False
 manifest=json.loads((dest/'wad/package.json').read_text(encoding='utf-8-sig'))
 for f in manifest['Files']:assert sha(dest/f['Path'])==f['SHA256'].lower()
 report=proof/('pack-'+channel+'-check.json')
 run=subprocess.run([str(exe),'--check-json',str(report)],capture_output=True,timeout=180)
 assert run.returncode==0,(channel,run.returncode)
 data=json.loads(report.read_text(encoding='utf-8-sig'))
 results.append({'Channel':channel,'ArchiveSHA256':sha(archive),'ExeSHA256':sha(exe),'Code':run.returncode,'ManifestFiles':len(manifest['Files']),'Configured':cfg['Configured'],'Check':data})
(proof/'packs-resultat.json').write_text(json.dumps({'Date':datetime.datetime.now().astimezone().isoformat(),'Results':results},indent=2),encoding='utf-8')
print(json.dumps(results,indent=2))
