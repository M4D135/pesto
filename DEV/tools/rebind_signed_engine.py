"""Rebind the generated module to already-signed Runtime bytes in a release COPY.
Never regenerate Runtime here. Does not execute PowerShell, sign or change trust.
"""
from pathlib import Path
import argparse,json,re
from refresh_manifest import safe_file,file_hash

PATTERN=re.compile(r"(\.Hash -ine ')[0-9a-fA-F]{64}(')")

def rebind(root):
    root=Path(root).resolve(strict=True)
    runtime=safe_file(root,'wad/Pesto.Engine.Runtime.ps1')
    module=safe_file(root,'wad/Pesto.Engine.psm1')
    metadata=safe_file(root,'wad/Pesto.Engine.build.json')
    text=module.read_bytes().decode('utf-8-sig')
    if '# SIG # Begin signature block' in text:raise ValueError('Module must be signed only after rebinding')
    if len(PATTERN.findall(text))!=1:raise ValueError('Expected exactly one reviewed runtime hash guard')
    data=json.loads(metadata.read_text(encoding='utf-8-sig'))
    if data.get('Schema')!=1 or not isinstance(data.get('RuntimeSHA256'),str):raise ValueError('Invalid engine metadata')
    digest=file_hash(runtime)
    replacement=PATTERN.sub(lambda m:m.group(1)+digest+m.group(2),text)
    data['RuntimeSHA256']=digest
    module.write_bytes(b'\xef\xbb\xbf'+replacement.encode('utf-8'))
    metadata.write_bytes(b'\xef\xbb\xbf'+(json.dumps(data,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
    return digest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);a=p.parse_args();print(rebind(a.root))
