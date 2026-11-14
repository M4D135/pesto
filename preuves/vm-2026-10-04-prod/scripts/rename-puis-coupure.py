import subprocess,json,datetime,time
from pathlib import Path
p=Path('/Users/david/Documents/Codex/2026-10-04/co-3/work/prod-validation')
g='/Users/david/Projects/pesto/outils/labo/mac/g.sh'
vbox='"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe" controlvm PESTO-W11-TEST setlinkstate2 '
record={'Date':datetime.datetime.now().astimezone().isoformat(),'VM':'PESTO-W11-TEST','NIC':2,'NewName':'V999004AAQA1004'}
probe='if exist C:\\PestoTest-run\\reseau-rename-ready.txt (echo READY) else (echo WAIT)'
assert 'WAIT' in subprocess.check_output([g,probe],text=True)
child=subprocess.Popen([g,'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\reseau-apres-rename.ps1'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
try:
 end=time.monotonic()+90
 while time.monotonic()<end:
  if child.poll() is not None:raise RuntimeError('worker termine avant le point de pause')
  if 'READY' in subprocess.check_output([g,probe],text=True,timeout=10):break
  time.sleep(2)
 else:raise RuntimeError('point de pause non atteint')
 record['PauseReachedAt']=datetime.datetime.now().astimezone().isoformat()
 subprocess.run(['ssh','degun@192.168.1.173',vbox+'off'],check=True,timeout=20)
 record['Cut']=True
 subprocess.run([g,'echo go > C:\\PestoTest-run\\reseau-rename-continue.txt'],check=True,timeout=10)
 out=child.communicate(timeout=130)[0].decode(errors='replace')
 record['WorkerExit']=child.returncode;record['Output']=out
 print(out,flush=True)
finally:
 r=subprocess.run(['ssh','degun@192.168.1.173',vbox+'on'],timeout=20,capture_output=True)
 record['Restored']=r.returncode==0;record['RestoredAt']=datetime.datetime.now().astimezone().isoformat()
 if child.poll() is not None and 'Output' not in record:
  record['Output']=child.communicate()[0].decode(errors='replace');print(record['Output'],flush=True)
 (p/'rename-puis-coupure-hote.json').write_text(json.dumps(record,indent=2))
 print('NIC2 restored:',record['Restored'],flush=True)
