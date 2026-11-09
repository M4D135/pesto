#!/usr/bin/env python3
"""Portable source/XML/PE checks. NOT a native PowerShell/WPF/AD runtime."""
import argparse,hashlib,json,os,pathlib,re,shutil,struct,subprocess,sys,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
from ps_lexical import functions,tokens,smart_quote_hazards
sys.path.insert(0,str(ROOT/'tools'))
from release_version import VERSION,FILE_VERSION
p=argparse.ArgumentParser();p.add_argument('--baseline',type=pathlib.Path);p.add_argument('--without-manifest',action='store_true');p.add_argument('--require-parser',action='store_true');args=p.parse_args()
checks=[]
def check(name,value,detail=''):
 checks.append(dict(name=name,passed=bool(value),detail=detail));print(('OK ' if value else 'FAIL ')+name+(': '+detail if detail and not value else ''))
def sha(b):return hashlib.sha256(b).hexdigest()
paths=sorted((ROOT/'wad').glob('Pesto-*.ps1'))
sources={p.name:p.read_text('utf-8-sig') for p in paths};allfn={};owners={}
for path in paths:
 s=sources[path.name]
 try:
  tokens(s);ff=functions(s);check('lexical '+path.name,True);check('smart quote safety '+path.name,not smart_quote_hazards(s))
  for n,(a,b) in ff.items():
   if n in allfn:check('unique function '+n,False,owners[n]+' / '+path.name)
   allfn[n]=s[a:b];owners[n]=path.name
 except Exception as e:check('lexical '+path.name,False,str(e))
for path in sorted((ROOT/'wad/maintenance').glob('*.ps1')):
 try:tokens(path.read_text('utf-8-sig'));check('lexical maintenance '+path.name,True)
 except Exception as e:check('lexical maintenance '+path.name,False,str(e))
check('no duplicate functions across runtime',len(allfn)==sum(len(functions(s)) for s in sources.values()))
core=sources['Pesto-Core.ps1'];direct=sources['Pesto-Direct.ps1'];join=sources['Pesto-Join.ps1'];auth=sources['Pesto-Authentication.ps1'];suite=sources['Pesto-SuiteUI.ps1'];inspect=sources['Pesto-Inspection.ps1'];support=sources['Pesto-Support.ps1']
ns='http://schemas.microsoft.com/winfx/2006/xaml';nk='{'+ns+'}Name';kk='{'+ns+'}Key'
shelltext=(ROOT/'wad/Pesto-Shell.xaml').read_text(encoding='utf-8-sig');jointext=(ROOT/'wad/Pesto-Join.xaml').read_text(encoding='utf-8-sig');shell=ET.fromstring(shelltext);jn=ET.fromstring(jointext)
check('shell XML',True);check('join XML',True)
for source_name,text in sources.items():
 for idx,m in enumerate(re.finditer(r"\[xml\]\$\w+\s*=\s*@(['\"])\n(.*?)\n\1@",text,re.S)):
  if m.group(2).lstrip().startswith('<Window'):
   try:ET.fromstring(m.group(2));check('secondary window XML '+source_name+' '+str(idx),True)
   except Exception as e:check('secondary window XML '+source_name+' '+str(idx),False,str(e))
names={e.get(nk) for e in shell.iter() if e.get(nk)};jnames={e.get(nk) for e in jn.iter() if e.get(nk)};resources={e.get(kk) for e in shell.iter() if e.get(kk)}
# Template names live in separate WPF name scopes. Named controls outside templates must be unique.
def scoped_names(node):
 out=[]
 def walk(e):
  if e.tag.split('}')[-1] in ('ControlTemplate','DataTemplate'):return
  if e.get(nk):out.append(e.get(nk))
  for child in e:walk(child)
 walk(node);return out
sn=scoped_names(shell);check('shell non-template names unique',len(sn)==len(set(sn)))
check('join names unique',len(jnames)==sum(bool(e.get(nk)) for e in jn.iter()))
for label,xml in [('shell',shelltext),('join',jointext)]:
 refs=set(re.findall(r'\{(?:Static|Dynamic)Resource ([\w]+)\}',xml));check(label+' resource references',not(refs-resources),str(sorted(refs-resources)))
# WPF effective value: local attribute, then the explicit Style, then the implicit Style for the
# control type, following the BasedOn chain. An unknown reference or a cycle stays unresolved (strict).
def _local_name(tag):return tag.split('}')[-1]
def _resource_key(ref):
 m=re.fullmatch(r'\{(?:Static|Dynamic)Resource\s+([\w.]+)\}',ref or '')
 return m.group(1) if m else None
