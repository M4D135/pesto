from pathlib import Path
import json, zipfile, hashlib, subprocess, sys, shutil
base=Path('/mnt/data'); root=base/'Pesto_REPRISE/DEV'
if not (root/'wad/Pesto-Core.ps1').is_file():
    raise RuntimeError('La reprise des sources doit reussir avant de changer le generateur.')
tools=root/'tools';tools.mkdir(exist_ok=True)
builder=r'''"""Fabrication hors ligne PROD/DEV. Aucun code Pesto, AD ou Windows n'est execute."""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, tempfile, zipfile
from pathlib import Path
from datetime import datetime,timezone

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()

def entries(node):
    out=[]
    if isinstance(node,dict):
        d={k.lower():v for k,v in node.items()}
        p=next((d[k] for k in ('path','relativepath','file','filename') if isinstance(d.get(k),str)),None)
        h=next((d[k] for k in ('sha256','sha256hash','hash','checksum') if isinstance(d.get(k),str) and len(d[k])==64 and all(c in '0123456789abcdefABCDEF' for c in d[k])),None)
        if p and h:out.append((p,h))
        for k,v in node.items():
            if isinstance(v,str) and len(v)==64 and all(c in '0123456789abcdefABCDEF' for c in v) and '.' in k:out.append((k,v))
            if isinstance(v,dict) and (k.startswith('wad/') or k.startswith('wad\\') or k.endswith('.exe')):
                s={x.lower():y for x,y in v.items()}
                value=next((s[x] for x in ('sha256','hash','checksum') if isinstance(s.get(x),str) and len(s[x])==64),None)
                if value:out.append((k,value))
            out.extend(entries(v))
    elif isinstance(node,list):
        for child in node:out.extend(entries(child))
    return list(dict.fromkeys(out))

def safe_relative(text):
    s=text.replace('\\','/')
    p=Path(s)
    if not s or p.is_absolute() or '..' in p.parts or ':' in s or any(x in ('','.','..') for x in s.split('/')):
        raise ValueError('Chemin de manifeste refuse : '+text)
    return p

def not_link(path,source):
    current=path
    while True:
        if current.is_symlink():raise ValueError('Lien refuse : '+str(path))
        if current==source:break
        if current.parent==current:raise ValueError('Chemin hors source.')
        current=current.parent

def runtime(source):
    source=Path(source).absolute()
    if source.is_symlink():raise ValueError('Racine liee refusee.')
    manifest=source/'wad/package.json';not_link(manifest,source)
    data=json.loads(manifest.read_text('utf-8-sig'))
    records=entries(data)
    if len(records)<1:raise ValueError('Schema de manifeste non reconnu.')
    seen={};paths=[]
    for text,wanted in records:
        rel=safe_relative(text);p=source/rel
        if not p.is_file() and (source/'wad'/rel).is_file():rel=Path('wad')/rel;p=source/rel
        key=rel.as_posix().casefold()
        if key in seen:
            if seen[key]!=wanted.lower():raise ValueError('Empreintes contradictoires : '+str(rel))
            continue
        if rel.parts[0]!='wad' and rel.as_posix()!='Pesto.exe':raise ValueError('Dependance runtime hors application : '+str(rel))
        if any(x.lower() in ('support','tests','tools','maintenance','docs','logs') for x in rel.parts):
            raise ValueError('Le manifeste exige un composant facultatif : '+str(rel))
        not_link(p,source)
        if not p.is_file() or digest(p).lower()!=wanted.lower():raise ValueError('Composant absent ou modifie : '+str(rel))
        seen[key]=wanted.lower();paths.append(rel)
    for required in ('Pesto.exe','wad/Pesto-Core.ps1','wad/Pesto-Startup.ps1'):
        p=source/required;not_link(p,source)
        if not p.is_file():raise ValueError('Composant essentiel absent : '+required)
        if required!='Pesto.exe' and required.casefold() not in seen:raise ValueError('Composant essentiel non couvert : '+required)
    # Extra application scripts cannot silently escape integrity checking.
    for p in (source/'wad').glob('Pesto-*.ps1'):
        if p.relative_to(source).as_posix().casefold() not in seen:raise ValueError('Script applicatif non couvert : '+p.name)
    return list(dict.fromkeys(paths+[Path('Pesto.exe'),Path('wad/package.json')])),data

def allowed_dev(rel):
    parts=[x.lower() for x in rel.parts]
    if any(p in ('.git','__pycache__','.pytest_cache','.venv','venv','logs','state','states','data','dist','build-output','node_modules') for p in parts):return False
    if rel.name.lower() in ('gp.prefs.json','pesto.prefs.json','receipt.json','direct.json','credentials.json','secrets.json'):return False
    if rel.suffix.lower() in ('.log','.pyc','.pfx','.p12','.key','.pem'):return False
    if len(rel.parts)==1 and rel.name.upper()=='DEBLOQUER_TOUT.CMD':return False
    return True

def zip_tree(source,target):
    with zipfile.ZipFile(target,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(source.rglob('*')):
            if p.is_file():
                if p.is_symlink():raise ValueError('Lien dans le pack.')
                name=p.relative_to(source.parent).as_posix()
                item=zipfile.ZipInfo(name,(2026,1,1,0,0,0));item.compress_type=zipfile.ZIP_DEFLATED;item.external_attr=0o100644<<16
                z.writestr(item,p.read_bytes())
    with zipfile.ZipFile(target) as z:
        bad=z.testzip()
        if bad:raise ValueError('Erreur ZIP : '+bad)

def build(source,output):
    source=Path(source).absolute();output=Path(output).absolute()
    if output==source or source in output.parents:raise ValueError('La sortie doit etre hors du dossier source.')
    if output.exists():raise FileExistsError('La sortie existe deja; choisir un nouveau dossier.')
    files,meta=runtime(source)
    output.parent.mkdir(parents=True,exist_ok=True)
    staging=Path(tempfile.mkdtemp(prefix='.pesto-stage-',dir=output.parent))
    try:
        prod=staging/'PROD';dev=staging/'DEV';prod.mkdir();dev.mkdir()
        for rel in files:
            dst=prod/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/rel,dst)
        for relative in ('wad/cfg.json',):
            p=source/relative
            if p.is_file():
                not_link(p,source);json.loads(p.read_text('utf-8-sig'));dst=prod/relative;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
        support=source/'wad/support'
        if support.is_dir():
            not_link(support,source)
            for p in sorted(support.rglob('*')):
                if p.is_file() and p.suffix.lower() not in ('.log','.pyc'):
                    not_link(p,source);dest=prod/p.relative_to(source);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
        for p in sorted(source.rglob('*')):
            rel=p.relative_to(source)
            if not allowed_dev(rel):continue
            if p.is_symlink():raise ValueError('Lien source refuse : '+str(rel))
            if p.is_file():
                dst=dev/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
        assert set(p.name for p in prod.iterdir())=={'Pesto.exe','wad'}
        for rel in files:
            if digest(prod/rel)!=digest(dev/rel):raise ValueError('Difference applicative PROD/DEV : '+str(rel))
        runtime(prod);runtime(dev)
        zip_tree(prod,staging/'Pesto_PROD.zip');zip_tree(dev,staging/'Pesto_DEV.zip')
        summary={'runtimeComponents':len(files),'PROD':{'sha256':digest(staging/'Pesto_PROD.zip')},'DEV':{'sha256':digest(staging/'Pesto_DEV.zip')},
                 'scope':'Coherence et fabrication uniquement; pas une validation Windows, WPF, UAC, AD ou signature.',
                 'supportRequiredAtRuntime':False,'configuration':'A preparer et verifier avant diffusion.'}
        (staging/'FABRICATION.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
        # No file-by-file replacement of a previous installation.
        os.rename(staging,output)
        return summary
    except Exception:
        shutil.rmtree(staging,ignore_errors=True);raise

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--output',type=Path)
    a=ap.parse_args()
    target=a.output or (a.source.absolute().parent/('Pesto_PACKS_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')))
    try:
        r=build(a.source,target);print(json.dumps({'output':str(target),**r},ensure_ascii=False,indent=2))
    except Exception as ex:ap.exit(1,'Fabrication refusee : '+str(ex)+'\n')
'''
(tools/'Build-PestoPacks.py').write_text(builder,encoding='utf-8')
factory='''@echo off
setlocal EnableExtensions DisableDelayedExpansion
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0tools\\Build-PestoPacks.py" --source "%~dp0."
) else (
  python "%~dp0tools\\Build-PestoPacks.py" --source "%~dp0."
)
set "PESTO_BUILD_EXIT=%ERRORLEVEL%"
pause
exit /b %PESTO_BUILD_EXIT%
'''
(root/'FABRIQUER_PACKS.cmd').write_bytes(factory.replace('\n','\r\n').encode('ascii'))
tests=r'''import unittest,tempfile,json,hashlib,importlib.util,sys,zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('packs',Path(__file__).resolve().parents[1]/'tools/Build-PestoPacks.py')
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
'''
(root/'tests').mkdir(exist_ok=True)
(root/'tests/test_support_distribution_reprise.py').write_text(tests,encoding='utf-8')
r=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_support_distribution_reprise.py','-v'],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=80)
report=base/'Pesto_REPRISE_BILAN.json'
data=json.loads(report.read_text('utf-8')) if report.is_file() else {}
data['supportDistributionTests']={'status':'PASS' if r.returncode==0 else 'FAIL','exitCode':r.returncode,'output':r.stdout,'scope':'Tests comportementaux du nouveau generateur sur fichiers fictifs, pas operations Windows.'}
data['additionalChanges']=['Generateur PROD/DEV dans tools/Build-PestoPacks.py','FABRIQUER_PACKS.cmd raccorde au nouveau generateur','Exclusion des preferences/journaux/certificats prives des paquets DEV','Tests de refus sur corruption, absence, chemins, composants facultatifs et code non couvert']
(root/'docs/bilan-reprise.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
# Save a source snapshot even if the previous native gate fails; do not label it validated PROD.
with zipfile.ZipFile(base/'Pesto_REPRISE_DEV.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file() and not p.is_symlink() and '__pycache__' not in p.parts and p.suffix!='.pyc':z.write(p,p.relative_to(root.parent).as_posix())
with zipfile.ZipFile(base/'Pesto_REPRISE_DEV.zip') as z:
 assert z.testzip() is None
packout=base/'Pesto_REPRISE_PACKS_VERIFIES'
if r.returncode==0 and not packout.exists():
 p=subprocess.run([sys.executable,'tools/Build-PestoPacks.py','--source',str(root),'--output',str(packout)],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=100)
 data['newPackBuilderResult']={'exitCode':p.returncode,'status':'PASS' if p.returncode==0 else 'FAIL','output':p.stdout}
 if p.returncode==0:
  shutil.copy2(packout/'Pesto_PROD.zip',base/'Pesto_REPRISE_PROD.zip')
  data['productionPackCreated']=True
report.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
print(r.stdout)
print(json.dumps({'developerSnapshot':str(base/'Pesto_REPRISE_DEV.zip'),'testsReturnCode':r.returncode,'packBuild':data.get('newPackBuilderResult',{})},ensure_ascii=False,indent=2))
