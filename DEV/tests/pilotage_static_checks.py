#!/usr/bin/env python3
"""RC5 source contracts, not a PowerShell parser or runtime test.

Checks executable tokens as well as structural ordering, actual XML templates,
worker function closure, test extraction closure, and packaging.
Use --source to probe deliberately broken temporary variants.
"""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from ps_lexical import functions, tokens

ROOT=Path(__file__).resolve().parents[1]
# The engine spread its functions over the components the core dot-sources. Indexing Pesto-Core.ps1 alone
# made this checker die on KeyError inside the read-only worker whitelist: it guarded nothing any more, and
# its own selftest turned that crash into a FileNotFoundError. The corpus is the core plus every dot-sourced
# component, as in ux_static_checks.py; --wad points the guards at a mutated copy.
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
# The main grid template left the core here-doc: the core now loads this file by name.
SHELL_XAML='Pesto-Shell.xaml'

def read_ps(path):
    return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

NEW_NAMES={
'Get-PestoRowPlanText','Get-PestoPlanSignature','Get-PestoIdentityChangeReason','ConvertTo-PestoFilterLiteral',
'Get-PestoQueueFilterExpression','ConvertFrom-PestoComputerList','New-PestoBulkPlan','Get-PestoPreflightSource',
'Invoke-PestoReadOnlyPreflight','Get-PestoResultGuidance','New-PestoQueueReportHtml','Reset-PestoRowPreflight',
'Get-PestoSelectedQueueIndex','Update-PestoQueueFilter','Invoke-PestoQueueSearchTick','Set-PestoVisibleSelection',
'Update-PestoPilotage','Update-PestoPreflightFreshness','Get-PestoPreflightRunIssues','Get-PestoPreflightConfirmationText',
'Start-PestoQueuePreflight','Complete-PestoQueuePreflight','Stop-PestoQueuePreflight','Invoke-PestoPilotagePulse',
'Start-PestoPilotagePulse','Stop-PestoPilotagePulse','Show-PestoBulkPlanner','Invalidate-PestoBulkPreview',
'Invoke-PestoBulkPrepare','Invoke-PestoBulkApply','Export-PestoHtmlReport','Save-PestoRunHistory','Show-PestoRunHistory'}

