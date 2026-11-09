#!/usr/bin/env python3
"""Negative controls for the structural checker. Static only, never the Windows application.

Rewritten on the pattern proven by async_checker_selftest.py. The previous version judged a defect "detected"
as soon as the checker exited non-zero with any FAIL, and every one of its ten anchors had drifted out of the
tree: x:Name="BtnStop" lives in wad/Pesto-Shell.xaml, not in the core; if($restoreRequired -and -not [bool]…)
and "Compilation :" no longer exist anywhere; DEBLOQUER_TOUT.cmd moved to wad/support/ and was rewritten
without StartsWith($prefix); Pesto.ps1 was replaced by Pesto.cmd. A missing anchor was recorded as
"Mutation anchor missing" and the run still printed PASS for the others, so the harness could report a healthy
checker while guarding nothing. Each control below now names the guard that must fire, the baseline is measured
before any mutation, and the report is written on every exit path.
"""
from __future__ import annotations
import datetime as dt
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / 'tests' / 'static_checks.py'

# Guards that are red on the unmutated tree at HEAD, with the reason. This is not a suppression list: the
# baseline below refuses to run unless the observed redness is EXACTLY this set, so a new red guard — or one
# that quietly turns green because a reference was regenerated — stops the harness until a human updates this
# file. It is empty as of the socle update: tests/original-assets.json no longer names two files the package
# does not ship (wad/cfg.original.json, a user file, and wad/icone.ico, renamed wad/Pesto.ico at identical
# bytes), and the live baseline comparisons moved to tests/current-core-baseline.json. If a reference drifts
# back, this harness blocks the run instead of reporting a healthy checker.
KNOWN_RED = {}

