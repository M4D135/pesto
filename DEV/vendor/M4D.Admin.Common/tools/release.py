"""Offline verified common bundle and consumer locks. No consumer is modified."""
import argparse, hashlib, json, re, shutil, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def version(text):
    if not re.fullmatch(r'\d+\.\d+\.\d+',text):raise ValueError('Stable three-part version required')
    return tuple(int(v) for v in text.split('.'))


def check_compatibility(baseline,current):
    missing={name:sorted(set(rows)-set(current.get(name,[]))) for name,rows in baseline.items()}
    missing={name:rows for name,rows in missing.items() if rows}
    if missing:raise ValueError('Removed public API: '+json.dumps(missing))
    return {'compatible':True,'baselineMembers':sum(len(v) for v in baseline.values())}


def source_digest(root=ROOT):
    root=Path(root)
    paths=sorted([*root.glob('src/**/*.cs'),root/'version.json',root/'tools/build.ps1'])
    lines=[]
    for path in paths:
        if path.is_symlink() or not path.is_file():raise ValueError('Missing or linked canonical source')
        lines.append(path.relative_to(root).as_posix()+'\0'+hashlib.sha256(path.read_bytes()).hexdigest())
    return hashlib.sha256(('\n'.join(lines)+'\n').encode('utf-8')).hexdigest()


def bundle(source,output,consumers,minimum='0.1.1',allow_dirty=False):
    source=Path(source)
    if source.is_symlink():raise ValueError('Linked source refused')
    source=source.resolve(strict=True);output=Path(output).absolute()
    if output.exists() or output.is_symlink():raise FileExistsError('New output required')
    output=output.resolve(strict=False)
    if output==source or source in output.parents:raise ValueError('Output must be outside source')
    manifest=json.loads((source/'manifest.json').read_text(encoding='utf-8-sig'))
    if version(manifest['Version'])<version(minimum):raise ValueError('Common downgrade refused')
    if manifest.get('SourceSHA256')!=source_digest():raise ValueError('Stale dist: canonical source digest differs; rebuild before bundling')
    rows=[row for row in manifest['Files'] if '.Tests.' not in row['Name']]
    files={row['Name']:row for row in rows}
    if not files or len(files)!=len(rows):raise ValueError('Empty or duplicate runtime component')
    if not consumers:raise ValueError('At least one consumer required')
    for name,row in files.items():
        if not re.fullmatch(r'M4D\.Admin\.Common\.[A-Za-z]+\.dll',name):raise ValueError('Unexpected component')
        path=source/name
        if path.is_symlink() or not path.is_file() or path.stat().st_size!=row['Bytes'] or hashlib.sha256(path.read_bytes()).hexdigest()!=row['SHA256']:raise ValueError('Changed common component: '+name)
    identities={}
    for consumer,modules in consumers.items():
        if not re.fullmatch('[A-Za-z0-9_.-]+',consumer):raise ValueError('Invalid consumer')
        selected=['M4D.Admin.Common.'+module+'.dll' for module in modules]
        if len(set(selected))!=len(selected) or not selected or any(name not in files for name in selected):raise ValueError('Invalid consumer modules')
        lock={key:manifest[key] for key in ('Schema','Version','Repository','SourceSHA256','TargetFramework','LanguageVersion','Builder')}
        lock['Files']=[files[name] for name in selected]
        commit=subprocess.run(['git','-C',str(ROOT),'rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
        dirty=subprocess.run(['git','-C',str(ROOT),'status','--porcelain'],capture_output=True,text=True,check=True).stdout.strip()
        if dirty and not allow_dirty:raise ValueError('Dirty source: commit the reviewed common revision or explicitly use --allow-dirty for development')
        lock.update(SourceCommit=commit,SourceDirty=bool(dirty),Consumer=consumer)
        identities[consumer]=lock
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.m4d-release-',dir=output.parent) as temporary:
        stage=Path(temporary)
        for name in files:shutil.copyfile(source/name,stage/name)
        for consumer,lock in identities.items():(stage/(consumer+'.common.lock.json')).write_text(json.dumps(lock,indent=2)+'\n',encoding='utf-8')
        runtime_manifest=dict(manifest,Files=list(files.values()))
        (stage/'manifest.json').write_text(json.dumps(runtime_manifest,indent=2)+'\n',encoding='utf-8')
        output.mkdir()
        try:
            for path in stage.iterdir():shutil.copyfile(path,output/path.name)
        except BaseException:shutil.rmtree(output);raise
    return identities

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,default=ROOT/'dist');p.add_argument('--output',type=Path,required=True);p.add_argument('--consumer',action='append',required=True,help='NAME:Core,Query');p.add_argument('--minimum-version',default='0.1.1');p.add_argument('--allow-dirty',action='store_true');a=p.parse_args()
    consumers={}
    for entry in a.consumer:
        name,modules=entry.split(':',1)
        if name in consumers:raise ValueError('Duplicate consumer')
        consumers[name]=modules.split(',')
    print(json.dumps(bundle(a.source,a.output,consumers,a.minimum_version,a.allow_dirty),indent=2))