def _style_maps(*roots):
 keyed={};implicit={}
 for root in roots:
  for res in root:
   if not _local_name(res.tag).endswith('Resources'):continue
   for st in res:
    if _local_name(st.tag)!='Style':continue
    key=st.get(kk);target=st.get('TargetType') or ''
    if target.startswith('{'):target=_local_name(target)
    if key:keyed[key]=st
    elif target:implicit.setdefault(target,st)
 return keyed,implicit
def _style_chain(elem,keyed,implicit):
 seen=set();chain=[];st=None;key=None
 ref=elem.get('Style')
 if ref is None:
  tag=_local_name(elem.tag)
  if tag in implicit:st=implicit[tag];key='#'+tag
 else:
  key=_resource_key(ref)
  if key is None or key not in keyed:return None
  st=keyed[key]
 while st is not None:
  if key in seen:return None
  if key is not None:seen.add(key)
  chain.append(st)
  based=st.get('BasedOn')
  if based is None:break
  key=_resource_key(based)
  if key is None or key not in keyed:return None
  st=keyed[key]
 return chain
def effective_property(elem,prop,keyed,implicit):
 local=elem.get(prop)
 if local is not None:return local
 chain=_style_chain(elem,keyed,implicit)
 if chain is None:return None
 for st in chain:
  for setter in st:
   if _local_name(setter.tag)=='Setter' and setter.get('Property')==prop:return setter.get('Value')
 return None
keyed,implicit=_style_maps(shell,jn)
for e in list(shell.iter())+list(jn.iter()):
 tag=e.tag.split('}')[-1]
 # Template parts (PART_*) inherit the owning control's help: their own tooltip would mask it.
 if tag in ('Button','TextBox','PasswordBox','ComboBox','CheckBox','RadioButton','DataGrid') and e.get(nk) and not str(e.get(nk)).startswith('PART_'):
  check('hover '+str(e.get(nk)),bool(effective_property(e,'ToolTip',keyed,implicit)) and effective_property(e,'ToolTipService.ShowOnDisabled',keyed,implicit)=='True')