# (name, file, anchor, replacement, guards that must fire)
VARIANTS = [
    ('xaml_control_renamed', 'wad/Pesto-Shell.xaml', 'x:Name="BtnStop"', 'x:Name="BrokenStop"',
     ('Correspondance noms XAML / contrôles principaux',)),
    ('legacy_repair_option_enabled_in_example', 'wad/cfg.example.json',
     '"AllowHybridRepair": "false"', '"AllowHybridRepair": "true"',
     ('Option legacy de réparation désactivée dans l’exemple',)),
    # Two distinct call sites, two distinct guards: RenameComputer uses the positive form, AddToDomain the
    # negated one, so one mutation can only ever fire one of them. Split instead of hoping both go red.
    ('missing_confirmation_guard_rename', 'wad/Pesto-Operations.ps1',
     'if(Test-PestoConfirmedChange $change)', 'if($true)',
     ('Garde structurelle RenameComputer : Test-PestoConfirmedChange $change',)),
    ('missing_confirmation_guard_join', 'wad/Pesto-Operations.ps1',
     'if (-not (Test-PestoConfirmedChange $change)) {', 'if ($false) {',
     ('Garde structurelle AddToDomain : Test-PestoConfirmedChange $change',)),
    # Re-anchored: MoveComputer lives in wad/Pesto-Operations.ps1, not in the core.
    ('broken_protection_guard', 'wad/Pesto-Operations.ps1',
     'Set-ADObject -Identity $id -ProtectedFromAccidentalDeletion:$true',
     'Set-ADObject -Identity $id -ProtectedFromAccidentalDeletion:$false',
     ('Garde structurelle MoveComputer : Set-ADObject -Identity $id -ProtectedFromA',)),
    # Re-anchored: "Compilation :" was never in tools/Build-Pesto.ps1. The defect is now a real typographic
    # quote inside a real single-quoted string, which is what actually breaks PowerShell 5.1.
    ('smart_quote_introduced', 'tools/Build-Pesto.ps1',
     "'Echec compilation des ressources.'", "'Echec \u2019 compilation des ressources.'",
     ('tools/Build-Pesto.ps1 : pas de guillemets typographiques dans les chaînes',)),
    ('legacy_ad_path', 'wad/Pesto-Core.ps1',
     "Join-Path $BasePath 'ActiveDirectory.psd1'", "Join-Path $BasePath 'mod\\ActiveDirectory.psd1'",
     ('Moteur : les chemins AD pointent dans wad, sans ancien mod',)),
    ('unblock_nonliteral', 'wad/support/DEBLOQUER_TOUT.cmd',
     'Unblock-File -LiteralPath $item.FullName -ErrorAction Stop',
     'Unblock-File -Path $item.FullName -ErrorAction Stop',
     ('Deblocage : commande litterale et controle du flux apres retrait',)),
    # Re-anchored: StartsWith($prefix) is gone from the rewritten unblocker. The control now removes the guard
    # that actually keeps the unblocker inside wad/support.
    ('unblock_missing_scope_check', 'wad/support/DEBLOQUER_TOUT.cmd',
     "throw 'Ce fichier doit rester dans wad\\support.'", "Write-Warning 'support'",
     ('Deblocage : garde du dossier Pesto et exclusion des jonctions',)),
    ('unblock_falls_into_payload', 'wad/support/DEBLOQUER_TOUT.cmd',
     'exit /b %PESTO_EXIT%\n:__PESTO_SUPPORT_POWERSHELL__',
     'rem sortie retiree\n:__PESTO_SUPPORT_POWERSHELL__',
     ('CMD de deblocage : bloc autonome et delimiteurs',)),
    # Re-anchored: Pesto.ps1 no longer exists. The launcher chain is Pesto.cmd -> wad/Pesto-Startup.ps1.
    ('launcher_wrong_core', 'Pesto.cmd',
     'wad\\Pesto-Startup.ps1', 'wad\\Pesto-Other.ps1',
     ('Lanceurs : Pesto.cmd vers wad/Pesto-Startup.ps1, PowerShell x64/STA',)),
    ('launcher_missing_x64', 'Pesto.cmd', 'Sysnative', 'System32',
     ('Lanceurs : Pesto.cmd vers wad/Pesto-Startup.ps1, PowerShell x64/STA',)),
    ('launcher_drops_exit_code', 'Pesto.cmd',
     'set "Pesto_EXIT_CODE=%ERRORLEVEL%"', 'set "Pesto_EXIT_CODE=0"',
     ('Lanceur : code de sortie du moteur propage',)),
    ('demo_not_isolated', 'wad/cfg.demo.json', '"Simulation": "true"', '"Simulation": "false"',
     ('Démonstration : GUI et Simulation actifs',)),
    ('worker_exports_unknown_function', 'wad/Pesto-Core.ps1',
     "'Assert-PestoRenameTarget'", "'Assert-PestoRenameTargetAbsent'",
     ('Fonctions exportées aux workers / fermeture lexicale',)),
]


def read_normalized(path: Path) -> str:
    return path.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')


def write_normalized(path: Path, text: str) -> None:
    raw = path.read_bytes()
    bom = b'\xef\xbb\xbf' if raw[:3] == b'\xef\xbb\xbf' else b''
    crlf = b'\r\n' in raw
    body = text.replace('\n', '\r\n') if crlf else text
    path.write_bytes(bom + body.encode('utf-8'))


def run_checker(tree: Path, report: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CHECKER), '--root', str(tree), '--report', str(report)],
                          capture_output=True, text=True, timeout=180)


def last_line(text: str) -> str:
    lines = [line for line in text.strip().splitlines() if line.strip()]
    return lines[-1] if lines else 'aucune sortie'


def failed_checks(report_path: Path) -> list:
    data = json.loads(report_path.read_text(encoding='utf-8'))
    return [c['name'] for c in data['checks'] if c['status'] == 'FAIL']


