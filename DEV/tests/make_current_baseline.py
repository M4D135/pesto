#!/usr/bin/env python3
"""Regenerate tests/current-core-baseline.json from the repository itself.

This is deliberately NOT the RC10/RC12 record. Those two files fingerprint an external package
("GP-Core(1).ps1 retrieved from the Library", input_zip_sha256, core_sha256) and stay untouched as the
provenance trail of what the user's RC10 and RC12 were. Their source artifacts are gone: the PROD pack on
the Mac hashes a3f2f462... where the RC12 zip records da78cde7..., its core hashes fa6b7030... where RC12
records 4c604f5f..., it ships no tests/ directory, and GP-Core(1).ps1 is nowhere on the machine.

Measured against HEAD, that history is also simply behind the code: 150 of RC10's 269 names and 157 of
RC12's 276 no longer exist (all of them GP->Pesto renames with a Pesto counterpart present), and 84 of the
119 names that survived carry a different body. Rewriting those files in place would fingerprint the code
against itself and destroy the audit trail, so instead the guards compare live code against THIS baseline,
which the repository can re-derive, while the RC10/RC12 files remain readable history.

Regenerating is a deliberate act, not a reflex: the report carries generated_from_commit and generated_utc,
so a blanket refresh that swallows a regression is visible in the report it produces.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

from ps_lexical import functions

# Same corpus definition as startup/sso/queue_removal static checks: the core plus every component it
# dot-sources, first definition wins. A baseline built on a narrower corpus would fingerprint a fraction
# of the engine and read as full coverage.
COMPONENT = re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")


def read_ps(path: Path) -> str:
    return path.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')


def corpus(core_path: Path, wad: Path):
    texts = {'Pesto-Core.ps1': read_ps(core_path)}
    missing = []
    for name in COMPONENT.findall(texts['Pesto-Core.ps1']):
        if name in texts:
            continue
        component = wad / name
        if component.is_file():
            texts[name] = read_ps(component)
        else:
            missing.append(name)
    return texts, missing


def git_commit(root: Path) -> str:
    try:
        return subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True,
                              text=True, timeout=30).stdout.strip() or 'inconnu'
    except Exception:
        return 'inconnu'


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source', type=Path, help='engine core (default: <wad>/Pesto-Core.ps1)')
    ap.add_argument('--wad', type=Path, help='engine components (default: <root>/wad)')
    ap.add_argument('--output', type=Path)
    a = ap.parse_args()
    root = a.root
    wad = a.wad or root / 'wad'
    core_path = a.source or wad / 'Pesto-Core.ps1'
    out = a.output or root / 'tests' / 'current-core-baseline.json'

    texts, missing_components = corpus(core_path, wad)
    # A baseline over a broken corpus is worse than no baseline: it would fingerprint half the engine and
    # report full coverage, and a function that vanished with a missing component would look preserved.
    if missing_components:
        print('REFUSÉ : composants dot-sourcés absents : ' + ', '.join(missing_components), flush=True)
        return 1
    spans = {}
    duplicates = []
    for file_name, text in texts.items():
        for name, span in functions(text).items():
            if name in spans:
                duplicates.append(name)
            else:
                spans[name] = (file_name, span)
    if duplicates:
        print('REFUSÉ : fonctions définies deux fois : ' + ', '.join(sorted(set(duplicates))[:10]), flush=True)
        return 1
    if 'Pesto-Core.ps1' not in texts or not spans:
        print('REFUSÉ : corpus vide ou sans cœur', flush=True)
        return 1

    digests = {}
    for name, (file_name, (a_, b_)) in spans.items():
        digests[name] = hashlib.sha256(texts[file_name][a_:b_].encode('utf-8')).hexdigest()

    payload = {
        'schema': 1,
        'scope': ('Socle courant mesuré sur le dépôt (cœur + composants dot-sourcés), pas une référence de '
                  'provenance. Les fichiers rc10-core-baseline.json et rc12-sso-baseline.json restent la trace '
                  'historique du paquet extérieur et ne sont ni réécrits ni comparés comme un contrat vivant.'),
        'generated_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'generated_from_commit': git_commit(root),
        'corpus_files': sorted(texts),
        'normalization': ('aucune : sha256 du span brut de la fonction. Mesuré sur ce dépôt, aucune chaîne de '
                          'version (17.0-RC*) n’apparaît dans le corpus, donc aucune substitution de version '
                          'n’est nécessaire ; en ajouter une masquerait un vrai changement de corps.'),
        'function_count': len(digests),
        # Deliberately empty: nothing is allowed to change silently. A human edits these lists on purpose when
        # a change is intended, exactly as rc11_intentional_changes / rc13_allowed_changes did for RC10/RC12.
        'intentional_changes': [],
        'added_functions': [],
        'normalized_function_sha256': digests,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print('Socle courant écrit : ' + str(out) + ' (' + str(len(digests)) + ' fonctions, ' +
          str(len(texts)) + ' fichiers, commit ' + payload['generated_from_commit'][:12] + ')', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
