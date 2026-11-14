import subprocess,json,datetime
from pathlib import Path
p=Path('/Users/david/Documents/Codex/2026-10-04/co-3/work/prod-validation')
vbox='"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe" controlvm PESTO-W11-TEST setlinkstate2 '
record={'Date':datetime.datetime.now().astimezone().isoformat(),'VM':'PESTO-W11-TEST','NIC':2,'Network':'LABO-LAB','NAT_NIC3_Kept':True}
try:
 subprocess.run(['ssh','degun@192.168.1.173',vbox+'off'],check=True,timeout=20)
 record['Cut']=True
 cmd='powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\lancer.ps1 -Compte LABO\\pesto-qualif -Eleve -Exe powershell.exe -Arguments "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\PestoTest-run\\ui-reseau.ps1" -Attendre -Delai 150'
 r=subprocess.run(['/Users/david/Projects/pesto/outils/labo/mac/g.sh',cmd],timeout=180,capture_output=True)
 record['DriverExit']=r.returncode;record['DriverOutput']=r.stdout.decode(errors='replace')+r.stderr.decode(errors='replace')
 print(record['DriverOutput'])
finally:
 r=subprocess.run(['ssh','degun@192.168.1.173',vbox+'on'],timeout=20,capture_output=True)
 record['Restored']=r.returncode==0;record['RestoredAt']=datetime.datetime.now().astimezone().isoformat()
 (p/'coupure-reseau-hote.json').write_text(json.dumps(record,indent=2))
 print('NIC2 restored:',record['Restored'])
