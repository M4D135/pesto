#!/usr/bin/env python3
"""Portable structural validation, NOT a PowerShell parser or WPF/AD runtime test."""
import hashlib,json,pathlib,re,struct,sys,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
from ps_lexical import functions,tokens
checks=[]
def check(name,value,detail=''):
    checks.append(dict(name=name,passed=bool(value),detail=detail));print(('OK ' if value else 'FAIL ')+name+((': '+detail) if detail and not value else ''))
def sha(b):return hashlib.sha256(b).hexdigest()
core=(ROOT/'wad/Pesto-Core.ps1').read_text('utf-8-sig');join=(ROOT/'wad/Pesto-Join.ps1').read_text('utf-8-sig');launcher=(ROOT/'Pesto.ps1').read_text('utf-8-sig')
funcs=functions(core);jfunc=functions(join)
for p in sorted(ROOT.rglob('*.ps1')):
    try:tokens(p.read_text('utf-8-sig'));ok=True;detail=''
    except Exception as e:ok=False;detail=str(e)
    check('lexical delimiters '+str(p.relative_to(ROOT)),ok,detail)
# Main literal XAML only: this is XML structure checking, not XamlReader.
m=re.search(r"\[xml\]\$xaml\s*=\s*@'\n(.*?)\n'@",core,re.S)
x=ET.fromstring(m.group(1));j=ET.parse(ROOT/'wad/Pesto-Join.xaml').getroot()
ns={'x':'http://schemas.microsoft.com/winfx/2006/xaml','w':'http://schemas.microsoft.com/winfx/2006/xaml/presentation'}
namekey='{'+ns['x']+'}Name';keykey='{'+ns['x']+'}Key'
names=[e.get(namekey) for e in x.iter() if e.get(namekey)];jnames=[e.get(namekey) for e in j.iter() if e.get(namekey)]
check('main XML parseable',True);check('join XML parseable',True)
check('join named controls unique',len(jnames)==len(set(jnames)))
bindingblock=join[join.index('$names=@{'):join.index('foreach($key in $names.Keys)')]
mapnames=re.findall(r"='(Jn\w+)'",bindingblock)
check('join controls mapped exactly',set(mapnames)==set(jnames),str(set(mapnames)^set(jnames)))
resources={e.get(keykey) for e in x.iter() if e.get(keykey)}
refs=set(re.findall(r'\{DynamicResource ([^}]+)\}',(ROOT/'wad/Pesto-Join.xaml').read_text()))
check('join dynamic resources exist in shell',not(refs-resources),str(refs-resources))
for e in j.iter():
    if e.tag.split('}')[-1] in ('Button','TextBox','ComboBox','DataGrid'):
        check('hover help '+str(e.get(namekey)), bool(e.get('ToolTip')) and e.get('ToolTipService.ShowOnDisabled')=='True')
tabs=next(e for e in x.iter() if e.get(namekey)=='MainTabs')
check('dedicated eighth join page',len(list(tabs))==8 and list(tabs)[-1].get(namekey)=='TabJoin')
check('join navigation exists','NavJoin' in names and 'UxJoinHost' in names)
check('join module loaded before main window',core.index(". (Join-Path $PSScriptRoot 'Pesto-Join.ps1')") < core.index('[xml]$xaml'))
check('no queue row manipulation in join module',not re.search(r'\$(?:script:)?table\.|Add-Or-UpdateRow|Run-Queue|GoJoinDomain',join))
check('no dsreg call in join module',not re.search(r'Invoke-PestoDsreg|dsregcmd\.exe|/leave',join))
check('join uses separate protected worker',"-Name 'DomainJoin'" in join and "@('QueueAction','DomainJoin')" in core)
check('machine-wide mutex for local join',r'Global\Pesto_LocalDomainJoin_v1' in join)
check('machine receipt outside per-user profile',"GetFolderPath('CommonApplicationData')" in join)
check('late result is not silently success',"$Request.Monitor.TimedOut -or $Request.Monitor.CancelRequested" in join)
check('restart only explicit handler',join.count('Restart-Computer -ErrorAction Stop')==1 and not re.search(r'Restart-Computer[^\n]*-Force',join))
check('hidden legacy off-domain UI not reactivated',"if($script:JoinUI){Update-PestoJoinUI;return $true}" in core)
check('native launcher starts Pesto.ps1 not a bundled engine',r'\\Pesto.ps1' in (ROOT/'tools/launcher/Pesto-launcher.c').read_text())
check('single instance guard present',r'Global\GP_Session_' in launcher and 'WaitOne(0)' in launcher)
check('demo join propagated',"DemoJoin=$DemoJoin.IsPresent" in launcher and '$DemoJoin.IsPresent -or' in core)
check('login remains nonmaximizable','ResizeMode="NoResize"' in core[funcs['Show-LoginWindow'][0]:funcs['Show-LoginWindow'][1]])
# Baseline hashes intentionally concern untouched sensitive behaviour only.
for name,expected in json.loads((ROOT/'tests/rc13-sensitive-functions.json').read_text()).items():
    body=core[slice(*funcs[name])]
    check('RC13 preserved '+name,sha(body.encode())==expected)
