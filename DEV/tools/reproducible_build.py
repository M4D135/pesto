"""Build twice in independent directories, then compare every closed runtime byte."""
import argparse, importlib.util, json
from pathlib import Path
from check_toolchain import check
from release_assurance import compare_builds

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--profile',required=True);p.add_argument('--powershell',required=True);a=p.parse_args()
    toolchain=check(a.profile)
    if a.output.exists() or a.output.is_symlink(): raise FileExistsError('New output required')
    a.output.mkdir(parents=True)
    spec=importlib.util.spec_from_file_location('production_builder',Path(__file__).with_name('Build-PestoProduction.py'));builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    for name in ('first','second'): builder.build(a.source/'wad',a.output/name,source=a.source,powershell=a.powershell)
    report=compare_builds(a.output/'first',a.output/'second');report['toolchain']=toolchain
    (a.output/'comparison.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    raise SystemExit(0 if report['identical'] else 1)