tabs=next(e for e in shell.iter() if e.get(nk)=='MainTabs');check('eight routed pages',len(list(tabs))==8)
check('single / batch / join navigation',{'NavBatch','NavJoin','SuiteDirectRun','SuiteDirectCheck','SuitePostState','SuiteHelpClose','SuiteNavToggle'}<=names)
check('site search above site removed','SuiteSiteSearch' not in shelltext and 'SuiteSiteSearch' not in suite and 'Invoke-PestoSiteSearch' not in suite)
check('join result popup','Show-PestoJoinOutcome' in allfn['Complete-PestoJoinExecution'] and 'Show-PestoJoinOutcome' in allfn['Complete-PestoJoinExecutionError'] and 'Show-PestoJoinOutcome' in allfn['Complete-PestoJoinCheck'])
check('direct result popup','Show-PestoOutcome' in allfn['Complete-PestoDirectAction'] and 'Show-PestoOutcome' not in allfn['Complete-PestoDirectPreflight'])
check('queue result popup','Show-PestoOutcome' in allfn['Complete-PestoQueueRun'] and "Show-MsgInfo $endMsg" not in allfn['Complete-PestoQueueRun'])
check('configuration section titles human',all(x in shelltext for x in ('Apparence','Options avancées','Domaine')))
check('theme labels not numeric',all(x in sources['Pesto-Appearance.ps1'] for x in ('Light','Dark','System')))
check('no theme applied by cfg reload','Set-Theme' not in allfn['Apply-CfgHot'])
check('cfg save does not require empty queue','table.Rows.Count' not in allfn['Save-Cfg'])
check('business invalidation keeps rows','Rows.Clear' not in allfn['Invalidate-PestoConfigurationPlans'] and 'NeedsReview' in allfn['Invalidate-PestoConfigurationPlans'])
check('unwanted login phrase removed',not re.search(r'aucune saisie suppl[eé]mentaire',auth,re.I))
check('login NoResize','ResizeMode="NoResize"' in allfn['Show-LoginWindow'])
check('light directory login','if([bool]$Request.FullInventory)' in sources['Pesto-Directory.ps1'] and not re.search(r'FullInventory\s*=\s*\$true',allfn['New-PestoDirectorySnapshotRequest']))
check('no network on hostname typing',not re.search(r'PCProbeTimer\.Start|Start-PestoAsyncOperation|Select-PCName',allfn['Request-PestoUxComputerLookup']))
check('direct no queue insertion',not re.search(r'Rows\.Add|Add-OrUpdateQueue|Run-Queue|Start-PestoNextQueueTask',direct))
check('join no queue insertion',not re.search(r'\$(?:script:)?table\.|Add-Or-UpdateRow|Run-Queue|GoJoinDomain',join))
check('join no Entra leave',not re.search(r'Invoke-PestoDsreg|dsregcmd\.exe|/leave',join))
check('same site decision preserved','Get-PestoRenameMoveDecision' in allfn)
check('no implicit reboot in direct','Reboot=$false' in direct and not re.search(r'Restart-Computer|shutdown.exe',direct))
check('direct receipt protected atomic','Write-PestoJoinReceipt -Path $Path -Receipt $Receipt' in direct and 'CommonApplicationData' in direct)
check('machine-wide mutation guard',all('Global\\GP_PostMutation_v1' in s for s in [direct,core,join]))
# The tick names the mutations through Test-PestoAsyncMutationName (one list for the whole async layer) or directly.
# Either way DirectAction must be fenced, and a cancelled/expired/faulted worker returns before any success callback.
tick=allfn['Invoke-PestoAsyncTimerTick'];mutation_names=set(re.findall(r"'(\w+)'",allfn.get('Test-PestoAsyncMutationName','')))
late_fence=tick.find('if($op.Cancelled -or $op.TimeoutReported -or $op.TimerFaultReported){')
check('late return fence direct',('DirectAction' in tick or ('Test-PestoAsyncMutationName $op.Name' in tick and 'DirectAction' in mutation_names)) and 'TimeoutReported' in tick and 0<=late_fence<tick.find("-CallbackKind 'callback de succès'"))
check('resume compares operation and GUID',all(t in allfn['Test-PestoDirectResumePlan'] for t in ('Partial','Objet_GUID','OperationId','Plan.Renommer','Plan.Reboot')))
# Le transport DCOM se sélectionne par le jeu de paramètres -PacketPrivacy. -Protocol Dcom est
# incompatible avec -PacketPrivacy et a été retiré : on exige l'option réellement présente et l'absence de la forme invalide.
check('CIM observation uses DCOM',bool(re.search(r'New-CimSessionOption\b[^\n]*-PacketPrivacy',inspect)) and not re.search(r'New-CimSessionOption[^\n]*-Protocol\s+Dcom',inspect,re.I))
check('no write commands in observation worker',not re.search(r'Add-Computer|Rename-Computer|Move-ADObject|Restart-Computer|/leave',allfn['Get-PestoPostObservation']))
check('origin SID appearance flow',all('AppearanceOwnerSid' in sources[n] for n in ['Pesto-Startup.ps1','Pesto-Core.ps1','Pesto-Appearance.ps1']))
check('appearance no profile loading',not re.search(r'reg(?:\.exe)?\s+load|LoadUserProfile|Set-Acl',sources['Pesto-Appearance.ps1'],re.I))
check('diagnostic excludes raw free text','LogEntries' in allfn['Get-PestoDiagnosticText'] and not re.search(r'(?:entry|line)\.Text\b',allfn['Get-PestoDiagnosticText'],re.I))
# Named callbacks resolved across the module boundary.
handlers=set(re.findall(r'\$\{function:([^}]+)\}', '\n'.join(sources.values())))
check('all named callback functions defined',not(handlers-set(allfn)),str(sorted(handlers-set(allfn))))
block=core[core.index('$script:PestoWorkerCoreNames = @('):core.index('$script:PestoWorkerCoreSourceCache')];exports=set(re.findall(r"'([A-Za-z][\w-]*)'",block))
check('core worker exports defined',not(exports-set(allfn)),str(sorted(exports-set(allfn))))
# Detect direct calls from exported definitions to another Pesto function absent from the worker.
missing=set()
for n in exports:
 body=allfn[n]
 # Literal strings/heredocs omitted, since embedded child scripts have their own scope.
 for kind,a,b in tokens(body):
  word=body[a:b]
  if kind=='word' and word in allfn and word!=n and word not in exports:missing.add(word)
worker_locals=set(re.findall(r'function\s+([\w-]+)',core[core.index('$script:PestoQueueWorker = {'):core.index('function Complete-PestoQueueRun') if 'function Complete-PestoQueueRun' in core else core.index('function Run-Queue')]))
missing -= worker_locals
check('worker dependency closure',not missing,str(sorted(missing)))
for sourcefn in ['Get-PestoJoinWorkerSource','Get-PestoDirectSupportSource']:
 refs=set(re.findall(r"'([A-Za-z][\w-]*)'",allfn[sourcefn]));refs={n for n in refs if '-' in n}
 check(sourcefn+' definitions present',not(refs-set(allfn)),str(sorted(refs-set(allfn))))
