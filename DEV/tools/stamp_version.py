#!/usr/bin/env python3
"""Apply tools/version.json to every version location of Pesto (runtime, launcher, build tools).

python3 tools/stamp_version.py          # rewrite locations in place (BOM and line endings preserved)
python3 tools/stamp_version.py --check  # fail if a location differs or a stale literal remains

After stamping runtime files: build_native.py, then refresh_manifest.py.
"""
import argparse,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from release_version import VERSION,FILE_VERSION

COMMA=FILE_VERSION.replace('.',',')
# (path, regex with exactly one group, replacement value). Each regex must match at least once.
LOCATIONS=[
 ('wad/Pesto-Core.ps1',r"^\$script:Pesto_VERSION = '([^']*)'",VERSION),
 ('wad/Pesto-Core.ps1',r'Title="Pesto (\S+) — Initialisation"',VERSION),
 ('wad/Pesto-Authentication.ps1',r'Title="Pesto (\S+) \| Connexion Windows"',VERSION),
 ('wad/Pesto-Authentication.ps1',r'Title="Pesto (\S+) · Connexion"',VERSION),
 ('wad/Pesto-Shell.xaml',r'Title="Pesto (\S+)"',VERSION),
 ('wad/Pesto-Shell.xaml',r'x:Name="UxVersion" Text="Pesto ([^"]+)"',VERSION),
 ('wad/Pesto-Join.ps1',r'^# Pesto (\S+) : jonction locale',VERSION),
 ('wad/Pesto-Join.ps1',r"Schema=1;Version='([^']*)';OperationId=\$Request",VERSION),
 ('wad/Pesto-Safety.ps1',r"Schema=2;Version='([^']*)';OperationId=\$id",VERSION),
 ('wad/Pesto-Integrity.ps1',r"\$m\.Version -ne '([^']*)'",VERSION),
 ('wad/Pesto-Startup.ps1',r"^# Pesto (\S+) : point d'entrée",VERSION),
 ('tools/launcher/Pesto-launcher.c',r'^/\* Pesto (\S+) - Windows x64',VERSION),
 ('tools/launcher/Pesto-launcher.c',r'W\("Pesto (\S+) \| Démarrage"\)',VERSION),
 ('tools/launcher/Pesto-launcher.c',r'W\("Pesto (\S+)\\r\\nLanceur natif',VERSION),
 ('tools/launcher/Pesto-launcher.c',r'\[Pesto (\S+) launcher\]',VERSION),
 ('tools/launcher/Pesto-launcher.c',r'W\("Pesto (\S+) \| Diagnostic"\)',VERSION),
 ('tools/launcher/Pesto.manifest',r'<assemblyIdentity version="([^"]*)"',FILE_VERSION),
 ('tools/Build-Pesto.ps1',r'^ FILEVERSION (\S+)',COMMA),
 ('tools/Build-Pesto.ps1',r'^ PRODUCTVERSION (\S+)',COMMA),
 ('tools/Build-Pesto.ps1',r'VALUE "FileVersion", "([^"\\]*)\\0"',FILE_VERSION),
 ('tools/Build-Pesto.ps1',r'VALUE "ProductVersion", "([^"\\]*)\\0"',VERSION),
 ('tools/Update-PackageManifest.ps1',r"Schema=2;Version='([^']*)';Scope",VERSION),
 ('tools/New-PestoDistribution.ps1',r"'Pesto_([^_']+)_'\+\$kind",VERSION),
 ('tools/Verify-Release.ps1',r"\$native\.Version -ne '([^']*)'",VERSION),
 ('tools/Verify-Release.ps1',r"\$evidence\.Version -ne '([^']*)'",VERSION),
 ('tools/Verify-Release.ps1',r"\[pscustomobject\]@\{Version='([^']*)';Utc",VERSION),
 ('wad/maintenance/Test-Pesto19.ps1',r"\$script:Pesto_VERSION='([^']*)'",VERSION),
 ('wad/maintenance/Test-Pesto19.ps1',r"Equal \$p\.Version '([^']*)'",VERSION),
 ('wad/maintenance/Test-Pesto19.ps1',r"FileVersion\) '([^']*)'",FILE_VERSION),
 ('wad/maintenance/Test-Pesto19.ps1',r"^\[pscustomobject\]@\{Version='([^']*)';Utc",VERSION),
 ('tests/Run-Pesto21Tests.ps1',r"\$script:Pesto_VERSION='([^']*)'",VERSION),
 ('tests/Run-Pesto21Tests.ps1',r"^\[pscustomobject\]@\{Version='([^']*)';PowerShell",VERSION),
 ('tests/Run-Pesto22Tests.ps1',r"^\[pscustomobject\]@\{Version='([^']*)';Utc",VERSION),
 ('tests/Run-Pesto23Tests.ps1',r"\$script:Pesto_VERSION='([^']*)'",VERSION),
 ('tests/Run-Pesto23Tests.ps1',r"^\[pscustomobject\]@\{Version='([^']*)';Utc",VERSION),
 ('tests/Run-NamesLoadingTests.ps1',r"^\[pscustomobject\]@\{Version='([^']*)';PowerShell",VERSION),
 ('TESTER.cmd',r'^title Pesto (\S+) - Tests Windows isoles',VERSION),
 ('TEST_RC23.cmd',r'^title Pesto (\S+) - Tests jonction et parcours',VERSION),
]
# Literals that must never survive in shipped code or build tools once stamped.
STALE=re.compile(r'17\.0-RC\d+|17\.0\.0\.\d+|17,0,0,\d+|Pesto RC\d+|\bRC\d+ Route=')
# Les suites de tests gardent des reçus témoins anciens (lecture rétrocompatible) : non scannées.
SCANNED=sorted({p for p,_,_ in LOCATIONS if not p.startswith(('tests/','wad/maintenance/'))}|{'wad/'+p.name for p in (ROOT/'wad').glob('Pesto-*.ps1')}|{'wad/Pesto-Shell.xaml','wad/Pesto-Join.xaml','tools/launcher/Pesto-launcher.c'})