def write_report(results, baseline_status, baseline_red):
    # Written on every exit path, the refused one included: leaving the previous green report next to a red run
    # is how a broken harness keeps reading as healthy.
    report = dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                  scope='Static checker negative controls only; NOT Windows runtime tests',
                  baseline=baseline_status, baseline_failed_checks=sorted(baseline_red),
                  declared_known_red=KNOWN_RED, total=len(results),
                  detected=sum(1 for r in results if r['detected']), results=results)
    path = ROOT / 'tests' / 'checker-selftest-report.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main() -> int:
    results = []
    baseline_red = set()
    baseline_status = 'non mesuré'
    with tempfile.TemporaryDirectory(prefix='pesto-static-selftest-') as td:
        tmp = Path(td)
        tree = tmp / 'tree'
        shutil.copytree(ROOT, tree, ignore=shutil.ignore_patterns('__pycache__', 'dist', '.git'))
        baseline_report = tmp / 'baseline.json'
        base = run_checker(tree, baseline_report)
        if not baseline_report.is_file():
            # A checker that dies writes nothing; every "defect detected" below would then be an artefact.
            baseline_status = 'refusé : aucun rapport écrit (' + last_line(base.stderr or base.stdout) + ')'
            print('FAIL baseline : ' + baseline_status, flush=True)
            write_report([], baseline_status, baseline_red)
            return 1
        baseline_red = set(failed_checks(baseline_report))
        if baseline_red != set(KNOWN_RED):
            new = sorted(baseline_red - set(KNOWN_RED))
            healed = sorted(set(KNOWN_RED) - baseline_red)
            detail = ('rouges non déclarées ' + str(new)) if new else ('rouges déclarées devenues vertes ' + str(healed))
            baseline_status = 'refusé : baseline ' + detail
            # Refused, not judged: with a red tree, "some guard went red" proves nothing about any mutation.
            print('FAIL baseline : ' + baseline_status, flush=True)
            write_report([], baseline_status, baseline_red)
            return 1
        baseline_status = ('rouge exactement comme déclaré : ' + ', '.join(sorted(baseline_red))
                           if baseline_red else 'verte')
        print('Baseline : ' + baseline_status, flush=True)

        for name, rel, old, new, expected in VARIANTS:
            copy = tmp / name
            shutil.copytree(tree, copy, ignore=shutil.ignore_patterns('__pycache__'))
            carriers = [copy / rel] if (copy / rel).is_file() else []
            if not carriers:
                # Recorded, never raised: the report must describe this run and the other controls still count.
                results.append(dict(name=name, detected=False, expected_guards=list(expected), carriers=[],
                                    error='fichier absent de la copie : ' + rel))
                print('FAIL ' + name + ' : fichier absent ' + rel, flush=True)
                continue
            carrier = carriers[0]
            value = read_normalized(carrier)
            if old not in value:
                results.append(dict(name=name, detected=False, expected_guards=list(expected),
                                    carriers=[rel], error='ancre absente : contrôle vacant, à ré-ancrer'))
                print('FAIL ' + name + ' : ancre absente de ' + rel, flush=True)
                continue
            # Every occurrence, not the first: "Sysnative" appears twice in Pesto.cmd, and replacing only the
            # first left the substring test green — a control that passes because the defect was only half
            # injected.
            write_normalized(carrier, value.replace(old, new))
            report = tmp / (name + '.json')
            run = run_checker(copy, report)
            if not report.is_file():
                results.append(dict(name=name, detected=False, expected_guards=list(expected),
                                    carriers=[rel], exit_code=run.returncode,
                                    error='contrôleur sans rapport : ' + last_line(run.stderr or run.stdout)))
                print('FAIL ' + name + ' : aucun rapport écrit : ' + last_line(run.stderr or run.stdout), flush=True)
                continue
            failed = failed_checks(report)
            missing = [g for g in expected if g not in failed]
            detected = run.returncode != 0 and not missing
            results.append(dict(name=name, detected=detected, expected_guards=list(expected),
                                failed_checks=failed, undetected_guards=missing,
                                unexpected_failures=[g for g in failed if g not in expected and g not in baseline_red],
                                carrier=rel, exit_code=run.returncode))
            print(('PASS ' if detected else 'FAIL ') + name + ' [' + rel + ']' +
                  ('' if detected else ' : garde attendue sans effet ' + str(missing)), flush=True)
    write_report(results, baseline_status, baseline_red)
    return 0 if results and all(r['detected'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
