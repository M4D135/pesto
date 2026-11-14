"""Optional managed install/detect/uninstall, preserving configuration and GP profiles.
No registry changes, elevation, service, AD or application launch. Management tools
can use detect's exit code (0 installed/healthy; 1 absent or changed).
"""
from pathlib import Path
import argparse
import json
import os
import shutil
from package_distribution import build_directory
from update_installation import mutation_guard, check_local_states, _write_json, _fsync_directory
from refresh_manifest import verify_runtime, runtime_files, safe_file, _is_link_or_junction
from installation_receipt import RECEIPT, make_receipt, load_receipt, changed_owned_files


def install(source, destination):
    destination = Path(destination)
    build_directory(Path(source), destination, 'PROD')
    try:
        receipt = make_receipt(destination, runtime_files(destination), verify_runtime(destination)['Version'])
        _write_json(destination / RECEIPT, receipt)
    except BaseException:
        # Only the directory created by this invocation can be removed here.
        shutil.rmtree(destination)
        raise
    return receipt


def detect(destination):
    root = Path(destination)
    if not root.exists(): return {'installed': False, 'healthy': False, 'reason': 'absent'}
    if _is_link_or_junction(root): raise ValueError('Linked installation refused')
    # Removed installations retain cfg.json but no runtime; check absence first.
    if not (root / RECEIPT).exists() and not _is_link_or_junction(root / RECEIPT):
        return {'installed': False, 'healthy': False, 'reason': 'unmanaged or removed; data retained'}
    if _is_link_or_junction(root / RECEIPT): raise ValueError('Linked installation receipt refused')
    try:
        receipt = load_receipt(root, runtime_files(root), required=True)
    except (OSError, ValueError):
        # Detection must be usable by management tools even after a partial copy.
        # Unknown ownership never grants permission to remove anything.
        return {'installed': True, 'healthy': False, 'reason': 'invalid or unreadable installation metadata',
                'changed': [], 'owned': []}
    changed = changed_owned_files(root, receipt)
    if not changed:
        try:
            manifest = verify_runtime(root)
            if receipt['version'] != manifest['Version']: raise ValueError('Installation receipt version differs')
        except (OSError, ValueError):
            return {'installed': True, 'healthy': False, 'reason': 'runtime or receipt version is inconsistent',
                    'changed': [], 'owned': sorted(receipt['files'])}
    return {'installed': True, 'healthy': not changed, 'version': receipt['version'], 'changed': changed, 'owned': sorted(receipt['files'])}


def uninstall(destination, execute=False):
    root = Path(destination).absolute()
    result = detect(root)
    if not result['installed']: return result
    if not result['healthy']: raise ValueError('Modified installed code: nothing removed')
    plan = {'remove': result['owned'] + [RECEIPT], 'preserve': ['wad/cfg.json', 'all unowned files', 'all GP user/system profiles'], 'executed': False}
    if not execute: return plan
    # Re-read all ownership/hashes before removing anything. Never recurse over the installation.
    again = detect(root)
    if not again['healthy'] or again['owned'] != result['owned']: raise ValueError('Installation changed during preparation')
    with mutation_guard():
        check_local_states()
        fence = root / '.pesto-update.lock'
        with fence.open('xb') as stream:
            stream.write(b'{"Stage":"ManagedUninstall"}')
            stream.flush(); os.fsync(stream.fileno())
        _fsync_directory(root)
        try:
            for relative in plan['remove']:
                target = safe_file(root, relative)
                target.unlink(); _fsync_directory(target.parent)
        except BaseException:
            # Keep the fence after a partial removal; never claim a complete uninstall.
            raise
        else:
            fence.unlink()
            _fsync_directory(root)
    plan['executed'] = True
    return plan


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('install','detect','uninstall'));p.add_argument('--destination',type=Path,required=True);p.add_argument('--source',type=Path);p.add_argument('--execute',action='store_true')
    a=p.parse_args()
    if a.action=='install':
        if not a.source: p.error('--source required')
        if not a.execute: result={'action':'install','execute':False,'destinationMustBeNew':True}
        else: result=install(a.source,a.destination)
    elif a.action=='detect': result=detect(a.destination)
    else: result=uninstall(a.destination,a.execute)
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 1 if a.action=='detect' and not result.get('healthy') else 0

if __name__=='__main__': raise SystemExit(main())
