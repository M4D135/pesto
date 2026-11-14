#!/usr/bin/env python3
"""Negative controls for RC4 static guards. Never executes PowerShell or AD."""
from pathlib import Path
import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
CHECKER=root/'tests/rc4_static_checks.py'
# The engine spread its functions over the components the core dot-sources, so a mutation anchor can live
# in any of them. The whole wad/*.ps1 corpus is copied and only the file that really carries the anchor is
# mutated: copying and mutating Pesto-Core.ps1 alone made three of these defects unreachable, and the
# checker then died on KeyError before writing any report, which surfaced here as a FileNotFoundError
# instead of a lost guard. Each defect also names the guard that must catch it: a non-zero exit caused by
# unrelated collateral damage is not a detection.
variants=[
    ('null_backup_regression', '[IO.File]::Replace($tmp,$full,[System.Management.Automation.Language.NullString]::Value)', '[IO.File]::Replace($tmp,$full,$null)',
     ('True null passed directly to File.Replace',)),
    ('site_equality_inverted', '$r.SiteChanged=($old -ine $new)', '$r.SiteChanged=($old -ieq $new)',
     ('Rename move flag derived from unequal site codes',)),
    ('implicit_move_on_site_selection', 'if($script:INDOMAIN){$ChkMove.IsChecked=$false}', 'if($script:INDOMAIN){$ChkMove.IsChecked=$true}',
     ('Selecting a site does not force a standalone move',)),
    # Replace all queue-normalization call sites for that deliberate defect.
    ('missing_queue_normalization', '$decision=Update-PestoQueueRenamePlan -Row $r', '$decision=[pscustomobject]@{Valid=$true;Reason="bad mock"}',
     ('Single decision integrated into Show-PestoQueuePreview','Single decision integrated into Run-Queue',
      'Confirmation contains normalized rename and move counts')),
    ('checkpoint_claimed_as_worker_failure', 'Complete-PestoQueueNotStarted -Failure $_;return', 'Complete-PestoQueueItem -Failure $_;return',
     ('Local save failure classified before the async worker exists',)),
    ('unreviewed_mutation_added', 'if($decision.Move -and -not $Deplacer)', 'if($false)',
     ('Worker never adds an unreviewed move',)),
    ('rename_missing_result_ignored', 'if(-not $renameResult){return New-ActionResult 97', 'if($false){return New-ActionResult 97',
     ('Move follows successful rename and absent result stops flow',)),
]

def read(path):
    return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def copy_corpus(destination):
    destination.mkdir(parents=True,exist_ok=True)
    for source in sorted((root/'wad').glob('*.ps1')):
        shutil.copy2(source,destination/source.name)
    return destination

def run_checker(corpus,report):
    return subprocess.run([sys.executable,str(CHECKER),'--root',str(root),'--wad',str(corpus),
                           '--source',str(corpus/'Pesto-Core.ps1'),'--report',str(report)],
                          capture_output=True,text=True,timeout=120)

def last_line(text):
    lines=[line for line in text.strip().splitlines() if line.strip()]
    return lines[-1] if lines else 'aucune sortie'

def write_report(results,baseline_status):
    # Written on every exit path, including the refused one: leaving the previous green report on disk
    # next to a red run is how a broken harness keeps reading as healthy.
    report=dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                scope='Negative controls for SOURCE GUARDS ONLY; not .NET or PowerShell execution',
                baseline=baseline_status,total=len(results),
                detected=sum(r['detected'] for r in results),results=results)
    (root/'tests/rc4-checker-selftest-report.json').write_text(
        json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

results=[]
with tempfile.TemporaryDirectory(prefix='pesto-rc4-guard-selftest-') as td:
    tmp=Path(td)
    base=run_checker(copy_corpus(tmp/'baseline'/'wad'),tmp/'baseline.json')
    if not (tmp/'baseline.json').is_file() or base.returncode!=0:
        # A red baseline means the harness itself is broken: every "defect detected" below would then be
        # meaningless, so the selftest refuses to judge anything.
        detail=last_line(base.stderr or base.stdout)
        print('FAIL baseline : le corpus non muté ne passe pas le contrôleur ('+detail+')',flush=True)
        write_report([],'refusé : le corpus non muté ne passe pas le contrôleur ('+detail+')')
        sys.exit(1)
    for name,old,new,expected in variants:
        corpus=copy_corpus(tmp/name/'wad')
        carriers=[f for f in sorted(corpus.glob('*.ps1')) if old in read(f)]
        if len(carriers)!=1:
            raise RuntimeError('Mutation anchor '+name+' found in '+str([f.name for f in carriers])+
                               '; exactly one file was expected: the product moved, re-anchor this defect')
        carrier=carriers[0]
        raw=carrier.read_bytes()
        carrier.write_bytes((b'\xef\xbb\xbf' if raw[:3]==b'\xef\xbb\xbf' else b'')+
                            read(carrier).replace(old,new).encode('utf-8'))
        report=tmp/(name+'.json')
        run=run_checker(corpus,report)
        if not report.is_file():
            # A crashing checker guards nothing and must read as a failed control, never as a traceback.
            results.append(dict(name=name,detected=False,expected_guards=list(expected),failed_checks=[],
                                carrier=carrier.name,exit_code=run.returncode,
                                error='contrôleur sans rapport : '+last_line(run.stderr or run.stdout)))
            print('FAIL '+name+' : aucun rapport écrit : '+last_line(run.stderr or run.stdout),flush=True)
            continue
        data=json.loads(report.read_text(encoding='utf-8'))
        failed=[c['name'] for c in data['checks'] if c['status']=='FAIL']
        missing=[g for g in expected if g not in failed]
        detected=run.returncode!=0 and not missing
        results.append(dict(name=name,detected=detected,expected_guards=list(expected),failed_checks=failed,
                            undetected_guards=missing,unexpected_failures=[g for g in failed if g not in expected],
                            carrier=carrier.name,exit_code=run.returncode))
        print(('PASS ' if detected else 'FAIL ')+name+' ['+carrier.name+']'+
              ('' if detected else ' : garde attendue sans effet '+str(missing)),flush=True)
write_report(results,'unmutated core and components pass the checker')
sys.exit(0 if all(r['detected'] for r in results) else 1)
