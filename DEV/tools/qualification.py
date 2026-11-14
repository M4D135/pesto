"""Prepare and record explicit qualification evidence. Never executes GUI/AD actions."""
from pathlib import Path
import argparse
import hashlib
import json
import re
from release_assurance import dump

SCENARIOS = {
 'gui': ['first-run-import','local-join-plan','single-rename-plan','batch-import-edit-undo','names-select','settings-diff-conflict','receipt-optional-followup','close-during-read'],
 'visual': ['100pct-1920x1080-light','150pct-1920x1080-dark','200pct-1920x1080-light','zoom150-small-window','high-contrast','two-monitors-different-dpi'],
 'accessibility': ['keyboard-only-all-pages','f6-shift-f6-zones','narrator-progress-coalesced','narrator-validation-errors','focus-restored-after-dialog'],
 'smb': ['two-hosts-same-name-one-owner','two-hosts-different-name','owner-crash-no-steal','share-unavailable-no-mutation','late-result-preserved'],
 'replication': ['selected-dc-remains-constant','second-dc-delay-observed','not-found-is-not-free-across-unread-dc','no-automatic-dc-switch'],
 'policy': ['app-control-audit','app-control-enforced','constrained-language-refused','untrusted-signature-refused'],
 'soak': ['repeated-navigation','repeated-read-cancel','open-close-receipts','memory-handles-subscriptions-trend']}


def plan(build_sha256):
    if not re.fullmatch('[0-9a-f]{64}', build_sha256): raise ValueError('Build SHA256 required')
    return {'schema': 1, 'buildSHA256': build_sha256, 'environment': {'windows': None, 'language': None, 'dotnet': None, 'accountMode': None, 'policy': None},
            'cases': [{'id': group+'/'+case,'status':'NOT_RUN','observed':None,'attachments':[]} for group,cases in SCENARIOS.items() for case in cases],
            'rule':'PASS requires an observed result and hashed evidence; NOT_RUN is never PASS. Actions on AD require a separately authorized lab.'}


def record(path, case_id, status, observed, attachments):
    path=Path(path); data=json.loads(path.read_text(encoding='utf-8'))
    if status not in ('PASS','FAIL','BLOCKED'): raise ValueError('Explicit outcome required')
    if not observed.strip() or len(observed)>8192: raise ValueError('Observed result required')
    cases=[c for c in data['cases'] if c['id']==case_id]
    if len(cases)!=1 or cases[0]['status']!='NOT_RUN': raise ValueError('Unknown or already recorded case; preserve the original report')
    if not attachments: raise ValueError('Evidence attachment required')
    evidence=[]
    for item in attachments:
        source=Path(item)
        if source.is_symlink() or not source.is_file(): raise ValueError('Regular attachment required')
        evidence.append({'name':source.name,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'bytes':source.stat().st_size})
    cases[0].update(status=status,observed=observed,attachments=evidence)
    return data


def main():
    p=argparse.ArgumentParser(description=__doc__);s=p.add_subparsers(dest='action',required=True)
    create=s.add_parser('plan');create.add_argument('--build',required=True);create.add_argument('--output',type=Path,required=True)
    add=s.add_parser('record');add.add_argument('--input',type=Path,required=True);add.add_argument('--output',type=Path,required=True);add.add_argument('--case',required=True);add.add_argument('--status',choices=('PASS','FAIL','BLOCKED'),required=True);add.add_argument('--observed',required=True);add.add_argument('--attachment',type=Path,action='append',required=True)
    a=p.parse_args();data=plan(a.build) if a.action=='plan' else record(a.input,a.case,a.status,a.observed,a.attachment)
    with a.output.open('xb') as stream: stream.write(dump(data))

if __name__=='__main__':main()
