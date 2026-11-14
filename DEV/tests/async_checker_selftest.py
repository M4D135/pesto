#!/usr/bin/env python3
"""Negative controls for the RC3 lexical guard only. No Windows runtime."""
from pathlib import Path
import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
CHECKER=root/'tests/async_static_checks.py'
# The engine spread its functions over the components the core dot-sources: five of these seven anchors no
# longer live in Pesto-Core.ps1 (the timer, the callback packing and the reentrancy flag all moved to
# Pesto-Async.ps1). Mutating the core alone left them unreachable, and the checker died on KeyError before
# writing any report, which surfaced here as a FileNotFoundError. Each defect now names the guard that must
# catch it: a non-zero exit from unrelated collateral damage is not a detection.
variants=[
    ('named_command_in_icon_closure',"& $writeIconLog 'Application de l''icône Win32 impossible.'","Write-Log 'Application de l''icône Win32 impossible.'",
     ('All remaining closures contain no script scope or Pesto function lookup',)),
    ('script_scope_inside_icon_closure','($iconBase64 -replace','($script:AppIconIcoB64 -replace',
     ('All remaining closures contain no script scope or Pesto function lookup',)),
    ('missing_timer_handler','${function:Invoke-PestoAsyncTimerTick}','${function:Missing-PestoAsyncTimerTick}',
     ('Timer delegate bound to the named function',)),
    ('missing_context','-OnError $err -CallbackContext $context -Replace -TimeoutSec 75','-OnError $err -Replace -TimeoutSec 75',
     ('Explicit callback context in Select-PCName',)),
    ('lost_context_argument','$cbArgs[1]=$Context','$cbArgs[1]=$null',
     ('Callback context packed separately from the result array',)),
    ('handler_not_detached','$op.Timer.Remove_Tick($op.TickHandler)','$op.Timer.ToString()',
     ('Completed handler and timer registry entry removed',)),
    ('blocking_worker_stop','$op.TickBusy=$true','$op.TickBusy=$true\n    $op.PowerShell.Stop()',
     ('No synchronous PowerShell.Stop used on the UI thread',)),
]

def read(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def copy_corpus(destination):
    destination.mkdir(parents=True,exist_ok=True)
    for source in sorted((root/'wad').glob('*.ps1')):shutil.copy2(source,destination/source.name)
    return destination

def run_checker(corpus,report):
    return subprocess.run([sys.executable,str(CHECKER),'--root',str(root),'--wad',str(corpus),
                           '--source',str(corpus/'Pesto-Core.ps1'),'--report',str(report)],
                          capture_output=True,text=True,timeout=120)

def last_line(text):
    lines=[line for line in text.strip().splitlines() if line.strip()]
    return lines[-1] if lines else 'aucune sortie'

def write_report(results,baseline_status):
    # Written on every exit path, including the refused one: leaving the previous green report on disk next to
    # a red run is how a broken harness keeps reading as healthy.
    report=dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                scope='Negative controls of the RC3 lexical guards only; NOT Windows runtime tests',
                baseline=baseline_status,total=len(results),
                detected=sum(1 for r in results if r['detected']),results=results)
    (root/'tests/async-checker-selftest-report.json').write_text(
        json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

results=[]
with tempfile.TemporaryDirectory(prefix='pesto-async-negative-') as td:
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
        if not carriers:
            # The product moved. Recorded, not raised: the report on disk must describe this run, not the
            # last green one, and the remaining controls still have to be measured.
            results.append(dict(name=name,detected=False,expected_guards=list(expected),failed_checks=[],
                                carriers=[],error='ancre absente du corpus : contrôle vacant, à ré-ancrer'))
            print('FAIL '+name+' : ancre absente du corpus',flush=True)
            continue
        for carrier in carriers:
            raw=carrier.read_bytes()
            carrier.write_bytes((b'\xef\xbb\xbf' if raw[:3]==b'\xef\xbb\xbf' else b'')+read(carrier).replace(old,new).encode('utf-8'))
        report=tmp/(name+'.json')
        run=run_checker(corpus,report)
        if not report.is_file():
            # A crashing checker guards nothing and must read as a failed control, never as a traceback.
            results.append(dict(name=name,detected=False,expected_guards=list(expected),failed_checks=[],
                                carriers=[f.name for f in carriers],exit_code=run.returncode,
                                error='contrôleur sans rapport : '+last_line(run.stderr or run.stdout)))
            print('FAIL '+name+' : aucun rapport écrit : '+last_line(run.stderr or run.stdout),flush=True)
            continue
        data=json.loads(report.read_text(encoding='utf-8'))
        failed=[c['name'] for c in data['checks'] if c['status']=='FAIL']
        missing=[g for g in expected if g not in failed]
        detected=run.returncode!=0 and not missing
        results.append(dict(name=name,detected=detected,expected_guards=list(expected),failed_checks=failed,
                            undetected_guards=missing,unexpected_failures=[g for g in failed if g not in expected],
                            carriers=[f.name for f in carriers],exit_code=run.returncode))
        print(('PASS ' if detected else 'FAIL ')+name+' ['+','.join(f.name for f in carriers)+']'+
              ('' if detected else ' : garde attendue sans effet '+str(missing)),flush=True)
write_report(results,'unmutated core and components pass the checker')
sys.exit(0 if all(r['detected'] for r in results) else 1)
