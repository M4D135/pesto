#!/usr/bin/env python3
"""RC8 local queue removal source contracts. Not PowerShell/WPF/AD execution."""
from pathlib import Path
import argparse, datetime as dt, hashlib, json, re, xml.etree.ElementTree as ET
from ps_lexical import functions, tokens
P='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
X='http://schemas.microsoft.com/winfx/2006/xaml'
NS={'p':P,'x':X};NAME='{'+X+'}Name'
# The engine spread its functions over the components the core dot-sources, and the window template left the
# core here-doc for wad/Pesto-Shell.xaml. Indexing Pesto-Core.ps1 alone made this checker die on
# ValueError('Main XAML absent') before it evaluated a single contract: it guarded nothing any more.
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
SHELL_XAML='Pesto-Shell.xaml'

def read_ps(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def corpus(core_path,wad):
    texts={'Pesto-Core.ps1':read_ps(core_path)};missing=[]
    for name in COMPONENT.findall(texts['Pesto-Core.ps1']):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing.append(name)
    template=wad/SHELL_XAML
    return texts,missing,(read_ps(template) if template.is_file() else '')

def contracts(texts,xaml_text,missing_components):
    s=texts['Pesto-Core.ps1'];out=[]
    spans={};duplicates={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():
            if function in spans:duplicates.setdefault(function,[spans[function][0]]).append(file_name)
            else:spans[function]=(file_name,span)
    ff=spans
    def check(n,test,detail=None):
        row={'name':n,'status':'PASS' if test else 'FAIL'}
        if detail is not None:row['detail']=detail
        out.append(row)
    def block(n):
        # A missing function must never read as an empty body: a guard that tests an empty body reports PASS
        # on nothing. It is recorded as a FAIL naming the function instead.
        if n not in spans:
            check('Function available to the guards: '+n,False,'Function absent from the corpus (core and components)')
            return ''
        file_name,(a,b)=spans[n];return texts[file_name][a:b]
    check('Core and its dot-sourced components are all present, each function defined once',
          not missing_components and not duplicates,{'missing_components':missing_components,'duplicates':duplicates})
    check('Core loads the main window template by name',"Join-Path $PSScriptRoot '"+SHELL_XAML+"'" in s)
    check('Main window template exists',bool(xaml_text))
    x=None
    if xaml_text:
        try:x=ET.fromstring(xaml_text)
        except Exception as e:check('Main window template is well-formed XML',False,str(e))
    names={n.get(NAME):n for n in x.iter() if n.get(NAME)} if x is not None else {}
    parents={c:p for p in (x.iter() if x is not None else []) for c in p}
    check('Main window template declares the controls the guards read','BtnDelete' in names and 'Grid' in names,
          sorted(names))
    ancestors=[]
    node=names.get('BtnDelete')
    while node is not None and node in parents:
        node=parents[node];ancestors.append(node)
    check('Explicit label Retirer de la file',names.get('BtnDelete') is not None and names['BtnDelete'].get('Content')=='Retirer de la file')
    check('Removal visible outside advanced expander','BtnDelete' in names and not any(n.get(NAME)=='QueueTools' for n in ancestors))
    check('Disabled tooltips retained',names.get('BtnDelete') is not None and names['BtnDelete'].get('ToolTipService.ShowOnDisabled')=='True')
    check('Native DataGrid deletion stays disabled',names.get('Grid') is not None and names['Grid'].get('CanUserDeleteRows')=='False')
    check('Button uses shared removal policy, without editing lock','$BtnDelete.IsEnabled=$removeState.CanRemove' in block('Update-QueueButtons') and '$BtnDelete.IsEnabled=(-not $locked -and $selected -and -not $editing)' not in s)
    policy=block('Get-PestoQueueRemovalState');remove=block('Remove-PestoQueueRow');delete=block('Delete-SelectedRow')
    check('Policy retains worker and preflight locks',all(t in policy for t in ('$script:Running','$script:PreflightRunning')))
    check('Policy validates exact table membership',all(t in policy for t in ('[object]::ReferenceEquals($Row.Table,$script:table)','$script:table.Rows.IndexOf($Row)','DataRowState]::Deleted')))
    check('Selected DataRowView, never checked rows or view index',all(t in delete for t in ('[System.Data.DataRowView]','$row=$Grid.SelectedItem.Row')) and 'SelectedIndex' not in delete+remove)
    check('Explicit confirmation before removal','Confirm-YesNo -Msg $message -Confirm $true' in delete and delete.find('Confirm-YesNo')<delete.find('Remove-PestoQueueRow -Row $row'))
    check('Editing discard explicitly explained',all(t in delete for t in ('non enregistrés','state.EndsEdit','Exit-EditMode')))
    check('Remove revalidates policy after modal','Get-PestoQueueRemovalState -Row $Row' in remove and 'if(-not $state.CanRemove){throw $state.Help}' in remove)
    check('Persist removal before reporting success','Save-PestoQueueCheckpoint\n' in remove and 'Save-PestoQueueCheckpointSafe' not in remove and remove.find('Save-PestoQueueCheckpoint')<remove.find('return [pscustomobject]'))
    check('Restore same row and data after checkpoint failure',all(t in remove for t in ('$values=$Row.ItemArray.Clone()','$Row.ItemArray=$values','$script:table.Rows.InsertAt($Row,','$script:EDIT_ROW_INDEX=$oldEdit','throw $errorRecord')))
    check('Preserve another editing target by identity','$script:table.Rows.IndexOf($editRow)' in remove)
    check('Remove only deleted plan cache','[void]$script:PreflightCache.Remove($key)' in remove and '$script:PreflightCache=@{}' not in remove)
    empty=block('Restore-PestoQueueCheckpoint')
    check('Restore safety lock before empty queue return',empty.find('$script:MutationUncertain=[bool]$uncertain')>=0 and empty.find('$script:MutationUncertain=[bool]$uncertain')<empty.find('if(-not $rows.Count)'))
    code=delete+remove+policy
    words={code[a:b] for k,a,b in tokens(code) if k=='word'}
    forbidden={'Rename-Computer','Add-Computer','Move-ADObject','Set-ADObject','Remove-ADComputer','Remove-ADObject','Restart-Computer','Run-Queue','Reset-PestoSafetyLock'}
    check('Removal path has no AD or safety-unlock calls',not (words&forbidden) and '$script:MutationUncertain=' not in remove)
    check('Edit cancellation has an explicit label',"$BtnEdit.Content = 'Annuler la modification'" in block('Enter-EditMode'))
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source',type=Path,help='engine core (default: <wad>/Pesto-Core.ps1)')
    ap.add_argument('--wad',type=Path,help='engine components and templates (default: <root>/wad)')
    ap.add_argument('--report',type=Path)
    a=ap.parse_args();root=a.root
    wad=a.wad or root/'wad';core_path=a.source or wad/'Pesto-Core.ps1'
    raw=core_path.read_bytes();texts,missing_components,xaml_text=corpus(core_path,wad)
    s=texts['Pesto-Core.ps1'];checks=contracts(texts,xaml_text,missing_components)
    spans={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():spans.setdefault(function,(file_name,span))
    ff=spans
    test=(root/'tests/Run-QueueRemovalTests.ps1').read_text(encoding='utf-8-sig');tf=functions(test);tt=tokens(test)
    load=re.search(r'\$load=@\((.*?)\)\s*foreach',test,re.S)
    checks.append({'name':'Isolated test declares its function whitelist','status':'PASS' if load else 'FAIL',
                   'detail':'$load=@(...) not found in Run-QueueRemovalTests.ps1' if not load else ''})
    required=set(re.findall(r"'([^']+)'",load[1])) if load else set()
    missing={}
    for name in required:
        if name not in spans:missing[name]=['function absent from the corpus'];continue
        file_name,span=spans[name];block=texts[file_name][span[0]:span[1]]
        words={block[x:y] for k,x,y in tokens(block) if k=='word'}
        deps=(words&set(ff))-required-set(tf)
        # Restore's nonempty branch is intentionally not entered by these tests.
        deps-= {'Test-PestoComputerName','Convert-Value-TF','Get-PestoRowPlanText'} if name=='Restore-PestoQueueCheckpoint' else set()
        if deps:missing[name]=sorted(deps)
    checks.append({'name':'Isolated test lexical structure and required function dependencies','status':'PASS' if not missing else 'FAIL','detail':missing,'lexical_tokens':len(tt)})
    checks.append({'name':'Test launcher and master suite packaged','status':'PASS' if 'Run-QueueRemovalTests.ps1' in (root/'TEST_FILE.cmd').read_text() and 'Run-QueueRemovalTests.ps1' in (root/'tests/Run-AllTests.ps1').read_text(encoding='utf-8-sig') else 'FAIL'})
    baseline=json.loads((root/'tests/current-core-baseline.json').read_text());changes=[];obsolete=[]
    for name,h in baseline['normalized_function_sha256'].items():
        # The live reference is tests/current-core-baseline.json, which the repository can re-derive. A name in
        # the reference that is gone from the corpus is still reported as obsolete, never skipped: silently
        # dropping it is how a stale reference turns into a green guard.
        if name not in spans:obsolete.append(name);continue
        file_name,span=spans[name]
        if hashlib.sha256(texts[file_name][span[0]:span[1]].encode()).hexdigest()!=h:changes.append(name)
    allowed=set(baseline.get('intentional_changes',[]))
    # RC10 is read only to report the historical delta in this row's detail. Its source package is gone and 150
    # of its 269 names predate the GP→Pesto rename, so it can no longer gate anything honestly — but the green
    # live guard above must not read as evidence that RC10's code survived.
    historical_path=root/'tests/rc10-core-baseline.json'
    history=None
    if historical_path.is_file():
        rc10=json.loads(historical_path.read_text())['normalized_function_sha256']
        gone=[n for n in rc10 if n not in spans]
        history={'historical_file':'tests/rc10-core-baseline.json','historical_functions':len(rc10),
                 'names_gone_since_historical':len(gone),'names_gone_examples':sorted(gone)[:8],
                 'changed_bodies_since_historical':sum(1 for n in rc10 if n in spans and
                     hashlib.sha256(texts[spans[n][0]][spans[n][1][0]:spans[n][1][1]].encode()).hexdigest()!=rc10[n])}
    checks.append({'name':'Queue removal/recovery preserved outside declared changes (socle courant)','status':'PASS' if not obsolete and set(changes)==allowed else 'FAIL',
                   'intentional_changes':changes,'baseline_functions':len(baseline['normalized_function_sha256']),
                   'baseline_commit':baseline.get('generated_from_commit'),
                   'obsolete_baseline_names':len(obsolete),'obsolete_examples':sorted(obsolete)[:8],
                   'rc10_history_informational_only':history})
    negative=[]
    for name,mutant in {
        'Reintroduce edit-mode block':'$BtnDelete.IsEnabled=$removeState.CanRemove|$BtnDelete.IsEnabled=(-not $locked -and $selected -and -not $editing)',
        'Drop persistence':'        Save-PestoQueueCheckpoint\n    }catch{|        # no persistence\n    }catch{',
        'Use view index instead of row identity':'$row=$Grid.SelectedItem.Row|$row=$script:table.Rows[$Grid.SelectedIndex]',
        'Lose rollback values':'$Row.ItemArray=$values|# no data rollback',
        'Bypass confirmation':'Confirm-YesNo -Msg $message -Confirm $true|Confirm-YesNo -Msg $message -Confirm $false',
    }.items():
        old,new=mutant.split('|')
        # The defect is injected wherever the term actually lives in the corpus. An anchor that disappeared is
        # recorded as undetected, which still fails the run and keeps the report readable.
        if not any(old in v for v in texts.values()):
            negative.append({'name':name,'detected':False,'failed_checks':[],'error':'ancre absente du corpus : contrôle vacant, à ré-ancrer'})
            continue
        mutated={k:(v.replace(old,new) if old in v else v) for k,v in texts.items()}
        failed=[c['name'] for c in contracts(mutated,xaml_text,missing_components) if c['status']=='FAIL']
        negative.append({'name':name,'detected':bool(failed),'failed_checks':failed})
    failed=sum(c['status']=='FAIL' for c in checks)
    report={'version':'17.0-RC13','utc':dt.datetime.now(dt.timezone.utc).isoformat(),'source_sha256':hashlib.sha256(raw).hexdigest(),'files':sorted(texts),'scope':'Source/XML contracts only. Neither native PowerShell parser nor Windows/WPF/AD execution.','summary':{'checks':len(checks),'passed':len(checks)-failed,'failed':failed},'checks':checks,'negative_controls':negative,'windows_cases_supplied':len(re.findall(r"(?m)^    Case '",test)),'windows_cases_executed':False}
    (a.report or root/'tests/queue-removal-static-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    for c in checks:print(c['status'],c['name'])
    print(json.dumps(report['summary']))
    print('Injected defects detected:',sum(1 for t in negative if t['detected']),'/',len(negative))
    return int(failed>0 or not all(t['detected'] for t in negative))
if __name__=='__main__':raise SystemExit(main())
