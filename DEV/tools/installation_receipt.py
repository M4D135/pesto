"""Closed ownership contract shared by managed install and durable code updates.

This is installation metadata, never an operation receipt. An absent receipt
does not adopt a portable installation. Hashes establish local consistency,
not publisher authenticity.
"""
import json
from pathlib import Path
import re

from package_distribution import PROD_HELPERS
from refresh_manifest import safe_file, file_hash, _is_link_or_junction

RECEIPT = 'pesto-installation.json'
RECEIPT_LIMIT = 262144
PRESERVED = ['wad/cfg.json', 'GP profiles, preferences, logs, receipts and credentials']


def ownership_paths(runtime):
    return set(runtime) | {'wad/package.json'} | set(PROD_HELPERS)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate installation receipt field')
        result[key] = value
    return result


def load_receipt(root, runtime, *, required=False, version=None):
    root = Path(root)
    target = root / RECEIPT
    if _is_link_or_junction(target):
        raise ValueError('Linked installation receipt refused')
    if not target.exists():
        if required:
            raise ValueError('Installation ownership receipt is missing')
        return None
    target = safe_file(root, RECEIPT)
    with target.open('rb') as stream:
        data = stream.read(RECEIPT_LIMIT + 1)
    if len(data) > RECEIPT_LIMIT:
        raise ValueError('Oversized install receipt')
    try:
        receipt = json.loads(data.decode('utf-8'), object_pairs_hook=_unique_object)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError('Unreadable installation receipt') from exc
    if (not isinstance(receipt, dict) or
            set(receipt) != {'schema', 'product', 'version', 'files', 'preserved'} or
            type(receipt['schema']) is not int or receipt['schema'] != 1 or
            receipt['product'] != 'Pesto' or not isinstance(receipt['version'], str) or
            not receipt['version'] or (version is not None and receipt['version'] != version) or
            receipt['preserved'] != PRESERVED or not isinstance(receipt['files'], dict) or
            set(receipt['files']) != ownership_paths(runtime)):
        raise ValueError('Invalid installation ownership')
    if any(not isinstance(digest, str) or not re.fullmatch(r'[a-f0-9]{64}', digest)
           for digest in receipt['files'].values()):
        raise ValueError('Invalid installation ownership hash')
    return receipt


def changed_owned_files(root, receipt):
    changed = []
    for path, digest in receipt['files'].items():
        try:
            matches = file_hash(safe_file(root, path)) == digest
        except (OSError, ValueError):
            # Missing, unreadable and linked files are unhealthy. Never follow a
            # rejected path or interpret an inspection failure as an intact file.
            matches = False
        if not matches:
            changed.append(path)
    return changed


def require_intact_receipt(root, runtime, *, required=False, version=None):
    receipt = load_receipt(root, runtime, required=required, version=version)
    if receipt is not None and changed_owned_files(root, receipt):
        raise ValueError('Modified managed installation: ownership hashes differ')
    return receipt


def make_receipt(root, runtime, version):
    return {'schema': 1, 'product': 'Pesto', 'version': version,
            'files': {path: file_hash(safe_file(root, path))
                      for path in sorted(ownership_paths(runtime))},
            'preserved': list(PRESERVED)}
