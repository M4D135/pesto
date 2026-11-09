#!/usr/bin/env python3
"""Deliberate RC6 source faults. Tests the STATIC validator, never the application.
Each fault targets the file that holds its anchor today: the engine wad/Pesto-Core.ps1 (--source) or the main window
wad/Pesto-Shell.xaml (--shell). The intact copies must pass first, otherwise no detection means anything.
A fault counts as detected only when the check it aims at fails, by its exact name, and, when a detail pattern is
given, when that check's detail names the mutated control, and when the checker ran all the checks of the intact
baseline. Other failing checks are reported, never counted. The intact baseline is replayed after the faults: a source
that changes or disappears during the run fails the self-test instead of passing it."""
from pathlib import Path
import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--report',type=Path,default=root/'tests/ux-checker-selftest-report.json')
a=parser.parse_args()
files={'source':root/'wad/Pesto-Core.ps1','shell':root/'wad/Pesto-Shell.xaml'}
raws={k:p.read_bytes() for k,p in files.items()};texts={k:raw.decode('utf-8-sig') for k,raw in raws.items()}
HELP='Interactive elements of the main window, core and login dialogs have tooltips, HelpText and disabled help'
RINGS='High-contrast state rings (X5): transparent overlays in Light/Dark, selection colours only in high contrast'
# (name, target, anchor, replacement, check that must fail, regex its detail must match or None).
# A str anchor is replaced once, '\n' following the file line endings; a compiled anchor must match exactly once.
variants=[
 ('missing_preview_control','shell','x:Name="UxCurrentName"','x:Name="BrokenCurrentName"','Every bound control is a public main window element, without template-part confusion',r"'UxCurrentName'"),
 ('broken_resource_reference','shell','Style="{StaticResource Card}"','Style="{StaticResource MissingCard}"','All referenced explicit style and brush keys exist',r"'MissingCard'"),
 ('editable_combobox_contract_removed','shell','x:Name="PART_EditableTextBox"','x:Name="BrokenEditablePart"','WPF named part contract ComboBox/PART_EditableTextBox',r'ComboBox missing PART_EditableTextBox'),
 # Main window: the run button is disabled at rest, so its help must stay visible when disabled.
 ('tooltip_disabled_help_removed','shell',re.compile(r'(x:Name="BtnRun"[^<>]*?ToolTipService\.ShowOnDisabled=")True(")'),r'\g<1>False\g<2>',HELP,r'Disabled tooltip absent: Pesto-Shell\.xaml:BtnRun(;|$)'),
 # Secondary report dialog declared in the core, also in the help scope.
 ('tooltip_disabled_help_removed_core_dialog','source',re.compile(r'(x:Name="Report"[^<>]*?ToolTipService\.ShowOnDisabled=")True(")'),r'\g<1>False\g<2>',HELP,r'Disabled tooltip absent: Pesto-Core\.ps1:\d+:\$\w+:Report(;|$)'),
 ('bad_same_site_preview','source','{$TargetOU}else{$CurrentOU}','{$TargetOU}else{$TargetOU}','Same-site preview keeps current OU instead of proposed OU',None),
 ('ui_bypasses_safety','source','    $UxCurrentName.Text=$view.CurrentName;', '    $BtnRun.IsEnabled=$true; $UxCurrentName.Text=$view.CurrentName;','UI projection never writes safety flags or enables execution',None),
 ('anonymous_ui_timer','source','[EventHandler]${function:Invoke-PestoUxRefreshTick}','[EventHandler]{Update-PestoUx}','UI timers use named script-bound delegates',None),
 # X5: the first ring colour is the Dark one; a visible ring would change the dark theme.
 ('state_ring_visible_in_dark','source',"HcStateRing='#00000000'","HcStateRing='#FF8ABEFF'",RINGS,r'Ring visible outside high contrast: Dark\.HcStateRing'),
 ('state_ring_missing_on_selected_tab','shell',re.compile(r'<Setter TargetName="InnerTabState" Property="BorderBrush" Value="\{DynamicResource HcStateRing\}"/>'),'',RINGS,r'TabItem/InnerTabState'),
 ('state_ring_catches_clicks','shell',re.compile(r'(x:Name="ComboItemState" CornerRadius="5" BorderThickness="2" IsHitTestVisible=")False(")'),r'\g<1>True\g<2>',RINGS,r'ComboBoxItem/ComboItemState'),
 ('state_ring_painted_with_focus_colour','shell',re.compile(r'(<Setter TargetName="ButtonState" Property="BorderBrush" Value="\{DynamicResource )HcStateRing(\}"/>)'),r'\g<1>FocusRing\g<2>',RINGS,r'ButtonState'),
 ('stale_identity_add_gap','source','    $BtnAdd.IsEnabled=$false\n    if($LblPCInfo){', '    $BtnAdd.IsEnabled=$true\n    if($LblPCInfo){','Lookup immediately disables adding and cancels stale probe generation',None),
 ('changed_legacy_tab_index','source','Rename=0;Names=1;Settings=2;Log=3;Home=4;History=5;Help=6','Rename=4;Names=1;Settings=2;Log=3;Home=0;History=5;Help=6','Original navigation indexes preserved and mapped to the right main window tabs',r'Legacy navigation index regression'),
 ('direct_queue_run_from_preview','source',"    $operation='Aucune action prête'", "    Run-Queue\n    $operation='Aucune action prête'",'New presentation functions do not call mutation entry points',r"'Run-Queue'"),
]
def run(td,name,target=None,old=None,new=None):
 """Writes both files (BOM and line endings kept), the target one mutated, then runs the static checker on them."""
 folder=Path(td)/name;folder.mkdir();args=[];out=folder/'report.json'
 for k,p in files.items():
  text=texts[k]
  if k==target:
   if isinstance(old,re.Pattern):
    hits=len(old.findall(text))
    if hits!=1:raise RuntimeError('Mutation anchor must match once: '+name+' in '+p.name+' ('+str(hits)+')')
    text=old.sub(new,text,count=1)
   else:
    nl='\r\n' if '\r\n' in text else '\n';old_t=old.replace('\n',nl)
    if old_t not in text:raise RuntimeError('Missing mutation anchor: '+name+' in '+p.name)
    text=text.replace(old_t,new.replace('\n',nl),1)
   if text==texts[k]:raise RuntimeError('Mutation left the file unchanged: '+name)
  copy=folder/p.name;copy.write_bytes((b'\xef\xbb\xbf' if raws[k].startswith(b'\xef\xbb\xbf') else b'')+text.encode('utf-8'))
  args+=['--'+k,str(copy)]
 proc=subprocess.run([sys.executable,str(root/'tests/ux_static_checks.py')]+args+['--report',str(out)],capture_output=True,text=True,timeout=30)
 data=json.loads(out.read_text(encoding='utf-8')) if out.is_file() else {'checks':[]}
 run.stderr=proc.stderr.strip()[-600:]
 return proc.returncode,{c['name']:str(c.get('detail')) for c in data['checks'] if c['status']=='FAIL'},len(data['checks'])