# CLI-only components are not loaded by the GUI core: Pesto-CliHost.ps1 is dot-sourced by both CLI entry points and
# Pesto-Automation.ps1 (unattended join) is compiled into the Pesto.Engine module that both entry points import.
cli_entries=[(ROOT/'wad'/n).read_text('utf-8-sig') for n in ('Invoke-Pesto.ps1','Invoke-PestoAutoJoin.ps1')]
engine_list=re.search(r"\$names=@\(([^)]*)\)",(ROOT/'tools/Build-PestoEngineModule.ps1').read_text('utf-8-sig'))
engine_parts={'Pesto-'+n+'.ps1' for n in re.findall(r"'(\w+)'",engine_list[1])} if engine_list else set()
cli_loaded={'Pesto-CliHost.ps1':all(". (Join-Path $PSScriptRoot 'Pesto-CliHost.ps1')" in e for e in cli_entries),
 'Pesto-Automation.ps1':'Pesto-Automation.ps1' in engine_parts and all("Import-Module (Join-Path $PSScriptRoot 'Pesto.Engine.psd1')" in e for e in cli_entries)}
for path in sorted((ROOT/'wad').glob('Pesto-*.ps1')):
 if path.name in ('Pesto-Core.ps1','Pesto-Startup.ps1'):continue
 check('component loaded '+path.name,repr(path.name) in core or path.name=='Pesto-Integrity.ps1' or cli_loaded.get(path.name,False))
if args.baseline:
 baseline=args.baseline
 basecore=(baseline/'wad/Pesto-Core.ps1').read_text('utf-8-sig');bf=functions(basecore)
 for name in ['Invoke-PestoDsregLeaveLocal','Invoke-PestoDsregLeaveBeforeRename','RenameComputer','MoveComputer','AddToDomain','Get-PestoRenameMoveDecision','GoRenameAndMove','Invoke-PestoWindowsLocalRename','Write-PestoAtomicText']:
  old=basecore[slice(*bf[name])];check('unchanged sensitive logic '+name,old==allfn[name])
 for path in sorted((baseline/'wad').rglob('*')):
  if path.is_file() and (path.suffix.lower() in ('.dll','.psd1','.ps1xml','.ico') or path.name.startswith('cfg')):
   target=ROOT/path.relative_to(baseline);check('original resource '+str(path.relative_to(baseline)),target.is_file() and path.read_bytes()==target.read_bytes())
 oldx=re.search(r"\[xml\]\$xaml\s*=\s*@'\n(.*?)\n'@",basecore,re.S);oldnames=set(scoped_names(ET.fromstring(oldx.group(1))))
 check('existing shell controls retained',not(oldnames-set(sn)),str(sorted(oldnames-set(sn))))
# Parse PE without execution.
b=(ROOT/'Pesto.exe').read_bytes();pe=struct.unpack_from('<I',b,60)[0];coff=pe+4;optional=coff+20
machine,sections=struct.unpack_from('<HH',b,coff);optsize=struct.unpack_from('<H',b,coff+16)[0]
check('native PE32+ x64 GUI',b[:2]==b'MZ' and b[pe:pe+4]==b'PE\0\0' and machine==0x8664 and struct.unpack_from('<H',b,optional)[0]==0x20b and struct.unpack_from('<H',b,optional+68)[0]==2)
sec=[]
for i in range(sections):
 at=optional+optsize+40*i;vsize,va,size,off=struct.unpack_from('<IIII',b,at+8);sec.append((va,max(size,vsize),off))
def offset(rva):
 for va,size,off in sec:
  if va<=rva<va+size:return off+rva-va
 raise ValueError('Unmapped RVA')
def cstring(at):return b[at:b.index(0,at)].decode('ascii')
imports=[];imp=struct.unpack_from('<I',b,optional+112+8)[0];at=offset(imp)
while any(b[at:at+20]):
 name=struct.unpack_from('<I',b,at+12)[0];imports.append(cstring(offset(name)));at+=20
