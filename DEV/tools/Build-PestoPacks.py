"""Offline PROD/DEV pack creation. Does not modify an existing installation."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json
from package_distribution import build_archives
from refresh_manifest import verify_runtime
from prepare_dev import ensure_config, check_pack_config

def check_build_record(source):
    # The packed EXE must be the one described by the last build record (toolchain included).
    record=source/'tools/launcher/last-build.json'
    if not record.is_file(): return None
    data=json.loads(record.read_text(encoding='utf-8-sig'))
    actual=hashlib.sha256((source/'Pesto.exe').read_bytes()).hexdigest()
    if data.get('SHA256')!=actual: raise ValueError('Pesto.exe does not match tools/launcher/last-build.json: rebuild, then refresh the manifest.')
    return {'Clang':data.get('Clang'),'Lld':data.get('Lld'),'SHA256':actual}

def build(source, output, allow_config=False):
    source=Path(source).resolve(strict=True); output=Path(output).absolute()
    if output.exists() or output.is_symlink(): raise FileExistsError('Choose a new output directory.')
    output=output.resolve(strict=False)
    if output==source or source in output.parents: raise ValueError('Output must be outside the source.')
    # Fresh clone: wad/cfg.json is Git-ignored; create the non-configured model only when absent.
    ensure_config(source)
    config=check_pack_config(source, allow_config)
    manifest=verify_runtime(source)
    toolchain=check_build_record(source)
    build_archives(source, output, ('PROD','DEV'), allow_config)
    return {'Version': manifest['Version'], 'RuntimeFiles': len(manifest['Files']), 'Config': config, 'Build': toolchain, 'WindowsExecution': 'NOT_RUN'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1])
    p.add_argument('--output',type=Path)
    p.add_argument('--allow-config',action='store_true',help='Pack a wad/cfg.json that differs from the unconfigured template (deliberate).')
    a=p.parse_args();dest=a.output or a.source.parent/('Pesto_PACKS_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
    result=build(a.source,dest,a.allow_config);print(dest);print(result)