# Definitions required by both real workers must exist.
block=core[core.index('$script:PestoWorkerCoreNames = @('):core.index('$script:PestoWorkerCoreSourceCache')]
exports=re.findall(r"'([A-Za-z][\w-]*)'",block)
check('core worker exports defined',all(n in funcs for n in exports),str([n for n in exports if n not in funcs]))
worker=join[slice(*jfunc['Get-PestoJoinWorkerSource'])]
extra=re.findall(r"'([A-Za-z][\w-]*)'",worker)
check('join worker exports defined',all(n in funcs or n in jfunc for n in extra),str([n for n in extra if n not in funcs and n not in jfunc]))
# Parse PE headers, imports and resource tree without executing the binary.
b=(ROOT/'Pesto.exe').read_bytes();pe=struct.unpack_from('<I',b,60)[0];coff=pe+4;optional=coff+20
machine,sections=struct.unpack_from('<HH',b,coff);optsize=struct.unpack_from('<H',b,coff+16)[0]
check('EXE native PE32+ x64 GUI',b[:2]==b'MZ' and b[pe:pe+4]==b'PE\0\0' and machine==0x8664 and struct.unpack_from('<H',b,optional)[0]==0x20b and struct.unpack_from('<H',b,optional+68)[0]==2)
sec=[]
for i in range(sections):
    at=optional+optsize+40*i;vsize,va,size,off=struct.unpack_from('<IIII',b,at+8);sec.append((va,max(size,vsize),off))
def offset(rva):
    for va,size,off in sec:
        if va<=rva<va+size:return off+rva-va
    raise ValueError('Unmapped RVA '+hex(rva))
def cstring(at):return b[at:b.index(0,at)].decode('ascii')
imports=[];imp=struct.unpack_from('<I',b,optional+112+8)[0];at=offset(imp)
while any(b[at:at+20]):
    name=struct.unpack_from('<I',b,at+12)[0];imports.append(cstring(offset(name)));at+=20
check('EXE imports only Windows system APIs',set(imports)=={'KERNEL32.dll','USER32.dll','SHELL32.dll'},str(imports))
security=struct.unpack_from('<II',b,optional+112+8*4);check('unsigned EXE explicitly identified',security==(0,0))
clr=struct.unpack_from('<II',b,optional+112+8*14);check('native launcher no CLR dependency',clr==(0,0))
rsrc=offset(struct.unpack_from('<I',b,optional+112+8*2)[0]);resources_found={}
def walk(rel=0,path=()):
    base=rsrc+rel;named,ids=struct.unpack_from('<HH',b,base+12)
    for i in range(named+ids):
        ident,target=struct.unpack_from('<II',b,base+16+8*i);p=path+(ident,)
        if target&0x80000000:walk(target&0x7fffffff,p)
        else:
            data_rva,n=struct.unpack_from('<II',b,rsrc+target);data=b[offset(data_rva):offset(data_rva)+n];resources_found[p]=data
walk()
manifest=next(data for path,data in resources_found.items() if path[0]==24)
check('manifest valid asInvoker',ET.fromstring(manifest) is not None and b'level="asInvoker"' in manifest)
check('icon and version embedded',{3,14,16,24} <= {p[0] for p in resources_found})
version=next(data for path,data in resources_found.items() if path[0]==16)
check('file version 17.0.0.14 embedded','17.0.0.14'.encode('utf-16le') in version and '17.0-RC14'.encode('utf-16le') in version)
# ICO data in PE must match the supplied source bit for bit.
ico=(ROOT/'wad/Pesto.ico').read_bytes();count=struct.unpack_from('<H',ico,4)[0];good=True
for i in range(count):
    n,off=struct.unpack_from('<II',ico,6+16*i+8);actual=next(d for p,d in resources_found.items() if p[0]==3 and p[1]==i+1);good &= actual==ico[off:off+n]
check('embedded icon equals original icon',good)
report={'version':'17.0-RC14','kind':'portable structural checks; NOT Windows/PowerShell/WPF/AD runtime validation','windowsExecuted':False,'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'exeSha256':sha(b)}
out=ROOT/'tests/rc14-portable-validation.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('RESULT:',report['passed'],'passed,',report['failed'],'failed. Windows NOT executed.')
sys.exit(bool(report['failed']))