check('launcher only system Windows imports',set(imports)=={'KERNEL32.dll','USER32.dll','SHELL32.dll'},str(imports))
check('unsigned binary identified',struct.unpack_from('<II',b,optional+112+8*4)==(0,0))
check('no native-launcher CLR dependency',struct.unpack_from('<II',b,optional+112+8*14)==(0,0))
rsrc=offset(struct.unpack_from('<I',b,optional+112+8*2)[0]);r={}
def walk(rel=0,path=()):
 base=rsrc+rel;named,ids=struct.unpack_from('<HH',b,base+12)
 for i in range(named+ids):
  ident,target=struct.unpack_from('<II',b,base+16+8*i);key=path+(ident,)
  if target&0x80000000:walk(target&0x7fffffff,key)
  else:
   data_rva,n=struct.unpack_from('<II',b,rsrc+target);r[key]=b[offset(data_rva):offset(data_rva)+n]
walk();manifest=next(v for k,v in r.items() if k[0]==24);check('launcher manifest asInvoker',ET.fromstring(manifest) is not None and b'level="asInvoker"' in manifest)
version=next(v for k,v in r.items() if k[0]==16);check('EXE version '+VERSION,all(v.encode('utf-16le') in version for v in [FILE_VERSION,VERSION]))
ico=(ROOT/'wad/Pesto.ico').read_bytes();good=True
for i in range(struct.unpack_from('<H',ico,4)[0]):
 n,off=struct.unpack_from('<II',ico,6+16*i+8);actual=next(v for k,v in r.items() if k[0]==3 and k[1]==i+1);good &= actual==ico[off:off+n]
check('EXE embeds original icon',good)
if not args.without_manifest:
 m=json.loads((ROOT/'wad/package.json').read_text('utf-8-sig'));check('package manifest version/count',m['Version']==VERSION and 12<=len(m['Files'])<=100)
 for e in m['Files']:check('package hash '+e['Path'],(ROOT/e['Path']).is_file() and sha((ROOT/e['Path']).read_bytes())==e['SHA256'])
st=subprocess.run([sys.executable,str(ROOT/'tools/stamp_version.py'),'--check'],capture_output=True,text=True,encoding='utf-8')
check('version stamped from tools/version.json',st.returncode==0,(st.stdout+st.stderr)[-800:])
# Vrai parseur PowerShell : seule preuve syntaxique valable (les contrôles lexicaux ci-dessus ne l'ont pas vue en RC23).
# Avec -Command, les arguments suivants sont concaténés au texte de la commande et $args reste vide :
# la racine passe par l'environnement.
PARSE=r"""$ErrorActionPreference='Stop';$out=foreach($f in (Get-ChildItem -LiteralPath $env:PESTO_PARSE_ROOT -Recurse -File -Filter *.ps1 | Where-Object { $_.Extension -eq '.ps1' })){$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e);[pscustomobject]@{Path=$f.FullName;Errors=@($e|ForEach-Object{'{0}:{1} {2}' -f $_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message})}};[pscustomobject]@{Engine=[string]$PSVersionTable.PSVersion;Edition=[string]$PSVersionTable.PSEdition;Files=@($out)}|ConvertTo-Json -Depth 4 -Compress"""
engine=shutil.which('powershell') or shutil.which('pwsh');parser='NOT_RUN'
if engine:
 r=subprocess.run([engine,'-NoProfile','-NonInteractive','-Command',PARSE],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600,env=dict(os.environ,PESTO_PARSE_ROOT=str(ROOT)))
 try:
  data=json.loads(r.stdout);files=data['Files'] if isinstance(data['Files'],list) else [data['Files']]
  parser='PowerShell '+data['Engine']+' '+data['Edition']
  check('real parser available',len(files)>0,parser)
  for f in files:
   errs=f['Errors'] if isinstance(f['Errors'],list) else ([f['Errors']] if f['Errors'] else [])
   check('real parser '+str(pathlib.Path(f['Path']).relative_to(ROOT)).replace('\\','/'),not errs,'; '.join(errs[:5]))
 except Exception as e:check('real parser run',False,(r.stderr or str(e))[:500])
else:
 print('NOT_RUN real PowerShell parser: neither powershell nor pwsh found')
 if args.require_parser:check('real parser available',False,'--require-parser')
report=dict(version=VERSION,kind='Portable source/XML/PE checks; NOT native PowerShell/WPF/AD execution',windowsExecuted=False,parser=parser,checks=checks,passed=sum(c['passed'] for c in checks),failed=sum(not c['passed'] for c in checks),exeSha256=sha(b),runtimeFunctions=len(allfn))
out=ROOT/'tests/pesto-portable-validation.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('RESULT',report['passed'],'passed',report['failed'],'failed; parser',parser+'; native Windows NOT executed')
sys.exit(bool(report['failed']))