def load(rel):
    raw=(ROOT/rel).read_bytes();bom=raw.startswith(b'\xef\xbb\xbf')
    return raw[3:].decode('utf-8') if bom else raw.decode('utf-8'),bom

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');a=ap.parse_args()
    problems=[];texts={}
    for rel,pattern,value in LOCATIONS:
        if rel not in texts:texts[rel]=list(load(rel))
        text=texts[rel][0];rx=re.compile(pattern,re.M);found=list(rx.finditer(text))
        if not found:problems.append(f'{rel}: emplacement introuvable {pattern}');continue
        stale=[m.group(1) for m in found if m.group(1)!=value]
        if a.check:
            for s in stale:problems.append(f'{rel}: {s!r} au lieu de {value!r}')
        elif stale:
            texts[rel][0]=rx.sub(lambda m:m.group(0)[:m.start(1)-m.start(0)]+value+m.group(0)[m.end(1)-m.start(0):],text)
    if not a.check:
        for rel,(text,bom) in texts.items():
            data=(b'\xef\xbb\xbf' if bom else b'')+text.encode('utf-8')
            if data!=(ROOT/rel).read_bytes():(ROOT/rel).write_bytes(data);print('estampillé',rel)
    for rel in SCANNED:
        text,_=load(rel)
        for n,line in enumerate(text.splitlines(),1):
            if STALE.search(line):problems.append(f'{rel}:{n}: littéral périmé {STALE.search(line).group(0)!r}')
    for p in problems:print('FAIL',p)
    print(('CHECK ' if a.check else 'STAMP ')+VERSION+' / '+FILE_VERSION+(' OK' if not problems else f' : {len(problems)} problème(s)'))
    return 1 if problems else 0

if __name__=='__main__':sys.exit(main())
