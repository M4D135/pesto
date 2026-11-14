"""Explicit, offline pilot/general selection; delegates mutations to the existing updater."""
from pathlib import Path
import argparse
import json
import re
from refresh_manifest import verify_runtime, file_hash, safe_file
import update_installation


def select(catalogue, ring, source):
    if ring not in ('pilot', 'general'): raise ValueError('Unknown release ring')
    data = json.loads(Path(catalogue).read_text(encoding='utf-8-sig'))
    if data.get('schema') != 1 or set(data.get('rings', {})) != {'pilot', 'general'}: raise ValueError('Invalid ring catalogue')
    entry = data['rings'][ring]
    if not isinstance(entry, dict) or set(entry) != {'version', 'exeSHA256', 'manifestSHA256'}: raise ValueError('Invalid release identity')
    if not all(isinstance(entry[k], str) and re.fullmatch('[0-9a-f]{64}', entry[k]) for k in ('exeSHA256', 'manifestSHA256')): raise ValueError('Invalid release hash')
    source = Path(source).resolve(strict=True); manifest = verify_runtime(source)
    if manifest['Version'] != entry['version'] or file_hash(safe_file(source, 'Pesto.exe')) != entry['exeSHA256'] or file_hash(safe_file(source, 'wad/package.json')) != entry['manifestSHA256']: raise ValueError('The supplied payload does not match this ring')
    return {'ring': ring, 'version': manifest['Version'], 'exeSHA256': entry['exeSHA256'], 'source': source}


def main():
    p = argparse.ArgumentParser(description=__doc__);p.add_argument('--catalogue', type=Path, required=True);p.add_argument('--ring',choices=('pilot','general'),required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--execute',action='store_true')
    a=p.parse_args(); choice=select(a.catalogue,a.ring,a.source)
    # The original update CLI remains the single source of transaction/backup/rollback behaviour.
    import subprocess, sys
    cmd=[sys.executable,str(Path(__file__).with_name('update_installation.py')),'--source',str(choice['source']),'--destination',str(a.target)]
    if a.execute: cmd.append('--apply')
    return subprocess.call(cmd)

if __name__=='__main__': raise SystemExit(main())
