#!/usr/bin/env python3
"""Targeted lexical checks for RC3 callback scope. NOT Windows execution."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, re, sys
from pathlib import Path
from ps_lexical import functions, tokens

# The engine spread its functions over the components the core dot-sources. Indexing Pesto-Core.ps1 alone made
# block() raise KeyError on twelve relocated functions (the async core lives in Pesto-Async.ps1, the config
# repair window in Pesto-Configuration.ps1); check() swallowed each KeyError as a FAIL, so the controller
# reported 15 broken guards on a healthy tree and its own selftest could not tell a lost guard from a real
# defect. The corpus is now the core plus every dot-sourced component, as in ux_static_checks.py.
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")

def read_ps(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def corpus(core_path,wad):
    texts={'Pesto-Core.ps1':read_ps(core_path)};missing=[]
    for name in COMPONENT.findall(texts['Pesto-Core.ps1']):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing.append(name)
    return texts,missing

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source',type=Path)
    ap.add_argument('--wad',type=Path,help='engine components (default: <root>/wad)')
    ap.add_argument('--report',type=Path)
    args=ap.parse_args();root=args.root.resolve();source=args.source or root/'wad/Pesto-Core.ps1'
    wad=args.wad or root/'wad'
    raw=source.read_bytes();texts,missing_components=corpus(source,wad)
    s=texts['Pesto-Core.ps1']
    ff={};duplicates={}
    for file_name,text in texts.items():
        for name,span in functions(text).items():
            if name in ff:duplicates.setdefault(name,[ff[name][0]]).append(file_name)
            else:ff[name]=(file_name,span)
    checks=[]
    def check(name,body):
        try:
            detail=body();checks.append(dict(name=name,status='PASS',detail=detail))
        except Exception as e:checks.append(dict(name=name,status='FAIL',detail=str(e)))
    def require(value,msg):
        if not value:raise AssertionError(msg)
    def block(n):
        # A missing function is a FAIL that names it, never a KeyError whose message is just the function name:
        # the reader must be able to tell "this guard had nothing to read" from "this guard found a defect".
        if n not in ff:raise AssertionError('Function absent from the corpus (core and components): '+n)
        file_name,(a,b)=ff[n];return texts[file_name][a:b]
    check('Core and its dot-sourced components are all present, each function defined once',
          lambda:require(not missing_components and not duplicates,
                         'Missing components: '+str(missing_components)+'; duplicates: '+str(duplicates)))
    def no_private_module(n):
        require(not re.search(r'\.GetNewClosure\s*\(',block(n)),n+' still creates a private closure module')
    for name in ['Start-PestoAsyncOperation','Invoke-PestoAsyncTimerTick','Select-PCName','Refresh-Names','Load-OUChildren','Show-PestoConfigRepair']:
        check('No private closure in '+name,lambda name=name:no_private_module(name))
    def closure_audit():
        found=[];bad=[]
        for file_name in sorted(texts):
            text=texts[file_name]
            tt=tokens(text);stack=[];pairs={}
            for kind,a,b in tt:
                if kind=='{':stack.append(a)
                elif kind=='}':pairs[a]=stack.pop()
            for m in re.finditer(r'\.GetNewClosure\s*\(',text):
                before=text[:m.start()].rstrip()
                while before.endswith(')'):before=before[:-1].rstrip()
                require(before.endswith('}'),'Unrecognized closure syntax at '+str(m.start())+' in '+file_name)
                end=len(before)-1;start=pairs[end];body=text[start:end+1]
                refs=[]
                for kind,a,b in tokens(body):
                    value=body[a:b]
                    if kind=='word' and (value in ff or value.lower().startswith('script:') or value.lower().startswith('function:')):refs.append(value)
                line=text[:start].count('\n')+1
                found.append(dict(file=file_name,line=line,unsafe_references=sorted(set(refs))))
                if refs:bad.append(dict(file=file_name,line=line,refs=refs))
        require(not bad,'Unsafe private-closure lookups: '+json.dumps(bad))
        return found
    check('All remaining closures contain no script scope or Pesto function lookup',closure_audit)
    check('Timer delegate bound to the named function',lambda:require(
        '[System.EventHandler]${function:Invoke-PestoAsyncTimerTick}' in block('Start-PestoAsyncOperation') and
        '$timer.Add_Tick($tickHandler)' in block('Start-PestoAsyncOperation'),'Unbound or anonymous timer handler'))
    check('Per-timer identity registry kept separate from operation names',lambda:require(
        '$script:PestoAsyncTimerOperations[$timer]=$op' in block('Start-PestoAsyncOperation') and
        '$op=$script:PestoAsyncTimerOperations[$Sender]' in block('Invoke-PestoAsyncTimerTick'),'Timer identity registry missing'))
    check('Completed handler and timer registry entry removed',lambda:require(
        '$op.Timer.Remove_Tick($op.TickHandler)' in block('Invoke-PestoAsyncTimerTick') and
        '$script:PestoAsyncTimerOperations.Remove($op.Timer)' in block('Invoke-PestoAsyncTimerTick'),'Completed timer not detached'))
    check('Replaced operation cannot remove its successor',lambda:require(
        block('Invoke-PestoAsyncTimerTick').count('[object]::ReferenceEquals($script:PestoAsyncOperations[$op.Name],$op)')==3,
        'Reference equality guard missing'))
    check('Callback context packed separately from the result array',lambda:require(
        '$cbArgs[0] = $Argument' in block('Invoke-PestoAsyncCallback') and '$cbArgs[1]=$Context' in block('Invoke-PestoAsyncCallback') and
        'InvokeReturnAsIs($cbArgs)' in block('Invoke-PestoAsyncCallback'),'Result/context argument contract changed'))
    for name in ['Select-PCName','Refresh-Names','Load-OUChildren']:
        check('Explicit callback context in '+name,lambda name=name:require('-CallbackContext $context' in block(name),'Missing callback context'))
    check('Reentrancy guard restored in finally',lambda:require(
        '$op.TickBusy' in block('Invoke-PestoAsyncTimerTick') and 'finally{$op.TickBusy=$false}' in block('Invoke-PestoAsyncTimerTick'),'Tick reentrancy guard missing'))
    check('No synchronous PowerShell.Stop used on the UI thread',lambda:require(
        not re.search(r'(?:PowerShell|\$ps)\.Stop\s*\(',re.sub(r'<#[\s\S]*?#>|(?m:#[^\n]*$)', '', block('Invoke-PestoAsyncTimerTick')+block('Start-PestoAsyncOperation')+block('Stop-PestoAsyncOperation'))),
        'Synchronous worker Stop introduced'))
    check('Queue callback exceptions still preserve the security lock',lambda:require(
        'Fail-PestoQueueCallback -Failure $_' in block('Invoke-PestoAsyncCallback') and '$script:MutationUncertain=$true' in block('Invoke-PestoAsyncCallback'),
        'Queue callback safety guard removed'))
    check('Configuration save uses a named handler and button-local state',lambda:require(
        '[Windows.RoutedEventHandler]${function:Invoke-PestoConfigRepairSave}' in block('Show-PestoConfigRepair') and
        '$ctx=$Sender.Tag' in block('Invoke-PestoConfigRepairSave'),'Configuration handler still loses local commands'))
    check('Empty OU worker output filtered before building the tree',lambda:require(
        '$arr=@($children | Where-Object {$null -ne $_})' in block('Load-OUChildren'),'Null OU treated as a real child'))
    check('No global function export introduced',lambda:require(
        not any(re.search(r'(?im)^\s*function\s+global:',text) for text in texts.values()),'Global function pollution'))
    # Re-anchored, disclosed as a scope change. This guard demanded four windows titled "Pesto 17.0-RC13". The
    # product dropped the RC label: the engine constant is now '1.0' and titles read "Pesto 1.0 …". Demanding
    # the old literal would have guarded a release label the project no longer uses. What the guard protects is
    # that no window ships a stale version, so it now reads the engine constant and requires every window title
    # that carries a version to carry exactly that one — over all corpus files, not four of them.
    def windows_version():
        m=re.search(r"\$script:Pesto_VERSION\s*=\s*'([^']*)'",s)
        require(m is not None,"Moteur : $script:Pesto_VERSION introuvable")
        version=m[1]
        require(version.strip()!='','Moteur : version vide')
        titles=[];stale=[]
        for file_name in sorted(texts):
            for t in re.findall(r'Title="Pesto ([^"]*)"',texts[file_name]):
                titles.append((file_name,t))
                head=t.split(' ')[0].split('|')[0].strip()
                if head and (head[0].isdigit() or head[0]=='v') and head!=version:stale.append((file_name,t))
        require(not stale,'Stale window version: '+json.dumps(stale))
        require(titles,'Aucun titre de fenêtre trouvé dans le corpus')
        return {'version':version,'titled_windows':len(titles)}
    check('Every window title carries the engine version',windows_version)
    for name in ['tests/Run-AsyncTests.ps1','tests/Async-ScopeFixture.ps1']:
        def lex(name=name):
            data=(root/name).read_bytes();require(data.startswith(b'\xef\xbb\xbf'),'UTF-8 BOM missing')
            text=data.decode('utf-8-sig');return {'lexical_tokens':len(tokens(text)),'native_execution':False}
        check(name+' encoding and delimiters',lex)
    check('Native regression runner uses a child script scope',lambda:require(
        "& (Join-Path $PSScriptRoot 'Async-ScopeFixture.ps1')" in (root/'tests/Run-AsyncTests.ps1').read_text(encoding='utf-8-sig'),
        'Fixture not called through the invocation operator'))
    failed=sum(c['status']=='FAIL' for c in checks)
    report=dict(version='17.0-RC13',utc=dt.datetime.now(dt.timezone.utc).isoformat(),source_sha256=hashlib.sha256(raw).hexdigest(),
        files=sorted(texts),
        scope='TARGETED STATIC ONLY: lexical structure, not PowerShell binding or WPF runtime execution',
        totals=dict(checks=len(checks),passed=len(checks)-failed,failed=failed),checks=checks)
    path=args.report or root/'tests/async-static-report.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    for c in checks:print(c['status']+' '+c['name']+((' : '+str(c['detail'])) if c['status']=='FAIL' else ''))
    print(json.dumps(report['totals']));return bool(failed)
if __name__=='__main__':sys.exit(main())
