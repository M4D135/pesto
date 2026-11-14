"""Read-only check of a reviewed compiler profile; no installation or download."""
import argparse, json, shutil, subprocess
from pathlib import Path


def check(profile, lock=None):
    lock=Path(lock) if lock else Path(__file__).with_name('toolchain.lock.json')
    expected=json.loads(lock.read_text(encoding='utf-8'))['profiles'][profile]
    observed={}
    for key, command in (('clang','clang'),('lld','lld-link')):
        path=shutil.which(command)
        if not path: raise RuntimeError('Missing compiler: '+command)
        result=subprocess.run([path,'--version'],capture_output=True,text=True,check=True)
        observed[key]=(result.stdout or result.stderr).strip().splitlines()[0]
        if observed[key] != expected[key]: raise ValueError('Compiler differs from reviewed profile: '+key)
    return {'schema':1,'profile':profile,'versions':observed,'status':'MATCH','byteReproducibility':'NOT_INFERRED'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--profile',required=True);a=p.parse_args();print(json.dumps(check(a.profile),indent=2))
