#!/usr/bin/env python3
"""Negative controls of RC5 source guards. Does NOT execute PowerShell."""
from pathlib import Path
import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[1]
CHECKER=root/'tests/pilotage_static_checks.py'
# The engine spread its functions over the components the core dot-sources, so an anchor can live outside the
# core (source_identity_guard_removed lives in Pesto-Operations.ps1). The whole wad corpus is copied and every
# file carrying the anchor is mutated: mutating Pesto-Core.ps1 alone left that defect unreachable, and the
# checker died on KeyError before writing any report, which surfaced here as a FileNotFoundError. Each defect
# names the guard that must catch it: a non-zero exit from unrelated collateral damage is not a detection.
variants=[
 ('bulk_autorun_regression','$r.Traiter=$false;$r.Reboot=$false','$r.Traiter=$true;$r.Reboot=$true',
  ('Bulk never selects/reboots newly prepared rows',)),
 ('bulk_collision_removed','$used[[string]$row.Nouveau_Nom]=$true','$unused=$true',
  ('Bulk reserves existing and queued target names',)),
 ('bulk_bypasses_site_rule','$r.Deplacer=[bool]$decision.Move','$r.Deplacer=$true',
  ('Bulk computes move with the shared site rule',)),
 ('readonly_worker_mutates',"$problems=[Collections.Generic.List[string]]::new();", "Rename-Computer -NewName 'UNSAFE'\n    $problems=[Collections.Generic.List[string]]::new();",
  ('Read-only worker whitelist contains no mutation or arbitrary execution',)),
 ('late_result_applied','$Context.Generation -ne $script:PreflightGeneration','$false',
  ('Late preflight result rejected by generation',)),
 # Replace every read worker that carries this deadline for that deliberate defect.
 ('unbounded_read_worker','-TimeoutSec 120 -CallbackContext $context','-TimeoutSec 0 -CallbackContext $context',
  ('Preflight uses runspace, deadline and named callbacks',)),
 ('source_identity_guard_removed','if($drift){return New-ActionResult 21 $drift}','if($false){return New-ActionResult 21 $drift}',
  ('RenameComputer verifies source identity before a mutation',)),
 ('view_index_edits_wrong_row','$script:table.Rows.IndexOf($Grid.SelectedItem.Row)','$Grid.SelectedIndex',
  ('Filtered editing resolves actual row, never view index',)),
 ('html_not_encoded','[Net.WebUtility]::HtmlEncode((Protect-PestoLogText ([string]$v)))','([string]$v)',
  ('Reports escape HTML, suppress resources and preserve per-result mode',)),
 ('checkpoint_recovery_size_incompatible','GetByteCount($json) -gt 16MB','GetByteCount($json) -gt 160MB',
  ('Checkpoint read/write both bounded at 16 MiB',)),
]

def read(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def copy_corpus(destination):
 destination.mkdir(parents=True,exist_ok=True)
 for source in sorted((root/'wad').glob('*.ps1'))+sorted((root/'wad').glob('*.xaml')):
  shutil.copy2(source,destination/source.name)
 return destination

def run_checker(corpus,report):
 return subprocess.run([sys.executable,str(CHECKER),'--source',str(corpus/'Pesto-Core.ps1'),'--wad',str(corpus),
                        '--report',str(report)],capture_output=True,text=True,timeout=120)

def last_line(text):
 lines=[line for line in text.strip().splitlines() if line.strip()]
 return lines[-1] if lines else 'aucune sortie'

def write_report(results,baseline_status):
 # Written on every exit path, including the refused one: leaving the previous green report on disk next to
 # a red run is how a broken harness keeps reading as healthy.
 report=dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
  scope='Negative controls of static source guards only; not a functional AD or PowerShell test',
  baseline=baseline_status,total=len(results),detected=sum(r['detected'] for r in results),results=results)
 (root/'tests/pilotage-checker-selftest-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

results=[]
with tempfile.TemporaryDirectory(prefix='pesto-rc5-source-guard-') as td:
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
   raise RuntimeError('Mutation anchor '+name+' found in no engine file: the product moved, re-anchor this defect')
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