results=[]
with tempfile.TemporaryDirectory(prefix='pesto-rc6-negative-') as td:
 code,failed,total=run(td,'intact_baseline')
 baseline=dict(passed=code==0 and not failed and total>0,returncode=code,checks=total,failed_checks=sorted(failed),stderr=run.stderr)
 print(('PASS ' if baseline['passed'] else 'FAIL ')+'intact_baseline',flush=True)
 for name,target,old,new,expected,detail in variants:
  code,failed,total=run(td,name,target,old,new)
  named=expected in failed;cited=named and (detail is None or re.search(detail,failed[expected]) is not None)
  complete=total==baseline['checks'];detected=code!=0 and named and cited and complete
  results.append(dict(name=name,target=files[target].name,expected_check=expected,expected_detail=detail,detected=detected,
                      expected_check_failed=named,expected_detail_found=cited,returncode=code,checks=total,all_checks_ran=complete,
                      failed_checks=sorted(failed),other_failed_checks=sorted(n for n in failed if n!=expected),stderr=run.stderr))
  print(('PASS ' if detected else 'FAIL ')+name+('' if detected else ' : expected '+repr(expected)+(' citing '+detail if detail else '')+'; failed '+str(sorted(failed))+'; checks '+str(total)+'/'+str(baseline['checks'])+'; rc '+str(code)),flush=True)
 code,failed,total=run(td,'intact_baseline_replay')
 replay=dict(passed=code==0 and not failed and total==baseline['checks'],returncode=code,checks=total,failed_checks=sorted(failed),stderr=run.stderr)
 print(('PASS ' if replay['passed'] else 'FAIL ')+'intact_baseline_replay',flush=True)
report=dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),scope='STATIC validator negative controls only. No PowerShell/WPF/AD execution.',
            rule='Detected = non-zero exit, the expected check fails by name (and its detail cites the mutated control when a pattern is given) and all baseline checks ran.',
            baseline=baseline,baseline_replay=replay,total=len(results),detected=sum(r['detected'] for r in results),results=results)
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sys.exit(0 if baseline['passed'] and replay['passed'] and all(r['detected'] for r in results) else 1)