def validate(source_path, report_path, wad=None):
    raw=source_path.read_bytes();s=raw.decode('utf-8-sig').replace('\r\n','\n');results=[]
    wad=wad or ROOT/'wad'
    texts={'Pesto-Core.ps1':s};missing_components=[]
    for name in COMPONENT.findall(s):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing_components.append(name)
    s_all='\n'.join(texts.values())
    spans={};duplicates={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():
            if function in spans:duplicates.setdefault(function,[spans[function][0]]).append(file_name)
            else:spans[function]=(file_name,span)
    def check(name, condition, message='Source contract failed'):
        try:
            ok=condition() if callable(condition) else bool(condition)
            if not ok:raise ValueError(message)
            results.append(dict(name=name,status='PASS',detail=''))
        except Exception as e:results.append(dict(name=name,status='FAIL',detail=str(e)))
    check('Core and its dot-sourced components are all present, each function defined once',
          not missing_components and not duplicates,
          'Missing components: '+str(missing_components)+'; functions defined in several files: '+str(duplicates))
    fs=spans
    def body(name):
        # A missing function is a FAIL with a message, never a KeyError: a checker that dies mid-file
        # guards nothing and looks like a broken toolchain instead of a lost guard.
        if name not in spans:
            check('Function available to the guards: '+name,False,'Function absent from the corpus (core and components)')
            return ''
        file_name,(a,b)=spans[name];return texts[file_name][a:b]
    def words(text):return [text[a:b] for k,a,b in tokens(text) if k=='word']
    check('All RC5 root functions exist', NEW_NAMES <= set(fs))
    for rel in ('tests/Run-PilotageTests.ps1','tests/Run-AllTests.ps1'):
        p=ROOT/rel
        check(rel+' UTF-8 BOM and balanced delimiters',lambda p=p: p.read_bytes().startswith(b'\xef\xbb\xbf') and len(functions(p.read_text(encoding='utf-8-sig'))) >= 0)
    # The conventional name types gained 'V' (Virtuel) after this guard was written, which made it red on a
    # deliberate extension of the naming convention. The set is now required exactly, and paired with the UI
    # mapping that produces it: a fourth letter cannot appear without re-anchoring this guard on purpose.
    check('Generated-name type stays in the closed P/S/V vocabulary',
          "$TypeLetter -notin @('P','S','V')" in body('New-PestoBulkPlan')
          and "TypeLetter=$(switch([string]$CbType.SelectedItem){'Fixe'{'S'};'Virtuel'{'V'};default{'P'}})" in body('Show-PestoBulkPlanner'),
          'Generated name type is no longer the closed P/S/V set')
    check('Bulk caps 200, no silent list deduplication', '$list.Count -gt 200' in body('ConvertFrom-PestoComputerList') and '$seen.ContainsKey' in body('ConvertFrom-PestoComputerList') and 'throw' in body('ConvertFrom-PestoComputerList'))
    check('Bulk reserves existing and queued target names', '$used[$name]=$true' in body('New-PestoBulkPlan') and '$used[[string]$row.Nouveau_Nom]=$true' in body('New-PestoBulkPlan'))
    check('Bulk numbers 001..999 and hard-fails exhaustion', "for($i=1;$i -le 999;$i++)" in body('New-PestoBulkPlan') and "if(-not $new){throw" in body('New-PestoBulkPlan'))
    check('Bulk never selects/reboots newly prepared rows', '$r.Traiter=$false;$r.Reboot=$false' in body('New-PestoBulkPlan'))
    check('Bulk computes move with the shared site rule', 'Get-PestoRenameMoveDecision' in words(body('New-PestoBulkPlan')) and '$r.Deplacer=[bool]$decision.Move' in body('New-PestoBulkPlan'))
    check('Bulk refuses ambiguous and out-of-scope sources', "$index[$name].DistinguishedName -ine" in body('New-PestoBulkPlan') and 'Test-PestoOUInConfiguredScope $sourceOU' in body('New-PestoBulkPlan'))
    b=body('Invoke-PestoBulkApply')
    check('Bulk applies a copied table only after rechecking conflicts',b.index('$targets.ContainsKey') < b.index('$copy=$script:table.Copy()') < b.index('$script:table=$copy'))
    check('Bulk input edits invalidate the preview', '$s.Candidate=$null' in body('Invalidate-PestoBulkPreview') and '${function:Invalidate-PestoBulkPreview}' in body('Show-PestoBulkPlanner'))
    pre=body('Get-PestoPreflightSource');match=re.search(r'\$names=@\((.*?)\)',pre,re.S)
    check('Read-only worker whitelist is declared in the source',bool(match),'$names=@(...) list not found in Get-PestoPreflightSource')
    white=re.findall(r"'([A-Za-z][A-Za-z0-9-]+)'",match.group(1)) if match else []
    check('Read-only worker function list is complete',bool(white) and all(n in fs for n in white))
    refs=set()
    for n in white:refs.update(set(words(body(n))) & set(fs))
    check('Read-only worker whitelist is lexically closed',refs <= set(white),str(sorted(refs-set(white))))
    bad={'Rename-Computer','Add-Computer','Remove-Computer','Set-ADComputer','Set-ADObject','Move-ADObject','Remove-ADObject','Restart-Computer','Invoke-Command','Invoke-Expression','Start-Process','RenameComputer','MoveComputer','Go'}
    check('Read-only worker whitelist contains no mutation or arbitrary execution',not(refs & bad) and not(set(w for n in white for w in words(body(n))) & bad))
    p=body('Invoke-PestoReadOnlyPreflight')
    check('Read-only AD lookup detects ambiguous sources on one DC', '-ResultSetSize 2' in p and '$found.Count -ne 1' in p and 'Server=[string]$Request.DC' in p)
    check('Read-only scan checks GUID, scope and protection policy', all(x in p for x in ('Get-PestoIdentityChangeReason','Test-PestoOUInConfiguredScope $observedOU','if(-not $Request.ClearProtection){throw')))
    check('ICMP failures are warnings, not a blocked computer', "else{$warnings.Add('Pas de réponse ICMP." in p and "catch{$warnings.Add('Sonde ICMP indisponible." in p)
    check('Probe never claims mutation-right certification', 'non certifiés par ce contrôle' in p)
    b=body('Start-PestoQueuePreflight')
    check('Demo control returns before starting a read worker', b.index('if($script:GUI)') < b.index('Complete-PestoQueuePreflight -Result') < b.index('Start-PestoAsyncOperation'))
    check('Preflight uses runspace, deadline and named callbacks', '-TimeoutSec $script:PreflightTimeout -CallbackContext $context' in b and 'Get-PestoPreflightBudget $items.Count' in b and '-OnSuccess {param($r,$ctx) Complete-PestoQueuePreflight' in b and '-OnError {param($e,$ctx) Complete-PestoQueuePreflight' in b)
    check('Preflight guards running, editing and directory refresh',all(t in b for t in ('$script:Running -or $script:PreflightRunning','$script:EDIT_ROW_INDEX -ge 0',"Test-PestoAsyncOperationRunning 'DirectoryRefresh'",'$rows.Count -gt 200')))
    b=body('Complete-PestoQueuePreflight')
    check('Late preflight result rejected by generation', '$Context.Generation -ne $script:PreflightGeneration' in b)
    check('Preflight refuses partial, duplicate and invalid results',all(x in b for x in ('@($Result.Results).Count -ne @($Context.Keys).Count','$results.ContainsKey($r.Key)','Horodatage du contrôle invalide.','GUID du contrôle invalide.')))
    check('Preflight application failure clears in-memory approvals', '$script:PreflightCache=@{}' in b and "$row.Precontrole='À REFAIRE'" in b)
    check('Preflight UI unlocks in finally', "}finally{\n        $script:PreflightRunning=$false" in b)
    b=body('Stop-PestoQueuePreflight')
    check('Cancellation preserves complete rows then invalidates late callbacks, without mutations', b.index('$script:PreflightProgress.Cancelled=$true') < b.index("Stop-PestoAsyncOperation 'QueuePreflight'") < b.index('Complete-PestoQueuePreflight -Failure') < b.index('$script:PreflightGeneration=') and not(set(words(b))&bad))
    check('No new script-private closures',all('GetNewClosure' not in body(n) for n in NEW_NAMES))
    check('New timers use named script-bound delegates', all(x in s_all for x in ('${function:Invoke-PestoPilotagePulse}','${function:Invoke-PestoQueueSearchTick}')))
    check('Plan fingerprint includes mutable actions and AD identity, not credentials',all(x in body('Get-PestoPlanSignature') for x in ('$Row.Nom_du_PC','$Row.Nouveau_Nom','$Row.Objet_GUID','$Row.Reboot','$script:SIM','$script:OU[\'ROOT\']')) and 'Credential' not in words(body('Get-PestoPlanSignature')))
    check('Known block does not expire into authorization', "if($r.State -eq 'BLOQUÉ'){$row.Precontrole='BLOQUÉ';continue}" in body('Update-PestoPreflightFreshness') and "$result.State -eq 'BLOQUÉ'" in body('Get-PestoPreflightRunIssues'))
    check('Freshness matches the two-minute execution gate and rejects clock reversal', '$age -lt 0 -or $age -gt 120' in body('Update-PestoPreflightFreshness'))
    check('Prepared identity passed into mutation worker',all(x in s_all for x in ('ObjectGuid=[string]$item.Row.Objet_GUID','$script:ExpectedObjectGuid=[string]$Request.ObjectGuid','$script:ExpectedSourceOU=[string]$Request.CurrentOU')))
    for fn,mutation in [('RenameComputer','@(Rename-Computer'),('MoveComputer','Set-ADObject -Identity')]:
        b=body(fn)
        check(fn+' verifies source identity before a mutation',b.index('Get-PestoIdentityChangeReason') < b.index(mutation) and 'if($drift){return New-ActionResult' in b)
    check('Filtered editing resolves actual row, never view index', '$script:table.Rows.IndexOf($Grid.SelectedItem.Row)' in body('Get-PestoSelectedQueueIndex') and '$Grid.SelectedIndex' not in body('Get-PestoSelectedQueueIndex'))
    b=body('Set-PestoVisibleSelection')
    check('Visible checkbox changes materialize filtered rows first',b.index('$visible=@(foreach')<b.index('foreach($r in $visible)') and "elseif($r.Statut -in @('','KO','ANNULÉ','NON LANCÉ'))" in b)
    check('RowFilter literal escaping includes quote, brackets and wildcards',all(x in body('ConvertTo-PestoFilterLiteral') for x in ('[[]','[]]','[*]','[%]', '.Append("\'\'")')))
    check('Hidden selected rows explicitly warned at confirmation',all(x in body('Get-PestoPreflightConfirmationText') for x in ('masquées par le filtre','mais seront exécutées')))
    check('Run queue uses preflight blocks and fresh/hidden confirmation',all(x in body('Run-Queue') for x in ('Get-PestoPreflightRunIssues','Get-PestoPreflightConfirmationText')))
    check('Reports escape HTML, suppress resources and preserve per-result mode',all(x in body('New-PestoQueueReportHtml') for x in ('[Net.WebUtility]::HtmlEncode','Protect-PestoLogText',"default-src 'none'",'HISTORIQUE NON QUALIFIÉ','$r.Mode_Resultat')))
    check('History keeps only explicit summaries, bounded to 100',all(x in body('Save-PestoRunHistory') for x in ('Select-Object -Last 99','RunId=[string]$State.RunId','Mode=[string]$State.Mode')) and '$State|ConvertTo-Json' not in body('Save-PestoRunHistory'))
    check('Checkpoint read/write both bounded at 16 MiB','GetByteCount($json) -gt 16MB' in body('Save-PestoQueueCheckpoint') and '.Length -gt 16MB' in body('Restore-PestoQueueCheckpoint'))
    check('Imported data never carries session controls or GUID pins',"'Objet_GUID'" not in body('Import-Queue') and "$r.Precontrole='À CONTRÔLER'" in body('Import-Queue'))
    # Examine the actual main grid column order and bindings, not an invented preview. The template left the
    # core here-doc and lives in wad/Pesto-Shell.xaml, which the core loads by name: both halves are guarded,
    # so the template can be neither dropped nor swapped for another file.
    check('Core loads the main grid template by name', "Join-Path $PSScriptRoot '"+SHELL_XAML+"'" in s,
          'Core no longer loads '+SHELL_XAML+' from $PSScriptRoot')
    xaml_path=wad/SHELL_XAML
    xaml=xaml_path.read_bytes().decode('utf-8-sig').replace('\r\n','\n') if xaml_path.is_file() else ''
    check('Main grid template exists',bool(xaml),'Main XAML absent: '+str(xaml_path))
    x=None
    if xaml:
        try:x=ET.fromstring(xaml)
        except Exception as e:check('Main grid template is well-formed XML',False,str(e))
    if x is not None:
        ns={'w':'http://schemas.microsoft.com/winfx/2006/xaml/presentation'};xn='{http://schemas.microsoft.com/winfx/2006/xaml}Name'
        grids=[e for e in x.iter() if e.attrib.get(xn)=='Grid']
        check('Main grid template declares the queue grid',bool(grids),'no element named Grid')
        if grids:
            grid=grids[0];cols=grid.find('w:DataGrid.Columns',ns)
            check('Queue grid declares its columns',cols is not None,'DataGrid.Columns absent')
            if cols is not None:
                bindings=[e.attrib.get('Binding') for e in cols]
                check('Before/after names first, source column stays frozen', bindings[:4]==['{Binding Traiter}','{Binding Nom_du_PC}','{Binding Nouveau_Nom}','{Binding Plan}'] and grid.attrib.get('FrozenColumnCount')=='2')
    for rel in ('TEST_PILOTAGE.cmd','TEST_TOUT.cmd'):
        b=(ROOT/rel).read_bytes();text=b.decode('ascii')
        check(rel+' x64 STA and exit code propagation',all(x in text for x in ('DisableDelayedExpansion','Sysnative','-NoProfile -STA -ExecutionPolicy RemoteSigned','exit /b %Pesto_TEST_EXIT%')))
    test=(ROOT/'tests/Run-PilotageTests.ps1').read_text(encoding='utf-8-sig')
    check('Native tests isolate external reads and mutations',all(x in test for x in ('Parser]::ParseFile','function Get-ADComputer','function Move-ADObject {throw','function Rename-Computer {throw','Host=$script:SourceName')))
    # All newly introduced dependencies of extracted functions must be extracted or mocked.
    for rel in ('tests/Run-PilotageTests.ps1','tests/Run-EngineTests.ps1','tests/Run-RC4Tests.ps1'):
        text=(ROOT/rel).read_text(encoding='utf-8-sig');lm=re.search(r'\$load=@\((.*?)\)\s*\nforeach',text,re.S)
        loaded=set(re.findall(r"'([A-Za-z][A-Za-z0-9-]+)'",lm.group(1)));mocked=set(functions(text));needs=set()
        for n in loaded:needs.update(set(words(body(n)))&NEW_NAMES)
        check(rel+' new extracted-function dependencies present',needs <= (loaded|mocked),str(sorted(needs-(loaded|mocked))))
    build=(ROOT/'tools/Build-Pesto.ps1').read_text(encoding='utf-8-sig')
    check('Build aborts on every failing native step',
          build.count('if($LASTEXITCODE -ne 0){throw')>=5 and "throw 'EXE et composants non concordants.'" in build,
          'A failing native step can be ignored before build')
    # Build-Pesto.ps1 runs no native suite any more (the same split RC4 records): the suites are invoked by
    # tests/Run-AllTests.ps1, which honours every child exit code. The guarantee is guarded where it lives
    # now, and it is no longer claimed as a property of the build.
    alltests=(ROOT/'tests/Run-AllTests.ps1').read_text(encoding='utf-8-sig')
    check('Native suites run outside the build and a failing one stops the run',
          'Run-PilotageTests.ps1' in alltests and 'if($LASTEXITCODE -ne 0){$failures.Add($suite)}' in alltests
          and "throw ('Suites en échec : '" in alltests,
          'A failing native suite no longer stops anything')
    check('No fabricated native results shipped',not any((ROOT/'tests').glob('windows-*-results.json')) and not (ROOT/'tests/windows-test-results.json').exists())
    failed=sum(r['status']=='FAIL' for r in results)
    report={'version':'17.0-RC5','utc':dt.datetime.now(dt.timezone.utc).isoformat(),'scope':'Source/lexical/XML contracts only, not PowerShell/WPF/AD execution','source_sha256':hashlib.sha256(raw).hexdigest(),'files':sorted(texts),'summary':{'checks':len(results),'passed':len(results)-failed,'failed':failed},'checks':results}
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for r in results:print(r['status']+' '+r['name']+(' : '+r['detail'] if r['detail'] else ''))
    print(json.dumps(report['summary']))
    return failed

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,default=ROOT/'wad/Pesto-Core.ps1');ap.add_argument('--wad',type=Path,help='engine components and templates (default: <root>/wad)');ap.add_argument('--report',type=Path,default=ROOT/'tests/pilotage-static-report.json');args=ap.parse_args()
    sys.exit(1 if validate(args.source,args.report,args.wad) else 0)
